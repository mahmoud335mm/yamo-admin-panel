import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient } from "../_shared/admin-client.ts";
import { requireJobSecret } from "../_shared/job-auth.ts";

Deno.serve(async (request) => {
  try {
    requireJobSecret(request);
    const supabase = adminClient();
    const { data: requests, error } = await supabase
      .from("yamo_account_deletion_requests")
      .select("id,user_id")
      .eq("status", "approved")
      .lte("eligible_at", new Date().toISOString())
      .limit(100);
    if (error) throw error;
    let completed = 0;
    const failures: string[] = [];
    for (const item of requests ?? []) {
      await supabase
        .from("yamo_account_deletion_requests")
        .update({ original_user_id: item.user_id })
        .eq("id", item.id);
      const { error: deleteError } = await supabase.auth.admin.deleteUser(item.user_id);
      if (deleteError) {
        failures.push(item.id);
        continue;
      }
      await supabase
        .from("yamo_account_deletion_requests")
        .update({ status: "completed", resolved_at: new Date().toISOString() })
        .eq("id", item.id);
      completed++;
    }
    await supabase
      .from("yamo_system_health_events")
      .insert({
        component: "account-deletion-job",
        status: failures.length ? "degraded" : "healthy",
        message: `completed=${completed}; failed=${failures.length}`,
      });
    return Response.json({ scanned: requests?.length ?? 0, completed, failed: failures.length });
  } catch (error) {
    if (error instanceof Response) return error;
    return Response.json(
      { error: error instanceof Error ? error.message : "job_failed" },
      { status: 500 },
    );
  }
});
