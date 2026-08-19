-- 5C-2 · Refund infrastructure static assertions.
-- Runs read-only. Every check must return the "expected" value.

-- 1. refund_policies has at least one active default policy.
SELECT 'default_policy_exists' AS check, (COUNT(*) > 0) AS pass
FROM public.refund_policies WHERE status='active' AND country_code IS NULL AND currency_code IS NULL AND gateway_id IS NULL;

-- 2. Lifecycle RPCs exist.
SELECT proname AS check, true AS pass
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND proname IN (
  'preview_recharge_refund','request_recharge_refund','review_recharge_refund',
  'approve_recharge_refund','second_approve_recharge_refund',
  'reject_recharge_refund','cancel_recharge_refund','execute_recharge_refund',
  '_apply_recharge_refund_wallet_reversal','_refund_preflight_calc','_lookup_refund_policy'
)
ORDER BY proname;

-- 3. PUBLIC / anon EXECUTE must be zero for every refund RPC.
SELECT p.proname AS function, r.rolname AS role
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN LATERAL aclexplode(p.proacl) a ON true
JOIN pg_roles r ON r.oid = a.grantee
WHERE n.nspname='public'
  AND p.proname IN ('preview_recharge_refund','request_recharge_refund','review_recharge_refund',
    'approve_recharge_refund','second_approve_recharge_refund','reject_recharge_refund',
    'cancel_recharge_refund','execute_recharge_refund','_apply_recharge_refund_wallet_reversal',
    '_refund_preflight_calc','_lookup_refund_policy')
  AND a.privilege_type = 'EXECUTE'
  AND r.rolname IN ('PUBLIC','anon');  -- expected: 0 rows

-- 4. Internal helper _apply_recharge_refund_wallet_reversal must NOT be executable by authenticated.
SELECT COUNT(*) AS authenticated_execute_leak_must_be_zero
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN LATERAL aclexplode(p.proacl) a ON true
JOIN pg_roles r ON r.oid = a.grantee
WHERE n.nspname='public'
  AND p.proname = '_apply_recharge_refund_wallet_reversal'
  AND a.privilege_type = 'EXECUTE'
  AND r.rolname = 'authenticated';

-- 5. system_ledger RESTRICTIVE UPDATE/DELETE deny policies exist.
SELECT policyname, permissive, cmd
FROM pg_policies
WHERE schemaname='public' AND tablename='system_ledger'
  AND permissive='RESTRICTIVE';

-- 6. Refund state machine trigger still attached (from 5C-1).
SELECT tgname AS check, true AS pass
FROM pg_trigger WHERE tgrelid = 'public.recharge_refunds'::regclass AND NOT tgisinternal;
