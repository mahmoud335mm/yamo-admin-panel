
-- ============================================================
-- 5B-3b Part 3 · Batch A
-- ============================================================

-- 1) Harden verify_recharge_payment: reject verified_webhook from any authenticated context.
--    Only service_role (no auth.uid) may pass verified_webhook.
--    mock_gateway only in test mode.
CREATE OR REPLACE FUNCTION public.verify_recharge_payment(_request_id uuid, _source text, _reason text, _idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  req record;
  wh  record;
  rcpt record;
  v_actor uuid;
BEGIN
  IF _source NOT IN ('verified_webhook','approved_manual_receipt','admin_retry','mock_gateway') THEN
    RAISE EXCEPTION 'INVALID_SOURCE';
  END IF;

  -- Source-based authorization (server enforced, never trusts client-passed source semantics)
  IF _source = 'admin_retry' THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
    IF NOT public.has_permission(auth.uid(),'recharge_requests.verify') THEN
      RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN
      RAISE EXCEPTION 'REASON_REQUIRED_MIN_5';
    END IF;
    v_actor := auth.uid();
  ELSIF _source = 'verified_webhook' THEN
    -- MUST come from service_role / internal webhook processor. Reject any authenticated call.
    IF auth.uid() IS NOT NULL THEN
      RAISE EXCEPTION 'UNTRUSTED_VERIFICATION_SOURCE';
    END IF;
    v_actor := NULL;
  ELSIF _source = 'mock_gateway' THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
    IF NOT public.has_permission(auth.uid(),'recharge_requests.verify') THEN
      RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    v_actor := auth.uid();
  ELSIF _source = 'approved_manual_receipt' THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
    IF NOT public.has_permission(auth.uid(),'recharge_requests.verify') THEN
      RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    v_actor := auth.uid();
  END IF;

  IF _idempotency_key IS NULL OR length(_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
  END IF;

  SELECT * INTO req FROM public.recharge_requests
   WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;

  IF req.status = 'completed' THEN
    RETURN jsonb_build_object('status','already_completed','request_id',_request_id);
  END IF;

  IF req.status = 'cancelled' THEN RAISE EXCEPTION 'REQUEST_CANCELLED'; END IF;
  IF req.status IN ('refunded','partially_refunded','refund_pending') THEN
    RAISE EXCEPTION 'REQUEST_REFUNDED';
  END IF;
  IF req.status IN ('reversed','chargeback') THEN
    RAISE EXCEPTION 'INVALID_STATE: %', req.status;
  END IF;

  IF req.expires_at IS NOT NULL AND req.expires_at < now() AND _source <> 'admin_retry' THEN
    RAISE EXCEPTION 'REQUEST_EXPIRED';
  END IF;

  IF req.status NOT IN ('paid','approved','verifying','manual_review','failed','payment_submitted') THEN
    RAISE EXCEPTION 'INVALID_STATE: %', req.status;
  END IF;

  -- Source-specific verification
  IF _source IN ('verified_webhook','mock_gateway') THEN
    SELECT * INTO wh
    FROM public.payment_webhooks
    WHERE related_request_id = _request_id
      AND processing_state IN ('processing','processed')
    ORDER BY received_at DESC
    LIMIT 1;

    IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_NOT_CONFIRMED'; END IF;

    IF _source = 'mock_gateway' THEN
      IF wh.gateway_mode <> 'test' THEN
        RAISE EXCEPTION 'GATEWAY_MODE_MISMATCH';
      END IF;
    ELSE
      IF wh.signature_valid IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'INVALID_SIGNATURE';
      END IF;
    END IF;

    IF wh.gateway_id <> req.payment_gateway_id THEN
      RAISE EXCEPTION 'GATEWAY_MISMATCH';
    END IF;
    IF wh.gateway_mode <> req.payment_gateway_mode THEN
      RAISE EXCEPTION 'GATEWAY_MODE_MISMATCH';
    END IF;
  ELSIF _source = 'approved_manual_receipt' THEN
    SELECT * INTO rcpt
    FROM public.recharge_receipts
    WHERE request_id = _request_id
      AND status = 'approved'
      AND reviewed_by IS NOT NULL
      AND reviewed_at IS NOT NULL
    ORDER BY reviewed_at DESC
    LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_APPROVED'; END IF;
  ELSIF _source = 'admin_retry' THEN
    -- admin override; still requires either an approved receipt OR a valid webhook
    IF NOT EXISTS (
      SELECT 1 FROM public.payment_webhooks
      WHERE related_request_id = _request_id
        AND signature_valid = true
        AND processing_state IN ('processing','processed')
    ) AND NOT EXISTS (
      SELECT 1 FROM public.recharge_receipts
      WHERE request_id = _request_id AND status = 'approved'
    ) THEN
      RAISE EXCEPTION 'PAYMENT_NOT_CONFIRMED';
    END IF;
  END IF;

  -- Delegate to _complete_internal for double-entry credit
  PERFORM public._complete_internal(_request_id, v_actor, _source, _idempotency_key);

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (v_actor, 'payment.verify.completed', 'recharge_request', _request_id::text,
          jsonb_build_object('source',_source,'reason',btrim(COALESCE(_reason,'')),'idempotency_key',_idempotency_key));

  RETURN jsonb_build_object('status','completed','request_id',_request_id,'source',_source);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.verify_recharge_payment(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_recharge_payment(uuid,text,text,text) TO authenticated, service_role;

-- 2) payment_webhook_attempts (historical, append-only)
CREATE TABLE IF NOT EXISTS public.payment_webhook_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id uuid NOT NULL REFERENCES public.payment_webhooks(id) ON DELETE CASCADE,
  attempt_number int NOT NULL,
  trigger_type text NOT NULL CHECK (trigger_type IN ('automatic','admin_retry','stale_recovery','initial_processing')),
  triggered_by uuid,
  reason text,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  result text CHECK (result IN ('success','failed','skipped','processing')),
  failure_code text,
  safe_error text,
  idempotency_key text,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.payment_webhook_attempts TO authenticated;
GRANT ALL ON public.payment_webhook_attempts TO service_role;

ALTER TABLE public.payment_webhook_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wh_att_read" ON public.payment_webhook_attempts
  FOR SELECT TO authenticated
  USING (has_permission(auth.uid(), 'payment_webhooks.read'));

-- No UPDATE/DELETE policies → append-only for authenticated. service_role bypasses.

CREATE INDEX IF NOT EXISTS idx_wh_attempts_webhook ON public.payment_webhook_attempts(webhook_id, attempt_number DESC);

-- 3) Record attempt from retry_payment_webhook (extend behavior; keep existing signature)
CREATE OR REPLACE FUNCTION public.retry_payment_webhook(_webhook_id uuid, _reason text, _idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  wh record;
  v_new_attempt int;
  MAX_ATTEMPTS constant int := 10;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT public.has_permission(auth.uid(),'payment_webhooks.retry') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN
    RAISE EXCEPTION 'REASON_REQUIRED_MIN_5';
  END IF;
  IF _idempotency_key IS NULL OR length(_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
  END IF;

  SELECT * INTO wh FROM public.payment_webhooks
   WHERE id = _webhook_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WEBHOOK_NOT_FOUND'; END IF;

  IF wh.processed = true AND wh.processing_state = 'processed' THEN
    RAISE EXCEPTION 'WEBHOOK_ALREADY_PROCESSED';
  END IF;
  IF wh.signature_valid IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'INVALID_SIGNATURE';
  END IF;
  IF wh.processing_state = 'processing'
     AND wh.processing_started_at IS NOT NULL
     AND wh.processing_started_at > now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'RETRY_ALREADY_RUNNING';
  END IF;
  IF wh.retry_count >= MAX_ATTEMPTS THEN
    RAISE EXCEPTION 'RETRY_LIMIT_REACHED';
  END IF;
  IF wh.related_request_id IS NULL THEN
    RAISE EXCEPTION 'WEBHOOK_NOT_LINKED';
  END IF;

  v_new_attempt := COALESCE(wh.retry_count,0) + 1;

  UPDATE public.payment_webhooks
     SET processing_state = 'processing',
         processing_started_at = now(),
         processing_owner = 'retry:' || auth.uid()::text,
         retry_count = v_new_attempt
   WHERE id = _webhook_id;

  INSERT INTO public.payment_webhook_attempts
    (webhook_id, attempt_number, trigger_type, triggered_by, reason, result, idempotency_key)
  VALUES
    (_webhook_id, v_new_attempt, 'admin_retry', auth.uid(), btrim(_reason), 'processing', _idempotency_key);

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(),'webhook_retry_started','payment_webhook',_webhook_id::text,
          jsonb_build_object('reason',btrim(_reason),
                             'attempt',v_new_attempt,
                             'idempotency_key',_idempotency_key,
                             'previous_state',wh.processing_state));

  RETURN jsonb_build_object(
    'status','retry_started',
    'webhook_id',_webhook_id,
    'attempt_count',v_new_attempt,
    'related_request_id',wh.related_request_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.retry_payment_webhook(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retry_payment_webhook(uuid,text,text) TO authenticated, service_role;

-- 4) list_recharge_webhooks — server-side list (no raw payload)
CREATE OR REPLACE FUNCTION public.list_recharge_webhooks(_request_id uuid)
 RETURNS TABLE(
   id uuid,
   gateway_id uuid,
   gateway_name text,
   gateway_mode text,
   event_type text,
   provider_event_id text,
   external_id text,
   signature_valid boolean,
   processing_state text,
   processed boolean,
   retry_count int,
   received_at timestamptz,
   processing_started_at timestamptz,
   processed_at timestamptz,
   processing_owner text,
   related_request_id uuid,
   processing_error text
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT public.has_permission(auth.uid(),'payment_webhooks.read') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY
  SELECT w.id, w.gateway_id, g.name AS gateway_name, w.gateway_mode,
         w.event_type, w.provider_event_id, w.external_id,
         w.signature_valid, w.processing_state, w.processed, w.retry_count,
         w.received_at, w.processing_started_at, w.processed_at,
         -- redact processing_owner to first 20 chars (contains admin uuid, we keep safe)
         CASE WHEN w.processing_owner IS NULL THEN NULL
              ELSE left(w.processing_owner, 40) END AS processing_owner,
         w.related_request_id,
         -- safe error message only
         CASE WHEN w.processing_error IS NULL THEN NULL
              ELSE left(w.processing_error, 200) END AS processing_error
  FROM public.payment_webhooks w
  LEFT JOIN public.payment_gateways g ON g.id = w.gateway_id
  WHERE w.related_request_id = _request_id
  ORDER BY w.received_at DESC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_recharge_webhooks(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_recharge_webhooks(uuid) TO authenticated, service_role;

-- 5) get_redacted_webhook_detail — server-side redaction of payload
CREATE OR REPLACE FUNCTION public.get_redacted_webhook_detail(_webhook_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  wh record;
  gw record;
  attempts jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT public.has_permission(auth.uid(),'payment_webhooks.read') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT * INTO wh FROM public.payment_webhooks WHERE id = _webhook_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'WEBHOOK_NOT_FOUND'; END IF;

  SELECT id, name, provider_code INTO gw FROM public.payment_gateways WHERE id = wh.gateway_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'attempt_number', a.attempt_number,
    'trigger_type', a.trigger_type,
    'triggered_by', a.triggered_by,
    'reason', CASE WHEN a.reason IS NULL THEN NULL ELSE left(a.reason, 200) END,
    'started_at', a.started_at,
    'finished_at', a.finished_at,
    'result', a.result,
    'failure_code', a.failure_code,
    'safe_error', a.safe_error,
    'idempotency_key', a.idempotency_key
  ) ORDER BY a.attempt_number DESC), '[]'::jsonb)
  INTO attempts
  FROM public.payment_webhook_attempts a
  WHERE a.webhook_id = _webhook_id;

  -- Audit read
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(),'webhook.detail.read','payment_webhook',_webhook_id::text,
          jsonb_build_object('gateway_id', wh.gateway_id));

  RETURN jsonb_build_object(
    'id', wh.id,
    'gateway_id', wh.gateway_id,
    'gateway_name', gw.name,
    'gateway_provider', gw.provider_code,
    'gateway_mode', wh.gateway_mode,
    'event_type', wh.event_type,
    'provider_event_id', wh.provider_event_id,
    'external_id', wh.external_id,
    'signature_valid', wh.signature_valid,
    'processing_state', wh.processing_state,
    'processed', wh.processed,
    'retry_count', wh.retry_count,
    'received_at', wh.received_at,
    'processing_started_at', wh.processing_started_at,
    'processed_at', wh.processed_at,
    'processing_owner', CASE WHEN wh.processing_owner IS NULL THEN NULL ELSE left(wh.processing_owner, 40) END,
    'processing_error', CASE WHEN wh.processing_error IS NULL THEN NULL ELSE left(wh.processing_error, 500) END,
    'related_request_id', wh.related_request_id,
    'idempotency_key', wh.idempotency_key,
    -- raw payload keys only (server-side allowlist done in JS redaction layer)
    'raw_payload_keys', (SELECT COALESCE(jsonb_agg(k), '[]'::jsonb) FROM jsonb_object_keys(wh.raw_payload) k),
    'raw_payload_size', pg_column_size(wh.raw_payload),
    'raw_payload', wh.raw_payload,  -- returned to server-fn only; server-fn applies redaction before responding
    'attempts', attempts
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_redacted_webhook_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_redacted_webhook_detail(uuid) TO authenticated, service_role;

-- 6) audit trail for CSV exports
CREATE OR REPLACE FUNCTION public.log_recharge_export(_row_count int, _filters jsonb, _export_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT public.has_permission(auth.uid(),'recharge_requests.read') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  IF _export_type NOT IN ('csv','excel') THEN
    RAISE EXCEPTION 'INVALID_EXPORT_TYPE';
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(),'recharge.export','recharge_requests',NULL,
          jsonb_build_object(
            'export_type', _export_type,
            'row_count', _row_count,
            'filters', COALESCE(_filters, '{}'::jsonb)
          ));
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.log_recharge_export(int,jsonb,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_recharge_export(int,jsonb,text) TO authenticated, service_role;
