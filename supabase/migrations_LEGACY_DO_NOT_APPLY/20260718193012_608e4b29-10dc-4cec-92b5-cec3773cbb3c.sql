
-- =====================================================================
-- Phase 5C-1: Refund Schema + State Machine
-- =====================================================================

-- ---------- Enums ------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.refund_status AS ENUM (
    'requested','pending_review','pending_second_review','approved',
    'processing_gateway','gateway_confirmed','reversing_wallet',
    'manual_review','completed','partially_completed','failed',
    'rejected','cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.refund_type AS ENUM ('full','partial');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.refund_scope AS ENUM (
    'money_only','money_and_base_coins','money_and_all_coins',
    'administrative_compensation','technical_failure'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------- Extend recharge_refunds -----------------------------------
ALTER TABLE public.recharge_refunds
  ADD COLUMN IF NOT EXISTS gateway_id                    uuid REFERENCES public.payment_gateways(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS payment_method_id             uuid REFERENCES public.payment_methods(id)  ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS original_payment_reference    text,
  ADD COLUMN IF NOT EXISTS provider_refund_id            text,
  ADD COLUMN IF NOT EXISTS user_id                       uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS refund_type_new               public.refund_type,
  ADD COLUMN IF NOT EXISTS refund_scope                  public.refund_scope,
  ADD COLUMN IF NOT EXISTS requested_amount              numeric(18,4),
  ADD COLUMN IF NOT EXISTS approved_amount               numeric(18,4),
  ADD COLUMN IF NOT EXISTS base_coins_to_reverse         bigint  DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bonus_coins_to_reverse        bigint  DEFAULT 0,
  ADD COLUMN IF NOT EXISTS coins_actually_reversed       bigint  DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bonus_actually_reversed       bigint  DEFAULT 0,
  ADD COLUMN IF NOT EXISTS unrecovered_coin_amount       bigint  DEFAULT 0,
  ADD COLUMN IF NOT EXISTS unrecovered_bonus_amount      bigint  DEFAULT 0,
  ADD COLUMN IF NOT EXISTS requires_coin_reversal        boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS requires_second_approval      boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS threshold_rule_id             uuid,
  ADD COLUMN IF NOT EXISTS first_reviewed_by             uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS first_reviewed_at             timestamptz,
  ADD COLUMN IF NOT EXISTS second_reviewed_by            uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS second_reviewed_at            timestamptz,
  ADD COLUMN IF NOT EXISTS executed_by                   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS failure_code                  text,
  ADD COLUMN IF NOT EXISTS failure_reason                text,
  ADD COLUMN IF NOT EXISTS idempotency_key               text,
  ADD COLUMN IF NOT EXISTS bonus_policy_snapshot         text,
  ADD COLUMN IF NOT EXISTS status_new                    public.refund_status;

-- Backfill status_new and refund_type_new from legacy columns.
UPDATE public.recharge_refunds
   SET status_new = CASE status
        WHEN 'requested'             THEN 'requested'::public.refund_status
        WHEN 'pending_review'        THEN 'pending_review'::public.refund_status
        WHEN 'pending_second_review' THEN 'pending_second_review'::public.refund_status
        WHEN 'processing'            THEN 'processing_gateway'::public.refund_status
        WHEN 'completed'             THEN 'completed'::public.refund_status
        WHEN 'failed'                THEN 'failed'::public.refund_status
        WHEN 'rejected'              THEN 'rejected'::public.refund_status
        WHEN 'cancelled'             THEN 'cancelled'::public.refund_status
        ELSE 'requested'::public.refund_status
   END
 WHERE status_new IS NULL;

UPDATE public.recharge_refunds
   SET refund_type_new = CASE kind
        WHEN 'full'    THEN 'full'::public.refund_type
        WHEN 'partial' THEN 'partial'::public.refund_type
        ELSE 'full'::public.refund_type
   END
 WHERE refund_type_new IS NULL;

UPDATE public.recharge_refunds r
   SET user_id = rr.user_id
  FROM public.recharge_requests rr
 WHERE r.request_id = rr.id AND r.user_id IS NULL;

ALTER TABLE public.recharge_refunds DROP CONSTRAINT IF EXISTS recharge_refunds_status_chk;
ALTER TABLE public.recharge_refunds DROP CONSTRAINT IF EXISTS recharge_refunds_kind_chk;

ALTER TABLE public.recharge_refunds DROP COLUMN status;
ALTER TABLE public.recharge_refunds RENAME COLUMN status_new TO status;
ALTER TABLE public.recharge_refunds ALTER COLUMN status SET NOT NULL;
ALTER TABLE public.recharge_refunds ALTER COLUMN status SET DEFAULT 'requested'::public.refund_status;

ALTER TABLE public.recharge_refunds DROP COLUMN kind;
ALTER TABLE public.recharge_refunds RENAME COLUMN refund_type_new TO refund_type;
ALTER TABLE public.recharge_refunds ALTER COLUMN refund_type SET NOT NULL;
ALTER TABLE public.recharge_refunds ALTER COLUMN refund_type SET DEFAULT 'full'::public.refund_type;

CREATE UNIQUE INDEX IF NOT EXISTS recharge_refunds_idempotency_key_uidx
  ON public.recharge_refunds (idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS recharge_refunds_user_status_idx
  ON public.recharge_refunds (user_id, status);
CREATE INDEX IF NOT EXISTS recharge_refunds_status_requested_idx
  ON public.recharge_refunds (status, requested_at DESC);

-- Two-eyes integrity: second reviewer must differ from first reviewer.
ALTER TABLE public.recharge_refunds DROP CONSTRAINT IF EXISTS recharge_refunds_two_eyes_chk;
ALTER TABLE public.recharge_refunds
  ADD CONSTRAINT recharge_refunds_two_eyes_chk
  CHECK (
    second_reviewed_by IS NULL
    OR first_reviewed_by IS NULL
    OR second_reviewed_by <> first_reviewed_by
  );

-- ---------- State machine ---------------------------------------------
CREATE OR REPLACE FUNCTION public._refund_transition_ok(
  p_from public.refund_status,
  p_to   public.refund_status
) RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT (p_from, p_to) IN (
    ('requested','pending_review'),
    ('requested','cancelled'),
    ('pending_review','pending_second_review'),
    ('pending_review','approved'),
    ('pending_review','rejected'),
    ('pending_review','cancelled'),
    ('pending_second_review','approved'),
    ('pending_second_review','rejected'),
    ('pending_second_review','cancelled'),
    ('approved','processing_gateway'),
    ('approved','cancelled'),
    ('processing_gateway','gateway_confirmed'),
    ('processing_gateway','failed'),
    ('processing_gateway','manual_review'),
    ('gateway_confirmed','reversing_wallet'),
    ('gateway_confirmed','completed'),
    ('reversing_wallet','completed'),
    ('reversing_wallet','partially_completed'),
    ('reversing_wallet','manual_review'),
    ('manual_review','reversing_wallet'),
    ('manual_review','completed'),
    ('manual_review','partially_completed'),
    ('manual_review','failed'),
    ('failed','manual_review'),
    ('failed','processing_gateway')
  );
$$;

REVOKE EXECUTE ON FUNCTION public._refund_transition_ok(public.refund_status, public.refund_status) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public._refund_transition_ok(public.refund_status, public.refund_status) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.tg_refund_state_machine()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT public._refund_transition_ok(OLD.status, NEW.status) THEN
      RAISE EXCEPTION 'REFUND_INVALID_TRANSITION: % -> %', OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refund_state_machine ON public.recharge_refunds;
CREATE TRIGGER trg_refund_state_machine
  BEFORE UPDATE ON public.recharge_refunds
  FOR EACH ROW EXECUTE FUNCTION public.tg_refund_state_machine();

-- ---------- Permissions (schema: key, module, label_ar, label_en, description) --
INSERT INTO public.permissions (key, module, label_ar, label_en, description) VALUES
  ('recharge_refunds.review',                       'refunds','مراجعة طلب استرداد',              'Review refund requests',                         'Review refund requests'),
  ('recharge_refunds.second_approve',               'refunds','موافقة ثانية على الاسترداد',      'Second approve refund',                          'Provide second approval for high-value refunds'),
  ('recharge_refunds.cancel',                       'refunds','إلغاء طلب استرداد',                'Cancel refund request',                          'Cancel a refund before execution'),
  ('recharge_refunds.reject',                       'refunds','رفض طلب استرداد',                  'Reject refund request',                          'Reject a refund request'),
  ('recharge_refunds.override_insufficient_balance','refunds','تجاوز نقص الرصيد عند الاسترداد',  'Override insufficient balance on refund',        'Approve refund when wallet balance is insufficient'),
  ('recharge_refunds.manual_review',                'refunds','تحويل استرداد للمراجعة اليدوية',  'Move refund to manual review',                   'Move a refund into or out of manual review'),
  ('recharge_refunds.retry_gateway',                'refunds','إعادة محاولة الاسترداد في البوابة','Retry gateway refund',                         'Retry gateway refund after failure')
ON CONFLICT (key) DO NOTHING;

-- Grant to admin_role enum values that exist today: super_admin, admin, finance, auditor.
INSERT INTO public.role_permissions (role, permission_key)
SELECT r.role, p.key
  FROM (VALUES ('super_admin'::admin_role),('admin'::admin_role),('finance'::admin_role)) AS r(role)
  CROSS JOIN (VALUES
    ('recharge_refunds.read'),('recharge_refunds.request'),('recharge_refunds.review'),
    ('recharge_refunds.approve'),('recharge_refunds.second_approve'),('recharge_refunds.execute'),
    ('recharge_refunds.reject'),('recharge_refunds.cancel'),('recharge_refunds.override_insufficient_balance'),
    ('recharge_refunds.manual_review'),('recharge_refunds.retry_gateway')
  ) AS p(key)
ON CONFLICT DO NOTHING;

-- Auditors get read-only visibility on refunds.
INSERT INTO public.role_permissions (role, permission_key)
VALUES ('auditor'::admin_role, 'recharge_refunds.read')
ON CONFLICT DO NOTHING;
