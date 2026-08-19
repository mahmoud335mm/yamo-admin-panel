
-- 1. columns
ALTER TABLE public.recharge_refunds
  ADD COLUMN IF NOT EXISTS polling_owner            text,
  ADD COLUMN IF NOT EXISTS polling_started_at       timestamptz,
  ADD COLUMN IF NOT EXISTS polling_lease_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_status_checked_at   timestamptz,
  ADD COLUMN IF NOT EXISTS next_status_check_at     timestamptz,
  ADD COLUMN IF NOT EXISTS status_refresh_count     integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS retry_attempt_count      integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_retry_at            timestamptz,
  ADD COLUMN IF NOT EXISTS gateway_execution_state  text;

CREATE INDEX IF NOT EXISTS idx_refunds_polling_due
  ON public.recharge_refunds (next_status_check_at)
  WHERE status = 'processing_gateway' AND next_status_check_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_refunds_polling_lease
  ON public.recharge_refunds (polling_lease_expires_at)
  WHERE polling_owner IS NOT NULL;

-- 2. refund_retry_policies
CREATE TABLE IF NOT EXISTS public.refund_retry_policies (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway_id                      uuid REFERENCES public.payment_gateways(id) ON DELETE CASCADE,
  gateway_mode                    payment_gateway_mode,
  max_create_attempts             integer NOT NULL DEFAULT 3 CHECK (max_create_attempts BETWEEN 1 AND 10),
  max_status_refresh_attempts     integer NOT NULL DEFAULT 20 CHECK (max_status_refresh_attempts BETWEEN 1 AND 200),
  initial_backoff_seconds         integer NOT NULL DEFAULT 30 CHECK (initial_backoff_seconds >= 5),
  max_backoff_seconds             integer NOT NULL DEFAULT 3600 CHECK (max_backoff_seconds >= 60),
  backoff_multiplier              numeric(6,3) NOT NULL DEFAULT 2.0 CHECK (backoff_multiplier >= 1.0),
  jitter_percent                  integer NOT NULL DEFAULT 20 CHECK (jitter_percent BETWEEN 0 AND 100),
  polling_interval_seconds        integer NOT NULL DEFAULT 60 CHECK (polling_interval_seconds >= 15),
  unknown_result_timeout_minutes  integer NOT NULL DEFAULT 60 CHECK (unknown_result_timeout_minutes >= 5),
  stale_processing_timeout_minutes integer NOT NULL DEFAULT 120 CHECK (stale_processing_timeout_minutes >= 5),
  move_to_manual_review_after     integer NOT NULL DEFAULT 240 CHECK (move_to_manual_review_after >= 10),
  active                          boolean NOT NULL DEFAULT true,
  version                         integer NOT NULL DEFAULT 1,
  created_by                      uuid REFERENCES auth.users(id),
  created_at                      timestamptz NOT NULL DEFAULT now(),
  updated_at                      timestamptz NOT NULL DEFAULT now()
);

-- Partial unique indexes for the four scope combos.
CREATE UNIQUE INDEX IF NOT EXISTS ux_refund_retry_policy_global
  ON public.refund_retry_policies ((true))
  WHERE active AND gateway_id IS NULL AND gateway_mode IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_refund_retry_policy_gw
  ON public.refund_retry_policies (gateway_id)
  WHERE active AND gateway_id IS NOT NULL AND gateway_mode IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_refund_retry_policy_mode
  ON public.refund_retry_policies (gateway_mode)
  WHERE active AND gateway_id IS NULL AND gateway_mode IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_refund_retry_policy_gw_mode
  ON public.refund_retry_policies (gateway_id, gateway_mode)
  WHERE active AND gateway_id IS NOT NULL AND gateway_mode IS NOT NULL;

GRANT SELECT ON public.refund_retry_policies TO authenticated;
GRANT ALL    ON public.refund_retry_policies TO service_role;
ALTER TABLE public.refund_retry_policies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "refund_retry_policies_read_admin" ON public.refund_retry_policies
  FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'recharge_refunds.read'));

CREATE POLICY "refund_retry_policies_manage_super" ON public.refund_retry_policies
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'::admin_role))
  WITH CHECK (public.has_role(auth.uid(), 'super_admin'::admin_role));

INSERT INTO public.refund_retry_policies (gateway_id, gateway_mode)
SELECT NULL, NULL
WHERE NOT EXISTS (
  SELECT 1 FROM public.refund_retry_policies
  WHERE gateway_id IS NULL AND gateway_mode IS NULL AND active
);

-- 3. permissions
INSERT INTO public.permissions (key, module, label_ar, label_en, description) VALUES
  ('recharge_refunds.refresh_status',        'recharge_refunds', 'تحديث حالة الاسترداد', 'Refresh refund status', 'Query gateway for current refund status without creating a new refund'),
  ('recharge_refunds.override_retry_limit',  'recharge_refunds', 'تجاوز حد المحاولات',    'Override refund retry limit', 'Allow retrying past max_create_attempts')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions (role, permission_key)
SELECT 'super_admin'::admin_role, k
FROM (VALUES ('recharge_refunds.refresh_status'), ('recharge_refunds.override_retry_limit')) t(k)
ON CONFLICT DO NOTHING;

-- 4. lookup helper
CREATE OR REPLACE FUNCTION public._lookup_refund_retry_policy(
  _gateway_id uuid, _gateway_mode payment_gateway_mode
) RETURNS public.refund_retry_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.refund_retry_policies
  WHERE active
    AND (gateway_id = _gateway_id OR gateway_id IS NULL)
    AND (gateway_mode = _gateway_mode OR gateway_mode IS NULL)
  ORDER BY (gateway_id = _gateway_id)::int DESC,
           (gateway_mode = _gateway_mode)::int DESC
  LIMIT 1
$$;

-- 5. claim/release/reclaim
CREATE OR REPLACE FUNCTION public.claim_refund_status_refresh(
  _refund_id uuid, _owner text, _lease_seconds integer DEFAULT 60
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.recharge_refunds%ROWTYPE; now_ts timestamptz := now();
BEGIN
  IF _owner IS NULL OR length(_owner) < 3 THEN RETURN jsonb_build_object('claimed', false, 'reason', 'INVALID_OWNER'); END IF;
  SELECT * INTO r FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('claimed', false, 'reason', 'REFUND_NOT_FOUND'); END IF;
  IF r.status NOT IN ('processing_gateway','manual_review') THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'REFUND_STATUS_NOT_ELIGIBLE', 'status', r.status);
  END IF;
  IF r.polling_owner IS NOT NULL AND r.polling_lease_expires_at IS NOT NULL AND r.polling_lease_expires_at > now_ts THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'REFUND_STATUS_CHECK_ALREADY_RUNNING');
  END IF;
  UPDATE public.recharge_refunds
     SET polling_owner = _owner, polling_started_at = now_ts,
         polling_lease_expires_at = now_ts + make_interval(secs => GREATEST(_lease_seconds, 15)),
         updated_at = now_ts
   WHERE id = _refund_id;
  RETURN jsonb_build_object('claimed', true, 'owner', _owner,
    'lease_expires_at', now_ts + make_interval(secs => GREATEST(_lease_seconds, 15)));
END;$$;
REVOKE ALL ON FUNCTION public.claim_refund_status_refresh(uuid, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_refund_status_refresh(uuid, text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.release_refund_status_refresh(_refund_id uuid, _owner text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.recharge_refunds
     SET polling_owner = NULL, polling_started_at = NULL, polling_lease_expires_at = NULL, updated_at = now()
   WHERE id = _refund_id AND polling_owner = _owner;
$$;
REVOKE ALL ON FUNCTION public.release_refund_status_refresh(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_refund_status_refresh(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.reclaim_stale_refund_status_checks(_max integer DEFAULT 50)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n integer;
BEGIN
  WITH candidates AS (
    SELECT id FROM public.recharge_refunds
     WHERE polling_owner IS NOT NULL AND polling_lease_expires_at IS NOT NULL AND polling_lease_expires_at < now()
     ORDER BY polling_lease_expires_at ASC LIMIT GREATEST(_max, 1)
  )
  UPDATE public.recharge_refunds r
     SET polling_owner = NULL, polling_started_at = NULL, polling_lease_expires_at = NULL, updated_at = now()
    FROM candidates c WHERE r.id = c.id;
  GET DIAGNOSTICS n = ROW_COUNT; RETURN n;
END;$$;
REVOKE ALL ON FUNCTION public.reclaim_stale_refund_status_checks(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reclaim_stale_refund_status_checks(integer) TO service_role;

-- 6. prepare_refund_status_refresh
CREATE OR REPLACE FUNCTION public.prepare_refund_status_refresh(
  _refund_id uuid, _triggered_by uuid, _reason text, _request_idempotency_key text, _polling_owner text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r public.recharge_refunds%ROWTYPE;
  attempt_id uuid := gen_random_uuid();
  attempt_num integer;
  policy public.refund_retry_policies%ROWTYPE;
  token text := encode(gen_random_bytes(24), 'hex');
BEGIN
  IF _reason IS NULL OR length(trim(_reason)) < 5 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'REASON_TOO_SHORT');
  END IF;
  SELECT * INTO r FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'REFUND_NOT_FOUND'); END IF;
  IF r.status NOT IN ('processing_gateway','manual_review') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'REFUND_STATUS_NOT_ELIGIBLE', 'status', r.status);
  END IF;
  IF r.provider_refund_id IS NULL AND r.provider_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NO_PROVIDER_REFERENCE');
  END IF;
  IF r.polling_owner IS DISTINCT FROM _polling_owner THEN
    RETURN jsonb_build_object('ok', false, 'error', 'POLLING_LEASE_NOT_HELD');
  END IF;
  SELECT * INTO policy FROM public._lookup_refund_retry_policy(r.gateway_id, r.gateway_mode);
  IF r.status_refresh_count >= policy.max_status_refresh_attempts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'REFRESH_LIMIT_REACHED');
  END IF;
  SELECT COALESCE(MAX(attempt_number), 0) + 1 INTO attempt_num
    FROM public.recharge_refund_attempts WHERE refund_id = _refund_id;
  INSERT INTO public.recharge_refund_attempts (
    id, refund_id, attempt_number, trigger_type, status,
    provider_refund_id, provider_idempotency_key, idempotency_key,
    gateway_id, gateway_mode, triggered_by, reason,
    execution_token_hash, execution_owner_id
  ) VALUES (
    attempt_id, _refund_id, attempt_num, 'refresh_status', 'started',
    r.provider_refund_id, r.provider_idempotency_key, _request_idempotency_key,
    r.gateway_id, r.gateway_mode, _triggered_by, _reason,
    encode(digest(token, 'sha256'), 'hex'), _triggered_by
  );
  UPDATE public.recharge_refunds
     SET status_refresh_count = status_refresh_count + 1, last_status_checked_at = now(), updated_at = now()
   WHERE id = _refund_id;
  RETURN jsonb_build_object('ok', true, 'attempt_id', attempt_id, 'attempt_number', attempt_num,
    'execution_token', token, 'provider_refund_id', r.provider_refund_id,
    'provider_idempotency_key', r.provider_idempotency_key,
    'gateway_id', r.gateway_id, 'gateway_mode', r.gateway_mode);
END;$$;
REVOKE ALL ON FUNCTION public.prepare_refund_status_refresh(uuid, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_refund_status_refresh(uuid, uuid, text, text, text) TO service_role;

-- 7. finalize_refund_status_refresh
CREATE OR REPLACE FUNCTION public.finalize_refund_status_refresh(
  _refund_id uuid, _attempt_id uuid, _execution_token text,
  _normalized_status text, _provider_refund_id text, _amount numeric, _currency text,
  _gateway_mode payment_gateway_mode, _is_final boolean, _safe_error_code text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.recharge_refunds%ROWTYPE; a public.recharge_refund_attempts%ROWTYPE;
  policy public.refund_retry_policies%ROWTYPE; attempt_status text; next_check timestamptz;
BEGIN
  IF _normalized_status NOT IN ('succeeded','failed','pending','unknown','cancelled') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'INVALID_STATUS');
  END IF;
  SELECT * INTO r FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'REFUND_NOT_FOUND'); END IF;
  SELECT * INTO a FROM public.recharge_refund_attempts WHERE id = _attempt_id AND refund_id = _refund_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'ATTEMPT_NOT_FOUND'); END IF;
  IF a.finalized_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'outcome', a.status);
  END IF;
  IF a.execution_token_hash IS DISTINCT FROM encode(digest(_execution_token, 'sha256'), 'hex') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'EXECUTION_TOKEN_INVALID');
  END IF;
  IF r.gateway_mode IS NOT NULL AND r.gateway_mode <> _gateway_mode THEN
    UPDATE public.recharge_refund_attempts SET status='wrong_mode', finished_at=now(), finalized_at=now(),
      failure_code='GATEWAY_MODE_MISMATCH', safe_error='gateway mode mismatch' WHERE id=_attempt_id;
    RETURN jsonb_build_object('ok', false, 'error', 'GATEWAY_MODE_MISMATCH');
  END IF;
  IF r.provider_refund_id IS NOT NULL AND _provider_refund_id IS NOT NULL AND r.provider_refund_id <> _provider_refund_id THEN
    UPDATE public.recharge_refund_attempts SET status='unknown_payment', finished_at=now(), finalized_at=now(),
      failure_code='PROVIDER_ID_MISMATCH', safe_error='provider refund id mismatch' WHERE id=_attempt_id;
    RETURN jsonb_build_object('ok', false, 'error', 'PROVIDER_ID_MISMATCH');
  END IF;
  IF _amount IS NOT NULL AND r.amount IS NOT NULL AND round(r.amount, 4) <> round(_amount, 4) THEN
    UPDATE public.recharge_refund_attempts SET status='wrong_amount', finished_at=now(), finalized_at=now(),
      failure_code='AMOUNT_MISMATCH', safe_error='refund amount mismatch' WHERE id=_attempt_id;
    UPDATE public.recharge_refunds SET status='manual_review'::refund_status, failure_code='AMOUNT_MISMATCH', updated_at=now() WHERE id=_refund_id;
    RETURN jsonb_build_object('ok', false, 'error', 'AMOUNT_MISMATCH');
  END IF;
  IF r.status IN ('completed','partially_completed','failed','rejected','cancelled') THEN
    UPDATE public.recharge_refund_attempts SET status=COALESCE(NULLIF(_normalized_status,'unknown'),'pending'),
      finished_at=now(), finalized_at=now(), safe_error='terminal state; no-op' WHERE id=_attempt_id;
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'outcome', 'terminal_noop');
  END IF;
  attempt_status := _normalized_status;
  IF attempt_status = 'unknown' THEN attempt_status := 'unknown_payment'; END IF;
  UPDATE public.recharge_refund_attempts
     SET status=attempt_status, finished_at=now(), finalized_at=now(),
         provider_refund_id=COALESCE(_provider_refund_id, a.provider_refund_id),
         failure_code=_safe_error_code, safe_error=_safe_error_code
   WHERE id=_attempt_id;
  IF _normalized_status = 'succeeded' AND _is_final THEN
    UPDATE public.recharge_refunds
       SET status='gateway_confirmed'::refund_status,
           provider_refund_id=COALESCE(_provider_refund_id, r.provider_refund_id),
           polling_owner=NULL, polling_lease_expires_at=NULL, next_status_check_at=NULL,
           gateway_execution_state='succeeded', updated_at=now()
     WHERE id=_refund_id;
    RETURN jsonb_build_object('ok', true, 'outcome', 'gateway_confirmed');
  END IF;
  IF _normalized_status IN ('failed','cancelled') AND _is_final THEN
    UPDATE public.recharge_refunds
       SET status='manual_review'::refund_status,
           failure_code=COALESCE(_safe_error_code, 'gateway_'||_normalized_status),
           polling_owner=NULL, polling_lease_expires_at=NULL, next_status_check_at=NULL,
           gateway_execution_state='failed_definitive', updated_at=now()
     WHERE id=_refund_id;
    RETURN jsonb_build_object('ok', true, 'outcome', 'manual_review');
  END IF;
  SELECT * INTO policy FROM public._lookup_refund_retry_policy(r.gateway_id, r.gateway_mode);
  next_check := now() + make_interval(secs => policy.polling_interval_seconds);
  UPDATE public.recharge_refunds
     SET next_status_check_at=next_check, polling_owner=NULL, polling_lease_expires_at=NULL,
         gateway_execution_state = CASE WHEN _normalized_status='unknown' THEN 'unknown_result' ELSE 'pending_confirmation' END,
         updated_at=now()
   WHERE id=_refund_id;
  RETURN jsonb_build_object('ok', true, 'outcome', 'still_processing', 'next_check_at', next_check);
END;$$;
REVOKE ALL ON FUNCTION public.finalize_refund_status_refresh(uuid, uuid, text, text, text, numeric, text, payment_gateway_mode, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_refund_status_refresh(uuid, uuid, text, text, text, numeric, text, payment_gateway_mode, boolean, text) TO service_role;

-- 8. prepare_refund_retry
CREATE OR REPLACE FUNCTION public.prepare_refund_retry(
  _refund_id uuid, _triggered_by uuid, _reason text, _request_idempotency_key text, _override_limit boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.recharge_refunds%ROWTYPE; policy public.refund_retry_policies%ROWTYPE;
  last_attempt public.recharge_refund_attempts%ROWTYPE;
  eligible_states text[] := ARRAY['never_sent','failed_retryable_before_send','failed_definitive'];
  now_ts timestamptz := now(); backoff_secs integer;
BEGIN
  IF _reason IS NULL OR length(trim(_reason)) < 5 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'REASON_TOO_SHORT');
  END IF;
  SELECT * INTO r FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'REFUND_NOT_FOUND'); END IF;
  IF r.status IN ('completed','partially_completed','gateway_confirmed','reversing_wallet','cancelled','rejected') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'REFUND_ALREADY_COMPLETED');
  END IF;
  IF r.polling_owner IS NOT NULL AND r.polling_lease_expires_at > now_ts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'REFUND_ALREADY_PROCESSING');
  END IF;
  IF r.gateway_execution_state IN ('unknown_result','pending_confirmation') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'REFUND_STATUS_REFRESH_REQUIRED');
  END IF;
  IF r.gateway_execution_state IS NOT NULL AND NOT (r.gateway_execution_state = ANY (eligible_states)) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'REFUND_NOT_RETRYABLE', 'state', r.gateway_execution_state);
  END IF;
  SELECT * INTO policy FROM public._lookup_refund_retry_policy(r.gateway_id, r.gateway_mode);
  IF r.retry_attempt_count >= policy.max_create_attempts AND NOT _override_limit THEN
    RETURN jsonb_build_object('ok', false, 'error', 'RETRY_LIMIT_REACHED');
  END IF;
  IF r.last_retry_at IS NOT NULL THEN
    backoff_secs := LEAST(policy.max_backoff_seconds,
      (policy.initial_backoff_seconds * power(policy.backoff_multiplier, GREATEST(r.retry_attempt_count - 1, 0)))::int);
    IF now_ts < r.last_retry_at + make_interval(secs => backoff_secs) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'RETRY_BACKOFF_ACTIVE',
        'next_available_at', r.last_retry_at + make_interval(secs => backoff_secs));
    END IF;
  END IF;
  SELECT * INTO last_attempt FROM public.recharge_refund_attempts
   WHERE refund_id = _refund_id ORDER BY attempt_number DESC LIMIT 1;
  IF last_attempt.id IS NOT NULL AND last_attempt.status = 'succeeded' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'PROVIDER_REFUND_ALREADY_CONFIRMED');
  END IF;
  UPDATE public.recharge_refunds SET retry_attempt_count = retry_attempt_count + 1, last_retry_at = now_ts, updated_at = now_ts WHERE id = _refund_id;
  RETURN jsonb_build_object('ok', true,
    'provider_idempotency_key', r.provider_idempotency_key,
    'request_idempotency_key', _request_idempotency_key,
    'gateway_id', r.gateway_id, 'gateway_mode', r.gateway_mode,
    'retry_attempt_count', r.retry_attempt_count + 1);
END;$$;
REVOKE ALL ON FUNCTION public.prepare_refund_retry(uuid, uuid, text, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_refund_retry(uuid, uuid, text, text, boolean) TO service_role;
