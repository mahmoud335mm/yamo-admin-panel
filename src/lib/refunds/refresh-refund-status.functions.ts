/**
 * refreshRefundStatus — TanStack Server Function.
 *
 * Queries the payment gateway for the CURRENT status of an existing refund.
 * NEVER creates a new refund. Uses the stored provider_refund_id /
 * provider_idempotency_key from the refund row — inputs from the client are
 * refund_id, reason, and idempotency_key only.
 *
 * Flow:
 *   1) requireSupabaseAuth
 *   2) claim polling lease (service_role RPC)
 *   3) prepare status refresh attempt (service_role RPC) — inserts refresh_status attempt
 *   4) resolve adapter (no fallback), call adapter.getRefundStatus outside DB locks
 *   5) finalize_refund_status_refresh (service_role RPC) — validates snapshot,
 *      updates attempt + refund state, schedules next poll or promotes to
 *      gateway_confirmed / manual_review.
 *   6) if succeeded → invoke process_confirmed_recharge_refund (canonical path).
 */
import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const InputSchema = z.object({
  refund_id: z.string().uuid(),
  reason: z.string().min(5),
  idempotency_key: z.string().min(8),
});

type RefreshResult =
  | {
      ok: true;
      outcome: string;
      refund_status?: string;
      next_check_at?: string | null;
      orchestrator?: string | null;
    }
  | { ok: false; error_code: string; safe_reference: string };

export const refreshRefundStatus = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input) => InputSchema.parse(input))
  .handler(async ({ data, context }): Promise<RefreshResult> => {
    const { supabase, userId } = context;

    // Permission check via authenticated client — RLS + has_permission.
    const { data: canRefresh } = await supabase.rpc("has_permission", {
      _user_id: userId,
      _key: "recharge_refunds.refresh_status",
    } as never);
    if (!canRefresh) {
      return { ok: false, error_code: "PERMISSION_DENIED", safe_reference: "refresh_status" };
    }

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { resolveRefundGatewayAdapter } = await import("./gateway-resolver.server");
    const { RefundGatewayError } = await import("./gateway-types.server");
    const { processConfirmedRechargeRefund } = await import("./process-confirmed-refund.server");

    const owner = `refresh:${userId.slice(0, 8)}:${crypto.randomUUID().slice(0, 8)}`;

    // 1) Claim polling lease
    const { data: claim, error: claimErr } = await supabaseAdmin.rpc(
      "claim_refund_status_refresh",
      { _refund_id: data.refund_id, _owner: owner, _lease_seconds: 60 } as never,
    );
    if (claimErr) return { ok: false, error_code: "CLAIM_FAILED", safe_reference: "claim" };
    const c = claim as { claimed: boolean; reason?: string };
    if (!c.claimed) {
      return {
        ok: false,
        error_code: c.reason ?? "REFUND_STATUS_CHECK_ALREADY_RUNNING",
        safe_reference: "claim",
      };
    }

    try {
      // 2) Prepare attempt (returns snapshot + execution_token)
      const { data: prep, error: prepErr } = await supabaseAdmin.rpc(
        "prepare_refund_status_refresh",
        {
          _refund_id: data.refund_id,
          _triggered_by: userId,
          _reason: data.reason,
          _request_idempotency_key: data.idempotency_key,
          _polling_owner: owner,
        } as never,
      );
      if (prepErr) return { ok: false, error_code: "PREPARE_FAILED", safe_reference: "prepare" };
      const p = prep as {
        ok: boolean;
        error?: string;
        attempt_id?: string;
        execution_token?: string;
        provider_refund_id?: string | null;
        provider_idempotency_key?: string | null;
        gateway_id?: string;
        gateway_mode?: "test" | "live";
      };
      if (!p.ok) {
        return { ok: false, error_code: p.error ?? "PREPARE_REJECTED", safe_reference: "prepare" };
      }
      if (!p.provider_refund_id) {
        return { ok: false, error_code: "NO_PROVIDER_REFERENCE", safe_reference: "prepare" };
      }

      // 3) Load gateway metadata for adapter resolution
      const { data: gw } = await supabaseAdmin
        .from("payment_gateways")
        .select("id, provider_type, mode, status")
        .eq("id", p.gateway_id!)
        .maybeSingle();
      if (!gw) return { ok: false, error_code: "GATEWAY_NOT_FOUND", safe_reference: "gateway" };

      // 4) Resolve + call adapter (NO DB locks held here)
      let adapter;
      try {
        adapter = resolveRefundGatewayAdapter({
          id: gw.id,
          provider_type: gw.provider_type,
          mode: gw.mode as "test" | "live",
          status: gw.status,
        });
      } catch (e) {
        const code =
          e instanceof RefundGatewayError ? e.code : "REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED";
        return { ok: false, error_code: code, safe_reference: "resolver" };
      }

      let result;
      try {
        result = await adapter.getRefundStatus({
          provider_refund_id: p.provider_refund_id,
          gateway_mode: p.gateway_mode!,
        });
      } catch (e) {
        const code = e instanceof RefundGatewayError ? e.code : "GATEWAY_ADAPTER_ERROR";
        // Do NOT finalize on unknown result — leave attempt open, release lease.
        return { ok: false, error_code: code, safe_reference: "adapter" };
      }

      // 5) Finalize
      const { data: fin, error: finErr } = await supabaseAdmin.rpc(
        "finalize_refund_status_refresh",
        {
          _refund_id: data.refund_id,
          _attempt_id: p.attempt_id!,
          _execution_token: p.execution_token!,
          _normalized_status: result.normalized_status,
          _provider_refund_id: result.provider_refund_id,
          _amount: null, // adapter may not know refund amount; skip amount check unless surfaced
          _currency: null,
          _gateway_mode: p.gateway_mode!,
          _is_final: result.is_final,
          _safe_error_code: result.safe_error_code,
        } as never,
      );
      if (finErr) return { ok: false, error_code: "FINALIZE_FAILED", safe_reference: "finalize" };
      const f = fin as { ok: boolean; outcome: string; next_check_at?: string; error?: string };
      if (!f.ok)
        return {
          ok: false,
          error_code: f.error ?? "FINALIZE_REJECTED",
          safe_reference: "finalize",
        };

      // 6) On gateway_confirmed → canonical wallet reversal orchestrator
      let orchestrator: string | null = null;
      if (f.outcome === "gateway_confirmed") {
        const orch = await processConfirmedRechargeRefund(supabaseAdmin, data.refund_id);
        orchestrator = orch.outcome ?? orch.reason ?? null;
      }

      return {
        ok: true,
        outcome: f.outcome,
        next_check_at: f.next_check_at ?? null,
        orchestrator,
      };
    } finally {
      await supabaseAdmin.rpc("release_refund_status_refresh", {
        _refund_id: data.refund_id,
        _owner: owner,
      } as never);
    }
  });
