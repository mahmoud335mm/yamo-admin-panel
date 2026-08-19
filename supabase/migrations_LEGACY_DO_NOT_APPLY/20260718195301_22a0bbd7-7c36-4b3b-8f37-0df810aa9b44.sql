
ALTER TABLE public.wallet_ledger
  ADD COLUMN IF NOT EXISTS transaction_group_id uuid,
  ADD COLUMN IF NOT EXISTS refund_id uuid REFERENCES public.recharge_refunds(id),
  ADD COLUMN IF NOT EXISTS recharge_request_id uuid REFERENCES public.recharge_requests(id),
  ADD COLUMN IF NOT EXISTS ledger_side text CHECK (ledger_side IN ('user','system'));

CREATE INDEX IF NOT EXISTS wallet_ledger_txn_group_idx ON public.wallet_ledger(transaction_group_id);
CREATE INDEX IF NOT EXISTS wallet_ledger_refund_idx ON public.wallet_ledger(refund_id) WHERE refund_id IS NOT NULL;

ALTER TABLE public.system_ledger
  ADD COLUMN IF NOT EXISTS transaction_group_id uuid,
  ADD COLUMN IF NOT EXISTS refund_id uuid REFERENCES public.recharge_refunds(id),
  ADD COLUMN IF NOT EXISTS recharge_request_id uuid REFERENCES public.recharge_requests(id),
  ADD COLUMN IF NOT EXISTS ledger_side text DEFAULT 'system' CHECK (ledger_side IN ('user','system'));

CREATE INDEX IF NOT EXISTS system_ledger_txn_group_idx ON public.system_ledger(transaction_group_id);
CREATE INDEX IF NOT EXISTS system_ledger_refund_idx ON public.system_ledger(refund_id) WHERE refund_id IS NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='payment_gateways' AND column_name='provider_type'
  ) THEN
    ALTER TABLE public.payment_gateways
      ADD COLUMN provider_type text NOT NULL DEFAULT 'generic'
      CHECK (provider_type IN ('mock','generic','stripe','paypal','tap','myfatoorah','paymob','custom'));
  END IF;
END $$;

INSERT INTO public.system_settings(key, value) VALUES
  ('is_production', 'false'::jsonb),
  ('test_environment', 'true'::jsonb),
  ('enable_mock_payment_gateway', 'true'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.assert_mock_refund_allowed(_gateway_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_prod boolean;
  v_test_env boolean;
  v_mock_enabled boolean;
  v_gateway record;
BEGIN
  SELECT COALESCE((value)::text::boolean, false) INTO v_is_prod
    FROM public.system_settings WHERE key='is_production';
  SELECT COALESCE((value)::text::boolean, false) INTO v_test_env
    FROM public.system_settings WHERE key='test_environment';
  SELECT COALESCE((value)::text::boolean, false) INTO v_mock_enabled
    FROM public.system_settings WHERE key='enable_mock_payment_gateway';

  IF v_is_prod THEN
    RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: production environment';
  END IF;
  IF NOT v_test_env THEN
    RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: test_environment=false';
  END IF;
  IF NOT v_mock_enabled THEN
    RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: enable_mock_payment_gateway=false';
  END IF;

  IF _gateway_id IS NOT NULL THEN
    SELECT provider_type, mode INTO v_gateway
      FROM public.payment_gateways WHERE id = _gateway_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: gateway not found';
    END IF;
    IF v_gateway.provider_type <> 'mock' THEN
      RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: gateway provider_type=%', v_gateway.provider_type;
    END IF;
    IF v_gateway.mode::text <> 'test' THEN
      RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: gateway mode=%', v_gateway.mode;
    END IF;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_mock_refund_allowed(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_mock_refund_allowed(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.assert_mock_refund_allowed(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.assert_mock_refund_allowed(uuid) TO service_role;

CREATE TABLE IF NOT EXISTS public.recharge_refund_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_id uuid NOT NULL REFERENCES public.recharge_refunds(id) ON DELETE CASCADE,
  attempt_number integer NOT NULL,
  trigger_type text NOT NULL CHECK (trigger_type IN ('execute','retry','refresh_status','webhook')),
  provider_refund_id text,
  status text NOT NULL CHECK (status IN ('started','pending','succeeded','failed','duplicate','wrong_amount','wrong_currency','wrong_mode','unknown_payment','timeout','cancelled')),
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  failure_code text,
  safe_error text,
  idempotency_key text,
  triggered_by uuid REFERENCES public.admin_users(id),
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (refund_id, attempt_number)
);

GRANT SELECT ON public.recharge_refund_attempts TO authenticated;
GRANT ALL ON public.recharge_refund_attempts TO service_role;

ALTER TABLE public.recharge_refund_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "attempts_read_admin" ON public.recharge_refund_attempts
  FOR SELECT TO authenticated
  USING (has_permission(auth.uid(), 'recharge_refunds.read'));

CREATE POLICY "attempts_no_insert" ON public.recharge_refund_attempts
  AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY "attempts_no_update" ON public.recharge_refund_attempts
  AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "attempts_no_delete" ON public.recharge_refund_attempts
  AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

CREATE INDEX IF NOT EXISTS refund_attempts_refund_idx
  ON public.recharge_refund_attempts(refund_id, attempt_number DESC);

CREATE OR REPLACE FUNCTION public.assert_refund_ledger_pairing()
RETURNS TABLE(issue text, refund_id uuid, transaction_group_id uuid, details text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT 'user_without_system'::text, wl.refund_id, wl.transaction_group_id,
         format('wallet_ledger.id=%s account=%s amount=%s', wl.id, wl.account, wl.amount)
    FROM public.wallet_ledger wl
    LEFT JOIN public.system_ledger sl
      ON sl.transaction_group_id = wl.transaction_group_id
    WHERE wl.refund_id IS NOT NULL
      AND wl.transaction_group_id IS NOT NULL
      AND sl.id IS NULL
  UNION ALL
  SELECT 'system_without_user'::text, sl.refund_id, sl.transaction_group_id,
         format('system_ledger.id=%s asset=%s amount=%s', sl.id, sl.asset_class, sl.amount)
    FROM public.system_ledger sl
    LEFT JOIN public.wallet_ledger wl
      ON wl.transaction_group_id = sl.transaction_group_id
    WHERE sl.refund_id IS NOT NULL
      AND sl.transaction_group_id IS NOT NULL
      AND wl.id IS NULL
  UNION ALL
  SELECT 'debit_credit_mismatch'::text, refund_id, transaction_group_id,
         format('user_amount_sum=%s system_amount_sum=%s', user_sum, system_sum)
  FROM (
    SELECT
      COALESCE(wl.refund_id, sl.refund_id) as refund_id,
      COALESCE(wl.transaction_group_id, sl.transaction_group_id) as transaction_group_id,
      SUM(wl.amount) as user_sum,
      SUM(sl.amount) as system_sum
    FROM public.wallet_ledger wl
    FULL OUTER JOIN public.system_ledger sl
      ON sl.transaction_group_id = wl.transaction_group_id
    WHERE (wl.refund_id IS NOT NULL OR sl.refund_id IS NOT NULL)
    GROUP BY COALESCE(wl.refund_id, sl.refund_id),
             COALESCE(wl.transaction_group_id, sl.transaction_group_id)
  ) grp
  WHERE user_sum IS DISTINCT FROM system_sum;
$$;

REVOKE ALL ON FUNCTION public.assert_refund_ledger_pairing() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_refund_ledger_pairing() FROM anon;
GRANT EXECUTE ON FUNCTION public.assert_refund_ledger_pairing() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.assert_refund_completed_has_ledger()
RETURNS TABLE(refund_id uuid, refund_reference text, status text, missing text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT r.id, r.refund_reference, r.status::text,
         CASE
           WHEN NOT EXISTS (SELECT 1 FROM public.wallet_ledger wl WHERE wl.refund_id = r.id)
             THEN 'no_wallet_ledger'
           WHEN NOT EXISTS (SELECT 1 FROM public.system_ledger sl WHERE sl.refund_id = r.id)
             THEN 'no_system_ledger'
           ELSE 'ok'
         END as missing
    FROM public.recharge_refunds r
    WHERE r.status IN ('completed','partially_completed')
      AND (r.coins_actually_reversed > 0 OR r.bonus_actually_reversed > 0);
$$;

REVOKE ALL ON FUNCTION public.assert_refund_completed_has_ledger() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_refund_completed_has_ledger() FROM anon;
GRANT EXECUTE ON FUNCTION public.assert_refund_completed_has_ledger() TO authenticated, service_role;
