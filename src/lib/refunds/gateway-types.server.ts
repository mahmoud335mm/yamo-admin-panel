/**
 * Refund Gateway Adapter — shared types.
 * Server-only: `.server.ts` filename blocks import into client bundles.
 */

export type NormalizedRefundStatus =
  | "pending"
  | "succeeded"
  | "failed"
  | "cancelled"
  | "unknown";

export interface RefundCreateInput {
  refund_reference: string;
  original_payment_reference: string | null;
  provider_payment_id: string | null;
  amount: number;
  currency: string;
  gateway_mode: "test" | "live";
  provider_idempotency_key: string;
  metadata_safe: Record<string, string | number | boolean>;
}

export interface NormalizedRefundResult {
  provider_refund_id: string | null;
  provider_status: string;
  normalized_status: NormalizedRefundStatus;
  is_final: boolean;
  is_success: boolean;
  requires_webhook_confirmation: boolean;
  safe_reference: string | null;
  safe_error_code: string | null;
  retryable: boolean;
  received_at: string; // ISO
}

export interface RefundStatusInput {
  provider_refund_id: string;
  gateway_mode: "test" | "live";
}

export interface RefundGatewayAdapter {
  readonly provider_type: string;
  createRefund(input: RefundCreateInput): Promise<NormalizedRefundResult>;
  getRefundStatus(input: RefundStatusInput): Promise<NormalizedRefundResult>;
  healthCheck(): Promise<{ ok: boolean; safe_reason?: string }>;
}

export class RefundGatewayError extends Error {
  constructor(
    public readonly code:
      | "GATEWAY_TIMEOUT_UNKNOWN_RESULT"
      | "GATEWAY_NETWORK_ERROR"
      | "GATEWAY_ADAPTER_ERROR"
      | "PROVIDER_RESPONSE_INVALID"
      | "MOCK_GATEWAY_NOT_ALLOWED"
      | "REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED",
    public readonly safe_reference: string,
  ) {
    super(code);
    this.name = "RefundGatewayError";
  }
}
