
CREATE OR REPLACE FUNCTION public.get_recharge_receipt_signed_url(
  _receipt_id uuid,
  _ttl_seconds integer DEFAULT 60,
  _reason text DEFAULT NULL
)
RETURNS TABLE(storage_bucket text, storage_object_path text, ttl_seconds integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec record;
  v_is_admin_view boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  SELECT id, user_id, request_id, storage_bucket, storage_object_path
    INTO rec
  FROM public.recharge_receipts
  WHERE id = _receipt_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RECEIPT_NOT_FOUND';
  END IF;

  IF rec.user_id = auth.uid() THEN
    v_is_admin_view := false;
  ELSIF public.has_permission(auth.uid(), 'recharge_receipts.read') THEN
    v_is_admin_view := true;
    IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN
      RAISE EXCEPTION 'REASON_REQUIRED_MIN_5';
    END IF;
  ELSE
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF _ttl_seconds IS NULL OR _ttl_seconds < 10 OR _ttl_seconds > 300 THEN
    _ttl_seconds := 60;
  END IF;

  IF v_is_admin_view THEN
    INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (
      auth.uid(),
      'receipt_viewed_by_admin',
      'recharge_receipt',
      _receipt_id::text,
      jsonb_build_object(
        'request_id', rec.request_id,
        'ttl_seconds', _ttl_seconds,
        'reason', btrim(_reason)
      )
    );
  END IF;

  storage_bucket := rec.storage_bucket;
  storage_object_path := rec.storage_object_path;
  ttl_seconds := _ttl_seconds;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.get_recharge_receipt_signed_url(uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_recharge_receipt_signed_url(uuid, integer, text) TO authenticated, service_role;
