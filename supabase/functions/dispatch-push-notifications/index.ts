import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { GoogleAuth } from "npm:google-auth-library@9";
import { adminClient } from "../_shared/admin-client.ts";
import { requireJobSecret } from "../_shared/job-auth.ts";

Deno.serve(async (request) => {
  try {
    requireJobSecret(request);
    const rawAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!rawAccount) throw new Error("missing_firebase_service_account");
    const account = JSON.parse(rawAccount);
    const auth = new GoogleAuth({
      credentials: account,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const token = await (await auth.getClient()).getAccessToken();
    if (!token.token) throw new Error("firebase_access_token_failed");
    const supabase = adminClient();
    const { data: queue, error } = await supabase
      .from("yamo_notification_deliveries")
      .select("id,notification_id,device_token_id,attempts")
      .in("status", ["pending", "failed"])
      .lte("next_attempt_at", new Date().toISOString())
      .limit(100);
    if (error) throw error;
    let sent = 0;
    for (const delivery of queue ?? []) {
      await supabase
        .from("yamo_notification_deliveries")
        .update({ status: "processing" })
        .eq("id", delivery.id);
      const { data: device } = await supabase
        .from("yamo_device_tokens")
        .select("token")
        .eq("id", delivery.device_token_id)
        .maybeSingle();
      if (!device?.token) continue;
      const { data: notification } = await supabase
        .from("yamo_notifications")
        .select("title_ar,body_ar")
        .eq("id", delivery.notification_id)
        .maybeSingle();
      if (!notification) {
        await supabase
          .from("yamo_notification_deliveries")
          .update({ status: "dead", last_error: "notification_not_found" })
          .eq("id", delivery.id);
        continue;
      }
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
        {
          method: "POST",
          headers: { authorization: `Bearer ${token.token}`, "content-type": "application/json" },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: { title: notification.title_ar, body: notification.body_ar },
              data: { notification_id: String(delivery.notification_id) },
            },
          }),
        },
      );
      const result = await response.json();
      if (response.ok) {
        await supabase
          .from("yamo_notification_deliveries")
          .update({
            status: "sent",
            sent_at: new Date().toISOString(),
            provider_message_id: result.name ?? null,
            last_error: null,
          })
          .eq("id", delivery.id);
        sent++;
      } else {
        const attempts = Number(delivery.attempts ?? 0) + 1;
        const dead = attempts >= 5;
        await supabase
          .from("yamo_notification_deliveries")
          .update({
            status: dead ? "dead" : "failed",
            attempts,
            last_error: JSON.stringify(result).slice(0, 1000),
            next_attempt_at: new Date(
              Date.now() + Math.min(3600, 2 ** attempts * 60) * 1000,
            ).toISOString(),
          })
          .eq("id", delivery.id);
        if (response.status === 404 || response.status === 400)
          await supabase
            .from("yamo_device_tokens")
            .update({ enabled: false })
            .eq("id", delivery.device_token_id);
      }
    }
    await supabase
      .from("yamo_system_health_events")
      .insert({
        component: "push-dispatch",
        status: "healthy",
        message: `queued=${queue?.length ?? 0}; sent=${sent}`,
      });
    return Response.json({ queued: queue?.length ?? 0, sent });
  } catch (error) {
    if (error instanceof Response) return error;
    return Response.json(
      { error: error instanceof Error ? error.message : "dispatch_failed" },
      { status: 500 },
    );
  }
});
