/**
 * Mock gateway event matrix. Runs ONLY under Test Project.
 * Calls mock_emit_webhook RPC with each variant and asserts the resulting request state.
 */
import { describe, it } from "vitest";
import { isTestEnvironment } from "../setup/_guard.server";

describe.runIf(isTestEnvironment())("mock gateway — event variants", () => {
  it.todo("payment.succeeded → recharge_request transitions to 'paid'");
  it.todo("payment.failed → recharge_request transitions to 'failed' with failure_code");
  it.todo("payment.pending → no transition, only event logged");
  it.todo("payment.duplicate → idempotent, ledger untouched");
  it.todo("payment.wrong_amount → recharge_request routed to 'manual_review'");
  it.todo("payment.wrong_currency → recharge_request routed to 'manual_review'");
  it.todo("payment.chargeback → recharge_request transitions to 'chargeback'");
  it.todo("refund.succeeded → refund transitions to 'gateway_confirmed'");
  it.todo("refund.failed → refund transitions to 'failed'");
  it.todo("refund.pending → no transition");
  it.todo("refund.duplicate → idempotent");
  it.todo("refund.wrong_amount → refund routed to 'manual_review'");
  it.todo("refund.wrong_currency → refund routed to 'manual_review'");
});
