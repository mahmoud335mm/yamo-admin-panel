export function requireJobSecret(request: Request) {
  const expected = Deno.env.get("CRON_SECRET");
  const supplied = request.headers.get("x-yamo-job-secret");
  if (!expected || !supplied || supplied !== expected) {
    throw new Response("unauthorized", { status: 401 });
  }
}
