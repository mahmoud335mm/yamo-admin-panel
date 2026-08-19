import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient } from "../_shared/admin-client.ts";
import { requireJobSecret } from "../_shared/job-auth.ts";

Deno.serve(async (request) => {
  try {
    requireJobSecret(request);
    const supabase = adminClient();
    const { data, error } = await supabase.rpc("yamo_expire_moderation_actions");
    if (error) throw error;
    await supabase
      .from("yamo_system_health_events")
      .insert({
        component: "moderation-expiry-job",
        status: "healthy",
        message: `expired=${Number(data ?? 0)}`,
      });
    return Response.json({ expired: Number(data ?? 0) });
  } catch (error) {
    if (error instanceof Response) return error;
    return Response.json(
      { error: error instanceof Error ? error.message : "job_failed" },
      { status: 500 },
    );
  }
});
