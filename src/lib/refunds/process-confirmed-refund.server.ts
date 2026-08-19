/**
 * Server-only orchestrator wrapper.
 *
 * Every entry (synchronous adapter success OR async webhook success)
 * flows through processConfirmedRechargeRefund → the DB orchestrator
 * process_confirmed_recharge_refund, which handles state transitions
 * and wallet reversal exactly-once.
 *
 * There is only ONE wallet-reversal path.
 */
import type { SupabaseClient } from "@supabase/supabase-js";

export interface ProcessResult {
  ok: boolean;
  outcome?: "completed" | "partially_completed" | "manual_review";
  reason?: string;
  status?: string;
}

export async function processConfirmedRechargeRefund(
  admin: SupabaseClient,
  refundId: string,
): Promise<ProcessResult> {
  const { data, error } = await admin.rpc("process_confirmed_recharge_refund", { _refund_id: refundId } as never);
  if (error) return { ok: false, reason: error.message };
  return (data ?? { ok: false }) as ProcessResult;
}
