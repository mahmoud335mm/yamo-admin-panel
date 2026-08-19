
REVOKE EXECUTE ON FUNCTION public._enqueue_txn_message(text,text,uuid,uuid,jsonb,text)                              FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.resolve_payment_instructions(uuid)                                                 FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_recharge_receipt_upload(uuid,text,bigint)                                   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.submit_recharge_receipt(uuid,text,numeric,text,text,timestamptz)                   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.review_recharge_receipt(uuid,text,text)                                            FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_recharge_receipt_signed_url(uuid,int)                                          FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.complete_recharge_request(uuid,text)                                               FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fail_recharge_request(uuid,text)                                                   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cancel_recharge_request(uuid,text)                                                 FROM PUBLIC, anon;
-- also ensure allowlist call safe
REVOKE EXECUTE ON FUNCTION public.audit_authenticated_security_definer()                                             FROM PUBLIC, anon;
