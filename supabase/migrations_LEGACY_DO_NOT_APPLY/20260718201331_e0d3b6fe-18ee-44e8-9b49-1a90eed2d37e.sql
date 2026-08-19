
INSERT INTO public.system_settings(key, value)
VALUES ('allow_mock_refund_gateway', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;

UPDATE public.system_settings SET value='false'::jsonb WHERE key='enable_mock_payment_gateway' AND value::text='true';
UPDATE public.system_settings SET value='false'::jsonb WHERE key='test_environment' AND value::text='true';

INSERT INTO public.permissions(key, module, label_ar, label_en, description)
VALUES ('system.manage_environment_flags', 'system', 'إدارة إعدادات البيئة', 'Manage environment flags', 'Toggle test_environment / enable_mock_payment_gateway / allow_mock_refund_gateway')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.assert_mock_refund_allowed(_gateway_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_is_prod boolean;
  v_test_env boolean;
  v_mock_enabled boolean;
  v_allow_refund boolean;
  v_gateway record;
BEGIN
  SELECT COALESCE((value)::text::boolean, false) INTO v_is_prod      FROM public.system_settings WHERE key='is_production';
  SELECT COALESCE((value)::text::boolean, false) INTO v_test_env     FROM public.system_settings WHERE key='test_environment';
  SELECT COALESCE((value)::text::boolean, false) INTO v_mock_enabled FROM public.system_settings WHERE key='enable_mock_payment_gateway';
  SELECT COALESCE((value)::text::boolean, false) INTO v_allow_refund FROM public.system_settings WHERE key='allow_mock_refund_gateway';

  IF v_is_prod          THEN RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: production environment'; END IF;
  IF NOT v_test_env     THEN RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: test_environment=false'; END IF;
  IF NOT v_mock_enabled THEN RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: enable_mock_payment_gateway=false'; END IF;
  IF NOT v_allow_refund THEN RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: allow_mock_refund_gateway=false'; END IF;

  IF _gateway_id IS NOT NULL THEN
    SELECT provider_type, mode, status INTO v_gateway FROM public.payment_gateways WHERE id=_gateway_id;
    IF NOT FOUND                          THEN RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: gateway not found'; END IF;
    IF v_gateway.provider_type <> 'mock'  THEN RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: provider_type=%', v_gateway.provider_type; END IF;
    IF v_gateway.mode::text <> 'test'     THEN RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: gateway mode=%', v_gateway.mode; END IF;
    IF v_gateway.status::text <> 'active' THEN RAISE EXCEPTION 'MOCK_GATEWAY_NOT_ALLOWED: gateway status=%', v_gateway.status; END IF;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_mock_refund_allowed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assert_mock_refund_allowed(uuid) TO authenticated, service_role;

ALTER TABLE public.recharge_refunds
  ADD COLUMN IF NOT EXISTS provider_idempotency_key text,
  ADD COLUMN IF NOT EXISTS execution_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS execution_owner_id uuid,
  ADD COLUMN IF NOT EXISTS preflight_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS gateway_mode public.payment_gateway_mode;

ALTER TABLE public.recharge_refund_attempts
  ADD COLUMN IF NOT EXISTS execution_token_hash text,
  ADD COLUMN IF NOT EXISTS provider_idempotency_key text,
  ADD COLUMN IF NOT EXISTS gateway_id uuid,
  ADD COLUMN IF NOT EXISTS gateway_mode public.payment_gateway_mode,
  ADD COLUMN IF NOT EXISTS request_correlation_id text,
  ADD COLUMN IF NOT EXISTS execution_owner_id uuid,
  ADD COLUMN IF NOT EXISTS finalized_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS ux_rref_attempts_gw_mode_provider_id
  ON public.recharge_refund_attempts(gateway_id, gateway_mode, provider_refund_id)
  WHERE provider_refund_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_rref_provider_idempotency
  ON public.recharge_refunds(provider_idempotency_key)
  WHERE provider_idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_rref_attempts_request_idem
  ON public.recharge_refund_attempts(refund_id, idempotency_key)
  WHERE trigger_type='execute' AND idempotency_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.prepare_refund_gateway_execution(
  _refund_id uuid, _reason text, _request_idempotency_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  actor uuid := auth.uid();
  rf public.recharge_refunds;
  rr public.recharge_requests;
  gw public.payment_gateways;
  existing public.recharge_refund_attempts;
  v_pre jsonb; v_snapshot jsonb;
  v_attempt_id uuid; v_attempt_number int;
  v_execution_token text; v_execution_token_hash text;
  v_provider_idem text; v_correlation text;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  IF NOT public.has_permission(actor, 'recharge_refunds.execute') THEN RAISE EXCEPTION 'FORBIDDEN: recharge_refunds.execute'; END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT'; END IF;
  IF _request_idempotency_key IS NULL OR length(_request_idempotency_key) < 8 THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_TOO_SHORT'; END IF;

  SELECT * INTO rf FROM public.recharge_refunds WHERE id=_refund_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;

  SELECT * INTO existing FROM public.recharge_refund_attempts
   WHERE refund_id=_refund_id AND trigger_type='execute' AND idempotency_key=_request_idempotency_key LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('idempotent_replay', true, 'attempt_id', existing.id,
      'attempt_status', existing.status, 'provider_refund_id', existing.provider_refund_id, 'refund_status', rf.status);
  END IF;

  IF rf.status <> 'approved' THEN RAISE EXCEPTION 'REFUND_NOT_EXECUTABLE: status=%', rf.status; END IF;
  IF rf.requires_second_approval AND rf.second_reviewed_by IS NULL THEN RAISE EXCEPTION 'SECOND_APPROVAL_REQUIRED'; END IF;
  IF rf.first_reviewed_by = actor OR rf.second_reviewed_by = actor OR rf.requested_by = actor THEN
    RAISE EXCEPTION 'SELF_EXECUTION_NOT_ALLOWED';
  END IF;

  SELECT * INTO rr FROM public.recharge_requests WHERE id=rf.request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORIGINAL_REQUEST_NOT_FOUND'; END IF;
  SELECT * INTO gw FROM public.payment_gateways WHERE id=rf.gateway_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'GATEWAY_NOT_FOUND'; END IF;
  IF gw.status::text <> 'active' THEN RAISE EXCEPTION 'GATEWAY_INACTIVE'; END IF;

  v_pre := public._refund_preflight_calc(rf.request_id, rf.refund_type, rf.refund_scope, rf.requested_amount);
  IF (v_pre->>'approved_amount')::numeric IS DISTINCT FROM rf.approved_amount THEN
    UPDATE public.recharge_refunds SET status='manual_review', failure_code='PREFLIGHT_DRIFT',
      failure_reason='Preflight drifted from snapshot', updated_at=now() WHERE id=rf.id;
    RAISE EXCEPTION 'PREFLIGHT_DRIFT';
  END IF;

  v_provider_idem := COALESCE(rf.provider_idempotency_key, 'refund:' || rf.refund_reference || ':gateway-refund');
  v_execution_token := encode(gen_random_bytes(32), 'hex');
  v_execution_token_hash := encode(digest(v_execution_token, 'sha256'), 'hex');
  v_correlation := encode(gen_random_bytes(12), 'hex');
  SELECT COALESCE(MAX(attempt_number),0)+1 INTO v_attempt_number FROM public.recharge_refund_attempts WHERE refund_id=rf.id;

  v_snapshot := jsonb_build_object(
    'refund_id', rf.id, 'refund_reference', rf.refund_reference, 'request_reference', rr.request_reference,
    'gateway_id', gw.id, 'gateway_code', gw.code, 'provider_type', gw.provider_type, 'gateway_mode', gw.mode,
    'original_payment_reference', rf.original_payment_reference, 'provider_payment_id', rr.provider_payment_id,
    'amount', rf.approved_amount, 'currency', rf.currency_code,
    'provider_idempotency_key', v_provider_idem, 'attempt_number', v_attempt_number);

  INSERT INTO public.recharge_refund_attempts(
    refund_id, attempt_number, trigger_type, status, idempotency_key, provider_idempotency_key,
    gateway_id, gateway_mode, execution_token_hash, request_correlation_id, execution_owner_id,
    started_at, triggered_by, reason
  ) VALUES (
    rf.id, v_attempt_number, 'execute', 'started', _request_idempotency_key, v_provider_idem,
    gw.id, gw.mode, v_execution_token_hash, v_correlation, actor, now(), actor, _reason
  ) RETURNING id INTO v_attempt_id;

  UPDATE public.recharge_refunds
     SET status='processing_gateway', provider_idempotency_key=v_provider_idem,
         execution_started_at=now(), execution_owner_id=actor,
         preflight_snapshot=v_snapshot, gateway_mode=gw.mode,
         executed_by=actor, updated_at=now()
   WHERE id=rf.id;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (actor, 'refund_gateway_execution_prepared', 'recharge_refund', rf.id,
    jsonb_build_object('attempt_id', v_attempt_id, 'attempt_number', v_attempt_number,
                       'gateway_id', gw.id, 'provider_type', gw.provider_type));

  RETURN jsonb_build_object('idempotent_replay', false, 'attempt_id', v_attempt_id,
    'execution_token', v_execution_token, 'provider_idempotency_key', v_provider_idem,
    'snapshot', v_snapshot, 'refund_status', 'processing_gateway');
END $$;

REVOKE EXECUTE ON FUNCTION public.prepare_refund_gateway_execution(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_refund_gateway_execution(uuid, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.finalize_refund_gateway_execution(
  _refund_id uuid, _attempt_id uuid, _execution_token text, _provider_refund_id text,
  _normalized_status text, _is_final boolean, _is_success boolean,
  _requires_webhook_confirmation boolean, _safe_error_code text, _safe_reference text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  rf public.recharge_refunds; at public.recharge_refund_attempts;
  v_token_hash text; v_new_attempt_status text; v_new_refund_status public.refund_status;
BEGIN
  IF _execution_token IS NULL OR length(_execution_token) < 32 THEN RAISE EXCEPTION 'EXECUTION_TOKEN_INVALID'; END IF;
  v_token_hash := encode(digest(_execution_token, 'sha256'), 'hex');
  SELECT * INTO rf FROM public.recharge_refunds WHERE id=_refund_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;
  SELECT * INTO at FROM public.recharge_refund_attempts WHERE id=_attempt_id FOR UPDATE;
  IF NOT FOUND OR at.refund_id <> rf.id THEN RAISE EXCEPTION 'ATTEMPT_INVALID'; END IF;
  IF at.execution_token_hash IS DISTINCT FROM v_token_hash THEN RAISE EXCEPTION 'EXECUTION_TOKEN_INVALID'; END IF;

  IF at.status IN ('succeeded','failed','pending','timeout') AND at.finalized_at IS NOT NULL THEN
    RETURN jsonb_build_object('idempotent', true, 'attempt_status', at.status, 'refund_status', rf.status);
  END IF;
  IF at.status <> 'started' THEN RAISE EXCEPTION 'ATTEMPT_STALE: status=%', at.status; END IF;
  IF rf.status <> 'processing_gateway' THEN RAISE EXCEPTION 'REFUND_NOT_PROCESSING: %', rf.status; END IF;

  IF _normalized_status = 'succeeded' AND _is_final AND NOT _requires_webhook_confirmation THEN
    v_new_attempt_status := 'succeeded'; v_new_refund_status := 'gateway_confirmed';
  ELSIF _normalized_status = 'succeeded' AND _requires_webhook_confirmation THEN
    v_new_attempt_status := 'pending'; v_new_refund_status := 'processing_gateway';
  ELSIF _normalized_status = 'pending' THEN
    v_new_attempt_status := 'pending'; v_new_refund_status := 'processing_gateway';
  ELSIF _normalized_status = 'failed' AND _is_final THEN
    v_new_attempt_status := 'failed'; v_new_refund_status := 'failed';
  ELSE
    v_new_attempt_status := 'pending'; v_new_refund_status := 'processing_gateway';
  END IF;

  UPDATE public.recharge_refund_attempts
     SET status=v_new_attempt_status,
         provider_refund_id=COALESCE(at.provider_refund_id, _provider_refund_id),
         failure_code=_safe_error_code, safe_error=_safe_reference,
         finished_at=now(), finalized_at=now()
   WHERE id=at.id;

  IF v_new_refund_status <> rf.status THEN
    UPDATE public.recharge_refunds
       SET status=v_new_refund_status,
           provider_refund_id=COALESCE(rf.provider_refund_id, _provider_refund_id),
           failure_code=CASE WHEN v_new_refund_status='failed' THEN _safe_error_code ELSE rf.failure_code END,
           updated_at=now()
     WHERE id=rf.id;
  ELSIF rf.provider_refund_id IS NULL AND _provider_refund_id IS NOT NULL THEN
    UPDATE public.recharge_refunds SET provider_refund_id=_provider_refund_id, updated_at=now() WHERE id=rf.id;
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (rf.execution_owner_id,
    CASE v_new_refund_status
      WHEN 'gateway_confirmed' THEN 'refund_gateway_confirmed'
      WHEN 'failed' THEN 'refund_gateway_failed'
      ELSE 'refund_gateway_pending' END,
    'recharge_refund', rf.id,
    jsonb_build_object('attempt_id', at.id, 'normalized_status', _normalized_status,
                       'is_final', _is_final, 'requires_webhook_confirmation', _requires_webhook_confirmation,
                       'safe_error_code', _safe_error_code));

  INSERT INTO public.transaction_message_outbox(event_type, transaction_type, transaction_id, safe_payload, idempotency_key)
  VALUES (
    CASE v_new_refund_status
      WHEN 'gateway_confirmed' THEN 'refund_gateway_confirmed'
      WHEN 'failed' THEN 'refund_gateway_failed'
      ELSE 'refund_gateway_pending' END,
    'recharge_refund', rf.id,
    jsonb_build_object('refund_reference', rf.refund_reference, 'amount', rf.approved_amount,
                       'currency', rf.currency_code, 'status', v_new_refund_status),
    'refund-finalize:' || rf.id::text || ':' || at.id::text)
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN jsonb_build_object('idempotent', false, 'attempt_status', v_new_attempt_status, 'refund_status', v_new_refund_status);
END $$;

REVOKE EXECUTE ON FUNCTION public.finalize_refund_gateway_execution(uuid, uuid, text, text, text, boolean, boolean, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_refund_gateway_execution(uuid, uuid, text, text, text, boolean, boolean, boolean, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_refund_gateway_execution(
  _refund_id uuid, _attempt_id uuid, _execution_token text, _failure_code text, _safe_error text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  rf public.recharge_refunds; at public.recharge_refund_attempts;
  v_token_hash text; v_attempt_status text; v_refund_next public.refund_status;
BEGIN
  v_token_hash := encode(digest(COALESCE(_execution_token,''), 'sha256'), 'hex');
  SELECT * INTO rf FROM public.recharge_refunds WHERE id=_refund_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;
  SELECT * INTO at FROM public.recharge_refund_attempts WHERE id=_attempt_id FOR UPDATE;
  IF NOT FOUND OR at.refund_id <> rf.id THEN RAISE EXCEPTION 'ATTEMPT_INVALID'; END IF;
  IF at.execution_token_hash IS DISTINCT FROM v_token_hash THEN RAISE EXCEPTION 'EXECUTION_TOKEN_INVALID'; END IF;
  IF at.status <> 'started' AND at.finalized_at IS NOT NULL THEN
    RETURN jsonb_build_object('idempotent', true, 'attempt_status', at.status);
  END IF;

  IF _failure_code IN ('GATEWAY_TIMEOUT_UNKNOWN_RESULT','PROVIDER_RESPONSE_INVALID') THEN
    v_attempt_status := 'timeout';
  ELSE
    v_attempt_status := 'failed';
  END IF;
  v_refund_next := 'manual_review';

  UPDATE public.recharge_refund_attempts
     SET status=v_attempt_status, failure_code=_failure_code, safe_error=_safe_error,
         finished_at=now(), finalized_at=now()
   WHERE id=at.id;

  IF rf.status='processing_gateway' AND v_refund_next <> rf.status THEN
    UPDATE public.recharge_refunds
       SET status=v_refund_next, failure_code=_failure_code, failure_reason=_safe_error, updated_at=now()
     WHERE id=rf.id;
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (rf.execution_owner_id,
    CASE WHEN v_attempt_status='timeout' THEN 'refund_gateway_timeout' ELSE 'refund_gateway_failed' END,
    'recharge_refund', rf.id,
    jsonb_build_object('attempt_id', at.id, 'failure_code', _failure_code));

  INSERT INTO public.transaction_message_outbox(event_type, transaction_type, transaction_id, safe_payload, idempotency_key)
  VALUES ('refund_gateway_status_unknown', 'recharge_refund', rf.id,
    jsonb_build_object('refund_reference', rf.refund_reference, 'status', v_refund_next, 'failure_code', _failure_code),
    'refund-fail:' || rf.id::text || ':' || at.id::text)
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN jsonb_build_object('idempotent', false, 'attempt_status', v_attempt_status, 'refund_status', v_refund_next);
END $$;

REVOKE EXECUTE ON FUNCTION public.fail_refund_gateway_execution(uuid, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_refund_gateway_execution(uuid, uuid, text, text, text) TO service_role;
