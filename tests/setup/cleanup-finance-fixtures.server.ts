/**
 * Deletes ONLY fixtures whose metadata->>'test_run_id' equals the current TEST_RUN_ID.
 * Refuses wildcard deletes. Refuses to run outside a Test Project.
 */
import { createClient } from "@supabase/supabase-js";
import { assertTestEnvironment } from "./_guard.server";

async function main() {
  const { supabaseUrl, serviceRoleKey, testRunId } = assertTestEnvironment();
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const tables = ["recharge_packages", "payment_gateways"] as const;
  const summary: Record<string, number> = {};

  for (const table of tables) {
    const { data, error } = await admin
      .from(table)
      .delete()
      .eq("metadata->>test_run_id", testRunId)
      .select("id");
    if (error) throw new Error(`cleanup(${table}) failed: ${error.message}`);
    summary[table] = data?.length ?? 0;
  }

  // Also clean up Auth users tagged with this run.
  const { data: users } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
  let userDeletes = 0;
  for (const u of users?.users ?? []) {
    if ((u.user_metadata as { test_run_id?: string } | null)?.test_run_id === testRunId) {
      await admin.auth.admin.deleteUser(u.id);
      userDeletes++;
    }
  }
  summary["auth_users"] = userDeletes;

  console.log(JSON.stringify({ test_run_id: testRunId, deleted: summary }));
}

main().catch((err) => {
  console.error("HARNESS FAILED:", err.message);
  process.exit(1);
});
