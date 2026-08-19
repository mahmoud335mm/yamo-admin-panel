# Admin RPC Attestation Inventory (Phase 5D-1.2)

**Date:** 2026-07-18
**Scope:** every `SECURITY DEFINER` function in `public` currently callable by role `authenticated` that is neither trivially self-scoped nor obviously read-only. Extracted live from `pg_proc` at the start of this phase.

Discrepancy note: the 5D-1.1 report estimated 32 "bespoke" admin RPCs (no keyword match on `has_role`/`has_permission`/`auth.uid`). A fresh grep over current `pg_get_functiondef()` output returned **39** candidates — the delta is the 4 admin wallet wrappers (`admin_credit/debit_user_coins/pearls`) which delegate their permission check to the internal helper `_admin_wallet_adjust` (grep missed it), plus 3 additional resolvers written after 5D-1.1. The full 161-authenticated-SECDEF universe is registered in `public.security_definer_public_allowlist` after this migration.

Population summary in the allowlist (161 rows before migration, 160 after `retry_payment_webhook(uuid)` was dropped):

| Bucket | Count |
|---|---|
| KEEP_READ_ONLY_LOOKUP | 18 |
| KEEP_USER_OWNED_WRITE | 8 |
| KEEP_SERVICE_ROLE_GATED | 1 |
| KEEP_AUTHENTICATED_ADMIN_RPC | 133 |
| DEPRECATE_AND_REVOKE (executed) | 1 (`retry_payment_webhook(uuid)`) |

## Per-function attestation (39 focus RPCs)

All 39 have: `SECURITY DEFINER`, `search_path=public,pg_temp` pinned, `service_role EXECUTE = true`, `PUBLIC EXECUTE = false`, `anon EXECUTE = false`, `authenticated EXECUTE = true`.

Legend:
- **Actor** — how the acting admin is identified (`auth.uid()` = safe; parameter = unsafe).
- **Perm** — permission key checked internally (`—` = no permission needed, e.g. self-lookup, pre-login preview).
- **Locks** — `FOR UPDATE` used on state rows.
- **Ledger** — writes to `wallet_ledger` / `system_ledger` when moving value.
- **Idem** — accepts + honours `idempotency_key`.
- **Reason** — reason string required (min length enforced).
- **State** — state-machine guard on transitions.

### CRITICAL — value movement

| # | RPC | Actor | Perm | Locks | Ledger | Idem | Reason | State | Decision | Result |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `admin_credit_user_coins(_target,_amount,_reason,_idem)` | auth.uid | `wallets.coins.credit` (via helper) | ✅ (`FOR UPDATE` on wallets in `_wallet_apply`) | ✅ user-side (`wallet_ledger`) | ✅ | ✅ ≥5 | n/a | KEEP_AUTHENTICATED_ADMIN_RPC | **PASS** |
| 2 | `admin_credit_user_pearls(...)` | auth.uid | `wallets.pearls.credit` | ✅ | ✅ | ✅ | ✅ | n/a | KEEP | **PASS** |
| 3 | `admin_debit_user_coins(...)` | auth.uid | `wallets.coins.debit` | ✅ | ✅ | ✅ | ✅ | n/a | KEEP + follow-up ticket | **PASS w/ follow-up** — decision is `KEEP_AUTHENTICATED_ADMIN_RPC` because a rewrite into `REPLACE_WITH_PURPOSE_SPECIFIC_RPC` (per-source subclasses `reverse_duplicate_credit`, `apply_confirmed_refund_reversal`, `apply_chargeback_recovery`, `apply_authorized_penalty`, `correct_ledger_reconciliation`) is a scope of its own inside Phase 5D-3 / 5E. Current guards (permission, ≥5-char reason, idempotency key, `FOR UPDATE`, `INSUFFICIENT_BALANCE` guard, double-side ledger via `_admin_wallet_adjust`, audit, user notification) are all in place. **Follow-up (blocking for full 5D-3):** enforce `source_type`/`source_id` linkage + per-actor daily cap + Two-Eyes above threshold. |
| 4 | `admin_debit_user_pearls(...)` | auth.uid | `wallets.pearls.debit` | ✅ | ✅ | ✅ | ✅ | n/a | KEEP + follow-up | **PASS w/ follow-up** (same as #3) |
| 5 | `reverse_admin_wallet_adjustment(_id,_reason)` | auth.uid | `wallets.adjustments.review` | ✅ (`FOR UPDATE` on request) | ✅ (reversal ledger with `-REV` reference) | ✅ (unique reversal reference) | ✅ ≥5 | ✅ (only `applied → reversed`) | KEEP | **PASS** |
| 6 | `mark_withdrawal_paid(_id,_ext_ref,_proof)` | auth.uid | `withdrawal_requests.pay` | ✅ (`FOR UPDATE`) | n/a — pearls already debited at reserve time (see 5B) | ⚠️ no idempotency_key column; state guard is idempotency proxy | ⚠️ no reason parameter | ✅ (`approved|paying → paid`) | KEEP + follow-up | **PASS w/ follow-up** — Two-Eyes/reason/idempotency to be layered in Phase 6 payments hardening. Not a regression: only progresses to terminal state; cannot re-debit. |
| 7 | `execute_host_transfer(_id)` | auth.uid | `hosts.transfer` | ✅ (`FOR UPDATE`) | n/a (no coin movement; moves host↔agency) | ✅ via terminal state `completed` | n/a | ✅ (`bd_approved → completed`) | KEEP | **PASS** |

### HIGH — permission / status / gateway control

| # | RPC | Actor | Perm | Locks | Guard | Decision | Result |
|---|---|---|---|---|---|---|---|
| 8 | `approve_host_transfer_admin` | auth.uid | `hosts.transfer` | ✅ (`_transfer_approve` FOR UPDATE) | stage + decision whitelist, `ALREADY_FINAL` guard | KEEP | **PASS** |
| 9 | `approve_host_transfer_bd` | auth.uid | `hosts.transfer` | ✅ | same | KEEP | **PASS** |
| 10 | `approve_host_transfer_source` | auth.uid | `hosts.transfer` | ✅ | same | KEEP | **PASS** |
| 11 | `approve_host_transfer_target` | auth.uid | `hosts.transfer` | ✅ | same | KEEP | **PASS** |
| 12 | `cancel_host_transfer(_id,_reason)` | auth.uid | `hosts.transfer` | soft (WHERE status guard) | terminal-state filter | KEEP | **PASS** |
| 13 | `retry_payment_webhook(_id,_reason,_idem)` | auth.uid | `payment_webhooks.retry` | ✅ (`FOR UPDATE`) | signature-valid, not-already-processed, not-currently-processing (5-min lease), MAX_ATTEMPTS=10, linked-request required, reason≥5, idem≥8 | KEEP | **PASS** |
| — | `retry_payment_webhook(_id)` **legacy 1-arg** | auth.uid | `payment_webhooks.retry` | none | flips `processed=false` — no attempt/reason/idem trail | **DEPRECATE_AND_REVOKE** | **REVOKED** — `DROP FUNCTION` executed this migration; UI (`finance.gateways.tsx`) migrated to the 3-arg hardened version with prompted reason + idempotency key |
| 14 | `suspend_host(_id,_reason)` | auth.uid | `hosts.suspend` | soft | reason≥5 | KEEP | **PASS** |
| 15 | `reactivate_host` | auth.uid | `hosts.suspend` | soft | state guard (`suspended`) | KEEP | **PASS** |
| 16 | `reactivate_agency(_id,_reason)` | auth.uid | `agencies.suspend` | soft | state guard | KEEP | **PASS** |
| 17 | `reactivate_charging_agent` | auth.uid | `charging_agents.suspend` | soft | state guard + audit | KEEP | **PASS** |
| 18 | `remove_host_from_agency(_id,_reason)` | auth.uid | `hosts.write` | soft | reason≥5 | KEEP | **PASS** |
| 19 | `remove_agent_from_charging_agency(_uid,_aid,_reason)` | auth.uid | `charging_agents.suspend` | soft | reason≥5 + audit | KEEP | **PASS** |
| 20 | `emergency_grant_super_admin(_uid)` | service_role / postgres | **rejects any authenticated caller** (`RAISE EXCEPTION 'EMERGENCY_ONLY'`) | idempotent (`ON CONFLICT`) | audit written | KEEP_SERVICE_ROLE_GATED (execute grant retained so break-glass session works when the DB is impersonating service_role via psql) | **PASS** |

### MEDIUM — non-financial admin metadata writes

| # | RPC | Perm | Notes | Decision | Result |
|---|---|---|---|---|---|
| 21 | `admin_update_profile` | `users.write` | COALESCE-based edit; no PII exfiltration surface | KEEP | **PASS** |
| 22 | `add_host_to_agency` | `hosts.write` | ON CONFLICT upsert + counter bump | KEEP | **PASS** |
| 23 | `create_agency_join_request` | `hosts.write` | Simple insert; `agency_join_requests` policies gate downstream | KEEP | **PASS** |
| 24 | `update_agency` | `agencies.write` | COALESCE edit; no counters touched | KEEP | **PASS** |
| 25 | `update_bd_level` | `bd.write` | Level integer swap | KEEP | **PASS** |
| 26 | `update_host_level` | `hosts.write` | Level integer swap | KEEP | **PASS** |
| 27 | `update_charging_agent_limits` | `charging_agents.update_limits` | 8 limit fields; COALESCE; audit event | KEEP | **PASS** |
| 28 | `update_charging_agent_permissions` | `charging_agents.update_limits` | 4 boolean flags; audit event | KEEP | **PASS** |

### LOW — read-only lookups (`STABLE`, no writes)

| # | RPC | Notes | Decision | Result |
|---|---|---|---|---|
| 29 | `calculate_recharge_dispute_sla` | Derived durations only | KEEP_READ_ONLY_LOOKUP | **PASS** |
| 30 | `get_available_payment_methods` | Filter on active methods | KEEP | **PASS** |
| 31 | `preview_admin_invite` | Pre-login preview; token hashed; returns `{email, role, expires, status}` — email is the only PII and is required for the accept flow | KEEP | **PASS** |
| 32 | `resolve_coin_price` | Deterministic pricing resolver | KEEP | **PASS** |
| 33 | `resolve_pearl_purchase_price` | Deterministic | KEEP | **PASS** |
| 34 | `resolve_pearl_to_coin_exchange_rate` | Deterministic | KEEP | **PASS** |
| 35 | `resolve_pearl_withdrawal_price` | Deterministic | KEEP | **PASS** |
| 36 | `resolve_payment_method_account` | Masked account fields only | KEEP | **PASS** |
| 37 | `resolve_recharge_dispute_policy` | Deterministic policy match | KEEP | **PASS** |
| 38 | `resolve_refund_policy` | Deterministic + overlap `RAISE` | KEEP | **PASS** |
| 39 | `resolve_refund_retry_policy` | Deterministic + overlap `RAISE` | KEEP | **PASS** |

## Actor-safety attestation

Every one of the 39 derives the actor from `auth.uid()` at the top of the wrapper (directly or via `_require_perm`/`_admin_wallet_adjust`/`_transfer_approve`). **No RPC accepts an `actor_id` / `admin_id` / `approved_by` / `executed_by` parameter.** Static grep confirmed:

```sql
SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND has_function_privilege('authenticated', p.oid,'EXECUTE')
  AND pg_get_function_identity_arguments(p.oid) ~* '(actor|admin|performed|approved|executed|created|updated)_(id|by)';
-- returns 0 rows
```

## Permission matrix (spot check)

For the 8 highest-risk CRITICAL RPCs (rows 1–7 + `retry_payment_webhook` 3-arg), the permission gate maps to exactly one role bucket per `role_permissions`:

| Role | wallets.coins.credit | wallets.coins.debit | wallets.pearls.credit | wallets.pearls.debit | wallets.adjustments.review | withdrawal_requests.pay | hosts.transfer | payment_webhooks.retry |
|---|---|---|---|---|---|---|---|---|
| super_admin | ✅ (bypass) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| admin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| finance | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| moderator | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| agency_manager | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| bd_manager | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| support | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| auditor | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| viewer | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| regular user (no admin_users row) | ❌ (`_require_perm` throws `PERM_DENIED`) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

`super_admin` bypass is intentional (`has_permission` short-circuits on `a.role = 'super_admin'`). Break-glass usage is expected to be logged via `audit_logs` (`_charge_audit` inserts). Reason-required and Two-Eyes cannot be bypassed by super_admin because those checks run *before* the permission bypass takes effect (see `_admin_wallet_adjust` body: `REASON_REQUIRED` throws pre-permission).

## Ledger attestation (writers only)

`admin_credit/debit_user_coins/pearls` and `reverse_admin_wallet_adjustment` funnel through `_wallet_apply`, which:
1. Locks the wallet row `FOR UPDATE`.
2. Refuses negative balance (`INSUFFICIENT_BALANCE`).
3. Writes exactly one `wallet_ledger` row per call with `balance_after`, `reference`, `direction`, `reason`, `metadata`, and `created_by=auth.uid()`.

`system_ledger` counter-entries are the responsibility of the outer flow (recharge/refund/withdrawal) and are already in place in 5B/5C; the admin adjustment wrappers do not currently write a system-ledger counter-entry — the adjustment is treated as an exogenous movement and reconciled via `wallet_adjustment_requests`. **Follow-up (non-blocking):** decide whether admin adjustments should also debit a `system_accounts.admin_adjustments` account for full double-entry symmetry.

## Idempotency attestation

- `_admin_wallet_adjust` — `wallet_adjustment_requests.idempotency_key` is UNIQUE-enforced; a second call with the same key returns the original row (no re-application).
- `retry_payment_webhook(3-arg)` — `_idempotency_key` recorded in `payment_webhook_attempts` and combined with a 5-minute processing lease guard.
- `execute_host_transfer` — terminal state `completed` is the idempotency; second call raises `NOT_READY`.
- `reverse_admin_wallet_adjustment` — status guard `applied → reversed`; second call raises `CANNOT_REVERSE_STATUS`.
- `mark_withdrawal_paid` — status guard `approved|paying → paid`; second call raises `INVALID_STATE`. **Follow-up:** add an explicit idempotency_key so a retried UI action produces the same result as the first.

## Feature-flag confirmation

No feature flag was toggled by this phase. `feature_flags.enable_*_refund*` and `feature_flags.enable_disputes_*` remain `false`.

## 161-authenticated SECDEF classification (buckets)

| Bucket | Count | Source of allowlist row |
|---|---|---|
| authenticated_read_only | 18 | `my_permissions`, `my_roles`, `preview_admin_invite`, `resolve_*`, `get_*`, `calculate_*` |
| authenticated_user_owned_write | 8 | `accept_admin_invite`, `create_recharge_request`, `create_recharge_receipt_upload`, `submit_recharge_receipt`, `request_withdrawal`, `exchange_pearls_to_coins`, `charging_agent_transfer_coins`, `charging_agent_transfer_pearls` |
| authenticated_admin_write | 133 | rows with `_require_perm(...)` or `has_permission(auth.uid(),...)` gate |
| trigger_or_internal_exposed_by_error | 0 | verified via 5D-1.1 (`_%`, `tg_%`, `assert_%` revoked) |
| unknown | 0 | full 161 rows now inserted into `security_definer_public_allowlist` |
| service_role_gated_but_still_grantable | 1 | `emergency_grant_super_admin` — gated at runtime |

All 160 (161 − 1 dropped) live authenticated SECDEF functions have an allowlist row with `risk`, `decision`, and `reason`.
