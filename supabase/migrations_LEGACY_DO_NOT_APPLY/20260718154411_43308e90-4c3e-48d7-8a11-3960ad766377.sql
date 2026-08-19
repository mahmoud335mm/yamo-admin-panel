
DO $$ BEGIN
  CREATE TYPE public.pearl_price_kind AS ENUM ('buy_from_user','withdrawal','agent_buy','exchange_to_coins');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE public.pearl_price_status AS ENUM ('draft','published','paused','archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.pearl_price_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  kind public.pearl_price_kind NOT NULL,
  country_code TEXT,
  currency_code TEXT NOT NULL,
  min_user_level INT,
  max_user_level INT,
  min_agent_level INT,
  max_agent_level INT,
  min_vip INT,
  max_vip INT,
  agency_id UUID,
  min_amount BIGINT NOT NULL DEFAULT 0,
  max_amount BIGINT,
  base_unit_price NUMERIC(18,6) NOT NULL CHECK (base_unit_price >= 0),
  agent_commission_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  agency_commission_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  platform_commission_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  withdrawal_fee_fixed NUMERIC(18,4) NOT NULL DEFAULT 0,
  withdrawal_fee_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  priority INT NOT NULL DEFAULT 100,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  status public.pearl_price_status NOT NULL DEFAULT 'draft',
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_pearl_rules_lookup ON public.pearl_price_rules(kind, country_code, currency_code, status, priority);
GRANT SELECT, INSERT, UPDATE ON public.pearl_price_rules TO authenticated;
GRANT ALL ON public.pearl_price_rules TO service_role;
ALTER TABLE public.pearl_price_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pp_read" ON public.pearl_price_rules FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'pearl_prices.read'));
CREATE POLICY "pp_insert" ON public.pearl_price_rules FOR INSERT TO authenticated WITH CHECK (public.has_permission(auth.uid(),'pearl_prices.create'));
CREATE POLICY "pp_update" ON public.pearl_price_rules FOR UPDATE TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_prices.update')) WITH CHECK (public.has_permission(auth.uid(),'pearl_prices.update'));

CREATE TABLE IF NOT EXISTS public.pearl_price_tiers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id UUID NOT NULL REFERENCES public.pearl_price_rules(id) ON DELETE CASCADE,
  min_amount BIGINT NOT NULL,
  max_amount BIGINT,
  unit_price NUMERIC(18,6) NOT NULL,
  bonus_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  discount_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pp_tiers_rule ON public.pearl_price_tiers(rule_id, min_amount);
GRANT SELECT, INSERT, UPDATE ON public.pearl_price_tiers TO authenticated;
GRANT ALL ON public.pearl_price_tiers TO service_role;
ALTER TABLE public.pearl_price_tiers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pp_tiers_read" ON public.pearl_price_tiers FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'pearl_prices.read'));
CREATE POLICY "pp_tiers_write" ON public.pearl_price_tiers FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_prices.update')) WITH CHECK (public.has_permission(auth.uid(),'pearl_prices.update'));

CREATE TABLE IF NOT EXISTS public.pearl_price_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id UUID NOT NULL REFERENCES public.pearl_price_rules(id) ON DELETE CASCADE,
  version INT NOT NULL,
  snapshot JSONB NOT NULL,
  change_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  UNIQUE (rule_id, version)
);
GRANT SELECT, INSERT ON public.pearl_price_versions TO authenticated;
GRANT ALL ON public.pearl_price_versions TO service_role;
ALTER TABLE public.pearl_price_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pp_ver_read" ON public.pearl_price_versions FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'pearl_prices.read'));
CREATE POLICY "pp_ver_insert" ON public.pearl_price_versions FOR INSERT TO authenticated WITH CHECK (public.has_permission(auth.uid(),'pearl_prices.update'));
CREATE POLICY "pp_ver_no_update" ON public.pearl_price_versions AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "pp_ver_no_delete" ON public.pearl_price_versions AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

-- pearl_exchange_rates (distinct from pearl_coin_exchange_rates which is agent-specific)
CREATE TABLE IF NOT EXISTS public.pearl_exchange_rates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  country_code TEXT,
  currency_code TEXT NOT NULL,
  pearls_per_coin NUMERIC(18,6) NOT NULL CHECK (pearls_per_coin > 0),
  fee_pct NUMERIC(6,3) NOT NULL DEFAULT 0,
  min_pearls BIGINT NOT NULL DEFAULT 0,
  max_pearls BIGINT,
  priority INT NOT NULL DEFAULT 100,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  status public.pearl_price_status NOT NULL DEFAULT 'draft',
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_per_lookup ON public.pearl_exchange_rates(country_code, currency_code, status, priority);
GRANT SELECT, INSERT, UPDATE ON public.pearl_exchange_rates TO authenticated;
GRANT ALL ON public.pearl_exchange_rates TO service_role;
ALTER TABLE public.pearl_exchange_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "per_read" ON public.pearl_exchange_rates FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'pearl_prices.read'));
CREATE POLICY "per_write" ON public.pearl_exchange_rates FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_exchange_rates.manage'))
  WITH CHECK (public.has_permission(auth.uid(),'pearl_exchange_rates.manage'));

CREATE TRIGGER trg_pp_updated_at BEFORE UPDATE ON public.pearl_price_rules FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pp_tiers_updated_at BEFORE UPDATE ON public.pearl_price_tiers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_per_updated_at BEFORE UPDATE ON public.pearl_exchange_rates FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pp_audit AFTER INSERT OR UPDATE OR DELETE ON public.pearl_price_rules FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_per_audit AFTER INSERT OR UPDATE OR DELETE ON public.pearl_exchange_rates FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

CREATE OR REPLACE FUNCTION public.tg_pearl_version_snapshot()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='UPDATE' AND (OLD.base_unit_price IS DISTINCT FROM NEW.base_unit_price OR OLD.status IS DISTINCT FROM NEW.status) THEN
    NEW.version := OLD.version + 1;
    INSERT INTO public.pearl_price_versions(rule_id,version,snapshot,created_by) VALUES (OLD.id,OLD.version,to_jsonb(OLD),auth.uid());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_pp_versioning BEFORE UPDATE ON public.pearl_price_rules FOR EACH ROW EXECUTE FUNCTION public.tg_pearl_version_snapshot();

CREATE OR REPLACE FUNCTION public._resolve_pearl_rule(
  _kind public.pearl_price_kind, _country TEXT, _currency TEXT, _amount BIGINT, _user_id UUID
) RETURNS public.pearl_price_rules
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.pearl_price_rules; u_level INT; u_vip INT;
BEGIN
  IF _user_id IS NOT NULL THEN
    SELECT level, vip_level INTO u_level, u_vip FROM public.profiles WHERE id=_user_id;
  END IF;
  SELECT * INTO r FROM public.pearl_price_rules
  WHERE kind=_kind AND status='published' AND currency_code=_currency
    AND (country_code IS NULL OR country_code=_country)
    AND (starts_at IS NULL OR starts_at<=now())
    AND (ends_at IS NULL OR ends_at>now())
    AND (min_amount<=_amount) AND (max_amount IS NULL OR max_amount>=_amount)
    AND (min_user_level IS NULL OR u_level IS NULL OR u_level>=min_user_level)
    AND (max_user_level IS NULL OR u_level IS NULL OR u_level<=max_user_level)
    AND (min_vip IS NULL OR u_vip IS NULL OR u_vip>=min_vip)
    AND (max_vip IS NULL OR u_vip IS NULL OR u_vip<=max_vip)
  ORDER BY (country_code IS NOT NULL) DESC, priority ASC, created_at DESC LIMIT 1;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.resolve_pearl_purchase_price(
  _country TEXT, _currency TEXT, _pearls BIGINT, _user_id UUID DEFAULT NULL
) RETURNS TABLE(rule_id UUID, version INT, base NUMERIC, agent_commission NUMERIC, agency_commission NUMERIC, platform_commission NUMERIC, final_amount NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.pearl_price_rules; b NUMERIC; ac NUMERIC; agc NUMERIC; pc NUMERIC;
BEGIN
  r := public._resolve_pearl_rule('buy_from_user',_country,_currency,_pearls,_user_id);
  IF r.id IS NULL THEN RAISE EXCEPTION 'NO_PEARL_PURCHASE_RULE'; END IF;
  b := r.base_unit_price * _pearls;
  ac := b * r.agent_commission_pct / 100.0;
  agc := b * r.agency_commission_pct / 100.0;
  pc := b * r.platform_commission_pct / 100.0;
  RETURN QUERY SELECT r.id, r.version, b, ac, agc, pc, (b - ac - agc - pc);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_pearl_withdrawal_price(
  _country TEXT, _currency TEXT, _pearls BIGINT, _user_id UUID DEFAULT NULL
) RETURNS TABLE(rule_id UUID, version INT, base NUMERIC, fees NUMERIC, final_amount NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.pearl_price_rules; b NUMERIC; f NUMERIC;
BEGIN
  r := public._resolve_pearl_rule('withdrawal',_country,_currency,_pearls,_user_id);
  IF r.id IS NULL THEN RAISE EXCEPTION 'NO_PEARL_WITHDRAWAL_RULE'; END IF;
  b := r.base_unit_price * _pearls;
  f := r.withdrawal_fee_fixed + (b * r.withdrawal_fee_pct / 100.0);
  RETURN QUERY SELECT r.id, r.version, b, f, (b - f);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_pearl_to_coin_exchange_rate(
  _country TEXT, _currency TEXT, _pearls BIGINT
) RETURNS TABLE(rate_id UUID, version INT, coins BIGINT, fee_pct NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE er public.pearl_exchange_rates; c BIGINT;
BEGIN
  SELECT * INTO er FROM public.pearl_exchange_rates
  WHERE status='published' AND currency_code=_currency
    AND (country_code IS NULL OR country_code=_country)
    AND (starts_at IS NULL OR starts_at<=now())
    AND (ends_at IS NULL OR ends_at>now())
    AND min_pearls<=_pearls AND (max_pearls IS NULL OR max_pearls>=_pearls)
  ORDER BY (country_code IS NOT NULL) DESC, priority ASC LIMIT 1;
  IF er.id IS NULL THEN RAISE EXCEPTION 'NO_EXCHANGE_RATE'; END IF;
  c := FLOOR(_pearls / er.pearls_per_coin * (1 - er.fee_pct/100.0))::bigint;
  RETURN QUERY SELECT er.id, er.version, c, er.fee_pct;
END $$;

CREATE OR REPLACE FUNCTION public.publish_pearl_price_rule(_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('pearl_prices.publish');
  UPDATE public.pearl_price_rules SET status='published', updated_by=auth.uid() WHERE id=_id AND status IN ('draft','paused');
END $$;

CREATE OR REPLACE FUNCTION public.rollback_pearl_price_rule(_id UUID,_to_version INT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE snap JSONB;
BEGIN PERFORM public._require_perm('pearl_prices.rollback');
  SELECT snapshot INTO snap FROM public.pearl_price_versions WHERE rule_id=_id AND version=_to_version;
  IF snap IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  UPDATE public.pearl_price_rules SET
    base_unit_price=(snap->>'base_unit_price')::numeric,
    agent_commission_pct=(snap->>'agent_commission_pct')::numeric,
    agency_commission_pct=(snap->>'agency_commission_pct')::numeric,
    platform_commission_pct=(snap->>'platform_commission_pct')::numeric,
    withdrawal_fee_fixed=(snap->>'withdrawal_fee_fixed')::numeric,
    withdrawal_fee_pct=(snap->>'withdrawal_fee_pct')::numeric,
    updated_by=auth.uid() WHERE id=_id;
END $$;

INSERT INTO public.permissions(key, module, label_ar, label_en) VALUES
  ('pearl_prices.read','finance','قراءة أسعار اللؤلؤ','Read pearl prices'),
  ('pearl_prices.create','finance','إنشاء قواعد أسعار لؤلؤ','Create pearl price rules'),
  ('pearl_prices.update','finance','تعديل قواعد أسعار لؤلؤ','Update pearl price rules'),
  ('pearl_prices.publish','finance','نشر قواعد أسعار لؤلؤ','Publish pearl prices'),
  ('pearl_prices.rollback','finance','إرجاع نسخة سعر لؤلؤ','Rollback pearl price'),
  ('pearl_exchange_rates.manage','finance','إدارة أسعار تبديل اللؤلؤ','Manage pearl exchange rates')
ON CONFLICT (key) DO NOTHING;
