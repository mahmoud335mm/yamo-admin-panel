
-- ============ 1) SYSTEM SETTINGS ============
CREATE TABLE IF NOT EXISTS public.system_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID
);
GRANT SELECT ON public.system_settings TO authenticated;
GRANT ALL ON public.system_settings TO service_role;
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "settings readable by admins" ON public.system_settings FOR SELECT TO authenticated
  USING (public.is_admin(auth.uid()));

INSERT INTO public.system_settings(key,value) VALUES
  ('bootstrap_super_admin_enabled', 'true'::jsonb),
  ('allow_admin_public_signup', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ============ 2) SAFER BOOTSTRAP TRIGGER ============
CREATE OR REPLACE FUNCTION public.handle_new_admin_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  admin_count INT;
  invite RECORD;
  bootstrap_enabled BOOL;
  allow_public BOOL;
BEGIN
  SELECT (value)::text::boolean INTO bootstrap_enabled FROM public.system_settings WHERE key='bootstrap_super_admin_enabled';
  SELECT (value)::text::boolean INTO allow_public FROM public.system_settings WHERE key='allow_admin_public_signup';

  -- Check invite first
  SELECT * INTO invite FROM public.admin_invites
    WHERE lower(email) = lower(NEW.email) AND accepted_at IS NULL AND expires_at > now()
    ORDER BY created_at DESC LIMIT 1;

  SELECT COUNT(*) INTO admin_count FROM public.admin_role_assignments;

  -- Allow if: has invite, OR bootstrap (first user + enabled), OR public signup allowed
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

-- ============ 3) ADMIN INVITES ============
CREATE TABLE IF NOT EXISTS public.admin_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL,
  role public.admin_role NOT NULL,
  token TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(24),'hex'),
  invited_by UUID REFERENCES public.admin_users(id),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
  accepted_at TIMESTAMPTZ,
  accepted_by UUID REFERENCES public.admin_users(id),
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.admin_invites TO authenticated;
GRANT ALL ON public.admin_invites TO service_role;
ALTER TABLE public.admin_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "invites read admins" ON public.admin_invites FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'admin.users.read'));
CREATE POLICY "invites write admins" ON public.admin_invites FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'admin.users.write'))
  WITH CHECK (public.has_permission(auth.uid(),'admin.users.write'));

-- ============ 4) ADMIN NOTES ============
CREATE TABLE IF NOT EXISTS public.admin_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  author_id UUID NOT NULL REFERENCES public.admin_users(id),
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS admin_notes_entity_idx ON public.admin_notes(entity_type, entity_id);
GRANT SELECT, INSERT, DELETE ON public.admin_notes TO authenticated;
GRANT ALL ON public.admin_notes TO service_role;
ALTER TABLE public.admin_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notes read" ON public.admin_notes FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY "notes write" ON public.admin_notes FOR INSERT TO authenticated
  WITH CHECK (public.is_admin(auth.uid()) AND author_id = auth.uid());
CREATE POLICY "notes delete own" ON public.admin_notes FOR DELETE TO authenticated
  USING (author_id = auth.uid() OR public.has_role(auth.uid(),'super_admin'));

-- ============ 5) USER EDIT HISTORY ============
CREATE TABLE IF NOT EXISTS public.user_edit_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  actor_id UUID,
  field TEXT NOT NULL,
  old_value JSONB,
  new_value JSONB,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS user_edit_history_user_idx ON public.user_edit_history(user_id, created_at DESC);
GRANT SELECT ON public.user_edit_history TO authenticated;
GRANT ALL ON public.user_edit_history TO service_role;
ALTER TABLE public.user_edit_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "history read admins" ON public.user_edit_history FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'users.read'));

-- ============ 6) PROFILES: soft delete + comm bans + extras ============
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS bio TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS cover_url TEXT,
  ADD COLUMN IF NOT EXISTS message_ban BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS call_ban BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS room_ban BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS post_ban BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID;

-- ============ 7) GENERIC DB AUDIT TRIGGER ============
CREATE OR REPLACE FUNCTION public.tg_audit_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  actor UUID := auth.uid();
  entity TEXT := TG_TABLE_NAME;
  eid TEXT;
  action_name TEXT;
  meta JSONB;
BEGIN
  IF TG_OP = 'INSERT' THEN
    eid := (row_to_json(NEW)->>'id');
    action_name := entity || '.insert';
    meta := jsonb_build_object('new', to_jsonb(NEW));
  ELSIF TG_OP = 'UPDATE' THEN
    eid := (row_to_json(NEW)->>'id');
    action_name := entity || '.update';
    meta := jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW));
  ELSE
    eid := (row_to_json(OLD)->>'id');
    action_name := entity || '.delete';
    meta := jsonb_build_object('old', to_jsonb(OLD));
  END IF;
  IF actor IS NOT NULL AND public.is_admin(actor) THEN
    INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, action_name, entity, eid, meta);
  END IF;
  RETURN COALESCE(NEW, OLD);
END; $$;

DROP TRIGGER IF EXISTS audit_profiles ON public.profiles;
CREATE TRIGGER audit_profiles AFTER INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
DROP TRIGGER IF EXISTS audit_wallets ON public.wallets;
CREATE TRIGGER audit_wallets AFTER UPDATE OR DELETE ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
DROP TRIGGER IF EXISTS audit_user_penalties ON public.user_penalties;
CREATE TRIGGER audit_user_penalties AFTER INSERT OR UPDATE OR DELETE ON public.user_penalties
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

-- ============ 8) TIGHTEN PROFILES RLS: no direct client updates ============
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='profiles admin write') THEN
    DROP POLICY "profiles admin write" ON public.profiles;
  END IF;
END $$;
-- Reads still allowed to admins with users.read (assume existing policy exists); write goes via RPCs only.

-- ============ 9) SERVER-SIDE ADMIN RPCs ============

-- Helper: require permission
CREATE OR REPLACE FUNCTION public._require_perm(_perm TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.has_permission(auth.uid(), _perm) THEN
    RAISE EXCEPTION 'PERM_DENIED: %', _perm USING ERRCODE='42501';
  END IF;
END; $$;

-- Ban user (temp or permanent)
CREATE OR REPLACE FUNCTION public.admin_ban_user(_user_id UUID, _reason TEXT, _until TIMESTAMPTZ DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE old_status TEXT;
BEGIN
  PERFORM public._require_perm('users.ban');
  SELECT status INTO old_status FROM public.profiles WHERE id=_user_id FOR UPDATE;
  IF old_status IS NULL THEN RAISE EXCEPTION 'USER_NOT_FOUND'; END IF;
  UPDATE public.profiles SET status='banned' WHERE id=_user_id;
  INSERT INTO public.user_penalties(user_id, type, reason, active, expires_at, created_by)
  VALUES (_user_id, CASE WHEN _until IS NULL THEN 'permanent_ban' ELSE 'temp_ban' END, _reason, true, _until, auth.uid());
  INSERT INTO public.user_edit_history(user_id, actor_id, field, old_value, new_value, reason)
  VALUES (_user_id, auth.uid(), 'status', to_jsonb(old_status), to_jsonb('banned'::text), _reason);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_unban_user(_user_id UUID, _reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public._require_perm('users.ban');
  UPDATE public.profiles SET status='active' WHERE id=_user_id;
  UPDATE public.user_penalties SET active=false WHERE user_id=_user_id AND active=true AND type IN ('permanent_ban','temp_ban');
  INSERT INTO public.user_edit_history(user_id, actor_id, field, old_value, new_value, reason)
  VALUES (_user_id, auth.uid(), 'status', to_jsonb('banned'::text), to_jsonb('active'::text), _reason);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_verify_user(_user_id UUID, _verified BOOL, _reason TEXT DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public._require_perm('users.verify');
  UPDATE public.profiles SET verification = CASE WHEN _verified THEN 'verified' ELSE 'rejected' END WHERE id=_user_id;
  INSERT INTO public.user_edit_history(user_id, actor_id, field, new_value, reason)
  VALUES (_user_id, auth.uid(), 'verification', to_jsonb(CASE WHEN _verified THEN 'verified' ELSE 'rejected' END), _reason);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_level(_user_id UUID, _level INT, _reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE oldv INT;
BEGIN
  PERFORM public._require_perm('users.write');
  IF _level < 0 OR _level > 200 THEN RAISE EXCEPTION 'INVALID_LEVEL'; END IF;
  SELECT level INTO oldv FROM public.profiles WHERE id=_user_id;
  UPDATE public.profiles SET level=_level WHERE id=_user_id;
  INSERT INTO public.user_edit_history(user_id, actor_id, field, old_value, new_value, reason)
  VALUES (_user_id, auth.uid(), 'level', to_jsonb(oldv), to_jsonb(_level), _reason);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_vip(_user_id UUID, _vip INT, _reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE oldv INT;
BEGIN
  PERFORM public._require_perm('users.write');
  IF _vip < 0 OR _vip > 20 THEN RAISE EXCEPTION 'INVALID_VIP'; END IF;
  SELECT vip_level INTO oldv FROM public.profiles WHERE id=_user_id;
  UPDATE public.profiles SET vip_level=_vip WHERE id=_user_id;
  INSERT INTO public.user_edit_history(user_id, actor_id, field, old_value, new_value, reason)
  VALUES (_user_id, auth.uid(), 'vip_level', to_jsonb(oldv), to_jsonb(_vip), _reason);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_toggle_comm_ban(_user_id UUID, _channel TEXT, _banned BOOL, _reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public._require_perm('users.ban');
  IF _channel NOT IN ('message','call','room','post') THEN RAISE EXCEPTION 'INVALID_CHANNEL'; END IF;
  EXECUTE format('UPDATE public.profiles SET %I=$1 WHERE id=$2', _channel||'_ban') USING _banned, _user_id;
  INSERT INTO public.user_edit_history(user_id, actor_id, field, new_value, reason)
  VALUES (_user_id, auth.uid(), _channel||'_ban', to_jsonb(_banned), _reason);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_terminate_sessions(_user_id UUID, _reason TEXT)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE n INT;
BEGIN
  PERFORM public._require_perm('users.write');
  UPDATE public.user_sessions SET revoked_at=now() WHERE user_id=_user_id AND revoked_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO public.user_edit_history(user_id, actor_id, field, new_value, reason)
  VALUES (_user_id, auth.uid(), 'sessions_terminated', to_jsonb(n), _reason);
  RETURN n;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_soft_delete_user(_user_id UUID, _reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public._require_perm('users.write');
  UPDATE public.profiles SET deleted_at=now(), deleted_by=auth.uid(), status='banned' WHERE id=_user_id;
  INSERT INTO public.user_edit_history(user_id, actor_id, field, new_value, reason)
  VALUES (_user_id, auth.uid(), 'deleted_at', to_jsonb(now()), _reason);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_restore_user(_user_id UUID, _reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public._require_perm('users.write');
  UPDATE public.profiles SET deleted_at=NULL, deleted_by=NULL, status='active' WHERE id=_user_id AND deleted_at IS NOT NULL;
  INSERT INTO public.user_edit_history(user_id, actor_id, field, new_value, reason)
  VALUES (_user_id, auth.uid(), 'restored', to_jsonb(true), _reason);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_profile(
  _user_id UUID, _display_name TEXT, _username TEXT, _bio TEXT, _country TEXT, _language TEXT, _avatar_url TEXT, _cover_url TEXT
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public._require_perm('users.write');
  UPDATE public.profiles SET
    display_name = COALESCE(_display_name, display_name),
    username = COALESCE(_username, username),
    bio = COALESCE(_bio, bio),
    country = COALESCE(_country, country),
    language = COALESCE(_language, language),
    avatar_url = COALESCE(_avatar_url, avatar_url),
    cover_url = COALESCE(_cover_url, cover_url)
  WHERE id=_user_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_gender(_user_id UUID, _gender TEXT, _reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE oldv TEXT;
BEGIN
  -- Requires super_admin OR explicit permission users.write + audited reason
  IF NOT (public.has_role(auth.uid(),'super_admin') OR public.has_permission(auth.uid(),'users.write')) THEN
    RAISE EXCEPTION 'PERM_DENIED';
  END IF;
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF _gender NOT IN ('male','female','other') THEN RAISE EXCEPTION 'INVALID_GENDER'; END IF;
  SELECT gender INTO oldv FROM public.profiles WHERE id=_user_id;
  UPDATE public.profiles SET gender=_gender WHERE id=_user_id;
  INSERT INTO public.user_edit_history(user_id, actor_id, field, old_value, new_value, reason)
  VALUES (_user_id, auth.uid(), 'gender', to_jsonb(oldv), to_jsonb(_gender), _reason);
END; $$;

-- Invites RPCs
CREATE OR REPLACE FUNCTION public.admin_create_invite(_email TEXT, _role public.admin_role, _days INT DEFAULT 7)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE new_id UUID;
BEGIN
  PERFORM public._require_perm('admin.users.write');
  INSERT INTO public.admin_invites(email, role, invited_by, expires_at)
  VALUES (_email, _role, auth.uid(), now() + make_interval(days => GREATEST(1,_days)))
  RETURNING id INTO new_id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'admin.invite.create', 'admin_invites', new_id::text, jsonb_build_object('email',_email,'role',_role));
  RETURN new_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_revoke_invite(_invite_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public._require_perm('admin.users.write');
  UPDATE public.admin_invites SET revoked_at=now() WHERE id=_invite_id AND accepted_at IS NULL;
END; $$;

-- Grant execute on admin RPCs
GRANT EXECUTE ON FUNCTION public.admin_ban_user, public.admin_unban_user, public.admin_verify_user,
  public.admin_update_level, public.admin_update_vip, public.admin_toggle_comm_ban,
  public.admin_terminate_sessions, public.admin_soft_delete_user, public.admin_restore_user,
  public.admin_update_profile, public.admin_update_gender,
  public.admin_create_invite, public.admin_revoke_invite TO authenticated;
