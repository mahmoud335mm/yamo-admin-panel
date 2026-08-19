/**
 * Refund Webhook Endpoint (public, verified by signature).
 *
 * POST /api/public/webhooks/payments/:gatewayId/refunds
 *
 * Contract:
 *   - Reads RAW body BEFORE JSON parse (signature is over raw bytes).
 *   - Loads gateway + webhook secret server-side (never from headers).
 *   - Verifies signature, timestamp, replay window.
 *   - Registers idempotently via composite (gateway_id, gateway_mode, provider_event_id).
 *   - Claims exclusive processing lock.
 *   - Applies event, then (only on gateway confirmation) invokes the
 *     internal wallet-reversal orchestrator.
 *   - Never returns raw payload, secrets, or provider error strings.
 */
import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/webhooks/payments/$gatewayId/refunds")({
  server: {
    handlers: {
      POST: async ({ request, params }) => {
        // 1) Read raw body first (signature is over raw bytes).
        const rawBody = await request.text();
        if (rawBody.length > 512 * 1024) {
          return json(413, { ok: false, error: "PAYLOAD_TOO_LARGE" });
        }

        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { verifyRefundWebhook } = await import("@/lib/refunds/verify-refund-webhook.server");
        const { processConfirmedRechargeRefund } = await import("@/lib/refunds/process-confirmed-refund.server");

        // 2) Load gateway config.
        const { data: gw, error: gwErr } = await supabaseAdmin
          .from("payment_gateways")
          .select("id, provider_type, mode, status, webhook_secret_ref")
          .eq("id", params.gatewayId)
          .maybeSingle();
        if (gwErr || !gw) return json(404, { ok: false, error: "WEBHOOK_GATEWAY_NOT_FOUND" });
        if (gw.status !== "active") {
          return json(403, { ok: false, error: "WEBHOOK_GATEWAY_INACTIVE" });
        }

        // 3) Resolve webhook secret from env (secret_ref is a lookup key, never the secret).
        const secretEnv = gw.webhook_secret_ref
          ? process.env[`WEBHOOK_SECRET__${gw.webhook_secret_ref}`] ?? null
          : null;

        // 4) Verify.
        const v = verifyRefundWebhook(rawBody, request.headers, {
          id: gw.id,
          provider_type: gw.provider_type,
          mode: gw.mode as "test" | "live",
          webhook_secret: secretEnv,
        });
        if (v.failure_code === "GATEWAY_WEBHOOK_NOT_CONFIGURED") {
          return json(503, { ok: false, error: "GATEWAY_WEBHOOK_NOT_CONFIGURED" });
        }
        if (!v.signature_verified) {
          return json(401, { ok: false, error: v.failure_code ?? "WEBHOOK_SIGNATURE_INVALID" });
        }
        if (!v.timestamp_verified) {
          return json(401, { ok: false, error: v.failure_code ?? "WEBHOOK_TIMESTAMP_EXPIRED" });
        }
        // Mode mismatch is fatal.
        if (v.gateway_mode && v.gateway_mode !== gw.mode) {
          return json(409, { ok: false, error: "WEBHOOK_GATEWAY_MODE_MISMATCH" });
        }

        // 5) Register (idempotent).
        const { data: reg, error: regErr } = await supabaseAdmin.rpc(
          "register_refund_webhook_event",
          {
            _gateway_id: gw.id,
            _gateway_mode: gw.mode,
            _provider_event_id: v.provider_event_id,
            _normalized_event_type: v.normalized_event_type,
            _refund_reference: v.refund_reference,
            _provider_refund_id: v.provider_refund_id,
            _original_provider_payment_id: v.original_provider_payment_id,
            _amount: v.amount,
            _currency: v.currency,
            _occurred_at: v.occurred_at,
            _payload_hash: v.payload_hash,
            _payload_redacted: v.payload_redacted as never,
            _signature_verified: v.signature_verified,
            _timestamp_verified: v.timestamp_verified,
            _replay_check_passed: v.replay_check_passed,
          } as never,
        );
        if (regErr) return json(500, { ok: false, error: "WEBHOOK_REGISTER_FAILED" });
        const r = reg as { webhook_id: string; duplicate: boolean; processing_state: string; refund_id: string | null };
        if (r.duplicate) {
          return json(200, { ok: true, idempotent: true, webhook_id: r.webhook_id });
        }

        // 6) Claim for processing.
        const { data: claim, error: claimErr } = await supabaseAdmin.rpc(
          "claim_refund_webhook_for_processing",
          { _webhook_id: r.webhook_id, _owner: `edge:${crypto.randomUUID().slice(0, 8)}` } as never,
        );
        if (claimErr) return json(500, { ok: false, error: "WEBHOOK_CLAIM_FAILED" });
        const c = claim as { claimed: boolean; attempt_id?: string; reason?: string };
        if (!c.claimed) {
          return json(200, { ok: true, deferred: true, reason: c.reason });
        }

        // 7) Apply event.
        const { data: apply, error: applyErr } = await supabaseAdmin.rpc(
          "apply_refund_webhook_event",
          { _webhook_id: r.webhook_id, _attempt_id: c.attempt_id! } as never,
        );
        if (applyErr) {
          await supabaseAdmin.rpc("mark_refund_webhook_terminal", {
            _webhook_id: r.webhook_id,
            _attempt_id: c.attempt_id,
            _final_state: "failed",
            _validation: "rejected",
            _failure_code: "WEBHOOK_APPLY_ERROR",
            _safe_error: "apply_refund_webhook_event",
            _marked_duplicate: false,
          } as never);
          return json(500, { ok: false, error: "WEBHOOK_APPLY_FAILED" });
        }
        const a = apply as {
          outcome: string;
          failure_code?: string;
          trigger_wallet_reversal?: boolean;
          marked_duplicate?: boolean;
        };

        // 8) On success events, orchestrate wallet reversal via the ONE canonical path.
        let orchestratorOutcome: string | null = null;
        if (a.trigger_wallet_reversal && r.refund_id) {
          const orch = await processConfirmedRechargeRefund(supabaseAdmin, r.refund_id);
          orchestratorOutcome = orch.outcome ?? orch.reason ?? null;
        }

        // 9) Finalize webhook state.
        const finalState = a.outcome === "rejected" ? "failed"
                         : a.outcome === "duplicate" ? "processed"
                         : "processed";
        const validation = a.outcome === "rejected" ? "rejected"
                         : a.outcome === "duplicate" ? "duplicate"
                         : a.outcome === "manual_review" ? "manual_review"
                         : "accepted";
        await supabaseAdmin.rpc("mark_refund_webhook_terminal", {
          _webhook_id: r.webhook_id,
          _attempt_id: c.attempt_id,
          _final_state: finalState,
          _validation: validation,
          _failure_code: a.failure_code ?? null,
          _safe_error: null,
          _marked_duplicate: a.outcome === "duplicate",
        } as never);

        return json(200, {
          ok: true,
          webhook_id: r.webhook_id,
          outcome: a.outcome,
          orchestrator: orchestratorOutcome,
        });
      },
    },
  },
});

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
