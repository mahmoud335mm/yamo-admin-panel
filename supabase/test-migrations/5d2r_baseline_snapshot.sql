-- TEST PROJECT ONLY
-- DO NOT APPLY TO PRODUCTION
--
-- Phase 5D-2R baseline snapshot helper.
-- Captures global finance/dispute totals plus a per-test-run marker so
-- specs can compare "financial state before" vs "after" for a given
-- test_run_id without being polluted by parallel test runs.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.test_environment_marker WHERE environment_name = 'test') THEN
    RAISE EXCEPTION 'TEST_PROJECT_MARKER_MISSING: baseline snapshot refused';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.test_baseline_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_run_id text NOT NULL,
  taken_at timestamptz NOT NULL DEFAULT now(),
  scope text NOT NULL CHECK (scope IN ('global', 'test_run')),
  wallet_count bigint,
  coins_total numeric,
  pearls_total numeric,
  bonus_total numeric,
  wallet_ledger_count bigint,
  system_ledger_count bigint,
  refunds_count bigint,
  receivables_count bigint,
  withdrawals_paid_count bigint,
  financial_adjustments_count bigint,
  gateway_attempts_count bigint,
  feature_flags jsonb,
  UNIQUE (test_run_id, scope, taken_at)
);

GRANT ALL ON public.test_baseline_snapshots TO service_role;
ALTER TABLE public.test_baseline_snapshots ENABLE ROW LEVEL SECURITY;

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
