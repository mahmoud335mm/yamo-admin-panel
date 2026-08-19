
DO $$ BEGIN CREATE TYPE public.payment_method_type AS ENUM ('wallet','card','bank_transfer','mobile_money','qr','manual','crypto'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.payment_method_status AS ENUM ('active','disabled','maintenance'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.payment_methods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,
  method_type public.payment_method_type NOT NULL,
  country_code TEXT,
  currency_code TEXT NOT NULL,
  gateway_id UUID REFERENCES public.payment_gateways(id) ON DELETE SET NULL,
  logo_url TEXT,
  qr_url TEXT,
  instructions_ar TEXT,
  instructions_en TEXT,
  min_amount NUMERIC(18,4) NOT NULL DEFAULT 0,
  max_amount NUMERIC(18,4),
  fixed_fee NUMERIC(18,4) NOT NULL DEFAULT 0,
  percentage_fee NUMERIC(6,3) NOT NULL DEFAULT 0,
  sort_order INT NOT NULL DEFAULT 100,
  status public.payment_method_status NOT NULL DEFAULT 'active',
  for_recharge BOOLEAN NOT NULL DEFAULT TRUE,
  for_withdrawal BOOLEAN NOT NULL DEFAULT FALSE,
  for_users BOOLEAN NOT NULL DEFAULT TRUE,
  for_agents BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_pm_country ON public.payment_methods(country_code, status) WHERE status='active';
CREATE INDEX IF NOT EXISTS idx_pm_type ON public.payment_methods(method_type);
GRANT SELECT, INSERT, UPDATE ON public.payment_methods TO authenticated;
GRANT ALL ON public.payment_methods TO service_role;
ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pm_read" ON public.payment_methods FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_methods.read'));
CREATE POLICY "pm_insert" ON public.payment_methods FOR INSERT TO authenticated WITH CHECK (public.has_permission(auth.uid(),'payment_methods.create'));
CREATE POLICY "pm_update" ON public.payment_methods FOR UPDATE TO authenticated
  USING (public.has_permission(auth.uid(),'payment_methods.update'))
  WITH CHECK (public.has_permission(auth.uid(),'payment_methods.update'));

CREATE TABLE IF NOT EXISTS public.payment_method_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  method_id UUID NOT NULL REFERENCES public.payment_methods(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  account_number_masked TEXT,
  account_number_secret_ref TEXT,
  beneficiary_name_masked TEXT,
  beneficiary_name_secret_ref TEXT,
  bank_name TEXT,
  swift_code TEXT,
  iban_masked TEXT,
  iban_secret_ref TEXT,
  extra_data JSONB NOT NULL DEFAULT '{}',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_pma_method ON public.payment_method_accounts(method_id);
GRANT SELECT, INSERT, UPDATE ON public.payment_method_accounts TO authenticated;
GRANT ALL ON public.payment_method_accounts TO service_role;
ALTER TABLE public.payment_method_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pma_read" ON public.payment_method_accounts FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_methods.read'));
CREATE POLICY "pma_write" ON public.payment_method_accounts FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'payment_methods.update'))
  WITH CHECK (public.has_permission(auth.uid(),'payment_methods.update'));

CREATE TABLE IF NOT EXISTS public.payment_method_country_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  method_id UUID NOT NULL REFERENCES public.payment_methods(id) ON DELETE CASCADE,
  country_code TEXT NOT NULL,
  min_amount NUMERIC(18,4),
  max_amount NUMERIC(18,4),
  fixed_fee NUMERIC(18,4),
  percentage_fee NUMERIC(6,3),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (method_id, country_code)
);
GRANT SELECT, INSERT, UPDATE ON public.payment_method_country_rules TO authenticated;
GRANT ALL ON public.payment_method_country_rules TO service_role;
ALTER TABLE public.payment_method_country_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pmcr_read" ON public.payment_method_country_rules FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_methods.read'));
CREATE POLICY "pmcr_write" ON public.payment_method_country_rules FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'payment_methods.update'))
  WITH CHECK (public.has_permission(auth.uid(),'payment_methods.update'));

CREATE TABLE IF NOT EXISTS public.payment_method_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  method_id UUID NOT NULL REFERENCES public.payment_methods(id) ON DELETE CASCADE,
  scope TEXT NOT NULL,
  per_txn_min NUMERIC(18,4),
  per_txn_max NUMERIC(18,4),
  daily_max NUMERIC(18,4),
  weekly_max NUMERIC(18,4),
  monthly_max NUMERIC(18,4),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pml_method ON public.payment_method_limits(method_id);
GRANT SELECT, INSERT, UPDATE ON public.payment_method_limits TO authenticated;
GRANT ALL ON public.payment_method_limits TO service_role;
ALTER TABLE public.payment_method_limits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pml_read" ON public.payment_method_limits FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_methods.read'));
CREATE POLICY "pml_write" ON public.payment_method_limits FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'payment_methods.update'))
  WITH CHECK (public.has_permission(auth.uid(),'payment_methods.update'));

CREATE TRIGGER trg_pm_updated_at BEFORE UPDATE ON public.payment_methods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pm_audit AFTER INSERT OR UPDATE OR DELETE ON public.payment_methods FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_pma_updated_at BEFORE UPDATE ON public.payment_method_accounts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pmcr_updated_at BEFORE UPDATE ON public.payment_method_country_rules FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pml_updated_at BEFORE UPDATE ON public.payment_method_limits FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.get_available_payment_methods(
  _country TEXT, _currency TEXT, _op_type TEXT, _amount NUMERIC, _user_type TEXT DEFAULT 'user'
) RETURNS SETOF public.payment_methods
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT * FROM public.payment_methods
  WHERE status='active'
    AND (country_code IS NULL OR country_code=_country)
    AND currency_code=_currency
    AND ((_op_type='recharge' AND for_recharge) OR (_op_type='withdrawal' AND for_withdrawal))
    AND ((_user_type='agent' AND for_agents) OR (_user_type<>'agent' AND for_users))
    AND (min_amount <= _amount)
    AND (max_amount IS NULL OR max_amount >= _amount)
  ORDER BY sort_order ASC, name_ar ASC;
$$;

CREATE OR REPLACE FUNCTION public.disable_payment_method(_id UUID, _reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('payment_methods.disable');
  UPDATE public.payment_methods SET status='disabled', updated_by=auth.uid() WHERE id=_id;
  PERFORM public._charge_audit('payment_method.disable','payment_methods',_id::text, jsonb_build_object('reason',_reason));
END $$;

INSERT INTO public.permissions(key, module, label_ar, label_en) VALUES
  ('payment_methods.read','finance','قراءة وسائل الدفع','Read payment methods'),
  ('payment_methods.create','finance','إنشاء وسيلة دفع','Create payment method'),
  ('payment_methods.update','finance','تعديل وسيلة دفع','Update payment method'),
  ('payment_methods.disable','finance','تعطيل وسيلة دفع','Disable payment method'),
  ('payment_method_accounts.read_sensitive','finance','قراءة بيانات حساب حساسة','Read sensitive account data')
ON CONFLICT (key) DO NOTHING;
