
DO $$ BEGIN
  CREATE TYPE public.coin_price_status AS ENUM ('draft','published','paused','archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.coin_price_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  country_code TEXT,
  currency_code TEXT NOT NULL,
  user_type TEXT,
  min_user_level INT,
  max_user_level INT,
  min_vip INT,
  max_vip INT,
  agency_id UUID,
  charging_agent_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  payment_gateway_id UUID,
  payment_method_id UUID,
  min_coin_amount BIGINT NOT NULL DEFAULT 0,
  max_coin_amount BIGINT,
  base_unit_price NUMERIC(18,6) NOT NULL CHECK (base_unit_price >= 0),
  buy_unit_price NUMERIC(18,6),
  discount_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  bonus_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  fixed_fee NUMERIC(18,4) NOT NULL DEFAULT 0,
  percentage_fee NUMERIC(6,3) NOT NULL DEFAULT 0,
  tax_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  priority INT NOT NULL DEFAULT 100,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  status public.coin_price_status NOT NULL DEFAULT 'draft',
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_coin_rules_lookup ON public.coin_price_rules(country_code, currency_code, status, priority);
CREATE INDEX IF NOT EXISTS idx_coin_rules_status ON public.coin_price_rules(status);

GRANT SELECT, INSERT, UPDATE ON public.coin_price_rules TO authenticated;
GRANT ALL ON public.coin_price_rules TO service_role;
ALTER TABLE public.coin_price_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "coin_rules_read" ON public.coin_price_rules FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'coin_prices.read'));
CREATE POLICY "coin_rules_insert" ON public.coin_price_rules FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(auth.uid(),'coin_prices.create'));
CREATE POLICY "coin_rules_update" ON public.coin_price_rules FOR UPDATE TO authenticated
  USING (public.has_permission(auth.uid(),'coin_prices.update'))
  WITH CHECK (public.has_permission(auth.uid(),'coin_prices.update'));

CREATE TABLE IF NOT EXISTS public.coin_price_tiers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id UUID NOT NULL REFERENCES public.coin_price_rules(id) ON DELETE CASCADE,
  min_amount BIGINT NOT NULL,
  max_amount BIGINT,
  unit_price NUMERIC(18,6) NOT NULL,
  bonus_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  discount_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_coin_tiers_rule ON public.coin_price_tiers(rule_id, min_amount);
GRANT SELECT, INSERT, UPDATE ON public.coin_price_tiers TO authenticated;
GRANT ALL ON public.coin_price_tiers TO service_role;
ALTER TABLE public.coin_price_tiers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "coin_tiers_read" ON public.coin_price_tiers FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'coin_prices.read'));
CREATE POLICY "coin_tiers_write" ON public.coin_price_tiers FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'coin_prices.update'))
  WITH CHECK (public.has_permission(auth.uid(),'coin_prices.update'));

CREATE TABLE IF NOT EXISTS public.coin_price_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id UUID NOT NULL REFERENCES public.coin_price_rules(id) ON DELETE CASCADE,
  version INT NOT NULL,
  snapshot JSONB NOT NULL,
  change_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  UNIQUE (rule_id, version)
);
GRANT SELECT, INSERT ON public.coin_price_versions TO authenticated;
GRANT ALL ON public.coin_price_versions TO service_role;
ALTER TABLE public.coin_price_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "coin_versions_read" ON public.coin_price_versions FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'coin_prices.read'));
CREATE POLICY "coin_versions_insert" ON public.coin_price_versions FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(auth.uid(),'coin_prices.update'));
CREATE POLICY "coin_versions_no_update" ON public.coin_price_versions AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "coin_versions_no_delete" ON public.coin_price_versions AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

CREATE TRIGGER trg_coin_rules_updated_at BEFORE UPDATE ON public.coin_price_rules FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_coin_tiers_updated_at BEFORE UPDATE ON public.coin_price_tiers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_coin_rules_audit AFTER INSERT OR UPDATE OR DELETE ON public.coin_price_rules FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

CREATE OR REPLACE FUNCTION public.tg_coin_price_version_snapshot()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='UPDATE' AND (
    OLD.base_unit_price IS DISTINCT FROM NEW.base_unit_price OR
    OLD.discount_pct IS DISTINCT FROM NEW.discount_pct OR
    OLD.bonus_pct IS DISTINCT FROM NEW.bonus_pct OR
    OLD.status IS DISTINCT FROM NEW.status
  ) THEN
    NEW.version := OLD.version + 1;
    INSERT INTO public.coin_price_versions(rule_id, version, snapshot, created_by)
    VALUES (OLD.id, OLD.version, to_jsonb(OLD), auth.uid());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_coin_rules_versioning BEFORE UPDATE ON public.coin_price_rules FOR EACH ROW EXECUTE FUNCTION public.tg_coin_price_version_snapshot();

-- Resolver RPC
CREATE OR REPLACE FUNCTION public.resolve_coin_price(
  _country TEXT, _currency TEXT, _coin_amount BIGINT,
  _user_id UUID DEFAULT NULL, _payment_gateway_id UUID DEFAULT NULL, _payment_method_id UUID DEFAULT NULL
) RETURNS TABLE(
  rule_id UUID, version INT, base_price NUMERIC, discount NUMERIC, bonus_coins BIGINT,
  fixed_fee NUMERIC, percentage_fee NUMERIC, tax NUMERIC, final_price NUMERIC
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD; t RECORD; unit NUMERIC; base NUMERIC; disc NUMERIC; bon BIGINT; fee_amt NUMERIC; tax_amt NUMERIC; total NUMERIC;
DECLARE u_level INT; u_vip INT;
BEGIN
  IF _user_id IS NOT NULL THEN
    SELECT level, vip_level INTO u_level, u_vip FROM public.profiles WHERE id=_user_id;
  END IF;

  SELECT * INTO r FROM public.coin_price_rules
  WHERE status='published'
    AND (country_code IS NULL OR country_code = _country)
    AND currency_code = _currency
    AND (starts_at IS NULL OR starts_at <= now())
    AND (ends_at IS NULL OR ends_at > now())
    AND (payment_gateway_id IS NULL OR payment_gateway_id = _payment_gateway_id)
    AND (payment_method_id IS NULL OR payment_method_id = _payment_method_id)
    AND (min_coin_amount IS NULL OR min_coin_amount <= _coin_amount)
    AND (max_coin_amount IS NULL OR max_coin_amount >= _coin_amount)
    AND (min_user_level IS NULL OR u_level IS NULL OR u_level >= min_user_level)
    AND (max_user_level IS NULL OR u_level IS NULL OR u_level <= max_user_level)
    AND (min_vip IS NULL OR u_vip IS NULL OR u_vip >= min_vip)
    AND (max_vip IS NULL OR u_vip IS NULL OR u_vip <= max_vip)
  ORDER BY
    (country_code IS NOT NULL) DESC,
    (payment_gateway_id IS NOT NULL) DESC,
    (payment_method_id IS NOT NULL) DESC,
    priority ASC,
    created_at DESC
  LIMIT 1;

  IF r.id IS NULL THEN RAISE EXCEPTION 'NO_MATCHING_PRICE_RULE'; END IF;

  unit := r.base_unit_price;
  SELECT * INTO t FROM public.coin_price_tiers
    WHERE rule_id=r.id AND min_amount <= _coin_amount AND (max_amount IS NULL OR max_amount >= _coin_amount)
    ORDER BY min_amount DESC LIMIT 1;
  IF t.id IS NOT NULL THEN unit := t.unit_price; END IF;

  base := unit * _coin_amount;
  disc := base * (r.discount_pct / 100.0);
  IF t.id IS NOT NULL AND t.discount_pct > 0 THEN disc := disc + base * (t.discount_pct / 100.0); END IF;
  bon := FLOOR(_coin_amount * ((r.bonus_pct + COALESCE(t.bonus_pct,0)) / 100.0))::bigint;
  fee_amt := r.fixed_fee + (base - disc) * (r.percentage_fee / 100.0);
  tax_amt := (base - disc + fee_amt) * (r.tax_pct / 100.0);
  total := base - disc + fee_amt + tax_amt;

  RETURN QUERY SELECT r.id, r.version, base, disc, bon, r.fixed_fee, r.percentage_fee, tax_amt, total;
END $$;

CREATE OR REPLACE FUNCTION public.publish_coin_price_rule(_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('coin_prices.publish');
  UPDATE public.coin_price_rules SET status='published', updated_by=auth.uid() WHERE id=_id AND status IN ('draft','paused');
END $$;

CREATE OR REPLACE FUNCTION public.pause_coin_price_rule(_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('coin_prices.update');
  UPDATE public.coin_price_rules SET status='paused', updated_by=auth.uid() WHERE id=_id AND status='published';
END $$;

CREATE OR REPLACE FUNCTION public.rollback_coin_price_rule(_id UUID,_to_version INT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE snap JSONB;
BEGIN PERFORM public._require_perm('coin_prices.rollback');
  SELECT snapshot INTO snap FROM public.coin_price_versions WHERE rule_id=_id AND version=_to_version;
  IF snap IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  UPDATE public.coin_price_rules SET
    base_unit_price=(snap->>'base_unit_price')::numeric,
    buy_unit_price=(snap->>'buy_unit_price')::numeric,
    discount_pct=(snap->>'discount_pct')::numeric,
    bonus_pct=(snap->>'bonus_pct')::numeric,
    fixed_fee=(snap->>'fixed_fee')::numeric,
    percentage_fee=(snap->>'percentage_fee')::numeric,
    tax_pct=(snap->>'tax_pct')::numeric,
    updated_by=auth.uid() WHERE id=_id;
END $$;

INSERT INTO public.permissions(key, module, label_ar, label_en) VALUES
  ('coin_prices.read','finance','قراءة أسعار الكوينز','Read coin prices'),
  ('coin_prices.create','finance','إنشاء قواعد أسعار كوينز','Create coin price rules'),
  ('coin_prices.update','finance','تعديل قواعد أسعار كوينز','Update coin price rules'),
  ('coin_prices.publish','finance','نشر قواعد أسعار','Publish coin price rules'),
  ('coin_prices.rollback','finance','إرجاع نسخة سعر','Rollback coin price')
ON CONFLICT (key) DO NOTHING;
