# Release Gate — Production Readiness Checklist

**Purpose:** Authoritative gate list. The Yamo Chat Admin Console MUST NOT be described as "Production Ready" until every item below reports `passed`.

**Statuses:** `pending` · `passed` · `failed` · `blocked`

Phase development (5C, 5D, …) may continue in parallel — the gate only governs the "ready to publish" claim.

---

## Critical Runtime Checks

| # | Check | Owner Phase | Status | Notes |
|---|---|---|---|---|
| G-01 | User A / User B RLS isolation (14-case matrix) | 5B | `pending` | Needs 2 provisioned Auth users; runs via `tests/runtime/user-isolation.spec.ts`. |
| G-02 | Concurrent webhook delivery (dedup on `(gateway_id, provider_event_id)`) | 5B | `pending` | `tests/runtime/recharge-concurrency.spec.ts::webhookDedup`. |
| G-03 | Concurrent `verify_recharge_payment` calls | 5B | `pending` | Row lock + idempotency. |
| G-04 | Concurrent `complete_recharge_request` calls | 5B | `pending` | Must yield exactly one ledger commit per request. |
| G-05 | Mock Gateway runtime — 13 event variants | 5B | `pending` | `tests/runtime/mock-gateway.spec.ts`. |
| G-06 | Playwright permission guards across finance routes | 5B | `pending` | Role matrix × route matrix. |
| G-07 | API HTTP authentication (bearer required, anon rejected) | 5B | `pending` | 15 endpoints. |
| G-08 | CSV / Excel live export (server-filtered, formula-injection safe) | 5B | `pending` | Live browser session required. |
| G-09 | Receipt signed-URL runtime (expiry, ownership, redaction) | 5B | `pending` | `create-recharge-receipt-upload` + `get-recharge-receipt-url`. |
| G-10 | Browser secret leak scan (client bundle) | 5B | `passed` | `rg` scan clean; keep re-running on every build. |
| G-11 | Refund lifecycle end-to-end (39-case matrix) | 5C | `pending` | Populated after 5C-4. |
| G-12 | Wallet balance == Σ ledger for all wallets **AND** batch double-entry (Σ user credits = Σ system debits) | 5B.5 / 5C-2 | `passed` | Verified 2026-07-18. Batch `legacy_seed_reconciliation_2026_07_18`: user credits = 14,655, system debits = 14,655, diff = 0, counter-entries = 6, unbalanced wallets = 0. See `tests/sql/5c2_reconciliation_double_entry.sql`. |
| G-13 | Two-eyes approval enforced on threshold-crossing refunds | 5C | `pending` | Same actor cannot first- and second-approve. |
| G-14 | No negative wallet balances under Refund reversal | 5C | `pending` | Insufficient balance → `manual_review`. |
| G-15 | Refund status refresh — 9-variant matrix runtime | 5C-2b.4 | `pending` | Mock adapter matrix in `tests/unit/mock-refund-status-matrix.test.ts` (static) PASS 9/9; DB integration (claim → prepare → finalize → orchestrator) requires Test Project. |
| G-16 | Retry vs webhook race (retry blocked on unknown/pending, succeeded not regressed) | 5C-2b.4 | `pending` | SQL guards verified via `tests/sql/5c2b4_status_retry_security_assertions.sql`; concurrent runtime requires Test Project. |
| G-17 | Refund user A / B isolation (23-case matrix) | 5C-4 | `blocked` | Needs Test Project + provisioned harness users; see `tests/runtime/user-isolation.spec.ts`. |
| G-18 | Refund role isolation (support / finance RO / reviewer1 / reviewer2 / manager / admin / auditor) | 5C-4 | `blocked` | Same Test Project dependency. |
| G-19 | Two-eyes approval runtime enforcement (SELF_APPROVAL_NOT_ALLOWED, SECOND_REVIEWER_MUST_DIFFER, EXECUTOR_SEPARATION_REQUIRED) | 5C-4 | `blocked` | Static SQL invariants authored in `tests/sql/5c_final_security_assertions.sql` (SEC-13, SEC-14); runtime pending. |
| G-20 | Concurrent `executeGatewayRefund` — exactly one final money movement per refund | 5C-4 | `blocked` | Test Project. |
| G-21 | Refund webhook idempotency (10× duplicate delivery → 1 wallet reversal) | 5C-4 | `blocked` | Test Project. |
| G-22 | Refund webhook vs polling race (polling never regresses `succeeded`) | 5C-4 | `blocked` | Test Project. |
| G-23 | Wallet reversal exactly-once (base + bonus double-entry pairing) | 5C-4 | `blocked` | Static ledger assertion authored (LDG-01); runtime pending. |
| G-24 | Refund ledger pairing (Σ user debits = Σ system credits per refund) | 5C-4 | `blocked` | `tests/sql/5c_final_security_assertions.sql` block 15 authored; run in Test Project. |
| G-25 | Refund negative-balance prevention (policy: block / manual_review / receivable / override) | 5C-4 | `blocked` | Test Project. |
| G-26 | Mock refund runtime matrix (create × 4, webhook × 12, status × 9) | 5C-4 | `blocked` | Unit-level matrix PASS (9/9 status, 11/11 create); DB runtime pending. |
| G-27 | Playwright refund permission guards across list / detail / wizard | 5C-4 | `blocked` | Test Project + Playwright wiring pending. |
| G-28 | Refund export redaction (CSV / Excel; formula-injection safe) | 5C-4 | `blocked` | Redaction util PASS via `tests/unit/redact.test.ts` 8/8; live export blocked. |
| G-29 | Client-bundle secret scan (0 hits for `service_role`, `SUPABASE_SERVICE_ROLE_KEY`, `sb_secret_`) | 5C-4 | `passed` | Re-verified 2026-07-18 by `rg` scan across `src/{routes,components,hooks,lib}` excluding `.server.ts` / `.functions.ts`. |
| G-30 | Refund API authentication (14 endpoints × unauth / invalid / permission-denied / feature-off) | 5C-4 | `blocked` | Test Project. |
| G-31 | Production mock guard (`MockRefundGatewayAdapter` refuses `gateway_mode !== "test"`) | 5C-4 | `passed` | `tests/unit/mock-refund-gateway.test.ts` — MOCK_GATEWAY_NOT_ALLOWED enforced. |

---

## Rules

1. Only automated evidence flips a row to `passed`. No manual sign-off substitutes for a test run.
2. A row moves to `failed` on any test failure — never silently reset to `pending`.
3. `blocked` is reserved for external dependencies (e.g. Test Project not yet provisioned); it does NOT count as `passed`.
4. Adding a new critical runtime area (Chargebacks, Disputes, KYC …) requires appending a row here in the same PR.
5. The service role key is CI-only. Never embedded in this repo, never in the client bundle, never in Playwright client context.

---

## How to run the harness

```bash
# In a dedicated Test Project — never against production data.
export TEST_ENVIRONMENT=true
export SUPABASE_URL=<test-project-url>
export SUPABASE_SERVICE_ROLE_KEY=<ci-secret>   # server-only, never printed
export TEST_RUN_ID=$(date +%s)-$RANDOM

bun run tests/setup/create-test-users.server.ts
bun run tests/setup/seed-finance-fixtures.server.ts
bunx vitest run tests/runtime/
bun run tests/setup/cleanup-finance-fixtures.server.ts
```

Every setup/cleanup script refuses to run without `TEST_ENVIRONMENT=true` and scopes writes/deletes to the current `TEST_RUN_ID`.

---

## Phase 5D-2R — Dispute Runtime Verification (Isolated Test Project)

All rows below are `blocked` with the same reason `BLOCKED_PENDING_ISOLATED_TEST_PROJECT`.
Scaffold artifacts exist and pass their own hygiene tests, but scaffold existence does NOT satisfy any runtime gate.

| # | Check | Owner Phase | Status | Notes / Evidence |
|---|---|---|---|---|
| G-32 | Dispute user A / B RLS isolation | 5D-2R | `blocked` | `tests/runtime/5d2/user-isolation.spec.ts` |
| G-33 | Dispute role isolation (support / reviewers / finance / auditor / admin) | 5D-2R | `blocked` | `tests/runtime/5d2/role-isolation.spec.ts` |
| G-34 | Direct-write protection on `recharge_disputes` (RESTRICTIVE deny) | 5D-2R | `blocked` | `tests/runtime/5d2/direct-write-protection.spec.ts` |
| G-35 | Two-eyes enforced on first/second decide (SELF_APPROVAL_NOT_ALLOWED) | 5D-2R | `blocked` | `tests/runtime/5d2/two-eyes.spec.ts` |
| G-36 | Idempotency on dispute lifecycle RPCs | 5D-2R | `blocked` | `tests/runtime/5d2/create-dispute.spec.ts`, `concurrency.spec.ts` |
| G-37 | Concurrency: exactly one winner on first_decide / second_decide race | 5D-2R | `blocked` | `tests/runtime/5d2/concurrency.spec.ts` + `helpers/concurrency-barrier.ts` |
| G-38 | Evidence upload + quarantine of blocked MIME types | 5D-2R | `blocked` | `evidence-upload.spec.ts`, `evidence-quarantine.spec.ts` |
| G-39 | Internal-note visibility restricted to reviewers | 5D-2R | `blocked` | `notes-visibility.spec.ts` |
| G-40 | Reopen produces a new record, does not mutate closed row | 5D-2R | `blocked` | `resolution-close-reopen.spec.ts` |
| G-41 | Chargeback record-only paths never touch ledger | 5D-2R | `blocked` | `chargeback-records.spec.ts` + `assert_5d2_no_financial_side_effects` |
| G-42 | Zero financial side-effects across full 5D-2R run | 5D-2R | `blocked` | `supabase/test-migrations/5d2r_no_financial_side_effects.sql` |
| G-43 | Anon has 0 EXECUTE on any dispute RPC (regression) | 5D-2R | `blocked` | `security-regression.spec.ts` |
| G-44 | Isolated Test Project provisioned and marker row present | 5D-2R | `blocked` | `tests/setup/provisioning-checklist.md`; guard `PRODUCTION_PROJECT_BLOCKED` fails closed |

Scaffold evidence (does NOT flip any gate to `passed`):
- Guard: `tests/setup/_guard.server.ts`
- Test marker migration: `supabase/test-migrations/5d2r_test_environment_marker.sql`
- Baseline snapshot + assertion: `supabase/test-migrations/5d2r_baseline_snapshot.sql`, `..._no_financial_side_effects.sql`
- Runtime specs: `tests/runtime/5d2/` (17 files)
- Scaffold validation: `tests/scaffold/5d2r-guard.test.ts`
- CI template: `.github/workflows/5d2-runtime-test.template.yml`
- Provisioning checklist: `tests/setup/provisioning-checklist.md`
