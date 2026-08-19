# Financial RPC Follow-up Register

Tracks the small set of financial RPCs that are **not** covered by 5D-2 runtime verification.
5D-2 introduces zero new callers for any of them and does not widen their permissions.

Reviewed on every phase gate.

---

## 1. `admin_debit_user_coins`

| Field | Value |
|---|---|
| Current permission | `wallet.admin_debit` (authenticated, allowlisted) |
| Current callers | `wallet-adjustments` UI wizard, `reverse_admin_wallet_adjustment` |
| Feature flag | none — permission-gated only |
| Runtime tests pending | end-to-end debit + double-entry reconciliation on a Test Project |
| Compensating controls | `_wallet_apply` locks the wallet row, blocks negative balances, writes paired `wallet_ledger` entries; requires reason ≥ 10 chars; audit log written |
| Prohibited new callers | any new 5D-* RPC, any UI outside `wallet-adjustments`, any refund/dispute lifecycle path |
| Owner | Finance Platform |
| Target phase | 6C — Wallet Runtime Verification |
| Release gate id | `RG-WALLET-DEBIT-01` |

## 2. `admin_debit_user_pearls`

| Field | Value |
|---|---|
| Current permission | `wallet.admin_debit` (authenticated, allowlisted) |
| Current callers | `wallet-adjustments` UI wizard, `reverse_admin_wallet_adjustment` |
| Feature flag | none — permission-gated only |
| Runtime tests pending | same as coins path, pearls variant |
| Compensating controls | `_wallet_apply` (pearls), audit log, reason ≥ 10 chars |
| Prohibited new callers | any 5D-* dispute/chargeback path, any refund path |
| Owner | Finance Platform |
| Target phase | 6C — Wallet Runtime Verification |
| Release gate id | `RG-WALLET-DEBIT-02` |

## 3. `mark_withdrawal_paid`

| Field | Value |
|---|---|
| Current permission | `withdrawals.mark_paid` (authenticated, allowlisted) |
| Current callers | `finance.withdrawal-requests` UI, second-reviewer flow |
| Feature flag | none — permission + Two-Eyes CHECK enforced |
| Runtime tests pending | two-eyes reviewer separation, idempotent status transition, ledger pairing under a Test Project |
| Compensating controls | Two-Eyes CHECK (`first_reviewer <> second_reviewer`), locked `withdrawal_requests` row, audit log, outbox event |
| Prohibited new callers | any 5D-* dispute path, any refund/chargeback path |
| Owner | Finance Platform |
| Target phase | 6C — Wallet Runtime Verification |
| Release gate id | `RG-WITHDRAW-PAID-01` |

---

## Rules for this register

1. No 5D-2 RPC calls any function above.
2. No 5D-2 migration or code path widens their EXECUTE grants.
3. Their feature flags (where they have any) are unchanged.
4. They remain **not** Runtime Verified — no phase report may claim otherwise.
5. Any new caller must fail static assertion `T-FIN-FOLLOWUP-NO-NEW-CALLERS` in `tests/sql/5d2_security_assertions.sql`.
6. Removing an entry requires a full runtime verification report and sign-off from the Finance Platform owner.
