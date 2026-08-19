-- Phase 5D-2 — Dispute Lifecycle Static Security Assertions
-- Every SELECT should return zero rows unless labelled otherwise.
\set ON_ERROR_STOP on

\echo '== T1: 0 PUBLIC EXECUTE on any SECDEF =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('public', p.oid,'EXECUTE');

\echo '== T2: 0 anon EXECUTE on any SECDEF =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('anon', p.oid,'EXECUTE');

\echo '== T3: every 5D-2 dispute wrapper is on the allowlist =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND p.proname IN (
    'create_recharge_dispute','assign_recharge_dispute','triage_recharge_dispute',
    'request_dispute_evidence','add_dispute_internal_note','add_dispute_user_visible_note',
    'redact_dispute_note','review_recharge_dispute','escalate_recharge_dispute',
    'first_decide_recharge_dispute','second_decide_recharge_dispute','resolve_recharge_dispute',
    'reject_recharge_dispute','cancel_recharge_dispute','close_recharge_dispute',
    'reopen_recharge_dispute','acknowledge_chargeback','mark_chargeback_evidence_due',
    'record_chargeback_recommendation','record_manual_chargeback_provider_status',
    'review_dispute_evidence','submit_dispute_evidence'
  )
  AND has_function_privilege('authenticated', p.oid,'EXECUTE')
  AND NOT EXISTS (
    SELECT 1 FROM public.security_definer_public_allowlist a
    WHERE a.function_name = p.proname
      AND a.function_args = pg_get_function_identity_arguments(p.oid)
  );

\echo '== T4: no dispute wrapper accepts actor-spoofing parameters =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND p.proname LIKE '%_recharge_dispute%'
  AND pg_get_function_identity_arguments(p.oid) ~* '(^|[, ])_?(actor|admin|performed_by|approved_by|executed_by|created_by|updated_by|staff)_id\b';

\echo '== T5: every dispute wrapper pins search_path =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND p.proname LIKE '%recharge_dispute%'
  AND (p.proconfig IS NULL OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%'));

\echo '== T6: dispute-scoped internal helpers stay revoked from authenticated =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND p.proname IN ('_dispute_assert_actor','_dispute_lock','_dispute_idem_lookup',
                    '_dispute_write_audit','_dispute_write_outbox','_dispute_snapshot_exposure',
                    'record_dispute_evidence_scan_result')
  AND has_function_privilege('authenticated', p.oid,'EXECUTE');

\echo '== T7: dispute feature flags remain false =='
SELECT key,value FROM public.system_settings
WHERE key IN ('feature_flags.enable_disputes_admin_ui','feature_flags.enable_user_dispute_submission',
              'feature_flags.enable_chargeback_processing','feature_flags.enable_dispute_financial_resolution',
              'feature_flags.enable_dispute_provisional_actions')
  AND value <> 'false';

\echo '== T8: 5C refund feature flags still false =='
SELECT key,value FROM public.system_settings
WHERE key LIKE 'feature_flags.%refund%' AND value <> 'false';

\echo '== T9: financial_resolution_status is never completed in schema defaults / seeds =='
SELECT id, financial_resolution_status FROM public.recharge_disputes
WHERE financial_resolution_status = 'completed';

\echo '== T10: T-FIN-FOLLOWUP-NO-NEW-CALLERS — the three financial follow-up RPCs have no new dispute callers =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname LIKE '%recharge_dispute%'
  AND pg_get_functiondef(p.oid) ~* '(admin_debit_user_coins|admin_debit_user_pearls|mark_withdrawal_paid)';

\echo '== T11: no dispute wrapper writes to wallet_ledger or system_ledger =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname LIKE '%recharge_dispute%'
  AND pg_get_functiondef(p.oid) ~* '(insert\s+into\s+public\.wallet_ledger|insert\s+into\s+public\.system_ledger|insert\s+into\s+wallet_ledger|insert\s+into\s+system_ledger)';

\echo '== T12: no dispute wrapper writes to wallets =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname LIKE '%recharge_dispute%'
  AND pg_get_functiondef(p.oid) ~* '(update\s+public\.wallets|update\s+wallets\s+set)';

\echo '== T13: RESTRICTIVE deny policies exist on the three dispute tables =='
SELECT tablename FROM pg_policies
WHERE schemaname='public' AND tablename IN ('recharge_disputes','recharge_dispute_notes','recharge_dispute_evidence')
  AND permissive='RESTRICTIVE'
GROUP BY tablename
HAVING COUNT(*) >= 1;
-- expected: three rows (one per table)

\echo '== T14: dispute_action_idempotency has unique (actor_id, action_type, idempotency_key) =='
SELECT conname FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
WHERE t.relname='dispute_action_idempotency' AND c.contype='u';

\echo '== T15: evidence rows default to quarantined + pending scan =='
SELECT column_name, column_default FROM information_schema.columns
WHERE table_schema='public' AND table_name='recharge_dispute_evidence'
  AND column_name IN ('is_quarantined','malware_scan_status')
  AND (column_default IS NULL
       OR (column_name='is_quarantined' AND column_default NOT LIKE 'true%')
       OR (column_name='malware_scan_status' AND column_default NOT LIKE '%pending%'));

\echo '== T16: summary counts =='
SELECT
  COUNT(*) FILTER (WHERE p.prosecdef) AS total_secdef,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('public', p.oid,'EXECUTE')) AS public_exec,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('anon', p.oid,'EXECUTE'))   AS anon_exec,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('authenticated', p.oid,'EXECUTE')) AS authn_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public';
