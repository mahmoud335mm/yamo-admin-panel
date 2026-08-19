# Runtime Test Suites (CI / Test Project only)

These vitest suites read `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `TEST_RUN_ID` from the environment. They call `assertTestEnvironment()` from `../setup/_guard.server.ts` before any request. Do NOT run these locally against production data.

## Suites

- `user-isolation.spec.ts` — Row-level isolation matrix for `user_a` vs `user_b` across recharge_requests, recharge_receipts, withdrawal_requests, wallet_ledger.
- `recharge-concurrency.spec.ts` — Concurrent webhook delivery, concurrent verify, concurrent complete.
- `mock-gateway.spec.ts` — Fires the 13 mock-gateway event variants (success, failure, pending, duplicate, wrong_amount, wrong_currency, …) and asserts idempotent handling.
