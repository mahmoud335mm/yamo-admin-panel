
-- Same as previous — resubmitting with label_en added to permission inserts
CREATE TABLE public.bd_levels (
  id SMALLINT PRIMARY KEY, name TEXT NOT NULL,
  min_agencies INT NOT NULL DEFAULT 0, commission_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
  perks JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.bd_levels TO authenticated;
GRANT ALL ON public.bd_levels TO service_role;
ALTER TABLE public.bd_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bd_levels read admins" ON public.bd_levels FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));

CREATE TABLE public.bd_managers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE, admin_user_id UUID REFERENCES public.admin_users(id) ON DELETE SET NULL,
  code TEXT UNIQUE NOT NULL, display_name TEXT NOT NULL,
  phone TEXT, email TEXT, country TEXT,
  level_id SMALLINT REFERENCES public.bd_levels(id),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','closed')),
  notes TEXT, created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.bd_managers TO authenticated;
GRANT ALL ON public.bd_managers TO service_role;
ALTER TABLE public.bd_managers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bd_managers read scoped" ON public.bd_managers FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'bd.read') OR admin_user_id = auth.uid());

CREATE TABLE public.agency_levels (
  id SMALLINT PRIMARY KEY, name TEXT NOT NULL,
  min_active_hosts INT NOT NULL DEFAULT 0, min_monthly_coins BIGINT NOT NULL DEFAULT 0,
  commission_pct NUMERIC(5,2) NOT NULL DEFAULT 0, perks JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.agency_levels TO authenticated;
GRANT ALL ON public.agency_levels TO service_role;
ALTER TABLE public.agency_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "agency_levels read admins" ON public.agency_levels FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));

CREATE TABLE public.agencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL, name TEXT NOT NULL, country TEXT, language TEXT DEFAULT 'ar',
  logo_url TEXT, cover_url TEXT, bio TEXT,
  owner_user_id UUID, deputy_user_id UUID,
  bd_id UUID REFERENCES public.bd_managers(id) ON DELETE SET NULL,
  level_id SMALLINT REFERENCES public.agency_levels(id),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','closed','pending')),
  active_hosts INT NOT NULL DEFAULT 0, total_hosts INT NOT NULL DEFAULT 0,
  monthly_coins BIGINT NOT NULL DEFAULT 0, monthly_hours NUMERIC(10,2) NOT NULL DEFAULT 0,
  join_policy TEXT NOT NULL DEFAULT 'approval' CHECK (join_policy IN ('open','approval','closed')),
  closed_at TIMESTAMPTZ, closed_by UUID, close_reason TEXT, created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON public.agencies (bd_id);
CREATE INDEX ON public.agencies (owner_user_id);
CREATE INDEX ON public.agencies (status);
GRANT SELECT ON public.agencies TO authenticated;
GRANT ALL ON public.agencies TO service_role;
ALTER TABLE public.agencies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "agencies read scoped" ON public.agencies FOR SELECT TO authenticated USING (
  public.has_permission(auth.uid(),'agencies.read')
  OR owner_user_id = auth.uid() OR deputy_user_id = auth.uid()
  OR bd_id IN (SELECT id FROM public.bd_managers WHERE admin_user_id = auth.uid())
);

CREATE TABLE public.agency_level_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
  old_level SMALLINT, new_level SMALLINT, reason TEXT, changed_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.agency_level_history TO authenticated;
GRANT ALL ON public.agency_level_history TO service_role;
ALTER TABLE public.agency_level_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "alh read admins" ON public.agency_level_history FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'agencies.read'));

CREATE TABLE public.agency_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  member_role TEXT NOT NULL CHECK (member_role IN ('owner','deputy','recruiter')),
  assigned_by UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(agency_id, user_id, member_role)
);
GRANT SELECT ON public.agency_members TO authenticated;
GRANT ALL ON public.agency_members TO service_role;
ALTER TABLE public.agency_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "am read admins" ON public.agency_members FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'agencies.read'));

CREATE TABLE public.agency_join_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
  user_id UUID NOT NULL, message TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  reviewed_by UUID, reviewed_at TIMESTAMPTZ, review_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON public.agency_join_requests (agency_id, status);
GRANT SELECT ON public.agency_join_requests TO authenticated;
GRANT ALL ON public.agency_join_requests TO service_role;
ALTER TABLE public.agency_join_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ajr read admins" ON public.agency_join_requests FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'agencies.read'));

CREATE TABLE public.agency_host_transfer_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id UUID NOT NULL,
  from_agency_id UUID REFERENCES public.agencies(id),
  to_agency_id UUID NOT NULL REFERENCES public.agencies(id),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','source_approved','target_approved','bd_approved','completed','rejected','cancelled')),
  source_decision TEXT, source_decided_by UUID, source_decided_at TIMESTAMPTZ, source_note TEXT,
  target_decision TEXT, target_decided_by UUID, target_decided_at TIMESTAMPTZ, target_note TEXT,
  bd_decision TEXT,     bd_decided_by UUID,     bd_decided_at TIMESTAMPTZ,     bd_note TEXT,
  admin_decision TEXT,  admin_decided_by UUID,  admin_decided_at TIMESTAMPTZ,  admin_note TEXT,
  executed_at TIMESTAMPTZ, idempotency_key TEXT UNIQUE, created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON public.agency_host_transfer_requests (status);
CREATE INDEX ON public.agency_host_transfer_requests (host_user_id);
GRANT SELECT ON public.agency_host_transfer_requests TO authenticated;
GRANT ALL ON public.agency_host_transfer_requests TO service_role;
ALTER TABLE public.agency_host_transfer_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ht read admins" ON public.agency_host_transfer_requests FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'agencies.read'));

CREATE TABLE public.agency_violations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'warning' CHECK (severity IN ('info','warning','major','critical')),
  reason TEXT NOT NULL, penalty JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.agency_violations TO authenticated;
GRANT ALL ON public.agency_violations TO service_role;
ALTER TABLE public.agency_violations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "av read admins" ON public.agency_violations FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'agencies.read'));

CREATE TABLE public.agency_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
  period_year INT NOT NULL, period_month INT NOT NULL,
  target_type TEXT NOT NULL, target_value BIGINT NOT NULL,
  progress_value BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(agency_id, period_year, period_month, target_type)
);
GRANT SELECT ON public.agency_tasks TO authenticated;
GRANT ALL ON public.agency_tasks TO service_role;
ALTER TABLE public.agency_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "at read admins" ON public.agency_tasks FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'agencies.read'));

CREATE TABLE public.host_levels (
  id SMALLINT PRIMARY KEY, name TEXT NOT NULL,
  min_hours NUMERIC(10,2) NOT NULL DEFAULT 0, min_coins BIGINT NOT NULL DEFAULT 0,
  bonus_pct NUMERIC(5,2) NOT NULL DEFAULT 0, perks JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.host_levels TO authenticated;
GRANT ALL ON public.host_levels TO service_role;
ALTER TABLE public.host_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "hl read admins" ON public.host_levels FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));

CREATE TABLE public.hosts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL,
  agency_id UUID REFERENCES public.agencies(id) ON DELETE SET NULL,
  level_id SMALLINT REFERENCES public.host_levels(id),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','left','pending','on_leave')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(), left_at TIMESTAMPTZ, cooldown_until TIMESTAMPTZ,
  total_hours NUMERIC(12,2) NOT NULL DEFAULT 0, total_coins BIGINT NOT NULL DEFAULT 0,
  monthly_hours NUMERIC(10,2) NOT NULL DEFAULT 0, monthly_coins BIGINT NOT NULL DEFAULT 0,
  pending_earnings BIGINT NOT NULL DEFAULT 0, debt BIGINT NOT NULL DEFAULT 0,
  suspend_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON public.hosts (agency_id);
CREATE INDEX ON public.hosts (status);
GRANT SELECT ON public.hosts TO authenticated;
GRANT ALL ON public.hosts TO service_role;
ALTER TABLE public.hosts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "hosts read scoped" ON public.hosts FOR SELECT TO authenticated USING (
  public.has_permission(auth.uid(),'hosts.read') OR user_id = auth.uid()
  OR agency_id IN (SELECT id FROM public.agencies WHERE owner_user_id = auth.uid() OR deputy_user_id = auth.uid()
                    OR bd_id IN (SELECT id FROM public.bd_managers WHERE admin_user_id = auth.uid()))
);

CREATE TABLE public.host_targets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES public.hosts(id) ON DELETE CASCADE,
  period_year INT NOT NULL, period_month INT NOT NULL,
  target_hours NUMERIC(10,2) NOT NULL DEFAULT 0, target_coins BIGINT NOT NULL DEFAULT 0,
  achieved_hours NUMERIC(10,2) NOT NULL DEFAULT 0, achieved_coins BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(host_id, period_year, period_month)
);
GRANT SELECT ON public.host_targets TO authenticated;
GRANT ALL ON public.host_targets TO service_role;
ALTER TABLE public.host_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ht2 read admins" ON public.host_targets FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'hosts.read'));

CREATE TABLE public.host_shifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES public.hosts(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL, ended_at TIMESTAMPTZ,
  duration_min INT, coins_earned BIGINT NOT NULL DEFAULT 0, room_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON public.host_shifts (host_id, started_at DESC);
GRANT SELECT ON public.host_shifts TO authenticated;
GRANT ALL ON public.host_shifts TO service_role;
ALTER TABLE public.host_shifts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "hs read admins" ON public.host_shifts FOR SELECT TO authenticated USING (public.has_permission(auth.uid(),'hosts.read'));

CREATE TABLE public.host_earnings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES public.hosts(id) ON DELETE CASCADE,
  agency_id UUID REFERENCES public.agencies(id) ON DELETE SET NULL,
  period_year INT NOT NULL, period_month INT NOT NULL,
  gross_coins BIGINT NOT NULL DEFAULT 0, agency_cut BIGINT NOT NULL DEFAULT 0,
  bd_cut BIGINT NOT NULL DEFAULT 0, platform_cut BIGINT NOT NULL DEFAULT 0,
  net_coins BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','paid','disputed','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(host_id, period_year, period_month)
);
GRANT SELECT ON public.host_earnings TO authenticated;
GRANT ALL ON public.host_earnings TO service_role;
ALTER TABLE public.host_earnings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "he read admins" ON public.host_earnings FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'economy.read') OR public.has_permission(auth.uid(),'hosts.read'));

CREATE TABLE public.bd_agencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bd_id UUID NOT NULL REFERENCES public.bd_managers(id) ON DELETE CASCADE,
  agency_id UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
  assigned_by UUID, assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  released_at TIMESTAMPTZ,
  UNIQUE(bd_id, agency_id, assigned_at)
);
GRANT SELECT ON public.bd_agencies TO authenticated;
GRANT ALL ON public.bd_agencies TO service_role;
ALTER TABLE public.bd_agencies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ba read admins" ON public.bd_agencies FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'bd.read')
    OR bd_id IN (SELECT id FROM public.bd_managers WHERE admin_user_id = auth.uid()));

CREATE TABLE public.bd_commissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bd_id UUID NOT NULL REFERENCES public.bd_managers(id) ON DELETE CASCADE,
  agency_id UUID REFERENCES public.agencies(id) ON DELETE SET NULL,
  period_year INT NOT NULL, period_month INT NOT NULL,
  gross_coins BIGINT NOT NULL DEFAULT 0,
  commission_pct NUMERIC(5,2) NOT NULL,
  commission_coins BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','paid','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON public.bd_commissions (bd_id, period_year, period_month);
GRANT SELECT ON public.bd_commissions TO authenticated;
GRANT ALL ON public.bd_commissions TO service_role;
ALTER TABLE public.bd_commissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bc read scoped" ON public.bd_commissions FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'economy.read')
    OR bd_id IN (SELECT id FROM public.bd_managers WHERE admin_user_id = auth.uid()));

CREATE POLICY "he no direct write" ON public.host_earnings AS RESTRICTIVE FOR ALL TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY "bc no direct write" ON public.bd_commissions AS RESTRICTIVE FOR ALL TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY "ag no direct delete" ON public.agencies AS RESTRICTIVE FOR DELETE TO authenticated USING (false);
CREATE POLICY "ho no direct delete" ON public.hosts AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

INSERT INTO public.agency_levels(id,name,min_active_hosts,min_monthly_coins,commission_pct) VALUES
  (1,'Bronze',0,0,10),(2,'Silver',5,100000,15),(3,'Gold',15,500000,20),
  (4,'Platinum',30,2000000,25),(5,'Diamond',60,8000000,30);
INSERT INTO public.host_levels(id,name,min_hours,min_coins,bonus_pct) VALUES
  (1,'H1',0,0,0),(2,'H2',30,10000,5),(3,'H3',80,50000,10),
  (4,'H4',150,200000,15),(5,'H5',250,500000,20);
INSERT INTO public.bd_levels(id,name,min_agencies,commission_pct) VALUES
  (1,'BD1',0,3),(2,'BD2',5,5),(3,'BD3',15,8),(4,'BD4',30,10);

CREATE TRIGGER trg_agencies_updated_at BEFORE UPDATE ON public.agencies FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_hosts_updated_at BEFORE UPDATE ON public.hosts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_bd_managers_updated_at BEFORE UPDATE ON public.bd_managers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_audit_agencies AFTER INSERT OR UPDATE OR DELETE ON public.agencies FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_audit_hosts AFTER INSERT OR UPDATE OR DELETE ON public.hosts FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_audit_bd AFTER INSERT OR UPDATE OR DELETE ON public.bd_managers FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_audit_transfers AFTER INSERT OR UPDATE OR DELETE ON public.agency_host_transfer_requests FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

INSERT INTO public.permissions(key, module, label_ar, label_en) VALUES
  ('agencies.read','agencies','قراءة الوكالات','Read agencies'),
  ('agencies.write','agencies','إنشاء وتعديل الوكالات','Create/update agencies'),
  ('agencies.suspend','agencies','إيقاف وكالة','Suspend agency'),
  ('agencies.close','agencies','إغلاق وكالة','Close agency'),
  ('agencies.transfer','agencies','نقل وكالة بين BD','Transfer agency BD'),
  ('agencies.level','agencies','تعديل مستوى الوكالة','Update agency level'),
  ('hosts.read','hosts','قراءة المضيفين','Read hosts'),
  ('hosts.write','hosts','تعديل المضيفين','Update hosts'),
  ('hosts.transfer','hosts','نقل مضيف','Transfer host'),
  ('hosts.suspend','hosts','إيقاف مضيف','Suspend host'),
  ('bd.read','bd','قراءة BD','Read BD'),
  ('bd.write','bd','إدارة BD','Manage BD')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions(role, permission_key) VALUES
  ('agency_manager','agencies.read'),('agency_manager','agencies.write'),('agency_manager','agencies.suspend'),
  ('agency_manager','agencies.level'),('agency_manager','hosts.read'),('agency_manager','hosts.write'),
  ('agency_manager','hosts.transfer'),
  ('bd_manager','bd.read'),('bd_manager','agencies.read'),('bd_manager','hosts.read'),
  ('moderator','agencies.read'),('moderator','hosts.read'),('moderator','bd.read'),
  ('viewer','agencies.read'),('viewer','hosts.read'),('viewer','bd.read'),
  ('auditor','agencies.read'),('auditor','hosts.read'),('auditor','bd.read')
ON CONFLICT DO NOTHING;

-- ============ RPCs ============
CREATE OR REPLACE FUNCTION public.create_agency(_code text,_name text,_country text,_language text,_owner_user_id uuid,_bd_id uuid,_level_id smallint)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE new_id uuid;
BEGIN
  PERFORM public._require_perm('agencies.write');
  IF _code IS NULL OR length(_code)<2 THEN RAISE EXCEPTION 'INVALID_CODE'; END IF;
  IF _name IS NULL OR length(_name)<2 THEN RAISE EXCEPTION 'INVALID_NAME'; END IF;
  INSERT INTO public.agencies(code,name,country,language,owner_user_id,bd_id,level_id,created_by,status)
  VALUES (_code,_name,_country,COALESCE(_language,'ar'),_owner_user_id,_bd_id,COALESCE(_level_id,1),auth.uid(),'active') RETURNING id INTO new_id;
  IF _owner_user_id IS NOT NULL THEN
    INSERT INTO public.agency_members(agency_id,user_id,member_role,assigned_by) VALUES (new_id,_owner_user_id,'owner',auth.uid()) ON CONFLICT DO NOTHING;
  END IF;
  IF _bd_id IS NOT NULL THEN INSERT INTO public.bd_agencies(bd_id,agency_id,assigned_by) VALUES (_bd_id,new_id,auth.uid()); END IF;
  RETURN new_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_agency(text,text,text,text,uuid,uuid,smallint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_agency(text,text,text,text,uuid,uuid,smallint) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_agency(_agency_id uuid,_name text,_country text,_language text,_bio text,_logo_url text,_cover_url text,_join_policy text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public._require_perm('agencies.write');
  UPDATE public.agencies SET name=COALESCE(_name,name), country=COALESCE(_country,country), language=COALESCE(_language,language),
    bio=COALESCE(_bio,bio), logo_url=COALESCE(_logo_url,logo_url), cover_url=COALESCE(_cover_url,cover_url),
    join_policy=COALESCE(_join_policy,join_policy) WHERE id=_agency_id;
END; $$;
REVOKE ALL ON FUNCTION public.update_agency(uuid,text,text,text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_agency(uuid,text,text,text,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.suspend_agency(_agency_id uuid,_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public._require_perm('agencies.suspend');
  IF _reason IS NULL OR length(_reason)<5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE public.agencies SET status='suspended' WHERE id=_agency_id;
  INSERT INTO public.agency_violations(agency_id,type,severity,reason,created_by) VALUES (_agency_id,'suspend','major',_reason,auth.uid());
END; $$;
REVOKE ALL ON FUNCTION public.suspend_agency(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suspend_agency(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reactivate_agency(_agency_id uuid,_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('agencies.suspend'); UPDATE public.agencies SET status='active' WHERE id=_agency_id AND status='suspended'; END; $$;
REVOKE ALL ON FUNCTION public.reactivate_agency(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reactivate_agency(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.close_agency(_agency_id uuid,_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE ah int;
BEGIN
  PERFORM public._require_perm('agencies.close');
  IF _reason IS NULL OR length(_reason)<5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT COUNT(*) INTO ah FROM public.hosts WHERE agency_id=_agency_id AND status='active';
  IF ah>0 THEN RAISE EXCEPTION 'AGENCY_HAS_ACTIVE_HOSTS: %', ah; END IF;
  UPDATE public.agencies SET status='closed', closed_at=now(), closed_by=auth.uid(), close_reason=_reason WHERE id=_agency_id;
END; $$;
REVOKE ALL ON FUNCTION public.close_agency(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_agency(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_agency_owner(_agency_id uuid,_user_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public._require_perm('agencies.write');
  UPDATE public.agencies SET owner_user_id=_user_id WHERE id=_agency_id;
  INSERT INTO public.agency_members(agency_id,user_id,member_role,assigned_by) VALUES (_agency_id,_user_id,'owner',auth.uid()) ON CONFLICT DO NOTHING;
END; $$;
REVOKE ALL ON FUNCTION public.assign_agency_owner(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_agency_owner(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_agency_deputy(_agency_id uuid,_user_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public._require_perm('agencies.write');
  UPDATE public.agencies SET deputy_user_id=_user_id WHERE id=_agency_id;
  INSERT INTO public.agency_members(agency_id,user_id,member_role,assigned_by) VALUES (_agency_id,_user_id,'deputy',auth.uid()) ON CONFLICT DO NOTHING;
END; $$;
REVOKE ALL ON FUNCTION public.assign_agency_deputy(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_agency_deputy(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.transfer_agency_to_bd(_agency_id uuid,_new_bd_id uuid,_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old_bd uuid;
BEGIN
  PERFORM public._require_perm('agencies.transfer');
  IF _reason IS NULL OR length(_reason)<5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT bd_id INTO old_bd FROM public.agencies WHERE id=_agency_id FOR UPDATE;
  UPDATE public.agencies SET bd_id=_new_bd_id WHERE id=_agency_id;
  IF old_bd IS NOT NULL THEN UPDATE public.bd_agencies SET released_at=now() WHERE bd_id=old_bd AND agency_id=_agency_id AND released_at IS NULL; END IF;
  INSERT INTO public.bd_agencies(bd_id,agency_id,assigned_by) VALUES (_new_bd_id,_agency_id,auth.uid());
END; $$;
REVOKE ALL ON FUNCTION public.transfer_agency_to_bd(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_agency_to_bd(uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_agency_level(_agency_id uuid,_new_level smallint,_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE oldv smallint;
BEGIN
  PERFORM public._require_perm('agencies.level');
  SELECT level_id INTO oldv FROM public.agencies WHERE id=_agency_id FOR UPDATE;
  UPDATE public.agencies SET level_id=_new_level WHERE id=_agency_id;
  INSERT INTO public.agency_level_history(agency_id,old_level,new_level,reason,changed_by) VALUES (_agency_id,oldv,_new_level,_reason,auth.uid());
END; $$;
REVOKE ALL ON FUNCTION public.update_agency_level(uuid,smallint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_agency_level(uuid,smallint,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.add_host_to_agency(_user_id uuid,_agency_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE h uuid;
BEGIN
  PERFORM public._require_perm('hosts.write');
  INSERT INTO public.hosts(user_id,agency_id,status,level_id) VALUES (_user_id,_agency_id,'active',1)
  ON CONFLICT (user_id) DO UPDATE SET agency_id=EXCLUDED.agency_id, status='active' RETURNING id INTO h;
  UPDATE public.agencies SET total_hosts=total_hosts+1, active_hosts=active_hosts+1 WHERE id=_agency_id;
  RETURN h;
END; $$;
REVOKE ALL ON FUNCTION public.add_host_to_agency(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_host_to_agency(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_host_from_agency(_host_id uuid,_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE aid uuid;
BEGIN
  PERFORM public._require_perm('hosts.write');
  IF _reason IS NULL OR length(_reason)<5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT agency_id INTO aid FROM public.hosts WHERE id=_host_id;
  UPDATE public.hosts SET agency_id=NULL, status='left', left_at=now() WHERE id=_host_id;
  IF aid IS NOT NULL THEN UPDATE public.agencies SET active_hosts=GREATEST(active_hosts-1,0) WHERE id=aid; END IF;
END; $$;
REVOKE ALL ON FUNCTION public.remove_host_from_agency(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_host_from_agency(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.suspend_host(_host_id uuid,_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public._require_perm('hosts.suspend');
  IF _reason IS NULL OR length(_reason)<5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE public.hosts SET status='suspended', suspend_reason=_reason WHERE id=_host_id;
END; $$;
REVOKE ALL ON FUNCTION public.suspend_host(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suspend_host(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reactivate_host(_host_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('hosts.suspend'); UPDATE public.hosts SET status='active', suspend_reason=NULL WHERE id=_host_id AND status='suspended'; END; $$;
REVOKE ALL ON FUNCTION public.reactivate_host(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reactivate_host(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_host_level(_host_id uuid,_level smallint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('hosts.write'); UPDATE public.hosts SET level_id=_level WHERE id=_host_id; END; $$;
REVOKE ALL ON FUNCTION public.update_host_level(uuid,smallint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_host_level(uuid,smallint) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_host_transfer_request(_host_user_id uuid,_to_agency_id uuid,_reason text,_idempotency_key text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE from_agency uuid; new_id uuid; existing uuid; h RECORD;
BEGIN
  PERFORM public._require_perm('hosts.transfer');
  IF _reason IS NULL OR length(_reason)<5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF _idempotency_key IS NOT NULL THEN
    SELECT id INTO existing FROM public.agency_host_transfer_requests WHERE idempotency_key=_idempotency_key;
    IF existing IS NOT NULL THEN RETURN existing; END IF;
  END IF;
  SELECT * INTO h FROM public.hosts WHERE user_id=_host_user_id FOR UPDATE;
  IF h.id IS NULL THEN RAISE EXCEPTION 'HOST_NOT_FOUND'; END IF;
  IF h.debt>0 THEN RAISE EXCEPTION 'HOST_HAS_DEBT: %', h.debt; END IF;
  IF h.pending_earnings>0 THEN RAISE EXCEPTION 'HOST_HAS_PENDING_EARNINGS: %', h.pending_earnings; END IF;
  IF h.cooldown_until IS NOT NULL AND h.cooldown_until>now() THEN RAISE EXCEPTION 'HOST_IN_COOLDOWN: %', h.cooldown_until; END IF;
  from_agency := h.agency_id;
  INSERT INTO public.agency_host_transfer_requests(host_user_id,from_agency_id,to_agency_id,reason,idempotency_key,created_by)
  VALUES (_host_user_id,from_agency,_to_agency_id,_reason,_idempotency_key,auth.uid()) RETURNING id INTO new_id;
  RETURN new_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_host_transfer_request(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_host_transfer_request(uuid,uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public._transfer_approve(_transfer_id uuid,_stage text,_decision text,_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD; new_status text;
BEGIN
  IF _stage NOT IN ('source','target','bd','admin') THEN RAISE EXCEPTION 'INVALID_STAGE'; END IF;
  IF _decision NOT IN ('approved','rejected') THEN RAISE EXCEPTION 'INVALID_DECISION'; END IF;
  SELECT * INTO r FROM public.agency_host_transfer_requests WHERE id=_transfer_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF r.status IN ('completed','rejected','cancelled') THEN RAISE EXCEPTION 'ALREADY_FINAL'; END IF;
  EXECUTE format('UPDATE public.agency_host_transfer_requests SET %I=$1, %I=$2, %I=now(), %I=$3 WHERE id=$4',
    _stage||'_decision',_stage||'_decided_by',_stage||'_decided_at',_stage||'_note')
    USING _decision, auth.uid(), _note, _transfer_id;
  IF _decision='rejected' THEN UPDATE public.agency_host_transfer_requests SET status='rejected' WHERE id=_transfer_id; RETURN; END IF;
  SELECT * INTO r FROM public.agency_host_transfer_requests WHERE id=_transfer_id;
  IF r.source_decision='approved' AND r.target_decision='approved' AND COALESCE(r.bd_decision,'approved')='approved' AND COALESCE(r.admin_decision,'approved')='approved' THEN new_status:='bd_approved';
  ELSIF r.target_decision='approved' THEN new_status:='target_approved';
  ELSIF r.source_decision='approved' THEN new_status:='source_approved';
  ELSE new_status:=r.status; END IF;
  UPDATE public.agency_host_transfer_requests SET status=new_status WHERE id=_transfer_id;
END; $$;

CREATE OR REPLACE FUNCTION public.approve_host_transfer_source(_transfer_id uuid,_decision text,_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('hosts.transfer'); PERFORM public._transfer_approve(_transfer_id,'source',_decision,_note); END; $$;
CREATE OR REPLACE FUNCTION public.approve_host_transfer_target(_transfer_id uuid,_decision text,_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('hosts.transfer'); PERFORM public._transfer_approve(_transfer_id,'target',_decision,_note); END; $$;
CREATE OR REPLACE FUNCTION public.approve_host_transfer_bd(_transfer_id uuid,_decision text,_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('hosts.transfer'); PERFORM public._transfer_approve(_transfer_id,'bd',_decision,_note); END; $$;
CREATE OR REPLACE FUNCTION public.approve_host_transfer_admin(_transfer_id uuid,_decision text,_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('hosts.transfer'); PERFORM public._transfer_approve(_transfer_id,'admin',_decision,_note); END; $$;
REVOKE ALL ON FUNCTION public.approve_host_transfer_source(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_host_transfer_target(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_host_transfer_bd(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_host_transfer_admin(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_host_transfer_source(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_host_transfer_target(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_host_transfer_bd(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_host_transfer_admin(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.execute_host_transfer(_transfer_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD;
BEGIN
  PERFORM public._require_perm('hosts.transfer');
  SELECT * INTO r FROM public.agency_host_transfer_requests WHERE id=_transfer_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF r.status <> 'bd_approved' THEN RAISE EXCEPTION 'NOT_READY: %', r.status; END IF;
  UPDATE public.hosts SET agency_id=r.to_agency_id, cooldown_until=now()+interval '14 days' WHERE user_id=r.host_user_id;
  IF r.from_agency_id IS NOT NULL THEN UPDATE public.agencies SET active_hosts=GREATEST(active_hosts-1,0) WHERE id=r.from_agency_id; END IF;
  UPDATE public.agencies SET active_hosts=active_hosts+1, total_hosts=total_hosts+1 WHERE id=r.to_agency_id;
  UPDATE public.agency_host_transfer_requests SET status='completed', executed_at=now() WHERE id=_transfer_id;
END; $$;
REVOKE ALL ON FUNCTION public.execute_host_transfer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.execute_host_transfer(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_host_transfer(_transfer_id uuid,_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public._require_perm('hosts.transfer');
  UPDATE public.agency_host_transfer_requests SET status='cancelled', admin_note=_reason WHERE id=_transfer_id AND status NOT IN ('completed','rejected','cancelled');
END; $$;
REVOKE ALL ON FUNCTION public.cancel_host_transfer(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_host_transfer(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_bd_manager(_code text,_display_name text,_admin_user_id uuid,_level smallint,_country text,_phone text,_email text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE new_id uuid;
BEGIN
  PERFORM public._require_perm('bd.write');
  INSERT INTO public.bd_managers(code,display_name,admin_user_id,level_id,country,phone,email,created_by)
  VALUES (_code,_display_name,_admin_user_id,COALESCE(_level,1),_country,_phone,_email,auth.uid()) RETURNING id INTO new_id;
  RETURN new_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_bd_manager(text,text,uuid,smallint,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_bd_manager(text,text,uuid,smallint,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_bd_level(_bd_id uuid,_level smallint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('bd.write'); UPDATE public.bd_managers SET level_id=_level WHERE id=_bd_id; END; $$;
REVOKE ALL ON FUNCTION public.update_bd_level(uuid,smallint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_bd_level(uuid,smallint) TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_agency_bd(_agency_id uuid,_bd_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public.transfer_agency_to_bd(_agency_id,_bd_id,'Initial assignment'); END; $$;
REVOKE ALL ON FUNCTION public.assign_agency_bd(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_agency_bd(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_agency_join_request(_agency_id uuid,_user_id uuid,_message text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE new_id uuid;
BEGIN PERFORM public._require_perm('hosts.write');
  INSERT INTO public.agency_join_requests(agency_id,user_id,message) VALUES (_agency_id,_user_id,_message) RETURNING id INTO new_id;
  RETURN new_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_agency_join_request(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_agency_join_request(uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.approve_agency_join_request(_req_id uuid,_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r RECORD;
BEGIN PERFORM public._require_perm('hosts.write');
  SELECT * INTO r FROM public.agency_join_requests WHERE id=_req_id FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'pending' THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  PERFORM public.add_host_to_agency(r.user_id,r.agency_id);
  UPDATE public.agency_join_requests SET status='approved', reviewed_by=auth.uid(), reviewed_at=now(), review_note=_note WHERE id=_req_id;
END; $$;
REVOKE ALL ON FUNCTION public.approve_agency_join_request(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_agency_join_request(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reject_agency_join_request(_req_id uuid,_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('hosts.write');
  UPDATE public.agency_join_requests SET status='rejected', reviewed_by=auth.uid(), reviewed_at=now(), review_note=_note WHERE id=_req_id AND status='pending';
END; $$;
REVOKE ALL ON FUNCTION public.reject_agency_join_request(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_agency_join_request(uuid,text) TO authenticated;
