
-- Retry Phase 5D-1 with corrected role_permissions column
DO $$ BEGIN CREATE TYPE public.recharge_dispute_type_enum AS ENUM (
  'payment_not_credited','charged_wrong_amount','duplicate_charge','unauthorized_payment',
  'payment_method_issue','receipt_rejected','refund_not_received','partial_refund_issue',
  'coins_removed_incorrectly','provider_chargeback','provider_inquiry','fraud_suspected',
  'technical_error','other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_source_enum AS ENUM (
  'user','support','finance','system','payment_gateway','bank','chargeback_webhook','internal_audit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_status_enum AS ENUM (
  'opened','triage','awaiting_user_evidence','awaiting_internal_evidence','awaiting_gateway_evidence',
  'under_review','escalated','pending_first_decision','pending_second_decision','provisional_action',
  'resolved_user_favor','resolved_platform_favor','resolved_partial','rejected','cancelled','closed',
  'chargeback_received','chargeback_acknowledged','chargeback_evidence_due','chargeback_contested',
  'chargeback_accepted','chargeback_won','chargeback_lost');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_priority_enum AS ENUM ('low','normal','high','urgent');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_severity_enum AS ENUM ('informational','low','medium','high','critical');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_provisional_action_enum AS ENUM (
  'none','manual_monitoring','temporary_recharge_hold','temporary_refund_hold',
  'temporary_withdrawal_hold','temporary_wallet_spending_hold','request_identity_review','escalate_to_fraud_review');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_note_type_enum AS ENUM (
  'internal_note','user_message','system_event','gateway_update','evidence_request',
  'evidence_received','decision_note','escalation_note','closure_note');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_note_visibility_enum AS ENUM (
  'internal','user_visible','finance_only','auditor_only','system_only');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_evidence_type_enum AS ENUM (
  'payment_receipt','bank_statement','account_statement','gateway_confirmation','refund_confirmation',
  'user_screenshot','chat_record','support_record','device_log','webhook_record',
  'provider_document','identity_confirmation','other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.recharge_dispute_evidence_status_enum AS ENUM (
  'uploaded','submitted','under_review','accepted','rejected','superseded','quarantined');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.recharge_disputes DROP CONSTRAINT IF EXISTS recharge_disputes_status_chk;
ALTER TABLE public.recharge_disputes DROP CONSTRAINT IF EXISTS recharge_disputes_priority_chk;

ALTER TABLE public.recharge_disputes ALTER COLUMN status DROP DEFAULT;
ALTER TABLE public.recharge_disputes
  ALTER COLUMN status TYPE public.recharge_dispute_status_enum
  USING (CASE lower(coalesce(status,'opened'))
    WHEN 'open' THEN 'opened' WHEN 'opened' THEN 'opened'
    WHEN 'evidence_required' THEN 'awaiting_user_evidence'
    WHEN 'under_review' THEN 'under_review'
    WHEN 'awaiting_gateway' THEN 'awaiting_gateway_evidence'
    WHEN 'won' THEN 'resolved_platform_favor'
    WHEN 'lost' THEN 'resolved_user_favor'
    WHEN 'refunded' THEN 'resolved_user_favor'
    WHEN 'chargeback' THEN 'chargeback_received'
    WHEN 'closed' THEN 'closed' ELSE 'opened' END::public.recharge_dispute_status_enum);
ALTER TABLE public.recharge_disputes ALTER COLUMN status SET DEFAULT 'opened';

ALTER TABLE public.recharge_disputes ALTER COLUMN dispute_type DROP DEFAULT;
ALTER TABLE public.recharge_disputes
  ALTER COLUMN dispute_type TYPE public.recharge_dispute_type_enum
  USING (CASE lower(coalesce(dispute_type,'other'))
    WHEN 'user_reported' THEN 'other'
    WHEN 'payment_not_credited' THEN 'payment_not_credited'
    WHEN 'duplicate_charge' THEN 'duplicate_charge'
    WHEN 'unauthorized_payment' THEN 'unauthorized_payment'
    WHEN 'chargeback' THEN 'provider_chargeback'
    ELSE 'other' END::public.recharge_dispute_type_enum);
ALTER TABLE public.recharge_disputes ALTER COLUMN dispute_type SET DEFAULT 'other';

ALTER TABLE public.recharge_disputes ALTER COLUMN priority DROP DEFAULT;
ALTER TABLE public.recharge_disputes
  ALTER COLUMN priority TYPE public.recharge_dispute_priority_enum
  USING (CASE lower(coalesce(priority,'normal'))
    WHEN 'low' THEN 'low' WHEN 'high' THEN 'high' WHEN 'urgent' THEN 'urgent'
    ELSE 'normal' END::public.recharge_dispute_priority_enum);
ALTER TABLE public.recharge_disputes ALTER COLUMN priority SET DEFAULT 'normal';

ALTER TABLE public.recharge_disputes
  ADD COLUMN IF NOT EXISTS refund_id uuid REFERENCES public.recharge_refunds(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS payment_method_id uuid REFERENCES public.payment_methods(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS dispute_source public.recharge_dispute_source_enum NOT NULL DEFAULT 'support',
  ADD COLUMN IF NOT EXISTS severity public.recharge_dispute_severity_enum NOT NULL DEFAULT 'low',
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS summary text,
  ADD COLUMN IF NOT EXISTS user_claim text,
  ADD COLUMN IF NOT EXISTS safe_internal_summary text,
  ADD COLUMN IF NOT EXISTS claimed_amount numeric(18,4),
  ADD COLUMN IF NOT EXISTS currency text,
  ADD COLUMN IF NOT EXISTS provider_chargeback_id text,
  ADD COLUMN IF NOT EXISTS provider_case_reference text,
  ADD COLUMN IF NOT EXISTS provider_reason_code text,
  ADD COLUMN IF NOT EXISTS provider_reason_category text,
  ADD COLUMN IF NOT EXISTS provider_status text,
  ADD COLUMN IF NOT EXISTS provider_decision text,
  ADD COLUMN IF NOT EXISTS provider_mode text,
  ADD COLUMN IF NOT EXISTS provider_event_id text,
  ADD COLUMN IF NOT EXISTS provider_opened_at timestamptz,
  ADD COLUMN IF NOT EXISTS provider_updated_at timestamptz,
  ADD COLUMN IF NOT EXISTS provider_decision_at timestamptz,
  ADD COLUMN IF NOT EXISTS original_payment_reference text,
  ADD COLUMN IF NOT EXISTS provider_payment_id text,
  ADD COLUMN IF NOT EXISTS gateway_mode text,
  ADD COLUMN IF NOT EXISTS original_paid_amount numeric(18,4),
  ADD COLUMN IF NOT EXISTS already_refunded_amount numeric(18,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS chargeback_amount numeric(18,4),
  ADD COLUMN IF NOT EXISTS chargeback_currency text,
  ADD COLUMN IF NOT EXISTS original_base_coins bigint,
  ADD COLUMN IF NOT EXISTS original_bonus_coins bigint,
  ADD COLUMN IF NOT EXISTS current_available_coins bigint,
  ADD COLUMN IF NOT EXISTS current_available_bonus bigint,
  ADD COLUMN IF NOT EXISTS coins_already_reversed bigint DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bonus_already_reversed bigint DEFAULT 0,
  ADD COLUMN IF NOT EXISTS financial_exposure_amount numeric(18,4),
  ADD COLUMN IF NOT EXISTS recoverable_coin_amount bigint,
  ADD COLUMN IF NOT EXISTS unrecovered_coin_amount bigint,
  ADD COLUMN IF NOT EXISTS assigned_team text,
  ADD COLUMN IF NOT EXISTS requested_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS opened_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS first_decision_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS first_decision_at timestamptz,
  ADD COLUMN IF NOT EXISTS second_decision_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS second_decision_at timestamptz,
  ADD COLUMN IF NOT EXISTS closed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS closed_at timestamptz,
  ADD COLUMN IF NOT EXISTS due_at timestamptz,
  ADD COLUMN IF NOT EXISTS response_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS evidence_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS sla_policy_id uuid,
  ADD COLUMN IF NOT EXISTS dispute_policy_id uuid,
  ADD COLUMN IF NOT EXISTS dispute_policy_version integer,
  ADD COLUMN IF NOT EXISTS requires_second_decision boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS decision_type text,
  ADD COLUMN IF NOT EXISTS resolution_code text,
  ADD COLUMN IF NOT EXISTS resolution_reason text,
  ADD COLUMN IF NOT EXISTS failure_code text,
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS provisional_action public.recharge_dispute_provisional_action_enum NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS provisional_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS metadata_safe jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE UNIQUE INDEX IF NOT EXISTS uq_disputes_provider_chargeback
  ON public.recharge_disputes (gateway_id, gateway_mode, provider_chargeback_id)
  WHERE provider_chargeback_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_disputes_idempotency
  ON public.recharge_disputes (idempotency_key) WHERE idempotency_key IS NOT NULL;

ALTER TABLE public.recharge_disputes DROP CONSTRAINT IF EXISTS chk_disputes_two_eyes_distinct;
ALTER TABLE public.recharge_disputes
  ADD CONSTRAINT chk_disputes_two_eyes_distinct CHECK (
    first_decision_by IS NULL OR second_decision_by IS NULL OR first_decision_by <> second_decision_by);

CREATE OR REPLACE FUNCTION public._dispute_transition_ok(
  _from public.recharge_dispute_status_enum, _to public.recharge_dispute_status_enum
) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT _from = _to OR (_from::text, _to::text) IN (
    ('opened','triage'),('opened','cancelled'),
    ('triage','awaiting_user_evidence'),('triage','awaiting_internal_evidence'),
    ('triage','awaiting_gateway_evidence'),('triage','under_review'),('triage','rejected'),('triage','cancelled'),
    ('awaiting_user_evidence','under_review'),('awaiting_user_evidence','closed'),('awaiting_user_evidence','cancelled'),
    ('awaiting_internal_evidence','under_review'),('awaiting_internal_evidence','cancelled'),
    ('awaiting_gateway_evidence','under_review'),('awaiting_gateway_evidence','cancelled'),
    ('under_review','escalated'),('under_review','pending_first_decision'),
    ('under_review','resolved_platform_favor'),('under_review','resolved_user_favor'),('under_review','resolved_partial'),
    ('under_review','provisional_action'),('under_review','rejected'),
    ('escalated','pending_first_decision'),('escalated','under_review'),
    ('provisional_action','under_review'),('provisional_action','pending_first_decision'),
    ('pending_first_decision','pending_second_decision'),
    ('pending_first_decision','resolved_platform_favor'),
    ('pending_first_decision','resolved_user_favor'),
    ('pending_first_decision','resolved_partial'),
    ('pending_second_decision','resolved_platform_favor'),
    ('pending_second_decision','resolved_user_favor'),
    ('pending_second_decision','resolved_partial'),
    ('resolved_user_favor','closed'),('resolved_platform_favor','closed'),('resolved_partial','closed'),
    ('rejected','closed'),
    ('chargeback_received','chargeback_acknowledged'),
    ('chargeback_acknowledged','chargeback_evidence_due'),
    ('chargeback_evidence_due','chargeback_contested'),
    ('chargeback_evidence_due','chargeback_accepted'),
    ('chargeback_contested','chargeback_won'),
    ('chargeback_contested','chargeback_lost'),
    ('chargeback_accepted','closed'),
    ('chargeback_won','closed'),
    ('chargeback_lost','closed'));
$$;
REVOKE ALL ON FUNCTION public._dispute_transition_ok(public.recharge_dispute_status_enum,public.recharge_dispute_status_enum) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._dispute_transition_ok(public.recharge_dispute_status_enum,public.recharge_dispute_status_enum) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.tg_recharge_dispute_state_machine()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT public._dispute_transition_ok(OLD.status, NEW.status) THEN
      RAISE EXCEPTION 'DISPUTE_ILLEGAL_TRANSITION: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS tg_recharge_dispute_state_machine ON public.recharge_disputes;
CREATE TRIGGER tg_recharge_dispute_state_machine
  BEFORE UPDATE ON public.recharge_disputes
  FOR EACH ROW EXECUTE FUNCTION public.tg_recharge_dispute_state_machine();

ALTER TABLE public.recharge_dispute_notes
  ADD COLUMN IF NOT EXISTS note_type public.recharge_dispute_note_type_enum NOT NULL DEFAULT 'internal_note',
  ADD COLUMN IF NOT EXISTS visibility public.recharge_dispute_note_visibility_enum NOT NULL DEFAULT 'internal',
  ADD COLUMN IF NOT EXISTS safe_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS supersedes_note_id uuid REFERENCES public.recharge_dispute_notes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_redacted boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS redacted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS redacted_at timestamptz,
  ADD COLUMN IF NOT EXISTS redaction_reason text;

UPDATE public.recharge_dispute_notes SET visibility = 'user_visible'
WHERE is_internal = false AND visibility = 'internal';

DO $$ BEGIN
  ALTER TABLE public.recharge_dispute_notes
    ADD COLUMN body text GENERATED ALWAYS AS (note) STORED;
EXCEPTION WHEN duplicate_column THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.recharge_dispute_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  country text, currency text,
  gateway_id uuid REFERENCES public.payment_gateways(id) ON DELETE CASCADE,
  gateway_mode text,
  dispute_type public.recharge_dispute_type_enum,
  source public.recharge_dispute_source_enum,
  user_dispute_window_days integer NOT NULL DEFAULT 30,
  evidence_submission_days integer NOT NULL DEFAULT 7,
  first_response_hours integer NOT NULL DEFAULT 24,
  resolution_target_hours integer NOT NULL DEFAULT 168,
  chargeback_response_days integer NOT NULL DEFAULT 7,
  second_decision_threshold numeric(18,4) NOT NULL DEFAULT 0,
  auto_close_after_no_response_days integer NOT NULL DEFAULT 14,
  allow_user_submission boolean NOT NULL DEFAULT false,
  require_receipt boolean NOT NULL DEFAULT true,
  require_gateway_evidence boolean NOT NULL DEFAULT false,
  require_second_decision boolean NOT NULL DEFAULT true,
  provisional_action_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
  wallet_restriction_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
  active boolean NOT NULL DEFAULT true,
  priority integer NOT NULL DEFAULT 100,
  version integer NOT NULL DEFAULT 1,
  starts_at timestamptz, ends_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now());

GRANT SELECT ON public.recharge_dispute_policies TO authenticated;
GRANT ALL ON public.recharge_dispute_policies TO service_role;
ALTER TABLE public.recharge_dispute_policies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rdp_read" ON public.recharge_dispute_policies;
CREATE POLICY "rdp_read" ON public.recharge_dispute_policies
  FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_disputes.read') OR public.has_permission(auth.uid(),'recharge_disputes.manage'));

DROP POLICY IF EXISTS "rdp_no_write" ON public.recharge_dispute_policies;
CREATE POLICY "rdp_no_write" ON public.recharge_dispute_policies
  AS RESTRICTIVE FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP TRIGGER IF EXISTS trg_rdp_updated_at ON public.recharge_dispute_policies;
CREATE TRIGGER trg_rdp_updated_at BEFORE UPDATE ON public.recharge_dispute_policies
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_rdp_active_prio ON public.recharge_dispute_policies (active, priority);
CREATE INDEX IF NOT EXISTS idx_rdp_match ON public.recharge_dispute_policies (country, currency, gateway_id, gateway_mode, dispute_type, source);

CREATE TABLE IF NOT EXISTS public.recharge_dispute_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dispute_id uuid NOT NULL REFERENCES public.recharge_disputes(id) ON DELETE CASCADE,
  submitted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  submitted_by_type text NOT NULL DEFAULT 'admin' CHECK (submitted_by_type IN ('user','admin','system','gateway')),
  evidence_type public.recharge_dispute_evidence_type_enum NOT NULL DEFAULT 'other',
  storage_bucket text NOT NULL DEFAULT 'recharge-dispute-evidence',
  storage_object_path text NOT NULL,
  original_filename_masked text,
  mime_type text NOT NULL,
  size_bytes bigint NOT NULL CHECK (size_bytes > 0),
  sha256_hash text,
  description text,
  source text,
  visibility public.recharge_dispute_note_visibility_enum NOT NULL DEFAULT 'internal',
  status public.recharge_dispute_evidence_status_enum NOT NULL DEFAULT 'uploaded',
  malware_scan_status text NOT NULL DEFAULT 'pending' CHECK (malware_scan_status IN ('pending','clean','infected','skipped')),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  review_status text, rejection_reason text,
  supersedes_evidence_id uuid REFERENCES public.recharge_dispute_evidence(id) ON DELETE SET NULL,
  is_quarantined boolean NOT NULL DEFAULT false,
  metadata_safe jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_evidence_mime_allowed CHECK (mime_type IN (
    'image/jpeg','image/png','image/webp','application/pdf','text/plain','message/rfc822')));

GRANT SELECT, INSERT ON public.recharge_dispute_evidence TO authenticated;
GRANT ALL ON public.recharge_dispute_evidence TO service_role;
ALTER TABLE public.recharge_dispute_evidence ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rde_read" ON public.recharge_dispute_evidence;
CREATE POLICY "rde_read" ON public.recharge_dispute_evidence
  FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_disputes.evidence.read') OR public.has_permission(auth.uid(),'recharge_disputes.manage'));

DROP POLICY IF EXISTS "rde_insert_admin" ON public.recharge_dispute_evidence;
CREATE POLICY "rde_insert_admin" ON public.recharge_dispute_evidence
  FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(auth.uid(),'recharge_disputes.evidence.create') OR public.has_permission(auth.uid(),'recharge_disputes.manage'));

DROP POLICY IF EXISTS "rde_no_update" ON public.recharge_dispute_evidence;
CREATE POLICY "rde_no_update" ON public.recharge_dispute_evidence
  AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS "rde_no_delete" ON public.recharge_dispute_evidence;
CREATE POLICY "rde_no_delete" ON public.recharge_dispute_evidence
  AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

CREATE INDEX IF NOT EXISTS idx_rde_dispute ON public.recharge_dispute_evidence (dispute_id, submitted_at DESC);

CREATE OR REPLACE FUNCTION public.resolve_recharge_dispute_policy(
  _country text, _currency text, _gateway_id uuid, _gateway_mode text,
  _dispute_type public.recharge_dispute_type_enum, _source public.recharge_dispute_source_enum
) RETURNS public.recharge_dispute_policies
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE _row public.recharge_dispute_policies;
BEGIN
  SELECT * INTO _row FROM public.recharge_dispute_policies p
  WHERE p.active = true
    AND (p.starts_at IS NULL OR p.starts_at <= now())
    AND (p.ends_at IS NULL OR p.ends_at > now())
    AND (p.country IS NULL OR p.country = _country)
    AND (p.currency IS NULL OR p.currency = _currency)
    AND (p.gateway_id IS NULL OR p.gateway_id = _gateway_id)
    AND (p.gateway_mode IS NULL OR p.gateway_mode = _gateway_mode)
    AND (p.dispute_type IS NULL OR p.dispute_type = _dispute_type)
    AND (p.source IS NULL OR p.source = _source)
  ORDER BY
    (p.country IS NOT NULL)::int + (p.currency IS NOT NULL)::int
    + (p.gateway_id IS NOT NULL)::int + (p.gateway_mode IS NOT NULL)::int
    + (p.dispute_type IS NOT NULL)::int + (p.source IS NOT NULL)::int DESC,
    p.priority ASC, p.created_at ASC
  LIMIT 1;
  RETURN _row;
END; $$;
REVOKE ALL ON FUNCTION public.resolve_recharge_dispute_policy(text,text,uuid,text,public.recharge_dispute_type_enum,public.recharge_dispute_source_enum) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_recharge_dispute_policy(text,text,uuid,text,public.recharge_dispute_type_enum,public.recharge_dispute_source_enum) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.assert_no_overlapping_recharge_dispute_policies()
RETURNS TABLE(a_id uuid, b_id uuid, reason text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.id, b.id, 'POLICY_CONFLICT: identical scope + same priority'::text
  FROM public.recharge_dispute_policies a
  JOIN public.recharge_dispute_policies b
    ON a.id < b.id AND a.active AND b.active AND a.priority = b.priority
   AND coalesce(a.country,'*')=coalesce(b.country,'*')
   AND coalesce(a.currency,'*')=coalesce(b.currency,'*')
   AND coalesce(a.gateway_id::text,'*')=coalesce(b.gateway_id::text,'*')
   AND coalesce(a.gateway_mode,'*')=coalesce(b.gateway_mode,'*')
   AND coalesce(a.dispute_type::text,'*')=coalesce(b.dispute_type::text,'*')
   AND coalesce(a.source::text,'*')=coalesce(b.source::text,'*');
$$;
REVOKE ALL ON FUNCTION public.assert_no_overlapping_recharge_dispute_policies() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_no_overlapping_recharge_dispute_policies() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.preview_recharge_dispute_exposure(
  _recharge_request_id uuid, _dispute_id uuid DEFAULT NULL
) RETURNS TABLE(
  original_paid_amount numeric, refunded_amount numeric, charged_back_amount numeric,
  resolved_compensation_amount numeric, remaining_financial_exposure numeric,
  original_base_coins bigint, reversed_base_coins bigint, remaining_base_exposure bigint,
  original_bonus bigint, reversed_bonus bigint, remaining_bonus_exposure bigint,
  warnings text[], blocking_reasons text[]
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE _rr record; _refunded numeric := 0; _cb numeric := 0;
  _warn text[] := ARRAY[]::text[]; _block text[] := ARRAY[]::text[];
BEGIN
  IF NOT (public.has_permission(auth.uid(),'recharge_disputes.read')
       OR public.has_permission(auth.uid(),'recharge_disputes.manage')) THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO _rr FROM public.recharge_requests WHERE id = _recharge_request_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT COALESCE(SUM(r.refunded_amount),0) INTO _refunded
  FROM public.recharge_refunds r
  WHERE r.recharge_request_id = _recharge_request_id
    AND r.status::text IN ('completed','partially_completed');

  SELECT COALESCE(SUM(d.chargeback_amount),0) INTO _cb
  FROM public.recharge_disputes d
  WHERE d.request_id = _recharge_request_id
    AND d.chargeback_amount IS NOT NULL
    AND (_dispute_id IS NULL OR d.id <> _dispute_id);

  original_paid_amount := COALESCE(_rr.amount, 0);
  refunded_amount := _refunded;
  charged_back_amount := _cb;
  resolved_compensation_amount := 0;
  remaining_financial_exposure := GREATEST(original_paid_amount - refunded_amount - charged_back_amount, 0);
  original_base_coins := COALESCE(_rr.coins_amount, 0);
  original_bonus := COALESCE(_rr.bonus_coins, 0);
  reversed_base_coins := 0; reversed_bonus := 0;
  remaining_base_exposure := original_base_coins;
  remaining_bonus_exposure := original_bonus;

  IF refunded_amount + charged_back_amount > original_paid_amount THEN
    _block := array_append(_block, 'OVER_REFUND_OR_CHARGEBACK');
  END IF;
  warnings := _warn; blocking_reasons := _block;
  RETURN NEXT;
END; $$;
REVOKE ALL ON FUNCTION public.preview_recharge_dispute_exposure(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.preview_recharge_dispute_exposure(uuid,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.calculate_recharge_dispute_sla(_dispute_id uuid)
RETURNS TABLE(
  policy_id uuid, first_response_due_at timestamptz, evidence_due_at timestamptz,
  resolution_due_at timestamptz, chargeback_due_at timestamptz,
  is_first_response_overdue boolean, is_resolution_overdue boolean, is_chargeback_overdue boolean
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE _d public.recharge_disputes; _p public.recharge_dispute_policies;
BEGIN
  SELECT * INTO _d FROM public.recharge_disputes WHERE id = _dispute_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF _d.dispute_policy_id IS NOT NULL THEN
    SELECT * INTO _p FROM public.recharge_dispute_policies WHERE id = _d.dispute_policy_id;
  END IF;
  policy_id := _p.id;
  first_response_due_at := _d.opened_at + make_interval(hours => COALESCE(_p.first_response_hours, 24));
  evidence_due_at := _d.opened_at + make_interval(days => COALESCE(_p.evidence_submission_days, 7));
  resolution_due_at := _d.opened_at + make_interval(hours => COALESCE(_p.resolution_target_hours, 168));
  chargeback_due_at := CASE WHEN _d.provider_chargeback_id IS NOT NULL
    THEN COALESCE(_d.provider_opened_at, _d.opened_at) + make_interval(days => COALESCE(_p.chargeback_response_days, 7))
    ELSE NULL END;
  is_first_response_overdue := (_d.first_decision_at IS NULL AND now() > first_response_due_at);
  is_resolution_overdue := (_d.resolved_at IS NULL AND now() > resolution_due_at);
  is_chargeback_overdue := (chargeback_due_at IS NOT NULL AND now() > chargeback_due_at
    AND _d.status::text NOT IN ('chargeback_contested','chargeback_won','chargeback_lost','chargeback_accepted','closed'));
  RETURN NEXT;
END; $$;
REVOKE ALL ON FUNCTION public.calculate_recharge_dispute_sla(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.calculate_recharge_dispute_sla(uuid) TO authenticated, service_role;

INSERT INTO public.permissions (key, module, label_ar, label_en, description) VALUES
  ('recharge_disputes.triage','disputes','فرز النزاعات','Triage disputes',NULL),
  ('recharge_disputes.review','disputes','مراجعة النزاعات','Review disputes',NULL),
  ('recharge_disputes.first_decide','disputes','قرار أول','First decision',NULL),
  ('recharge_disputes.second_decide','disputes','قرار ثانٍ','Second decision',NULL),
  ('recharge_disputes.close','disputes','إغلاق نزاع','Close dispute',NULL),
  ('recharge_disputes.reopen','disputes','إعادة فتح نزاع','Reopen dispute',NULL),
  ('recharge_disputes.escalate','disputes','تصعيد نزاع','Escalate dispute',NULL),
  ('recharge_disputes.read_sensitive','disputes','قراءة بيانات حساسة','Read sensitive data',NULL),
  ('recharge_disputes.evidence.create','disputes','رفع أدلة','Upload evidence',NULL),
  ('recharge_disputes.evidence.read','disputes','قراءة أدلة','Read evidence',NULL),
  ('recharge_disputes.evidence.read_sensitive','disputes','قراءة أدلة حساسة','Read sensitive evidence',NULL),
  ('recharge_disputes.evidence.review','disputes','مراجعة أدلة','Review evidence',NULL),
  ('recharge_disputes.notes.create_internal','disputes','ملاحظة داخلية','Create internal note',NULL),
  ('recharge_disputes.notes.create_user_visible','disputes','ملاحظة مرئية للمستخدم','Create user-visible note',NULL),
  ('recharge_disputes.chargeback.read','disputes','قراءة chargeback','Read chargeback',NULL),
  ('recharge_disputes.chargeback.manage','disputes','إدارة chargeback','Manage chargeback',NULL),
  ('recharge_disputes.provisional_action','disputes','إجراء مؤقت','Provisional action',NULL),
  ('recharge_disputes.export','disputes','تصدير النزاعات','Export disputes',NULL),
  ('recharge_disputes.policies.manage','disputes','إدارة سياسات النزاعات','Manage dispute policies',NULL)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions (role, permission_key)
SELECT 'super_admin'::admin_role, p.key FROM public.permissions p
WHERE p.key LIKE 'recharge_disputes.%'
ON CONFLICT DO NOTHING;

INSERT INTO public.system_settings(key, value) VALUES
  ('feature_flags.enable_disputes_admin_ui', 'false'::jsonb),
  ('feature_flags.enable_user_dispute_submission', 'false'::jsonb),
  ('feature_flags.enable_chargeback_processing', 'false'::jsonb),
  ('feature_flags.enable_dispute_financial_resolution', 'false'::jsonb),
  ('feature_flags.enable_dispute_provisional_actions', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;
