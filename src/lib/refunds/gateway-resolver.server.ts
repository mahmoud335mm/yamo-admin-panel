/**
 * Refund Gateway Resolver — server-only.
 *
 * NEVER falls back to a generic or mock adapter automatically.
 * Missing provider → REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED.
 * Mock is only returned after a full environment guard chain.
 */
import type { RefundGatewayAdapter } from "./gateway-types.server";
import { RefundGatewayError } from "./gateway-types.server";
import { MockRefundGatewayAdapter } from "./mock-refund-gateway.server";

export interface ResolverGateway {
  id: string;
  provider_type: string;
  mode: "test" | "live";
  status: string;
}

/**
 * Server environment guard — layer one.
 * Returns null if OK, otherwise a stable error code.
 */
export function assertMockRuntimeEnvironment(): string | null {
  const nodeEnv = process.env.NODE_ENV;
  const appEnv = process.env.APP_ENV ?? process.env.DEPLOYMENT_ENV;
  const allow = process.env.ALLOW_MOCK_REFUND_GATEWAY;
  const supabaseUrl = process.env.SUPABASE_URL ?? "";

  if (nodeEnv === "production") return "NODE_ENV=production";
  if (appEnv === "production") return "APP_ENV=production";
  if (allow !== "true") return "ALLOW_MOCK_REFUND_GATEWAY!=true";
  // Deny known production hosts even when other flags are misconfigured.
  const deny = (process.env.PROD_HOST_DENYLIST ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  for (const host of deny) if (host && supabaseUrl.includes(host)) return `SUPABASE_URL matches prod host ${host}`;
  return null;
}

export function resolveRefundGatewayAdapter(gateway: ResolverGateway): RefundGatewayAdapter {
  if (!gateway || !gateway.provider_type) {
    throw new RefundGatewayError("REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED", "gateway missing provider_type");
  }
  const provider = gateway.provider_type.toLowerCase();

  if (provider === "mock") {
    const envErr = assertMockRuntimeEnvironment();
    if (envErr) throw new RefundGatewayError("MOCK_GATEWAY_NOT_ALLOWED", envErr);
    if (gateway.mode !== "test") throw new RefundGatewayError("MOCK_GATEWAY_NOT_ALLOWED", `mode=${gateway.mode}`);
    if (gateway.status !== "active") throw new RefundGatewayError("MOCK_GATEWAY_NOT_ALLOWED", `status=${gateway.status}`);
    return new MockRefundGatewayAdapter();
  }

  // No adapters registered for real providers yet (5C-2b.3+). Never fall back.
  throw new RefundGatewayError(
    "REFUND_GATEWAY_ADAPTER_NOT_CONFIGURED",
    `no adapter for provider_type=${provider}`,
  );
}
