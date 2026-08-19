# Phase 5C-2b.4 — Refund Status Refresh, Retry, Polling, Race Protection

**Status:** Gateway Layer Code Complete (Static + Mock PASS; DB-runtime matrix stays SKIPPED per Release Gate)
**Date:** 2026-07-18

> Not "Production Ready", not "Runtime Verified", not "Live Gateway Verified".
> Runtime concurrency and live-gateway checks require a Test Project (G-01/G-05/G-15/G-16).

---

## 1. Refresh Status Architecture

`refreshRefundStatus` (TanStack Server Function, `src/lib/refunds/refresh-refund-status.functions.ts`)
does **not** create a refund. It queries an existing one.

Client inputs (only): `refund_id`, `reason (≥5)`, `idempotency_key (≥8)`.
Server refuses: `amount`, `currency`, `provider_refund_id`, `gateway_id`, `gateway_mode`.

Flow: `has_permission(recharge_refunds.refresh_status)` → `claim_refund_status_refresh`
(60-second lease) → `prepare_refund_status_refresh` (inserts `refresh_status`
attempt with hashed execution token) → resolve adapter (no fallback) →
`adapter.getRefundStatus` **outside DB locks** → `finalize_refund_status_refresh`
(snapshot check + status decision) → `release_refund_status_refresh` in
`finally`. On `gateway_confirmed`, the canonical `process_confirmed_recharge_refund`
orchestrator runs.

## 2. Retry Architecture

`retryGatewayRefund` (`src/lib/refunds/retry-gateway-refund.functions.ts`) reuses the
same `provider_idempotency_key` stored on the refund row — never a new one.
Client cannot supply amount/currency/mode/provider IDs.

Flow: dual permission gate (`recharge_refunds.retry_gateway` + optional
`override_retry_limit`) → `prepare_refund_retry` (eligibility, backoff, limit) →
`prepare_refund_gateway_execution` (existing 5C-2b.2 pipeline; **hard equality
check** on `provider_idempotency_key`, `PROVIDER_IDEMPOTENCY_MISMATCH` otherwise)
→ adapter → `finalize_refund_gateway_execution` /
`fail_refund_gateway_execution`. Timeout / unknown result → **never** auto-retries;
route requires `refreshRefundStatus` next.

## 3. Unknown-Result Policy

`gateway_execution_state = unknown_result` blocks retry with
`REFUND_STATUS_REFRESH_REQUIRED`. Only `refreshRefundStatus` can advance the
state, either to `gateway_confirmed`, `manual_review` (final failure / cancel),
or reschedule the next poll.

## 4. Polling Claim / Lease

Columns added to `recharge_refunds`: `polling_owner`, `polling_started_at`,
`polling_lease_expires_at`, `last_status_checked_at`, `next_status_check_at`,
`status_refresh_count`, `retry_attempt_count`, `last_retry_at`,
`gateway_execution_state`. `claim_refund_status_refresh` returns
`REFUND_STATUS_CHECK_ALREADY_RUNNING` when a live lease exists;
`reclaim_stale_refund_status_checks` frees expired leases in batches.

## 5. Retry Policy

`refund_retry_policies` — one active row per scope (global / gateway /
mode / gateway+mode), enforced by four partial unique indexes. Fields:
`max_create_attempts`, `max_status_refresh_attempts`, `initial_backoff_seconds`,
`max_backoff_seconds`, `backoff_multiplier`, `jitter_percent`,
`polling_interval_seconds`, `unknown_result_timeout_minutes`,
`stale_processing_timeout_minutes`, `move_to_manual_review_after`. Read allowed
via `recharge_refunds.read`; management restricted to `super_admin`. Client
cannot override any of these values.

## 6. Backoff + Jitter

`prepare_refund_retry` computes `backoff = min(max, initial × multiplier^(n-1))`
and rejects with `RETRY_BACKOFF_ACTIVE` when `now < last_retry_at + backoff`.
Jitter is applied at scheduling time via the policy field (worker-side).

## 7. Worker Contract

Poll query: `status = 'processing_gateway' AND next_status_check_at <= now()
AND polling_owner IS NULL AND provider_refund_id IS NOT NULL`. Worker MUST
`claim_refund_status_refresh` first, hold no DB locks during adapter call,
and always `release_refund_status_refresh` in a `finally`. Worker is
implemented as a server-only path; no external automation deployed this phase
(Release Gate blocks production polling until Test Project + feature flag).

## 8. Webhook / Polling Race Rules

Terminal states never regress. `finalize_refund_status_refresh`:
- refuses `AMOUNT_MISMATCH`, `PROVIDER_ID_MISMATCH`, `GATEWAY_MODE_MISMATCH`
  and routes those to `manual_review`
- treats `recharge_refunds.status IN ('completed','partially_completed','failed','rejected','cancelled')`
  as terminal `no-op` — attempt closed, refund untouched
- clears polling lease + `next_status_check_at` on `gateway_confirmed` / `manual_review`
- on `pending` / `unknown`, only schedules the next poll and updates
  `gateway_execution_state = pending_confirmation | unknown_result`

## 9. Event Ordering

Priority (server-enforced): `succeeded` > `failed|cancelled (final)` > `pending`
> `unknown`. Older `failed` events cannot override a confirmed `succeeded`
because the refund row will already be in a terminal state.

## 10. Mock Status Matrix

Extended `MockRefundGatewayAdapter.getRefundStatus` (variant suffix `::variant`
in `provider_refund_id` OR deterministic hash-based classification): supports
`succeeded`, `failed`, `pending`, `unknown`, `not_found`, `wrong_amount`,
`wrong_currency`, `wrong_mode`, `timeout`. Verified in
`tests/unit/mock-refund-status-matrix.test.ts` (9/9 PASS).

## 11. Attempt History

`recharge_refund_attempts.trigger_type` now covers
`execute | retry | refresh_status | webhook`. All rows Append-Only via
restrictive `attempts_no_insert` / `attempts_no_update` / `attempts_no_delete`
policies; only service-role RPCs may write.

## 12–14. Audit / Outbox / Metrics

Reuses existing 5C-2b audit + outbox tables. New audit event codes
(surfaced via `_reason` and `failure_code`): `refund_status_refresh_started`,
`refund_status_refresh_pending`, `refund_status_refresh_succeeded`,
`refund_status_refresh_failed`, `refund_status_refresh_unknown`,
`refund_retry_requested`, `refund_retry_rejected`,
`refund_retry_limit_reached`, `refund_provider_status_conflict`. No PII, no
raw payloads, no secrets.

## 15. Permissions

Added:
- `recharge_refunds.refresh_status`
- `recharge_refunds.override_retry_limit`

Both granted to `super_admin` in seed. Distribution to `admin`, `finance
manager`, `finance reviewer`, `auditor`, `support` is configurable via
`role_permissions` — enforced server-side in the RPC and again in the server
function permission gate.

## 16–18. Tests

**SQL security assertions** — `tests/sql/5c2b4_status_retry_security_assertions.sql`:
```
NOTICE: ALL 5C-2b.4 SECURITY ASSERTIONS PASSED
```
Covers: (1) zero PUBLIC/anon/authenticated EXECUTE on the 7 new RPCs,
(2) both new permission keys present, (3) all 9 new polling columns present,
(4) all 4 partial unique indexes on `refund_retry_policies`, (5) RLS enabled +
both policies present, (6) default global policy seeded, (7) attempt-table
restrictive write policy still in force.

**Unit tests — `tests/unit/mock-refund-status-matrix.test.ts`:** 9/9 PASS.
**Full unit-test suite:** 36 PASS / 14 SKIPPED / 0 real failures. The 3 test
files reported as "failed" are `tests/runtime/*.spec.ts` refusing to run
without `TEST_ENVIRONMENT=true` — this is the documented Release Gate
skip, not a regression.

## 19. Race Tests — SKIPPED (need Test Project)

Concurrent runtime scenarios in the task list (webhook succeeded during
refresh, refresh pending after succeeded, retry vs webhook, stale reclaim
during new refresh, dual finalize, etc.) require live authenticated
users and a Test Project. State-machine invariants they exercise are
enforced by SQL guards (`finalize_refund_status_refresh`,
`prepare_refund_retry`) and remain SKIPPED per Release Gate G-15 / G-16.

## 20. Build / Secret Scan

- Client bundle scan: only `.server.ts` files reference
  `SUPABASE_SERVICE_ROLE_KEY`; every `client.server` import in
  `*.functions.ts` is behind a handler-scope `await import(...)`. Clean.
- `resolveRefundGatewayAdapter` still throws
  `REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED` for unknown providers; mock
  requires `ALLOW_MOCK_REFUND_GATEWAY=true` + non-prod env.

## 21. Release Gate Update

`docs/testing/release-gate.md` gains rows **G-15** (status refresh matrix)
and **G-16** (retry vs webhook race). Both stay `pending` because a Test
Project is required. No existing runtime gate flips to `passed` from unit
tests alone. **Do NOT use the phrases** *Production Ready* / *Runtime
Verified* / *Live Gateway Verified*.

---

## Deferred / SKIPPED

1. Live gateway adapters (real Stripe/Adyen/… integration) — future phase.
2. Automated polling worker deployment — code-complete; deployment gated
   behind feature flag + Release Gate G-15.
3. Two-eyes flow for `override_retry_limit` on large amounts — permission
   exists; UI + threshold check will land with 5C-3 UI batch.

## Next

Now proceeding to **5C-3.1** (Refunds list UI) → **5C-3.2** (detail tabs)
→ **5C-3.3** (create refund from recharge request).
