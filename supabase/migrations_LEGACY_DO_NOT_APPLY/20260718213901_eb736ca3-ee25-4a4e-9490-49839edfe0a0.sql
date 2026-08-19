
REVOKE EXECUTE ON FUNCTION public.resolve_recharge_dispute_policy(text,text,uuid,text,public.recharge_dispute_type_enum,public.recharge_dispute_source_enum) FROM anon;
REVOKE EXECUTE ON FUNCTION public.assert_no_overlapping_recharge_dispute_policies() FROM anon;
REVOKE EXECUTE ON FUNCTION public.preview_recharge_dispute_exposure(uuid,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.calculate_recharge_dispute_sla(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public._dispute_transition_ok(public.recharge_dispute_status_enum,public.recharge_dispute_status_enum) FROM anon;
