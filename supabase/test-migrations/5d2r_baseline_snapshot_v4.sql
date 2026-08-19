-- TEST PROJECT ONLY
-- DO NOT APPLY TO PRODUCTION
--
-- Phase 5D-2R baseline snapshot correction v4.
--
-- The isolated Test project schema does NOT include the
-- recharge_disputes column that earlier baseline versions assumed for
-- financial-resolution tracking. Baseline helpers must never depend on
-- that missing column, so this migration CREATE OR REPLACEs both:
--   - public.capture_5d2_baseline(text, text)
--   - public.assert_5d2_no_financial_side_effects(text)
--
-- The "refund_executed" invariant is derived from real columns present in
-- the isolated schema: recharge_refunds.executed_at IS NOT NULL. That is
-- the actual signal that a refund produced a financial side effect.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.test_environment_marker WHERE environment_name = 'test') THEN
    RAISE EXCEPTION 'TEST_PROJECT_MARKER_MISSING: baseline snapshot v4 refused';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.capture_5d2_baseline(_test_run_id text, _scope text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.test_environment_marker WHERE environment_name = 'test') THEN
    RAISE EXCEPTION 'TEST_PROJECT_MARKER_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'wallets' AND column_name = 'account'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'wallets' AND column_name = 'balance'
  ) THEN
    RAISE EXCEPTION 'WALLET_BASELINE_SCHEMA_MISMATCH';
  END IF;

  INSERT INTO public.test_baseline_snapshots (
    test_run_id, scope,
    wallet_count, coins_total, pearls_total, bonus_total,
    wallet_ledger_count, system_ledger_count,
    refunds_count, receivables_count,
    withdrawals_paid_count, financial_adjustments_count,
    gateway_attempts_count, feature_flags
  )
  SELECT
    _test_run_id, _scope,
    (SELECT COUNT(*) FROM public.wallets),
    (SELECT COALESCE(SUM(balance) FILTER (WHERE account = 'coins'::public.wallet_account), 0) FROM public.wallets),
    (SELECT COALESCE(SUM(balance) FILTER (WHERE account = 'diamonds'::public.wallet_account), 0) FROM public.wallets),
    (SELECT COALESCE(SUM(balance) FILTER (WHERE account = 'bonus'::public.wallet_account), 0) FROM public.wallets),
    (SELECT COUNT(*) FROM public.wallet_ledger),
    (SELECT COUNT(*) FROM public.system_ledger),
    (SELECT COUNT(*) FROM public.recharge_refunds),
    0,
    (SELECT COUNT(*) FROM public.withdrawal_requests WHERE status = 'paid'),
    (SELECT COUNT(*) FROM public.wallet_adjustment_requests),
    (SELECT COUNT(*) FROM public.recharge_refund_attempts),
    (SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb) FROM public.system_settings WHERE key LIKE 'feature_flags.%')
  RETURNING id INTO _id;

  RETURN _id;
END $$;

REVOKE ALL ON FUNCTION public.capture_5d2_baseline(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.capture_5d2_baseline(text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.assert_5d2_no_financial_side_effects(_test_run_id text)
RETURNS TABLE (violation text, details jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.test_environment_marker WHERE environment_name = 'test') THEN
    RAISE EXCEPTION 'TEST_PROJECT_MARKER_MISSING';
  END IF;

  -- 1. wallet_ledger entries tagged with this run
  RETURN QUERY
  SELECT 'wallet_ledger_entry_created'::text, to_jsonb(l.*)
  FROM public.wallet_ledger l
  WHERE l.metadata ->> 'test_run_id' = _test_run_id;

  -- 2. system_ledger entries
  RETURN QUERY
  SELECT 'system_ledger_entry_created'::text, to_jsonb(s.*)
  FROM public.system_ledger s
  WHERE s.metadata ->> 'test_run_id' = _test_run_id;

  -- 3. refunds created
  RETURN QUERY
  SELECT 'refund_created'::text, to_jsonb(r.*)
  FROM public.recharge_refunds r
  WHERE r.metadata ->> 'test_run_id' = _test_run_id;

  -- 4. refunds actually executed (real column: executed_at IS NOT NULL)
  RETURN QUERY
  SELECT 'refund_executed'::text, to_jsonb(r.*)
  FROM public.recharge_refunds r
  WHERE r.metadata ->> 'test_run_id' = _test_run_id
    AND r.executed_at IS NOT NULL;

  -- 5. withdrawal changes
  RETURN QUERY
  SELECT 'withdrawal_changed'::text, to_jsonb(w.*)
  FROM public.withdrawal_requests w
  WHERE w.metadata ->> 'test_run_id' = _test_run_id
    AND w.status IN ('paid', 'reversed');

  -- 6. wallet adjustment requests
  RETURN QUERY
  SELECT 'financial_adjustment_created'::text, to_jsonb(a.*)
  FROM public.wallet_adjustment_requests a
  WHERE COALESCE(a.idempotency_key, '') LIKE '%' || _test_run_id || '%'
     OR COALESCE(a.reason, '') LIKE '%' || _test_run_id || '%';

  -- 7. refund gateway attempts
  RETURN QUERY
  SELECT 'gateway_attempt_created'::text, to_jsonb(g.*)
  FROM public.recharge_refund_attempts g
  WHERE g.result ->> 'test_run_id' = _test_run_id
     OR COALESCE(g.idempotency_key, '') LIKE '%' || _test_run_id || '%';

  RETURN;
END $$;

REVOKE ALL ON FUNCTION public.assert_5d2_no_financial_side_effects(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assert_5d2_no_financial_side_effects(text) TO service_role;
