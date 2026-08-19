# Phase 5D-2R — Isolated Test Project Provisioning Checklist

Follow this checklist EXACTLY once, by hand, in the customer's own infra.
The Lovable agent MUST NOT execute these steps against the production
project (`omgrldatyncodeabecia`) under any circumstance.

## Steps

1. Create a brand-new Supabase project.
2. Confirm its Project Ref is **not** `omgrldatyncodeabecia`.
3. Attach a dedicated database (never shared with production).
4. Apply the full production migration chain from scratch to the new project.
5. Apply the test-only migrations from `supabase/test-migrations/` in order:
   - `5d2r_test_environment_marker.sql`
   - `5d2r_baseline_snapshot.sql`
   - `5d2r_no_financial_side_effects.sql`
6. Insert the marker row (service-role SQL editor):
   ```sql
   INSERT INTO public.test_environment_marker (environment_name, project_ref)
   VALUES ('test', '<expected-test-project-ref>');
   ```
7. Configure CI secrets in the `isolated-test` GitHub Environment:
   - `SUPABASE_TEST_URL`
   - `SUPABASE_TEST_ANON_KEY`
   - `SUPABASE_TEST_SERVICE_ROLE_KEY`
   - `EXPECTED_TEST_PROJECT_REF`
8. Do **not** add these secrets to the Lovable production project's secret store.
9. Run a schema-drift check between production and test.
10. Run guard verification: `bunx vitest run tests/scaffold`.
11. Run setup: nothing to run standalone — specs provision users in `beforeAll`.
12. Run the runtime suite: `bunx vitest run tests/runtime/5d2`.
13. Run cleanup: `bun run tests/setup/cleanup-test-users.server.ts`.
14. Confirm all dispute feature flags are back to `false` in the Test project.
15. Download the CI report artifact.
16. Delete the Test project (or keep it isolated) per your retention policy.
