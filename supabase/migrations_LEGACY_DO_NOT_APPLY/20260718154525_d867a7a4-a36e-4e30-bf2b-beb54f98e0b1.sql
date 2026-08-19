
DO $$ BEGIN
  CREATE TYPE public.withdrawal_status AS ENUM ('submitted','reviewing','approved','paying','paid','confirmed','rejected','cancelled','disputed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'withdrawal_reserve';
EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'withdrawal_release';
EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'withdrawal_settle';
EXCEPTION WHEN others THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.withdrawal_methods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  payment_gateway_id UUID REFERENCES public.payment_gateways(id) ON DELETE SET NULL,
  country_code TEXT,
  currency_code TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  requires_manual_review BOOLEAN NOT NULL DEFAULT true,
  instructions TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.withdrawal_methods TO authenticated;
GRANT ALL ON public.withdrawal_methods TO service_role;
ALTER TABLE public.withdrawal_methods ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wm_read" ON public.withdrawal_methods FOR SELECT TO authenticated USING (is_active OR public.has_permission(auth.uid(),'withdrawal_settings.manage'));
CREATE POLICY "wm_write" ON public.withdrawal_methods FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'withdrawal_settings.manage')) WITH CHECK (public.has_permission(auth.uid(),'withdrawal_settings.manage'));

CREATE TABLE IF NOT EXISTS public.withdrawal_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  method_id UUID REFERENCES public.withdrawal_methods(id) ON DELETE CASCADE,
  country_code TEXT,
  currency_code TEXT NOT NULL,
  min_user_level INT,
  min_pearls BIGINT NOT NULL DEFAULT 0,
  max_pearls_per_request BIGINT,
  daily_max_pearls BIGINT,
  weekly_max_pearls BIGINT,
  monthly_max_pearls BIGINT,
  dual_review_threshold BIGINT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.withdrawal_limits TO authenticated;
GRANT ALL ON public.withdrawal_limits TO service_role;
ALTER TABLE public.withdrawal_limits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wl_read" ON public.withdrawal_limits FOR SELECT TO authenticated USING (is_active OR public.has_permission(auth.uid(),'withdrawal_settings.manage'));
CREATE POLICY "wl_write" ON public.withdrawal_limits FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'withdrawal_settings.manage')) WITH CHECK (public.has_permission(auth.uid(),'withdrawal_settings.manage'));

CREATE TABLE IF NOT EXISTS public.withdrawal_fees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  method_id UUID REFERENCES public.withdrawal_methods(id) ON DELETE CASCADE,
  country_code TEXT,
  currency_code TEXT NOT NULL,
  min_pearls BIGINT NOT NULL DEFAULT 0,
  max_pearls BIGINT,
  fixed_fee NUMERIC(18,4) NOT NULL DEFAULT 0,
  percentage_fee NUMERIC(6,3) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.withdrawal_fees TO authenticated;
GRANT ALL ON public.withdrawal_fees TO service_role;
ALTER TABLE public.withdrawal_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wf_read" ON public.withdrawal_fees FOR SELECT TO authenticated USING (is_active OR public.has_permission(auth.uid(),'withdrawal_settings.manage'));
CREATE POLICY "wf_write" ON public.withdrawal_fees FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'withdrawal_settings.manage')) WITH CHECK (public.has_permission(auth.uid(),'withdrawal_settings.manage'));

CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  method_id UUID REFERENCES public.withdrawal_methods(id) ON DELETE SET NULL,
  pearls_amount BIGINT NOT NULL CHECK (pearls_amount > 0),
  fee_amount NUMERIC(18,4) NOT NULL DEFAULT 0,
  net_amount NUMERIC(18,4) NOT NULL,
  currency_code TEXT NOT NULL,
  country_code TEXT,
  price_rule_id UUID REFERENCES public.pearl_price_rules(id) ON DELETE SET NULL,
  price_version INT,
  account_data JSONB NOT NULL DEFAULT '{}',
  status public.withdrawal_status NOT NULL DEFAULT 'submitted',
  requires_dual_review BOOLEAN NOT NULL DEFAULT false,
  approval_count INT NOT NULL DEFAULT 0,
  required_approvals INT NOT NULL DEFAULT 1,
  proof_url TEXT,
  external_reference TEXT,
  admin_notes TEXT,
  rejection_reason TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  confirmed_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wr_user ON public.withdrawal_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wr_status ON public.withdrawal_requests(status, created_at DESC);
GRANT SELECT, INSERT ON public.withdrawal_requests TO authenticated;
GRANT ALL ON public.withdrawal_requests TO service_role;
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wr_read" ON public.withdrawal_requests FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_permission(auth.uid(),'withdrawal_requests.read'));

CREATE TABLE IF NOT EXISTS public.withdrawal_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.withdrawal_requests(id) ON DELETE CASCADE,
  reviewer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  decision TEXT NOT NULL CHECK (decision IN ('approved','rejected','needs_info')),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (request_id, reviewer_id)
);
GRANT SELECT, INSERT ON public.withdrawal_reviews TO authenticated;
GRANT ALL ON public.withdrawal_reviews TO service_role;
ALTER TABLE public.withdrawal_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wrv_read" ON public.withdrawal_reviews FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'withdrawal_requests.read'));
CREATE POLICY "wrv_no_update" ON public.withdrawal_reviews AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "wrv_no_delete" ON public.withdrawal_reviews AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

CREATE TABLE IF NOT EXISTS public.withdrawal_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.withdrawal_requests(id) ON DELETE CASCADE,
  from_status public.withdrawal_status,
  to_status public.withdrawal_status NOT NULL,
  note TEXT,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.withdrawal_events TO authenticated;
GRANT ALL ON public.withdrawal_events TO service_role;
ALTER TABLE public.withdrawal_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "we_read" ON public.withdrawal_events FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'withdrawal_requests.read')
    OR EXISTS(SELECT 1 FROM public.withdrawal_requests r WHERE r.id=request_id AND r.user_id=auth.uid()));
CREATE POLICY "we_no_update" ON public.withdrawal_events AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "we_no_delete" ON public.withdrawal_events AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

CREATE TRIGGER trg_wm_updated_at BEFORE UPDATE ON public.withdrawal_methods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_wl_updated_at BEFORE UPDATE ON public.withdrawal_limits FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_wf_updated_at BEFORE UPDATE ON public.withdrawal_fees FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_wr_updated_at BEFORE UPDATE ON public.withdrawal_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_wr_audit AFTER INSERT OR UPDATE OR DELETE ON public.withdrawal_requests FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

CREATE OR REPLACE FUNCTION public.tg_wr_log_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    INSERT INTO public.withdrawal_events(request_id,to_status,actor_id) VALUES (NEW.id,NEW.status,auth.uid());
  ELSIF TG_OP='UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.withdrawal_events(request_id,from_status,to_status,actor_id) VALUES (NEW.id,OLD.status,NEW.status,auth.uid());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_wr_transition AFTER INSERT OR UPDATE ON public.withdrawal_requests FOR EACH ROW EXECUTE FUNCTION public.tg_wr_log_transition();

-- Create withdrawal request (user)
CREATE OR REPLACE FUNCTION public.request_withdrawal(
  _pearls BIGINT, _method_id UUID, _country TEXT, _currency TEXT, _account_data JSONB
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE new_id UUID; price RECORD; lim RECORD; dual BOOL := false; req_appr INT := 1; w_bal BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _pearls <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  SELECT * INTO lim FROM public.withdrawal_limits
    WHERE is_active AND currency_code=_currency AND (country_code IS NULL OR country_code=_country)
      AND (method_id IS NULL OR method_id=_method_id)
    ORDER BY (country_code IS NOT NULL) DESC LIMIT 1;
  IF lim.id IS NULL THEN RAISE EXCEPTION 'NO_LIMITS_CONFIG'; END IF;
  IF _pearls < lim.min_pearls THEN RAISE EXCEPTION 'BELOW_MIN: %', lim.min_pearls; END IF;
  IF lim.max_pearls_per_request IS NOT NULL AND _pearls > lim.max_pearls_per_request THEN RAISE EXCEPTION 'ABOVE_MAX'; END IF;
  IF lim.dual_review_threshold IS NOT NULL AND _pearls >= lim.dual_review_threshold THEN dual := true; req_appr := 2; END IF;

  SELECT balance INTO w_bal FROM public.wallets WHERE user_id=auth.uid() AND account='pearls'::wallet_account FOR UPDATE;
  IF w_bal IS NULL OR w_bal < _pearls THEN RAISE EXCEPTION 'INSUFFICIENT_PEARLS'; END IF;

  SELECT * INTO price FROM public.resolve_pearl_withdrawal_price(_country,_currency,_pearls,auth.uid());

  -- Reserve pearls (debit balance)
  PERFORM public._wallet_apply(auth.uid(),'pearls'::wallet_account, -_pearls, 'withdrawal_reserve'::ledger_reason,
    'WDR-RESERVE-'||gen_random_uuid()::text, jsonb_build_object('pearls',_pearls));

  INSERT INTO public.withdrawal_requests(user_id,method_id,pearls_amount,fee_amount,net_amount,currency_code,country_code,price_rule_id,price_version,account_data,requires_dual_review,required_approvals)
  VALUES (auth.uid(),_method_id,_pearls,price.fees,price.final_amount,_currency,_country,price.rule_id,price.version,COALESCE(_account_data,'{}'::jsonb),dual,req_appr)
  RETURNING id INTO new_id;
  RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION public.review_withdrawal(_request_id UUID, _decision TEXT, _note TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD; c INT;
BEGIN PERFORM public._require_perm('withdrawal_requests.review');
  IF _decision NOT IN ('approved','rejected','needs_info') THEN RAISE EXCEPTION 'INVALID_DECISION'; END IF;
  SELECT * INTO r FROM public.withdrawal_requests WHERE id=_request_id FOR UPDATE;
  IF r.id IS NULL OR r.status NOT IN ('submitted','reviewing') THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  INSERT INTO public.withdrawal_reviews(request_id, reviewer_id, decision, note) VALUES (_request_id, auth.uid(), _decision, _note);
  IF _decision='rejected' THEN
    -- release funds back
    PERFORM public._wallet_apply(r.user_id,'pearls'::wallet_account, r.pearls_amount, 'withdrawal_release'::ledger_reason,
      'WDR-RELEASE-'||r.id::text, jsonb_build_object('reason',_note));
    UPDATE public.withdrawal_requests SET status='rejected', rejected_at=now(), rejection_reason=_note WHERE id=_request_id;
    RETURN;
  END IF;
  IF _decision='approved' THEN
    SELECT COUNT(*) INTO c FROM public.withdrawal_reviews WHERE request_id=_request_id AND decision='approved';
    IF c >= r.required_approvals THEN
      UPDATE public.withdrawal_requests SET status='approved', approved_at=now(), approval_count=c WHERE id=_request_id;
    ELSE
      UPDATE public.withdrawal_requests SET status='reviewing', approval_count=c, reviewed_at=COALESCE(reviewed_at,now()) WHERE id=_request_id;
    END IF;
  ELSE
    UPDATE public.withdrawal_requests SET status='reviewing', reviewed_at=COALESCE(reviewed_at,now()) WHERE id=_request_id;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.mark_withdrawal_paid(_request_id UUID, _external_ref TEXT, _proof_url TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD;
BEGIN PERFORM public._require_perm('withdrawal_requests.pay');
  SELECT * INTO r FROM public.withdrawal_requests WHERE id=_request_id FOR UPDATE;
  IF r.id IS NULL OR r.status NOT IN ('approved','paying') THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  -- Settle: reserved pearls are now permanently spent (already debited on reserve)
  UPDATE public.withdrawal_requests SET status='paid', paid_at=now(), external_reference=_external_ref, proof_url=COALESCE(_proof_url,proof_url) WHERE id=_request_id;
END $$;

CREATE OR REPLACE FUNCTION public.confirm_withdrawal(_request_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.withdrawal_requests WHERE id=_request_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF r.user_id <> auth.uid() AND NOT public.has_permission(auth.uid(),'withdrawal_requests.pay') THEN RAISE EXCEPTION 'PERM_DENIED'; END IF;
  IF r.status <> 'paid' THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  -- Log final settle to ledger (accounting entry, no balance change since already debited)
  INSERT INTO public.wallet_ledger(wallet_id,user_id,account,direction,reason,amount,balance_after,reference,metadata,created_by)
  SELECT w.id,r.user_id,'pearls'::wallet_account,'debit'::ledger_direction,'withdrawal_settle'::ledger_reason,0,w.balance,'WDR-SETTLE-'||r.id::text,
    jsonb_build_object('request_id',r.id,'pearls',r.pearls_amount,'net',r.net_amount),auth.uid()
  FROM public.wallets w WHERE w.user_id=r.user_id AND w.account='pearls'::wallet_account;
  UPDATE public.withdrawal_requests SET status='confirmed', confirmed_at=now() WHERE id=_request_id;
END $$;

CREATE OR REPLACE FUNCTION public.cancel_withdrawal(_request_id UUID, _reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.withdrawal_requests WHERE id=_request_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF r.user_id <> auth.uid() AND NOT public.has_permission(auth.uid(),'withdrawal_requests.review') THEN RAISE EXCEPTION 'PERM_DENIED'; END IF;
  IF r.status NOT IN ('submitted','reviewing') THEN RAISE EXCEPTION 'CANNOT_CANCEL: %', r.status; END IF;
  PERFORM public._wallet_apply(r.user_id,'pearls'::wallet_account, r.pearls_amount, 'withdrawal_release'::ledger_reason,
    'WDR-CANCEL-'||r.id::text, jsonb_build_object('reason',_reason));
  UPDATE public.withdrawal_requests SET status='cancelled', rejection_reason=_reason WHERE id=_request_id;
END $$;

INSERT INTO public.permissions(key, module, label_ar, label_en) VALUES
  ('withdrawal_requests.read','finance','قراءة طلبات السحب','Read withdrawal requests'),
  ('withdrawal_requests.review','finance','مراجعة طلبات السحب','Review withdrawal requests'),
  ('withdrawal_requests.pay','finance','دفع طلبات السحب','Pay withdrawal requests'),
  ('withdrawal_settings.manage','finance','إدارة إعدادات السحب','Manage withdrawal settings')
ON CONFLICT (key) DO NOTHING;
