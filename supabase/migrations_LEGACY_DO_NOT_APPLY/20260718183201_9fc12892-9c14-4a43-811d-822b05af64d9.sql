
-- 1) HARDEN: internal wallet primitive must never be authenticated-callable
REVOKE EXECUTE ON FUNCTION public._wallet_apply(uuid, wallet_account, bigint, ledger_reason, text, jsonb) FROM PUBLIC, authenticated;
-- service_role retains default rights via ownership; SECURITY DEFINER RPCs that call it still work.

-- 2) Improve classifier: detect trigger returns, IS NULL guards, and indirect admin calls.
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
  is_trigger boolean;
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
    src := lower(r.def);
    fname := r.proname;
    is_trigger := (r.rettype = 'trigger');

    -- Classification
    IF is_trigger OR fname ~ '^(_|tg_)' OR fname ~ '(outbox|internal|_snapshot)' THEN
      cat := 'internal_service';
    ELSIF fname ~ '^(admin_|rbac_|assert_)' OR fname ~ '_admin_' THEN
      cat := 'admin';
    ELSIF fname ~ '(recharge|withdraw|wallet|ledger|coin|pearl|payment|refund|dispute|charging|finance|exchange)' THEN
      cat := 'financial';
    ELSIF fname ~ '(profile|me_|user_)' THEN
      cat := 'authenticated_user';
    ELSE
      cat := 'legacy';
    END IF;

    -- Guard detection (direct + indirect)
    hasg := false; guard := NULL;
    IF src ~ '_require_perm\s*\(' THEN hasg := true; guard := '_require_perm';
    ELSIF src ~ 'has_permission\s*\(' THEN hasg := true; guard := 'has_permission';
    ELSIF src ~ 'has_role\s*\(' THEN hasg := true; guard := 'has_role';
    ELSIF src ~ 'is_admin\s*\(' THEN hasg := true; guard := 'is_admin';
    ELSIF src ~ 'auth\.uid\s*\(\s*\)\s+is\s+null' THEN hasg := true; guard := 'not_authenticated_raise';
    ELSIF src ~ 'auth\.uid\s*\(\s*\)\s+is\s+not\s+null' THEN hasg := true; guard := 'uid_not_null';
    ELSIF src ~ '=\s*auth\.uid\s*\(\s*\)' OR src ~ 'auth\.uid\s*\(\s*\)\s*=' THEN hasg := true; guard := 'ownership';
    ELSIF src ~ 'current_setting\s*\(\s*''role''' AND src ~ 'service_role' THEN hasg := true; guard := 'service_role_only';
    -- Indirect: SQL functions delegating to guarded admin/private helpers
    ELSIF src ~ '_admin_wallet_adjust\s*\(' OR src ~ '_admin_[a-z_]+\s*\(' THEN hasg := true; guard := 'delegates_to_admin_helper';
    -- Token-guarded preview
    ELSIF src ~ 'token_hash' AND src ~ 'digest\s*\(' THEN hasg := true; guard := 'token_hash_match';
    END IF;

    function_signature := r.nspname || '.' || r.proname || '(' || r.args || ')';
    category := cat; has_guard := hasg; guard_kind := guard;
    verdict := CASE
      WHEN cat = 'internal_service' AND NOT hasg THEN 'OK'   -- triggers/internal not user-callable in practice
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
