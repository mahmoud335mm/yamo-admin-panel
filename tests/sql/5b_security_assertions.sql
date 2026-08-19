-- 5B Security Assertions — every check emits (test_id, name, status, evidence)
WITH
-- 1. PUBLIC EXECUTE on SECURITY DEFINER = 0
t1 AS (
  SELECT 'SEC-001' AS id,
         'No PUBLIC EXECUTE on SECURITY DEFINER' AS name,
         COUNT(*)::text AS evidence,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND has_function_privilege('public', p.oid, 'EXECUTE')
),
-- 2. anon EXECUTE on SECURITY DEFINER = 0
t2 AS (
  SELECT 'SEC-002' AS id,
         'No anon EXECUTE on SECURITY DEFINER' AS name,
         COUNT(*)::text AS evidence,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
),
-- 3. security_definer_public_allowlist empty
t3 AS (
  SELECT 'SEC-003', 'security_definer_public_allowlist empty',
         COUNT(*)::text,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM public.security_definer_public_allowlist
),
-- 4. All SECURITY DEFINER have search_path set
t4 AS (
  SELECT 'SEC-004', 'SECURITY DEFINER functions have search_path',
         COUNT(*)::text,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prosecdef = true
    AND NOT EXISTS (
      SELECT 1 FROM unnest(coalesce(p.proconfig,'{}'::text[])) c
      WHERE c LIKE 'search_path=%'
    )
),
-- 5. audit_authenticated_security_definer returns 0 WARN + 0 FAIL
t5 AS (
  SELECT 'SEC-005', 'audit_authenticated_security_definer 0 WARN/FAIL',
         COALESCE((SELECT COUNT(*)::text FROM public.audit_authenticated_security_definer()
                    WHERE verdict IN ('WARN','FAIL')), 'n/a'),
         CASE WHEN COALESCE((SELECT COUNT(*) FROM public.audit_authenticated_security_definer()
                              WHERE verdict IN ('WARN','FAIL')), 0) = 0
              THEN 'PASS' ELSE 'FAIL' END
),
-- 13-14. wallet_ledger no UPDATE/DELETE policy (append-only)
t13 AS (
  SELECT 'SEC-013', 'wallet_ledger has no UPDATE policy',
         COUNT(*)::text,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM pg_policies WHERE schemaname='public' AND tablename='wallet_ledger' AND cmd='UPDATE' AND permissive='PERMISSIVE'
),
t14 AS (
  SELECT 'SEC-014', 'wallet_ledger has no DELETE policy',
         COUNT(*)::text,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM pg_policies WHERE schemaname='public' AND tablename='wallet_ledger' AND cmd='DELETE' AND permissive='PERMISSIVE'
),
-- 15-16. audit_logs no UPDATE/DELETE policy
t15 AS (
  SELECT 'SEC-015', 'audit_logs has no UPDATE policy',
         COUNT(*)::text,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM pg_policies WHERE schemaname='public' AND tablename='audit_logs' AND cmd='UPDATE' AND permissive='PERMISSIVE'
),
t16 AS (
  SELECT 'SEC-016', 'audit_logs has no DELETE policy',
         COUNT(*)::text,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM pg_policies WHERE schemaname='public' AND tablename='audit_logs' AND cmd='DELETE' AND permissive='PERMISSIVE'
),
-- 17. transaction_message_outbox: no client write policies
t17 AS (
  SELECT 'SEC-017', 'transaction_message_outbox no client INSERT/UPDATE/DELETE policy',
         COUNT(*)::text,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM pg_policies
  WHERE schemaname='public' AND tablename='transaction_message_outbox'
    AND cmd IN ('INSERT','UPDATE','DELETE')
    AND 'authenticated' = ANY(roles)
),
-- 19. payment_webhooks: no direct client write policies
t19 AS (
  SELECT 'SEC-019', 'payment_webhooks no client INSERT/UPDATE/DELETE policy',
         COUNT(*)::text,
         CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM pg_policies
  WHERE schemaname='public' AND tablename='payment_webhooks'
    AND cmd IN ('INSERT','UPDATE','DELETE')
    AND 'authenticated' = ANY(roles)
),
-- Extra: RLS enabled on critical tables
tR AS (
  SELECT 'SEC-RLS', 'RLS enabled on critical finance tables',
         string_agg(c.relname||':'||c.relrowsecurity::text, ',') AS evidence,
         CASE WHEN bool_and(c.relrowsecurity) THEN 'PASS' ELSE 'FAIL' END AS status
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public'
    AND c.relname IN ('wallet_ledger','audit_logs','recharge_requests','recharge_receipts',
                      'payment_webhooks','transaction_message_outbox','wallets')
)
SELECT * FROM t1 UNION ALL SELECT * FROM t2 UNION ALL SELECT * FROM t3
UNION ALL SELECT * FROM t4 UNION ALL SELECT * FROM t5
UNION ALL SELECT * FROM t13 UNION ALL SELECT * FROM t14
UNION ALL SELECT * FROM t15 UNION ALL SELECT * FROM t16
UNION ALL SELECT * FROM t17 UNION ALL SELECT * FROM t19
UNION ALL SELECT * FROM tR
ORDER BY 1;
