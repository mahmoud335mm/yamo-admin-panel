
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND (
        p.proname LIKE '\_%' ESCAPE '\'
        OR p.proname LIKE 'tg\_%' ESCAPE '\'
        OR p.proname LIKE 'assert\_%' ESCAPE '\'
        OR p.proname = 'handle_new_admin_user'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM authenticated',
                   r.proname, r.args);
  END LOOP;
END $$;
