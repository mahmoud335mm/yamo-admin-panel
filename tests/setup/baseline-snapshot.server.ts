/**
 * Phase 5D-2R: baseline snapshot helper.
 * Calls capture_5d2_baseline() SQL function (test-only).
 */
import { getVerifiedAdminClient } from "./verified-admin-client.server";

export const BASELINE_WALLET_COLUMNS = ["account", "balance"] as const;
export const BASELINE_WALLET_ACCOUNTS = ["coins", "diamonds", "bonus"] as const;

export async function captureBaseline(scope: "global" | "test_run"): Promise<string> {
  const { admin, env } = await getVerifiedAdminClient();
  const { data, error } = await admin.rpc("capture_5d2_baseline", {
    _test_run_id: env.testRunId,
    _scope: scope,
  });
  if (error) throw error;
  return data as string;
}

export async function assertNoFinancialSideEffects(): Promise<void> {
  const { admin, env } = await getVerifiedAdminClient();
  const { data, error } = await admin.rpc("assert_5d2_no_financial_side_effects", {
    _test_run_id: env.testRunId,
  });
  if (error) throw error;
  const violations = (data as Array<{ violation: string }> | null) ?? [];
  if (violations.length > 0) {
    throw new Error(`FINANCIAL_SIDE_EFFECTS_DETECTED: ${violations.map((v) => v.violation).join(",")}`);
  }
}
