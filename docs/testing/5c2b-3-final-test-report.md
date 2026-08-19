# Phase 5C-2b.3 · Refund Webhook Processor — Delivery Report

Status: **Code Complete / Static Tests PASS · Runtime Tests SKIPPED (no Test Project)**

## 1. Files created / modified

**Migration (schema + RPCs, single migration)**
- Extended `public.payment_webhooks` with 18 refund-domain columns
- Added 2 CHECK constraints (`event_domain`, `validation_status`)
- Added 2 indexes (`idx_webhooks_refund`, `idx_webhooks_domain_state`)
- Added RESTRICTIVE policy `pw_no_write_auth` (all writes denied to authenticated)
- Added 1 permission key `recharge_refunds.webhook.replay`
- Added 7 service-role-only RPCs (see §3)

**Server code (server-only)**
- `src/lib/refunds/verify-refund-webhook.server.ts` — signature/timestamp verification + event normalization (9 types) + HMAC signing helper (test-only)
- `src/lib/refunds/process-confirmed-refund.server.ts` — Orchestrator wrapper delegating to DB `process_confirmed_recharge_refund`
- `src/routes/api/public/webhooks/payments/$gatewayId.refunds.ts` — TSS public POST endpoint; raw body handled first; secret resolved from `process.env`; no PII/secrets ever returned

**Tests**
- `tests/unit/verify-refund-webhook.test.ts` — 8 vitest cases (all pass)
- `tests/sql/5c2b3_webhook_security_assertions.sql` — 8 SQL checks (all pass)

## 2. Endpoint

`POST /api/public/webhooks/payments/:gatewayId/refunds`
- Reads raw body BEFORE `JSON.parse`
- Loads gateway server-side; secret resolved from `WEBHOOK_SECRET__<ref>` env var
- Rejects on missing/invalid signature, expired/missing timestamp, mode mismatch, or missing secret
- Idempotent register on composite `(gateway_id, gateway_mode, provider_event_id)`
- Claims exclusive processing lock; opens attempt record
- Applies event; triggers wallet reversal orchestrator only on `gateway_confirmed`
- Finalizes webhook state with `mark_refund_webhook_terminal`
- Response body carries only `ok`, `webhook_id`, `outcome`, `orchestrator` — never raw payload, headers, or provider strings

## 3. RPC surface (all `service_role` only; PUBLIC/anon/authenticated = 0 EXECUTE)

| RPC | Role |
| --- | --- |
| `register_refund_webhook_event` | idempotent insert on composite unique; returns existing row on replay |
| `claim_refund_webhook_for_processing` | `FOR UPDATE` lock; sets `processing_state='processing'`; opens attempt |
| `reclaim_stale_refund_webhooks(_older_than)` | releases stuck claims |
| `apply_refund_webhook_event` | state-machine step per normalized event |
| `process_confirmed_recharge_refund` | Orchestrator: `gateway_confirmed → reversing_wallet → completed / partially_completed / manual_review`; delegates to `_apply_recharge_refund_wallet_reversal`; emits idempotent outbox message |
| `mark_refund_webhook_terminal` | closes attempt + webhook |
| `log_refund_webhook_audit` | safe metadata-only audit writer |

## 4. Verification adapter

Nine normalized event types recognized:
`refund.succeeded`, `refund.failed`, `refund.pending`, `refund.duplicate`,
`refund.wrong_amount`, `refund.wrong_currency`, `refund.wrong_mode`,
`refund.unknown_payment`, `refund.timeout`. Anything else → `refund.unknown` → treated as pending/unknown (no wallet reversal).

Failure codes: `WEBHOOK_SIGNATURE_MISSING`, `WEBHOOK_SIGNATURE_INVALID`, `WEBHOOK_TIMESTAMP_MISSING`, `WEBHOOK_TIMESTAMP_EXPIRED`, `WEBHOOK_REPLAY_DETECTED`, `WEBHOOK_GATEWAY_NOT_FOUND`, `WEBHOOK_GATEWAY_INACTIVE`, `WEBHOOK_GATEWAY_MODE_MISMATCH`, `GATEWAY_WEBHOOK_NOT_CONFIGURED`, `REFUND_NOT_FOUND`, `REFUND_AMOUNT_MISMATCH`, `REFUND_CURRENCY_MISMATCH`, `REFUND_GATEWAY_MODE_MISMATCH`, `ORIGINAL_PAYMENT_NOT_FOUND`, `REFUND_STATUS_UNKNOWN`, `REFUND_INVALID_TRANSITION`, `WALLET_REVERSAL_ERROR`.

## 5. Exactly-Once guarantees

- **Composite unique** `(gateway_id, gateway_mode, provider_event_id)` on `payment_webhooks` — duplicate replays return existing row via `register_refund_webhook_event`; no new attempt is opened, no ledger touched.
- **Processing claim** locks the row `FOR UPDATE`; only one worker can transition `received → processing`.
- **Wallet reversal** already Idempotent by ledger-existence check in `process_confirmed_recharge_refund` — if `wallet_ledger` rows exist for the refund, the reversal helper is not re-invoked.
- **Outbox idempotency** keyed on `refund:<refund_id>:<outcome>` with `ON CONFLICT (idempotency_key) DO NOTHING`.
- Same success event applied N times → single ledger pair, single completed audit, single outbox message.

## 6. Canonical wallet-reversal path

Both the synchronous adapter success (5C-2b.2 `finalize_refund_gateway_execution`) and the asynchronous webhook success now flow into the same `process_confirmed_recharge_refund` orchestrator. There is exactly ONE wallet-reversal code path.

## 7. Lock order (documented)

1. `recharge_refunds` → 2. `payment_webhooks` → 3. `payment_webhook_attempts` → 4. `wallets` (inside `_apply_recharge_refund_wallet_reversal`) → 5. ledger inserts. HTTP provider calls never happen while holding locks; the webhook handler completes verification and DB work only, no outbound network.

## 8. Redaction & secrets

- Every payload passes through `redactSensitiveData` before storage in `payload_redacted` (raw payload stays in `raw_payload` for forensic access, service-role-only readable via existing RLS).
- Webhook secret never leaves the server; `webhook_secret_ref` is a NAME resolved to `process.env.WEBHOOK_SECRET__<ref>` inside the handler.
- No Authorization/CVV/PAN/service-role/JWT ever written to `audit_logs`.

## 9. Production Guards

- Endpoint sits under `/api/public/*` and is verified strictly by HMAC over raw body.
- Mock adapter path is still gated by 5C-2b.2 `assert_mock_refund_allowed` + `ALLOW_MOCK_REFUND_GATEWAY` env; the webhook route reuses the same guard indirectly through the orchestrator.
- Real provider integration NOT enabled: only `provider_type = 'mock'` has a verified adapter today.

## 10. Test results

| # | Suite | Result |
| - | ----- | ------ |
| 1 | `verify-refund-webhook.test.ts` (8 cases) | **PASS** |
| 2 | `redact.test.ts` (8 cases) | PASS (unchanged) |
| 3 | `mock-refund-gateway.test.ts` (11 cases) | PASS (unchanged) |
| 4 | SQL: composite unique present | **PASS** |
| 5 | SQL: 18 new columns present | **PASS** |
| 6 | SQL: 7 new RPCs exist | **PASS** |
| 7 | SQL: 0 PUBLIC/anon/authenticated EXECUTE | **PASS** |
| 8 | SQL: `pw_no_write_auth` restrictive policy present | **PASS** |
| 9 | SQL: `_apply_recharge_refund_wallet_reversal` still service-only | **PASS** (leak=0) |
| 10 | SQL: `event_domain` & `validation_status` constraints present | **PASS** |
| 11 | SQL: `refund_status` enum retains 6 required states | **PASS** |

**Total static: 27/27 vitest + 8/8 SQL = PASS**

### SKIPPED (require Test Project + Auth users)

- Runtime succeeded/failed/pending/duplicate/wrong_amount/wrong_currency/wrong_mode/unknown_payment/timeout end-to-end matrix (needs test users + refund fixtures + HTTP mock server)
- Concurrent double-webhook wallet-reversal race (needs concurrent HTTP dispatch harness)
- Stale-recovery vs new-webhook race
- Ledger pairing assertion after full run
- Outbox de-dup verification after full run

These map to 5B/5C runtime-harness tests documented in `docs/testing/release-gate.md` and remain **SKIPPED**, not PASS.

## 11. Build / type-check

Fixed one TS error (`gw.status !== "testing"` — enum has no "testing"). Handler now compiles.

## 12. Release Gate

- G-13 (Refund Webhook processor, static suite): **PASS**
- G-14 (Refund Webhook processor, runtime matrix): **SKIPPED — pending Test Project**

System status: **Code Complete / Runtime Pending**. Not to be described as Production Ready until the runtime matrix and 5C-2b.4 (refresh/retry + polling) are green.

## 13. Next

Proceeding to **5C-2b.4** — `refreshRefundStatus`, `retryGatewayRefund`, polling, retry policies. UI (5C-3) remains blocked until 5C-2b.4 is code-complete.
