import { expect } from "vitest";

interface RpcError { code?: string; message?: string }

export function expectRpcErrorCode(err: RpcError | null | undefined, code: string): void {
  expect(err, `expected error code ${code}`).toBeTruthy();
  expect((err?.code ?? err?.message ?? "").toString()).toContain(code);
}
export const expectRlsDenied           = (e: RpcError) => expectRpcErrorCode(e, "42501");
export const expectPermissionDenied    = (e: RpcError) => expectRpcErrorCode(e, "PERMISSION_DENIED");
export const expectIdempotentReplay    = (e: RpcError) => expectRpcErrorCode(e, "IDEMPOTENT_REPLAY");
export const expectIllegalTransition   = (e: RpcError) => expectRpcErrorCode(e, "ILLEGAL_TRANSITION");
export function expectNoFinancialMutation(violations: Array<{ violation: string }>): void {
  expect(violations, "no financial mutations allowed").toEqual([]);
}
