/**
 * Phase 5D-2R — Vitest global setup for the 5D-2 runtime suite.
 *
 * Runs ONCE per full Vitest invocation of `tests/runtime/5d2`:
 *   - fail-closed runtime preflight (env + DB marker)
 *   - provision the single shared set of fixture users
 *   - assign RBAC roles
 *   - mint each required session (retrying only on transient 429s)
 *   - write a runner-only session file (0600 perms) at RUNTIME_FIXTURE_FILE
 *
 * Never prints passwords, JWTs, refresh tokens, keys, or file contents.
 * Teardown removes the file. Auth user cleanup remains the responsibility
 * of the CI cleanup step (deletes by metadata.test_run_id).
 */
import { writeFileSync, chmodSync, existsSync, rmSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import {
  assertRuntimeEnvironmentConfigured,
} from "../../setup/_guard.server";
import { assertRuntimePreflight } from "../helpers/runtime-env";
import { provisionTestUsers } from "../../setup/create-test-users.server";
import { assignTestRoles } from "../../setup/assign-test-roles.server";
import { mintAllSessions } from "../../setup/mint-test-sessions.server";

function defaultFixturePath(testRunId: string): string {
  return join(tmpdir(), `5d2r-fixtures-${testRunId}.json`);
}

export default async function setup(): Promise<() => Promise<void>> {
  const env = assertRuntimeEnvironmentConfigured();
  await assertRuntimePreflight();

  const fixturePath = process.env.RUNTIME_FIXTURE_FILE ?? defaultFixturePath(env.testRunId);
  process.env.RUNTIME_FIXTURE_FILE = fixturePath;

  const provisioned = await provisionTestUsers();
  await assignTestRoles(provisioned);
  const sessionsMap = await mintAllSessions(provisioned);

  const users = Object.values(sessionsMap).map((s) => ({
    handle: s.handle,
    role: s.role,
    userId: s.userId,
    accessToken: s.accessToken,
  }));

  // Derive the shared fixture_scope used by provisionTestUsers via the first
  // provisioned email (harness+<handle>-<emailScope>@yamo.test). Never
  // reconstruct any secret from this — it is a non-secret scope tag.
  const firstEmail = provisioned[0]?.email ?? "";
  const scopeMatch = firstEmail.match(/harness\+[^-]+-(.+)@yamo\.test$/);
  const fixtureScope = scopeMatch?.[1] ?? env.testRunId;

  const payload = { testRunId: env.testRunId, fixtureScope, users };

  mkdirSync(dirname(fixturePath), { recursive: true });
  writeFileSync(fixturePath, JSON.stringify(payload), { encoding: "utf8" });
  try { chmodSync(fixturePath, 0o600); } catch { /* filesystem may not support */ }

  // Safe log — no tokens, no passwords, no key material, no file body.
  // eslint-disable-next-line no-console
  console.log(JSON.stringify({
    stage: "5d2r_global_setup_ready",
    test_run_id: env.testRunId,
    fixture_scope: fixtureScope,
    session_count: users.length,
  }));

  return async () => {
    try {
      if (existsSync(fixturePath)) rmSync(fixturePath, { force: true });
    } catch { /* best-effort */ }
  };
}
