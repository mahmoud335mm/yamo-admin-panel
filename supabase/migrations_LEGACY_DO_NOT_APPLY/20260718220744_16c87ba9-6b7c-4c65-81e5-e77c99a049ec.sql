
-- 1) Retire weak 1-arg retry_payment_webhook (superseded by reason+idempotency version)
DROP FUNCTION IF EXISTS public.retry_payment_webhook(uuid);

-- 2) Ensure allowlist columns support risk classification
ALTER TABLE public.security_definer_public_allowlist
  ADD COLUMN IF NOT EXISTS risk text
    CHECK (risk IN ('low','medium','high','critical'));
ALTER TABLE public.security_definer_public_allowlist
  ADD COLUMN IF NOT EXISTS decision text
    CHECK (decision IN (
      'KEEP_AUTHENTICATED_ADMIN_RPC',
      'SPLIT_PUBLIC_WRAPPER_AND_INTERNAL_HELPER',
      'MOVE_TO_SERVICE_ROLE_ONLY',
      'REPLACE_WITH_PURPOSE_SPECIFIC_RPC',
      'DEPRECATE_AND_REVOKE',
      'KEEP_USER_OWNED_WRITE',
      'KEEP_READ_ONLY_LOOKUP',
      'KEEP_SERVICE_ROLE_GATED'
    ));

-- 3) Populate allowlist for every current authenticated-callable SECURITY DEFINER
--    function in public. Justification derived from static inspection (5D-1.2).
INSERT INTO public.security_definer_public_allowlist(function_name, function_args, reason, risk, decision)
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid),
  CASE
    -- read-only lookups
    WHEN p.proname IN ('my_permissions','my_roles') THEN 'Self-permissions lookup; scoped to auth.uid()'
    WHEN p.proname IN ('preview_admin_invite') THEN 'Pre-login invite preview; hashes token, returns invite metadata only'
    WHEN p.proname LIKE 'resolve_%' THEN 'Deterministic policy/pricing resolver; STABLE; no writes'
    WHEN p.proname LIKE 'get_%' THEN 'Read-only lookup; STABLE'
    WHEN p.proname LIKE 'calculate_%' THEN 'Read-only SLA/derived-metric calculator; STABLE'
    -- emergency
    WHEN p.proname='emergency_grant_super_admin' THEN 'Internally gated to service_role/postgres session; authenticated callers get RAISE'
    -- admin wallet wrappers (call _admin_wallet_adjust which enforces permission)
    WHEN p.proname IN ('admin_credit_user_coins','admin_credit_user_pearls','admin_debit_user_coins','admin_debit_user_pearls')
      THEN 'Thin wrapper over _admin_wallet_adjust; enforces auth.uid, per-kind permission, reason>=5, idempotency, FOR UPDATE lock, double-entry ledger, no negative balance, audit + notification'
    -- user-owned writes
    WHEN p.proname IN ('accept_admin_invite','create_recharge_request','create_recharge_receipt_upload',
                       'submit_recharge_receipt','request_withdrawal','exchange_pearls_to_coins',
                       'charging_agent_transfer_coins','charging_agent_transfer_pearls')
      THEN 'User-owned write; actor derived from auth.uid(); enforces per-user quotas/state guards'
    -- everything else with permission check
    ELSE 'Admin write RPC; enforces _require_perm() / has_permission(auth.uid(),...) and audit'
  END AS reason,
  CASE
    -- CRITICAL: writes money / changes financial terminal state
    WHEN p.proname IN (
      'admin_credit_user_coins','admin_credit_user_pearls','admin_debit_user_coins','admin_debit_user_pearls',
      'reverse_admin_wallet_adjustment','mark_withdrawal_paid','execute_host_transfer',
      'charging_agent_transfer_coins','charging_agent_transfer_pearls','exchange_pearls_to_coins',
      'request_withdrawal','create_recharge_request','submit_recharge_receipt',
      'request_recharge_refund','approve_recharge_refund','second_approve_recharge_refund',
      'execute_recharge_refund','reject_recharge_refund','cancel_recharge_refund','review_recharge_refund',
      'apply_charging_debt_payment','settle_charging_debt'
    ) THEN 'critical'
    -- HIGH: permission/role/status writes, dispute + gateway retry, package + policy writers
    WHEN p.proname IN ('emergency_grant_super_admin','update_charging_agent_permissions',
                       'update_charging_agent_limits','suspend_host','reactivate_host',
                       'reactivate_agency','reactivate_charging_agent','remove_host_from_agency',
                       'remove_agent_from_charging_agency','approve_host_transfer_admin',
                       'approve_host_transfer_bd','approve_host_transfer_source','approve_host_transfer_target',
                       'cancel_host_transfer','retry_payment_webhook','accept_admin_invite')
      OR p.proname LIKE '%_dispute_%' OR p.proname LIKE '%_publish' OR p.proname LIKE 'publish_%'
      THEN 'high'
    -- LOW: read-only lookups
    WHEN p.proname IN ('my_permissions','my_roles','preview_admin_invite')
      OR p.proname LIKE 'resolve_%' OR p.proname LIKE 'get_%' OR p.proname LIKE 'calculate_%'
      THEN 'low'
    -- MEDIUM: everything else (admin metadata edits, non-financial writes)
    ELSE 'medium'
  END AS risk,
  CASE
    WHEN p.proname IN ('my_permissions','my_roles','preview_admin_invite')
      OR p.proname LIKE 'resolve_%' OR p.proname LIKE 'get_%' OR p.proname LIKE 'calculate_%'
      THEN 'KEEP_READ_ONLY_LOOKUP'
    WHEN p.proname='emergency_grant_super_admin' THEN 'KEEP_SERVICE_ROLE_GATED'
    WHEN p.proname IN ('accept_admin_invite','create_recharge_request','create_recharge_receipt_upload',
                       'submit_recharge_receipt','request_withdrawal','exchange_pearls_to_coins',
                       'charging_agent_transfer_coins','charging_agent_transfer_pearls')
      THEN 'KEEP_USER_OWNED_WRITE'
    ELSE 'KEEP_AUTHENTICATED_ADMIN_RPC'
  END AS decision
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.prosecdef
  AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
ON CONFLICT DO NOTHING;
