-- TEST PROJECT ONLY
-- DO NOT APPLY TO PRODUCTION
--
-- Phase 5D-2R baseline snapshot correction.
-- Replaces capture_5d2_baseline after the original test-only migration was
-- applied. The real wallet schema is row-based: account + balance, with
-- account labels coins / diamonds / bonus. There are no wallets.coins,
-- wallets.pearls, or wallets.bonus_coins columns.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.test_environment_marker WHERE environment_name = 'test') THEN
    RAISE EXCEPTION 'TEST_PROJECT_MARKER_MISSING: baseline snapshot v2 refused';
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
    (SELECT COUNT(*) FROM public.refund_receivables),
    (SELECT COUNT(*) FROM public.withdrawal_requests WHERE status = 'paid'),
    (SELECT COUNT(*) FROM public.wallet_adjustments),
    (SELECT COUNT(*) FROM public.refund_gateway_attempts),
    (SELECT jsonb_object_agg(key, value) FROM public.feature_flags)
  RETURNING id INTO _id;

  RETURN _id;
END $$;

REVOKE ALL ON FUNCTION public.capture_5d2_baseline(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.capture_5d2_baseline(text, text) TO service_role;