
-- 5C-2b.3 · Refund Webhook Processor: schema + RPCs.
-- Extends payment_webhooks with refund-domain columns and installs
-- service-role-only RPCs used by the /api/public webhook endpoint and
-- the internal Orchestrator. No new tables; all data lives in the
-- existing payment_webhooks / payment_webhook_attempts / recharge_refunds.

-- 1) Extend payment_webhooks with refund domain columns (idempotent).
ALTER TABLE public.payment_webhooks
  ADD COLUMN IF NOT EXISTS event_domain               text  NOT NULL DEFAULT 'payment',
  ADD COLUMN IF NOT EXISTS refund_id                  uuid  REFERENCES public.recharge_refunds(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS refund_reference           text,
  ADD COLUMN IF NOT EXISTS provider_refund_id         text,
  ADD COLUMN IF NOT EXISTS original_provider_payment_id text,
  ADD COLUMN IF NOT EXISTS normalized_event_type      text,
  ADD COLUMN IF NOT EXISTS signature_verified         boolean,
  ADD COLUMN IF NOT EXISTS timestamp_verified         boolean,
  ADD COLUMN IF NOT EXISTS replay_check_passed        boolean,
  ADD COLUMN IF NOT EXISTS validation_status          text,
  ADD COLUMN IF NOT EXISTS payload_redacted           jsonb,
  ADD COLUMN IF NOT EXISTS payload_hash               text,
  ADD COLUMN IF NOT EXISTS failure_code               text,
  ADD COLUMN IF NOT EXISTS safe_error                 text,
  ADD COLUMN IF NOT EXISTS marked_as_duplicate        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS event_amount               numeric(18,4),
  ADD COLUMN IF NOT EXISTS event_currency             text,
  ADD COLUMN IF NOT EXISTS occurred_at                timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payment_webhooks_event_domain_chk') THEN
    ALTER TABLE public.payment_webhooks
      ADD CONSTRAINT payment_webhooks_event_domain_chk
      CHECK (event_domain IN ('payment','refund'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payment_webhooks_validation_status_chk') THEN
    ALTER TABLE public.payment_webhooks
      ADD CONSTRAINT payment_webhooks_validation_status_chk
      CHECK (validation_status IS NULL OR validation_status IN (
        'pending','accepted','rejected','duplicate','manual_review'
      ));
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_webhooks_refund
  ON public.payment_webhooks (refund_id, received_at DESC)
  WHERE refund_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_webhooks_domain_state
  ON public.payment_webhooks (event_domain, processing_state, received_at);

-- Restrictive policies: outbox is service-only; refund domain rows must
-- never be UPDATE/DELETE-able by authenticated. (Read policy already exists.)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='payment_webhooks' AND policyname='pw_no_write_auth') THEN
    CREATE POLICY "pw_no_write_auth" ON public.payment_webhooks
      AS RESTRICTIVE FOR ALL TO authenticated
      USING (false) WITH CHECK (false);
  END IF;
  -- keep read policy from prior migration (wh_read)
END$$;

-- 2) Permissions surface (for later UI).
INSERT INTO public.permissions (key, module, label_ar, label_en)
VALUES
  ('recharge_refunds.webhook.replay', 'refunds', 'إعادة معالجة Webhook', 'Replay refund webhook')
ON CONFLICT (key) DO NOTHING;

-- 3) register_refund_webhook_event — service-only insertion / idempotent replay.
CREATE OR REPLACE FUNCTION public.register_refund_webhook_event(
  _gateway_id                 uuid,
  _gateway_mode               payment_gateway_mode,
  _provider_event_id          text,
  _normalized_event_type      text,
  _refund_reference           text,
  _provider_refund_id         text,
  _original_provider_payment_id text,
  _amount                     numeric,
  _currency                   text,
  _occurred_at                timestamptz,
  _payload_hash               text,
  _payload_redacted           jsonb,
  _signature_verified         boolean,
  _timestamp_verified         boolean,
  _replay_check_passed        boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_webhook_id uuid;
  v_existing   public.payment_webhooks%ROWTYPE;
  v_refund_id  uuid;
BEGIN
  -- Idempotent replay on composite (gateway_id, gateway_mode, provider_event_id)
  IF _provider_event_id IS NOT NULL THEN
    SELECT * INTO v_existing
      FROM public.payment_webhooks
     WHERE gateway_id = _gateway_id
       AND gateway_mode = _gateway_mode
       AND provider_event_id = _provider_event_id
     LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'webhook_id', v_existing.id,
        'duplicate', true,
        'processing_state', v_existing.processing_state,
        'refund_id', v_existing.refund_id
      );
    END IF;
  END IF;

  -- Try to link to refund (trusted lookup: provider_refund_id → refund_reference)
  IF _provider_refund_id IS NOT NULL THEN
    SELECT id INTO v_refund_id
      FROM public.recharge_refunds
     WHERE provider_refund_id = _provider_refund_id
       AND gateway_id = _gateway_id
       AND (gateway_mode = _gateway_mode OR gateway_mode IS NULL)
     LIMIT 1;
  END IF;
  IF v_refund_id IS NULL AND _refund_reference IS NOT NULL THEN
    SELECT id INTO v_refund_id
      FROM public.recharge_refunds
     WHERE refund_reference = _refund_reference
       AND (gateway_id = _gateway_id OR gateway_id IS NULL)
     LIMIT 1;
  END IF;

  INSERT INTO public.payment_webhooks(
    gateway_id, gateway_mode, provider_event_id, event_type,
    signature, signature_valid, raw_payload,
    event_domain, refund_id, refund_reference, provider_refund_id,
    original_provider_payment_id, normalized_event_type,
    signature_verified, timestamp_verified, replay_check_passed,
    validation_status, payload_redacted, payload_hash,
    event_amount, event_currency, occurred_at,
    processing_state
  ) VALUES (
    _gateway_id, _gateway_mode, _provider_event_id, coalesce(_normalized_event_type,'refund.unknown'),
    NULL, _signature_verified, _payload_redacted,
    'refund', v_refund_id, _refund_reference, _provider_refund_id,
    _original_provider_payment_id, _normalized_event_type,
    _signature_verified, _timestamp_verified, _replay_check_passed,
    'pending', _payload_redacted, _payload_hash,
    _amount, _currency, _occurred_at,
    'received'
  ) RETURNING id INTO v_webhook_id;

  RETURN jsonb_build_object(
    'webhook_id', v_webhook_id,
    'duplicate', false,
    'processing_state', 'received',
    'refund_id', v_refund_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.register_refund_webhook_event(uuid,payment_gateway_mode,text,text,text,text,text,numeric,text,timestamptz,text,jsonb,boolean,boolean,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_refund_webhook_event(uuid,payment_gateway_mode,text,text,text,text,text,numeric,text,timestamptz,text,jsonb,boolean,boolean,boolean) TO service_role;

-- 4) claim_refund_webhook_for_processing — locks a row for exactly-once processing.
CREATE OR REPLACE FUNCTION public.claim_refund_webhook_for_processing(
  _webhook_id  uuid,
  _owner       text,
  _stale_after interval DEFAULT interval '5 minutes'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v public.payment_webhooks%ROWTYPE;
  v_attempt_id uuid;
  v_next_no int;
BEGIN
  SELECT * INTO v FROM public.payment_webhooks WHERE id = _webhook_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'WEBHOOK_NOT_FOUND';
  END IF;

  IF v.processing_state IN ('processed','skipped') THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'ALREADY_TERMINAL', 'state', v.processing_state);
  END IF;

  IF v.processing_state = 'processing'
     AND v.processing_started_at IS NOT NULL
     AND v.processing_started_at > now() - _stale_after THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'WEBHOOK_ALREADY_PROCESSING');
  END IF;

  UPDATE public.payment_webhooks
     SET processing_state       = 'processing',
         processing_owner       = _owner,
         processing_started_at  = now(),
         retry_count            = retry_count + 1
   WHERE id = _webhook_id;

  SELECT coalesce(max(attempt_number),0)+1 INTO v_next_no
    FROM public.payment_webhook_attempts WHERE webhook_id = _webhook_id;

  INSERT INTO public.payment_webhook_attempts(
    webhook_id, attempt_number, trigger_type, started_at, result
  ) VALUES (
    _webhook_id, v_next_no,
    CASE WHEN v.processing_state = 'processing' THEN 'stale_recovery' ELSE 'initial_processing' END,
    now(), 'processing'
  ) RETURNING id INTO v_attempt_id;

  RETURN jsonb_build_object(
    'claimed', true,
    'attempt_id', v_attempt_id,
    'attempt_number', v_next_no,
    'refund_id', v.refund_id,
    'normalized_event_type', v.normalized_event_type,
    'signature_verified', v.signature_verified,
    'timestamp_verified', v.timestamp_verified,
    'replay_check_passed', v.replay_check_passed,
    'provider_refund_id', v.provider_refund_id,
    'original_provider_payment_id', v.original_provider_payment_id,
    'event_amount', v.event_amount,
    'event_currency', v.event_currency,
    'gateway_id', v.gateway_id,
    'gateway_mode', v.gateway_mode
  );
END;
$$;

REVOKE ALL ON FUNCTION public.claim_refund_webhook_for_processing(uuid,text,interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_refund_webhook_for_processing(uuid,text,interval) TO service_role;

-- 5) reclaim_stale_refund_webhooks — recovery routine.
CREATE OR REPLACE FUNCTION public.reclaim_stale_refund_webhooks(_older_than interval DEFAULT interval '10 minutes')
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v int;
BEGIN
  WITH stale AS (
    UPDATE public.payment_webhooks
       SET processing_state='received', processing_owner=NULL, processing_started_at=NULL
     WHERE event_domain='refund'
       AND processing_state='processing'
       AND processing_started_at < now() - _older_than
     RETURNING id
  ) SELECT count(*) INTO v FROM stale;
  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.reclaim_stale_refund_webhooks(interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reclaim_stale_refund_webhooks(interval) TO service_role;

-- 6) mark_refund_webhook_terminal — closes attempt + webhook.
CREATE OR REPLACE FUNCTION public.mark_refund_webhook_terminal(
  _webhook_id   uuid,
  _attempt_id   uuid,
  _final_state  text,               -- processed | failed | skipped
  _validation   text,               -- accepted | rejected | duplicate | manual_review
  _failure_code text,
  _safe_error   text,
  _marked_duplicate boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF _final_state NOT IN ('processed','failed','skipped') THEN
    RAISE EXCEPTION 'INVALID_FINAL_STATE:%', _final_state;
  END IF;

  UPDATE public.payment_webhook_attempts
     SET finished_at = now(),
         result      = CASE _final_state WHEN 'processed' THEN 'success'
                                         WHEN 'skipped'   THEN 'skipped'
                                         ELSE 'failed' END,
         failure_code = _failure_code,
         safe_error   = _safe_error
   WHERE id = _attempt_id;

  UPDATE public.payment_webhooks
     SET processing_state    = _final_state,
         processed           = (_final_state = 'processed'),
         processed_at        = CASE WHEN _final_state <> 'received' THEN now() ELSE processed_at END,
         validation_status   = coalesce(_validation, validation_status),
         failure_code        = coalesce(_failure_code, failure_code),
         safe_error          = coalesce(_safe_error, safe_error),
         marked_as_duplicate = marked_as_duplicate OR _marked_duplicate,
         processing_owner    = NULL
   WHERE id = _webhook_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_refund_webhook_terminal(uuid,uuid,text,text,text,text,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_refund_webhook_terminal(uuid,uuid,text,text,text,text,boolean) TO service_role;

-- 7) apply_refund_webhook_event — state-machine transition for a claimed webhook.
--    Handles: succeeded, failed, pending, duplicate, invalid_amount,
--             invalid_currency, invalid_mode, unknown_payment, unknown/timeout.
CREATE OR REPLACE FUNCTION public.apply_refund_webhook_event(
  _webhook_id uuid,
  _attempt_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  w  public.payment_webhooks%ROWTYPE;
  r  public.recharge_refunds%ROWTYPE;
  v_next_status refund_status;
  v_result jsonb := jsonb_build_object();
  v_failure text;
  v_safe    text;
BEGIN
  SELECT * INTO w FROM public.payment_webhooks WHERE id=_webhook_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WEBHOOK_NOT_FOUND'; END IF;

  IF NOT coalesce(w.signature_verified,false) THEN
    RETURN jsonb_build_object('outcome','rejected','failure_code','WEBHOOK_SIGNATURE_INVALID');
  END IF;
  IF NOT coalesce(w.timestamp_verified,false) THEN
    RETURN jsonb_build_object('outcome','rejected','failure_code','WEBHOOK_TIMESTAMP_EXPIRED');
  END IF;
  IF NOT coalesce(w.replay_check_passed,true) THEN
    RETURN jsonb_build_object('outcome','rejected','failure_code','WEBHOOK_REPLAY_DETECTED');
  END IF;

  -- Duplicate normalized event
  IF w.normalized_event_type = 'refund.duplicate' THEN
    RETURN jsonb_build_object('outcome','duplicate','marked_duplicate',true);
  END IF;

  -- Locate refund
  IF w.refund_id IS NULL THEN
    RETURN jsonb_build_object('outcome','manual_review','failure_code','REFUND_NOT_FOUND');
  END IF;

  SELECT * INTO r FROM public.recharge_refunds WHERE id=w.refund_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('outcome','manual_review','failure_code','REFUND_NOT_FOUND');
  END IF;

  -- Validation matrix
  IF w.normalized_event_type IN ('refund.wrong_amount','refund.wrong_currency','refund.wrong_mode','refund.unknown_payment') THEN
    v_failure := CASE w.normalized_event_type
      WHEN 'refund.wrong_amount'   THEN 'REFUND_AMOUNT_MISMATCH'
      WHEN 'refund.wrong_currency' THEN 'REFUND_CURRENCY_MISMATCH'
      WHEN 'refund.wrong_mode'     THEN 'REFUND_GATEWAY_MODE_MISMATCH'
      ELSE 'ORIGINAL_PAYMENT_NOT_FOUND'
    END;
    UPDATE public.recharge_refunds
       SET status='manual_review', failure_code=v_failure, failure_reason=w.normalized_event_type
     WHERE id=r.id;
    RETURN jsonb_build_object('outcome','manual_review','failure_code',v_failure);
  END IF;

  IF w.normalized_event_type IN ('refund.timeout','refund.unknown') THEN
    -- keep as processing_gateway; do NOT reverse wallet
    RETURN jsonb_build_object('outcome','pending','failure_code','REFUND_STATUS_UNKNOWN');
  END IF;

  IF w.normalized_event_type = 'refund.pending' THEN
    IF r.status NOT IN ('processing_gateway','gateway_confirmed','reversing_wallet','completed','partially_completed') THEN
      UPDATE public.recharge_refunds
         SET status='processing_gateway',
             provider_refund_id=coalesce(r.provider_refund_id, w.provider_refund_id)
       WHERE id=r.id;
    END IF;
    RETURN jsonb_build_object('outcome','pending');
  END IF;

  IF w.normalized_event_type = 'refund.failed' THEN
    IF r.status IN ('processing_gateway','gateway_confirmed') THEN
      UPDATE public.recharge_refunds
         SET status='failed',
             failure_code='GATEWAY_DECLINED',
             failure_reason=w.normalized_event_type,
             provider_refund_id=coalesce(r.provider_refund_id, w.provider_refund_id)
       WHERE id=r.id;
    END IF;
    RETURN jsonb_build_object('outcome','failed');
  END IF;

  -- refund.succeeded
  IF w.normalized_event_type = 'refund.succeeded' THEN
    -- Amount check (loose): must not exceed approved_amount when both known
    IF r.approved_amount IS NOT NULL AND w.event_amount IS NOT NULL
       AND w.event_amount::numeric > r.approved_amount::numeric THEN
      UPDATE public.recharge_refunds
         SET status='manual_review', failure_code='REFUND_AMOUNT_MISMATCH'
       WHERE id=r.id;
      RETURN jsonb_build_object('outcome','manual_review','failure_code','REFUND_AMOUNT_MISMATCH');
    END IF;

    IF r.status IN ('completed','partially_completed') THEN
      RETURN jsonb_build_object('outcome','idempotent_replay','status',r.status);
    END IF;

    IF r.status IN ('processing_gateway') THEN
      UPDATE public.recharge_refunds
         SET status='gateway_confirmed',
             provider_refund_id=coalesce(r.provider_refund_id, w.provider_refund_id)
       WHERE id=r.id;
      RETURN jsonb_build_object('outcome','gateway_confirmed','trigger_wallet_reversal',true);
    ELSIF r.status IN ('gateway_confirmed','reversing_wallet') THEN
      RETURN jsonb_build_object('outcome','gateway_confirmed','trigger_wallet_reversal',true);
    ELSE
      -- Invalid state to receive a success event
      RETURN jsonb_build_object('outcome','manual_review','failure_code','REFUND_INVALID_TRANSITION');
    END IF;
  END IF;

  RETURN jsonb_build_object('outcome','manual_review','failure_code','REFUND_UNHANDLED_EVENT');
END;
$$;

REVOKE ALL ON FUNCTION public.apply_refund_webhook_event(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_refund_webhook_event(uuid,uuid) TO service_role;

-- 8) process_confirmed_recharge_refund — Orchestrator that drives
--    gateway_confirmed → reversing_wallet → completed / partially / manual_review.
--    Delegates the actual double-entry to _apply_recharge_refund_wallet_reversal.
CREATE OR REPLACE FUNCTION public.process_confirmed_recharge_refund(_refund_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.recharge_refunds%ROWTYPE;
  v_res jsonb;
  v_have_ledger boolean;
BEGIN
  SELECT * INTO r FROM public.recharge_refunds WHERE id=_refund_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;

  IF r.status NOT IN ('gateway_confirmed','reversing_wallet') THEN
    RETURN jsonb_build_object('ok',false,'reason','INVALID_STATE','status',r.status);
  END IF;

  -- Idempotency: if ledger pair already exists, mark completed and return.
  SELECT EXISTS (
    SELECT 1 FROM public.wallet_ledger WHERE refund_id = r.id
  ) INTO v_have_ledger;

  IF r.status = 'gateway_confirmed' THEN
    UPDATE public.recharge_refunds SET status='reversing_wallet' WHERE id=r.id;
  END IF;

  IF NOT v_have_ledger THEN
    -- Delegate to existing double-entry wallet reversal helper.
    BEGIN
      PERFORM public._apply_recharge_refund_wallet_reversal(r.id);
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.recharge_refunds
         SET status='manual_review',
             failure_code='WALLET_REVERSAL_ERROR',
             failure_reason=SQLERRM
       WHERE id=r.id;
      RETURN jsonb_build_object('ok',false,'reason','WALLET_REVERSAL_ERROR');
    END;
  END IF;

  -- Re-read after reversal
  SELECT * INTO r FROM public.recharge_refunds WHERE id=r.id FOR UPDATE;

  IF (coalesce(r.unrecovered_coin_amount,0) + coalesce(r.unrecovered_bonus_amount,0)) = 0 THEN
    UPDATE public.recharge_refunds SET status='completed' WHERE id=r.id AND status='reversing_wallet';
    v_res := jsonb_build_object('ok',true,'outcome','completed');
  ELSIF coalesce(r.coins_actually_reversed,0) + coalesce(r.bonus_actually_reversed,0) > 0 THEN
    UPDATE public.recharge_refunds SET status='partially_completed' WHERE id=r.id AND status='reversing_wallet';
    v_res := jsonb_build_object('ok',true,'outcome','partially_completed');
  ELSE
    UPDATE public.recharge_refunds SET status='manual_review',
           failure_code=coalesce(r.failure_code,'INSUFFICIENT_BALANCE') WHERE id=r.id AND status='reversing_wallet';
    v_res := jsonb_build_object('ok',true,'outcome','manual_review');
  END IF;

  -- Outbox: emit idempotent completion event.
  INSERT INTO public.transaction_message_outbox(
    event_type, transaction_type, transaction_id, recipient_user_id,
    safe_payload, idempotency_key
  )
  SELECT
    CASE (v_res->>'outcome')
      WHEN 'completed' THEN 'refund_completed'
      WHEN 'partially_completed' THEN 'refund_partially_completed'
      ELSE 'refund_manual_review'
    END,
    'recharge_refund', r.id, r.user_id,
    jsonb_build_object(
      'refund_reference', r.refund_reference,
      'approved_amount', r.approved_amount,
      'currency', r.currency_code,
      'outcome', v_res->>'outcome'
    ),
    'refund:'||r.id::text||':'||(v_res->>'outcome')
  WHERE r.user_id IS NOT NULL
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN v_res;
END;
$$;

REVOKE ALL ON FUNCTION public.process_confirmed_recharge_refund(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_confirmed_recharge_refund(uuid) TO service_role;

-- 9) Audit-log helper used by orchestrator (safe metadata only).
CREATE OR REPLACE FUNCTION public.log_refund_webhook_audit(
  _refund_id uuid, _webhook_id uuid, _action text, _metadata jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
BEGIN
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (NULL, _action, 'recharge_refund',
          coalesce(_refund_id::text, _webhook_id::text),
          coalesce(_metadata,'{}'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.log_refund_webhook_audit(uuid,uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.log_refund_webhook_audit(uuid,uuid,text,jsonb) TO service_role;
