/**
 * User A / User B isolation matrix. Runs ONLY under Test Project.
 * Vitest suite — requires TEST_ENVIRONMENT=true, service role key, and provisioned users.
 */
import { describe, it, expect, beforeAll } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { assertTestEnvironment, isTestEnvironment } from "../setup/_guard.server";

let adminClient: SupabaseClient;
let userAClient: SupabaseClient;
let userBClient: SupabaseClient;
let userAId: string;
let userBId: string;

const suite = describe.runIf(isTestEnvironment());

beforeAll(async () => {
  if (!isTestEnvironment()) return;
  const { supabaseUrl, serviceRoleKey, testRunId } = assertTestEnvironment();
  adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  // Look up harness users
  const { data } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 200 });
  const a = data.users.find((u) => u.email === `harness+user_a-${testRunId}@yamo.test`);
  const b = data.users.find((u) => u.email === `harness+user_b-${testRunId}@yamo.test`);
  if (!a || !b) throw new Error("Harness users not provisioned. Run create-test-users.server.ts first.");
  userAId = a.id;
  userBId = b.id;

  // Mint bearer tokens via admin API magic links (out of scope for this stub).
  // Real implementation: use admin.auth.admin.generateLink({ type: 'magiclink' }) + follow flow.
  // Left as TODO — flip release-gate G-01 to `passed` only after wiring these two clients.
  userAClient = createClient(supabaseUrl, "PLACEHOLDER_USER_A_TOKEN");
  userBClient = createClient(supabaseUrl, "PLACEHOLDER_USER_B_TOKEN");
});

suite("recharge_requests RLS — user isolation", () => {
  it("user A cannot read user B's recharge requests", async () => {
    // Seed a recharge_request as user B (via admin, tagged with user_id = userBId)
    const { data: req } = await adminClient
      .from("recharge_requests")
      .insert({ user_id: userBId, package_id: null, amount: 100 })
      .select("id")
      .single();
    expect(req?.id).toBeTruthy();

    const { data, error } = await userAClient.from("recharge_requests").select("*").eq("id", req!.id);
    expect(error?.code).not.toBe(undefined); // RLS should reject or return empty
    expect(data ?? []).toHaveLength(0);
  });

  // 13 more cases: receipts, ledger, disputes, refunds, withdrawal…
  it.todo("user A cannot read user B's recharge_receipts");
  it.todo("user A cannot upload a receipt for user B's request");
  it.todo("user A cannot download user B's receipt signed URL");
  it.todo("user A cannot read user B's wallet_ledger rows");
  it.todo("user A cannot create refund on user B's request");
  it.todo("user A cannot read user B's withdrawal_requests");
  it.todo("user A cannot read audit_logs unless has permission");
  it.todo("admin CAN read both users' recharge_requests");
  it.todo("finance_reviewer CAN read receipts but cannot approve without permission");
  it.todo("finance_manager CAN complete recharge, finance_reviewer CANNOT");
  it.todo("super_admin bypasses no RLS on wallet_ledger update/delete (still denied)");
  it.todo("anonymous cannot read any recharge_requests");
  it.todo("anonymous cannot call complete_recharge_request RPC");
});
