/**
 * Concurrent execution of recharge lifecycle RPCs. Runs ONLY under Test Project.
 */
import { describe, it } from "vitest";
import { isTestEnvironment } from "../setup/_guard.server";

describe.runIf(isTestEnvironment())("recharge lifecycle — concurrency", () => {
  it.todo("webhook dedup: 10 parallel deliveries of same (gateway_id, provider_event_id) → 1 processed");
  it.todo("verify_recharge_payment: 5 concurrent calls → single ledger commit");
  it.todo("complete_recharge_request: 5 concurrent calls → exactly one 'completed' transition");
  it.todo("retry_payment_webhook: capped at MAX_ATTEMPTS (10) even under parallel retries");
  it.todo("submit_recharge_receipt: idempotent under 5 concurrent uploads");
  it.todo("review_recharge_receipt: last-write-wins is blocked (row lock + state guard)");
  it.todo("_wallet_apply: 20 concurrent credits sum correctly to the same wallet");
  it.todo("_wallet_apply: 20 concurrent debits reject when balance would go negative");
  it.todo("recharge_request state machine: illegal transitions rejected under race");
  it.todo("audit_logs: append-only under concurrent writes (no lost updates)");
});
