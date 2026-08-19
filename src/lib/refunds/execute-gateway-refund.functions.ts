/**
 * executeGatewayRefund — TanStack Server Function.
 *
 * Client-safe module path. All server-only imports (admin client, adapters)
 * are loaded inside the handler with dynamic import so nothing leaks into
 * the browser bundle.
 *
 * Flow:
 *   1) requireSupabaseAuth
 *   2) call prepare_refund_gateway_execution (as authenticated user)
 *   3) if idempotent replay → return existing result, do NOT call gateway
 *   4) resolve adapter (server-only, strict, no fallback)
 *   5) adapter.createRefund(...)
 *   6) finalize_refund_gateway_execution (service_role) or
 *      fail_refund_gateway_execution (service_role) on error
 */
import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const InputSchema = z.object({
  refund_id: z.string().uuid(),
  reason: z.string().min(5),
  idempotency_key: z.string().min(8),
});

type ExecuteResult =
  | {
      ok: true;
      idempotent_replay: boolean;
      refund_status: string;
      attempt_status: string;
      provider_refund_id: string | null;
    }
  | { ok: false; error_code: string; safe_reference: string };

export const executeGatewayRefund = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input) => InputSchema.parse(input))
  .handler(async ({ data, context }): Promise<ExecuteResult> => {
    const { supabase, userId } = context;

    // 1) Prepare (as authenticated user; RLS + permission check enforced in RPC)
    const { data: prep, error: prepErr } = await supabase.rpc("prepare_refund_gateway_execution", {
      _refund_id: data.refund_id,
      _reason: data.reason,
      _request_idempotency_key: data.idempotency_key,
    });
    if (prepErr) {
      const msg = prepErr.message ?? "PREPARE_FAILED";
      return { ok: false, error_code: msg.split(":")[0], safe_reference: "prepare" };
    }
    const p = prep as {
      idempotent_replay: boolean;
      attempt_id: string;
      execution_token?: string;
      provider_idempotency_key: string;
      snapshot?: {
        gateway_id: string;
        provider_type: string;
        gateway_mode: "test" | "live";
        original_payment_reference: string | null;
        provider_payment_id: string | null;
        amount: number;
        currency: string;
        refund_reference: string;
      };
      refund_status: string;
      attempt_status?: string;
      provider_refund_id?: string | null;
    };

    if (p.idempotent_replay) {
      console.log("[refund] idempotent replay", { refund_id: data.refund_id, actor: userId });
      return {
        ok: true,
        idempotent_replay: true,
        refund_status: p.refund_status,
        attempt_status: p.attempt_status ?? "unknown",
        provider_refund_id: p.provider_refund_id ?? null,
      };
    }

    if (!p.execution_token || !p.snapshot) {
      return { ok: false, error_code: "PREPARE_RESPONSE_INVALID", safe_reference: "prepare" };
    }

    // 2) Load server-only modules (adapter + admin client)
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { resolveRefundGatewayAdapter } = await import("./gateway-resolver.server");
    const { RefundGatewayError } = await import("./gateway-types.server");

    // 3) Extra DB-side mock guard (defense in depth)
    if (p.snapshot.provider_type === "mock") {
      const { error: mockErr } = await supabaseAdmin.rpc("assert_mock_refund_allowed", {
        _gateway_id: p.snapshot.gateway_id,
      });
      if (mockErr) {
        await supabaseAdmin.rpc("fail_refund_gateway_execution", {
          _refund_id: data.refund_id,
          _attempt_id: p.attempt_id,
          _execution_token: p.execution_token,
          _failure_code: "GATEWAY_ADAPTER_ERROR",
          _safe_error: "mock guard rejected",
        });
        return { ok: false, error_code: "MOCK_GATEWAY_NOT_ALLOWED", safe_reference: "guard" };
      }
    }

    // 4) Resolve + call adapter (NO DB locks held here)
    let adapter;
    try {
      adapter = resolveRefundGatewayAdapter({
        id: p.snapshot.gateway_id,
        provider_type: p.snapshot.provider_type,
        mode: p.snapshot.gateway_mode,
        status: "active",
      });
    } catch (e) {
      const code =
        e instanceof RefundGatewayError ? e.code : "REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED";
      await supabaseAdmin.rpc("fail_refund_gateway_execution", {
        _refund_id: data.refund_id,
        _attempt_id: p.attempt_id,
        _execution_token: p.execution_token,
        _failure_code: "GATEWAY_ADAPTER_ERROR",
        _safe_error: code,
      });
      return { ok: false, error_code: code, safe_reference: "resolver" };
    }

    try {
      const result = await adapter.createRefund({
        refund_reference: p.snapshot.refund_reference,
        original_payment_reference: p.snapshot.original_payment_reference,
        provider_payment_id: p.snapshot.provider_payment_id,
        amount: Number(p.snapshot.amount),
        currency: p.snapshot.currency,
        gateway_mode: p.snapshot.gateway_mode,
        provider_idempotency_key: p.provider_idempotency_key,
        metadata_safe: { refund_reference: p.snapshot.refund_reference },
      });

      const { data: fin, error: finErr } = await supabaseAdmin.rpc(
        "finalize_refund_gateway_execution",
        {
          _refund_id: data.refund_id,
          _attempt_id: p.attempt_id,
          _execution_token: p.execution_token,
          _provider_refund_id: result.provider_refund_id,
          _normalized_status: result.normalized_status,
          _is_final: result.is_final,
          _is_success: result.is_success,
          _requires_webhook_confirmation: result.requires_webhook_confirmation,
          _safe_error_code: result.safe_error_code,
          _safe_reference: result.safe_reference,
        } as never,
      );
      if (finErr) {
        return { ok: false, error_code: "FINALIZE_FAILED", safe_reference: "finalize" };
      }
      const f = fin as { attempt_status: string; refund_status: string };
      return {
        ok: true,
        idempotent_replay: false,
        refund_status: f.refund_status,
        attempt_status: f.attempt_status,
        provider_refund_id: result.provider_refund_id,
      };
    } catch (e) {
      const code = e instanceof RefundGatewayError ? e.code : "GATEWAY_ADAPTER_ERROR";
      const safeRef = e instanceof RefundGatewayError ? e.safe_reference : "adapter";
      await supabaseAdmin.rpc("fail_refund_gateway_execution", {
        _refund_id: data.refund_id,
        _attempt_id: p.attempt_id,
        _execution_token: p.execution_token,
        _failure_code: code,
        _safe_error: safeRef,
      });
      return { ok: false, error_code: code, safe_reference: safeRef };
    }
  });
