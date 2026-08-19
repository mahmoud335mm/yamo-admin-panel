
REVOKE EXECUTE ON FUNCTION public.tg_refund_state_machine() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.tg_refund_state_machine() TO service_role;

REVOKE EXECUTE ON FUNCTION public._refund_transition_ok(public.refund_status, public.refund_status) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public._refund_transition_ok(public.refund_status, public.refund_status) TO authenticated, service_role;
