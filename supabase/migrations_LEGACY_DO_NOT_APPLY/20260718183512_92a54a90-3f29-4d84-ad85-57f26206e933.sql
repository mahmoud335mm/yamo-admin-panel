
DROP FUNCTION IF EXISTS public.complete_recharge_request(uuid, text);
DROP FUNCTION IF EXISTS public.fail_recharge_request(uuid, text);

-- outbox helper
CREATE OR REPLACE FUNCTION public._enqueue_txn_message(
  _event_type text, _txn_type text, _txn_id uuid,
  _recipient uuid, _safe_payload jsonb, _idem text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.transaction_message_outbox(
    event_type, transaction_type, transaction_id,
    recipient_user_id, safe_payload, idempotency_key
  ) VALUES (_event_type, _txn_type, _txn_id, _recipient, COALESCE(_safe_payload,'{}'::jsonb), _idem)
  ON CONFLICT (idempotency_key) DO NOTHING;
END $$;
REVOKE EXECUTE ON FUNCTION public._enqueue_txn_message(text,text,uuid,uuid,jsonb,text) FROM PUBLIC, authenticated;

CREATE OR REPLACE FUNCTION public.resolve_payment_instructions(_request_id uuid)
RETURNS TABLE(
  method_id uuid, method_kind text, method_label_ar text, method_label_en text,
  account_display_name text, account_last4 text, account_reference text,
  account_bank_name text, account_currency text, expires_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO r FROM public.recharge_requests WHERE id = _request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF r.user_id <> auth.uid() AND NOT public.has_permission(auth.uid(),'recharge_payment_instructions.resolve') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  RETURN QUERY
    SELECT pm.id, pm.kind::text, pm.label_ar, pm.label_en,
           pma.display_name, pma.account_last4, pma.account_reference,
           pma.bank_name, pma.currency, r.expires_at
      FROM public.payment_methods pm
      LEFT JOIN LATERAL (
        SELECT * FROM public.payment_method_accounts
         WHERE method_id = pm.id AND status = 'active'
         ORDER BY sort_order NULLS LAST LIMIT 1
      ) pma ON true
     WHERE pm.id = r.payment_method_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.resolve_payment_instructions(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.resolve_payment_instructions(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_recharge_receipt_upload(
  _request_id uuid, _mime text, _size_bytes bigint
) RETURNS TABLE(receipt_id uuid, storage_bucket text, storage_object_path text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE req record; new_id uuid; new_path text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _mime NOT IN ('image/jpeg','image/png','image/webp','application/pdf') THEN RAISE EXCEPTION 'MIME_NOT_ALLOWED'; END IF;
  IF _size_bytes IS NULL OR _size_bytes <= 0 OR _size_bytes > 10*1024*1024 THEN RAISE EXCEPTION 'SIZE_INVALID'; END IF;
  SELECT * INTO req FROM public.recharge_requests WHERE id = _request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF req.user_id <> auth.uid() THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF req.status NOT IN ('pending_payment','manual_review','more_info_required') THEN
    RAISE EXCEPTION 'REQUEST_STATE_INVALID: %', req.status;
  END IF;
  new_id := gen_random_uuid();
  new_path := auth.uid()::text || '/' || _request_id::text || '/' || new_id::text ||
              CASE _mime WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png'
                         WHEN 'image/webp' THEN '.webp' WHEN 'application/pdf' THEN '.pdf' END;
  INSERT INTO public.recharge_receipts(id, request_id, user_id, uploaded_by, storage_bucket, storage_object_path, mime_type, size_bytes, status)
  VALUES (new_id, _request_id, auth.uid(), auth.uid(), 'recharge-receipts', new_path, _mime, _size_bytes, 'uploaded');
  INSERT INTO public.audit_logs(actor_id, action, resource_type, resource_id, metadata)
  VALUES (auth.uid(),'receipt_upload_session_created','recharge_receipt', new_id,
          jsonb_build_object('request_id',_request_id,'mime',_mime,'size_bytes',_size_bytes));
  receipt_id := new_id; storage_bucket := 'recharge-receipts'; storage_object_path := new_path;
  RETURN NEXT;
END $$;
REVOKE EXECUTE ON FUNCTION public.create_recharge_receipt_upload(uuid,text,bigint) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_recharge_receipt_upload(uuid,text,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_recharge_receipt(
  _receipt_id uuid, _sender_name text, _paid_amount numeric,
  _currency text, _payment_reference text, _paid_at timestamptz
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rec record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO rec FROM public.recharge_receipts WHERE id = _receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF rec.user_id <> auth.uid() THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF rec.status <> 'uploaded' THEN RAISE EXCEPTION 'RECEIPT_STATE_INVALID: %', rec.status; END IF;

  SET LOCAL role = 'service_role';
  UPDATE public.recharge_receipts
     SET sender_name=_sender_name, paid_amount=_paid_amount, currency=_currency,
         payment_reference=_payment_reference, paid_at=_paid_at,
         submitted_at=now(), status='submitted'
   WHERE id = _receipt_id;
  RESET role;

  UPDATE public.recharge_requests
     SET status='payment_submitted', updated_at=now()
   WHERE id = rec.request_id AND status IN ('pending_payment','more_info_required');

  INSERT INTO public.audit_logs(actor_id, action, resource_type, resource_id, metadata)
  VALUES (auth.uid(),'receipt_submitted','recharge_receipt', _receipt_id,
          jsonb_build_object('request_id',rec.request_id,'amount',_paid_amount,'currency',_currency));
  PERFORM public._enqueue_txn_message('recharge_receipt_submitted','recharge', rec.request_id, auth.uid(),
    jsonb_build_object('receipt_id',_receipt_id,'amount',_paid_amount,'currency',_currency),
    'recharge_receipt_submitted:' || _receipt_id::text);
END $$;
REVOKE EXECUTE ON FUNCTION public.submit_recharge_receipt(uuid,text,numeric,text,text,timestamptz) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.submit_recharge_receipt(uuid,text,numeric,text,text,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.review_recharge_receipt(
  _receipt_id uuid, _decision text, _reason text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rec record; req record; new_status public.recharge_receipt_status; new_req_status text;
BEGIN
  PERFORM public._require_perm('recharge_receipts.review');
  IF _decision NOT IN ('approved','rejected','more_info_required') THEN RAISE EXCEPTION 'INVALID_DECISION'; END IF;
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;

  SELECT * INTO rec FROM public.recharge_receipts WHERE id = _receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF rec.status NOT IN ('submitted','under_review') THEN RAISE EXCEPTION 'RECEIPT_STATE_INVALID: %', rec.status; END IF;

  new_status := _decision::public.recharge_receipt_status;
  new_req_status := CASE _decision WHEN 'approved' THEN 'paid' WHEN 'rejected' THEN 'manual_review' ELSE 'more_info_required' END;

  SET LOCAL role = 'service_role';
  UPDATE public.recharge_receipts
     SET status=new_status, reviewed_at=now(), reviewed_by=auth.uid(),
         review_decision=_decision, review_reason=_reason
   WHERE id = _receipt_id;
  RESET role;

  SELECT * INTO req FROM public.recharge_requests WHERE id = rec.request_id;
  UPDATE public.recharge_requests SET status=new_req_status, updated_at=now() WHERE id = rec.request_id;
  INSERT INTO public.audit_logs(actor_id, action, resource_type, resource_id, metadata)
  VALUES (auth.uid(),'receipt_' || _decision,'recharge_receipt', _receipt_id,
          jsonb_build_object('request_id',rec.request_id,'reason',_reason));
  PERFORM public._enqueue_txn_message('recharge_receipt_' || _decision,'recharge', rec.request_id, req.user_id,
    jsonb_build_object('receipt_id',_receipt_id,'decision',_decision),
    'recharge_receipt_' || _decision || ':' || _receipt_id::text);
END $$;
REVOKE EXECUTE ON FUNCTION public.review_recharge_receipt(uuid,text,text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.review_recharge_receipt(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_recharge_receipt_signed_url(_receipt_id uuid, _ttl_seconds int DEFAULT 60)
RETURNS TABLE(storage_bucket text, storage_object_path text, ttl_seconds int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rec record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO rec FROM public.recharge_receipts WHERE id = _receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF rec.user_id = auth.uid() THEN
    NULL;
  ELSIF public.has_permission(auth.uid(),'recharge_receipts.read') THEN
    INSERT INTO public.audit_logs(actor_id, action, resource_type, resource_id, metadata)
    VALUES (auth.uid(),'receipt_viewed_by_admin','recharge_receipt', _receipt_id,
            jsonb_build_object('request_id',rec.request_id));
  ELSE
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  IF _ttl_seconds IS NULL OR _ttl_seconds < 10 OR _ttl_seconds > 300 THEN _ttl_seconds := 60; END IF;
  storage_bucket := rec.storage_bucket;
  storage_object_path := rec.storage_object_path;
  ttl_seconds := _ttl_seconds;
  RETURN NEXT;
END $$;
REVOKE EXECUTE ON FUNCTION public.get_recharge_receipt_signed_url(uuid,int) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_recharge_receipt_signed_url(uuid,int) TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_recharge_request(_request_id uuid, _external_ref text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE req record; ref text; new_bal bigint;
BEGIN
  PERFORM public._require_perm('recharge_requests.complete');
  SELECT * INTO req FROM public.recharge_requests WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF req.status IN ('completed','failed','cancelled','refunded') THEN RAISE EXCEPTION 'REQUEST_ALREADY_TERMINAL: %', req.status; END IF;
  IF req.status NOT IN ('paid','approved','crediting','manual_review','payment_submitted') THEN RAISE EXCEPTION 'REQUEST_STATE_INVALID: %', req.status; END IF;

  ref := 'YC-RCH-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(_request_id::text,'-',''),1,8);
  new_bal := public._wallet_apply(req.user_id,'coins'::wallet_account, req.total_coins,
    'recharge_credit'::ledger_reason, ref,
    jsonb_build_object('request_id',_request_id,'external_ref',_external_ref,'coins',req.coin_amount,'bonus',req.bonus_amount));

  UPDATE public.recharge_requests
     SET status='completed', completed_at=now(), updated_at=now(),
         external_reference = COALESCE(external_reference, _external_ref)
   WHERE id = _request_id;

  INSERT INTO public.recharge_request_events(request_id, event_type, actor_id, metadata)
  VALUES (_request_id, 'completed', auth.uid(), jsonb_build_object('reference',ref,'balance_after',new_bal));
  INSERT INTO public.audit_logs(actor_id, action, resource_type, resource_id, metadata)
  VALUES (auth.uid(),'recharge_completed','recharge_request', _request_id, jsonb_build_object('reference',ref,'total_coins',req.total_coins));
  PERFORM public._enqueue_txn_message('recharge_completed','recharge', _request_id, req.user_id,
    jsonb_build_object('coins',req.coin_amount,'bonus',req.bonus_amount,'total',req.total_coins,'reference',ref),
    'recharge_completed:' || _request_id::text);
  RETURN _request_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.complete_recharge_request(uuid,text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.complete_recharge_request(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fail_recharge_request(_request_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE req record;
BEGIN
  PERFORM public._require_perm('recharge_requests.fail');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT * INTO req FROM public.recharge_requests WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF req.status IN ('completed','failed','cancelled','refunded') THEN RAISE EXCEPTION 'ALREADY_TERMINAL'; END IF;
  UPDATE public.recharge_requests SET status='failed', failure_reason=_reason, updated_at=now() WHERE id=_request_id;
  INSERT INTO public.recharge_request_events(request_id, event_type, actor_id, metadata)
  VALUES (_request_id,'failed',auth.uid(),jsonb_build_object('reason',_reason));
  INSERT INTO public.audit_logs(actor_id, action, resource_type, resource_id, metadata)
  VALUES (auth.uid(),'recharge_failed','recharge_request',_request_id,jsonb_build_object('reason',_reason));
  PERFORM public._enqueue_txn_message('recharge_failed','recharge',_request_id, req.user_id,
    jsonb_build_object('reason',_reason), 'recharge_failed:' || _request_id::text);
END $$;
REVOKE EXECUTE ON FUNCTION public.fail_recharge_request(uuid,text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fail_recharge_request(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_recharge_request(_request_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE req record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT * INTO req FROM public.recharge_requests WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF req.user_id <> auth.uid() AND NOT public.has_permission(auth.uid(),'recharge_requests.cancel') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF req.status NOT IN ('created','pending_payment','more_info_required') THEN RAISE EXCEPTION 'REQUEST_STATE_INVALID: %', req.status; END IF;
  UPDATE public.recharge_requests SET status='cancelled', cancellation_reason=_reason, updated_at=now() WHERE id=_request_id;
  INSERT INTO public.recharge_request_events(request_id, event_type, actor_id, metadata)
  VALUES (_request_id,'cancelled',auth.uid(),jsonb_build_object('reason',_reason));
  INSERT INTO public.audit_logs(actor_id, action, resource_type, resource_id, metadata)
  VALUES (auth.uid(),'recharge_cancelled','recharge_request',_request_id,jsonb_build_object('reason',_reason));
  PERFORM public._enqueue_txn_message('recharge_cancelled','recharge',_request_id, req.user_id,
    jsonb_build_object('reason',_reason), 'recharge_cancelled:' || _request_id::text);
END $$;
REVOKE EXECUTE ON FUNCTION public.cancel_recharge_request(uuid,text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.cancel_recharge_request(uuid,text) TO authenticated;
