
CREATE OR REPLACE FUNCTION public.assign_agency_bd(_agency_id uuid, _bd_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF NOT public.has_permission(v_actor, 'agencies.assign_bd')
     AND NOT public.has_permission(v_actor, 'agencies.manage') THEN
    RAISE EXCEPTION 'FORBIDDEN: agencies.assign_bd required' USING ERRCODE='42501';
  END IF;
  IF _agency_id IS NULL OR _bd_id IS NULL THEN RAISE EXCEPTION 'invalid_arguments'; END IF;

  INSERT INTO public.bd_agencies (bd_id, agency_id, assigned_by, assigned_at)
  VALUES (_bd_id, _agency_id, v_actor, now())
  ON CONFLICT (bd_id, agency_id) DO NOTHING;

  INSERT INTO public.audit_logs (actor_id, action, target_type, target_id, metadata, created_at)
  VALUES (v_actor, 'agency.assign_bd', 'agency', _agency_id,
          jsonb_build_object('bd_id', _bd_id), now());
END $$;

REVOKE EXECUTE ON FUNCTION public.assign_agency_bd(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.assign_agency_bd(uuid, uuid) TO authenticated;

INSERT INTO public.permissions (key, module, label_ar, label_en, description)
VALUES ('agencies.assign_bd', 'agencies', 'تعيين مدير BD للوكالة', 'Assign BD to agency', 'Assign a BD manager to an agency')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions (role, permission_key)
SELECT r.role, 'agencies.assign_bd' FROM public.roles r
WHERE r.role::text IN ('super_admin','admin')
ON CONFLICT DO NOTHING;
