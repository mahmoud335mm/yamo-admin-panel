/**
 * Phase 5D-2R: provisions harness users on the Test project via Admin API.
 * REFUSES to run outside the Test project.
 *
 * Never uses admin.auth.admin.generateLink for session minting; see
 * mint-test-sessions.server.ts for signInWithPassword-based JWT minting.
 */
import { getVerifiedAdminClient } from "./verified-admin-client.server";
import { cleanupTestUsers } from "./cleanup-test-users.server";
import { formatSafeAuthError } from "./safe-auth-error.server";

export const ROLES = [
  "support",
  "finance",
  "moderator",
  "agency_manager",
  "bd_manager",
  "auditor",
  "admin",
  "super_admin",
  "viewer",
] as const;
export const PLAIN_USERS = ["user_a", "user_b"] as const;

function randomPassword(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export interface ProvisionedUser {
  handle: string;
  email: string;
  id: string;
  role: string | null;
  password: string; // in-memory only, never logged
}

function emailSafe(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 96);
}

export async function provisionTestUsers(): Promise<ProvisionedUser[]> {
  const { admin, env } = await getVerifiedAdminClient();
  const created: ProvisionedUser[] = [];
  const fixtureScope = `${env.testRunId}-${crypto.randomUUID()}`;
  const emailScope = emailSafe(fixtureScope);

  const { error: probeError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1 });
  if (probeError) {
    throw new Error(`adminAuthProbe failed: ${formatSafeAuthError(probeError)}`);
  }

  await cleanupTestUsers({ silent: true });

  const mk = async (handle: string, role: string | null) => {
    const email = `harness+${emailSafe(handle)}-${emailScope}@yamo.test`;
    const password = randomPassword();
    const harnessRole = role ?? "plain_user";
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { test_run_id: env.testRunId, fixture_scope: fixtureScope, handle, harness_role: harnessRole },
    });
    if (error) throw new Error(`createUser(${handle}) failed: ${formatSafeAuthError(error)}`);
    created.push({ handle, email, id: data.user!.id, role, password });
  };

  for (const h of PLAIN_USERS) await mk(h, null);
  for (const r of ROLES) await mk(r, r);

  // Manifest (no passwords, no tokens).
  console.log(JSON.stringify({
    test_run_id: env.testRunId,
    fixture_scope: fixtureScope,
    users: created.map(({ password: _p, ...rest }) => rest),
  }, null, 2));

  return created;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  provisionTestUsers().catch((err) => {
    console.error("HARNESS FAILED:", (err as Error).message);
    process.exit(1);
  });
}
