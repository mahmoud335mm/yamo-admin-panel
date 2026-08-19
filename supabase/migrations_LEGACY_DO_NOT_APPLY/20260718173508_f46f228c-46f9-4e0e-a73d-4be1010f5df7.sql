
ALTER TYPE payment_health_status ADD VALUE IF NOT EXISTS 'misconfigured';

INSERT INTO public.permissions (key, module, label_ar, label_en, description) VALUES
  ('payment_gateways.enable',        'payments', 'تفعيل بوابة دفع',       'Enable gateway',   'تفعيل بوابة دفع'),
  ('payment_gateways.disable',       'payments', 'تعطيل بوابة دفع',       'Disable gateway',  'تعطيل بوابة دفع'),
  ('payment_gateways.change_mode',   'payments', 'تغيير Test/Live',       'Change mode',      'تغيير وضع البوابة'),
  ('payment_gateways.rotate_secret', 'payments', 'تدوير أسرار البوابة',    'Rotate secrets',   'تدوير أسرار البوابة'),
  ('payment_failures.read',          'payments', 'قراءة سجل الأعطال',      'Read failures',    'قراءة سجل أعطال الدفع'),
  ('payment_failures.resolve',       'payments', 'حل الأعطال',            'Resolve failures', 'حل أعطال الدفع')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions (role, permission_key)
SELECT 'super_admin'::admin_role, p.key FROM public.permissions p
WHERE p.key IN (
  'payment_gateways.enable','payment_gateways.disable','payment_gateways.change_mode',
  'payment_gateways.rotate_secret','payment_failures.read','payment_failures.resolve'
) ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.create_payment_gateway(
  _code text, _name text, _provider text, _mode payment_gateway_mode DEFAULT 'test',
  _logo_url text DEFAULT NULL, _countries text[] DEFAULT '{}', _currencies text[] DEFAULT '{}',
  _min_amount numeric DEFAULT 0, _max_amount numeric DEFAULT NULL,
  _fixed_fee numeric DEFAULT 0, _percentage_fee numeric DEFAULT 0,
  _priority integer DEFAULT 100, _callback_url text DEFAULT NULL, _webhook_url text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _id uuid; _uid uuid := auth.uid();
BEGIN
  IF NOT public.has_permission(_uid, 'payment_gateways.create') THEN
    RAISE EXCEPTION 'permission_denied: payment_gateways.create';
  END IF;
  INSERT INTO public.payment_gateways(
    code, name, provider, mode, logo_url, supported_countries, supported_currencies,
    min_amount, max_amount, fixed_fee, percentage_fee, priority, callback_url, webhook_url,
    status, health_status, created_by, updated_by
  ) VALUES (
    _code, _name, _provider, _mode, _logo_url, _countries, _currencies,
    _min_amount, _max_amount, _fixed_fee, _percentage_fee, _priority, _callback_url, _webhook_url,
    'inactive', 'unknown', _uid, _uid
  ) RETURNING id INTO _id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.create', 'payment_gateway', _id::text,
          jsonb_build_object('code', _code, 'mode', _mode));
  RETURN _id;
END $$;

CREATE OR REPLACE FUNCTION public.update_payment_gateway(_id uuid, _patch jsonb, _reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT public.has_permission(_uid, 'payment_gateways.update') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  UPDATE public.payment_gateways SET
    name                = COALESCE(_patch->>'name', name),
    provider            = COALESCE(_patch->>'provider', provider),
    logo_url            = COALESCE(_patch->>'logo_url', logo_url),
    supported_countries = COALESCE((SELECT array_agg(x) FROM jsonb_array_elements_text(_patch->'supported_countries') x), supported_countries),
    supported_currencies= COALESCE((SELECT array_agg(x) FROM jsonb_array_elements_text(_patch->'supported_currencies') x), supported_currencies),
    min_amount          = COALESCE((_patch->>'min_amount')::numeric, min_amount),
    max_amount          = CASE WHEN _patch ? 'max_amount' THEN NULLIF(_patch->>'max_amount','')::numeric ELSE max_amount END,
    fixed_fee           = COALESCE((_patch->>'fixed_fee')::numeric, fixed_fee),
    percentage_fee      = COALESCE((_patch->>'percentage_fee')::numeric, percentage_fee),
    priority            = COALESCE((_patch->>'priority')::int, priority),
    callback_url        = COALESCE(_patch->>'callback_url', callback_url),
    webhook_url         = COALESCE(_patch->>'webhook_url', webhook_url),
    updated_by          = _uid, updated_at = now()
  WHERE id = _id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.update', 'payment_gateway', _id::text, jsonb_build_object('reason', _reason));
END $$;

CREATE OR REPLACE FUNCTION public.enable_payment_gateway(_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF _reason IS NULL OR length(trim(_reason)) < 5 THEN RAISE EXCEPTION 'reason_required_min_5'; END IF;
  IF NOT public.has_permission(_uid, 'payment_gateways.enable') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  UPDATE public.payment_gateways SET status='active', updated_by=_uid, updated_at=now() WHERE id=_id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.enable', 'payment_gateway', _id::text, jsonb_build_object('reason', _reason));
END $$;

CREATE OR REPLACE FUNCTION public.disable_payment_gateway(_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF _reason IS NULL OR length(trim(_reason)) < 5 THEN RAISE EXCEPTION 'reason_required_min_5'; END IF;
  IF NOT public.has_permission(_uid, 'payment_gateways.disable') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  UPDATE public.payment_gateways SET status='inactive', updated_by=_uid, updated_at=now() WHERE id=_id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.disable', 'payment_gateway', _id::text, jsonb_build_object('reason', _reason));
END $$;

CREATE OR REPLACE FUNCTION public.change_payment_gateway_mode(_id uuid, _new_mode payment_gateway_mode, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid(); _g public.payment_gateways%rowtype;
BEGIN
  IF _reason IS NULL OR length(trim(_reason)) < 5 THEN RAISE EXCEPTION 'reason_required_min_5'; END IF;
  IF NOT public.has_permission(_uid, 'payment_gateways.change_mode') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT * INTO _g FROM public.payment_gateways WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'gateway_not_found'; END IF;
  IF _new_mode = 'live' THEN
    IF _g.webhook_secret_ref IS NULL OR length(_g.webhook_secret_ref)=0 THEN RAISE EXCEPTION 'live_requires_webhook_secret'; END IF;
    IF _g.api_key_secret_ref IS NULL OR length(_g.api_key_secret_ref)=0 THEN RAISE EXCEPTION 'live_requires_api_key_secret'; END IF;
    IF _g.webhook_url IS NULL OR length(_g.webhook_url)=0 THEN RAISE EXCEPTION 'live_requires_webhook_url'; END IF;
    IF coalesce(array_length(_g.supported_countries,1),0) = 0 THEN RAISE EXCEPTION 'live_requires_country'; END IF;
    IF coalesce(array_length(_g.supported_currencies,1),0) = 0 THEN RAISE EXCEPTION 'live_requires_currency'; END IF;
  END IF;
  UPDATE public.payment_gateways SET mode=_new_mode, updated_by=_uid, updated_at=now() WHERE id=_id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.change_mode', 'payment_gateway', _id::text,
          jsonb_build_object('from', _g.mode, 'to', _new_mode, 'reason', _reason));
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS payment_gateway_country_configs_unique ON public.payment_gateway_country_configs(gateway_id, country_code);
CREATE UNIQUE INDEX IF NOT EXISTS payment_gateway_currencies_unique ON public.payment_gateway_currencies(gateway_id, currency_code);

CREATE OR REPLACE FUNCTION public.update_gateway_country_config(
  _gateway_id uuid, _country_code text, _min_amount numeric, _max_amount numeric,
  _fixed_fee numeric, _percentage_fee numeric, _active boolean
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid;
BEGIN
  IF NOT public.has_permission(_uid, 'payment_gateways.update') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  INSERT INTO public.payment_gateway_country_configs(gateway_id, country_code, min_amount, max_amount, fixed_fee, percentage_fee, active)
  VALUES (_gateway_id, upper(_country_code), _min_amount, _max_amount, _fixed_fee, _percentage_fee, _active)
  ON CONFLICT (gateway_id, country_code) DO UPDATE SET
    min_amount=EXCLUDED.min_amount, max_amount=EXCLUDED.max_amount,
    fixed_fee=EXCLUDED.fixed_fee, percentage_fee=EXCLUDED.percentage_fee,
    active=EXCLUDED.active, updated_at=now()
  RETURNING id INTO _id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.country_config.upsert', 'payment_gateway', _gateway_id::text,
          jsonb_build_object('country', _country_code, 'active', _active));
  RETURN _id;
END $$;

CREATE OR REPLACE FUNCTION public.update_gateway_currency_config(
  _gateway_id uuid, _currency_code text, _exchange_rate numeric, _active boolean
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid;
BEGIN
  IF NOT public.has_permission(_uid, 'payment_gateways.update') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  INSERT INTO public.payment_gateway_currencies(gateway_id, currency_code, exchange_rate, active)
  VALUES (_gateway_id, upper(_currency_code), _exchange_rate, _active)
  ON CONFLICT (gateway_id, currency_code) DO UPDATE SET
    exchange_rate=EXCLUDED.exchange_rate, active=EXCLUDED.active, updated_at=now()
  RETURNING id INTO _id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.currency_config.upsert', 'payment_gateway', _gateway_id::text,
          jsonb_build_object('currency', _currency_code, 'active', _active));
  RETURN _id;
END $$;

CREATE OR REPLACE FUNCTION public.record_gateway_health_check(
  _id uuid, _new_status payment_health_status, _response_ms integer, _http_status integer, _error text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT public.has_permission(_uid, 'payment_gateways.test') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  UPDATE public.payment_gateways
     SET health_status=_new_status, last_health_check_at=now(),
         metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
           'last_health', jsonb_build_object('status', _new_status, 'response_ms', _response_ms, 'http_status', _http_status, 'error', _error, 'checked_at', now())
         )
   WHERE id=_id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.health_check', 'payment_gateway', _id::text,
          jsonb_build_object('status', _new_status, 'response_ms', _response_ms, 'http_status', _http_status));
END $$;

CREATE OR REPLACE FUNCTION public.mark_gateway_secret_configured(_id uuid, _secret_kind text, _ref text, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF _reason IS NULL OR length(trim(_reason)) < 5 THEN RAISE EXCEPTION 'reason_required_min_5'; END IF;
  IF NOT public.has_permission(_uid, 'payment_gateways.rotate_secret') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  IF _secret_kind NOT IN ('webhook','api_key') THEN RAISE EXCEPTION 'invalid_secret_kind'; END IF;
  IF _secret_kind = 'webhook' THEN
    UPDATE public.payment_gateways SET webhook_secret_ref=_ref, updated_by=_uid, updated_at=now() WHERE id=_id;
  ELSE
    UPDATE public.payment_gateways SET api_key_secret_ref=_ref, updated_by=_uid, updated_at=now() WHERE id=_id;
  END IF;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_gateway.secret_rotated', 'payment_gateway', _id::text,
          jsonb_build_object('kind', _secret_kind, 'reason', _reason));
END $$;

CREATE OR REPLACE FUNCTION public.resolve_payment_failure(_id uuid, _resolution_note text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF _resolution_note IS NULL OR length(trim(_resolution_note)) < 5 THEN RAISE EXCEPTION 'note_required_min_5'; END IF;
  IF NOT public.has_permission(_uid, 'payment_failures.resolve') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  UPDATE public.payment_failures
     SET details = coalesce(details,'{}'::jsonb) || jsonb_build_object(
       'resolved_by', _uid, 'resolved_at', now(), 'resolution_note', _resolution_note, 'status', 'resolved'
     )
   WHERE id=_id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_failure.resolve', 'payment_failure', _id::text,
          jsonb_build_object('note', _resolution_note));
END $$;

CREATE OR REPLACE VIEW public.payment_gateway_stats AS
SELECT
  g.id AS gateway_id,
  (SELECT count(*) FROM public.payment_webhooks w WHERE w.gateway_id=g.id AND w.processed) AS success_count,
  (SELECT count(*) FROM public.payment_webhooks w WHERE w.gateway_id=g.id AND w.processing_error IS NOT NULL) AS failure_count,
  (SELECT max(received_at) FROM public.payment_webhooks w WHERE w.gateway_id=g.id) AS last_webhook_at,
  (SELECT count(*) FROM public.payment_failures f WHERE f.gateway_id=g.id) AS total_failures
FROM public.payment_gateways g;

GRANT SELECT ON public.payment_gateway_stats TO authenticated;
