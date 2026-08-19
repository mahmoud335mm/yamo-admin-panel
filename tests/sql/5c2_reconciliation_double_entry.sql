-- 5C-2 · Reconciliation double-entry assertion.
-- Runs read-only. Expects: user_credits = system_debits, diff = 0, unbalanced_wallets = 0.

WITH user_side AS (
  SELECT COALESCE(SUM(CASE WHEN direction='credit' THEN amount::numeric ELSE -amount::numeric END),0) AS user_sum
  FROM public.wallet_ledger
  WHERE reference LIKE 'legacy_seed_reconciliation_2026_07_18:%'
),
sys_side AS (
  SELECT COALESCE(SUM(CASE WHEN direction='debit' THEN amount ELSE -amount END),0) AS sys_sum
  FROM public.system_ledger
  WHERE batch_reference = 'legacy_seed_reconciliation_2026_07_18'
),
unbalanced AS (
  SELECT COUNT(*) AS cnt FROM (
    SELECT w.id
    FROM wallets w LEFT JOIN wallet_ledger l ON l.wallet_id = w.id
    GROUP BY w.id, w.balance
    HAVING w.balance <> COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0)
  ) t
)
SELECT
  (SELECT user_sum FROM user_side)                            AS user_credits,
  (SELECT sys_sum  FROM sys_side)                             AS system_debits,
  (SELECT user_sum FROM user_side) - (SELECT sys_sum FROM sys_side) AS diff_must_be_zero,
  (SELECT COUNT(*) FROM public.system_ledger
     WHERE batch_reference='legacy_seed_reconciliation_2026_07_18') AS counter_entry_count,
  (SELECT cnt FROM unbalanced)                                AS unbalanced_wallets_must_be_zero;
