
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Harden all SECURITY DEFINER functions
DO $$
DECLARE fn RECORD;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef = true
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', fn.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', fn.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn.sig);
  END LOOP;
END $$;

-- 2. admin_invites: hash tokens
ALTER TABLE public.admin_invites ADD COLUMN IF NOT EXISTS token_hash TEXT;
ALTER TABLE public.admin_invites ADD COLUMN IF NOT EXISTS revoked_by UUID;
UPDATE public.admin_invites SET token = NULL WHERE token IS NOT NULL;
ALTER TABLE public.admin_invites DROP COLUMN IF EXISTS token;
CREATE UNIQUE INDEX IF NOT EXISTS admin_invites_token_hash_uniq
  ON public.admin_invites(token_hash) WHERE token_hash IS NOT NULL;

DROP FUNCTION IF EXISTS public.admin_create_invite(text, admin_role, integer);
CREATE FUNCTION public.admin_create_invite(_email text, _role admin_role, _days integer DEFAULT 7)
RETURNS TABLE(invite_id uuid, raw_token text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE new_id UUID; raw TEXT; hashed TEXT;
BEGIN
  PERFORM public._require_perm('admin.users.write');
  IF _email IS NULL OR position('@' in _email) = 0 THEN RAISE EXCEPTION 'INVALID_EMAIL'; END IF;
  raw := encode(gen_random_bytes(32), 'hex');
  hashed := encode(digest(raw, 'sha256'), 'hex');
  INSERT INTO public.admin_invites(email, role, invited_by, expires_at, token_hash)
  VALUES (lower(_email), _role, auth.uid(), now() + make_interval(days => GREATEST(1,LEAST(30,_days))), hashed)
  RETURNING id INTO new_id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'admin.invite.create', 'admin_invites', new_id::text,
          jsonb_build_object('email', lower(_email), 'role', _role));
  RETURN QUERY SELECT new_id, raw;
END $$;
REVOKE ALL ON FUNCTION public.admin_create_invite(text, admin_role, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_invite(text, admin_role, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_revoke_invite(_invite_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._require_perm('admin.users.write');
  UPDATE public.admin_invites
    SET revoked_at = now(), revoked_by = auth.uid()
    WHERE id = _invite_id AND accepted_at IS NULL AND revoked_at IS NULL;
  IF FOUND THEN
    INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id)
    VALUES (auth.uid(), 'admin.invite.revoke', 'admin_invites', _invite_id::text);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.admin_revoke_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_revoke_invite(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.admin_revoc_invite(uuid);

-- 3. audit_logs + wallet_ledger append-only
DROP POLICY IF EXISTS "audit no update" ON public.audit_logs;
DROP POLICY IF EXISTS "audit no delete" ON public.audit_logs;
CREATE POLICY "audit no update" ON public.audit_logs AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "audit no delete" ON public.audit_logs AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS "ledger no update" ON public.wallet_ledger;
DROP POLICY IF EXISTS "ledger no delete" ON public.wallet_ledger;
CREATE POLICY "ledger no update" ON public.wallet_ledger AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "ledger no delete" ON public.wallet_ledger AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

REVOKE UPDATE, DELETE ON public.audit_logs FROM authenticated;
REVOKE UPDATE, DELETE ON public.wallet_ledger FROM authenticated;

-- 4. profiles: force sensitive edits through RPC
DROP POLICY IF EXISTS "write profiles" ON public.profiles;
DROP POLICY IF EXISTS "delete profiles" ON public.profiles;
DROP POLICY IF EXISTS "insert profiles" ON public.profiles;
CREATE POLICY "profiles no direct update" ON public.profiles AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY "profiles no direct delete" ON public.profiles AS RESTRICTIVE FOR DELETE TO authenticated USING (false);
CREATE POLICY "profiles insert admins" ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(auth.uid(), 'users.write'));
REVOKE UPDATE, DELETE ON public.profiles FROM authenticated;

-- 5. system_settings locked
DROP POLICY IF EXISTS "settings no write" ON public.system_settings;
CREATE POLICY "settings no write" ON public.system_settings AS RESTRICTIVE FOR ALL TO authenticated USING (false) WITH CHECK (false);
REVOKE INSERT, UPDATE, DELETE ON public.system_settings FROM authenticated;

-- 6. Emergency recovery
CREATE OR REPLACE FUNCTION public.emergency_grant_super_admin(_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('role', true) NOT IN ('service_role') AND session_user <> 'postgres' THEN
    RAISE EXCEPTION 'EMERGENCY_ONLY: service_role required';
  END IF;
  INSERT INTO public.admin_users(id, email, full_name, is_active)
  SELECT _user_id, u.email, COALESCE(u.raw_user_meta_data->>'full_name', u.email), true
  FROM auth.users u WHERE u.id = _user_id
  ON CONFLICT (id) DO UPDATE SET is_active = true;
  INSERT INTO public.admin_role_assignments(admin_user_id, role)
  VALUES (_user_id, 'super_admin') ON CONFLICT DO NOTHING;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (_user_id, 'emergency.super_admin.granted', 'admin_users', _user_id::text,
          jsonb_build_object('source','service_role'));
END $$;
REVOKE ALL ON FUNCTION public.emergency_grant_super_admin(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.emergency_grant_super_admin(uuid) TO service_role;

-- 7. Bootstrap flag
INSERT INTO public.system_settings(key, value)
VALUES ('bootstrap_super_admin_enabled', 'true'::jsonb),
       ('allow_admin_public_signup',     'false'::jsonb)
ON CONFLICT (key) DO NOTHING;

UPDATE public.system_settings SET value = 'false'::jsonb
  WHERE key = 'bootstrap_super_admin_enabled'
    AND (SELECT COUNT(*) FROM public.admin_role_assignments) > 0;
