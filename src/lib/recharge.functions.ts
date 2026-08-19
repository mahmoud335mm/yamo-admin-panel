/**
 * Recharge request server functions (5B-3).
 * All auth-gated via requireSupabaseAuth. Signed URLs are minted server-side
 * with the service-role client after the SECURITY DEFINER RPC authorizes.
 * Never returns storage paths, buckets, secret refs, or provider secrets.
 */
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);
const MAX_BYTES = 10 * 1024 * 1024; // 10 MB

/* ------------------------------------------------------------------ */
/* resolve_payment_instructions — safe display data, no secret refs     */
/* ------------------------------------------------------------------ */
export const resolvePaymentInstructions = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => z.object({ request_id: z.string().uuid() }).parse(raw))
  .handler(async ({ data, context }) => {
    const { data: rpc, error } = await context.supabase.rpc("resolve_payment_instructions", {
      _request_id: data.request_id,
    });
    if (error) {
      const msg = error.message ?? "";
      let code = "INTERNAL";
      if (msg.includes("NOT_AUTHENTICATED")) code = "AUTH_REQUIRED";
      else if (msg.includes("NOT_FOUND")) code = "REQUEST_NOT_FOUND";
      else if (msg.includes("FORBIDDEN")) code = "REQUEST_NOT_OWNED";
      else if (msg.includes("EXPIRED")) code = "REQUEST_EXPIRED";
      else if (msg.includes("INACTIVE")) code = "PAYMENT_METHOD_INACTIVE";
      else if (msg.includes("UNAVAILABLE")) code = "PAYMENT_ACCOUNT_UNAVAILABLE";
      else if (msg.includes("NOT_CONFIGURED")) code = "INSTRUCTIONS_NOT_CONFIGURED";
      else if (msg.includes("INVALID_STATE")) code = "INVALID_REQUEST_STATE";
      return { success: false as const, error_code: code, safe_message: msg };
    }
    return { success: true as const, data: rpc };
  });

/* ------------------------------------------------------------------ */
/* create_recharge_receipt_upload — validates MIME/size, returns URL    */
/* ------------------------------------------------------------------ */
export const createReceiptUpload = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        request_id: z.string().uuid(),
        mime_type: z.string().min(1),
        size_bytes: z.number().int().positive(),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    if (!ALLOWED_MIME.has(data.mime_type)) {
      return {
        success: false as const,
        error_code: "MIME_NOT_ALLOWED",
        safe_message: "نوع الملف غير مسموح به",
      };
    }
    if (data.size_bytes > MAX_BYTES) {
      return {
        success: false as const,
        error_code: "FILE_TOO_LARGE",
        safe_message: "حجم الملف يتجاوز الحد المسموح (10MB)",
      };
    }

    const { data: rpc, error } = await context.supabase.rpc("create_recharge_receipt_upload", {
      _request_id: data.request_id,
      _mime: data.mime_type,
      _size_bytes: data.size_bytes,
    });
    if (error || !rpc || !Array.isArray(rpc) || rpc.length === 0) {
      const msg = error?.message ?? "unknown";
      return {
        success: false as const,
        error_code: msg.includes("FORBIDDEN")
          ? "REQUEST_NOT_OWNED"
          : msg.includes("STATE")
            ? "INVALID_REQUEST_STATE"
            : "UPLOAD_INIT_FAILED",
        safe_message: msg,
      };
    }
    const row = rpc[0] as {
      receipt_id: string;
      storage_bucket: string;
      storage_object_path: string;
    };

    // Mint short-lived signed upload URL server-side using service role.
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: signed, error: signErr } = await supabaseAdmin.storage
      .from(row.storage_bucket)
      .createSignedUploadUrl(row.storage_object_path);

    if (signErr || !signed) {
      return {
        success: false as const,
        error_code: "UPLOAD_SIGN_FAILED",
        safe_message: signErr?.message ?? "sign_failed",
      };
    }
    return {
      success: true as const,
      data: {
        receipt_id: row.receipt_id,
        upload_url: signed.signedUrl,
        upload_token: signed.token,
        expires_in: 120,
      },
    };
  });

/* ------------------------------------------------------------------ */
/* get_recharge_receipt_url — signed download URL, admin audit trail   */
/* ------------------------------------------------------------------ */
export const getReceiptSignedUrl = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        receipt_id: z.string().uuid(),
        reason: z.string().min(5).max(500).optional(),
        ttl_seconds: z.number().int().min(30).max(300).default(60),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    const { data: rpc, error } = await context.supabase.rpc("get_recharge_receipt_signed_url", {
      _receipt_id: data.receipt_id,
      _ttl_seconds: data.ttl_seconds,
      _reason: data.reason ?? null,
    });
    if (error || !rpc || !Array.isArray(rpc) || rpc.length === 0) {
      const msg = error?.message ?? "";
      return {
        success: false as const,
        error_code: msg.includes("REASON_REQUIRED")
          ? "REASON_REQUIRED"
          : msg.includes("FORBIDDEN")
            ? "FORBIDDEN"
            : msg.includes("NOT_FOUND")
              ? "RECEIPT_NOT_FOUND"
              : "SIGN_FAILED",
        safe_message: msg.includes("REASON_REQUIRED")
          ? "السبب مطلوب (5 أحرف على الأقل)"
          : "تعذّر إنشاء الرابط",
      };
    }
    const row = rpc[0] as {
      storage_bucket: string;
      storage_object_path: string;
      ttl_seconds: number;
    };

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: signed, error: signErr } = await supabaseAdmin.storage
      .from(row.storage_bucket)
      .createSignedUrl(row.storage_object_path, row.ttl_seconds);
    if (signErr || !signed) {
      return {
        success: false as const,
        error_code: "SIGN_FAILED",
        safe_message: signErr?.message ?? "sign_failed",
      };
    }
    return {
      success: true as const,
      data: { signed_url: signed.signedUrl, expires_in: row.ttl_seconds },
    };
  });

/* ------------------------------------------------------------------ */
/* list_recharge_requests — server-side pagination + filters            */
/* ------------------------------------------------------------------ */
const LIST_FILTERS = z.object({
  page: z.number().int().min(1).default(1),
  page_size: z.number().int().min(10).max(100).default(25),
  user_id: z.string().uuid().optional(),
  reference: z.string().max(120).optional(),
  status: z.string().max(40).optional(),
  payment_status: z.string().max(40).optional(),
  gateway_id: z.string().uuid().optional(),
  payment_method_id: z.string().uuid().optional(),
  mode: z.enum(["test", "live"]).optional(),
  currency: z.string().max(8).optional(),
  has_receipt: z.boolean().optional(),
  needs_review: z.boolean().optional(),
  date_from: z.string().datetime().optional(),
  date_to: z.string().datetime().optional(),
  sort: z.enum(["created_at", "final_amount", "status"]).default("created_at"),
  order: z.enum(["asc", "desc"]).default("desc"),
});

export const listRechargeRequests = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => LIST_FILTERS.parse(raw ?? {}))
  .handler(async ({ data, context }) => {
    // gate via read permission (RLS also enforces, but fail fast for clarity)
    const { data: perm } = await context.supabase.rpc("has_permission", {
      _user_id: context.userId,
      _permission: "recharge_requests.read",
    });
    if (!perm) {
      return {
        success: false as const,
        error_code: "FORBIDDEN",
        safe_message: "recharge_requests.read required",
      };
    }

    const from = (data.page - 1) * data.page_size;
    const to = from + data.page_size - 1;

    let q = context.supabase
      .from("recharge_requests")
      .select(
        "id,request_reference,user_id,package_id,coin_amount,bonus_amount,total_coins,price,final_amount,currency_code,country_code,payment_gateway_id,payment_method_id,payment_gateway_mode,external_reference,status,payment_status,created_at,updated_at,expires_at,paid_at,completed_at,failure_code",
        { count: "exact" },
      );

    if (data.user_id) q = q.eq("user_id", data.user_id);
    if (data.status) q = q.eq("status", data.status as never);
    if (data.payment_status) q = q.eq("payment_status", data.payment_status);
    if (data.gateway_id) q = q.eq("payment_gateway_id", data.gateway_id);
    if (data.payment_method_id) q = q.eq("payment_method_id", data.payment_method_id);
    if (data.mode) q = q.eq("payment_gateway_mode", data.mode);
    if (data.currency) q = q.eq("currency_code", data.currency);
    if (data.date_from) q = q.gte("created_at", data.date_from);
    if (data.date_to) q = q.lte("created_at", data.date_to);
    if (data.reference) {
      const term = data.reference.replace(/[,%()]/g, "");
      q = q.or(`request_reference.ilike.%${term}%,external_reference.ilike.%${term}%`);
    }

    q = q.order(data.sort, { ascending: data.order === "asc" }).range(from, to);

    const { data: rows, count, error } = await q;
    if (error) {
      return {
        success: false as const,
        error_code: "LIST_FAILED",
        safe_message: error.message,
      };
    }
    return {
      success: true as const,
      data: {
        rows: rows ?? [],
        total: count ?? 0,
        page: data.page,
        page_size: data.page_size,
      },
    };
  });

/* ------------------------------------------------------------------ */
/* get_recharge_request_detail — merged detail bundle for the drawer   */
/* ------------------------------------------------------------------ */
export const getRechargeRequestDetail = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => z.object({ request_id: z.string().uuid() }).parse(raw))
  .handler(async ({ data, context }) => {
    const { data: perm } = await context.supabase.rpc("has_permission", {
      _user_id: context.userId,
      _permission: "recharge_requests.read",
    });
    if (!perm) {
      return {
        success: false as const,
        error_code: "FORBIDDEN",
        safe_message: "recharge_requests.read required",
      };
    }
    const [req, events, receipts, ledger, webhooks, audits] = await Promise.all([
      context.supabase
        .from("recharge_requests")
        .select("*")
        .eq("id", data.request_id)
        .maybeSingle(),
      context.supabase
        .from("recharge_request_events")
        .select("*")
        .eq("request_id", data.request_id)
        .order("created_at", { ascending: true }),
      context.supabase
        .from("recharge_receipts")
        .select(
          "id,receipt_number,status,malware_scan_status,is_quarantined,mime_type,size_bytes,sha256_hash,paid_amount,currency,payment_reference,sender_name,paid_at,submitted_at,reviewed_at,reviewed_by,review_decision,review_reason,supersedes_receipt_id,original_filename_masked,created_at",
        )
        .eq("request_id", data.request_id)
        .order("created_at", { ascending: false }),
      context.supabase
        .from("wallet_ledger")
        .select("*")
        .eq("reference", data.request_id)
        .order("created_at", { ascending: true }),
      context.supabase
        .from("payment_webhooks")
        .select("*")
        .contains("payload", { recharge_request_id: data.request_id })
        .order("created_at", { ascending: false })
        .limit(50),
      context.supabase
        .from("audit_logs")
        .select("id,actor_email,action,entity_type,metadata,created_at")
        .eq("entity_type", "recharge_request")
        .eq("entity_id", data.request_id)
        .order("created_at", { ascending: false })
        .limit(100),
    ]);

    if (!req.data) {
      return {
        success: false as const,
        error_code: "REQUEST_NOT_FOUND",
        safe_message: "not_found",
      };
    }
    return {
      success: true as const,
      data: {
        request: req.data,
        events: events.data ?? [],
        receipts: receipts.data ?? [],
        ledger: ledger.data ?? [],
        webhooks: (webhooks.data ?? []).map((w) => ({
          ...w,
          payload: null, // redact raw payload in list view
        })),
        audits: audits.data ?? [],
      },
    };
  });

/* ------------------------------------------------------------------ */
/* review_recharge_receipt / fail / cancel — thin wrappers              */
/* ------------------------------------------------------------------ */
export const reviewReceipt = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        receipt_id: z.string().uuid(),
        decision: z.enum(["approve", "reject", "request_more_information"]),
        reason: z.string().min(5).max(1000),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    const { error } = await context.supabase.rpc("review_recharge_receipt", {
      _receipt_id: data.receipt_id,
      _decision: data.decision,
      _reason: data.reason,
    });
    if (error) {
      return {
        success: false as const,
        error_code: "REVIEW_FAILED",
        safe_message: error.message,
      };
    }
    return { success: true as const };
  });

export const failRechargeRequest = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        request_id: z.string().uuid(),
        reason: z.string().min(5).max(500),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    const { error } = await context.supabase.rpc("fail_recharge_request", {
      _request_id: data.request_id,
      _reason: data.reason,
    });
    if (error)
      return {
        success: false as const,
        error_code: "FAIL_ACTION_FAILED",
        safe_message: error.message,
      };
    return { success: true as const };
  });

export const cancelRechargeRequest = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        request_id: z.string().uuid(),
        reason: z.string().min(5).max(500),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    const { error } = await context.supabase.rpc("cancel_recharge_request", {
      _request_id: data.request_id,
      _reason: data.reason,
    });
    if (error)
      return {
        success: false as const,
        error_code: "CANCEL_FAILED",
        safe_message: error.message,
      };
    return { success: true as const };
  });

/* ------------------------------------------------------------------ */
/* retry_payment_webhook — إعادة معالجة آمنة لسجل webhook               */
/* ------------------------------------------------------------------ */
const WEBHOOK_ERROR_MAP: Record<string, string> = {
  FORBIDDEN: "لا تملك صلاحية إعادة المحاولة",
  REASON_REQUIRED_MIN_5: "السبب مطلوب (5 أحرف على الأقل)",
  IDEMPOTENCY_KEY_REQUIRED: "مفتاح idempotency مطلوب",
  WEBHOOK_NOT_FOUND: "الحدث غير موجود",
  INVALID_SIGNATURE_NOT_RETRIABLE: "توقيع غير صالح — لا يُعاد",
  WEBHOOK_PROCESSING_IN_PROGRESS: "معالجة جارية بالفعل",
  NOT_AUTHENTICATED: "الجلسة منتهية",
};

export const retryPaymentWebhook = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        webhook_id: z.string().uuid(),
        reason: z.string().min(5).max(500),
        idempotency_key: z.string().min(8).max(80),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    const { data: rpc, error } = await context.supabase.rpc("retry_payment_webhook", {
      _webhook_id: data.webhook_id,
      _reason: data.reason,
      _idempotency_key: data.idempotency_key,
    });
    if (error) {
      const msg = error.message ?? "";
      const code = Object.keys(WEBHOOK_ERROR_MAP).find((k) => msg.includes(k)) ?? "RETRY_FAILED";
      return {
        success: false as const,
        error_code: code,
        safe_message: WEBHOOK_ERROR_MAP[code] ?? "تعذّرت إعادة المحاولة",
      };
    }
    return {
      success: true as const,
      result: (rpc ?? {}) as {
        status?: string;
        webhook_id?: string;
        attempt_count?: number;
        related_request_id?: string | null;
      },
    };
  });

/* ------------------------------------------------------------------ */
/* verify_recharge_payment — إعادة التحقق من الدفع (Admin)              */
/* ------------------------------------------------------------------ */
const VERIFY_ERROR_MAP: Record<string, string> = {
  FORBIDDEN: "لا تملك صلاحية إعادة التحقق",
  REASON_REQUIRED_MIN_5: "السبب مطلوب (5 أحرف على الأقل)",
  IDEMPOTENCY_KEY_REQUIRED: "مفتاح idempotency مطلوب",
  INVALID_SOURCE: "مصدر التحقق غير صالح",
  REQUEST_NOT_FOUND: "الطلب غير موجود",
  REQUEST_EXPIRED: "انتهت صلاحية الطلب",
  REQUEST_CANCELLED: "الطلب ملغى",
  REQUEST_REFUNDED: "الطلب مسترد",
  PAYMENT_NOT_CONFIRMED: "لم يتم تأكيد الدفع",
  INVALID_SIGNATURE: "توقيع Webhook غير صالح",
  GATEWAY_MISMATCH: "بوابة الدفع لا تطابق الطلب",
  GATEWAY_MODE_MISMATCH: "وضع البوابة (test/live) لا يطابق",
  AMOUNT_MISMATCH: "المبلغ لا يطابق",
  CURRENCY_MISMATCH: "العملة لا تطابق",
  RECEIPT_NOT_APPROVED: "الإيصال غير معتمد",
  INVALID_STATE: "حالة الطلب لا تسمح بالتحقق",
};

export const verifyRechargePayment = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        request_id: z.string().uuid(),
        reason: z.string().min(5).max(500),
        idempotency_key: z.string().min(8).max(80),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    const { data: rpc, error } = await context.supabase.rpc("verify_recharge_payment", {
      _request_id: data.request_id,
      _source: "admin_retry",
      _reason: data.reason,
      _idempotency_key: data.idempotency_key,
    });
    if (error) {
      const msg = error.message ?? "";
      const code = Object.keys(VERIFY_ERROR_MAP).find((k) => msg.includes(k)) ?? "VERIFY_FAILED";
      return {
        success: false as const,
        error_code: code,
        safe_message: VERIFY_ERROR_MAP[code] ?? "فشل التحقق",
      };
    }
    const result = rpc as { status?: string; request_id?: string };
    return {
      success: true as const,
      status: result.status ?? "completed",
      request_id: result.request_id ?? data.request_id,
    };
  });

/* ------------------------------------------------------------------ */
/* Webhook list per request                                            */
/* ------------------------------------------------------------------ */
export const listRechargeWebhooks = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => z.object({ request_id: z.string().uuid() }).parse(raw))
  .handler(async ({ data, context }) => {
    const { data: rows, error } = await context.supabase.rpc("list_recharge_webhooks", {
      _request_id: data.request_id,
    });
    if (error) {
      return {
        success: false as const,
        error_code: error.message?.includes("FORBIDDEN") ? "FORBIDDEN" : "LIST_FAILED",
        safe_message: error.message?.includes("FORBIDDEN")
          ? "لا تملك صلاحية عرض الـ webhooks"
          : "تعذر جلب القائمة",
      };
    }
    // Supabase RPC payload is JSON-serializable but not represented in generated types.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return { success: true as const, webhooks: (rows ?? []) as any[] };
  });

/* ------------------------------------------------------------------ */
/* Redacted webhook detail                                             */
/* ------------------------------------------------------------------ */
export const getRedactedWebhookDetail = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) => z.object({ webhook_id: z.string().uuid() }).parse(raw))
  .handler(async ({ data, context }) => {
    const { data: rpc, error } = await context.supabase.rpc("get_redacted_webhook_detail", {
      _webhook_id: data.webhook_id,
    });
    if (error) {
      const msg = error.message ?? "";
      let code = "DETAIL_FAILED";
      if (msg.includes("FORBIDDEN")) code = "FORBIDDEN";
      else if (msg.includes("WEBHOOK_NOT_FOUND")) code = "WEBHOOK_NOT_FOUND";
      return {
        success: false as const,
        error_code: code,
        safe_message:
          code === "FORBIDDEN"
            ? "لا تملك صلاحية عرض تفاصيل الـ webhook"
            : code === "WEBHOOK_NOT_FOUND"
              ? "الحدث غير موجود"
              : "تعذر جلب التفاصيل",
      };
    }
    const { redactSensitiveData } = await import("./redact.server");
    const raw = rpc as Record<string, unknown> & { raw_payload?: unknown };
    const redactedPayload = redactSensitiveData(raw.raw_payload ?? {});
    const { raw_payload: _drop, ...rest } = raw;
    return {
      success: true as const,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      detail: { ...rest, redacted_payload: redactedPayload } as any,
    };
  });

/* ------------------------------------------------------------------ */
/* CSV export for recharge_requests                                    */
/* ------------------------------------------------------------------ */
export const exportRechargeRequestsCsv = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((raw: unknown) =>
    z
      .object({
        status: z.array(z.string()).optional(),
        gateway_mode: z.enum(["test", "live"]).optional(),
        gateway_id: z.string().uuid().optional(),
        from: z.string().datetime().optional(),
        to: z.string().datetime().optional(),
        search: z.string().max(120).optional(),
        limit: z.number().int().min(1).max(5000).default(1000),
      })
      .parse(raw),
  )
  .handler(async ({ data, context }) => {
    let q = context.supabase
      .from("recharge_requests")
      .select(
        `id, request_reference, user_id, package_id, coin_amount, bonus_amount, total_coins,
         final_amount, price, currency_code, payment_gateway_id, payment_method_id,
         payment_gateway_mode, payment_status, status, country_code,
         external_reference, failure_code, created_at, completed_at,
         package_snapshot`,
      )
      .order("created_at", { ascending: false })
      .limit(data.limit);

    // Generated enum types lag behind the server-side status set.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    if (data.status?.length) q = q.in("status", data.status as any);
    if (data.gateway_mode) q = q.eq("payment_gateway_mode", data.gateway_mode);
    if (data.gateway_id) q = q.eq("payment_gateway_id", data.gateway_id);
    if (data.from) q = q.gte("created_at", data.from);
    if (data.to) q = q.lte("created_at", data.to);
    if (data.search) q = q.ilike("request_reference", `%${data.search}%`);

    const { data: rows, error } = await q;
    if (error) {
      return {
        success: false as const,
        error_code: "EXPORT_FAILED",
        safe_message: "تعذر إنشاء التصدير",
      };
    }

    const { toCsv } = await import("./redact.server");
    const maskExternal = (s: string | null): string => {
      if (!s) return "";
      if (s.length <= 8) return "•".repeat(s.length);
      return `${s.slice(0, 4)}…${s.slice(-4)}`;
    };

    const headers = [
      "request_reference",
      "user_id",
      "package_name",
      "coin_amount",
      "bonus_amount",
      "total_coins",
      "final_amount",
      "currency",
      "gateway_mode",
      "payment_status",
      "request_status",
      "country",
      "external_reference",
      "failure_code",
      "created_at",
      "completed_at",
    ];

    const list = (rows ?? []) as Array<Record<string, unknown>>;
    const csvRows: (string | number | null | undefined)[][] = list.map((r) => {
      const pkg = (r.package_snapshot ?? {}) as Record<string, unknown>;
      return [
        String(r.request_reference ?? ""),
        String(r.user_id ?? ""),
        String(pkg.name_ar ?? pkg.name ?? ""),
        Number(r.coin_amount ?? 0),
        Number(r.bonus_amount ?? 0),
        Number(r.total_coins ?? 0),
        Number(r.final_amount ?? r.price ?? 0),
        String(r.currency_code ?? ""),
        String(r.payment_gateway_mode ?? ""),
        String(r.payment_status ?? ""),
        String(r.status ?? ""),
        String(r.country_code ?? ""),
        maskExternal((r.external_reference as string) ?? null),
        String(r.failure_code ?? ""),
        String(r.created_at ?? ""),
        String(r.completed_at ?? ""),
      ];
    });

    const csv = toCsv(headers, csvRows);

    // audit
    await context.supabase.rpc("log_recharge_export", {
      _row_count: list.length,
      _filters: data,
      _export_type: "csv",
    });

    return {
      success: true as const,
      row_count: list.length,
      filename: `recharge_requests_${new Date().toISOString().slice(0, 10)}.csv`,
      csv,
    };
  });
