
CREATE TABLE IF NOT EXISTS public.financial_read_only_allowlist (
  function_name   text PRIMARY KEY,
  reason          text NOT NULL,
  reviewed_by     text NOT NULL DEFAULT 'security-review-5A.1',
  reviewed_at     timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.financial_read_only_allowlist TO authenticated;
ALTER TABLE public.financial_read_only_allowlist ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allowlist_read" ON public.financial_read_only_allowlist
  FOR SELECT TO authenticated USING (true);

INSERT INTO public.financial_read_only_allowlist(function_name, reason) VALUES
  ('get_available_payment_methods',       'Read-only catalog of enabled payment methods; no PII, no state change'),
  ('is_charging_agency_owner',            'Boolean predicate used by RLS; parametric ownership check, no data leak'),
  ('is_charging_agent',                   'Boolean role predicate for UI gating; safe to expose'),
  ('resolve_coin_price',                  'Pure pricing calculator over published price rules; no writes'),
  ('resolve_payment_method_account',      'Read-only account resolver; returns only masked account_ref, no secrets'),
  ('resolve_pearl_purchase_price',        'Pure pricing calculator over published pearl rules; no writes'),
  ('resolve_pearl_to_coin_exchange_rate', 'Pure FX calculator over published exchange rules; no writes'),
  ('resolve_pearl_withdrawal_price',      'Pure pricing calculator over published pearl rules; no writes')
ON CONFLICT (function_name) DO NOTHING;

-- Update classifier to consult the allowlist
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
  r record; src text; fname text; cat text; guard text;
  hasg boolean; is_trigger boolean; is_allowlisted boolean;
BEGIN
  FOR r IN
    SELECT DISTINCT n.nspname, p.proname, p.oid,
           pg_get_function_identity_arguments(p.oid) AS args,
           pg_get_functiondef(p.oid) AS def,
           t.typname AS rettype
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_type t ON t.oid = p.prorettype
      JOIN aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a ON true
      JOIN pg_roles g ON g.oid = a.grantee
     WHERE n.nspname = 'public'
       AND p.prosecdef = true
       AND a.privilege_type = 'EXECUTE'
       AND g.rolname = 'authenticated'
  LOOP
    src := lower(r.def); fname := r.proname;
    is_trigger := (r.rettype = 'trigger');
    is_allowlisted := EXISTS (SELECT 1 FROM public.financial_read_only_allowlist WHERE function_name = fname);

    IF is_trigger OR fname ~ '^(_|tg_)' OR fname ~ '(outbox|internal|_snapshot)' THEN
      cat := 'internal_service';
    ELSIF fname ~ '^(admin_|rbac_|assert_)' OR fname ~ '_admin_' THEN
      cat := 'admin';
    ELSIF fname ~ '(recharge|withdraw|wallet|ledger|coin|pearl|payment|refund|dispute|charging|finance|exchange)' THEN
      cat := 'financial';
    ELSIF fname ~ '(profile|me_|user_)' THEN
      cat := 'authenticated_user';
    ELSE cat := 'legacy';
    END IF;

    hasg := false; guard := NULL;
    IF is_allowlisted THEN hasg := true; guard := 'reviewed_read_only';
    ELSIF src ~ '_require_perm\s*\(' THEN hasg := true; guard := '_require_perm';
    ELSIF src ~ 'has_permission\s*\(' THEN hasg := true; guard := 'has_permission';
    ELSIF src ~ 'has_role\s*\(' THEN hasg := true; guard := 'has_role';
    ELSIF src ~ 'is_admin\s*\(' THEN hasg := true; guard := 'is_admin';
    ELSIF src ~ 'auth\.uid\s*\(\s*\)\s+is\s+null' THEN hasg := true; guard := 'not_authenticated_raise';
    ELSIF src ~ 'auth\.uid\s*\(\s*\)\s+is\s+not\s+null' THEN hasg := true; guard := 'uid_not_null';
    ELSIF src ~ '=\s*auth\.uid\s*\(\s*\)' OR src ~ 'auth\.uid\s*\(\s*\)\s*=' THEN hasg := true; guard := 'ownership';
    ELSIF src ~ 'current_setting\s*\(\s*''role''' AND src ~ 'service_role' THEN hasg := true; guard := 'service_role_only';
    ELSIF src ~ '_admin_wallet_adjust\s*\(' OR src ~ '_admin_[a-z_]+\s*\(' THEN hasg := true; guard := 'delegates_to_admin_helper';
    ELSIF src ~ 'token_hash' AND src ~ 'digest\s*\(' THEN hasg := true; guard := 'token_hash_match';
    END IF;

    function_signature := r.nspname || '.' || r.proname || '(' || r.args || ')';
    category := cat; has_guard := hasg; guard_kind := guard;
    verdict := CASE
      WHEN cat = 'internal_service' AND NOT hasg THEN 'OK'
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
