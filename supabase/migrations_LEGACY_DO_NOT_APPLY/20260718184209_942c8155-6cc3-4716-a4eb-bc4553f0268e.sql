
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

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (v_actor, 'agency.assign_bd', 'agency', _agency_id::text,
          jsonb_build_object('bd_id', _bd_id));
END $$;
REVOKE EXECUTE ON FUNCTION public.assign_agency_bd(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.assign_agency_bd(uuid, uuid) TO authenticated;
