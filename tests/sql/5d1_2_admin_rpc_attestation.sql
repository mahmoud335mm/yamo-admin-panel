-- Phase 5D-1.2 — Admin RPC Attestation Static Assertions
-- Every SELECT should return zero rows unless labelled otherwise.

\echo '== T1: 0 PUBLIC EXECUTE on any SECDEF =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('public', p.oid,'EXECUTE');

\echo '== T2: 0 anon EXECUTE on any SECDEF =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('anon', p.oid,'EXECUTE');

\echo '== T3: every authenticated SECDEF is on the allowlist =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND has_function_privilege('authenticated', p.oid,'EXECUTE')
  AND NOT EXISTS (
    SELECT 1 FROM public.security_definer_public_allowlist a
    WHERE a.function_name = p.proname
      AND a.function_args = pg_get_function_identity_arguments(p.oid)
  );

\echo '== T4: every allowlist row has a decision and risk =='
SELECT function_name FROM public.security_definer_public_allowlist
WHERE decision IS NULL OR risk IS NULL;

\echo '== T5: every authenticated SECDEF has search_path pinned =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND has_function_privilege('authenticated', p.oid,'EXECUTE')
  AND (p.proconfig IS NULL OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%'));

\echo '== T6: no authenticated admin RPC accepts an actor-spoofing parameter =='
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND has_function_privilege('authenticated', p.oid,'EXECUTE')
  AND pg_get_function_identity_arguments(p.oid) ~* '(^|[, ])_?(actor|admin|performed_by|approved_by|executed_by|created_by|updated_by|staff)_id\b';

\echo '== T7: internal helpers (_/tg_/assert_) remain revoked from authenticated =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND (p.proname LIKE '\_%' ESCAPE '\' OR p.proname LIKE 'tg\_%' ESCAPE '\' OR p.proname LIKE 'assert\_%' ESCAPE '\')
  AND has_function_privilege('authenticated', p.oid,'EXECUTE');

\echo '== T8: legacy weak retry_payment_webhook(uuid) is gone =='
SELECT p.proname, pg_get_function_identity_arguments(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='retry_payment_webhook'
  AND pg_get_function_identity_arguments(p.oid) = '_webhook_id uuid';

\echo '== T9: CRITICAL wallet writers use _wallet_apply (which locks + blocks negative) =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('admin_credit_user_coins','admin_credit_user_pearls',
                    'admin_debit_user_coins','admin_debit_user_pearls','reverse_admin_wallet_adjustment')
  AND pg_get_functiondef(p.oid) !~* '(_wallet_apply|_admin_wallet_adjust)';

\echo '== T10: 5C refund feature flags still false =='
SELECT key,value FROM public.system_settings
WHERE key LIKE 'feature_flags.%refund%' AND value<>'false';

\echo '== T11: 5D dispute feature flags still false =='
SELECT key,value FROM public.system_settings
WHERE key IN ('feature_flags.enable_disputes_admin_ui','feature_flags.enable_user_dispute_submission',
              'feature_flags.enable_chargeback_processing','feature_flags.enable_dispute_financial_resolution',
              'feature_flags.enable_dispute_provisional_actions')
  AND value<>'false';

\echo '== T12: emergency_grant_super_admin refuses non-service_role callers (definition check) =='
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='emergency_grant_super_admin'
  AND pg_get_functiondef(p.oid) !~ 'EMERGENCY_ONLY';

\echo '== T13: summary counts =='
SELECT
  COUNT(*) FILTER (WHERE p.prosecdef) AS total_secdef,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('public', p.oid,'EXECUTE')) AS public_exec,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('anon', p.oid,'EXECUTE'))   AS anon_exec,
  COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('authenticated', p.oid,'EXECUTE')) AS authn_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public';
-- expected: total=201, public=0, anon=0, authn=160

\echo '== T14: allowlist coverage matches authenticated SECDEF count =='
SELECT
  (SELECT COUNT(*) FROM public.security_definer_public_allowlist) AS allowlist_rows,
  (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('authenticated', p.oid,'EXECUTE')) AS authn_secdef;
-- both should be 160
