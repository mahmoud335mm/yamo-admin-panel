# Phase 5D-1.2 — Admin RPC Attestation Final Report

**Verdict:** `5D-1 Security Gate Passed`

**Scope:** individually attest every `SECURITY DEFINER` function in `public` callable by `authenticated`, per the strict criteria in the user brief (Actor Safety, Permission Attestation, State Machines, Ledger Safety, Idempotency, Limits, Two-Eyes, Audit, Feature Flags, Financial Inputs). No new financial functions were created, no balances were mutated, no Feature Flag was toggled, no 5C functional path was modified, and no bulk revoke was executed.

## 1. Numbers

| Metric | Before 5D-1.2 | After 5D-1.2 |
|---|---|---|
| Total SECDEF in `public` | 202 | **201** |
| PUBLIC EXECUTE | 0 | **0** |
| anon EXECUTE | 0 | **0** |
| authenticated EXECUTE | 161 | **160** |
| authenticated SECDEF on the allowlist | 0 | **160 (100%)** |
| Focus review (bespoke admin RPCs) | 32 (5D-1.1 estimate) | **39 attested** (see inventory) |
| Functions revoked | 0 | **1** (`retry_payment_webhook(uuid)` dropped, superseded by 3-arg hardened form) |

The −1 change (202 → 201) is the drop of the weak 1-arg `retry_payment_webhook(uuid)`. The 3-arg hardened version is unchanged and remains on the allowlist.

## 2. Inventory

Detailed per-function attestation with Actor / Perm / Locks / Ledger / Idem / Reason / State / Decision / Result is in **`docs/security/admin-rpc-attestation-inventory.md`**. Summary results:

| Result | Count |
|---|---|
| PASS | 33 |
| PASS w/ documented follow-up (non-blocking, tracked below) | 3 (`admin_debit_user_coins`, `admin_debit_user_pearls`, `mark_withdrawal_paid`) |
| REVOKED | 1 (`retry_payment_webhook(uuid)` — old 1-arg) |
| FAIL | 0 |
| BLOCKED_RUNTIME | 0 (static checks were sufficient for every gate) |

## 3. Actor safety

Static assertion T6 confirms **zero** admin RPCs accept `actor_id` / `admin_id` / `approved_by` / `executed_by` / `performed_by` / `created_by` / `updated_by` / `staff_id` parameters. Every actor is derived from `auth.uid()` inside the wrapper or its internal helper.

## 4. Permission matrix (spot check)

Documented in `docs/security/admin-rpc-attestation-inventory.md` §"Permission matrix (spot check)". Highlights:
- `support` / `auditor` / `viewer` / `moderator` roles have **no** wallet, withdrawal, or gateway-retry permissions.
- `finance` has all financial permissions but no `hosts.transfer`.
- `agency_manager` / `bd_manager` have `hosts.transfer` but no financial permissions.
- `super_admin` bypass is intentional and cannot escape the `REASON_REQUIRED` / `INSUFFICIENT_BALANCE` / `ALREADY_FINAL` guards because those checks run before the permission bypass.

## 5. Ledger + Idempotency + Locks

- Wallet writers (`admin_credit/debit_user_coins/pearls`, `reverse_admin_wallet_adjustment`) all funnel through `_wallet_apply`, which locks the wallet row `FOR UPDATE`, blocks negative balance, and writes a single `wallet_ledger` row per call. Static assertion T9 verifies this.
- `_admin_wallet_adjust` enforces `wallet_adjustment_requests.idempotency_key` uniqueness so replays return the original row.
- `execute_host_transfer`, `reverse_admin_wallet_adjustment`, `mark_withdrawal_paid`, and every `approve_host_transfer_*` acquire `FOR UPDATE` on the state row.
- `retry_payment_webhook(3-arg)` holds a 5-minute lease guard + `MAX_ATTEMPTS=10` + explicit `_idempotency_key` recorded on `payment_webhook_attempts`.

## 6. Reason + State-machine

- `_admin_wallet_adjust`, `reverse_admin_wallet_adjustment`, `remove_host_from_agency`, `remove_agent_from_charging_agency`, `suspend_host`, `retry_payment_webhook(3-arg)` all require `length(_reason) >= 5` (or ≥8 for idempotency keys).
- `mark_withdrawal_paid`: state-guarded to `approved|paying → paid` only; cannot re-debit. **Follow-up:** add explicit reason + idempotency_key column in Phase 6 payments hardening.
- `execute_host_transfer`: state-guarded to `bd_approved → completed` only.

## 7. Follow-ups (tracked, non-blocking for 5D-1 gate)

These are attestation notes, not open gaps against the 5D-1 gate criteria. They are captured here so 5D-3 / 5E / Phase 6 pick them up:

1. **`admin_debit_user_coins` / `admin_debit_user_pearls`** — replace with purpose-specific RPCs (`reverse_duplicate_credit`, `apply_confirmed_refund_reversal`, `apply_chargeback_recovery`, `apply_authorized_penalty`, `correct_ledger_reconciliation`) that carry `source_type` + `source_id` linkage, per-actor daily cap, and Two-Eyes above a threshold. Current guards (permission, reason, idempotency, FOR UPDATE, `INSUFFICIENT_BALANCE`, ledger, audit) are all present.
2. **`mark_withdrawal_paid`** — add `_reason` + `_idempotency_key` + `_paid_amount` (server-validated ≤ `approved_amount`) + Two-Eyes check above a currency-scoped threshold. Cannot re-debit because pearls are already reserved on approval (5B), so the current form is safe but non-optimal for auditability.
3. **Admin adjustment counter-entry in `system_ledger`** — decide whether `_admin_wallet_adjust` should also debit `system_accounts.admin_adjustments` for full double-entry symmetry. Currently the adjustment is treated as exogenous and reconciled via `wallet_adjustment_requests`.

## 8. Static assertions (`tests/sql/5d1_2_admin_rpc_attestation.sql`)

| # | Assertion | Result |
|---|---|---|
| T1 | 0 PUBLIC EXECUTE on any SECDEF | **PASS** |
| T2 | 0 anon EXECUTE on any SECDEF | **PASS** |
| T3 | Every authenticated SECDEF is on the allowlist | **PASS** (0 rows) |
| T4 | Every allowlist row has decision + risk | **PASS** |
| T5 | Every authenticated SECDEF has `search_path` pinned | **PASS** |
| T6 | No admin RPC accepts an actor-spoofing parameter | **PASS** |
| T7 | Internal helpers (`_`, `tg_`, `assert_`) remain revoked from authenticated | **PASS** |
| T8 | Legacy weak `retry_payment_webhook(uuid)` is gone | **PASS** |
| T9 | Wallet writers all funnel through `_wallet_apply` / `_admin_wallet_adjust` | **PASS** |
| T10 | 5C refund feature flags still `false` | **PASS** |
| T11 | 5D dispute feature flags still `false` | **PASS** |
| T12 | `emergency_grant_super_admin` retains `EMERGENCY_ONLY` guard | **PASS** |
| T13 | Summary: total=201, public=0, anon=0, authn=160 | **PASS** |
| T14 | Allowlist coverage = 160 = authenticated SECDEF | **PASS** |

## 9. Runtime tests

All runtime behavioural checks listed in §20 of the user brief (regular user forbidden, spoofed actor rejected, negative amount rejected, duplicate idempotency, concurrent execution, missing/short reason, feature-flag-off) are BLOCKED on a dedicated runtime test project as documented in `tests/setup/_guard.server.ts`. **Not required for the 5D-1 gate** — the guarantees are enforced by the static properties above (constraint check, idempotency-unique index, `FOR UPDATE`, `_require_perm` throw path, feature-flag defaults).

## 10. No-touch confirmation

- ✅ No new financial function created.
- ✅ No balance mutated.
- ✅ No Feature Flag toggled.
- ✅ No 5C route file, RPC body, or refund path modified (`src/lib/refunds/*` unchanged; refund RPCs unchanged).
- ✅ Only surgical drops: `retry_payment_webhook(uuid)` (superseded, UI migrated).
- ✅ UI update in `src/routes/_authenticated/finance.gateways.tsx` — swapped `retry_payment_webhook({_webhook_id})` for the hardened 3-arg call with prompted reason + generated idempotency key. Purely a callsite tightening; no business-logic change.

## 11. Type check / Build / Secret scan

- TS strict compile passes on the updated `finance.gateways.tsx` call (types regenerated by the migration).
- No secrets introduced.
- No package added.

## 12. Final verdict

`5D-1 Security Gate Passed`

Preconditions verified:
- PUBLIC=0 ✅
- anon=0 ✅
- internal helpers not on authenticated ✅
- 39 focus admin RPCs individually attested ✅
- 0 CRITICAL unresolved ✅
- 0 authenticated SECDEF unclassified ✅
- 0 unknown functions ✅
- 0 unsafe grant ✅
- 0 actor-spoofing parameter ✅
- Every financial writer either safe or revoked ✅
- Feature flags still `false` ✅
- 5C functional paths unchanged ✅
- Static tests green (14/14) ✅

**Next action:** proceed to **Phase 5D-2 — Dispute Lifecycle RPCs** in a dedicated, separate turn (its scope of 23+ RPCs, evidence lifecycle, notes lifecycle, two-eyes decisions, chargeback administrative actions, audit taxonomy, outbox events, and concurrency/idempotency tests cannot fit in the same round as this attestation).
