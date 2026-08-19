/**
 * Refund admin server functions (5C-3).
 * All wrappers around SECURITY DEFINER RPCs — no direct wallet/ledger writes.
 */
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

/* eslint-disable @typescript-eslint/no-explicit-any */

function maskId(v: string | null | undefined): string | null {
  if (!v) return null;
  if (v.length <= 8) return "***" + v.slice(-2);
  return v.slice(0, 4) + "…" + v.slice(-4);
}

function safeRpcError(msg: string, prefix = "REFUND"): string {
  const m = (msg ?? "").toUpperCase();
  const known = [
    "REFUND_FEATURE_DISABLED",
    "REFUND_EXECUTION_DISABLED",
    "REFUND_NOT_FOUND",
    "REFUND_INVALID_TRANSITION",
    "REFUND_NOT_EXECUTABLE",
    "REFUND_ALREADY_PROCESSING",
    "REFUND_ALREADY_COMPLETED",
    "SELF_APPROVAL_NOT_ALLOWED",
    "SECOND_REVIEWER_MUST_DIFFER",
    "SECOND_APPROVAL_REQUIRED",
    "EXECUTOR_SEPARATION_REQUIRED",
    "REFUND_AMOUNT_EXCEEDS_AVAILABLE",
    "INSUFFICIENT_BALANCE",
    "PREVIEW_DRIFT_REQUIRES_REVIEW",
    "REFUND_STATUS_REFRESH_REQUIRED",
    "REFUND_RESULT_UNKNOWN",
    "REFUND_NOT_RETRYABLE",
    "RETRY_LIMIT_REACHED",
    "RETRY_BACKOFF_ACTIVE",
    "MOCK_GATEWAY_NOT_ALLOWED",
    "PROVIDER_STATUS_CONFLICT",
    "POLICY_CONFLICT",
    "FORBIDDEN",
    "PERMISSION_DENIED",
    "NOT_AUTHENTICATED",
    "REASON_REQUIRED_MIN_5",
  ];
  for (const k of known) if (m.includes(k)) return k;
  return `${prefix}_INTERNAL`;
}

async function checkPermission(supabase: any, userId: string, key: string): Promise<boolean> {
  const { data } = await supabase.rpc("has_permission", { _user_id: userId, _key: key });
  return data === true;
}

async function featureFlagOn(supabase: any, key: string): Promise<boolean> {
  const { data } = await supabase
    .from("system_settings")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  return Boolean(data && (data.value === true || data.value === "true"));
}

/* ---------------- feature flags ---------------- */
export const getRefundFeatureFlags = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const s: any = context.supabase;
    const { data } = await s
      .from("system_settings")
      .select("key,value")
      .in("key", [
        "enable_refund_admin_ui",
        "enable_refund_execution",
        "enable_refund_user_requests",
      ]);
    const map: Record<string, boolean> = {};
    ((data ?? []) as Array<{ key: string; value: unknown }>).forEach((r) => {
      map[r.key] = r.value === true || r.value === "true";
    });
    return {
      admin_ui: map.enable_refund_admin_ui ?? false,
      execution: map.enable_refund_execution ?? false,
      user_requests: map.enable_refund_user_requests ?? false,
    };
  });

/* ---------------- listRechargeRefunds ---------------- */
const ListInput = z.object({
  page: z.number().int().min(1).default(1),
  page_size: z.number().int().min(1).max(100).default(25),
  search: z.string().max(120).optional(),
  status: z.array(z.string()).optional(),
  refund_type: z.array(z.enum(["full", "partial"])).optional(),
  refund_scope: z.array(z.string()).optional(),
  gateway_id: z.array(z.string().uuid()).optional(),
  gateway_mode: z.array(z.enum(["test", "live"])).optional(),
  currency: z.array(z.string()).optional(),
  requires_second_approval: z.boolean().optional(),
  manual_review_only: z.boolean().optional(),
  date_from: z.string().optional(),
  date_to: z.string().optional(),
});

export const listRechargeRefunds = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => ListInput.parse(raw))
  .handler(async ({ data, context }) => {
    const s: any = context.supabase;
    if (!(await checkPermission(s, context.userId, "recharge_refunds.read"))) {
      return {
        success: false as const,
        error_code: "PERMISSION_DENIED",
        safe_message: "لا تملك صلاحية عرض الاستردادات",
      };
    }
    let q: any = s
      .from("recharge_refunds")
      .select("*", { count: "exact" })
      .order("created_at", { ascending: false });
    if (data.search)
      q = q.or(`refund_reference.ilike.%${data.search}%,provider_refund_id.ilike.%${data.search}%`);
    if (data.status?.length) q = q.in("status", data.status);
    if (data.refund_type?.length) q = q.in("refund_type", data.refund_type);
    if (data.refund_scope?.length) q = q.in("refund_scope", data.refund_scope);
    if (data.gateway_id?.length) q = q.in("gateway_id", data.gateway_id);
    if (data.gateway_mode?.length) q = q.in("gateway_mode", data.gateway_mode);
    if (data.currency?.length) q = q.in("currency_code", data.currency);
    if (data.requires_second_approval !== undefined)
      q = q.eq("requires_second_approval", data.requires_second_approval);
    if (data.manual_review_only) q = q.eq("status", "manual_review");
    if (data.date_from) q = q.gte("created_at", data.date_from);
    if (data.date_to) q = q.lte("created_at", data.date_to);
    const from = (data.page - 1) * data.page_size;
    q = q.range(from, from + data.page_size - 1);
    const { data: rows, error, count } = await q;
    if (error)
      return {
        success: false as const,
        error_code: "LIST_FAILED",
        safe_message: "تعذّر تحميل الاستردادات",
      };
    const masked = ((rows ?? []) as Array<Record<string, any>>).map((r) => ({
      id: r.id,
      refund_reference: r.refund_reference,
      request_id: r.request_id,
      user_id: r.user_id,
      refund_type: r.refund_type,
      refund_scope: r.refund_scope,
      requested_amount: r.requested_amount,
      approved_amount: r.approved_amount,
      currency_code: r.currency_code,
      base_coins_to_reverse: r.base_coins_to_reverse,
      bonus_coins_to_reverse: r.bonus_coins_to_reverse,
      coins_actually_reversed: r.coins_actually_reversed,
      bonus_actually_reversed: r.bonus_actually_reversed,
      unrecovered_coin_amount: r.unrecovered_coin_amount,
      unrecovered_bonus_amount: r.unrecovered_bonus_amount,
      status: r.status,
      requires_second_approval: r.requires_second_approval,
      gateway_id: r.gateway_id,
      gateway_mode: r.gateway_mode,
      retry_attempt_count: r.retry_attempt_count,
      status_refresh_count: r.status_refresh_count,
      requested_at: r.requested_at,
      executed_at: r.executed_at,
      updated_at: r.updated_at,
      created_at: r.created_at,
      provider_refund_id_masked: maskId(r.provider_refund_id ?? null),
    }));
    return { success: true as const, data: { rows: masked, total: count ?? 0 } };
  });

/* ---------------- listRefundStats ---------------- */
export const listRefundStats = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const s: any = context.supabase;
    if (!(await checkPermission(s, context.userId, "recharge_refunds.read"))) {
      return { success: false as const, error_code: "PERMISSION_DENIED" };
    }
    const { data, error } = await s
      .from("recharge_refunds")
      .select(
        "status,currency_code,approved_amount,coins_actually_reversed,unrecovered_coin_amount",
      );
    if (error) return { success: false as const, error_code: "STATS_FAILED" };
    const rows = (data ?? []) as Array<any>;
    const byStatus: Record<string, number> = {};
    const amountsByCurrency: Record<string, number> = {};
    let totalCoinsReversed = 0,
      totalCoinsUnrecovered = 0;
    for (const r of rows) {
      byStatus[r.status] = (byStatus[r.status] ?? 0) + 1;
      if (r.status === "completed" || r.status === "partially_completed") {
        amountsByCurrency[r.currency_code] =
          (amountsByCurrency[r.currency_code] ?? 0) + Number(r.approved_amount ?? 0);
      }
      totalCoinsReversed += Number(r.coins_actually_reversed ?? 0);
      totalCoinsUnrecovered += Number(r.unrecovered_coin_amount ?? 0);
    }
    return {
      success: true as const,
      data: {
        total: rows.length,
        by_status: byStatus,
        amounts_by_currency: amountsByCurrency,
        total_coins_reversed: totalCoinsReversed,
        total_coins_unrecovered: totalCoinsUnrecovered,
      },
    };
  });

/* ---------------- getRechargeRefundDetail ---------------- */
export const getRechargeRefundDetail = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => z.object({ refund_id: z.string().uuid() }).parse(raw))
  .handler(async ({ data, context }) => {
    const s: any = context.supabase;
    if (!(await checkPermission(s, context.userId, "recharge_refunds.read"))) {
      return {
        success: false as const,
        error_code: "PERMISSION_DENIED",
        safe_message: "لا تملك صلاحية عرض الاستردادات",
      };
    }
    const canReadAttempts = await checkPermission(
      s,
      context.userId,
      "recharge_refunds.read_attempts",
    );

    const { data: refund, error } = await s
      .from("recharge_refunds")
      .select("*")
      .eq("id", data.refund_id)
      .maybeSingle();
    if (error || !refund) {
      return {
        success: false as const,
        error_code: "REFUND_NOT_FOUND",
        safe_message: "الاسترداد غير موجود",
      };
    }
    const r = refund as any;

    const [reqRes, gwRes, attemptsRes, whRes, ledgerRes, audRes] = await Promise.all([
      s
        .from("recharge_requests")
        .select(
          "id,request_reference,user_id,package_id,coin_amount,bonus_amount,total_coins,currency_code,final_amount,payment_gateway_id,payment_gateway_mode,payment_status,external_reference,status,updated_at,created_at,package_snapshot",
        )
        .eq("id", r.request_id)
        .maybeSingle(),
      r.gateway_id
        ? s
            .from("payment_gateways")
            .select("id,name,provider_type,mode,status")
            .eq("id", r.gateway_id)
            .maybeSingle()
        : Promise.resolve({ data: null }),
      canReadAttempts
        ? s
            .from("recharge_refund_attempts")
            .select(
              "id,attempt_number,trigger_type,status,provider_refund_id,started_at,finished_at,failure_code,safe_error,triggered_by,reason,request_correlation_id,gateway_mode",
            )
            .eq("refund_id", data.refund_id)
            .order("attempt_number", { ascending: false })
            .limit(50)
        : Promise.resolve({ data: [] }),
      canReadAttempts
        ? s
            .from("payment_webhooks")
            .select(
              "id,provider_event_id,normalized_event_type,signature_verified,timestamp_verified,replay_check_passed,processing_state,validation_status,received_at,processed_at,failure_code,safe_error",
            )
            .eq("refund_id", data.refund_id)
            .order("received_at", { ascending: false })
            .limit(50)
        : Promise.resolve({ data: [] }),
      s
        .from("wallet_ledger")
        .select(
          "id,transaction_group_id,wallet_id,account,direction,amount,balance_after,reason,reference,ledger_side,created_at",
        )
        .eq("refund_id", data.refund_id)
        .order("created_at", { ascending: true })
        .limit(200),
      s
        .from("audit_logs")
        .select("id,actor_id,action,entity_type,entity_id,reason,metadata,created_at")
        .eq("entity_id", data.refund_id)
        .order("created_at", { ascending: false })
        .limit(100),
    ]);

    const attempts = ((attemptsRes.data ?? []) as any[]).map((a) => ({
      id: a.id,
      attempt_number: a.attempt_number,
      trigger_type: a.trigger_type,
      status: a.status,
      started_at: a.started_at,
      finished_at: a.finished_at,
      failure_code: a.failure_code,
      safe_error: a.safe_error,
      triggered_by: a.triggered_by,
      reason: a.reason,
      gateway_mode: a.gateway_mode,
      provider_refund_id_masked: maskId(a.provider_refund_id ?? null),
      request_correlation_id_masked: maskId(a.request_correlation_id ?? null),
    }));
    const webhooks = ((whRes.data ?? []) as any[]).map((w) => ({
      id: w.id,
      normalized_event_type: w.normalized_event_type,
      signature_verified: w.signature_verified,
      timestamp_verified: w.timestamp_verified,
      replay_check_passed: w.replay_check_passed,
      processing_state: w.processing_state,
      validation_status: w.validation_status,
      received_at: w.received_at,
      processed_at: w.processed_at,
      failure_code: w.failure_code,
      safe_error: w.safe_error,
      provider_event_id_masked: maskId(w.provider_event_id ?? null),
    }));

    const refundSafe = {
      ...r,
      provider_refund_id_masked: maskId(r.provider_refund_id ?? null),
      idempotency_key_masked: maskId(r.idempotency_key ?? null),
      provider_idempotency_key_masked: maskId(r.provider_idempotency_key ?? null),
      original_payment_reference_masked: maskId(r.original_payment_reference ?? null),
      provider_refund_id: undefined,
      idempotency_key: undefined,
      provider_idempotency_key: undefined,
      original_payment_reference: undefined,
    };

    return {
      success: true as const,
      data: {
        refund: refundSafe,
        recharge_request: reqRes.data,
        gateway: gwRes.data,
        attempts,
        webhooks,
        ledger: ledgerRes.data ?? [],
        audit: audRes.data ?? [],
        can_read_attempts: canReadAttempts,
      },
    };
  });

/* ---------------- previewRechargeRefund ---------------- */
export const previewRechargeRefundFn = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        recharge_request_id: z.string().uuid(),
        refund_type: z.enum(["full", "partial"]),
        refund_scope: z.enum([
          "money_only",
          "money_and_base_coins",
          "money_and_all_coins",
          "administrative_compensation",
          "technical_failure",
        ]),
        requested_amount: z.number().positive().optional(),
        bonus_policy: z.string().optional(),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    const s: any = context.supabase;
    if (!(await checkPermission(s, context.userId, "recharge_refunds.read"))) {
      return {
        success: false as const,
        error_code: "PERMISSION_DENIED",
        safe_message: "لا تملك صلاحية المعاينة",
      };
    }
    const { data: preview, error } = await s.rpc("preview_recharge_refund", {
      _recharge_request_id: data.recharge_request_id,
      _refund_type: data.refund_type,
      _refund_scope: data.refund_scope,
      _requested_amount: data.requested_amount ?? null,
      _bonus_policy: data.bonus_policy ?? null,
    });
    if (error) {
      return {
        success: false as const,
        error_code: safeRpcError(error.message ?? ""),
        safe_message: error.message ?? "تعذّرت المعاينة",
      };
    }
    return { success: true as const, data: preview };
  });

/* ---------------- requestRechargeRefund ---------------- */
export const requestRechargeRefundFn = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        recharge_request_id: z.string().uuid(),
        refund_type: z.enum(["full", "partial"]),
        refund_scope: z.enum([
          "money_only",
          "money_and_base_coins",
          "money_and_all_coins",
          "administrative_compensation",
          "technical_failure",
        ]),
        requested_amount: z.number().positive(),
        bonus_policy: z.string().optional(),
        reason: z.string().min(5).max(500),
        idempotency_key: z.string().min(8).max(80),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    const s: any = context.supabase;
    if (!(await checkPermission(s, context.userId, "recharge_refunds.request"))) {
      return {
        success: false as const,
        error_code: "PERMISSION_DENIED",
        safe_message: "لا تملك صلاحية طلب الاسترداد",
      };
    }
    if (!(await featureFlagOn(s, "enable_refund_admin_ui"))) {
      return {
        success: false as const,
        error_code: "REFUND_FEATURE_DISABLED",
        safe_message: "واجهة الاسترداد معطلة",
      };
    }
    const { data: refund, error } = await s.rpc("request_recharge_refund", {
      _recharge_request_id: data.recharge_request_id,
      _refund_type: data.refund_type,
      _refund_scope: data.refund_scope,
      _requested_amount: data.requested_amount,
      _bonus_policy: data.bonus_policy ?? null,
      _reason: data.reason,
      _idempotency_key: data.idempotency_key,
    });
    if (error) {
      return {
        success: false as const,
        error_code: safeRpcError(error.message ?? ""),
        safe_message: error.message ?? "تعذّر إنشاء الاسترداد",
      };
    }
    return { success: true as const, data: refund };
  });

/* ---------------- lifecycle actions ---------------- */
const idInput = z.object({ refund_id: z.string().uuid(), reason: z.string().min(5).max(500) });
const idIdemInput = idInput.extend({ idempotency_key: z.string().min(8).max(80) });

async function runAction(
  supabase: any,
  userId: string,
  permKey: string,
  rpcName: string,
  args: Record<string, unknown>,
) {
  if (!(await checkPermission(supabase, userId, permKey))) {
    return {
      success: false as const,
      error_code: "PERMISSION_DENIED",
      safe_message: "لا تملك صلاحية هذا الإجراء",
    };
  }
  const { data: res, error } = await supabase.rpc(rpcName, args);
  if (error) {
    return {
      success: false as const,
      error_code: safeRpcError(error.message ?? ""),
      safe_message: error.message ?? "فشل التنفيذ",
    };
  }
  return { success: true as const, data: res };
}

export const approveRechargeRefundFn = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => idInput.parse(raw))
  .handler(async ({ data, context }) =>
    runAction(
      context.supabase as any,
      context.userId,
      "recharge_refunds.approve",
      "approve_recharge_refund",
      { _refund_id: data.refund_id, _reason: data.reason },
    ),
  );

export const secondApproveRechargeRefundFn = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => idInput.parse(raw))
  .handler(async ({ data, context }) =>
    runAction(
      context.supabase as any,
      context.userId,
      "recharge_refunds.second_approve",
      "second_approve_recharge_refund",
      { _refund_id: data.refund_id, _reason: data.reason },
    ),
  );

export const rejectRechargeRefundFn = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => idInput.parse(raw))
  .handler(async ({ data, context }) =>
    runAction(
      context.supabase as any,
      context.userId,
      "recharge_refunds.reject",
      "reject_recharge_refund",
      { _refund_id: data.refund_id, _reason: data.reason },
    ),
  );

export const cancelRechargeRefundFn = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => idInput.parse(raw))
  .handler(async ({ data, context }) =>
    runAction(
      context.supabase as any,
      context.userId,
      "recharge_refunds.cancel",
      "cancel_recharge_refund",
      { _refund_id: data.refund_id, _reason: data.reason },
    ),
  );

export const executeRechargeRefundFn = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => idIdemInput.parse(raw))
  .handler(async ({ data, context }) => {
    const s: any = context.supabase;
    if (!(await checkPermission(s, context.userId, "recharge_refunds.execute"))) {
      return {
        success: false as const,
        error_code: "PERMISSION_DENIED",
        safe_message: "لا تملك صلاحية التنفيذ",
      };
    }
    if (!(await featureFlagOn(s, "enable_refund_execution"))) {
      return {
        success: false as const,
        error_code: "REFUND_EXECUTION_DISABLED",
        safe_message: "تنفيذ الاسترداد معطل",
      };
    }
    return runAction(s, context.userId, "recharge_refunds.execute", "execute_recharge_refund", {
      _refund_id: data.refund_id,
      _reason: data.reason,
      _idempotency_key: data.idempotency_key,
    });
  });

/* ---------------- checkRefundEligibility for a recharge request ---------------- */
export const checkRefundEligibility = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => z.object({ recharge_request_id: z.string().uuid() }).parse(raw))
  .handler(async ({ data, context }) => {
    const s: any = context.supabase;
    const canRequest = await checkPermission(s, context.userId, "recharge_refunds.request");
    const { data: req } = await s
      .from("recharge_requests")
      .select("id,status,final_amount,currency_code")
      .eq("id", data.recharge_request_id)
      .maybeSingle();
    if (!req)
      return {
        success: false as const,
        error_code: "REQUEST_NOT_FOUND",
        safe_message: "الطلب غير موجود",
      };
    const { data: existing } = await s
      .from("recharge_refunds")
      .select("id,status,approved_amount")
      .eq("request_id", data.recharge_request_id);
    const activeStatuses = new Set([
      "requested",
      "pending_review",
      "pending_second_review",
      "approved",
      "processing_gateway",
      "gateway_confirmed",
      "reversing_wallet",
      "manual_review",
    ]);
    const rows = (existing ?? []) as Array<any>;
    const has_active = rows.some((r) => activeStatuses.has(r.status));
    const total_refunded = rows.reduce((sum, r) => sum + Number(r.approved_amount ?? 0), 0);
    const remaining = Math.max(0, Number(req.final_amount ?? 0) - total_refunded);
    return {
      success: true as const,
      data: {
        can_request: canRequest && req.status === "completed" && !has_active && remaining > 0,
        can_request_permission: canRequest,
        request_status: req.status,
        currency: req.currency_code,
        original_amount: Number(req.final_amount ?? 0),
        already_refunded: total_refunded,
        remaining_refundable: remaining,
        has_active_refund: has_active,
        existing_refunds: rows,
      },
    };
  });
