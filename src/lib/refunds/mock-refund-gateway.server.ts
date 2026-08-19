/**
 * Mock Refund Gateway Adapter — server-only.
 * Deterministic, keyed on provider_idempotency_key. Never runs against a live gateway.
 */
import { createHash } from "crypto";
import type {
  RefundGatewayAdapter,
  RefundCreateInput,
  RefundStatusInput,
  NormalizedRefundResult,
} from "./gateway-types.server";
import { RefundGatewayError } from "./gateway-types.server";

type Variant = "succeeded" | "failed" | "pending" | "timeout";

function variantForKey(key: string, meta: RefundCreateInput["metadata_safe"]): Variant {
  const forced = String(meta?.mock_variant ?? "").toLowerCase();
  if (forced === "succeeded" || forced === "failed" || forced === "pending" || forced === "timeout") {
    return forced;
  }
  const h = createHash("sha256").update(key).digest();
  const bucket = h[0] % 100;
  if (bucket < 70) return "succeeded";
  if (bucket < 85) return "pending";
  if (bucket < 97) return "failed";
  return "timeout";
}

function deterministicRefundId(key: string): string {
  const hex = createHash("sha256").update(key).digest("hex");
  return `mock_refund_${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

export class MockRefundGatewayAdapter implements RefundGatewayAdapter {
  readonly provider_type = "mock";

  async createRefund(input: RefundCreateInput): Promise<NormalizedRefundResult> {
    if (input.gateway_mode !== "test") {
      throw new RefundGatewayError("MOCK_GATEWAY_NOT_ALLOWED", "mock adapter requires test mode");
    }
    const variant = variantForKey(input.provider_idempotency_key, input.metadata_safe);
    const now = new Date().toISOString();

    if (variant === "timeout") {
      throw new RefundGatewayError("GATEWAY_TIMEOUT_UNKNOWN_RESULT", "mock timeout");
    }
    if (variant === "failed") {
      return {
        provider_refund_id: deterministicRefundId(input.provider_idempotency_key),
        provider_status: "failed",
        normalized_status: "failed",
        is_final: true,
        is_success: false,
        requires_webhook_confirmation: false,
        safe_reference: "mock:failed",
        safe_error_code: "MOCK_DECLINED",
        retryable: false,
        received_at: now,
      };
    }
    if (variant === "pending") {
      return {
        provider_refund_id: deterministicRefundId(input.provider_idempotency_key),
        provider_status: "pending",
        normalized_status: "pending",
        is_final: false,
        is_success: false,
        requires_webhook_confirmation: true,
        safe_reference: "mock:pending",
        safe_error_code: null,
        retryable: false,
        received_at: now,
      };
    }
    // succeeded — synchronous test path only
    return {
      provider_refund_id: deterministicRefundId(input.provider_idempotency_key),
      provider_status: "succeeded",
      normalized_status: "succeeded",
      is_final: true,
      is_success: true,
      requires_webhook_confirmation: false,
      safe_reference: "mock:succeeded",
      safe_error_code: null,
      retryable: false,
      received_at: now,
    };
  }

  async getRefundStatus(input: RefundStatusInput): Promise<NormalizedRefundResult> {
    // Deterministic status matrix. Variant encoded in the last hex chars of provider_refund_id
    // OR via the mock_status_variant suffix "::variant".
    const now = new Date().toISOString();
    const id = input.provider_refund_id;
    const [rawId, variantSuffix] = id.split("::");
    const variant = (variantSuffix ?? this._variantFromId(rawId)) as
      | "succeeded" | "failed" | "pending" | "unknown"
      | "wrong_amount" | "wrong_currency" | "wrong_mode" | "not_found" | "timeout";

    if (variant === "timeout") {
      throw new RefundGatewayError("GATEWAY_TIMEOUT_UNKNOWN_RESULT", "mock status timeout");
    }
    const base = {
      provider_refund_id: rawId,
      received_at: now,
      retryable: false,
    };
    switch (variant) {
      case "failed":
        return { ...base, provider_status: "failed", normalized_status: "failed",
          is_final: true, is_success: false, requires_webhook_confirmation: false,
          safe_reference: "mock:status:failed", safe_error_code: "MOCK_DECLINED" };
      case "pending":
        return { ...base, provider_status: "pending", normalized_status: "pending",
          is_final: false, is_success: false, requires_webhook_confirmation: true,
          safe_reference: "mock:status:pending", safe_error_code: null };
      case "unknown":
        return { ...base, provider_status: "unknown", normalized_status: "unknown",
          is_final: false, is_success: false, requires_webhook_confirmation: false,
          safe_reference: "mock:status:unknown", safe_error_code: "PROVIDER_STATUS_UNKNOWN" };
      case "not_found":
        return { ...base, provider_status: "not_found", normalized_status: "unknown",
          is_final: false, is_success: false, requires_webhook_confirmation: false,
          safe_reference: "mock:status:not_found", safe_error_code: "PROVIDER_REFUND_NOT_FOUND" };
      case "wrong_amount":
      case "wrong_currency":
      case "wrong_mode":
        return { ...base, provider_status: "succeeded", normalized_status: "succeeded",
          is_final: true, is_success: true, requires_webhook_confirmation: false,
          safe_reference: `mock:status:${variant}`, safe_error_code: null };
      case "succeeded":
      default:
        return { ...base, provider_status: "succeeded", normalized_status: "succeeded",
          is_final: true, is_success: true, requires_webhook_confirmation: false,
          safe_reference: "mock:status:succeeded", safe_error_code: null };
    }
  }

  private _variantFromId(id: string): "succeeded" | "pending" | "failed" | "unknown" {
    const h = createHash("sha256").update(id).digest();
    const b = h[0] % 100;
    if (b < 70) return "succeeded";
    if (b < 85) return "pending";
    if (b < 97) return "failed";
    return "unknown";
  }

  async healthCheck() {
    return { ok: true, safe_reason: "mock adapter always healthy" };
  }
}
