-- Phase 5C-2b.4 — SQL security assertions for status refresh & retry
-- Run with: psql -v ON_ERROR_STOP=1 -f tests/sql/5c2b4_status_retry_security_assertions.sql

DO $$
DECLARE
  bad_grants integer;
  missing_perms integer;
  missing_columns integer;
  missing_indexes integer;
  missing_policy_count integer;
BEGIN
  -- 1) New RPCs have zero PUBLIC/anon/authenticated EXECUTE
  SELECT count(*) INTO bad_grants
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      '_lookup_refund_retry_policy',
      'claim_refund_status_refresh',
      'release_refund_status_refresh',
      'reclaim_stale_refund_status_checks',
      'prepare_refund_status_refresh',
      'finalize_refund_status_refresh',
      'prepare_refund_retry'
    )
    AND (
      has_function_privilege('anon',          p.oid, 'EXECUTE') OR
      has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );
  ASSERT bad_grants = 0, format('FAIL: %s new RPCs leak EXECUTE grants', bad_grants);

  -- 2) New permission keys exist
  SELECT 2 - count(*) INTO missing_perms
  FROM public.permissions
  WHERE key IN ('recharge_refunds.refresh_status', 'recharge_refunds.override_retry_limit');
  ASSERT missing_perms = 0, format('FAIL: %s new permission keys missing', missing_perms);

  -- 3) Polling / retry columns exist on recharge_refunds
  SELECT 9 - count(*) INTO missing_columns
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'recharge_refunds'
    AND column_name IN (
      'polling_owner','polling_started_at','polling_lease_expires_at',
      'last_status_checked_at','next_status_check_at','status_refresh_count',
      'retry_attempt_count','last_retry_at','gateway_execution_state'
    );
  ASSERT missing_columns = 0, format('FAIL: %s polling/retry columns missing', missing_columns);

  -- 4) refund_retry_policies partial unique indexes exist
  SELECT 4 - count(*) INTO missing_indexes
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND indexname IN (
      'ux_refund_retry_policy_global',
      'ux_refund_retry_policy_gw',
      'ux_refund_retry_policy_mode',
      'ux_refund_retry_policy_gw_mode'
    );
  ASSERT missing_indexes = 0, format('FAIL: %s retry-policy indexes missing', missing_indexes);

  -- 5) refund_retry_policies has RLS enabled and read/manage policies
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE relname = 'refund_retry_policies'),
    'FAIL: RLS not enabled on refund_retry_policies';
  SELECT 2 - count(*) INTO missing_policy_count
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'refund_retry_policies'
    AND policyname IN ('refund_retry_policies_read_admin', 'refund_retry_policies_manage_super');
  ASSERT missing_policy_count = 0, format('FAIL: %s refund_retry_policies policies missing', missing_policy_count);

  -- 6) A default global policy row is seeded
  ASSERT EXISTS (
    SELECT 1 FROM public.refund_retry_policies
    WHERE gateway_id IS NULL AND gateway_mode IS NULL AND active
  ), 'FAIL: default global retry policy missing';

  -- 7) Attempt table still has restrictive write policies
  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='recharge_refund_attempts'
      AND policyname='attempts_no_insert' AND permissive='RESTRICTIVE'
  ), 'FAIL: attempts_no_insert restrictive policy missing';

  RAISE NOTICE 'ALL 5C-2b.4 SECURITY ASSERTIONS PASSED';
END $$;
