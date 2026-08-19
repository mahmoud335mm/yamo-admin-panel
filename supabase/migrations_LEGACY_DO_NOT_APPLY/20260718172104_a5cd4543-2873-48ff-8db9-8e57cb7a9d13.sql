
INSERT INTO public.permissions(key, module, label_ar, label_en, description) VALUES
  ('coin_prices.pause','finance','إيقاف مؤقت لسعر الكوينز','Pause coin price rule',''),
  ('coin_prices.archive','finance','أرشفة سعر الكوينز','Archive coin price rule','')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions(role, permission_key)
SELECT r::admin_role, p FROM (VALUES
  ('super_admin','coin_prices.pause'),('super_admin','coin_prices.archive'),
  ('finance','coin_prices.pause'),('finance','coin_prices.archive')
) v(r,p)
WHERE EXISTS (SELECT 1 FROM roles WHERE role = v.r::admin_role)
ON CONFLICT DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='coin_price_status'::regtype AND enumlabel='archived') THEN
    ALTER TYPE coin_price_status ADD VALUE 'archived'; END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='coin_price_status'::regtype AND enumlabel='paused') THEN
    ALTER TYPE coin_price_status ADD VALUE 'paused'; END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='coin_price_status'::regtype AND enumlabel='expired') THEN
    ALTER TYPE coin_price_status ADD VALUE 'expired'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.validate_coin_price_conflicts(_rule_id uuid)
RETURNS TABLE(conflict_rule_id uuid, conflict_code text, conflict_name text, reason text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE me RECORD;
BEGIN
  IF NOT has_permission(auth.uid(),'coin_prices.read') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT * INTO me FROM coin_price_rules WHERE id=_rule_id;
  IF me.id IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT r.id, r.code, r.name, 'تداخل في الشروط والفترة والأولوية'::text
  FROM coin_price_rules r
  WHERE r.id <> _rule_id
    AND r.status IN ('published','review')
    AND r.currency_code = me.currency_code
    AND (r.country_code IS NOT DISTINCT FROM me.country_code)
    AND r.priority = me.priority
    AND COALESCE(r.payment_gateway_id,'00000000-0000-0000-0000-000000000000'::uuid) IS NOT DISTINCT FROM COALESCE(me.payment_gateway_id,'00000000-0000-0000-0000-000000000000'::uuid)
    AND COALESCE(r.payment_method_id,'00000000-0000-0000-0000-000000000000'::uuid) IS NOT DISTINCT FROM COALESCE(me.payment_method_id,'00000000-0000-0000-0000-000000000000'::uuid)
    AND r.min_coin_amount <= COALESCE(me.max_coin_amount, 9223372036854775807::bigint)
    AND COALESCE(r.max_coin_amount, 9223372036854775807::bigint) >= me.min_coin_amount
    AND COALESCE(r.starts_at,'-infinity'::timestamptz) <= COALESCE(me.ends_at,'infinity'::timestamptz)
    AND COALESCE(r.ends_at,'infinity'::timestamptz) >= COALESCE(me.starts_at,'-infinity'::timestamptz);
END $$;
GRANT EXECUTE ON FUNCTION public.validate_coin_price_conflicts(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_coin_price_rule(_payload jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE new_id uuid; me uuid := auth.uid();
BEGIN
  IF NOT has_permission(me,'coin_prices.create') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  INSERT INTO coin_price_rules(
    code, name, country_code, currency_code, user_type,
    min_user_level, max_user_level, min_vip, max_vip,
    agency_id, charging_agent_user_id, payment_gateway_id, payment_method_id,
    min_coin_amount, max_coin_amount, base_unit_price, buy_unit_price,
    discount_pct, bonus_pct, fixed_fee, percentage_fee, tax_pct, priority,
    starts_at, ends_at, status, created_by, updated_by
  ) VALUES (
    COALESCE(NULLIF(_payload->>'code',''),'rule_'||substr(md5(random()::text||clock_timestamp()::text),1,10)),
    _payload->>'name',
    NULLIF(_payload->>'country_code',''),
    _payload->>'currency_code',
    NULLIF(_payload->>'user_type',''),
    (_payload->>'min_user_level')::int,
    (_payload->>'max_user_level')::int,
    (_payload->>'min_vip')::int,
    (_payload->>'max_vip')::int,
    NULLIF(_payload->>'agency_id','')::uuid,
    NULLIF(_payload->>'charging_agent_user_id','')::uuid,
    NULLIF(_payload->>'payment_gateway_id','')::uuid,
    NULLIF(_payload->>'payment_method_id','')::uuid,
    COALESCE((_payload->>'min_coin_amount')::bigint, 0),
    (_payload->>'max_coin_amount')::bigint,
    (_payload->>'base_unit_price')::numeric,
    (_payload->>'buy_unit_price')::numeric,
    COALESCE((_payload->>'discount_pct')::numeric, 0),
    COALESCE((_payload->>'bonus_pct')::numeric, 0),
    COALESCE((_payload->>'fixed_fee')::numeric, 0),
    COALESCE((_payload->>'percentage_fee')::numeric, 0),
    COALESCE((_payload->>'tax_pct')::numeric, 0),
    COALESCE((_payload->>'priority')::int, 100),
    (_payload->>'starts_at')::timestamptz,
    (_payload->>'ends_at')::timestamptz,
    'draft'::coin_price_status, me, me
  ) RETURNING id INTO new_id;
  INSERT INTO audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (me,'coin_price_rule.create','coin_price_rule',new_id,_payload);
  RETURN new_id;
END $$;
GRANT EXECUTE ON FUNCTION public.create_coin_price_rule(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_coin_price_rule(_id uuid, _payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE me uuid := auth.uid(); old jsonb;
BEGIN
  IF NOT has_permission(me,'coin_prices.update') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT to_jsonb(r.*) INTO old FROM coin_price_rules r WHERE id=_id;
  IF old IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF (old->>'status') = 'archived' THEN RAISE EXCEPTION 'RULE_ARCHIVED'; END IF;

  UPDATE coin_price_rules SET
    name = COALESCE(_payload->>'name', name),
    country_code = CASE WHEN _payload ? 'country_code' THEN NULLIF(_payload->>'country_code','') ELSE country_code END,
    currency_code = COALESCE(_payload->>'currency_code', currency_code),
    user_type = CASE WHEN _payload ? 'user_type' THEN NULLIF(_payload->>'user_type','') ELSE user_type END,
    min_user_level = CASE WHEN _payload ? 'min_user_level' THEN (_payload->>'min_user_level')::int ELSE min_user_level END,
    max_user_level = CASE WHEN _payload ? 'max_user_level' THEN (_payload->>'max_user_level')::int ELSE max_user_level END,
    min_vip = CASE WHEN _payload ? 'min_vip' THEN (_payload->>'min_vip')::int ELSE min_vip END,
    max_vip = CASE WHEN _payload ? 'max_vip' THEN (_payload->>'max_vip')::int ELSE max_vip END,
    agency_id = CASE WHEN _payload ? 'agency_id' THEN NULLIF(_payload->>'agency_id','')::uuid ELSE agency_id END,
    charging_agent_user_id = CASE WHEN _payload ? 'charging_agent_user_id' THEN NULLIF(_payload->>'charging_agent_user_id','')::uuid ELSE charging_agent_user_id END,
    payment_gateway_id = CASE WHEN _payload ? 'payment_gateway_id' THEN NULLIF(_payload->>'payment_gateway_id','')::uuid ELSE payment_gateway_id END,
    payment_method_id = CASE WHEN _payload ? 'payment_method_id' THEN NULLIF(_payload->>'payment_method_id','')::uuid ELSE payment_method_id END,
    min_coin_amount = COALESCE((_payload->>'min_coin_amount')::bigint, min_coin_amount),
    max_coin_amount = CASE WHEN _payload ? 'max_coin_amount' THEN (_payload->>'max_coin_amount')::bigint ELSE max_coin_amount END,
    base_unit_price = COALESCE((_payload->>'base_unit_price')::numeric, base_unit_price),
    buy_unit_price = CASE WHEN _payload ? 'buy_unit_price' THEN (_payload->>'buy_unit_price')::numeric ELSE buy_unit_price END,
    discount_pct = COALESCE((_payload->>'discount_pct')::numeric, discount_pct),
    bonus_pct = COALESCE((_payload->>'bonus_pct')::numeric, bonus_pct),
    fixed_fee = COALESCE((_payload->>'fixed_fee')::numeric, fixed_fee),
    percentage_fee = COALESCE((_payload->>'percentage_fee')::numeric, percentage_fee),
    tax_pct = COALESCE((_payload->>'tax_pct')::numeric, tax_pct),
    priority = COALESCE((_payload->>'priority')::int, priority),
    starts_at = CASE WHEN _payload ? 'starts_at' THEN (_payload->>'starts_at')::timestamptz ELSE starts_at END,
    ends_at = CASE WHEN _payload ? 'ends_at' THEN (_payload->>'ends_at')::timestamptz ELSE ends_at END,
    version = version + 1, updated_by = me, updated_at = now()
  WHERE id=_id;
  INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata)
  VALUES (me,'coin_price_rule.update','coin_price_rule',_id,jsonb_build_object('old',old,'new',_payload));
END $$;
GRANT EXECUTE ON FUNCTION public.update_coin_price_rule(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.archive_coin_price_rule(_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE me uuid := auth.uid();
BEGIN
  IF NOT has_permission(me,'coin_prices.archive') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF _reason IS NULL OR length(trim(_reason))<3 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE coin_price_rules SET status='archived'::coin_price_status, updated_by=me, updated_at=now() WHERE id=_id;
  INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata)
  VALUES (me,'coin_price_rule.archive','coin_price_rule',_id,jsonb_build_object('reason',_reason));
END $$;
GRANT EXECUTE ON FUNCTION public.archive_coin_price_rule(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.publish_coin_price_rule_v2(_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp
AS $$
DECLARE me uuid := auth.uid(); conflicts int;
BEGIN
  IF NOT has_permission(me,'coin_prices.publish') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF _reason IS NULL OR length(trim(_reason))<3 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT count(*) INTO conflicts FROM validate_coin_price_conflicts(_id);
  IF conflicts > 0 THEN RAISE EXCEPTION 'CONFLICT_DETECTED_% ',conflicts; END IF;
  UPDATE coin_price_rules SET status='published'::coin_price_status, updated_by=me, updated_at=now() WHERE id=_id;
  INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata)
  VALUES (me,'coin_price_rule.publish','coin_price_rule',_id,jsonb_build_object('reason',_reason));
END $$;
GRANT EXECUTE ON FUNCTION public.publish_coin_price_rule_v2(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.pause_coin_price_rule_v2(_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp
AS $$
DECLARE me uuid := auth.uid();
BEGIN
  IF NOT has_permission(me,'coin_prices.pause') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF _reason IS NULL OR length(trim(_reason))<3 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE coin_price_rules SET status='paused'::coin_price_status, updated_by=me, updated_at=now() WHERE id=_id;
  INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata)
  VALUES (me,'coin_price_rule.pause','coin_price_rule',_id,jsonb_build_object('reason',_reason));
END $$;
GRANT EXECUTE ON FUNCTION public.pause_coin_price_rule_v2(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rollback_coin_price_rule_v2(_id uuid, _to_version int, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp
AS $$
DECLARE me uuid := auth.uid(); snap jsonb;
BEGIN
  IF NOT has_permission(me,'coin_prices.rollback') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF _reason IS NULL OR length(trim(_reason))<3 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT snapshot INTO snap FROM coin_price_versions WHERE rule_id=_id AND version=_to_version;
  IF snap IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  UPDATE coin_price_rules SET
    name = COALESCE(snap->>'name', name),
    country_code = NULLIF(snap->>'country_code',''),
    currency_code = COALESCE(snap->>'currency_code', currency_code),
    min_coin_amount = COALESCE((snap->>'min_coin_amount')::bigint, min_coin_amount),
    max_coin_amount = (snap->>'max_coin_amount')::bigint,
    base_unit_price = COALESCE((snap->>'base_unit_price')::numeric, base_unit_price),
    discount_pct = COALESCE((snap->>'discount_pct')::numeric, discount_pct),
    bonus_pct = COALESCE((snap->>'bonus_pct')::numeric, bonus_pct),
    fixed_fee = COALESCE((snap->>'fixed_fee')::numeric, fixed_fee),
    percentage_fee = COALESCE((snap->>'percentage_fee')::numeric, percentage_fee),
    tax_pct = COALESCE((snap->>'tax_pct')::numeric, tax_pct),
    priority = COALESCE((snap->>'priority')::int, priority),
    version = version + 1, updated_by = me, updated_at = now()
  WHERE id=_id;
  INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata)
  VALUES (me,'coin_price_rule.rollback','coin_price_rule',_id,jsonb_build_object('to_version',_to_version,'reason',_reason));
END $$;
GRANT EXECUTE ON FUNCTION public.rollback_coin_price_rule_v2(uuid,int,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.simulate_coin_price(_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp
AS $$
DECLARE
  _country text := _payload->>'country';
  _currency text := _payload->>'currency';
  _coin_amount bigint := (_payload->>'coin_amount')::bigint;
  _user_id uuid := NULLIF(_payload->>'user_id','')::uuid;
  _gw uuid := NULLIF(_payload->>'payment_gateway_id','')::uuid;
  _pm uuid := NULLIF(_payload->>'payment_method_id','')::uuid;
  chosen jsonb; candidates jsonb;
BEGIN
  IF NOT has_permission(auth.uid(),'coin_prices.read') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  BEGIN
    SELECT to_jsonb(x) || jsonb_build_object('name',r.name,'code',r.code,'priority',r.priority)
      INTO chosen
    FROM resolve_coin_price(_country,_currency,_coin_amount,_user_id,_gw,_pm) x
    JOIN coin_price_rules r ON r.id = x.rule_id;
  EXCEPTION WHEN OTHERS THEN
    chosen := jsonb_build_object('error', SQLERRM);
  END;

  SELECT jsonb_agg(jsonb_build_object(
    'id',r.id,'name',r.name,'code',r.code,'status',r.status::text,
    'priority',r.priority,'country_code',r.country_code,'currency_code',r.currency_code,
    'min_coin_amount',r.min_coin_amount,'max_coin_amount',r.max_coin_amount,
    'base_unit_price',r.base_unit_price,
    'chosen', (chosen->>'rule_id') IS NOT NULL AND (chosen->>'rule_id')::uuid = r.id,
    'reason', CASE
      WHEN r.status::text <> 'published' THEN 'الحالة ليست منشورة'
      WHEN r.currency_code <> _currency THEN 'عملة مختلفة'
      WHEN r.country_code IS NOT NULL AND r.country_code <> _country THEN 'دولة مختلفة'
      WHEN r.min_coin_amount > _coin_amount THEN 'الكمية أقل من الحد الأدنى'
      WHEN r.max_coin_amount IS NOT NULL AND r.max_coin_amount < _coin_amount THEN 'الكمية أكبر من الحد الأعلى'
      WHEN r.starts_at IS NOT NULL AND r.starts_at > now() THEN 'لم تبدأ بعد'
      WHEN r.ends_at IS NOT NULL AND r.ends_at <= now() THEN 'انتهت الصلاحية'
      WHEN (chosen->>'rule_id') IS NOT NULL AND (chosen->>'rule_id')::uuid = r.id THEN 'القاعدة المختارة'
      ELSE 'قاعدة أقل أولوية أو غير مطابقة كليًا'
    END
  ) ORDER BY r.priority) INTO candidates
  FROM coin_price_rules r
  WHERE r.currency_code = _currency
    AND (r.country_code IS NULL OR r.country_code = _country);

  RETURN jsonb_build_object('chosen',chosen,'candidates',COALESCE(candidates,'[]'::jsonb),'inputs',_payload);
END $$;
GRANT EXECUTE ON FUNCTION public.simulate_coin_price(jsonb) TO authenticated;
