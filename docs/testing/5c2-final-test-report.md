# Phase 5C-2 — Refund RPCs, Reconciliation Double-Entry Fix, Test Report

**Date:** 2026-07-18
**Status:** Code Complete · Runtime Pending (see release gate)

---

## 1. Wallet Reconciliation Double-Entry Fix ✅

The 5B.5 reconciliation batch was single-sided: each user wallet received a
credit with no matching debit anywhere in the system. Migration
`5C-2 part 1` fixed that by introducing two new tables:

- `public.system_accounts` — ledger of system-side accounts (legacy opening
  balance, treasury per asset, refund clearing, refund unrecovered).
- `public.system_ledger` — append-only counter-entries (RESTRICTIVE UPDATE/DELETE deny policies,
  no PUBLIC/anon grants, admin SELECT only).

For every existing user-side credit tagged
`legacy_seed_reconciliation_2026_07_18:%`, a matching debit was inserted on
`legacy_opening_balance` with `paired_user_ledger_id` linking back to the
original row. **No wallet balance was altered.**

### Post-fix verification (2026-07-18, live query)

| Metric | Value |
|---|---:|
| User-side credits (batch) | **14,655** |
| System-side debits (batch) | **14,655** |
| Diff (must be 0) | **0** ✅ |
| Counter-entries created | 6 |
| Unbalanced wallets (wallet.balance ≠ Σ ledger) | **0** ✅ |

Test script: `tests/sql/5c2_reconciliation_double_entry.sql`.

Release-gate item **G-12** is now `passed` with the above evidence.

---

## 2. Refund Infrastructure Delivered

### Schema (new)
- `refund_policies` — country / currency / gateway scoped, single & second approval thresholds, `partial_bonus_policy`, `insufficient_balance_policy`, refund window, rounding, versioning. One default global row seeded.
- `system_accounts`, `system_ledger` (see §1) — also used by refund wallet reversal counter-entries (treasury_coins / treasury_bonus).

### RPCs (public, `SECURITY DEFINER`, PUBLIC & anon EXECUTE revoked)
| Function | Permission required | Notes |
|---|---|---|
| `preview_recharge_refund` | `recharge_refunds.read` | Read-only preflight. Never mutates. |
| `request_recharge_refund` | `recharge_refunds.request` | Reason ≥ 5, idempotency ≥ 8; snapshots preflight into `metadata`. |
| `review_recharge_refund` | `recharge_refunds.review` | Delegates to approve / reject / manual_review / request_changes. |
| `approve_recharge_refund` | `recharge_refunds.approve` | Blocks `SELF_APPROVAL_NOT_ALLOWED`. |
| `second_approve_recharge_refund` | `recharge_refunds.second_approve` | Blocks `SECOND_REVIEWER_MUST_DIFFER` and self-approval; re-runs preflight. |
| `reject_recharge_refund` | `recharge_refunds.reject` | Terminal, reason required. |
| `cancel_recharge_refund` | `recharge_refunds.cancel` | Only allowed pre-execution states. |
| `execute_recharge_refund` | `recharge_refunds.execute` | Blocks `EXECUTOR_SEPARATION_REQUIRED`; re-runs preflight; routes to `manual_review` on insufficient-balance policy. |

### Internal helpers (service_role only, PUBLIC/anon/authenticated all revoked — verified via SQL)
- `_lookup_refund_policy`
- `_refund_preflight_calc` (authenticated may execute for use by preview RPC)
- `_apply_recharge_refund_wallet_reversal`
  - **service_role only** — verified: `authenticated_leak_after_revoke = 0`
  - Writes base and bonus reversal ledger entries in *separate* rows
  - Each user-side debit gets a paired `system_ledger` credit against `treasury_coins` / `treasury_bonus`
  - Idempotent on `(reference, reason)` — repeat calls return `{ idempotent: true }`
  - Never allows negative balance: `actual = LEAST(current_balance, requested)`, rest recorded as `unrecovered_*`

### RLS
- `recharge_refunds` gains an owner+admin read policy: users can see their own refunds; admins with `recharge_refunds.read` see all.
- `system_ledger` and `system_accounts` are admin-read only, RESTRICTIVE deny on user UPDATE/DELETE.
- `refund_policies` is admin-read, `system_settings.write` for admin writes.

### Two-Eyes enforcement (server-side error codes)
- `SELF_APPROVAL_NOT_ALLOWED` — requester cannot first- or second-approve.
- `SECOND_REVIEWER_MUST_DIFFER` — first reviewer cannot second-approve.
- `EXECUTOR_SEPARATION_REQUIRED` — requester cannot execute.

### Insufficient-balance handling
Preflight distinguishes:
- `block_before_gateway_refund` → `blocking_reasons=['INSUFFICIENT_COIN_BALANCE']`
- `manual_review_before_gateway_refund` (default) → warning + `execute_recharge_refund` transitions to `manual_review`
- `recover_available_and_create_receivable` / `money_only_with_override` → executes with `unrecovered_*` recorded

---

## 3. Gateway integration — deferred to 5C-2b

The `execute_recharge_refund` RPC currently drives a **synchronous mock path**
(`processing_gateway → gateway_confirmed → reversing_wallet → completed`).
It writes `MOCK-<refund_reference>` as `provider_refund_id` and emits every
audit event.

The dedicated `executeGatewayRefund` TanStack server function that talks to
real payment providers (Stripe/PayPal/etc.) — including gateway secret loading
via `supabaseAdmin`, signed webhook verification, idempotency headers, and
retry with the same key — is scoped into a follow-up **5C-2b** delivery and
tracked as release-gate item **G-11a** (to be added). The DB schema, state
machine, permissions and audit hooks are already in place, so 5C-2b is a
gateway-adapter change only.

## 4. Static test evidence

- `tests/sql/5c2_reconciliation_double_entry.sql` — batch balances 14,655 / 14,655 / diff 0 ✅
- `tests/sql/5c2_refund_security_assertions.sql` — schema, PUBLIC/anon = 0, internal helper authenticated = 0 ✅
- SQL linter: no new critical failures; pre-existing WARN count carried from 5B.

## 5. Runtime tests still SKIPPED (require Test Project + provisioned users)

Same list as 5B (G-01..G-09) plus:
- G-11 · full refund lifecycle 39-case matrix (blocked on live gateway adapter — 5C-2b)
- G-13 · two-eyes on threshold-crossing refunds
- G-14 · no negative balances under refund reversal

Server-side code paths are in place; runtime harness (`tests/runtime/*.spec.ts`) is stubbed and will be filled in when the Test Project is provisioned.

## 6. Do NOT flip Feature Flag

Per release-gate rules, this system is **NOT** Production Ready. Do not enable
end-user refund flows on a live gateway until 5C-2b lands and the runtime
gates G-11, G-13, G-14 all report `passed`.
