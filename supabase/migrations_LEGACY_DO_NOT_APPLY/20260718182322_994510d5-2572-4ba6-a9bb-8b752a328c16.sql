
-- Allowlist for intentionally public SECURITY DEFINER functions (empty by default)
CREATE TABLE IF NOT EXISTS public.security_definer_public_allowlist (
  function_name text NOT NULL,
  function_args text NOT NULL,
  reason text NOT NULL,
  added_by uuid,
  added_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (function_name, function_args)
);
GRANT SELECT ON public.security_definer_public_allowlist TO authenticated;
GRANT ALL ON public.security_definer_public_allowlist TO service_role;
ALTER TABLE public.security_definer_public_allowlist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read allowlist" ON public.security_definer_public_allowlist;
CREATE POLICY "read allowlist" ON public.security_definer_public_allowlist FOR SELECT TO authenticated USING (true);

-- Bulk revoke EXECUTE from PUBLIC and anon for every SECURITY DEFINER function in public
DO $bulk$
DECLARE
  r record;
  in_allow boolean;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef = true
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM public.security_definer_public_allowlist a
      WHERE a.function_name = r.proname AND a.function_args = r.args
    ) INTO in_allow;

    IF NOT in_allow THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC', r.proname, r.args);
      EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM anon', r.proname, r.args);
      -- Ensure authenticated + service_role retain access (idempotent)
      BEGIN
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated', r.proname, r.args);
      EXCEPTION WHEN OTHERS THEN NULL; END;
      BEGIN
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO service_role', r.proname, r.args);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END LOOP;
END
$bulk$;

-- Guard function: fails if any non-allowlisted SECURITY DEFINER is executable by PUBLIC/anon
CREATE OR REPLACE FUNCTION public.assert_no_public_security_definer()
RETURNS TABLE(function_name text, function_args text, exposure text)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  RETURN QUERY
  SELECT p.proname::text, pg_get_function_identity_arguments(p.oid)::text,
         CASE
           WHEN EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
                        WHERE a.grantee = 0 AND a.privilege_type='EXECUTE') THEN 'PUBLIC'
           WHEN has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'anon'
         END
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND (
      EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
              WHERE a.grantee = 0 AND a.privilege_type='EXECUTE')
      OR has_function_privilege('anon', p.oid, 'EXECUTE')
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.security_definer_public_allowlist al
      WHERE al.function_name = p.proname
        AND al.function_args = pg_get_function_identity_arguments(p.oid)
    );
END
$fn$;
REVOKE ALL ON FUNCTION public.assert_no_public_security_definer() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assert_no_public_security_definer() TO authenticated, service_role;
