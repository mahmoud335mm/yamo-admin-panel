
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='payment_method_status' AND e.enumlabel='paused') THEN ALTER TYPE payment_method_status ADD VALUE 'paused'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='payment_method_status' AND e.enumlabel='archived') THEN ALTER TYPE payment_method_status ADD VALUE 'archived'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='payment_method_status' AND e.enumlabel='draft') THEN ALTER TYPE payment_method_status ADD VALUE 'draft'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='payment_method_status' AND e.enumlabel='under_review') THEN ALTER TYPE payment_method_status ADD VALUE 'under_review'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='payment_method_status' AND e.enumlabel='misconfigured') THEN ALTER TYPE payment_method_status ADD VALUE 'misconfigured'; END IF; END $$;

INSERT INTO permissions (key, module, label_ar, label_en, description) VALUES
  ('payment_methods.activate',        'finance', 'تفعيل وسيلة دفع', 'Activate payment method', null),
  ('payment_methods.pause',           'finance', 'إيقاف وسيلة دفع', 'Pause payment method', null),
  ('payment_methods.archive',         'finance', 'أرشفة وسيلة دفع', 'Archive payment method', null),
  ('payment_methods.reorder',         'finance', 'إعادة ترتيب الوسائل', 'Reorder payment methods', null),
  ('payment_method_accounts.create',  'finance', 'إضافة حساب وسيلة دفع', 'Create payment account', null),
  ('payment_method_accounts.update',  'finance', 'تعديل حساب وسيلة دفع', 'Update payment account', null),
  ('payment_method_accounts.pause',   'finance', 'إيقاف حساب وسيلة دفع', 'Pause payment account', null),
  ('payment_method_limits.manage',    'finance', 'إدارة حدود وسائل الدفع', 'Manage payment limits', null)
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role, permission_key)
SELECT r.role, p.key
FROM (VALUES ('super_admin'::admin_role), ('admin'::admin_role), ('finance'::admin_role)) AS r(role)
CROSS JOIN permissions p
WHERE p.key IN (
    'payment_methods.activate','payment_methods.pause','payment_methods.archive','payment_methods.reorder',
    'payment_method_accounts.create','payment_method_accounts.update','payment_method_accounts.pause',
    'payment_method_limits.manage'
  )
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public._assert_reason(_reason text) RETURNS void
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN
    RAISE EXCEPTION 'REASON_REQUIRED_MIN_5' USING ERRCODE = '22023';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.create_payment_method(
  _code text, _name_ar text, _name_en text, _method_type payment_method_type,
  _country_code text, _currency_code text,
  _gateway_id uuid, _for_recharge boolean, _for_withdrawal boolean,
  _for_users boolean, _for_agents boolean,
  _min_amount numeric, _max_amount numeric,
  _fixed_fee numeric, _percentage_fee numeric,
  _sort_order integer, _logo_url text, _qr_url text,
  _instructions_ar text, _instructions_en text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _new_id uuid;
BEGIN
  IF NOT has_permission(_uid, 'payment_methods.create') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  IF _code IS NULL OR length(btrim(_code)) < 2 THEN RAISE EXCEPTION 'CODE_REQUIRED'; END IF;
  IF _min_amount < 0 OR _fixed_fee < 0 OR _percentage_fee < 0 THEN RAISE EXCEPTION 'NEGATIVE_NUMERIC'; END IF;
  IF _max_amount IS NOT NULL AND _max_amount < _min_amount THEN RAISE EXCEPTION 'MAX_LT_MIN'; END IF;
  IF _gateway_id IS NOT NULL THEN
    PERFORM 1 FROM payment_gateways g WHERE g.id=_gateway_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'GATEWAY_NOT_FOUND'; END IF;
  END IF;
  INSERT INTO payment_methods (
    code, name_ar, name_en, method_type, country_code, currency_code, gateway_id,
    for_recharge, for_withdrawal, for_users, for_agents,
    min_amount, max_amount, fixed_fee, percentage_fee,
    sort_order, logo_url, qr_url, instructions_ar, instructions_en,
    status, created_by, updated_by
  ) VALUES (
    _code, _name_ar, _name_en, _method_type, _country_code, _currency_code, _gateway_id,
    _for_recharge, _for_withdrawal, _for_users, _for_agents,
    _min_amount, _max_amount, _fixed_fee, _percentage_fee,
    _sort_order, _logo_url, _qr_url, _instructions_ar, _instructions_en,
    'draft'::payment_method_status, _uid, _uid
  ) RETURNING id INTO _new_id;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method.create', 'payment_method', _new_id::text, jsonb_build_object('code',_code));
  RETURN _new_id;
END $$;

CREATE OR REPLACE FUNCTION public.update_payment_method(_id uuid, _patch jsonb, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT has_permission(_uid, 'payment_methods.update') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  UPDATE payment_methods SET
    name_ar=COALESCE(_patch->>'name_ar',name_ar),
    name_en=COALESCE(_patch->>'name_en',name_en),
    country_code=COALESCE(_patch->>'country_code',country_code),
    currency_code=COALESCE(_patch->>'currency_code',currency_code),
    gateway_id=COALESCE(NULLIF(_patch->>'gateway_id','')::uuid,gateway_id),
    logo_url=COALESCE(_patch->>'logo_url',logo_url),
    qr_url=COALESCE(_patch->>'qr_url',qr_url),
    instructions_ar=COALESCE(_patch->>'instructions_ar',instructions_ar),
    instructions_en=COALESCE(_patch->>'instructions_en',instructions_en),
    min_amount=COALESCE((_patch->>'min_amount')::numeric,min_amount),
    max_amount=COALESCE((_patch->>'max_amount')::numeric,max_amount),
    fixed_fee=COALESCE((_patch->>'fixed_fee')::numeric,fixed_fee),
    percentage_fee=COALESCE((_patch->>'percentage_fee')::numeric,percentage_fee),
    sort_order=COALESCE((_patch->>'sort_order')::int,sort_order),
    for_recharge=COALESCE((_patch->>'for_recharge')::boolean,for_recharge),
    for_withdrawal=COALESCE((_patch->>'for_withdrawal')::boolean,for_withdrawal),
    for_users=COALESCE((_patch->>'for_users')::boolean,for_users),
    for_agents=COALESCE((_patch->>'for_agents')::boolean,for_agents),
    updated_by=_uid
  WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method.update', 'payment_method', _id::text,
          jsonb_build_object('reason', _reason, 'patch_keys', (SELECT jsonb_agg(k) FROM jsonb_object_keys(_patch) k)));
END $$;

CREATE OR REPLACE FUNCTION public.activate_payment_method(_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _rec payment_methods%rowtype;
BEGIN
  IF NOT has_permission(_uid, 'payment_methods.activate') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  PERFORM _assert_reason(_reason);
  SELECT * INTO _rec FROM payment_methods WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF _rec.currency_code IS NULL OR _rec.currency_code='' THEN RAISE EXCEPTION 'MISSING_CURRENCY'; END IF;
  IF _rec.for_recharge=false AND _rec.for_withdrawal=false THEN RAISE EXCEPTION 'NO_OPERATION_ENABLED'; END IF;
  IF _rec.gateway_id IS NOT NULL THEN
    PERFORM 1 FROM payment_gateways g WHERE g.id=_rec.gateway_id AND g.status='active';
    IF NOT FOUND THEN RAISE EXCEPTION 'GATEWAY_INACTIVE'; END IF;
  END IF;
  IF _rec.method_type IN ('wallet','bank_transfer','mobile_money','qr','manual') THEN
    PERFORM 1 FROM payment_method_accounts WHERE method_id=_id AND active=true LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'NO_ACTIVE_ACCOUNT'; END IF;
  END IF;
  UPDATE payment_methods SET status='active', updated_by=_uid WHERE id=_id;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method.activate', 'payment_method', _id::text, jsonb_build_object('reason',_reason));
END $$;

CREATE OR REPLACE FUNCTION public.pause_payment_method(_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT has_permission(_uid, 'payment_methods.pause') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  PERFORM _assert_reason(_reason);
  UPDATE payment_methods SET status='paused', updated_by=_uid WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method.pause', 'payment_method', _id::text, jsonb_build_object('reason',_reason));
END $$;

CREATE OR REPLACE FUNCTION public.archive_payment_method(_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT has_permission(_uid, 'payment_methods.archive') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  PERFORM _assert_reason(_reason);
  UPDATE payment_methods SET status='archived', updated_by=_uid WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method.archive', 'payment_method', _id::text, jsonb_build_object('reason',_reason));
END $$;

CREATE OR REPLACE FUNCTION public.reorder_payment_methods(_order uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _i int;
BEGIN
  IF NOT has_permission(_uid, 'payment_methods.reorder') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  FOR _i IN 1..array_length(_order,1) LOOP
    UPDATE payment_methods SET sort_order=_i*10, updated_by=_uid WHERE id=_order[_i];
  END LOOP;
  INSERT INTO audit_logs (actor_id, action, entity_type, metadata)
  VALUES (_uid, 'payment_method.reorder', 'payment_method', jsonb_build_object('count', array_length(_order,1)));
END $$;

CREATE OR REPLACE FUNCTION public.create_payment_method_account(
  _method_id uuid, _label text,
  _account_number_masked text, _account_number_secret_ref text,
  _beneficiary_name_masked text, _beneficiary_name_secret_ref text,
  _bank_name text, _swift_code text,
  _iban_masked text, _iban_secret_ref text,
  _extra_data jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid;
BEGIN
  IF NOT has_permission(_uid, 'payment_method_accounts.create') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  INSERT INTO payment_method_accounts (
    method_id, label,
    account_number_masked, account_number_secret_ref,
    beneficiary_name_masked, beneficiary_name_secret_ref,
    bank_name, swift_code, iban_masked, iban_secret_ref,
    extra_data, active, created_by
  ) VALUES (
    _method_id, _label,
    _account_number_masked, _account_number_secret_ref,
    _beneficiary_name_masked, _beneficiary_name_secret_ref,
    _bank_name, _swift_code, _iban_masked, _iban_secret_ref,
    COALESCE(_extra_data,'{}'::jsonb), true, _uid
  ) RETURNING id INTO _id;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method_account.create', 'payment_method_account', _id::text,
          jsonb_build_object('method_id', _method_id, 'label', _label));
  RETURN _id;
END $$;

CREATE OR REPLACE FUNCTION public.update_payment_method_account(_id uuid, _patch jsonb, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT has_permission(_uid, 'payment_method_accounts.update') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  UPDATE payment_method_accounts SET
    label=COALESCE(_patch->>'label',label),
    account_number_masked=COALESCE(_patch->>'account_number_masked',account_number_masked),
    account_number_secret_ref=COALESCE(_patch->>'account_number_secret_ref',account_number_secret_ref),
    beneficiary_name_masked=COALESCE(_patch->>'beneficiary_name_masked',beneficiary_name_masked),
    beneficiary_name_secret_ref=COALESCE(_patch->>'beneficiary_name_secret_ref',beneficiary_name_secret_ref),
    bank_name=COALESCE(_patch->>'bank_name',bank_name),
    swift_code=COALESCE(_patch->>'swift_code',swift_code),
    iban_masked=COALESCE(_patch->>'iban_masked',iban_masked),
    iban_secret_ref=COALESCE(_patch->>'iban_secret_ref',iban_secret_ref),
    extra_data=COALESCE(_patch->'extra_data',extra_data)
  WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method_account.update', 'payment_method_account', _id::text,
          jsonb_build_object('reason', _reason, 'patch_keys', (SELECT jsonb_agg(k) FROM jsonb_object_keys(_patch) k)));
END $$;

CREATE OR REPLACE FUNCTION public.set_payment_method_account_active(_id uuid, _active boolean, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT has_permission(_uid, 'payment_method_accounts.pause') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  PERFORM _assert_reason(_reason);
  UPDATE payment_method_accounts SET active=_active WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method_account.set_active', 'payment_method_account', _id::text,
          jsonb_build_object('active', _active, 'reason', _reason));
END $$;

CREATE OR REPLACE FUNCTION public.upsert_payment_method_limit(
  _method_id uuid, _scope text,
  _per_txn_min numeric, _per_txn_max numeric,
  _daily_max numeric, _weekly_max numeric, _monthly_max numeric
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid;
BEGIN
  IF NOT has_permission(_uid, 'payment_method_limits.manage') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  INSERT INTO payment_method_limits (method_id, scope, per_txn_min, per_txn_max, daily_max, weekly_max, monthly_max)
  VALUES (_method_id, _scope, _per_txn_min, _per_txn_max, _daily_max, _weekly_max, _monthly_max)
  RETURNING id INTO _id;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method_limit.upsert', 'payment_method_limit', _id::text,
          jsonb_build_object('method_id',_method_id,'scope',_scope));
  RETURN _id;
END $$;

CREATE OR REPLACE FUNCTION public.resolve_payment_method_account(
  _method_id uuid, _country_code text, _currency_code text,
  _operation_type text, _amount numeric
) RETURNS TABLE (
  account_id uuid, label text,
  account_number_masked text, beneficiary_name_masked text,
  iban_masked text, bank_name text, swift_code text,
  extra_data jsonb, fixed_fee numeric, percentage_fee numeric,
  computed_fee numeric
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _pm payment_methods%rowtype; _acc payment_method_accounts%rowtype;
BEGIN
  SELECT * INTO _pm FROM payment_methods WHERE id=_method_id AND status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'METHOD_NOT_ACTIVE'; END IF;
  IF _operation_type='recharge'   AND NOT _pm.for_recharge   THEN RAISE EXCEPTION 'NOT_FOR_RECHARGE'; END IF;
  IF _operation_type='withdrawal' AND NOT _pm.for_withdrawal THEN RAISE EXCEPTION 'NOT_FOR_WITHDRAWAL'; END IF;
  IF _pm.country_code IS NOT NULL AND _country_code IS NOT NULL AND _pm.country_code <> _country_code THEN RAISE EXCEPTION 'COUNTRY_MISMATCH'; END IF;
  IF _pm.currency_code <> _currency_code THEN RAISE EXCEPTION 'CURRENCY_MISMATCH'; END IF;
  IF _amount < _pm.min_amount OR (_pm.max_amount IS NOT NULL AND _amount > _pm.max_amount) THEN RAISE EXCEPTION 'AMOUNT_OUT_OF_RANGE'; END IF;
  SELECT * INTO _acc FROM payment_method_accounts
    WHERE method_id=_method_id AND active=true
    ORDER BY created_at ASC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'NO_ACTIVE_ACCOUNT'; END IF;
  RETURN QUERY SELECT
    _acc.id, _acc.label,
    _acc.account_number_masked, _acc.beneficiary_name_masked,
    _acc.iban_masked, _acc.bank_name, _acc.swift_code,
    _acc.extra_data, _pm.fixed_fee, _pm.percentage_fee,
    (_pm.fixed_fee + (_amount * _pm.percentage_fee / 100.0))::numeric;
END $$;

CREATE OR REPLACE FUNCTION public.reveal_payment_account_sensitive_data(_id uuid, _reason text)
RETURNS TABLE (
  account_number_secret_ref text,
  beneficiary_name_secret_ref text,
  iban_secret_ref text
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _acc payment_method_accounts%rowtype;
BEGIN
  IF NOT has_permission(_uid, 'payment_method_accounts.read_sensitive') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE='42501'; END IF;
  PERFORM _assert_reason(_reason);
  SELECT * INTO _acc FROM payment_method_accounts WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (_uid, 'payment_method_account.reveal_sensitive', 'payment_method_account', _id::text,
          jsonb_build_object('reason', _reason));
  RETURN QUERY SELECT _acc.account_number_secret_ref, _acc.beneficiary_name_secret_ref, _acc.iban_secret_ref;
END $$;

REVOKE ALL ON FUNCTION public.create_payment_method(text,text,text,payment_method_type,text,text,uuid,boolean,boolean,boolean,boolean,numeric,numeric,numeric,numeric,integer,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_payment_method(uuid,jsonb,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.activate_payment_method(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pause_payment_method(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.archive_payment_method(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reorder_payment_methods(uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_payment_method_account(uuid,text,text,text,text,text,text,text,text,text,jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_payment_method_account(uuid,jsonb,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_payment_method_account_active(uuid,boolean,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.upsert_payment_method_limit(uuid,text,numeric,numeric,numeric,numeric,numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reveal_payment_account_sensitive_data(uuid,text) FROM PUBLIC, anon;
