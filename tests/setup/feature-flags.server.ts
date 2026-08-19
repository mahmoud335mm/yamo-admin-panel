/**
 * Phase 5D-2R: feature-flag capture/restore helpers.
 * Test-only. Never touches production flags.
 */
import { getVerifiedAdminClient } from "./verified-admin-client.server";

export async function captureFeatureFlags(): Promise<Record<string, unknown>> {
  const { admin } = await getVerifiedAdminClient();
  const { data, error } = await admin.from("feature_flags").select("key, value");
  if (error) throw error;
  return Object.fromEntries((data ?? []).map((r) => [r.key as string, r.value]));
}

export async function enableTestAdminUi(): Promise<void> {
  const { admin } = await getVerifiedAdminClient();
  await admin.from("feature_flags").upsert({ key: "enable_disputes_admin_ui", value: true });
}

export async function restoreFeatureFlags(snapshot: Record<string, unknown>): Promise<void> {
  const { admin } = await getVerifiedAdminClient();
  for (const [key, value] of Object.entries(snapshot)) {
    await admin.from("feature_flags").upsert({ key, value });
  }
}
