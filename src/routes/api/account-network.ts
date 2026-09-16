import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/account-network" as never)({
  server: { handlers: { POST: async ({ request }) => {
    const response = (status: number) => new Response(null, { status, headers: { "Cache-Control": "no-store" } });
    // Never trust location fields or an IP supplied in the request body.
    // Fail closed if the Cloudflare runtime metadata did not reach this handler.
    const cf = (request as Request & { cf?: { country?: string; city?: string } }).cf;
    const ip = request.headers.get("cf-connecting-ipv6") ?? request.headers.get("cf-connecting-ip");
    if (!cf || !ip || ip === "2a06:98c0:3600::103" || request.headers.has("cf-ew-via")) return response(503);
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ") || authorization.length>8192) return response(401);
    try {
      const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
      const { data, error } = await supabaseAdmin.auth.getUser(authorization.slice(7));
      if (error || !data.user) return response(401);
      const { error: captureError } = await supabaseAdmin.rpc("yamo_capture_network_signal" as never, {
        p_user_id: data.user.id, p_ip: ip, p_country: cf.country ?? null, p_city: cf.city ?? null,
      } as never);
      return response(captureError ? 503 : 204);
    } catch { return response(503); }
  } } },
});
