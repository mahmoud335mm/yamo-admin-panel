# Wallet Reconciliation Report — Phase 5B.5

**Date:** 2026-07-18
**Batch:** `legacy_seed_reconciliation_2026_07_18`
**Migration:** `reconcile_legacy_wallet_opening_balances`

---

## 1. Purpose

Bring `wallets.balance` back into equality with `Σ wallet_ledger` for every wallet, without mutating any existing ledger row and without changing any wallet balance. Each mismatched wallet receives exactly one synthetic opening-balance ledger entry that documents the pre-5B seed state.

**Guarantees:**

1. No wallet balance is modified.
2. No existing ledger entry is modified or deleted.
3. Each reconciliation entry uses a deterministic idempotency key — re-running is a no-op.
4. All entries share a single `reconciliation_batch_id` for auditability.
5. Every wallet in the database is scanned, not only the six known cases.
6. A dry-run block (returns a preview table) runs before any insert.

---

## 2. Dry-Run — Pre-Migration Snapshot

Query executed 2026-07-18 against sandbox DB:

```sql
SELECT w.id AS wallet_id, w.user_id, w.account AS currency_type,
       w.balance AS current_balance,
       COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0) AS ledger_sum,
       w.balance - COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0) AS diff
FROM wallets w LEFT JOIN wallet_ledger l ON l.wallet_id = w.id
GROUP BY w.id
HAVING w.balance <> COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0);
```

| wallet_id | user_id | currency | current_balance | ledger_sum | diff | reason | proposed action |
|---|---|---|---:|---:|---:|---|---|
| 96bc9c3b… | 3119bd63… | diamonds | 4634 | 0 | +4634 | pre-5B seed | insert 1 opening-balance credit = 4634 |
| 0c5ed197… | d83a0f53… | diamonds | 3477 | 0 | +3477 | pre-5B seed | insert 1 opening-balance credit = 3477 |
| 1effaf96… | a491e92b… | diamonds | 2260 | 0 | +2260 | pre-5B seed | insert 1 opening-balance credit = 2260 |
| 5f18a3f3… | f508691d… | diamonds | 2168 | 0 | +2168 | pre-5B seed | insert 1 opening-balance credit = 2168 |
| 74a53b90… | db15f052… | diamonds | 2066 | 0 | +2066 | pre-5B seed | insert 1 opening-balance credit = 2066 |
| eee2fd0f… | 73c46f62… | diamonds | 50 | 0 | +50 | pre-5B seed | insert 1 opening-balance credit = 50 |

**Wallets scanned:** all (full-table scan, no filter).
**Mismatched wallets:** 6.
**Coin / bonus mismatches:** 0.
**Negative-diff wallets:** 0 (would require a *debit* opening entry; none present).

---

## 3. Reconciliation Entry Schema

Each entry is inserted into `wallet_ledger` with these fields:

| field | value |
|---|---|
| `wallet_id` | mismatched wallet id |
| `user_id` | wallet owner |
| `account` | `diamonds` (matches wallet.account) |
| `direction` | `credit` (positive diff) or `debit` (negative diff) |
| `reason` | `adjustment` |
| `amount` | `|diff|` |
| `balance_after` | `wallet.balance` (unchanged) |
| `reference` | `legacy_seed_reconciliation:<batch_id>:<wallet_id>` — used as **idempotency key** (UNIQUE lookup before insert) |
| `metadata` | `{ "source": "opening_balance_reconciliation", "batch_id": "…", "note": "pre-5B seed opening balance; synthesized 2026-07-18; wallet balance was NOT altered." }` |
| `created_by` | `NULL` (system) |

`reason='adjustment'` is used because the existing `ledger_reason` enum has no dedicated `opening_balance` value, and adding an enum value inside a data migration would tie ledger schema evolution to a one-shot backfill. The metadata's `source` field carries the exact category (`opening_balance_reconciliation`) for reporting.

---

## 4. Idempotency & Safety

- Idempotency: pre-insert `SELECT 1 … WHERE reference = 'legacy_seed_reconciliation:…:<wallet_id>'` — insert is skipped if the row exists.
- Batch reference recorded in `audit_logs` (action = `wallet_reconciliation_batch`).
- Migration wrapped in a single transaction; failure rolls back all inserts, leaving state untouched.
- No `UPDATE`/`DELETE` on `wallets` or `wallet_ledger` is performed — the RESTRICTIVE deny-all policies on ledger UPDATE/DELETE remain enforced.

---

## 5. Post-Migration Verification

After the migration runs, this query MUST return zero rows:

```sql
SELECT w.id, w.balance, COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0) AS ledger_sum
FROM wallets w LEFT JOIN wallet_ledger l ON l.wallet_id = w.id
GROUP BY w.id
HAVING w.balance <> COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0);
```

**Post-migration numbers (verified 2026-07-18 by `SELECT COUNT(*)` and `audit_logs` inspection):**

| Metric | Before | After |
|---|---:|---:|
| Mismatched wallets | 6 | **0** ✅ |
| Reconciliation entries created | — | **6** |
| Entries skipped (idempotent) | — | 0 |
| Remaining unbalanced wallets | 6 | **0** ✅ |

Audit record: `audit_logs.action = 'wallet_reconciliation_batch'`, batch_id `legacy_seed_reconciliation_2026_07_18`.

Release-gate item **G-12** flips to `passed` only when the post-migration query returns 0 rows AND `wallet_reconciliation_batch` is present in `audit_logs`.
