# Runtime Test Harness

These scripts run **only** in a dedicated Test Project. They refuse to execute unless `TEST_ENVIRONMENT=true` is set and `SUPABASE_URL` does not point at the production project.

## Environment contract

| Variable | Required | Notes |
|---|---|---|
| `TEST_ENVIRONMENT` | yes — must equal `true` | Hard gate. |
| `SUPABASE_URL` | yes | Must be a Test Project URL. |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | CI secret only. Never in git, never in client bundle, never printed. |
| `TEST_RUN_ID` | yes | Unique per run; every fixture is tagged with it so `cleanup` is scoped. |

## Files

- `create-test-users.server.ts` — provisions `user_a`, `user_b`, and one user per admin role (`finance_read_only`, `finance_reviewer`, `finance_manager`, `admin`, `super_admin`). Emails: `harness+<role>-<test-run-id>@yamo.test`.
- `seed-finance-fixtures.server.ts` — seeds payment gateways/methods/packages tagged with `TEST_RUN_ID` in metadata.
- `cleanup-finance-fixtures.server.ts` — deletes only rows whose `metadata->>'test_run_id' = current TEST_RUN_ID`.

## Security invariants

- Every script's first executable line is a `assertTestEnvironment()` guard.
- `SUPABASE_SERVICE_ROLE_KEY` is read from `process.env` and never logged, echoed, or serialized.
- Scripts refuse to run if `SUPABASE_URL` contains the production host allowlist (configurable via `PROD_HOST_DENYLIST`).
- All writes/deletes are scoped to the current `TEST_RUN_ID`. Wildcard deletes are forbidden.

## Run

```bash
export TEST_ENVIRONMENT=true
export SUPABASE_URL=<test-project-url>
export SUPABASE_SERVICE_ROLE_KEY=<ci-secret>
export TEST_RUN_ID=run-$(date +%s)

bun run tests/setup/create-test-users.server.ts
bun run tests/setup/seed-finance-fixtures.server.ts
bunx vitest run tests/runtime/
bun run tests/setup/cleanup-finance-fixtures.server.ts
```
