/**
 * Static unit tests for the mock refund adapter + resolver env guard.
 * Runtime DB integration tests live under tests/runtime/ and require Test Project.
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { MockRefundGatewayAdapter } from "@/lib/refunds/mock-refund-gateway.server";
import { assertMockRuntimeEnvironment, resolveRefundGatewayAdapter } from "@/lib/refunds/gateway-resolver.server";
import { RefundGatewayError } from "@/lib/refunds/gateway-types.server";

const baseInput = {
  refund_reference: "REF-001",
  original_payment_reference: "PAY-001",
  provider_payment_id: "prov-001",
  amount: 100,
  currency: "USD",
  gateway_mode: "test" as const,
  provider_idempotency_key: "refund:REF-001:gateway-refund",
  metadata_safe: {} as Record<string, string | number | boolean>,
};

describe("MockRefundGatewayAdapter", () => {
  const a = new MockRefundGatewayAdapter();

  it("succeeded variant returns final success without webhook", async () => {
    const r = await a.createRefund({ ...baseInput, metadata_safe: { mock_variant: "succeeded" } });
    expect(r.normalized_status).toBe("succeeded");
    expect(r.is_final).toBe(true);
    expect(r.requires_webhook_confirmation).toBe(false);
    expect(r.provider_refund_id).toMatch(/^mock_refund_/);
  });

  it("failed variant returns final failure", async () => {
    const r = await a.createRefund({ ...baseInput, metadata_safe: { mock_variant: "failed" } });
    expect(r.normalized_status).toBe("failed");
    expect(r.is_final).toBe(true);
    expect(r.is_success).toBe(false);
  });

  it("pending variant is non-final and requires webhook", async () => {
    const r = await a.createRefund({ ...baseInput, metadata_safe: { mock_variant: "pending" } });
    expect(r.normalized_status).toBe("pending");
    expect(r.is_final).toBe(false);
    expect(r.requires_webhook_confirmation).toBe(true);
  });

  it("timeout variant throws GATEWAY_TIMEOUT_UNKNOWN_RESULT", async () => {
    await expect(
      a.createRefund({ ...baseInput, metadata_safe: { mock_variant: "timeout" } }),
    ).rejects.toMatchObject({ code: "GATEWAY_TIMEOUT_UNKNOWN_RESULT" });
  });

  it("same provider_idempotency_key returns same provider_refund_id", async () => {
    const r1 = await a.createRefund({ ...baseInput, metadata_safe: { mock_variant: "succeeded" } });
    const r2 = await a.createRefund({ ...baseInput, metadata_safe: { mock_variant: "succeeded" } });
    expect(r1.provider_refund_id).toBe(r2.provider_refund_id);
  });

  it("rejects live mode", async () => {
    await expect(
      a.createRefund({ ...baseInput, gateway_mode: "live" as unknown as "test" }),
    ).rejects.toMatchObject({ code: "MOCK_GATEWAY_NOT_ALLOWED" });
  });
});

describe("assertMockRuntimeEnvironment", () => {
  const saved = { ...process.env };
  beforeEach(() => {
    process.env = { ...saved };
  });
  afterEach(() => {
    process.env = saved;
  });

  it("rejects NODE_ENV=production", () => {
    process.env.NODE_ENV = "production";
    process.env.ALLOW_MOCK_REFUND_GATEWAY = "true";
    expect(assertMockRuntimeEnvironment()).toMatch(/NODE_ENV/);
  });

  it("rejects when ALLOW_MOCK_REFUND_GATEWAY is unset", () => {
    process.env.NODE_ENV = "development";
    delete process.env.ALLOW_MOCK_REFUND_GATEWAY;
    expect(assertMockRuntimeEnvironment()).toMatch(/ALLOW_MOCK_REFUND_GATEWAY/);
  });

  it("passes when env flags are correct", () => {
    process.env.NODE_ENV = "development";
    process.env.APP_ENV = "test";
    process.env.ALLOW_MOCK_REFUND_GATEWAY = "true";
    process.env.SUPABASE_URL = "https://test-project.supabase.co";
    process.env.PROD_HOST_DENYLIST = "prod.example.com";
    expect(assertMockRuntimeEnvironment()).toBeNull();
  });
});

describe("resolveRefundGatewayAdapter", () => {
  it("never falls back to mock for unknown providers", () => {
    expect(() =>
      resolveRefundGatewayAdapter({ id: "g1", provider_type: "stripe", mode: "test", status: "active" }),
    ).toThrow(RefundGatewayError);
  });
  it("rejects unknown provider with explicit code", () => {
    try {
      resolveRefundGatewayAdapter({ id: "g1", provider_type: "unknown", mode: "test", status: "active" });
    } catch (e) {
      expect((e as RefundGatewayError).code).toBe("REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED");
    }
  });
});
