
-- =====================================================================
-- PHASE 1 — Foundation (Auth / RBAC / Audit)
-- =====================================================================

-- 1. ENUMS ------------------------------------------------------------
CREATE TYPE public.admin_role AS ENUM (
  'super_admin',
  'admin',
  'finance',
  'moderator',
  'agency_manager',
  'bd_manager',
  'support',
  'auditor',
  'viewer'
);

-- 2. admin_users ------------------------------------------------------
CREATE TABLE public.admin_users (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT NOT NULL UNIQUE,
  full_name     TEXT,
  avatar_url    TEXT,
  phone         TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_users TO authenticated;
GRANT ALL ON public.admin_users TO service_role;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- 3. roles catalog ----------------------------------------------------
CREATE TABLE public.roles (
  role        public.admin_role PRIMARY KEY,
  label_ar    TEXT NOT NULL,
  label_en    TEXT NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.roles TO authenticated;
GRANT ALL   ON public.roles TO service_role;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

-- 4. permissions catalog ---------------------------------------------
CREATE TABLE public.permissions (
  key         TEXT PRIMARY KEY,
  module      TEXT NOT NULL,
  label_ar    TEXT NOT NULL,
  label_en    TEXT NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.permissions TO authenticated;
GRANT ALL   ON public.permissions TO service_role;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;

-- 5. role_permissions -------------------------------------------------
CREATE TABLE public.role_permissions (
  role           public.admin_role NOT NULL,
  permission_key TEXT NOT NULL REFERENCES public.permissions(key) ON DELETE CASCADE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (role, permission_key)
);
GRANT SELECT, INSERT, DELETE ON public.role_permissions TO authenticated;
GRANT ALL ON public.role_permissions TO service_role;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

-- 6. admin_role_assignments -------------------------------------------
CREATE TABLE public.admin_role_assignments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id UUID NOT NULL REFERENCES public.admin_users(id) ON DELETE CASCADE,
  role          public.admin_role NOT NULL,
  granted_by    UUID REFERENCES public.admin_users(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (admin_user_id, role)
);
GRANT SELECT, INSERT, DELETE ON public.admin_role_assignments TO authenticated;
GRANT ALL ON public.admin_role_assignments TO service_role;
ALTER TABLE public.admin_role_assignments ENABLE ROW LEVEL SECURITY;

-- 7. audit_logs -------------------------------------------------------
CREATE TABLE public.audit_logs (
  id           BIGSERIAL PRIMARY KEY,
  actor_id     UUID REFERENCES public.admin_users(id),
  actor_email  TEXT,
  action       TEXT NOT NULL,
  entity_type  TEXT,
  entity_id    TEXT,
  metadata     JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address   TEXT,
  user_agent   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_actor_idx     ON public.audit_logs (actor_id, created_at DESC);
CREATE INDEX audit_logs_entity_idx    ON public.audit_logs (entity_type, entity_id);
CREATE INDEX audit_logs_created_idx   ON public.audit_logs (created_at DESC);
GRANT SELECT, INSERT ON public.audit_logs TO authenticated;
GRANT USAGE, SELECT  ON SEQUENCE public.audit_logs_id_seq TO authenticated;
GRANT ALL ON public.audit_logs TO service_role;
GRANT ALL ON SEQUENCE public.audit_logs_id_seq TO service_role;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- SECURITY DEFINER HELPERS
-- =====================================================================

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.admin_role)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_role_assignments a
    JOIN public.admin_users u ON u.id = a.admin_user_id
    WHERE a.admin_user_id = _user_id AND a.role = _role AND u.is_active = TRUE
  );
$$;

CREATE OR REPLACE FUNCTION public.has_permission(_user_id UUID, _permission TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_role_assignments a
    JOIN public.admin_users u        ON u.id = a.admin_user_id
    JOIN public.role_permissions rp  ON rp.role = a.role
    WHERE a.admin_user_id = _user_id
      AND u.is_active = TRUE
      AND (rp.permission_key = _permission OR a.role = 'super_admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users u
    WHERE u.id = _user_id AND u.is_active = TRUE
  );
$$;

CREATE OR REPLACE FUNCTION public.my_permissions()
RETURNS TABLE(permission_key TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT DISTINCT
    CASE WHEN a.role = 'super_admin' THEN p.key ELSE rp.permission_key END AS permission_key
  FROM public.admin_role_assignments a
  JOIN public.admin_users u ON u.id = a.admin_user_id
  LEFT JOIN public.role_permissions rp ON rp.role = a.role
  LEFT JOIN public.permissions p ON a.role = 'super_admin'
  WHERE a.admin_user_id = auth.uid() AND u.is_active = TRUE;
$$;
GRANT EXECUTE ON FUNCTION public.my_permissions() TO authenticated;

CREATE OR REPLACE FUNCTION public.my_roles()
RETURNS TABLE(role public.admin_role)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.role FROM public.admin_role_assignments a
  JOIN public.admin_users u ON u.id = a.admin_user_id
  WHERE a.admin_user_id = auth.uid() AND u.is_active = TRUE;
$$;
GRANT EXECUTE ON FUNCTION public.my_roles() TO authenticated;

-- =====================================================================
-- RLS POLICIES
-- =====================================================================

-- admin_users: any active admin can read, only super_admin can write; each admin can read themselves.
CREATE POLICY "admins read admin_users"
  ON public.admin_users FOR SELECT TO authenticated
  USING (public.is_admin(auth.uid()));

CREATE POLICY "self read admin_users"
  ON public.admin_users FOR SELECT TO authenticated
  USING (id = auth.uid());

CREATE POLICY "super_admin writes admin_users"
  ON public.admin_users FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "self update basic fields"
  ON public.admin_users FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- roles catalog: readable by any admin, writable by super_admin
CREATE POLICY "admins read roles"
  ON public.roles FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY "super_admin manage roles"
  ON public.roles FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- permissions catalog: readable by any admin, writable by super_admin
CREATE POLICY "admins read permissions"
  ON public.permissions FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY "super_admin manage permissions"
  ON public.permissions FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- role_permissions: readable by any admin, writable by super_admin
CREATE POLICY "admins read role_permissions"
  ON public.role_permissions FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY "super_admin manage role_permissions"
  ON public.role_permissions FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- admin_role_assignments: admins can read, only super_admin writes; self read
CREATE POLICY "admins read assignments"
  ON public.admin_role_assignments FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY "super_admin manage assignments"
  ON public.admin_role_assignments FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- audit_logs: readable by admins with audit.read (or super_admin), inserts by any authenticated admin.
CREATE POLICY "audit read"
  ON public.audit_logs FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'audit.read'));
CREATE POLICY "audit insert own"
  ON public.audit_logs FOR INSERT TO authenticated
  WITH CHECK (public.is_admin(auth.uid()) AND (actor_id = auth.uid() OR actor_id IS NULL));

-- =====================================================================
-- updated_at trigger
-- =====================================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;
CREATE TRIGGER admin_users_touch BEFORE UPDATE ON public.admin_users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =====================================================================
-- Auth signup handler: register admin_users, bootstrap first super_admin
-- =====================================================================
CREATE OR REPLACE FUNCTION public.handle_new_admin_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  admin_count INTEGER;
BEGIN
  INSERT INTO public.admin_users (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;

  SELECT COUNT(*) INTO admin_count FROM public.admin_role_assignments;
  IF admin_count = 0 THEN
    INSERT INTO public.admin_role_assignments (admin_user_id, role)
    VALUES (NEW.id, 'super_admin');
    INSERT INTO public.audit_logs (actor_id, actor_email, action, entity_type, entity_id, metadata)
    VALUES (NEW.id, NEW.email, 'bootstrap.super_admin', 'admin_users', NEW.id::text,
            jsonb_build_object('reason', 'first signup auto-promoted'));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_admin_user();

-- =====================================================================
-- SEED: roles + permissions + role_permissions
-- =====================================================================

INSERT INTO public.roles (role, label_ar, label_en, description) VALUES
  ('super_admin',    'مدير أعلى',       'Super Admin',    'Full unrestricted access'),
  ('admin',          'مدير',            'Admin',          'General admin, most modules'),
  ('finance',        'مسؤول مالي',      'Finance',        'Wallets, ledger, withdrawals, payments'),
  ('moderator',      'مشرف محتوى',      'Moderator',      'Reports, moderation, penalties'),
  ('agency_manager', 'مدير الوكالات',   'Agency Manager', 'Agencies, hosts, transfers'),
  ('bd_manager',     'مدير BD',         'BD Manager',     'BD ops, own agencies'),
  ('support',        'دعم فني',         'Support',        'Read users, tickets, limited actions'),
  ('auditor',        'مدقق',            'Auditor',        'Read-only + audit logs'),
  ('viewer',         'مشاهد',           'Viewer',         'Read-only dashboard');

INSERT INTO public.permissions (key, module, label_ar, label_en) VALUES
  ('dashboard.view',       'dashboard', 'عرض الرئيسية',           'View dashboard'),
  ('users.read',           'users',     'قراءة المستخدمين',       'Read users'),
  ('users.write',          'users',     'تعديل المستخدمين',       'Edit users'),
  ('users.ban',            'users',     'حظر المستخدمين',         'Ban users'),
  ('users.verify',         'users',     'توثيق المستخدمين',       'Verify users'),
  ('agencies.read',        'agencies',  'قراءة الوكالات',         'Read agencies'),
  ('agencies.write',       'agencies',  'إدارة الوكالات',         'Manage agencies'),
  ('hosts.read',           'hosts',     'قراءة المضيفين',         'Read hosts'),
  ('hosts.write',          'hosts',     'إدارة المضيفين',         'Manage hosts'),
  ('bd.read',              'bd',        'قراءة BD',              'Read BD'),
  ('bd.write',             'bd',        'إدارة BD',              'Manage BD'),
  ('rooms.read',           'rooms',     'قراءة الغرف',            'Read rooms'),
  ('rooms.write',          'rooms',     'إدارة الغرف',            'Manage rooms'),
  ('messages.read',        'messages',  'قراءة الرسائل',          'Read messages'),
  ('calls.read',           'calls',     'قراءة المكالمات',        'Read calls'),
  ('posts.read',           'posts',     'قراءة المنشورات',        'Read posts'),
  ('posts.moderate',       'posts',     'مراقبة المنشورات',       'Moderate posts'),
  ('economy.read',         'economy',   'قراءة الاقتصاد',         'Read economy'),
  ('economy.write',        'economy',   'إدارة الاقتصاد',         'Manage economy'),
  ('withdrawals.read',     'withdraw',  'قراءة السحوبات',         'Read withdrawals'),
  ('withdrawals.approve',  'withdraw',  'اعتماد السحوبات',        'Approve withdrawals'),
  ('recharge.read',        'recharge',  'قراءة الشحن',            'Read recharge'),
  ('recharge.write',       'recharge',  'إدارة الشحن',            'Manage recharge'),
  ('gifts.read',           'gifts',     'قراءة الهدايا',          'Read gifts'),
  ('gifts.write',          'gifts',     'إدارة الهدايا',          'Manage gifts'),
  ('store.read',           'store',     'قراءة المتجر',           'Read store'),
  ('store.write',          'store',     'إدارة المتجر',           'Manage store'),
  ('games.read',           'games',     'قراءة الألعاب',          'Read games'),
  ('games.write',          'games',     'إدارة الألعاب',          'Manage games'),
  ('events.read',          'events',    'قراءة الفعاليات',        'Read events'),
  ('events.write',         'events',    'إدارة الفعاليات',        'Manage events'),
  ('banners.read',         'banners',   'قراءة البنرات',          'Read banners'),
  ('banners.write',        'banners',   'إدارة البنرات',          'Manage banners'),
  ('daily_login.read',     'daily',     'قراءة تسجيل الدخول',     'Read daily login'),
  ('daily_login.write',    'daily',     'إدارة تسجيل الدخول',     'Manage daily login'),
  ('notifications.read',   'notif',     'قراءة الإشعارات',        'Read notifications'),
  ('notifications.send',   'notif',     'إرسال الإشعارات',        'Send notifications'),
  ('reports.read',         'reports',   'قراءة البلاغات',         'Read reports'),
  ('reports.moderate',     'reports',   'إدارة البلاغات',         'Moderate reports'),
  ('ai.read',              'ai',        'قراءة الذكاء الاصطناعي', 'Read AI drafts'),
  ('ai.execute',           'ai',        'تنفيذ الذكاء الاصطناعي', 'Execute AI actions'),
  ('analytics.read',       'analytics', 'قراءة التقارير',         'Read analytics'),
  ('settings.read',        'settings',  'قراءة الإعدادات',        'Read settings'),
  ('settings.write',       'settings',  'تعديل الإعدادات',        'Edit settings'),
  ('admin.users.read',     'admin',     'قراءة المسؤولين',        'Read admins'),
  ('admin.users.write',    'admin',     'إدارة المسؤولين',        'Manage admins'),
  ('audit.read',           'admin',     'سجل العمليات',           'Read audit logs');

-- Grants per role (super_admin gets everything implicitly via has_permission)
-- admin: everything except admin.users.write & settings.write
INSERT INTO public.role_permissions (role, permission_key)
SELECT 'admin'::public.admin_role, key FROM public.permissions
WHERE key NOT IN ('admin.users.write','settings.write');

-- finance
INSERT INTO public.role_permissions (role, permission_key) VALUES
 ('finance','dashboard.view'),
 ('finance','economy.read'),('finance','economy.write'),
 ('finance','withdrawals.read'),('finance','withdrawals.approve'),
 ('finance','recharge.read'),('finance','recharge.write'),
 ('finance','users.read'),('finance','analytics.read'),('finance','audit.read');

-- moderator
INSERT INTO public.role_permissions (role, permission_key) VALUES
 ('moderator','dashboard.view'),
 ('moderator','users.read'),('moderator','users.ban'),
 ('moderator','reports.read'),('moderator','reports.moderate'),
 ('moderator','posts.read'),('moderator','posts.moderate'),
 ('moderator','messages.read'),('moderator','rooms.read'),('moderator','rooms.write'),
 ('moderator','calls.read');

-- agency_manager
INSERT INTO public.role_permissions (role, permission_key) VALUES
 ('agency_manager','dashboard.view'),
 ('agency_manager','agencies.read'),('agency_manager','agencies.write'),
 ('agency_manager','hosts.read'),('agency_manager','hosts.write'),
 ('agency_manager','users.read'),('agency_manager','analytics.read');

-- bd_manager
INSERT INTO public.role_permissions (role, permission_key) VALUES
 ('bd_manager','dashboard.view'),
 ('bd_manager','bd.read'),('bd_manager','bd.write'),
 ('bd_manager','agencies.read'),('bd_manager','hosts.read'),
 ('bd_manager','analytics.read');

-- support
INSERT INTO public.role_permissions (role, permission_key) VALUES
 ('support','dashboard.view'),
 ('support','users.read'),('support','reports.read'),
 ('support','messages.read'),('support','calls.read');

-- auditor: read-only across the board + audit
INSERT INTO public.role_permissions (role, permission_key)
SELECT 'auditor'::public.admin_role, key FROM public.permissions
WHERE key LIKE '%.read' OR key = 'audit.read' OR key = 'dashboard.view' OR key='analytics.read';

-- viewer
INSERT INTO public.role_permissions (role, permission_key) VALUES
 ('viewer','dashboard.view'),('viewer','analytics.read');
