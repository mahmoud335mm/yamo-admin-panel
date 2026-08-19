# Phase 5C-2b.2 — Refund Gateway Adapter (Prepare / Execute / Finalize)

**Status:** code complete, static tests pass. Runtime multi-user / concurrency tests remain SKIPPED (require Test Project). Release Gate rows G-11 / G-13 / G-14 unchanged.

---

## 1. Environment guard hardening

- `system_settings.allow_mock_refund_gateway` added, default `false`.
- Legacy permissive defaults flipped to safe values:
  - `enable_mock_payment_gateway` → `false`
  - `test_environment` → `false`
- New permission `system.manage_environment_flags` created (assignment out of scope for this batch).
- `assert_mock_refund_allowed(_gateway_id)` now requires **all** to be true simultaneously:
  1. `is_production = false`
  2. `test_environment = true`
  3. `enable_mock_payment_gateway = true`
  4. `allow_mock_refund_gateway = true`
  5. `gateway.provider_type = 'mock'`
  6. `gateway.mode = 'test'`
  7. `gateway.status = 'active'`
- Server-side second layer (`assertMockRuntimeEnvironment` in `gateway-resolver.server.ts`):
  1. `NODE_ENV ≠ production`
  2. `APP_ENV ≠ production`
  3. `ALLOW_MOCK_REFUND_GATEWAY = "true"`
  4. `SUPABASE_URL` not in `PROD_HOST_DENYLIST`
- Failure returns `MOCK_GATEWAY_NOT_ALLOWED` (no `is_production=false` fallback).
- `EXECUTE` on `assert_mock_refund_allowed` revoked from PUBLIC/anon.

## 2. Schema

`recharge_refunds` new columns: `provider_idempotency_key`, `execution_started_at`, `execution_owner_id`, `preflight_snapshot`, `gateway_mode`.

`recharge_refund_attempts` new columns: `execution_token_hash`, `provider_idempotency_key`, `gateway_id`, `gateway_mode`, `request_correlation_id`, `execution_owner_id`, `finalized_at`.

Unique indexes:
- `ux_rref_provider_idempotency` — `recharge_refunds(provider_idempotency_key) WHERE NOT NULL`
- `ux_rref_attempts_request_idem` — `(refund_id, idempotency_key) WHERE trigger_type='execute'`
- `ux_rref_attempts_gw_mode_provider_id` — `(gateway_id, gateway_mode, provider_refund_id) WHERE NOT NULL`

## 3. RPCs

| RPC | SECURITY | Callable by |
|---|---|---|
| `prepare_refund_gateway_execution` | DEFINER | `authenticated`, `service_role` |
| `finalize_refund_gateway_execution` | DEFINER | `service_role` only |
| `fail_refund_gateway_execution`    | DEFINER | `service_role` only |

`prepare_` enforces: `auth.uid()`, `recharge_refunds.execute`, reason ≥ 5, idempotency key ≥ 8, `FOR UPDATE` locks on refund + request, second-approval check, self-execution ban, gateway active, preflight drift → `manual_review`, deterministic provider idempotency key `refund:<reference>:gateway-refund`, atomic attempt insert, `approved → processing_gateway`. Returns `{ execution_token, attempt_id, provider_idempotency_key, snapshot }`. Idempotent replay returns existing attempt without new work.

`finalize_` verifies `execution_token_hash`, attempt is `started`, refund is `processing_gateway`. Handles four normalized results (succeeded-final / succeeded-webhook / pending / failed-final) → correct attempt+refund transitions. Idempotent replay returns without duplicate transition. `provider_refund_id` write-once via `COALESCE`. No wallet reversal here — that's the 5C-2b.3+ Webhook / retry path.

`fail_` records `timeout` or `failed` attempt, routes refund to `manual_review`, never mutates `provider_idempotency_key`, never spawns a new attempt.

## 4. Server-only adapter layer

Files (all `.server.ts` / `.functions.ts` — cannot be imported into client bundles):

- `src/lib/refunds/gateway-types.server.ts` — `RefundGatewayAdapter`, normalized result shape, `RefundGatewayError`.
- `src/lib/refunds/mock-refund-gateway.server.ts` — `MockRefundGatewayAdapter` (succeeded / failed / pending / timeout).
- `src/lib/refunds/gateway-resolver.server.ts` — strict `resolveRefundGatewayAdapter` and `assertMockRuntimeEnvironment`.
- `src/lib/refunds/execute-gateway-refund.functions.ts` — `executeGatewayRefund` server function.

Resolver rules:
- `provider_type='mock'` → guard chain, then `MockRefundGatewayAdapter`.
- Any other `provider_type` (`stripe`, `paymob`, etc.) → `REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED`.
- Unknown / missing → `REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED`.
- **No implicit fallback to mock or generic.**

`executeGatewayRefund` accepts only `{ refund_id, reason, idempotency_key }`. It rejects `amount`, `currency`, `gateway_id`, `provider_type`, `gateway_mode`, `provider_payment_id`, `provider_refund_id`, `coins_to_reverse`, `bonus_to_reverse`, `refund status`, `execution_token` from clients (schema-enforced via zod). DB lock is released before the outbound adapter call.

## 5. Mock adapter behavior (variants)

| Variant | `is_final` | `is_success` | `requires_webhook_confirmation` | Notes |
|---|---|---|---|---|
| `succeeded` | ✅ | ✅ | ❌ | Synchronous test path |
| `failed`    | ✅ | ❌ | ❌ | `safe_error_code=MOCK_DECLINED` |
| `pending`   | ❌ | ❌ | ✅ | Webhook-required path (finalized on webhook, 5C-2b.3) |
| `timeout`   | — | — | — | Throws `GATEWAY_TIMEOUT_UNKNOWN_RESULT` |

`provider_refund_id` derived from SHA-256 of the provider idempotency key (deterministic across retries). Adapter refuses `gateway_mode='live'`.

## 6. Static tests

`tests/unit/mock-refund-gateway.test.ts` — **11 / 11 passed**:

1. succeeded variant → final success, no webhook
2. failed variant → final failure
3. pending variant → non-final + requires webhook
4. timeout variant → throws `GATEWAY_TIMEOUT_UNKNOWN_RESULT`
5. same provider idempotency key → same `provider_refund_id`
6. live mode rejected with `MOCK_GATEWAY_NOT_ALLOWED`
7. env guard rejects `NODE_ENV=production`
8. env guard rejects missing `ALLOW_MOCK_REFUND_GATEWAY`
9. env guard passes with correct env
10. resolver never falls back to mock for unknown providers
11. resolver returns explicit `REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED`

`tests/unit/redact.test.ts` — **8 / 8 passed** (regression).

## 7. SQL / permission verifications

- `prepare_refund_gateway_execution`: `EXECUTE` → `authenticated`, `service_role`; revoked from `PUBLIC`, `anon`.
- `finalize_refund_gateway_execution`: `EXECUTE` → `service_role` only; revoked from `PUBLIC`, `anon`, `authenticated`.
- `fail_refund_gateway_execution`: same as finalize.
- Migration linter output: 184 pre-existing WARNs, **0 new** WARN attributable to these three functions.

## 8. Type check / lint / build / secret scan

| Check | Result |
|---|---|
| `tsgo --noEmit` | pass — 0 errors in `src/lib/refunds/**` |
| Unit tests | pass — 19 / 19 (mock + redact) |
| Secret scan for adapter files | pass — no API keys / bearer tokens / webhook secrets returned or logged |
| Client bundle leak scan | pass — all files use `.server.ts` / `.functions.ts` extensions; `client.server` imported only via dynamic `await import()` inside handler |

## 9. Runtime tests — SKIPPED (Test Project required)

Blocked on provisioning a dedicated Test Project with `ALLOW_MOCK_REFUND_GATEWAY=true`, `TEST_ENVIRONMENT=true`, `SUPABASE_SERVICE_ROLE_KEY`, and admin/reviewer/executor Auth users. Documented in `docs/testing/release-gate.md`:

- Two admins racing `executeGatewayRefund` → exactly one active attempt.
- Same idempotency key twice → idempotent replay.
- Different keys against same refund while `processing_gateway` → second rejected.
- `succeeded` variant → `gateway_confirmed`.
- `pending` variant → refund stays `processing_gateway`.
- `failed` variant → refund → `failed`.
- `timeout` variant → refund → `manual_review`, no new attempt spawned, `provider_idempotency_key` preserved.
- Finalize called twice → idempotent.
- Wrong `execution_token` → `EXECUTION_TOKEN_INVALID`.
- Stale attempt cannot finalize.
- Preflight drift during prepare → `manual_review`.

## 10. Remaining errors / follow-ups

- None blocking. Real gateway adapters (Stripe / PayMob / etc.), webhook processor, and wallet reversal after `gateway_confirmed` land in **5C-2b.3** (Refund Webhook Processor). UI (`5C-3`) not started per user directive.
- Environment flag change auditing (`system.manage_environment_flags` role assignment + trigger) queued for Phase 5C-2b.3.

## 11. Release Gate impact

Unchanged: G-11 (refund E2E), G-13 (two-eyes), G-14 (no negative balances) remain `pending` until Test Project runtime harness executes.
