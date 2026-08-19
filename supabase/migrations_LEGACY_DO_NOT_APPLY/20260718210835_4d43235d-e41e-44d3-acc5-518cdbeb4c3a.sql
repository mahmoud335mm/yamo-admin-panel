
INSERT INTO public.permissions (key, module, label_ar, label_en, description)
VALUES
  ('recharge_refunds.export',        'recharge_refunds', 'تصدير الاستردادات',       'Export refunds',        'Server-side redacted export'),
  ('recharge_refunds.read_attempts', 'recharge_refunds', 'قراءة محاولات الاسترداد', 'Read refund attempts',  'Read gateway attempts / webhooks')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.system_settings (key, value) VALUES
  ('enable_refund_admin_ui',      'true'::jsonb),
  ('enable_refund_execution',     'false'::jsonb),
  ('enable_refund_user_requests', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.resolve_refund_policy(
  _country text, _currency text, _gateway_id uuid, _gateway_mode text,
  _refund_type public.refund_type, _refund_scope public.refund_scope,
  _at timestamptz DEFAULT now()
) RETURNS TABLE (policy_id uuid, version integer, priority integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_scope_key text := _refund_type::text || ':' || _refund_scope::text;
  v_row record; v_found int := 0;
BEGIN
  FOR v_row IN
    WITH candidates AS (
      SELECT p.id, p.version,
        CASE
          WHEN p.gateway_id=_gateway_id AND p.country_code=_country AND p.currency_code=_currency THEN 1
          WHEN p.gateway_id=_gateway_id AND p.currency_code=_currency AND p.country_code IS NULL  THEN 2
          WHEN p.gateway_id=_gateway_id AND p.country_code IS NULL AND p.currency_code IS NULL    THEN 3
          WHEN p.gateway_id IS NULL AND p.country_code=_country AND p.currency_code=_currency     THEN 4
          WHEN p.gateway_id IS NULL AND p.country_code IS NULL AND p.currency_code=_currency      THEN 5
          WHEN p.gateway_id IS NULL AND p.country_code IS NULL AND p.currency_code IS NULL
               AND v_scope_key = ANY(p.refund_type_scope) THEN 6
          WHEN p.gateway_id IS NULL AND p.country_code IS NULL AND p.currency_code IS NULL
               AND (p.refund_type_scope IS NULL OR array_length(p.refund_type_scope,1) IS NULL
                    OR 'default' = ANY(p.refund_type_scope)) THEN 7
          ELSE NULL END AS pri
      FROM public.refund_policies p
      WHERE p.status='active'
        AND (p.starts_at IS NULL OR p.starts_at<=_at)
        AND (p.ends_at   IS NULL OR p.ends_at   > _at)
        AND (p.refund_type_scope IS NULL
             OR v_scope_key = ANY(p.refund_type_scope)
             OR 'default' = ANY(p.refund_type_scope))
    )
    SELECT id, version, pri FROM candidates WHERE pri IS NOT NULL
    ORDER BY pri ASC, version DESC
  LOOP
    IF v_found=0 THEN
      policy_id:=v_row.id; version:=v_row.version; priority:=v_row.pri; v_found:=1; RETURN NEXT;
    ELSIF v_row.pri=priority AND v_row.version=version THEN
      RAISE EXCEPTION 'POLICY_CONFLICT: overlapping refund policies at priority % (ids: %, %)', priority, policy_id, v_row.id;
    ELSE RETURN; END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.resolve_refund_policy(text,text,uuid,text,public.refund_type,public.refund_scope,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_refund_policy(text,text,uuid,text,public.refund_type,public.refund_scope,timestamptz) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.resolve_refund_retry_policy(
  _gateway_id uuid, _gateway_mode text, _at timestamptz DEFAULT now()
) RETURNS TABLE (policy_id uuid, version integer, priority integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row record; v_found int := 0;
BEGIN
  FOR v_row IN
    WITH candidates AS (
      SELECT p.id, p.version,
        CASE
          WHEN p.gateway_id=_gateway_id AND p.gateway_mode::text=_gateway_mode THEN 1
          WHEN p.gateway_id=_gateway_id AND p.gateway_mode IS NULL             THEN 2
          WHEN p.gateway_id IS NULL     AND p.gateway_mode::text=_gateway_mode THEN 3
          WHEN p.gateway_id IS NULL     AND p.gateway_mode IS NULL             THEN 4
          ELSE NULL END AS pri
      FROM public.refund_retry_policies p WHERE p.active=true
    )
    SELECT id, version, pri FROM candidates WHERE pri IS NOT NULL
    ORDER BY pri ASC, version DESC
  LOOP
    IF v_found=0 THEN
      policy_id:=v_row.id; version:=v_row.version; priority:=v_row.pri; v_found:=1; RETURN NEXT;
    ELSIF v_row.pri=priority AND v_row.version=version THEN
      RAISE EXCEPTION 'RETRY_POLICY_CONFLICT: overlapping retry policies at priority % (ids: %, %)', priority, policy_id, v_row.id;
    ELSE RETURN; END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.resolve_refund_retry_policy(uuid,text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_refund_retry_policy(uuid,text,timestamptz) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.assert_no_overlapping_refund_policies()
RETURNS TABLE (violation text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT format('DUP policy g=%s c=%s cur=%s scope=%s v=%s: %s rows',
      COALESCE(gateway_id::text,'*'), COALESCE(country_code,'*'),
      COALESCE(currency_code,'*'),
      COALESCE(array_to_string(refund_type_scope,','),'default'),
      version, c)
  FROM (
    SELECT gateway_id, country_code, currency_code, refund_type_scope, version, count(*) c
    FROM public.refund_policies WHERE status='active'
    GROUP BY 1,2,3,4,5 HAVING count(*) > 1
  ) d;
$$;
REVOKE ALL ON FUNCTION public.assert_no_overlapping_refund_policies() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_no_overlapping_refund_policies() TO service_role;

CREATE OR REPLACE FUNCTION public.assert_no_overlapping_refund_retry_policies()
RETURNS TABLE (violation text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT format('DUP retry gw=%s mode=%s v=%s: %s rows',
      COALESCE(gateway_id::text,'*'), COALESCE(gateway_mode::text,'*'), version, c)
  FROM (
    SELECT gateway_id, gateway_mode, version, count(*) c
    FROM public.refund_retry_policies WHERE active=true
    GROUP BY 1,2,3 HAVING count(*) > 1
  ) d;
$$;
REVOKE ALL ON FUNCTION public.assert_no_overlapping_refund_retry_policies() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_no_overlapping_refund_retry_policies() TO service_role;
