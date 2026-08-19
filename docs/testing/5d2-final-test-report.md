# Phase 5D-2 — Final Test Report

**Phase:** 5D-2 — Dispute Lifecycle RPCs + Notes + Evidence + Two-Eyes Decisions
**Verdict:** ✅ **5D-2 Lifecycle Code Complete — Runtime Verification Pending**
**Date:** 2026-07-18
**Environment:** Preview / Non-production. No production data touched.

---

## 1. Scope Delivered

### Schema (idempotent, data-preserving)

- `recharge_disputes`: +19 columns (financial_resolution_status enum, exposure snapshots,
  policy_snapshot, threshold_snapshot, parent/root reopen chain, resolution_version,
  last_action_idempotency_key, decision-actor timestamps for triage/reject/cancel).
- `recharge_dispute_evidence`: +3 columns (review_reason, object_verified_at, idempotency_key),
  defaults hardened (`is_quarantined=true`, `malware_scan_status='pending'`).
- `recharge_dispute_notes`: +4 columns (idempotency_key, content_hash, redaction_hash,
  user_delivery_status).
- New enum `public.financial_resolution_status_enum` (not_required, pending, blocked, waived, completed).
- New table `public.dispute_action_idempotency` with per-actor/action/key uniqueness and
  per-dispute/action/decision-version uniqueness for two-eyes cycles.
- New permissions: `recharge_disputes.notes.redact`, `recharge_disputes.set_critical_severity`.
- New feature flags (all default `false`): `enable_disputes_admin_ui`,
  `enable_user_dispute_submission`, `enable_chargeback_processing`,
  `enable_dispute_financial_resolution`, `enable_dispute_provisional_actions`.

### RESTRICTIVE write-deny on core tables

`recharge_disputes`, `recharge_dispute_notes`, `recharge_dispute_evidence` each carry
RESTRICTIVE `FOR INSERT/UPDATE/DELETE TO authenticated USING (false) WITH CHECK (false)`
policies, so direct table writes from the client are impossible; all state changes go
through the SECDEF wrappers below.

### Internal helpers (revoked from anon/authenticated/PUBLIC)

- `_dispute_assert_actor(text)` — auth + permission gate.
- `_dispute_lock(uuid)` — `SELECT … FOR UPDATE` on the dispute row.
- `_dispute_idem_lookup / _dispute_idem_finalize` — actor-scoped idempotency with
  input-hash guard against key reuse with different inputs.
- `_dispute_write_audit / _dispute_write_outbox` — structured audit + outbox writes.
- `_dispute_snapshot_exposure(dispute, request)` — snapshots financial exposure via
  `preview_recharge_dispute_exposure`.
- `_dispute_assert_transition(current, next)` — enforces the 5D-1 status machine.
- `record_dispute_evidence_scan_result(evidence, status, ref)` — service-role-only
  hook for the malware-scan pipeline (validates scan status enum).

### Lifecycle RPCs (22, all SECDEF, `authenticated` EXECUTE only, on the allowlist)

| RPC | Permission | Notes |
| --- | --- | --- |
| `create_recharge_dispute` | `recharge_disputes.create` | Validates title/reason/summary; enforces one active dispute per (request,user,type,source); attaches policy snapshot + exposure snapshot. |
| `assign_recharge_dispute` | `recharge_disputes.assign` | Requires active admin assignee. |
| `triage_recharge_dispute` | `recharge_disputes.triage` | `critical` severity requires `set_critical_severity`. |
| `request_dispute_evidence` | `recharge_disputes.review` | Emits `user_visible` note + outbox event for user-facing requests. |
| `add_dispute_internal_note` | `recharge_disputes.notes.create_internal` | Rejects `user_visible`. |
| `add_dispute_user_visible_note` | `recharge_disputes.notes.create_user_visible` | Writes outbox for user delivery. |
| `redact_dispute_note` | `recharge_disputes.notes.redact` | Preserves row, stores `redaction_hash` of the original body, body → `[REDACTED]`. |
| `submit_dispute_evidence` | `recharge_disputes.evidence.create` | Only `uploaded → submitted`. |
| `review_dispute_evidence` | `recharge_disputes.evidence.review` | `accept` blocked unless `malware_scan_status='clean'` and not quarantined. |
| `review_recharge_dispute` | `recharge_disputes.review` | Refreshes exposure snapshot each call. |
| `escalate_recharge_dispute` | `recharge_disputes.escalate` | Enum-checked target team. |
| `first_decide_recharge_dispute` | `recharge_disputes.first_decide` | Refreshes exposure; caps `recommended_amount ≤ remaining_financial_exposure`. |
| `second_decide_recharge_dispute` | `recharge_disputes.second_decide` | Second reviewer ≠ first reviewer and ≠ opener; caps `approved_amount ≤ remaining exposure`; bumps `resolution_version`; sets `financial_resolution_status='pending'` on user_favor/partial. |
| `resolve_recharge_dispute` | `recharge_disputes.resolve` | Emits user outbox event. |
| `reject_recharge_dispute` | `recharge_disputes.review` | Requires reason ≥ 5 chars. |
| `cancel_recharge_dispute` | `recharge_disputes.review` | Only `opened / triage / awaiting_user_evidence`. |
| `close_recharge_dispute` | `recharge_disputes.close` | Blocks close while `financial_resolution_status='pending'` OR evidence pending/scan pending. |
| `reopen_recharge_dispute` | `recharge_disputes.reopen` | Creates a **new** dispute row linked via `parent_dispute_id` / `root_dispute_id`, `reopen_sequence` unique per root. |
| `acknowledge_chargeback` | `recharge_disputes.chargeback.manage` | Records-only. |
| `mark_chargeback_evidence_due` | `recharge_disputes.chargeback.manage` | Records-only. |
| `record_chargeback_recommendation` | `recharge_disputes.chargeback.manage` | Records-only. |
| `record_manual_chargeback_provider_status` | `recharge_disputes.chargeback.manage` + `recharge_disputes.read_sensitive` | Requires provider reference ≥ 3 chars + source reference; sets `provider_mode='manual'`. |

**No wallet, no ledger, no gateway, no refund executor is touched by any of these RPCs.**
Financial resolution is a status flag only; execution is deferred to 5D-3.

---

## 2. Security posture after 5D-2

| Metric | Value |
| --- | --- |
| Total SECURITY DEFINER functions in `public` | 231 |
| Callable by `PUBLIC` | **0** |
| Callable by `anon` | **0** |
| Callable by `authenticated` | 182 (all on `security_definer_public_allowlist`) |
| Dispute-related SECDEF functions | 31 (22 new lifecycle wrappers + 9 pre-existing helpers/queries) |
| Allowlist rows (`security_definer_public_allowlist`) | 182 |
| New allowlist decision | `KEEP_AUTHENTICATED_ADMIN_RPC` (risk `medium`) with 5D-2 reason string |

All 5D-2 authenticated SECDEF wrappers have:

- Pinned `search_path = public, pg_temp`.
- Explicit `auth.uid()` actor (no `_actor` / `_admin` / `_performed_by` parameters — 5D-1.2 pattern).
- Permission gate via `has_permission()` (no direct role checks in RPCs).
- Idempotency envelope (actor + action + key + input-hash) via `dispute_action_idempotency`.
- Row lock via `_dispute_lock` before any state read.
- Status-machine gate via `_dispute_assert_transition` on every status change.
- Audit + outbox writes for every terminal or user-visible action.

### Financial follow-up register

`docs/security/financial-rpc-follow-up-register.md` continues to list the 3 non-runtime-verified
financial RPCs from 5C. **5D-2 adds no new financial executors** and therefore no new
follow-ups.

---

## 3. Static SQL assertions

`tests/sql/5d2_security_assertions.sql` — 16 static checks. Executed against the live DB
via `supabase--read_query` (equivalent to running each SELECT), all pass:

| # | Assertion | Result |
| --- | --- | --- |
| T1 | 0 PUBLIC EXECUTE on any SECDEF | PASS |
| T2 | 0 anon EXECUTE on any SECDEF | PASS |
| T3 | Every authenticated SECDEF is on the allowlist | PASS |
| T4 | Every allowlist row has decision + risk | PASS |
| T5 | Every authenticated SECDEF has pinned `search_path` | PASS |
| T6 | No authenticated admin RPC accepts actor-spoofing parameters | PASS |
| T7 | Internal helpers (`_*`, `tg_*`, `assert_*`) revoked from authenticated | PASS |
| T8 | Legacy `retry_payment_webhook(uuid)` remains gone | PASS |
| T9 | Wallet writers still use `_wallet_apply` / `_admin_wallet_adjust` | PASS |
| T10 | 5C refund feature flags remain `false` | PASS |
| T11 | 5D dispute feature flags remain `false` | PASS |
| T12 | `emergency_grant_super_admin` still enforces EMERGENCY_ONLY | PASS |
| T13 | Summary counts: 231 SECDEF, 0 public, 0 anon, 182 authenticated | PASS |
| T14 | Allowlist size == authenticated SECDEF count (182 / 182) | PASS |
| T15 | RESTRICTIVE write-deny policies present on the 3 dispute tables | PASS |
| T16 | 22 new lifecycle RPCs exist and are `SECURITY DEFINER` | PASS |

---

## 4. Runtime tests

Runtime harness (`tests/setup/_guard.server.ts`) still refuses to run outside a dedicated
Test Project (`TEST_ENVIRONMENT=true` + non-production `SUPABASE_URL` + `TEST_RUN_ID`).
The following are **BLOCKED — requires dedicated Test Project + service-role secret in
CI, neither is available in this sandbox**:

- Lifecycle flow tests (opened → triage → evidence → review → first_decide → second_decide → resolve → close).
- Two-eyes separation test (first_decider ≠ second_decider ≠ opener).
- Reopen chain uniqueness under concurrency.
- Idempotency-key reuse with different input rejection.
- RLS isolation for `dispute_action_idempotency` (`SELECT` scoped to `actor_id = auth.uid()`).
- Evidence quarantine gate (accept rejected while `is_quarantined=true` or scan≠clean).
- Playwright UI flows (blocked at the framework level — flags off, no UI shipped in 5D-2).

None of these are regressions from prior phases; they are the same class of tests
skipped in 5C / 5D-1 for the same reason.

---

## 5. Feature flags

All 5 dispute flags remain `false`. Nothing in this phase enables user-facing UI or
financial execution. Enabling `enable_dispute_financial_resolution` is explicitly
deferred to 5D-3 and requires the runtime tests above to run green in a Test Project first.

---

## 6. Verdict

✅ **5D-2 Lifecycle Code Complete — Runtime Verification Pending**

- Schema, RPCs, allowlist, permissions, feature flags, RESTRICTIVE policies, idempotency,
  two-eyes separation, exposure caps, reopen chain, and chargeback administrative records
  are deployed and pass all 16 static SQL assertions.
- No financial side effects introduced. Financial follow-up register unchanged.
- Runtime + Playwright verification remains blocked on Test-Project provisioning and
  moves as-is into the 5D-3 gate.

Do **NOT** enable any dispute feature flag or start 5D-3 financial execution until
runtime tests execute green in a dedicated Test Project.
