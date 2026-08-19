/**
 * Server-only refund webhook verification and normalization.
 *
 * The mock adapter uses HMAC-SHA256 over the RAW body with the
 * gateway's webhook_secret_ref value used as the shared secret.
 * Real provider adapters would replace this with the provider's
 * signature scheme; the interface stays the same.
 */
import { createHmac, timingSafeEqual, createHash } from "crypto";
import { redactSensitiveData } from "../redact.server";

export interface RefundWebhookVerification {
  signature_verified: boolean;
  timestamp_verified: boolean;
  replay_check_passed: boolean;
  failure_code: string | null;
  provider_event_id: string | null;
  normalized_event_type: string; // one of the 9
  provider_refund_id: string | null;
  original_provider_payment_id: string | null;
  refund_reference: string | null;
  amount: number | null;
  currency: string | null;
  gateway_mode: "test" | "live" | null;
  occurred_at: string | null;
  payload_hash: string;
  payload_redacted: unknown;
}

export interface GatewayConfig {
  id: string;
  provider_type: string;
  mode: "test" | "live";
  webhook_secret: string | null; // resolved server-side
}

const TIMESTAMP_WINDOW_SECONDS = 5 * 60;

const RAW_TO_NORMALIZED: Record<string, string> = {
  "refund.succeeded": "refund.succeeded",
  "refund.failed": "refund.failed",
  "refund.pending": "refund.pending",
  "refund.duplicate": "refund.duplicate",
  "refund.wrong_amount": "refund.wrong_amount",
  "refund.wrong_currency": "refund.wrong_currency",
  "refund.wrong_mode": "refund.wrong_mode",
  "refund.unknown_payment": "refund.unknown_payment",
  "refund.timeout": "refund.timeout",
};

function safeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  try {
    return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
  } catch {
    return false;
  }
}

function payloadHash(raw: string): string {
  return createHash("sha256").update(raw).digest("hex");
}

/**
 * verifyRefundWebhook — pure function. NEVER logs raw body or headers.
 * Returns a normalized verification result; caller decides persistence.
 */
export function verifyRefundWebhook(
  rawBody: string,
  headers: Headers,
  gateway: GatewayConfig,
): RefundWebhookVerification {
  const hash = payloadHash(rawBody);
  const base: RefundWebhookVerification = {
    signature_verified: false,
    timestamp_verified: false,
    replay_check_passed: true,
    failure_code: null,
    provider_event_id: null,
    normalized_event_type: "refund.unknown",
    provider_refund_id: null,
    original_provider_payment_id: null,
    refund_reference: null,
    amount: null,
    currency: null,
    gateway_mode: null,
    occurred_at: null,
    payload_hash: hash,
    payload_redacted: null,
  };

  if (!gateway.webhook_secret) {
    return { ...base, failure_code: "GATEWAY_WEBHOOK_NOT_CONFIGURED" };
  }

  const sig = headers.get("x-webhook-signature");
  const tsHeader = headers.get("x-webhook-timestamp");
  if (!sig) return { ...base, failure_code: "WEBHOOK_SIGNATURE_MISSING" };
  if (!tsHeader) return { ...base, failure_code: "WEBHOOK_TIMESTAMP_MISSING" };

  const tsNum = Number(tsHeader);
  if (!Number.isFinite(tsNum)) {
    return { ...base, failure_code: "WEBHOOK_TIMESTAMP_MISSING" };
  }
  const nowSec = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSec - tsNum) > TIMESTAMP_WINDOW_SECONDS) {
    return { ...base, failure_code: "WEBHOOK_TIMESTAMP_EXPIRED" };
  }

  const expected = createHmac("sha256", gateway.webhook_secret)
    .update(`${tsHeader}.${rawBody}`)
    .digest("hex");
  if (!safeEqualHex(sig, expected)) {
    return { ...base, timestamp_verified: true, failure_code: "WEBHOOK_SIGNATURE_INVALID" };
  }

  // Parse safely.
  let json: Record<string, unknown>;
  try {
    json = JSON.parse(rawBody) as Record<string, unknown>;
  } catch {
    return {
      ...base,
      signature_verified: true,
      timestamp_verified: true,
      failure_code: "WEBHOOK_PAYLOAD_INVALID",
    };
  }

  const rawEventType = String(json.event_type ?? "");
  const normalized = RAW_TO_NORMALIZED[rawEventType] ?? "refund.unknown";
  const mode = (json.gateway_mode === "live" || json.gateway_mode === "test")
    ? (json.gateway_mode as "test" | "live")
    : null;

  return {
    signature_verified: true,
    timestamp_verified: true,
    replay_check_passed: true,
    failure_code: null,
    provider_event_id: (json.provider_event_id as string) ?? null,
    normalized_event_type: normalized,
    provider_refund_id: (json.provider_refund_id as string) ?? null,
    original_provider_payment_id: (json.original_provider_payment_id as string) ?? null,
    refund_reference: (json.refund_reference as string) ?? null,
    amount: typeof json.amount === "number" ? json.amount : (json.amount ? Number(json.amount) : null),
    currency: (json.currency as string) ?? null,
    gateway_mode: mode,
    occurred_at: (json.occurred_at as string) ?? null,
    payload_hash: hash,
    payload_redacted: redactSensitiveData(json),
  };
}

/**
 * signMockRefundWebhook — TEST-ONLY helper to produce the header set
 * a mock provider would send. Never used in production paths.
 */
export function signMockRefundWebhook(rawBody: string, secret: string, ts = Math.floor(Date.now() / 1000)) {
  const signature = createHmac("sha256", secret).update(`${ts}.${rawBody}`).digest("hex");
  return { "x-webhook-signature": signature, "x-webhook-timestamp": String(ts) };
}
