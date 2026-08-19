
-- Enums
DO $$ BEGIN
  CREATE TYPE public.recharge_package_status AS ENUM ('draft','review','published','paused','expired','archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE public.recharge_user_target AS ENUM ('all','new','existing','vip','host','agent');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.recharge_packages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,
  description_ar TEXT,
  description_en TEXT,
  image_url TEXT,
  base_coins BIGINT NOT NULL CHECK (base_coins >= 0),
  bonus_coins BIGINT NOT NULL DEFAULT 0 CHECK (bonus_coins >= 0),
  total_coins BIGINT GENERATED ALWAYS AS (base_coins + bonus_coins) STORED,
  sort_order INT NOT NULL DEFAULT 100,
  featured BOOLEAN NOT NULL DEFAULT FALSE,
  badge_text_ar TEXT, badge_text_en TEXT,
  terms_ar TEXT, terms_en TEXT,
  status public.recharge_package_status NOT NULL DEFAULT 'draft',
  version INT NOT NULL DEFAULT 1,
  starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ,
  published_at TIMESTAMPTZ, archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_recharge_packages_status ON public.recharge_packages(status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_recharge_packages_sort ON public.recharge_packages(sort_order) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_recharge_packages_featured ON public.recharge_packages(featured) WHERE featured = TRUE;
GRANT SELECT, INSERT, UPDATE ON public.recharge_packages TO authenticated;
GRANT ALL ON public.recharge_packages TO service_role;
ALTER TABLE public.recharge_packages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "packages_read" ON public.recharge_packages FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.read'));
CREATE POLICY "packages_insert" ON public.recharge_packages FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(auth.uid(),'recharge_packages.create'));
CREATE POLICY "packages_update" ON public.recharge_packages FOR UPDATE TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.update'))
  WITH CHECK (public.has_permission(auth.uid(),'recharge_packages.update'));

CREATE TABLE IF NOT EXISTS public.recharge_package_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id UUID NOT NULL REFERENCES public.recharge_packages(id) ON DELETE CASCADE,
  country_code TEXT, currency_code TEXT NOT NULL,
  price NUMERIC(18,4) NOT NULL CHECK (price >= 0),
  payment_gateway_id UUID, payment_method_id UUID,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_pkg_prices_pkg ON public.recharge_package_prices(package_id);
CREATE INDEX IF NOT EXISTS idx_pkg_prices_country ON public.recharge_package_prices(country_code, currency_code) WHERE active = TRUE;
GRANT SELECT, INSERT, UPDATE ON public.recharge_package_prices TO authenticated;
GRANT ALL ON public.recharge_package_prices TO service_role;
ALTER TABLE public.recharge_package_prices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pkg_prices_read" ON public.recharge_package_prices FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.read'));
CREATE POLICY "pkg_prices_write" ON public.recharge_package_prices FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.update'))
  WITH CHECK (public.has_permission(auth.uid(),'recharge_packages.update'));

CREATE TABLE IF NOT EXISTS public.recharge_package_bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id UUID NOT NULL REFERENCES public.recharge_packages(id) ON DELETE CASCADE,
  label_ar TEXT, label_en TEXT,
  extra_coins BIGINT NOT NULL DEFAULT 0 CHECK (extra_coins >= 0),
  target public.recharge_user_target NOT NULL DEFAULT 'all',
  starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pkg_bonuses_pkg ON public.recharge_package_bonuses(package_id);
GRANT SELECT, INSERT, UPDATE ON public.recharge_package_bonuses TO authenticated;
GRANT ALL ON public.recharge_package_bonuses TO service_role;
ALTER TABLE public.recharge_package_bonuses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pkg_bonuses_read" ON public.recharge_package_bonuses FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.read'));
CREATE POLICY "pkg_bonuses_write" ON public.recharge_package_bonuses FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.update'))
  WITH CHECK (public.has_permission(auth.uid(),'recharge_packages.update'));

CREATE TABLE IF NOT EXISTS public.recharge_package_targets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id UUID NOT NULL REFERENCES public.recharge_packages(id) ON DELETE CASCADE,
  country_codes TEXT[] DEFAULT '{}',
  min_level INT DEFAULT 0, max_level INT,
  min_vip INT DEFAULT 0, max_vip INT,
  user_target public.recharge_user_target NOT NULL DEFAULT 'all',
  include_user_ids UUID[] DEFAULT '{}',
  exclude_user_ids UUID[] DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pkg_targets_pkg ON public.recharge_package_targets(package_id);
GRANT SELECT, INSERT, UPDATE ON public.recharge_package_targets TO authenticated;
GRANT ALL ON public.recharge_package_targets TO service_role;
ALTER TABLE public.recharge_package_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pkg_targets_read" ON public.recharge_package_targets FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.read'));
CREATE POLICY "pkg_targets_write" ON public.recharge_package_targets FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.update'))
  WITH CHECK (public.has_permission(auth.uid(),'recharge_packages.update'));

CREATE TABLE IF NOT EXISTS public.recharge_package_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id UUID NOT NULL REFERENCES public.recharge_packages(id) ON DELETE CASCADE,
  version INT NOT NULL,
  snapshot JSONB NOT NULL,
  change_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  UNIQUE (package_id, version)
);
CREATE INDEX IF NOT EXISTS idx_pkg_versions_pkg ON public.recharge_package_versions(package_id, version DESC);
GRANT SELECT, INSERT ON public.recharge_package_versions TO authenticated;
GRANT ALL ON public.recharge_package_versions TO service_role;
ALTER TABLE public.recharge_package_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pkg_versions_read" ON public.recharge_package_versions FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.read'));
CREATE POLICY "pkg_versions_insert" ON public.recharge_package_versions FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(auth.uid(),'recharge_packages.update'));
CREATE POLICY "pkg_versions_no_update" ON public.recharge_package_versions AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "pkg_versions_no_delete" ON public.recharge_package_versions AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

CREATE TABLE IF NOT EXISTS public.recharge_package_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id UUID NOT NULL REFERENCES public.recharge_packages(id) ON DELETE CASCADE,
  stat_date DATE NOT NULL DEFAULT CURRENT_DATE,
  views_count BIGINT NOT NULL DEFAULT 0,
  purchases_count BIGINT NOT NULL DEFAULT 0,
  revenue_amount NUMERIC(18,4) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (package_id, stat_date)
);
CREATE INDEX IF NOT EXISTS idx_pkg_stats_date ON public.recharge_package_stats(stat_date DESC);
GRANT SELECT, INSERT, UPDATE ON public.recharge_package_stats TO authenticated;
GRANT ALL ON public.recharge_package_stats TO service_role;
ALTER TABLE public.recharge_package_stats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pkg_stats_read" ON public.recharge_package_stats FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'recharge_packages.read'));

CREATE TRIGGER trg_packages_updated_at BEFORE UPDATE ON public.recharge_packages FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pkg_prices_updated_at BEFORE UPDATE ON public.recharge_package_prices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pkg_bonuses_updated_at BEFORE UPDATE ON public.recharge_package_bonuses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pkg_targets_updated_at BEFORE UPDATE ON public.recharge_package_targets FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_pkg_stats_updated_at BEFORE UPDATE ON public.recharge_package_stats FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_packages_audit AFTER INSERT OR UPDATE OR DELETE ON public.recharge_packages FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_pkg_prices_audit AFTER INSERT OR UPDATE OR DELETE ON public.recharge_package_prices FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

CREATE OR REPLACE FUNCTION public.tg_recharge_package_version_snapshot()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND (
    OLD.name_ar IS DISTINCT FROM NEW.name_ar OR OLD.name_en IS DISTINCT FROM NEW.name_en OR
    OLD.base_coins IS DISTINCT FROM NEW.base_coins OR OLD.bonus_coins IS DISTINCT FROM NEW.bonus_coins OR
    OLD.status IS DISTINCT FROM NEW.status
  ) THEN
    NEW.version := OLD.version + 1;
    INSERT INTO public.recharge_package_versions(package_id, version, snapshot, created_by)
    VALUES (OLD.id, OLD.version, to_jsonb(OLD), auth.uid());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_packages_versioning BEFORE UPDATE ON public.recharge_packages FOR EACH ROW EXECUTE FUNCTION public.tg_recharge_package_version_snapshot();

CREATE OR REPLACE FUNCTION public.create_recharge_package(_code TEXT,_name_ar TEXT,_name_en TEXT,_base_coins BIGINT,_bonus_coins BIGINT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE new_id UUID;
BEGIN PERFORM public._require_perm('recharge_packages.create');
  INSERT INTO public.recharge_packages(code,name_ar,name_en,base_coins,bonus_coins,created_by,updated_by)
  VALUES (_code,_name_ar,_name_en,_base_coins,COALESCE(_bonus_coins,0),auth.uid(),auth.uid())
  RETURNING id INTO new_id; RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION public.publish_recharge_package(_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('recharge_packages.publish');
  UPDATE public.recharge_packages SET status='published', published_at=COALESCE(published_at,now()), updated_by=auth.uid()
  WHERE id=_id AND status IN ('draft','review','paused');
END $$;

CREATE OR REPLACE FUNCTION public.pause_recharge_package(_id UUID,_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('recharge_packages.update');
  UPDATE public.recharge_packages SET status='paused', updated_by=auth.uid() WHERE id=_id AND status='published';
END $$;

CREATE OR REPLACE FUNCTION public.archive_recharge_package(_id UUID,_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM public._require_perm('recharge_packages.archive');
  UPDATE public.recharge_packages SET status='archived', archived_at=now(), updated_by=auth.uid() WHERE id=_id;
END $$;

CREATE OR REPLACE FUNCTION public.duplicate_recharge_package(_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE new_id UUID; src RECORD;
BEGIN PERFORM public._require_perm('recharge_packages.create');
  SELECT * INTO src FROM public.recharge_packages WHERE id=_id;
  IF src.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  INSERT INTO public.recharge_packages(code,name_ar,name_en,description_ar,description_en,image_url,base_coins,bonus_coins,sort_order,featured,badge_text_ar,badge_text_en,terms_ar,terms_en,status,created_by,updated_by)
  VALUES (src.code||'-copy-'||substr(gen_random_uuid()::text,1,6), src.name_ar||' (نسخة)', src.name_en||' (copy)',
    src.description_ar,src.description_en,src.image_url,src.base_coins,src.bonus_coins,src.sort_order,false,
    src.badge_text_ar,src.badge_text_en,src.terms_ar,src.terms_en,'draft',auth.uid(),auth.uid())
  RETURNING id INTO new_id; RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION public.rollback_recharge_package(_id UUID,_to_version INT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE snap JSONB;
BEGIN PERFORM public._require_perm('recharge_packages.update');
  SELECT snapshot INTO snap FROM public.recharge_package_versions WHERE package_id=_id AND version=_to_version;
  IF snap IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  UPDATE public.recharge_packages SET
    name_ar=snap->>'name_ar', name_en=snap->>'name_en',
    description_ar=snap->>'description_ar', description_en=snap->>'description_en',
    image_url=snap->>'image_url',
    base_coins=(snap->>'base_coins')::bigint, bonus_coins=(snap->>'bonus_coins')::bigint,
    badge_text_ar=snap->>'badge_text_ar', badge_text_en=snap->>'badge_text_en',
    terms_ar=snap->>'terms_ar', terms_en=snap->>'terms_en',
    updated_by=auth.uid() WHERE id=_id;
END $$;

INSERT INTO public.permissions(key, module, label_ar, label_en, description) VALUES
  ('recharge_packages.read','finance','قراءة باقات الشحن','Read recharge packages',NULL),
  ('recharge_packages.create','finance','إنشاء باقات شحن','Create recharge packages',NULL),
  ('recharge_packages.update','finance','تعديل باقات الشحن','Update recharge packages',NULL),
  ('recharge_packages.publish','finance','نشر باقات الشحن','Publish recharge packages',NULL),
  ('recharge_packages.archive','finance','أرشفة باقات الشحن','Archive recharge packages',NULL)
ON CONFLICT (key) DO NOTHING;
