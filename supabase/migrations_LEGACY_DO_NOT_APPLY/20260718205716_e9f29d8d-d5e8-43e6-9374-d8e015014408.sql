
REVOKE ALL ON FUNCTION public._lookup_refund_retry_policy(uuid, payment_gateway_mode) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._lookup_refund_retry_policy(uuid, payment_gateway_mode) TO service_role;
