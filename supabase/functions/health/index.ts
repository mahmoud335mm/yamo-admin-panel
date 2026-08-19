import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient } from "../_shared/admin-client.ts";

Deno.serve(async () => {
  const started = Date.now();
  try {
    const supabase = adminClient();
    const { error } = await supabase
      .from("yamo_app_releases")
      .select("id", { count: "exact", head: true });
    if (error) throw error;
    return Response.json({
      status: "healthy",
      database: "reachable",
      latency_ms: Date.now() - started,
      checked_at: new Date().toISOString(),
    });
  } catch {
    return Response.json(
      { status: "down", database: "unreachable", checked_at: new Date().toISOString() },
      { status: 503 },
    );
  }
});
