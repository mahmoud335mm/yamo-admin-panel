
-- ============================================================================
-- 1) recharge_requests column additions
-- ============================================================================
ALTER TABLE public.recharge_requests
  ADD COLUMN IF NOT EXISTS request_reference text,
  ADD COLUMN IF NOT EXISTS package_version_id uuid REFERENCES public.recharge_package_versions(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS package_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS price_rule_id uuid REFERENCES public.coin_price_rules(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS price_rule_version integer,
  ADD COLUMN IF NOT EXISTS price_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS base_price numeric(18,4),
  ADD COLUMN IF NOT EXISTS discount_amount numeric(18,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gateway_fee numeric(18,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS payment_method_fee numeric(18,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tax_amount numeric(18,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS final_amount numeric(18,4),
  ADD COLUMN IF NOT EXISTS payment_gateway_mode text NOT NULL DEFAULT 'live',
  ADD COLUMN IF NOT EXISTS payment_account_reference text,
  ADD COLUMN IF NOT EXISTS payment_account_id uuid REFERENCES public.payment_method_accounts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS provider_payment_id text,
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid',
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz,
  ADD COLUMN IF NOT EXISTS refunded_at timestamptz,
  ADD COLUMN IF NOT EXISTS failure_code text,
  ADD COLUMN IF NOT EXISTS requires_second_review boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reviewer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_requests_gateway_mode_chk') THEN
    ALTER TABLE public.recharge_requests ADD CONSTRAINT recharge_requests_gateway_mode_chk CHECK (payment_gateway_mode IN ('test','live'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_requests_payment_status_chk') THEN
    ALTER TABLE public.recharge_requests ADD CONSTRAINT recharge_requests_payment_status_chk CHECK (payment_status IN ('unpaid','pending','submitted','paid','failed','refunded','partially_refunded','chargeback'));
  END IF;
END $$;

UPDATE public.recharge_requests SET request_reference = 'RR-' || substr(replace(id::text,'-',''),1,10) WHERE request_reference IS NULL;
ALTER TABLE public.recharge_requests ALTER COLUMN request_reference SET NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_requests_request_reference_key') THEN
    ALTER TABLE public.recharge_requests ADD CONSTRAINT recharge_requests_request_reference_key UNIQUE (request_reference);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_rr_provider_pid ON public.recharge_requests(payment_gateway_id, provider_payment_id) WHERE provider_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rr_expires_at ON public.recharge_requests(expires_at) WHERE expires_at IS NOT NULL AND status IN ('created','pending_payment','payment_submitted');

-- ============================================================================
-- 2) State machine registry
-- ============================================================================
CREATE OR REPLACE FUNCTION public._recharge_transition_ok(_from recharge_request_status, _to recharge_request_status)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT (_from,_to) IN (
    ('created'::recharge_request_status,'pending_payment'::recharge_request_status),
    ('created','cancelled'),
    ('pending_payment','payment_submitted'),
    ('pending_payment','paid'),
    ('pending_payment','cancelled'),
    ('pending_payment','failed'),
    ('payment_submitted','manual_review'),
    ('payment_submitted','paid'),
    ('payment_submitted','failed'),
    ('payment_submitted','cancelled'),
    ('manual_review','approved'),
    ('manual_review','failed'),
    ('manual_review','cancelled'),
    ('paid','verifying'),
    ('paid','crediting'),
    ('verifying','crediting'),
    ('verifying','manual_review'),
    ('verifying','failed'),
    ('approved','crediting'),
    ('crediting','completed'),
    ('crediting','failed'),
    ('completed','refund_pending'),
    ('completed','disputed'),
    ('completed','chargeback'),
    ('refund_pending','partially_refunded'),
    ('refund_pending','refunded'),
    ('refund_pending','completed'),
    ('partially_refunded','refunded'),
    ('partially_refunded','disputed'),
    ('refunded','reversed'),
    ('disputed','completed'),
    ('disputed','refunded'),
    ('disputed','chargeback'),
    ('chargeback','reversed')
  );
$$;
REVOKE ALL ON FUNCTION public._recharge_transition_ok(recharge_request_status, recharge_request_status) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._recharge_transition_ok(recharge_request_status, recharge_request_status) FROM anon;

-- ============================================================================
-- 3) recharge_refunds extensions
-- ============================================================================
ALTER TABLE public.recharge_refunds
  ADD COLUMN IF NOT EXISTS refund_reference text,
  ADD COLUMN IF NOT EXISTS gateway_refund_id text,
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'full',
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'requested',
  ADD COLUMN IF NOT EXISTS currency_code text,
  ADD COLUMN IF NOT EXISTS cash_amount numeric(18,4),
  ADD COLUMN IF NOT EXISTS bonus_coins_reversed bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reversal_mode text NOT NULL DEFAULT 'cash_only',
  ADD COLUMN IF NOT EXISTS requested_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS second_reviewer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rejected_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS decision_reason text,
  ADD COLUMN IF NOT EXISTS requested_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS executed_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

UPDATE public.recharge_refunds SET refund_reference = 'RF-' || substr(replace(id::text,'-',''),1,10) WHERE refund_reference IS NULL;
ALTER TABLE public.recharge_refunds ALTER COLUMN refund_reference SET NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_refunds_refund_reference_key') THEN
    ALTER TABLE public.recharge_refunds ADD CONSTRAINT recharge_refunds_refund_reference_key UNIQUE (refund_reference);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_refunds_status_chk') THEN
    ALTER TABLE public.recharge_refunds ADD CONSTRAINT recharge_refunds_status_chk CHECK (status IN ('requested','pending_review','pending_second_review','processing','completed','failed','rejected','cancelled'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_refunds_kind_chk') THEN
    ALTER TABLE public.recharge_refunds ADD CONSTRAINT recharge_refunds_kind_chk CHECK (kind IN ('full','partial'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_refunds_reversal_mode_chk') THEN
    ALTER TABLE public.recharge_refunds ADD CONSTRAINT recharge_refunds_reversal_mode_chk CHECK (reversal_mode IN ('cash_only','cash_and_coins','coins_only'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_refunds_status ON public.recharge_refunds(status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_refunds_request ON public.recharge_refunds(request_id, requested_at DESC);

DROP TRIGGER IF EXISTS trg_rref_updated_at ON public.recharge_refunds;
CREATE TRIGGER trg_rref_updated_at BEFORE UPDATE ON public.recharge_refunds FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 4) recharge_disputes extensions
-- ============================================================================
ALTER TABLE public.recharge_disputes
  ADD COLUMN IF NOT EXISTS dispute_reference text,
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS gateway_id uuid REFERENCES public.payment_gateways(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS provider_dispute_id text,
  ADD COLUMN IF NOT EXISTS dispute_type text NOT NULL DEFAULT 'user_reported',
  ADD COLUMN IF NOT EXISTS reason_code text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS amount numeric(18,4),
  ADD COLUMN IF NOT EXISTS currency_code text,
  ADD COLUMN IF NOT EXISTS evidence_deadline timestamptz,
  ADD COLUMN IF NOT EXISTS priority text NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

UPDATE public.recharge_disputes d SET user_id = r.user_id FROM public.recharge_requests r WHERE d.request_id = r.id AND d.user_id IS NULL;
UPDATE public.recharge_disputes SET dispute_reference = 'DP-' || substr(replace(id::text,'-',''),1,10) WHERE dispute_reference IS NULL;
ALTER TABLE public.recharge_disputes ALTER COLUMN dispute_reference SET NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_disputes_dispute_reference_key') THEN
    ALTER TABLE public.recharge_disputes ADD CONSTRAINT recharge_disputes_dispute_reference_key UNIQUE (dispute_reference);
  END IF;
END $$;

-- Drop old restrictive check (status TEXT default 'open') and replace with extended set
ALTER TABLE public.recharge_disputes DROP CONSTRAINT IF EXISTS recharge_disputes_status_chk;
ALTER TABLE public.recharge_disputes ADD CONSTRAINT recharge_disputes_status_chk CHECK (status IN ('open','evidence_required','under_review','awaiting_gateway','won','lost','refunded','chargeback','closed'));

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_disputes_priority_chk') THEN
    ALTER TABLE public.recharge_disputes ADD CONSTRAINT recharge_disputes_priority_chk CHECK (priority IN ('low','normal','high','urgent'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_disputes_status ON public.recharge_disputes(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_disputes_assigned ON public.recharge_disputes(assigned_to, status) WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_disputes_user ON public.recharge_disputes(user_id, created_at DESC) WHERE user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.recharge_dispute_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dispute_id uuid NOT NULL REFERENCES public.recharge_disputes(id) ON DELETE CASCADE,
  author_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  note text NOT NULL,
  is_internal boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.recharge_dispute_notes TO authenticated;
GRANT ALL ON public.recharge_dispute_notes TO service_role;
ALTER TABLE public.recharge_dispute_notes ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='recharge_dispute_notes' AND policyname='rdn_read') THEN
    CREATE POLICY rdn_read ON public.recharge_dispute_notes FOR SELECT TO authenticated USING (has_permission(auth.uid(),'recharge_disputes.read') OR has_permission(auth.uid(),'recharge_disputes.manage'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='recharge_dispute_notes' AND policyname='rdn_insert') THEN
    CREATE POLICY rdn_insert ON public.recharge_dispute_notes FOR INSERT TO authenticated WITH CHECK (has_permission(auth.uid(),'recharge_disputes.manage'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='recharge_dispute_notes' AND policyname='rdn_no_update') THEN
    CREATE POLICY rdn_no_update ON public.recharge_dispute_notes AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='recharge_dispute_notes' AND policyname='rdn_no_delete') THEN
    CREATE POLICY rdn_no_delete ON public.recharge_dispute_notes AS RESTRICTIVE FOR DELETE TO authenticated USING (false);
  END IF;
END $$;

-- ============================================================================
-- 5) payment_webhooks hardening
-- ============================================================================
ALTER TABLE public.payment_webhooks
  ADD COLUMN IF NOT EXISTS gateway_mode text NOT NULL DEFAULT 'live',
  ADD COLUMN IF NOT EXISTS provider_event_id text,
  ADD COLUMN IF NOT EXISTS processing_state text NOT NULL DEFAULT 'received',
  ADD COLUMN IF NOT EXISTS processing_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS processing_owner text,
  ADD COLUMN IF NOT EXISTS related_request_id uuid REFERENCES public.recharge_requests(id) ON DELETE SET NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payment_webhooks_processing_state_chk') THEN
    ALTER TABLE public.payment_webhooks ADD CONSTRAINT payment_webhooks_processing_state_chk CHECK (processing_state IN ('received','processing','processed','failed','skipped'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payment_webhooks_gateway_mode_chk') THEN
    ALTER TABLE public.payment_webhooks ADD CONSTRAINT payment_webhooks_gateway_mode_chk CHECK (gateway_mode IN ('test','live'));
  END IF;
END $$;

UPDATE public.payment_webhooks SET provider_event_id = external_id WHERE provider_event_id IS NULL AND external_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_webhook_provider_event
  ON public.payment_webhooks (gateway_id, gateway_mode, provider_event_id)
  WHERE provider_event_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_webhooks_processing ON public.payment_webhooks(processing_state, received_at) WHERE processing_state IN ('received','processing');

CREATE OR REPLACE FUNCTION public.reclaim_stale_webhooks(_older_than interval DEFAULT interval '10 minutes')
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _n integer;
BEGIN
  IF auth.uid() IS NULL OR NOT has_permission(auth.uid(),'payment_webhooks.read') THEN RAISE EXCEPTION 'forbidden'; END IF;
  UPDATE public.payment_webhooks
     SET processing_state='received', processing_owner=NULL, processing_started_at=NULL
   WHERE processing_state='processing' AND processing_started_at < now() - _older_than;
  GET DIAGNOSTICS _n = ROW_COUNT;
  RETURN _n;
END $$;
REVOKE ALL ON FUNCTION public.reclaim_stale_webhooks(interval) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reclaim_stale_webhooks(interval) FROM anon;
GRANT EXECUTE ON FUNCTION public.reclaim_stale_webhooks(interval) TO authenticated;

-- ============================================================================
-- 6) Permissions
-- ============================================================================
INSERT INTO public.permissions (key, module, label_ar, label_en, description) VALUES
  ('recharge_requests.review',   'finance', 'مراجعة طلبات الشحن',       'Review recharge requests',  'مراجعة طلبات الدفع اليدوية'),
  ('recharge_requests.verify',   'finance', 'تحقق طلبات الشحن',         'Verify recharge requests',  'تحقق من مطابقة الدفع'),
  ('recharge_requests.complete', 'finance', 'إكمال طلبات الشحن',        'Complete recharge requests','إكمال وإضافة الكوينز'),
  ('recharge_requests.fail',     'finance', 'رفض طلبات الشحن',          'Fail recharge requests',    'وسم الطلب كفاشل'),
  ('recharge_requests.cancel',   'finance', 'إلغاء طلبات الشحن',        'Cancel recharge requests',  'إلغاء طلبات معلقة'),
  ('recharge_receipts.read',     'finance', 'قراءة الإيصالات',          'Read recharge receipts',    'عرض إيصالات الدفع اليدوي'),
  ('recharge_receipts.review',   'finance', 'مراجعة الإيصالات',         'Review recharge receipts',  'قبول أو رفض الإيصالات'),
  ('recharge_refunds.read',      'finance', 'قراءة الاستردادات',        'Read refunds',              'عرض طلبات الاسترداد'),
  ('recharge_refunds.request',   'finance', 'طلب استرداد',              'Request refund',            'إنشاء طلب استرداد'),
  ('recharge_refunds.approve',   'finance', 'اعتماد الاسترداد',         'Approve refund',            'اعتماد أو رفض الاسترداد'),
  ('recharge_refunds.execute',   'finance', 'تنفيذ الاسترداد',          'Execute refund',            'تنفيذ الاسترداد عبر البوابة'),
  ('recharge_disputes.read',     'finance', 'قراءة النزاعات',           'Read disputes',             'عرض النزاعات'),
  ('recharge_disputes.create',   'finance', 'فتح نزاع',                 'Open dispute',              'فتح نزاع جديد'),
  ('recharge_disputes.assign',   'finance', 'تعيين نزاع',               'Assign dispute',            'تعيين مسؤول للنزاع'),
  ('recharge_disputes.resolve',  'finance', 'حل النزاع',                'Resolve dispute',           'حل النزاع وتحديد النتيجة'),
  ('recharge_chargebacks.manage','finance', 'إدارة الاسترداد القسري',   'Manage chargebacks',        'معالجة chargebacks')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions (role, permission_key)
SELECT r.role_enum, p.key
  FROM (VALUES ('super_admin'::admin_role),('admin'::admin_role),('finance'::admin_role)) AS r(role_enum)
  CROSS JOIN (VALUES
    ('recharge_requests.review'),('recharge_requests.verify'),('recharge_requests.complete'),
    ('recharge_requests.fail'),('recharge_requests.cancel'),
    ('recharge_receipts.read'),('recharge_receipts.review'),
    ('recharge_refunds.read'),('recharge_refunds.request'),('recharge_refunds.approve'),('recharge_refunds.execute'),
    ('recharge_disputes.read'),('recharge_disputes.create'),('recharge_disputes.assign'),('recharge_disputes.resolve'),
    ('recharge_chargebacks.manage')
  ) AS p(key)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 7) Mock Payment Gateway
-- ============================================================================
INSERT INTO public.payment_gateways (id, code, name, provider, status, mode, supported_currencies, min_amount, max_amount, metadata)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'mock',
  'Mock Test Gateway',
  'mock',
  'active'::payment_gateway_status,
  'test'::payment_gateway_mode,
  ARRAY['USD','EUR','SAR','EGP','AED'],
  0,
  NULL,
  '{"purpose":"automated_tests","supports":["succeeded","failed","cancelled","refunded","chargeback"]}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET status='active'::payment_gateway_status;

CREATE OR REPLACE FUNCTION public.mock_emit_webhook(
  _kind text, _request_id uuid, _override jsonb DEFAULT '{}'::jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _wh_id uuid;
  _req public.recharge_requests%ROWTYPE;
  _payload jsonb;
  _event_id text;
  _valid_sig boolean := true;
BEGIN
  IF auth.uid() IS NULL OR NOT has_permission(auth.uid(),'payment_webhooks.read') THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO _req FROM public.recharge_requests WHERE id = _request_id;
  IF _req.id IS NULL THEN RAISE EXCEPTION 'request_not_found'; END IF;

  _event_id := COALESCE(_override->>'provider_event_id', 'mock_evt_' || replace(gen_random_uuid()::text,'-',''));

  _payload := jsonb_build_object(
    'kind', _kind,
    'provider_event_id', _event_id,
    'request_id', _request_id,
    'amount', COALESCE((_override->>'amount')::numeric, _req.final_amount, _req.price),
    'currency', COALESCE(_override->>'currency', _req.currency_code),
    'mode', 'test',
    'created_at', now()
  );

  CASE _kind
    WHEN 'invalid_signature' THEN _valid_sig := false;
    WHEN 'expired_timestamp' THEN _payload := _payload || jsonb_build_object('created_at', now() - interval '2 hours');
    WHEN 'wrong_amount'      THEN _payload := _payload || jsonb_build_object('amount', COALESCE(_req.final_amount,_req.price) * 2);
    WHEN 'wrong_currency'    THEN _payload := _payload || jsonb_build_object('currency', 'ZZZ');
    ELSE NULL;
  END CASE;

  INSERT INTO public.payment_webhooks (
    gateway_id, gateway_mode, external_id, provider_event_id,
    event_type, signature, signature_valid, raw_payload,
    idempotency_key, related_request_id
  ) VALUES (
    '00000000-0000-0000-0000-000000000001'::uuid, 'test', _event_id, _event_id,
    _kind, 'mock_sig', _valid_sig, _payload,
    _event_id, _request_id
  )
  ON CONFLICT (gateway_id, gateway_mode, provider_event_id) WHERE provider_event_id IS NOT NULL
  DO UPDATE SET retry_count = payment_webhooks.retry_count + 1
  RETURNING id INTO _wh_id;

  RETURN _wh_id;
END $$;
REVOKE ALL ON FUNCTION public.mock_emit_webhook(text, uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mock_emit_webhook(text, uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.mock_emit_webhook(text, uuid, jsonb) TO authenticated;

-- ============================================================================
-- 8) tg_rr_sync_payment_status
-- ============================================================================
CREATE OR REPLACE FUNCTION public.tg_rr_sync_payment_status()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.payment_status := CASE NEW.status::text
      WHEN 'created' THEN 'unpaid'
      WHEN 'pending_payment' THEN 'pending'
      WHEN 'payment_submitted' THEN 'submitted'
      WHEN 'paid' THEN 'paid'
      WHEN 'verifying' THEN 'paid'
      WHEN 'manual_review' THEN 'submitted'
      WHEN 'approved' THEN 'paid'
      WHEN 'crediting' THEN 'paid'
      WHEN 'completed' THEN 'paid'
      WHEN 'failed' THEN 'failed'
      WHEN 'cancelled' THEN COALESCE(NEW.payment_status,'unpaid')
      WHEN 'refund_pending' THEN 'paid'
      WHEN 'partially_refunded' THEN 'partially_refunded'
      WHEN 'refunded' THEN 'refunded'
      WHEN 'chargeback' THEN 'chargeback'
      WHEN 'reversed' THEN 'refunded'
      WHEN 'disputed' THEN NEW.payment_status
      ELSE NEW.payment_status
    END;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_rr_sync_payment_status ON public.recharge_requests;
CREATE TRIGGER trg_rr_sync_payment_status BEFORE UPDATE ON public.recharge_requests
  FOR EACH ROW EXECUTE FUNCTION public.tg_rr_sync_payment_status();
