/**
 * retryGatewayRefund — TanStack Server Function.
 *
 * Retries createRefund against the payment gateway using the SAME
 * provider_idempotency_key stored on the refund row. Only permitted when
 * the previous gateway state is `never_sent`, `failed_retryable_before_send`,
 * or `failed_definitive`. `unknown_result` and `pending_confirmation` require
 * refreshRefundStatus first — never a blind retry.
 *
 * Inputs from the client: refund_id, reason, idempotency_key (request-level).
 * Amount, currency, gateway_id, provider_refund_id are NEVER accepted from
 * the client — they come from the refund row snapshot.
 */
import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const InputSchema = z.object({
  refund_id: z.string().uuid(),
  reason: z.string().min(5),
  idempotency_key: z.string().min(8),
  override_retry_limit: z.boolean().optional().default(false),
});

type RetryResult =
  | {
      ok: true;
      refund_status: string;
      attempt_status: string;
      provider_refund_id: string | null;
      retry_attempt_count: number;
    }
  | { ok: false; error_code: string; safe_reference: string; next_available_at?: string };

export const retryGatewayRefund = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input) => InputSchema.parse(input))
  .handler(async ({ data, context }): Promise<RetryResult> => {
    const { supabase, userId } = context;

    // Permission gates
    const { data: canRetry } = await supabase.rpc("has_permission", {
      _user_id: userId,
      _key: "recharge_refunds.retry_gateway",
    } as never);
    if (!canRetry) {
      return { ok: false, error_code: "PERMISSION_DENIED", safe_reference: "retry_gateway" };
    }
    if (data.override_retry_limit) {
      const { data: canOverride } = await supabase.rpc("has_permission", {
        _user_id: userId,
        _key: "recharge_refunds.override_retry_limit",
      } as never);
      if (!canOverride) {
        return {
          ok: false,
          error_code: "PERMISSION_DENIED",
          safe_reference: "override_retry_limit",
        };
      }
    }

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { resolveRefundGatewayAdapter } = await import("./gateway-resolver.server");
    const { RefundGatewayError } = await import("./gateway-types.server");

    // 1) prepare_refund_retry — checks eligibility, backoff, retry limit
    const { data: prep, error: prepErr } = await supabaseAdmin.rpc("prepare_refund_retry", {
      _refund_id: data.refund_id,
      _triggered_by: userId,
      _reason: data.reason,
      _request_idempotency_key: data.idempotency_key,
      _override_limit: data.override_retry_limit,
    } as never);
    if (prepErr) return { ok: false, error_code: "PREPARE_FAILED", safe_reference: "prepare" };
    const p = prep as {
      ok: boolean;
      error?: string;
      next_available_at?: string;
      provider_idempotency_key?: string | null;
      gateway_id?: string;
      gateway_mode?: "test" | "live";
      retry_attempt_count?: number;
    };
    if (!p.ok) {
      return {
        ok: false,
        error_code: p.error ?? "PREPARE_REJECTED",
        safe_reference: "prepare",
        next_available_at: p.next_available_at,
      };
    }

    // 2) Delegate the actual Create Refund via prepare/execute pipeline of 5C-2b.2.
    // The existing prepare_refund_gateway_execution enforces the same
    // provider_idempotency_key on the refund row — so passing a fresh
    // request-level idempotency key here still resolves to the same provider call.
    const { data: gwPrep, error: gwPrepErr } = await supabaseAdmin.rpc(
      "prepare_refund_gateway_execution",
      {
        _refund_id: data.refund_id,
        _reason: data.reason,
        _request_idempotency_key: data.idempotency_key,
      } as never,
    );
    if (gwPrepErr) return { ok: false, error_code: "PREPARE_FAILED", safe_reference: "gw_prepare" };
    const gp = gwPrep as {
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
    if (gp.idempotent_replay) {
      return {
        ok: true,
        refund_status: gp.refund_status,
        attempt_status: gp.attempt_status ?? "duplicate",
        provider_refund_id: gp.provider_refund_id ?? null,
        retry_attempt_count: p.retry_attempt_count ?? 0,
      };
    }
    if (!gp.execution_token || !gp.snapshot) {
      return { ok: false, error_code: "PREPARE_RESPONSE_INVALID", safe_reference: "gw_prepare" };
    }
    // The provider_idempotency_key MUST match the one on the refund row.
    if (gp.provider_idempotency_key !== p.provider_idempotency_key) {
      await supabaseAdmin.rpc("fail_refund_gateway_execution", {
        _refund_id: data.refund_id,
        _attempt_id: gp.attempt_id,
        _execution_token: gp.execution_token,
        _failure_code: "PROVIDER_IDEMPOTENCY_MISMATCH",
        _safe_error: "provider idempotency key changed",
      } as never);
      return { ok: false, error_code: "PROVIDER_IDEMPOTENCY_MISMATCH", safe_reference: "retry" };
    }

    // 3) Adapter call outside DB locks.
    let adapter;
    try {
      adapter = resolveRefundGatewayAdapter({
        id: gp.snapshot.gateway_id,
        provider_type: gp.snapshot.provider_type,
        mode: gp.snapshot.gateway_mode,
        status: "active",
      });
    } catch (e) {
      const code =
        e instanceof RefundGatewayError ? e.code : "REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED";
      await supabaseAdmin.rpc("fail_refund_gateway_execution", {
        _refund_id: data.refund_id,
        _attempt_id: gp.attempt_id,
        _execution_token: gp.execution_token,
        _failure_code: "GATEWAY_ADAPTER_ERROR",
        _safe_error: code,
      } as never);
      return { ok: false, error_code: code, safe_reference: "resolver" };
    }

    try {
      const result = await adapter.createRefund({
        refund_reference: gp.snapshot.refund_reference,
        original_payment_reference: gp.snapshot.original_payment_reference,
        provider_payment_id: gp.snapshot.provider_payment_id,
        amount: Number(gp.snapshot.amount),
        currency: gp.snapshot.currency,
        gateway_mode: gp.snapshot.gateway_mode,
        provider_idempotency_key: gp.provider_idempotency_key,
        metadata_safe: {
          refund_reference: gp.snapshot.refund_reference,
          retry: true,
        },
      });

      const { data: fin, error: finErr } = await supabaseAdmin.rpc(
        "finalize_refund_gateway_execution",
        {
          _refund_id: data.refund_id,
          _attempt_id: gp.attempt_id,
          _execution_token: gp.execution_token,
          _provider_refund_id: result.provider_refund_id,
          _normalized_status: result.normalized_status,
          _is_final: result.is_final,
          _is_success: result.is_success,
          _requires_webhook_confirmation: result.requires_webhook_confirmation,
          _safe_error_code: result.safe_error_code,
          _safe_reference: result.safe_reference,
        } as never,
      );
      if (finErr) return { ok: false, error_code: "FINALIZE_FAILED", safe_reference: "finalize" };
      const f = fin as { attempt_status: string; refund_status: string };
      return {
        ok: true,
        refund_status: f.refund_status,
        attempt_status: f.attempt_status,
        provider_refund_id: result.provider_refund_id,
        retry_attempt_count: p.retry_attempt_count ?? 0,
      };
    } catch (e) {
      // Timeout / unknown result → NEVER auto-retry; move to unknown_result.
      const code = e instanceof RefundGatewayError ? e.code : "GATEWAY_ADAPTER_ERROR";
      const safeRef = e instanceof RefundGatewayError ? e.safe_reference : "adapter";
      await supabaseAdmin.rpc("fail_refund_gateway_execution", {
        _refund_id: data.refund_id,
        _attempt_id: gp.attempt_id,
        _execution_token: gp.execution_token,
        _failure_code: code,
        _safe_error: safeRef,
      } as never);
      return { ok: false, error_code: code, safe_reference: safeRef };
    }
  });
