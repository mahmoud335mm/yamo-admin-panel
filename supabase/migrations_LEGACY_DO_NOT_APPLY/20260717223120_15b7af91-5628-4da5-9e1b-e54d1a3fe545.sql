
-- Preview invite (safe, no hash returned) - callable by anon so the /auth page can show role/email before signup
CREATE OR REPLACE FUNCTION public.preview_admin_invite(_token text)
RETURNS TABLE(email text, role admin_role, expires_at timestamptz, status text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  h text;
  r RECORD;
BEGIN
  IF _token IS NULL OR length(_token) < 16 THEN RETURN; END IF;
  h := encode(digest(_token, 'sha256'), 'hex');
  SELECT * INTO r FROM public.admin_invites WHERE token_hash = h LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  RETURN QUERY SELECT
    r.email,
    r.role,
    r.expires_at,
    CASE
      WHEN r.revoked_at IS NOT NULL THEN 'revoked'
      WHEN r.accepted_at IS NOT NULL THEN 'accepted'
      WHEN r.expires_at < now() THEN 'expired'
      ELSE 'pending'
    END;
END; $$;

REVOKE ALL ON FUNCTION public.preview_admin_invite(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.preview_admin_invite(text) TO anon, authenticated;

-- Accept invite by raw token (called after signup)
CREATE OR REPLACE FUNCTION public.accept_admin_invite(_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  uid uuid := auth.uid();
  uemail text;
  h text;
  inv RECORD;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _token IS NULL OR length(_token) < 16 THEN RAISE EXCEPTION 'INVALID_TOKEN'; END IF;
  SELECT email INTO uemail FROM auth.users WHERE id = uid;
  h := encode(digest(_token, 'sha256'), 'hex');

  SELECT * INTO inv FROM public.admin_invites WHERE token_hash = h FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVITE_NOT_FOUND'; END IF;
  IF inv.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'INVITE_REVOKED'; END IF;
  IF inv.accepted_at IS NOT NULL THEN RAISE EXCEPTION 'INVITE_ALREADY_USED'; END IF;
  IF inv.expires_at < now() THEN RAISE EXCEPTION 'INVITE_EXPIRED'; END IF;
  IF lower(inv.email) <> lower(uemail) THEN RAISE EXCEPTION 'EMAIL_MISMATCH'; END IF;

  INSERT INTO public.admin_users(id, email, full_name)
  VALUES (uid, uemail, split_part(uemail,'@',1))
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.admin_role_assignments(admin_user_id, role, assigned_by)
  VALUES (uid, inv.role, inv.invited_by)
  ON CONFLICT DO NOTHING;

  UPDATE public.admin_invites
     SET accepted_at = now(), accepted_by = uid
   WHERE id = inv.id AND accepted_at IS NULL;

  INSERT INTO public.audit_logs(actor_id, actor_email, action, entity_type, entity_id, metadata)
  VALUES (uid, uemail, 'admin.invite.accepted', 'admin_invites', inv.id::text,
          jsonb_build_object('role', inv.role));
END; $$;

REVOKE ALL ON FUNCTION public.accept_admin_invite(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_admin_invite(text) TO authenticated;

-- Update handle_new_admin_user to accept raw invite token in metadata OR fall back to email match
CREATE OR REPLACE FUNCTION public.handle_new_admin_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  admin_count INT;
  invite RECORD;
  bootstrap_enabled BOOL;
  allow_public BOOL;
  raw_token TEXT;
  h TEXT;
BEGIN
  SELECT (value)::text::boolean INTO bootstrap_enabled FROM public.system_settings WHERE key='bootstrap_super_admin_enabled';
  SELECT (value)::text::boolean INTO allow_public FROM public.system_settings WHERE key='allow_admin_public_signup';

  raw_token := NEW.raw_user_meta_data->>'invite_token';
  IF raw_token IS NOT NULL AND length(raw_token) >= 16 THEN
    h := encode(digest(raw_token, 'sha256'), 'hex');
    SELECT * INTO invite FROM public.admin_invites
      WHERE token_hash = h AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now()
        AND lower(email) = lower(NEW.email)
      LIMIT 1;
  END IF;

  IF invite.id IS NULL THEN
    SELECT * INTO invite FROM public.admin_invites
      WHERE lower(email) = lower(NEW.email) AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now()
      ORDER BY created_at DESC LIMIT 1;
  END IF;

  SELECT COUNT(*) INTO admin_count FROM public.admin_role_assignments;

  IF invite.id IS NULL AND admin_count > 0 AND NOT COALESCE(allow_public, false) THEN
    RAISE EXCEPTION 'Admin signup is closed. An invitation is required.';
  END IF;

  INSERT INTO public.admin_users (id, email, full_name)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email,'@',1)))
  ON CONFLICT (id) DO NOTHING;

  IF invite.id IS NOT NULL THEN
    INSERT INTO public.admin_role_assignments(admin_user_id, role, assigned_by)
    VALUES (NEW.id, invite.role, invite.invited_by)
    ON CONFLICT DO NOTHING;
    UPDATE public.admin_invites SET accepted_at = now(), accepted_by = NEW.id WHERE id = invite.id;
    INSERT INTO public.audit_logs(actor_id, actor_email, action, entity_type, entity_id, metadata)
    VALUES (NEW.id, NEW.email, 'admin.invite.accepted', 'admin_invites', invite.id::text,
            jsonb_build_object('role', invite.role));
  ELSIF admin_count = 0 AND COALESCE(bootstrap_enabled, true) THEN
    INSERT INTO public.admin_role_assignments(admin_user_id, role) VALUES (NEW.id, 'super_admin');
    UPDATE public.system_settings SET value='false'::jsonb, updated_at=now() WHERE key='bootstrap_super_admin_enabled';
    INSERT INTO public.audit_logs(actor_id, actor_email, action, entity_type, entity_id, metadata)
    VALUES (NEW.id, NEW.email, 'bootstrap.super_admin', 'admin_users', NEW.id::text,
            jsonb_build_object('reason','first signup, bootstrap now disabled'));
  END IF;

  RETURN NEW;
END; $$;
