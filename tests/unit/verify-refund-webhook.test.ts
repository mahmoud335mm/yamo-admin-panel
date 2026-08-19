import { describe, it, expect } from "vitest";
import { verifyRefundWebhook, signMockRefundWebhook } from "../../src/lib/refunds/verify-refund-webhook.server";

const gw = { id: "gw-1", provider_type: "mock", mode: "test" as const, webhook_secret: "secret-xyz" };

function make(rawBody: string, secret = "secret-xyz", ts?: number) {
  const h = signMockRefundWebhook(rawBody, secret, ts);
  const headers = new Headers();
  for (const [k, v] of Object.entries(h)) headers.set(k, v);
  return headers;
}

const okBody = JSON.stringify({
  event_type: "refund.succeeded",
  provider_event_id: "evt_1",
  provider_refund_id: "pref_1",
  original_provider_payment_id: "pay_1",
  refund_reference: "REF-1",
  amount: 10,
  currency: "USD",
  gateway_mode: "test",
  occurred_at: new Date().toISOString(),
});

describe("verifyRefundWebhook", () => {
  it("verifies a well-formed signed payload", () => {
    const r = verifyRefundWebhook(okBody, make(okBody), gw);
    expect(r.signature_verified).toBe(true);
    expect(r.timestamp_verified).toBe(true);
    expect(r.normalized_event_type).toBe("refund.succeeded");
    expect(r.failure_code).toBeNull();
    expect(r.payload_hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it("rejects when signature is missing", () => {
    const headers = new Headers();
    headers.set("x-webhook-timestamp", String(Math.floor(Date.now() / 1000)));
    const r = verifyRefundWebhook(okBody, headers, gw);
    expect(r.failure_code).toBe("WEBHOOK_SIGNATURE_MISSING");
    expect(r.signature_verified).toBe(false);
  });

  it("rejects when timestamp is expired", () => {
    const ts = Math.floor(Date.now() / 1000) - 3600;
    const r = verifyRefundWebhook(okBody, make(okBody, "secret-xyz", ts), gw);
    expect(r.failure_code).toBe("WEBHOOK_TIMESTAMP_EXPIRED");
  });

  it("rejects on signature tampering", () => {
    const tampered = okBody.replace('"amount":10', '"amount":9999');
    const r = verifyRefundWebhook(tampered, make(okBody), gw);
    expect(r.failure_code).toBe("WEBHOOK_SIGNATURE_INVALID");
  });

  it("rejects when gateway has no webhook secret", () => {
    const r = verifyRefundWebhook(okBody, make(okBody), { ...gw, webhook_secret: null });
    expect(r.failure_code).toBe("GATEWAY_WEBHOOK_NOT_CONFIGURED");
  });

  it("normalizes each of the 9 event types", () => {
    const kinds = [
      "refund.succeeded","refund.failed","refund.pending","refund.duplicate",
      "refund.wrong_amount","refund.wrong_currency","refund.wrong_mode",
      "refund.unknown_payment","refund.timeout",
    ];
    for (const k of kinds) {
      const body = JSON.stringify({ ...JSON.parse(okBody), event_type: k, provider_event_id: `e_${k}` });
      const r = verifyRefundWebhook(body, make(body), gw);
      expect(r.normalized_event_type).toBe(k);
    }
  });

  it("falls back to refund.unknown for unrecognized event names", () => {
    const body = JSON.stringify({ ...JSON.parse(okBody), event_type: "refund.what" });
    const r = verifyRefundWebhook(body, make(body), gw);
    expect(r.normalized_event_type).toBe("refund.unknown");
  });

  it("redacts sensitive fields in payload_redacted", () => {
    const body = JSON.stringify({
      event_type: "refund.succeeded", provider_event_id: "e",
      authorization: "Bearer xxxxxxxxxxxxxxxxxxxx",
      card_number: "4111111111111111",
      amount: 1, currency: "USD", gateway_mode: "test",
    });
    const r = verifyRefundWebhook(body, make(body), gw);
    const p = r.payload_redacted as Record<string, unknown>;
    expect(p.authorization).toBe("***REDACTED***");
    expect(String(p.card_number)).not.toBe("4111111111111111");
  });
});
