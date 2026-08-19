
DO $$ BEGIN CREATE TYPE public.payment_gateway_mode AS ENUM ('test','live'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.payment_gateway_status AS ENUM ('active','inactive','maintenance','deprecated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.payment_health_status AS ENUM ('healthy','degraded','down','unknown'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.payment_gateways (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  provider TEXT NOT NULL,
  logo_url TEXT,
  mode public.payment_gateway_mode NOT NULL DEFAULT 'test',
  supported_countries TEXT[] NOT NULL DEFAULT '{}',
  supported_currencies TEXT[] NOT NULL DEFAULT '{}',
  min_amount NUMERIC(18,4) NOT NULL DEFAULT 0,
  max_amount NUMERIC(18,4),
  fixed_fee NUMERIC(18,4) NOT NULL DEFAULT 0,
  percentage_fee NUMERIC(6,3) NOT NULL DEFAULT 0,
  callback_url TEXT,
  webhook_url TEXT,
  webhook_secret_ref TEXT,
  api_key_secret_ref TEXT,
  status public.payment_gateway_status NOT NULL DEFAULT 'inactive',
  priority INT NOT NULL DEFAULT 100,
  health_status public.payment_health_status NOT NULL DEFAULT 'unknown',
  last_health_check_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_gateways_status ON public.payment_gateways(status, priority);
GRANT SELECT, INSERT, UPDATE ON public.payment_gateways TO authenticated;
GRANT ALL ON public.payment_gateways TO service_role;
ALTER TABLE public.payment_gateways ENABLE ROW LEVEL SECURITY;
CREATE POLICY "gw_read" ON public.payment_gateways FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_gateways.read'));
CREATE POLICY "gw_insert" ON public.payment_gateways FOR INSERT TO authenticated WITH CHECK (public.has_permission(auth.uid(),'payment_gateways.create'));
CREATE POLICY "gw_update" ON public.payment_gateways FOR UPDATE TO authenticated
  USING (public.has_permission(auth.uid(),'payment_gateways.update'))
  WITH CHECK (public.has_permission(auth.uid(),'payment_gateways.update'));

CREATE TABLE IF NOT EXISTS public.payment_gateway_country_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway_id UUID NOT NULL REFERENCES public.payment_gateways(id) ON DELETE CASCADE,
  country_code TEXT NOT NULL,
  min_amount NUMERIC(18,4),
  max_amount NUMERIC(18,4),
  fixed_fee NUMERIC(18,4),
  percentage_fee NUMERIC(6,3),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (gateway_id, country_code)
);
GRANT SELECT, INSERT, UPDATE ON public.payment_gateway_country_configs TO authenticated;
GRANT ALL ON public.payment_gateway_country_configs TO service_role;
ALTER TABLE public.payment_gateway_country_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "gw_cc_read" ON public.payment_gateway_country_configs FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_gateways.read'));
CREATE POLICY "gw_cc_write" ON public.payment_gateway_country_configs FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'payment_gateways.update'))
  WITH CHECK (public.has_permission(auth.uid(),'payment_gateways.update'));

CREATE TABLE IF NOT EXISTS public.payment_gateway_currencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway_id UUID NOT NULL REFERENCES public.payment_gateways(id) ON DELETE CASCADE,
  currency_code TEXT NOT NULL,
  exchange_rate NUMERIC(18,6),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (gateway_id, currency_code)
);
GRANT SELECT, INSERT, UPDATE ON public.payment_gateway_currencies TO authenticated;
GRANT ALL ON public.payment_gateway_currencies TO service_role;
ALTER TABLE public.payment_gateway_currencies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "gw_cur_read" ON public.payment_gateway_currencies FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_gateways.read'));
CREATE POLICY "gw_cur_write" ON public.payment_gateway_currencies FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'payment_gateways.update'))
  WITH CHECK (public.has_permission(auth.uid(),'payment_gateways.update'));

CREATE TABLE IF NOT EXISTS public.payment_webhooks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway_id UUID NOT NULL REFERENCES public.payment_gateways(id) ON DELETE CASCADE,
  external_id TEXT,
  event_type TEXT NOT NULL,
  signature TEXT,
  signature_valid BOOLEAN,
  raw_payload JSONB NOT NULL,
  processed BOOLEAN NOT NULL DEFAULT FALSE,
  processing_error TEXT,
  processed_at TIMESTAMPTZ,
  retry_count INT NOT NULL DEFAULT 0,
  idempotency_key TEXT UNIQUE,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_webhooks_gateway ON public.payment_webhooks(gateway_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhooks_unprocessed ON public.payment_webhooks(processed, received_at) WHERE processed = FALSE;
GRANT SELECT ON public.payment_webhooks TO authenticated;
GRANT ALL ON public.payment_webhooks TO service_role;
ALTER TABLE public.payment_webhooks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wh_read" ON public.payment_webhooks FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_webhooks.read'));
-- No INSERT/UPDATE/DELETE from clients; only service_role via webhook receiver

CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id UUID NOT NULL REFERENCES public.payment_webhooks(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  entity_type TEXT,
  entity_id TEXT,
  data JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wh_events_webhook ON public.payment_webhook_events(webhook_id);
GRANT SELECT ON public.payment_webhook_events TO authenticated;
GRANT ALL ON public.payment_webhook_events TO service_role;
ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wh_ev_read" ON public.payment_webhook_events FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_webhooks.read'));

CREATE TABLE IF NOT EXISTS public.payment_failures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway_id UUID REFERENCES public.payment_gateways(id) ON DELETE SET NULL,
  webhook_id UUID REFERENCES public.payment_webhooks(id) ON DELETE SET NULL,
  request_id UUID,
  failure_type TEXT NOT NULL,
  error_code TEXT,
  error_message TEXT,
  details JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pay_failures_gw ON public.payment_failures(gateway_id, created_at DESC);
GRANT SELECT ON public.payment_failures TO authenticated;
GRANT ALL ON public.payment_failures TO service_role;
ALTER TABLE public.payment_failures ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pay_fail_read" ON public.payment_failures FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'payment_webhooks.read'));

CREATE TRIGGER trg_gw_updated_at BEFORE UPDATE ON public.payment_gateways FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_gw_audit AFTER INSERT OR UPDATE OR DELETE ON public.payment_gateways FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_gw_cc_updated_at BEFORE UPDATE ON public.payment_gateway_country_configs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_gw_cur_updated_at BEFORE UPDATE ON public.payment_gateway_currencies FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.update_gateway_health(_id UUID, _status public.payment_health_status)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('payment_gateways.test');
  UPDATE public.payment_gateways SET health_status=_status, last_health_check_at=now(), updated_by=auth.uid() WHERE id=_id;
END $$;

CREATE OR REPLACE FUNCTION public.retry_payment_webhook(_webhook_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('payment_webhooks.retry');
  UPDATE public.payment_webhooks SET processed=FALSE, retry_count=retry_count+1, processing_error=NULL WHERE id=_webhook_id;
  PERFORM public._charge_audit('payment.webhook.retry','payment_webhooks',_webhook_id::text,'{}'::jsonb);
END $$;

INSERT INTO public.permissions(key, module, label_ar, label_en) VALUES
  ('payment_gateways.read','finance','قراءة بوابات الدفع','Read payment gateways'),
  ('payment_gateways.create','finance','إنشاء بوابة دفع','Create payment gateway'),
  ('payment_gateways.update','finance','تعديل بوابة دفع','Update payment gateway'),
  ('payment_gateways.test','finance','اختبار اتصال البوابة','Test gateway connection'),
  ('payment_webhooks.read','finance','قراءة سجل Webhooks','Read payment webhooks'),
  ('payment_webhooks.retry','finance','إعادة معالجة Webhook','Retry payment webhook')
ON CONFLICT (key) DO NOTHING;
