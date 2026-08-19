-- Phase 5D-1.1 — Project-Wide Security Reconciliation Assertions
-- Every SELECT should return zero rows unless labelled otherwise.

\echo '== R1: project-wide PUBLIC EXECUTE on SECURITY DEFINER == expect 0 rows =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND has_function_privilege('public', p.oid, 'EXECUTE');

\echo '== R2: project-wide anon EXECUTE on SECURITY DEFINER == expect 0 rows =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE');

\echo '== R3: no internal helper (prefix _) callable by authenticated =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND p.proname LIKE '\_%' ESCAPE '\'
  AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

\echo '== R4: no trigger helper (prefix tg_) callable by authenticated =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND p.proname LIKE 'tg\_%' ESCAPE '\'
  AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

\echo '== R5: no integrity-assertion helper callable by authenticated =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND p.proname LIKE 'assert\_%' ESCAPE '\'
  AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

\echo '== R6: search_path pinned on every SECDEF function =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND (p.proconfig IS NULL
       OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%'));

\echo '== R7: chargeback provider identity completeness constraint present =='
SELECT conname FROM pg_constraint
WHERE conrelid='public.recharge_disputes'::regclass
  AND conname='chk_disputes_chargeback_identity_complete';
-- expect exactly one row

\echo '== R8: legacy_status_original column present on recharge_disputes =='
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='recharge_disputes'
  AND column_name='legacy_status_original';
-- expect exactly one row

\echo '== R9: 5C refund flags remain false =='
SELECT key, value FROM public.system_settings
WHERE key LIKE 'feature_flags.%refund%'
  AND value <> 'false';
-- expect 0 rows

\echo '== R10: 5D dispute flags remain false =='
SELECT key, value FROM public.system_settings
WHERE key IN (
  'feature_flags.enable_disputes_admin_ui',
  'feature_flags.enable_user_dispute_submission',
  'feature_flags.enable_chargeback_processing',
  'feature_flags.enable_dispute_financial_resolution',
  'feature_flags.enable_dispute_provisional_actions')
  AND value <> 'false';
-- expect 0 rows

\echo '== R11: chargeback completeness — insert without gateway_id must fail (expect error) =='
-- Manual runtime check; not executed inline to keep this file idempotent.

\echo '== R12: summary counts =='
SELECT
  COUNT(*) FILTER (WHERE p.prosecdef) AS total_secdef,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('public', p.oid, 'EXECUTE')) AS public_execute,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('anon', p.oid, 'EXECUTE')) AS anon_execute,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('authenticated', p.oid, 'EXECUTE')) AS authn_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public';
-- expected: total=202, public=0, anon=0, authn=161 (allowlisted admin RPCs)
