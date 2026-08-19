CREATE OR REPLACE FUNCTION public.handle_new_admin_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  admin_count INT;
  invite public.admin_invites%ROWTYPE;
  invite_found BOOLEAN := false;
  bootstrap_enabled BOOL;
  allow_public BOOL;
  raw_token TEXT;
  h TEXT;
BEGIN
  SELECT (value)::text::boolean INTO bootstrap_enabled FROM public.system_settings WHERE key='bootstrap_super_admin_enabled';
  SELECT (value)::text::boolean INTO allow_public FROM public.system_settings WHERE key='allow_admin_public_signup';

  raw_token := NEW.raw_user_meta_data->>'invite_token';
  IF raw_token IS NOT NULL AND length(raw_token) >= 16 THEN
    h := encode(extensions.digest(raw_token, 'sha256'), 'hex');
    SELECT * INTO invite FROM public.admin_invites
      WHERE token_hash = h AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now()
        AND lower(email) = lower(NEW.email)
      LIMIT 1;
    invite_found := FOUND;
  END IF;

  IF NOT invite_found THEN
    SELECT * INTO invite FROM public.admin_invites
      WHERE lower(email) = lower(NEW.email) AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now()
      ORDER BY created_at DESC LIMIT 1;
    invite_found := FOUND;
  END IF;

  SELECT COUNT(*) INTO admin_count FROM public.admin_role_assignments;

  IF NOT invite_found AND admin_count > 0 AND NOT COALESCE(allow_public, false) THEN
    RAISE EXCEPTION 'Admin signup is closed. An invitation is required.';
  END IF;

  INSERT INTO public.admin_users (id, email, full_name)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email,'@',1)))
  ON CONFLICT (id) DO NOTHING;

  IF invite_found THEN
    INSERT INTO public.admin_role_assignments(admin_user_id, role, granted_by)
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
END; $function$;