/**
 * Phase 5D-2R — User A / User B isolation runtime tests.
 *
 * Executes against the ISOLATED Supabase Test Project only. The global
 * setup provisioned every fixture user and minted their sessions once.
 * This spec reads the shared fixture file, seeds spec-scoped data, then
 * cleans it up.
 *
 * Real recharge_requests columns used (no invented columns): user_id,
 * coin_amount, total_coins, price, currency_code, request_reference and
 * metadata. The mutable non-financial verification uses external_reference
 * so the assertions never rely on a nonexistent `amount` column.
 */
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { assertRuntimeEnvironmentConfigured } from "../../setup/_guard.server";
import { getVerifiedAdminClient } from "../../setup/verified-admin-client.server";
import { loadSharedFixtures, specScope, type SharedSession } from "./shared-fixtures";

const SPEC_SCOPE = "user_isolation";

function seedRow(userId: string, testRunId: string, scope: string, tag: string) {
  return {
    user_id: userId,
    coin_amount: 100,
    total_coins: 100,
    price: 1,
    currency_code: "USD",
    request_reference: `5d2r-${scope}-${tag}-${crypto.randomUUID()}`,
    external_reference: `initial-${tag}`,
    metadata: { test_run_id: testRunId, spec_scope: scope, seeded_for: tag },
  };
}

describe("5D-2R user-isolation", () => {
  let sessions: Record<string, SharedSession> = {};
  let admin: SupabaseClient;
  let anon: SupabaseClient;
  let userAId = "";
  let userBId = "";
  let testRunId = "";
  let scope = "";
  const seededRechargeIds: string[] = [];

  beforeAll(async () => {
    ({ sessions, testRunId } = loadSharedFixtures());
    scope = specScope(SPEC_SCOPE);

    const env = assertRuntimeEnvironmentConfigured();
    const verified = await getVerifiedAdminClient();
    admin = verified.admin;
    anon = createClient(env.supabaseUrl, env.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    userAId = sessions.user_a.userId;
    userBId = sessions.user_b.userId;

    for (const [uid, tag] of [[userAId, "a"], [userBId, "b"]] as const) {
      const { data, error } = await admin
        .from("recharge_requests")
        .insert(seedRow(uid, testRunId, scope, tag))
        .select("id")
        .single();
      if (error) throw new Error(`seed recharge_requests(${tag}): ${error.message}`);
      seededRechargeIds.push(data!.id as string);
    }
  }, 90_000);

  afterAll(async () => {
    try {
      if (seededRechargeIds.length) {
        await admin.from("recharge_requests").delete().in("id", seededRechargeIds);
      }
    } catch { /* best-effort */ }
  }, 60_000);

  it("user_a cannot SELECT user_b recharge_requests", async () => {
    const { data, error } = await sessions.user_a.client
      .from("recharge_requests")
      .select("id, user_id")
      .eq("user_id", userBId);
    expect(error).toBeNull();
    expect(data ?? []).toHaveLength(0);
  });

  it("user_a can SELECT its own recharge_requests", async () => {
    const { data, error } = await sessions.user_a.client
      .from("recharge_requests")
      .select("id, user_id")
      .eq("user_id", userAId);
    expect(error).toBeNull();
    expect((data ?? []).length).toBeGreaterThanOrEqual(1);
    for (const row of data ?? []) expect(row.user_id).toBe(userAId);
  });

  it("user_a cannot UPDATE user_b recharge_requests (non-financial field)", async () => {
    const targetId = seededRechargeIds[1]; // user_b's row
    const { data, error } = await sessions.user_a.client
      .from("recharge_requests")
      .update({ external_reference: "hacked-by-user-a" })
      .eq("id", targetId)
      .select("id");
    expect((data ?? []).length).toBe(0);
    if (error) expect(error.code).toBeDefined();

    const { data: check } = await admin
      .from("recharge_requests")
      .select("external_reference")
      .eq("id", targetId)
      .single();
    expect(check?.external_reference).toBe("initial-b");
  });

  it("user_a cannot DELETE user_b recharge_requests", async () => {
    const targetId = seededRechargeIds[1];
    const { data, error } = await sessions.user_a.client
      .from("recharge_requests")
      .delete()
      .eq("id", targetId)
      .select("id");
    expect((data ?? []).length).toBe(0);
    if (error) expect(error.code).toBeDefined();

    const { data: check } = await admin
      .from("recharge_requests")
      .select("id")
      .eq("id", targetId)
      .maybeSingle();
    expect(check?.id).toBe(targetId);
  });

  it("user_a cannot SELECT user_b wallet_ledger rows", async () => {
    const { data, error } = await sessions.user_a.client
      .from("wallet_ledger")
      .select("id, user_id")
      .eq("user_id", userBId);
    expect(error).toBeNull();
    expect(data ?? []).toHaveLength(0);
  });

  it("user_a cannot INSERT a recharge_request on behalf of user_b", async () => {
    const { data, error } = await sessions.user_a.client
      .from("recharge_requests")
      .insert(seedRow(userBId, testRunId, scope, "impersonation"))
      .select("id");
    const inserted = data ?? [];
    expect(inserted.length).toBe(0);
    if (inserted.length === 0) expect(error).not.toBeNull();

    const { data: leaked } = await admin
      .from("recharge_requests")
      .select("id, metadata")
      .eq("user_id", userBId);
    for (const row of leaked ?? []) {
      const md = (row.metadata ?? {}) as { seeded_for?: string };
      expect(md.seeded_for).not.toBe("impersonation");
    }
  });

  it("anonymous client cannot SELECT recharge_requests", async () => {
    const { data } = await anon.from("recharge_requests").select("id").limit(1);
    expect(data ?? []).toHaveLength(0);
  });

  it("anonymous client cannot INSERT a recharge_request", async () => {
    const { data, error } = await anon
      .from("recharge_requests")
      .insert(seedRow(userAId, testRunId, scope, "anon_insert"))
      .select("id");
    expect((data ?? []).length).toBe(0);
    expect(error).not.toBeNull();
  });
});
