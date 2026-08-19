/**
 * Seeds a minimal finance fixture set tagged with TEST_RUN_ID.
 * Every insert carries metadata.test_run_id for later cleanup scoping.
 */
import { createClient } from "@supabase/supabase-js";
import { assertTestEnvironment } from "./_guard.server";

async function main() {
  const { supabaseUrl, serviceRoleKey, testRunId } = assertTestEnvironment();
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Test gateway (mock)
  const { data: gw, error: gwErr } = await admin
    .from("payment_gateways")
    .insert({
      code: `mock_${testRunId}`,
      name: `Mock Gateway ${testRunId}`,
      mode: "test",
      is_active: true,
      metadata: { test_run_id: testRunId },
    })
    .select("id")
    .single();
  if (gwErr) throw gwErr;

  // Test recharge package
  const { error: pkgErr } = await admin.from("recharge_packages").insert({
    code: `pkg_${testRunId}`,
    name: `Test Package ${testRunId}`,
    base_coins: 100,
    bonus_coins: 10,
    is_active: true,
    metadata: { test_run_id: testRunId },
  });
  if (pkgErr) throw pkgErr;

  console.log(JSON.stringify({ test_run_id: testRunId, gateway_id: gw.id, seeded: true }));
}

main().catch((err) => {
  console.error("HARNESS FAILED:", err.message);
  process.exit(1);
});
