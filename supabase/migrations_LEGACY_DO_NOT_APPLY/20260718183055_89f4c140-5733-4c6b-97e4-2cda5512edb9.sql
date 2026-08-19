
-- 1) PERMISSIONS
INSERT INTO public.permissions (key, module, label_ar, label_en, description) VALUES
  ('recharge_receipts.create',              'recharge', 'إنشاء إيصال شحن',                     'Create recharge receipt',                  'Upload a receipt for a recharge request'),
  ('recharge_receipts.read_sensitive',      'recharge', 'قراءة بيانات الإيصال الحساسة',        'Read sensitive receipt data',              'View sender name / paid amount / reference'),
  ('recharge_payment_instructions.resolve', 'recharge', 'حل تعليمات الدفع للمستخدم',           'Resolve payment instructions',             'Return safe payment instructions to a user'),
  ('transaction_messages.read',             'messaging','قراءة رسائل المعاملات',                'Read transaction messages',                'Read system-generated transaction messages'),
  ('transaction_messages.create_internal',  'messaging','إنشاء رسائل معاملات (داخلي)',         'Create transaction messages (internal)',   'Internal only, guarded by RPC / service role')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions(role, permission_key)
SELECT r::admin_role, p FROM (VALUES
  ('super_admin','recharge_receipts.create'),
  ('super_admin','recharge_receipts.read_sensitive'),
  ('super_admin','recharge_payment_instructions.resolve'),
  ('super_admin','transaction_messages.read'),
  ('super_admin','transaction_messages.create_internal'),
  ('finance','recharge_receipts.read_sensitive'),
  ('finance','recharge_payment_instructions.resolve'),
  ('finance','transaction_messages.read'),
  ('admin','recharge_receipts.read_sensitive'),
  ('admin','transaction_messages.read'),
  ('support','transaction_messages.read'),
  ('auditor','transaction_messages.read')
) v(r,p)
ON CONFLICT DO NOTHING;

-- 2) ENUMS
DO $$ BEGIN
  CREATE TYPE public.recharge_receipt_status AS ENUM
    ('uploaded','submitted','under_review','approved','rejected','more_info_required','superseded','quarantined');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.malware_scan_status AS ENUM
    ('pending','clean','suspicious','infected','failed','skipped');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.txn_outbox_status AS ENUM ('pending','processing','sent','failed','dead_letter');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3) EXTEND recharge_receipts
ALTER TABLE public.recharge_receipts
  ADD COLUMN IF NOT EXISTS user_id                  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS storage_bucket           text NOT NULL DEFAULT 'recharge-receipts',
  ADD COLUMN IF NOT EXISTS storage_object_path      text,
  ADD COLUMN IF NOT EXISTS original_filename_masked text,
  ADD COLUMN IF NOT EXISTS mime_type                text,
  ADD COLUMN IF NOT EXISTS size_bytes               bigint,
  ADD COLUMN IF NOT EXISTS sha256_hash              text,
  ADD COLUMN IF NOT EXISTS payment_reference        text,
  ADD COLUMN IF NOT EXISTS sender_name              text,
  ADD COLUMN IF NOT EXISTS paid_amount              numeric(18,2),
  ADD COLUMN IF NOT EXISTS currency                 text,
  ADD COLUMN IF NOT EXISTS paid_at                  timestamptz,
  ADD COLUMN IF NOT EXISTS status                   public.recharge_receipt_status NOT NULL DEFAULT 'uploaded',
  ADD COLUMN IF NOT EXISTS submitted_at             timestamptz,
  ADD COLUMN IF NOT EXISTS reviewed_at              timestamptz,
  ADD COLUMN IF NOT EXISTS reviewed_by              uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS review_decision          text,
  ADD COLUMN IF NOT EXISTS review_reason            text,
  ADD COLUMN IF NOT EXISTS supersedes_receipt_id    uuid REFERENCES public.recharge_receipts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_quarantined           boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS malware_scan_status      public.malware_scan_status NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS metadata_safe            jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS updated_at               timestamptz NOT NULL DEFAULT now();

UPDATE public.recharge_receipts rr
   SET user_id = req.user_id
  FROM public.recharge_requests req
 WHERE rr.request_id = req.id AND rr.user_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_rr_user    ON public.recharge_receipts(user_id);
CREATE INDEX IF NOT EXISTS idx_rr_request ON public.recharge_receipts(request_id);
CREATE INDEX IF NOT EXISTS idx_rr_status  ON public.recharge_receipts(status);
CREATE UNIQUE INDEX IF NOT EXISTS uq_rr_storage_path
  ON public.recharge_receipts(storage_bucket, storage_object_path)
  WHERE storage_object_path IS NOT NULL;

CREATE OR REPLACE FUNCTION public._tg_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS tg_recharge_receipts_touch ON public.recharge_receipts;
CREATE TRIGGER tg_recharge_receipts_touch
BEFORE UPDATE ON public.recharge_receipts
FOR EACH ROW EXECUTE FUNCTION public._tg_touch_updated_at();

CREATE OR REPLACE FUNCTION public._tg_rr_guard_user_edit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public AS $$
BEGIN
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status
     OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
     OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
     OR NEW.review_decision IS DISTINCT FROM OLD.review_decision
     OR NEW.review_reason IS DISTINCT FROM OLD.review_reason
     OR NEW.malware_scan_status IS DISTINCT FROM OLD.malware_scan_status
     OR NEW.is_quarantined IS DISTINCT FROM OLD.is_quarantined
     OR NEW.sha256_hash IS DISTINCT FROM OLD.sha256_hash
     OR NEW.size_bytes IS DISTINCT FROM OLD.size_bytes
     OR NEW.storage_object_path IS DISTINCT FROM OLD.storage_object_path
  THEN
    RAISE EXCEPTION 'recharge_receipts: protected columns can only be changed via server RPCs';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_rr_guard_user ON public.recharge_receipts;
CREATE TRIGGER tg_rr_guard_user
BEFORE UPDATE ON public.recharge_receipts
FOR EACH ROW EXECUTE FUNCTION public._tg_rr_guard_user_edit();

ALTER TABLE public.recharge_receipts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rrc_owner_read"   ON public.recharge_receipts;
DROP POLICY IF EXISTS "rrc_owner_insert" ON public.recharge_receipts;
DROP POLICY IF EXISTS "rrc_owner_update" ON public.recharge_receipts;
DROP POLICY IF EXISTS "rrc_no_delete"    ON public.recharge_receipts;

CREATE POLICY "rrc_owner_read" ON public.recharge_receipts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "rrc_owner_insert" ON public.recharge_receipts
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.recharge_requests r
                WHERE r.id = request_id AND r.user_id = auth.uid())
  );

CREATE POLICY "rrc_owner_update" ON public.recharge_receipts
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status = 'uploaded')
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "rrc_no_delete" ON public.recharge_receipts
  AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

GRANT SELECT, INSERT, UPDATE ON public.recharge_receipts TO authenticated;
GRANT ALL ON public.recharge_receipts TO service_role;

-- 4) OUTBOX
CREATE TABLE IF NOT EXISTS public.transaction_message_outbox (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type        text NOT NULL,
  transaction_type  text NOT NULL,
  transaction_id    uuid NOT NULL,
  recipient_user_id uuid NOT NULL,
  safe_payload      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status            public.txn_outbox_status NOT NULL DEFAULT 'pending',
  attempts          int NOT NULL DEFAULT 0,
  available_at      timestamptz NOT NULL DEFAULT now(),
  processed_at      timestamptz,
  last_error        text,
  idempotency_key   text NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_txn_outbox_idem ON public.transaction_message_outbox(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_txn_outbox_status ON public.transaction_message_outbox(status, available_at);
CREATE INDEX IF NOT EXISTS idx_txn_outbox_recipient ON public.transaction_message_outbox(recipient_user_id);

GRANT ALL ON public.transaction_message_outbox TO service_role;
ALTER TABLE public.transaction_message_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "outbox_no_client" ON public.transaction_message_outbox;
CREATE POLICY "outbox_no_client" ON public.transaction_message_outbox
  AS RESTRICTIVE FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- 5) STORAGE OBJECT POLICIES (bucket already created private via tool)
-- Path: <user_id>/<request_id>/<uuid>.<ext>
-- Bucket-level file_size_limit/mime restrictions live at bucket config; we ALSO enforce here.
DROP POLICY IF EXISTS "rr_obj_owner_insert" ON storage.objects;
DROP POLICY IF EXISTS "rr_obj_owner_read"   ON storage.objects;
DROP POLICY IF EXISTS "rr_obj_owner_delete" ON storage.objects;
DROP POLICY IF EXISTS "rr_obj_admin_read"   ON storage.objects;

CREATE POLICY "rr_obj_owner_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'recharge-receipts'
    AND split_part(name, '/', 1) = auth.uid()::text
    AND split_part(name, '/', 2) <> ''
    AND (metadata->>'mimetype') IN ('image/jpeg','image/png','image/webp','application/pdf')
    AND COALESCE((metadata->>'size')::bigint, 0) <= 10 * 1024 * 1024
    AND EXISTS (
      SELECT 1 FROM public.recharge_requests r
      WHERE r.id::text = split_part(name, '/', 2)
        AND r.user_id  = auth.uid()
    )
  );

CREATE POLICY "rr_obj_owner_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'recharge-receipts'
    AND split_part(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "rr_obj_owner_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'recharge-receipts'
    AND split_part(name, '/', 1) = auth.uid()::text
    AND NOT EXISTS (
      SELECT 1 FROM public.recharge_receipts rr
      WHERE rr.storage_bucket = 'recharge-receipts'
        AND rr.storage_object_path = storage.objects.name
        AND rr.status <> 'uploaded'
    )
  );

CREATE POLICY "rr_obj_admin_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'recharge-receipts'
    AND has_permission(auth.uid(), 'recharge_receipts.read')
  );

-- 6) CI SECURITY AUDIT FUNCTION
CREATE OR REPLACE FUNCTION public.audit_authenticated_security_definer()
RETURNS TABLE(
  function_signature text,
  category           text,
  has_guard          boolean,
  guard_kind         text,
  verdict            text
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
  r record;
  src text;
  fname text;
  cat text;
  guard text;
  hasg boolean;
BEGIN
  FOR r IN
    SELECT DISTINCT n.nspname, p.proname, p.oid,
           pg_get_function_identity_arguments(p.oid) AS args,
           pg_get_functiondef(p.oid) AS def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a ON true
      JOIN pg_roles g ON g.oid = a.grantee
     WHERE n.nspname = 'public'
       AND p.prosecdef = true
       AND a.privilege_type = 'EXECUTE'
       AND g.rolname = 'authenticated'
  LOOP
    src   := lower(r.def);
    fname := r.proname;

    IF fname ~ '^(admin_|rbac_|assert_)' OR fname ~ '_admin_' THEN
      cat := 'admin';
    ELSIF fname ~ '(recharge|withdraw|wallet|ledger|coin|pearl|payment|refund|dispute|charging|finance|exchange)' THEN
      cat := 'financial';
    ELSIF fname ~ '^(_|tg_)' OR fname ~ '(outbox|internal)' THEN
      cat := 'internal_service';
    ELSIF fname ~ '(profile|me_|user_)' THEN
      cat := 'authenticated_user';
    ELSE
      cat := 'legacy';
    END IF;

    hasg := false; guard := NULL;
    IF src ~ '_require_perm\s*\(' THEN hasg := true; guard := '_require_perm';
    ELSIF src ~ 'has_permission\s*\(' THEN hasg := true; guard := 'has_permission';
    ELSIF src ~ 'has_role\s*\(' THEN hasg := true; guard := 'has_role';
    ELSIF src ~ 'is_admin\s*\(' THEN hasg := true; guard := 'is_admin';
    ELSIF src ~ 'auth\.uid\s*\(\s*\)\s+is\s+not\s+null' THEN hasg := true; guard := 'uid_not_null';
    ELSIF src ~ 'auth\.uid\s*\(\s*\)\s*=' OR src ~ '=\s*auth\.uid\s*\(\s*\)' THEN hasg := true; guard := 'ownership';
    ELSIF src ~ 'current_setting\s*\(\s*''role''' AND src ~ 'service_role' THEN hasg := true; guard := 'service_role_only';
    END IF;

    function_signature := r.nspname || '.' || r.proname || '(' || r.args || ')';
    category := cat; has_guard := hasg; guard_kind := guard;
    verdict := CASE
      WHEN cat IN ('admin','financial') AND NOT hasg THEN 'FAIL'
      WHEN NOT hasg THEN 'WARN'
      ELSE 'OK'
    END;
    RETURN NEXT;
  END LOOP;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.audit_authenticated_security_definer() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.audit_authenticated_security_definer() TO authenticated;
