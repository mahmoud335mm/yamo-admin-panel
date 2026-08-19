
DO $$ BEGIN
  CREATE TYPE public.recharge_request_status AS ENUM ('created','pending_payment','paid','verifying','completed','failed','cancelled','refunded','disputed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Extend ledger reason enum
DO $$ BEGIN
  ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'recharge_credit';
EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'recharge_bonus';
EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'recharge_refund';
EXCEPTION WHEN others THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.recharge_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  package_id UUID REFERENCES public.recharge_packages(id) ON DELETE SET NULL,
  coin_amount BIGINT NOT NULL CHECK (coin_amount >= 0),
  bonus_amount BIGINT NOT NULL DEFAULT 0 CHECK (bonus_amount >= 0),
  total_coins BIGINT NOT NULL,
  price NUMERIC(18,4) NOT NULL CHECK (price >= 0),
  currency_code TEXT NOT NULL,
  country_code TEXT,
  payment_gateway_id UUID REFERENCES public.payment_gateways(id) ON DELETE SET NULL,
  payment_method_id UUID REFERENCES public.payment_methods(id) ON DELETE SET NULL,
  external_reference TEXT,
  idempotency_key TEXT UNIQUE,
  status public.recharge_request_status NOT NULL DEFAULT 'created',
  receipt_url TEXT,
  failure_reason TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (payment_gateway_id, external_reference)
);
CREATE INDEX IF NOT EXISTS idx_rr_user ON public.recharge_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rr_status ON public.recharge_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rr_gateway ON public.recharge_requests(payment_gateway_id, created_at DESC);

GRANT SELECT ON public.recharge_requests TO authenticated;
GRANT ALL ON public.recharge_requests TO service_role;
ALTER TABLE public.recharge_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rr_read_own" ON public.recharge_requests FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_permission(auth.uid(),'recharge_requests.read'));

CREATE TABLE IF NOT EXISTS public.recharge_request_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.recharge_requests(id) ON DELETE CASCADE,
  from_status public.recharge_request_status,
  to_status public.recharge_request_status NOT NULL,
  note TEXT,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rre_request ON public.recharge_request_events(request_id, created_at);
GRANT SELECT ON public.recharge_request_events TO authenticated;
GRANT ALL ON public.recharge_request_events TO service_role;
ALTER TABLE public.recharge_request_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rre_read" ON public.recharge_request_events FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_requests.read')
    OR EXISTS(SELECT 1 FROM public.recharge_requests r WHERE r.id=request_id AND r.user_id=auth.uid()));
CREATE POLICY "rre_no_update" ON public.recharge_request_events AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "rre_no_delete" ON public.recharge_request_events AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

CREATE TABLE IF NOT EXISTS public.recharge_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.recharge_requests(id) ON DELETE CASCADE,
  receipt_number TEXT UNIQUE,
  receipt_url TEXT,
  uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.recharge_receipts TO authenticated;
GRANT ALL ON public.recharge_receipts TO service_role;
ALTER TABLE public.recharge_receipts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rrc_read" ON public.recharge_receipts FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_requests.read'));

CREATE TABLE IF NOT EXISTS public.recharge_refunds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.recharge_requests(id) ON DELETE RESTRICT,
  amount NUMERIC(18,4) NOT NULL,
  coins_reversed BIGINT NOT NULL DEFAULT 0,
  reason TEXT NOT NULL,
  processed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.recharge_refunds TO authenticated;
GRANT ALL ON public.recharge_refunds TO service_role;
ALTER TABLE public.recharge_refunds ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rref_read" ON public.recharge_refunds FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_requests.read'));
CREATE POLICY "rref_no_update" ON public.recharge_refunds AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "rref_no_delete" ON public.recharge_refunds AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

CREATE TABLE IF NOT EXISTS public.recharge_disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.recharge_requests(id) ON DELETE RESTRICT,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  resolution TEXT,
  opened_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.recharge_disputes TO authenticated;
GRANT ALL ON public.recharge_disputes TO service_role;
ALTER TABLE public.recharge_disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rdis_read" ON public.recharge_disputes FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_disputes.manage'));
CREATE POLICY "rdis_write" ON public.recharge_disputes FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_disputes.manage'))
  WITH CHECK (public.has_permission(auth.uid(),'recharge_disputes.manage'));

CREATE TRIGGER trg_rr_updated_at BEFORE UPDATE ON public.recharge_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_rr_audit AFTER INSERT OR UPDATE OR DELETE ON public.recharge_requests FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_rdis_updated_at BEFORE UPDATE ON public.recharge_disputes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Status transition logger
CREATE OR REPLACE FUNCTION public.tg_rr_log_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    INSERT INTO public.recharge_request_events(request_id,to_status,actor_id) VALUES (NEW.id,NEW.status,auth.uid());
  ELSIF TG_OP='UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.recharge_request_events(request_id,from_status,to_status,actor_id) VALUES (NEW.id,OLD.status,NEW.status,auth.uid());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_rr_transition AFTER INSERT OR UPDATE ON public.recharge_requests FOR EACH ROW EXECUTE FUNCTION public.tg_rr_log_transition();

-- Create request (user-facing)
CREATE OR REPLACE FUNCTION public.create_recharge_request(
  _package_id UUID, _coin_amount BIGINT, _bonus BIGINT, _price NUMERIC, _currency TEXT,
  _country TEXT, _gateway_id UUID, _method_id UUID, _idempotency_key TEXT
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE new_id UUID; existing UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _idempotency_key IS NOT NULL THEN
    SELECT id INTO existing FROM public.recharge_requests WHERE idempotency_key=_idempotency_key;
    IF existing IS NOT NULL THEN RETURN existing; END IF;
  END IF;
  INSERT INTO public.recharge_requests(user_id,package_id,coin_amount,bonus_amount,total_coins,price,currency_code,country_code,payment_gateway_id,payment_method_id,idempotency_key,status)
  VALUES (auth.uid(),_package_id,_coin_amount,COALESCE(_bonus,0),_coin_amount+COALESCE(_bonus,0),_price,_currency,_country,_gateway_id,_method_id,_idempotency_key,'pending_payment')
  RETURNING id INTO new_id;
  RETURN new_id;
END $$;

-- Complete request (only via webhook receiver — checks are enforced by caller)
CREATE OR REPLACE FUNCTION public.complete_recharge_request(_request_id UUID, _external_ref TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD;
BEGIN
  -- Restricted: only service_role (webhook) or explicit permission
  IF NOT (current_setting('role',true)='service_role' OR public.has_permission(auth.uid(),'recharge_requests.complete')) THEN
    RAISE EXCEPTION 'PERM_DENIED';
  END IF;
  SELECT * INTO r FROM public.recharge_requests WHERE id=_request_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF r.status = 'completed' THEN RETURN; END IF;
  IF r.status NOT IN ('pending_payment','paid','verifying') THEN RAISE EXCEPTION 'INVALID_STATE: %', r.status; END IF;

  PERFORM public._wallet_apply(r.user_id,'coins'::wallet_account, r.coin_amount, 'recharge_credit'::ledger_reason,
    'RECHARGE-'||r.id::text, jsonb_build_object('request_id',r.id,'external_ref',_external_ref));
  IF r.bonus_amount > 0 THEN
    PERFORM public._wallet_apply(r.user_id,'coins'::wallet_account, r.bonus_amount, 'recharge_bonus'::ledger_reason,
      'RECHARGE-BONUS-'||r.id::text, jsonb_build_object('request_id',r.id));
  END IF;

  UPDATE public.recharge_requests
    SET status='completed', external_reference=COALESCE(external_reference,_external_ref),
        paid_at=COALESCE(paid_at,now()), verified_at=COALESCE(verified_at,now()), completed_at=now()
    WHERE id=_request_id;

  IF r.package_id IS NOT NULL THEN
    INSERT INTO public.recharge_package_stats(package_id, purchases_count, revenue_amount)
    VALUES (r.package_id, 1, r.price)
    ON CONFLICT (package_id, stat_date) DO UPDATE SET
      purchases_count = public.recharge_package_stats.purchases_count + 1,
      revenue_amount = public.recharge_package_stats.revenue_amount + EXCLUDED.revenue_amount;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fail_recharge_request(_request_id UUID, _reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF NOT (current_setting('role',true)='service_role' OR public.has_permission(auth.uid(),'recharge_requests.review')) THEN RAISE EXCEPTION 'PERM_DENIED'; END IF;
  UPDATE public.recharge_requests SET status='failed', failed_at=now(), failure_reason=_reason
    WHERE id=_request_id AND status NOT IN ('completed','refunded');
END $$;

CREATE OR REPLACE FUNCTION public.refund_recharge_request(_request_id UUID, _reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD;
BEGIN PERFORM public._require_perm('recharge_requests.refund');
  IF _reason IS NULL OR length(_reason)<5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT * INTO r FROM public.recharge_requests WHERE id=_request_id FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'completed' THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  PERFORM public._wallet_apply(r.user_id,'coins'::wallet_account, -(r.coin_amount + r.bonus_amount),
    'recharge_refund'::ledger_reason, 'RECHARGE-REFUND-'||r.id::text, jsonb_build_object('reason',_reason));
  INSERT INTO public.recharge_refunds(request_id, amount, coins_reversed, reason, processed_by)
    VALUES (_request_id, r.price, r.coin_amount + r.bonus_amount, _reason, auth.uid());
  UPDATE public.recharge_requests SET status='refunded' WHERE id=_request_id;
END $$;

CREATE OR REPLACE FUNCTION public.open_recharge_dispute(_request_id UUID, _reason TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE new_id UUID;
BEGIN PERFORM public._require_perm('recharge_disputes.manage');
  INSERT INTO public.recharge_disputes(request_id, reason, opened_by) VALUES (_request_id,_reason,auth.uid()) RETURNING id INTO new_id;
  UPDATE public.recharge_requests SET status='disputed' WHERE id=_request_id;
  RETURN new_id;
END $$;

INSERT INTO public.permissions(key, module, label_ar, label_en) VALUES
  ('recharge_requests.read','finance','قراءة طلبات الشحن','Read recharge requests'),
  ('recharge_requests.review','finance','مراجعة طلبات الشحن','Review recharge requests'),
  ('recharge_requests.complete','finance','إكمال طلب شحن','Complete recharge request'),
  ('recharge_requests.refund','finance','استرداد طلب شحن','Refund recharge request'),
  ('recharge_disputes.manage','finance','إدارة نزاعات الشحن','Manage recharge disputes')
ON CONFLICT (key) DO NOTHING;
