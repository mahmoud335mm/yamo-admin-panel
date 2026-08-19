import {
  assertRuntimeEnvironmentConfigured,
  assertTestMarker,
  runtimeEnvironmentConfigured,
} from "../../setup/_guard.server";
import { getVerifiedAdminClient } from "../../setup/verified-admin-client.server";

export {
  assertRuntimeEnvironmentConfigured,
  runtimeEnvironmentConfigured,
};

/**
 * Async preflight for every runtime `beforeAll`. Hard-fails when the CI
 * env is configured but the DB marker row is missing/invalid — never
 * silently skips at that point.
 */
export async function assertRuntimePreflight(): Promise<void> {
  const env = assertRuntimeEnvironmentConfigured();
  const { admin } = await getVerifiedAdminClient();
  await assertTestMarker(admin, env);
}
