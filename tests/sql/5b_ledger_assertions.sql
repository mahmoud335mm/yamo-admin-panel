-- 5B Ledger Assertions
WITH
-- L1. Per-wallet: last balance_after matches computed running sum (integrity of ledger)
per_wallet AS (
  SELECT wallet_id,
         SUM(CASE WHEN direction='credit' THEN amount ELSE -amount END) AS computed
  FROM public.wallet_ledger
  GROUP BY wallet_id
),
l1 AS (
  SELECT 'LDG-001' AS id,
         'Wallet balances match ledger sums' AS name,
         COUNT(*) FILTER (WHERE w.balance <> COALESCE(pw.computed,0))::text AS evidence,
         CASE WHEN COUNT(*) FILTER (WHERE w.balance <> COALESCE(pw.computed,0))=0
              THEN 'PASS' ELSE 'FAIL' END AS status
  FROM public.wallets w
  LEFT JOIN per_wallet pw ON pw.wallet_id = w.id
),
-- L2. No wallet has negative balance
l2 AS (
  SELECT 'LDG-002', 'No negative balances',
         COUNT(*)::text,
         CASE WHEN COUNT(*)=0 THEN 'PASS' ELSE 'FAIL' END
  FROM public.wallets WHERE balance < 0
),
-- L3. Ledger amount always positive (constraint present)
l3 AS (
  SELECT 'LDG-003', 'wallet_ledger.amount > 0 constraint present',
         CASE WHEN EXISTS(
           SELECT 1 FROM pg_constraint
           WHERE conname='wallet_ledger_amount_check'
         ) THEN 'present' ELSE 'missing' END,
         CASE WHEN EXISTS(
           SELECT 1 FROM pg_constraint
           WHERE conname='wallet_ledger_amount_check'
         ) THEN 'PASS' ELSE 'FAIL' END
),
-- L4. Every completed recharge request has ledger entries referencing it
l4 AS (
  SELECT 'LDG-004', 'Completed recharge requests reflected in ledger',
         COUNT(*)::text,
         CASE WHEN COUNT(*)=0 THEN 'PASS' ELSE 'FAIL' END
  FROM public.recharge_requests r
  WHERE r.status = 'completed'
    AND NOT EXISTS (
      SELECT 1 FROM public.wallet_ledger l
      WHERE l.user_id = r.user_id
        AND (l.reference = r.id::text OR l.metadata->>'recharge_request_id' = r.id::text)
    )
),
-- L5. verify_recharge_payment enforces UNTRUSTED_VERIFICATION_SOURCE
l5 AS (
  SELECT 'LDG-005', 'verify_recharge_payment guards UNTRUSTED_VERIFICATION_SOURCE',
         CASE WHEN definition LIKE '%UNTRUSTED_VERIFICATION_SOURCE%' THEN 'guard-present' ELSE 'missing' END,
         CASE WHEN definition LIKE '%UNTRUSTED_VERIFICATION_SOURCE%' THEN 'PASS' ELSE 'FAIL' END
  FROM (
    SELECT pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='verify_recharge_payment' LIMIT 1
  ) x
),
-- L6. complete_recharge_request enforces reason>=5 chars
l6 AS (
  SELECT 'LDG-006', 'complete_recharge_request enforces permission guard',
         CASE WHEN definition ~* '_require_perm|has_permission' THEN 'guard-present' ELSE 'missing' END,
         CASE WHEN definition ~* '_require_perm|has_permission' THEN 'PASS' ELSE 'FAIL' END
  FROM (
    SELECT pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='complete_recharge_request' LIMIT 1
  ) x
),
-- L7. retry_payment_webhook requires permission (has_permission call inside body)
l7 AS (
  SELECT 'LDG-007', 'retry_payment_webhook enforces permission',
         CASE WHEN bool_and(definition ~* 'has_permission|_require_perm') THEN 'guard-present' ELSE 'missing' END,
         CASE WHEN bool_and(definition ~* 'has_permission|_require_perm') THEN 'PASS' ELSE 'FAIL' END
  FROM (
    SELECT pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='retry_payment_webhook'
  ) x
),
-- L8. review_recharge_receipt enforces permission + reason
l8 AS (
  SELECT 'LDG-008', 'review_recharge_receipt enforces permission & reason',
         CASE WHEN definition ~* '_require_perm|has_permission' THEN 'guard-present' ELSE 'missing' END,
         CASE WHEN definition ~* '_require_perm|has_permission' THEN 'PASS' ELSE 'FAIL' END
  FROM (
    SELECT pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='review_recharge_receipt' LIMIT 1
  ) x
)
SELECT * FROM l1 UNION ALL SELECT * FROM l2 UNION ALL SELECT * FROM l3
UNION ALL SELECT * FROM l4 UNION ALL SELECT * FROM l5 UNION ALL SELECT * FROM l6
UNION ALL SELECT * FROM l7 UNION ALL SELECT * FROM l8
ORDER BY 1;
