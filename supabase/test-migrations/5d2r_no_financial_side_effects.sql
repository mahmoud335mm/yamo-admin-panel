-- TEST PROJECT ONLY
-- DO NOT APPLY TO PRODUCTION
--
-- Phase 5D-2R: assert_5d2_no_financial_side_effects(_test_run_id uuid)
-- Fails if any dispute lifecycle action produced a financial mutation.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.test_environment_marker WHERE environment_name = 'test') THEN
    RAISE EXCEPTION 'TEST_PROJECT_MARKER_MISSING: refusing to install assertion on non-test project';
  END IF;
END $$;

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

  -- 4. refunds executed (finance side)
  RETURN QUERY
  SELECT 'refund_executed'::text, to_jsonb(r.*)
  FROM public.recharge_refunds r
  WHERE r.metadata ->> 'test_run_id' = _test_run_id
    AND r.financial_resolution_status IS DISTINCT FROM NULL;

  -- 5. receivables
  RETURN QUERY
  SELECT 'receivable_created'::text, to_jsonb(rc.*)
  FROM public.refund_receivables rc
  WHERE rc.metadata ->> 'test_run_id' = _test_run_id;

  -- 6. withdrawal changes
  RETURN QUERY
  SELECT 'withdrawal_changed'::text, to_jsonb(w.*)
  FROM public.withdrawal_requests w
  WHERE w.metadata ->> 'test_run_id' = _test_run_id
    AND w.status IN ('paid', 'reversed');

  -- 7. wallet adjustments
  RETURN QUERY
  SELECT 'financial_adjustment_created'::text, to_jsonb(a.*)
  FROM public.wallet_adjustments a
  WHERE a.metadata ->> 'test_run_id' = _test_run_id;

  -- 8. gateway attempts
  RETURN QUERY
  SELECT 'gateway_attempt_created'::text, to_jsonb(g.*)
  FROM public.refund_gateway_attempts g
  WHERE g.metadata ->> 'test_run_id' = _test_run_id;

  RETURN;
END $$;

REVOKE ALL ON FUNCTION public.assert_5d2_no_financial_side_effects(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assert_5d2_no_financial_side_effects(text) TO service_role;
