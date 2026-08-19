/**
 * Phase 5D-1 — Dispute & Chargeback TypeScript Contracts
 *
 * Schema-only for 5D-1. No server functions, no wallet/refund execution.
 * All financial-decision RPCs are deferred to 5D-2 and later.
 */
import { z } from "zod";

export const RechargeDisputeStatus = z.enum([
  "opened","triage","awaiting_user_evidence","awaiting_internal_evidence","awaiting_gateway_evidence",
  "under_review","escalated","pending_first_decision","pending_second_decision","provisional_action",
  "resolved_user_favor","resolved_platform_favor","resolved_partial","rejected","cancelled","closed",
  "chargeback_received","chargeback_acknowledged","chargeback_evidence_due","chargeback_contested",
  "chargeback_accepted","chargeback_won","chargeback_lost",
]);
export type RechargeDisputeStatus = z.infer<typeof RechargeDisputeStatus>;

export const RechargeDisputeType = z.enum([
  "payment_not_credited","charged_wrong_amount","duplicate_charge","unauthorized_payment",
  "payment_method_issue","receipt_rejected","refund_not_received","partial_refund_issue",
  "coins_removed_incorrectly","provider_chargeback","provider_inquiry","fraud_suspected",
  "technical_error","other",
]);
export type RechargeDisputeType = z.infer<typeof RechargeDisputeType>;

export const RechargeDisputeSource = z.enum([
  "user","support","finance","system","payment_gateway","bank","chargeback_webhook","internal_audit",
]);
export type RechargeDisputeSource = z.infer<typeof RechargeDisputeSource>;

export const RechargeDisputePriority = z.enum(["low","normal","high","urgent"]);
export type RechargeDisputePriority = z.infer<typeof RechargeDisputePriority>;

export const RechargeDisputeSeverity = z.enum(["informational","low","medium","high","critical"]);
export type RechargeDisputeSeverity = z.infer<typeof RechargeDisputeSeverity>;

export const RechargeDisputeProvisionalAction = z.enum([
  "none","manual_monitoring","temporary_recharge_hold","temporary_refund_hold",
  "temporary_withdrawal_hold","temporary_wallet_spending_hold","request_identity_review","escalate_to_fraud_review",
]);
export type RechargeDisputeProvisionalAction = z.infer<typeof RechargeDisputeProvisionalAction>;

export const RechargeDisputeNoteType = z.enum([
  "internal_note","user_message","system_event","gateway_update","evidence_request",
  "evidence_received","decision_note","escalation_note","closure_note",
]);
export type RechargeDisputeNoteType = z.infer<typeof RechargeDisputeNoteType>;

export const RechargeDisputeNoteVisibility = z.enum([
  "internal","user_visible","finance_only","auditor_only","system_only",
]);
export type RechargeDisputeNoteVisibility = z.infer<typeof RechargeDisputeNoteVisibility>;

export const RechargeDisputeEvidenceType = z.enum([
  "payment_receipt","bank_statement","account_statement","gateway_confirmation","refund_confirmation",
  "user_screenshot","chat_record","support_record","device_log","webhook_record",
  "provider_document","identity_confirmation","other",
]);
export type RechargeDisputeEvidenceType = z.infer<typeof RechargeDisputeEvidenceType>;

export const RechargeDisputeEvidenceStatus = z.enum([
  "uploaded","submitted","under_review","accepted","rejected","superseded","quarantined",
]);
export type RechargeDisputeEvidenceStatus = z.infer<typeof RechargeDisputeEvidenceStatus>;

export const RechargeDisputePolicy = z.object({
  id: z.string().uuid(),
  name: z.string(),
  country: z.string().nullable(),
  currency: z.string().nullable(),
  gateway_id: z.string().uuid().nullable(),
  gateway_mode: z.string().nullable(),
  dispute_type: RechargeDisputeType.nullable(),
  source: RechargeDisputeSource.nullable(),
  user_dispute_window_days: z.number().int(),
  evidence_submission_days: z.number().int(),
  first_response_hours: z.number().int(),
  resolution_target_hours: z.number().int(),
  chargeback_response_days: z.number().int(),
  second_decision_threshold: z.coerce.number(),
  auto_close_after_no_response_days: z.number().int(),
  allow_user_submission: z.boolean(),
  require_receipt: z.boolean(),
  require_gateway_evidence: z.boolean(),
  require_second_decision: z.boolean(),
  active: z.boolean(),
  priority: z.number().int(),
  version: z.number().int(),
});
export type RechargeDisputePolicy = z.infer<typeof RechargeDisputePolicy>;

export const RechargeDisputeExposurePreview = z.object({
  original_paid_amount: z.coerce.number(),
  refunded_amount: z.coerce.number(),
  charged_back_amount: z.coerce.number(),
  resolved_compensation_amount: z.coerce.number(),
  remaining_financial_exposure: z.coerce.number(),
  original_base_coins: z.coerce.number(),
  reversed_base_coins: z.coerce.number(),
  remaining_base_exposure: z.coerce.number(),
  original_bonus: z.coerce.number(),
  reversed_bonus: z.coerce.number(),
  remaining_bonus_exposure: z.coerce.number(),
  warnings: z.array(z.string()),
  blocking_reasons: z.array(z.string()),
});
export type RechargeDisputeExposurePreview = z.infer<typeof RechargeDisputeExposurePreview>;

export const RechargeDisputeSla = z.object({
  policy_id: z.string().uuid().nullable(),
  first_response_due_at: z.string().nullable(),
  evidence_due_at: z.string().nullable(),
  resolution_due_at: z.string().nullable(),
  chargeback_due_at: z.string().nullable(),
  is_first_response_overdue: z.boolean(),
  is_resolution_overdue: z.boolean(),
  is_chargeback_overdue: z.boolean(),
});
export type RechargeDisputeSla = z.infer<typeof RechargeDisputeSla>;

export const ChargebackProviderSummary = z.object({
  provider_chargeback_id: z.string().nullable(),
  provider_case_reference: z.string().nullable(),
  provider_reason_code: z.string().nullable(),
  provider_reason_category: z.string().nullable(),
  provider_status: z.string().nullable(),
  chargeback_amount: z.coerce.number().nullable(),
  chargeback_currency: z.string().nullable(),
  evidence_due_at: z.string().nullable(),
  provider_opened_at: z.string().nullable(),
  provider_updated_at: z.string().nullable(),
  provider_decision_at: z.string().nullable(),
  provider_decision: z.string().nullable(),
  provider_mode: z.string().nullable(),
});
export type ChargebackProviderSummary = z.infer<typeof ChargebackProviderSummary>;
