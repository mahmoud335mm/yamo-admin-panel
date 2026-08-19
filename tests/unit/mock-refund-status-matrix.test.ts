/**
 * Phase 5C-2b.4 — MockRefundGatewayAdapter.getRefundStatus matrix.
 * Static tests only. Runtime DB matrix is deferred to Test Project.
 */
import { describe, it, expect } from "vitest";
import { MockRefundGatewayAdapter } from "@/lib/refunds/mock-refund-gateway.server";

const a = new MockRefundGatewayAdapter();
const base = { gateway_mode: "test" as const };

describe("MockRefundGatewayAdapter.getRefundStatus — status matrix", () => {
  it("succeeded → final success, no webhook", async () => {
    const r = await a.getRefundStatus({ ...base, provider_refund_id: "mock_refund_x::succeeded" });
    expect(r.normalized_status).toBe("succeeded");
    expect(r.is_final).toBe(true);
    expect(r.is_success).toBe(true);
    expect(r.requires_webhook_confirmation).toBe(false);
  });

  it("failed → final failure", async () => {
    const r = await a.getRefundStatus({ ...base, provider_refund_id: "mock_refund_x::failed" });
    expect(r.normalized_status).toBe("failed");
    expect(r.is_final).toBe(true);
    expect(r.is_success).toBe(false);
  });

  it("pending → non-final, awaits webhook", async () => {
    const r = await a.getRefundStatus({ ...base, provider_refund_id: "mock_refund_x::pending" });
    expect(r.normalized_status).toBe("pending");
    expect(r.is_final).toBe(false);
    expect(r.requires_webhook_confirmation).toBe(true);
  });

  it("unknown → non-final, no webhook, safe error code", async () => {
    const r = await a.getRefundStatus({ ...base, provider_refund_id: "mock_refund_x::unknown" });
    expect(r.normalized_status).toBe("unknown");
    expect(r.is_final).toBe(false);
    expect(r.is_success).toBe(false);
    expect(r.safe_error_code).toBe("PROVIDER_STATUS_UNKNOWN");
  });

  it("not_found → normalizes to unknown with distinct safe code", async () => {
    const r = await a.getRefundStatus({ ...base, provider_refund_id: "mock_refund_x::not_found" });
    expect(r.normalized_status).toBe("unknown");
    expect(r.safe_error_code).toBe("PROVIDER_REFUND_NOT_FOUND");
  });

  it("timeout → throws GATEWAY_TIMEOUT_UNKNOWN_RESULT", async () => {
    await expect(
      a.getRefundStatus({ ...base, provider_refund_id: "mock_refund_x::timeout" }),
    ).rejects.toMatchObject({ code: "GATEWAY_TIMEOUT_UNKNOWN_RESULT" });
  });

  it("wrong_amount / wrong_currency / wrong_mode → succeed at provider layer (finalizer flags mismatch)", async () => {
    for (const v of ["wrong_amount", "wrong_currency", "wrong_mode"]) {
      const r = await a.getRefundStatus({ ...base, provider_refund_id: `mock_refund_x::${v}` });
      expect(r.normalized_status).toBe("succeeded");
      expect(r.safe_reference).toBe(`mock:status:${v}`);
    }
  });

  it("no variant suffix → deterministic per-id classification (never throws)", async () => {
    const r = await a.getRefundStatus({ ...base, provider_refund_id: "mock_refund_deadbeef1234" });
    expect(["succeeded", "pending", "failed", "unknown"]).toContain(r.normalized_status);
  });

  it("safe_reference and safe_error_code never contain raw payloads", async () => {
    const r = await a.getRefundStatus({ ...base, provider_refund_id: "mock_refund_x::failed" });
    expect(r.safe_reference).toMatch(/^mock:/);
    expect(String(r.safe_error_code ?? "")).not.toMatch(/token|secret|password|authorization/i);
  });
});
