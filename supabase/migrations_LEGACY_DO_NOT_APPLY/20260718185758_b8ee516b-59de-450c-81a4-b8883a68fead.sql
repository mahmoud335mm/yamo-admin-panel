
-- =====================================================================
-- PART A · إصلاح audit_logs في 6 دوال شحن (resource_type → entity_type)
-- =====================================================================
DO $fix$
DECLARE r record; new_def text;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname IN ('cancel_recharge_request','complete_recharge_request',
                        'create_recharge_receipt_upload','fail_recharge_request',
                        'review_recharge_receipt','submit_recharge_receipt')
      AND pg_get_functiondef(p.oid) LIKE '%audit_logs%resource_type%'
  LOOP
    new_def := pg_get_functiondef(r.oid);
    -- استبدال قائمة الأعمدة داخل INSERT INTO audit_logs
    new_def := replace(new_def,
      'INSERT INTO public.audit_logs(actor_id, action, resource_type, resource_id, metadata)',
      'INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)');
    -- التأكد من تحويل UUID إلى TEXT في VALUES (entity_id text)
    -- نمط شائع: ...,'recharge_request',_request_id, ... أو , _request_id,
    new_def := regexp_replace(new_def,
      E'(,''[a-z_]+'',)\\s*(_?[a-z_]+_id)(\\s*,\\s*jsonb_build_object)',
      E'\\1 \\2::text\\3', 'g');
    EXECUTE new_def;
  END LOOP;
END $fix$;

-- =====================================================================
-- PART B · مُساعِد داخلي لإكمال الطلب من مسار تحقق موثوق (بدون فحص صلاحية)
-- =====================================================================
CREATE OR REPLACE FUNCTION public._complete_recharge_request_internal(
  _request_id     uuid,
  _external_ref   text,
  _actor          uuid,
  _source         text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE req record; ref text; new_bal bigint;
BEGIN
  SELECT * INTO req FROM public.recharge_requests WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;

  -- idempotent: لا تعيد إضافة الكوينز
  IF req.status = 'completed' THEN
    RETURN _request_id;
  END IF;

  IF req.status IN ('failed','cancelled','refunded','reversed','chargeback') THEN
    RAISE EXCEPTION 'REQUEST_ALREADY_TERMINAL: %', req.status;
  END IF;

  IF req.status NOT IN ('paid','approved','crediting','manual_review',
                        'payment_submitted','verifying') THEN
    RAISE EXCEPTION 'REQUEST_STATE_INVALID: %', req.status;
  END IF;

  ref := 'YC-RCH-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(_request_id::text,'-',''),1,8);

  -- قيد الكوينز الأساسية
  new_bal := public._wallet_apply(
    req.user_id, 'coins'::wallet_account, req.coin_amount,
    'recharge_credit'::ledger_reason, ref,
    jsonb_build_object('request_id',_request_id,'external_ref',_external_ref,
                       'source',_source,'kind','base'));

  -- قيد البونص منفصل (إن وجد)
  IF COALESCE(req.bonus_amount,0) > 0 THEN
    new_bal := public._wallet_apply(
      req.user_id, 'coins'::wallet_account, req.bonus_amount,
      'recharge_credit'::ledger_reason, ref || '-B',
      jsonb_build_object('request_id',_request_id,'external_ref',_external_ref,
                         'source',_source,'kind','bonus'));
  END IF;

  UPDATE public.recharge_requests
     SET status='completed', completed_at=now(), updated_at=now(),
         external_reference = COALESCE(external_reference, _external_ref)
   WHERE id = _request_id;

  INSERT INTO public.recharge_request_events(request_id, event_type, actor_id, metadata)
  VALUES (_request_id,'completed',_actor,
          jsonb_build_object('reference',ref,'balance_after',new_bal,'source',_source));

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_actor,'recharge_completed','recharge_request',_request_id::text,
          jsonb_build_object('reference',ref,'total_coins',req.total_coins,'source',_source));

  PERFORM public._enqueue_txn_message('recharge_completed','recharge',_request_id, req.user_id,
    jsonb_build_object('coins',req.coin_amount,'bonus',req.bonus_amount,
                       'total',req.total_coins,'reference',ref),
    'recharge_completed:' || _request_id::text);
  RETURN _request_id;
END;
$$;

REVOKE ALL ON FUNCTION public._complete_recharge_request_internal(uuid,text,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._complete_recharge_request_internal(uuid,text,uuid,text) TO service_role;

-- =====================================================================
-- PART C · retry_payment_webhook
-- =====================================================================
CREATE OR REPLACE FUNCTION public.retry_payment_webhook(
  _webhook_id       uuid,
  _reason           text,
  _idempotency_key  text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  wh record;
  v_new_attempt int;
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

  SELECT * INTO wh
  FROM public.payment_webhooks
  WHERE id = _webhook_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'WEBHOOK_NOT_FOUND'; END IF;

  -- منع إعادة معالجة webhook مكتمل بنجاح
  IF wh.processed = true AND wh.processing_state = 'processed' THEN
    RETURN jsonb_build_object(
      'status','already_processed',
      'webhook_id',_webhook_id,
      'attempt_count',wh.retry_count);
  END IF;

  -- منع إعادة محاولة توقيع غير صالح (بدون تصحيح موثق)
  IF wh.signature_valid = false THEN
    RAISE EXCEPTION 'INVALID_SIGNATURE_NOT_RETRIABLE';
  END IF;

  -- منع محاولتين متزامنتين — قفل ذرّي بتغيير الحالة
  IF wh.processing_state = 'processing'
     AND wh.processing_started_at IS NOT NULL
     AND wh.processing_started_at > now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'WEBHOOK_PROCESSING_IN_PROGRESS';
  END IF;

  v_new_attempt := COALESCE(wh.retry_count,0) + 1;

  UPDATE public.payment_webhooks
     SET processing_state = 'processing',
         processing_started_at = now(),
         processing_owner = 'retry:' || auth.uid()::text,
         retry_count = v_new_attempt
   WHERE id = _webhook_id;

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
$$;

REVOKE ALL ON FUNCTION public.retry_payment_webhook(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retry_payment_webhook(uuid,text,text) TO authenticated, service_role;

-- =====================================================================
-- PART D · verify_recharge_payment
-- =====================================================================
CREATE OR REPLACE FUNCTION public.verify_recharge_payment(
  _request_id      uuid,
  _source          text,
  _reason          text,
  _idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req record;
  wh  record;
  rcpt record;
  v_actor uuid;
  v_result jsonb;
BEGIN
  IF _source NOT IN ('verified_webhook','approved_manual_receipt','admin_retry','mock_gateway') THEN
    RAISE EXCEPTION 'INVALID_SOURCE';
  END IF;

  -- تفويض حسب المصدر
  IF _source = 'admin_retry' THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
    IF NOT public.has_permission(auth.uid(),'recharge_requests.verify') THEN
      RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN
      RAISE EXCEPTION 'REASON_REQUIRED_MIN_5';
    END IF;
    v_actor := auth.uid();
  ELSE
    -- المصادر الأخرى: داخلية موثوقة، لا تحتاج auth.uid()
    v_actor := auth.uid(); -- قد تكون NULL في سياق webhook
  END IF;

  IF _idempotency_key IS NULL OR length(_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
  END IF;

  -- قفل الطلب
  SELECT * INTO req FROM public.recharge_requests
   WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;

  -- Idempotent: طلب مكتمل مسبقًا
  IF req.status = 'completed' THEN
    RETURN jsonb_build_object('status','already_completed','request_id',_request_id);
  END IF;

  -- حالات نهائية غير قابلة للتحقق
  IF req.status = 'cancelled' THEN RAISE EXCEPTION 'REQUEST_CANCELLED'; END IF;
  IF req.status IN ('refunded','partially_refunded','refund_pending') THEN
    RAISE EXCEPTION 'REQUEST_REFUNDED';
  END IF;
  IF req.status IN ('reversed','chargeback') THEN
    RAISE EXCEPTION 'INVALID_STATE: %', req.status;
  END IF;

  -- انتهاء الصلاحية (يسمح للمسؤول بتجاوزه في admin_retry)
  IF req.expires_at IS NOT NULL AND req.expires_at < now() AND _source <> 'admin_retry' THEN
    RAISE EXCEPTION 'REQUEST_EXPIRED';
  END IF;

  -- حالات مسموحة للتحقق
  IF req.status NOT IN ('paid','approved','verifying','manual_review','failed','payment_submitted') THEN
    RAISE EXCEPTION 'INVALID_STATE: %', req.status;
  END IF;

  -- ==========================================================
  -- التحقق من مصدر الدفع
  -- ==========================================================
  IF _source IN ('verified_webhook','mock_gateway') THEN
    SELECT * INTO wh
    FROM public.payment_webhooks
    WHERE related_request_id = _request_id
      AND processing_state IN ('processing','processed')
    ORDER BY received_at DESC
    LIMIT 1;

    IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_NOT_CONFIRMED'; END IF;
    IF wh.signature_valid = false AND _source <> 'mock_gateway' THEN
      RAISE EXCEPTION 'INVALID_SIGNATURE';
    END IF;
    IF req.payment_gateway_id IS NOT NULL AND wh.gateway_id <> req.payment_gateway_id THEN
      RAISE EXCEPTION 'GATEWAY_MISMATCH';
    END IF;
    IF wh.gateway_mode <> req.payment_gateway_mode THEN
      RAISE EXCEPTION 'GATEWAY_MODE_MISMATCH';
    END IF;

    -- فحص مبلغ/عملة webhook إذا كانت raw_payload تحملها بشكل معياري
    IF wh.raw_payload ? 'amount' THEN
      IF (wh.raw_payload->>'amount')::numeric <> COALESCE(req.final_amount, req.price) THEN
        RAISE EXCEPTION 'AMOUNT_MISMATCH';
      END IF;
    END IF;
    IF wh.raw_payload ? 'currency' THEN
      IF (wh.raw_payload->>'currency') <> req.currency_code THEN
        RAISE EXCEPTION 'CURRENCY_MISMATCH';
      END IF;
    END IF;

  ELSIF _source = 'approved_manual_receipt' THEN
    SELECT * INTO rcpt
    FROM public.recharge_receipts
    WHERE request_id = _request_id
      AND review_status = 'approved'
    ORDER BY reviewed_at DESC NULLS LAST
    LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_APPROVED'; END IF;

  ELSIF _source = 'admin_retry' THEN
    -- لا نفرض مصدر دفع محدد؛ نستمر إلى الإكمال بناءً على قرار المسؤول
    NULL;
  END IF;

  -- انتقال إلى verifying
  UPDATE public.recharge_requests
     SET status = 'verifying', verified_at = now(), updated_at = now()
   WHERE id = _request_id AND status <> 'verifying';

  INSERT INTO public.recharge_request_events(request_id, event_type, actor_id, metadata)
  VALUES (_request_id,'verify_started',v_actor,
          jsonb_build_object('source',_source,'idempotency_key',_idempotency_key));

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (v_actor,'recharge_verify','recharge_request',_request_id::text,
          jsonb_build_object('source',_source,
                             'reason',CASE WHEN _source='admin_retry' THEN btrim(_reason) ELSE NULL END,
                             'idempotency_key',_idempotency_key));

  -- إكمال داخلي (يضيف الكوينز، idempotent)
  PERFORM public._complete_recharge_request_internal(
    _request_id,
    COALESCE(req.external_reference,'verify:'||_idempotency_key),
    v_actor,
    _source);

  RETURN jsonb_build_object('status','completed','request_id',_request_id,'source',_source);
END;
$$;

REVOKE ALL ON FUNCTION public.verify_recharge_payment(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_recharge_payment(uuid,text,text,text) TO authenticated, service_role;
