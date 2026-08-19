import { createFileRoute, Link, useParams } from "@tanstack/react-router";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { PermissionGuard } from "@/components/permission-guard";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import {
  ArrowRight,
  Receipt,
  Clock,
  Wallet,
  ShieldAlert,
  FileText,
  CreditCard,
  Eye,
  XCircle,
  AlertTriangle,
  RefreshCw,
  ShieldCheck,
} from "lucide-react";
import { fmtDate } from "@/lib/charging-utils";
import { CreateRefundButton } from "@/components/create-refund-button";
import {
  getRechargeRequestDetail,
  getReceiptSignedUrl,
  reviewReceipt,
  failRechargeRequest,
  cancelRechargeRequest,
  retryPaymentWebhook,
  verifyRechargePayment,
  listRechargeWebhooks,
  getRedactedWebhookDetail,
} from "@/lib/recharge.functions";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";

export const Route = createFileRoute(
  "/_authenticated/finance/recharge-requests/$id",
)({
  component: () => (
    <PermissionGuard permission="recharge_requests.read">
      <DetailPage />
    </PermissionGuard>
  ),
});

type Snapshot = Record<string, unknown> | null;

const STATUS_CLS: Record<string, string> = {
  completed: "bg-emerald-500/15 text-emerald-500",
  failed: "bg-destructive/15 text-destructive",
  cancelled: "bg-muted text-muted-foreground",
  refunded: "bg-orange-500/15 text-orange-500",
};

function DetailPage() {
  const { id } = useParams({ from: "/_authenticated/finance/recharge-requests/$id" });
  const fetchDetail = useServerFn(getRechargeRequestDetail);
  const q = useQuery({
    queryKey: ["rr_detail", id],
    queryFn: () => fetchDetail({ data: { request_id: id } }),
  });

  if (q.isLoading) return <Skeleton className="h-96" />;
  if (!q.data) return <div className="text-destructive">تعذر التحميل.</div>;
  if (!q.data.success)
    return (
      <div className="text-destructive space-y-2">
        <div>{q.data.error_code}: {q.data.safe_message}</div>
        <Button variant="outline" size="sm" onClick={() => q.refetch()}>
          إعادة المحاولة
        </Button>
      </div>
    );

  const { request, events, receipts, ledger, webhooks, audits } = q.data.data;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link to="/finance/recharge-requests">
          <Button variant="ghost" size="sm">
            <ArrowRight className="h-4 w-4 ml-1" /> رجوع
          </Button>
        </Link>
        <div className="flex-1">
          <h1 className="text-xl font-bold font-mono">{request.request_reference}</h1>
          <p className="text-xs text-muted-foreground">
            {request.id} · {fmtDate(request.created_at)}
          </p>
        </div>
        <Badge className={STATUS_CLS[request.status] ?? "bg-blue-500/15 text-blue-500"}>
          {request.status}
        </Badge>
        <Badge variant={request.payment_gateway_mode === "test" ? "outline" : "secondary"}>
          {request.payment_gateway_mode}
        </Badge>
        <CreateRefundButton rechargeRequestId={request.id} />
      </div>

      <Tabs defaultValue="overview">
        <TabsList className="flex-wrap">
          <TabsTrigger value="overview"><FileText className="h-3.5 w-3.5 ml-1" />نظرة عامة</TabsTrigger>
          <TabsTrigger value="payment"><CreditCard className="h-3.5 w-3.5 ml-1" />الدفع</TabsTrigger>
          <TabsTrigger value="receipt"><Receipt className="h-3.5 w-3.5 ml-1" />الإيصال</TabsTrigger>
          <TabsTrigger value="timeline"><Clock className="h-3.5 w-3.5 ml-1" />Timeline</TabsTrigger>
          <TabsTrigger value="webhooks"><RefreshCw className="h-3.5 w-3.5 ml-1" />Webhooks</TabsTrigger>
          <TabsTrigger value="ledger"><Wallet className="h-3.5 w-3.5 ml-1" />Ledger</TabsTrigger>
          <TabsTrigger value="audit"><ShieldAlert className="h-3.5 w-3.5 ml-1" />Audit</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-4">
          <OverviewTab request={request} />
          <ActionsBar request={request} onChanged={() => q.refetch()} />
        </TabsContent>

        <TabsContent value="payment"><PaymentTab request={request} webhooks={webhooks} /></TabsContent>
        <TabsContent value="receipt"><ReceiptTab receipts={receipts} onChanged={() => q.refetch()} /></TabsContent>
        <TabsContent value="timeline"><TimelineTab events={events} /></TabsContent>
        <TabsContent value="webhooks"><WebhooksTab requestId={request.id} /></TabsContent>
        <TabsContent value="ledger"><LedgerTab ledger={ledger} /></TabsContent>
        <TabsContent value="audit"><AuditTab audits={audits} /></TabsContent>
      </Tabs>
    </div>
  );
}

/* ------------------------------ tabs ---------------------------------- */

function OverviewTab({ request }: { request: any }) {
  const pkg = (request.package_snapshot ?? {}) as Record<string, unknown>;
  const price = (request.price_snapshot ?? {}) as Record<string, unknown>;
  return (
    <div className="grid gap-4 md:grid-cols-3">
      <Card>
        <CardHeader><CardTitle className="text-sm">الطلب</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-sm">
          <Stat label="User ID" value={<Link to="/users/$id" params={{ id: request.user_id }} className="text-primary hover:underline font-mono text-xs">{request.user_id.slice(0, 12)}…</Link>} />
          <Stat label="حالة الطلب" value={request.status} />
          <Stat label="حالة الدفع" value={request.payment_status} />
          <Stat label="External Ref" value={request.external_reference ?? "—"} />
          <Stat label="Provider Payment ID" value={request.provider_payment_id ? mask(request.provider_payment_id) : "—"} />
          <Stat label="ينتهي في" value={request.expires_at ? fmtDate(request.expires_at) : "—"} />
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle className="text-sm">Package Snapshot</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-sm">
          <Stat label="اسم الباقة" value={String(pkg.name_ar ?? pkg.name ?? "—")} />
          <Stat label="كوينز أساسية" value={request.coin_amount?.toLocaleString?.() ?? "—"} />
          <Stat label="Bonus" value={String(request.bonus_amount)} />
          <Stat label="الإجمالي" value={String(request.total_coins ?? "—")} />
          <Stat label="الدولة" value={request.country_code ?? "—"} />
          <Stat label="العملة" value={request.currency_code} />
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle className="text-sm">Price Snapshot</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-sm">
          <Stat label="Base" value={String(request.base_price ?? "—")} />
          <Stat label="Discount" value={String(request.discount_amount)} />
          <Stat label="Gateway Fee" value={String(request.gateway_fee)} />
          <Stat label="Method Fee" value={String(request.payment_method_fee)} />
          <Stat label="Tax" value={String(request.tax_amount)} />
          <Stat label="Final" value={<strong>{String(request.final_amount ?? request.price)} {request.currency_code}</strong>} />
          <Stat label="Price Rule" value={<span className="font-mono text-xs">{request.price_rule_id?.slice(0, 8) ?? "—"} · v{String(price.version ?? "—")}</span>} />
        </CardContent>
      </Card>
    </div>
  );
}

function PaymentTab({ request, webhooks }: { request: any; webhooks: any[] }) {
  const { has } = usePermissions();
  const retryFn = useServerFn(retryPaymentWebhook);
  const qc = useQueryClient();
  const [retryOn, setRetryOn] = useState<string | null>(null);
  const [reason, setReason] = useState("");

  const mut = useMutation({
    mutationFn: async ({ id, reason }: { id: string; reason: string }) => {
      const key = `retry_wh_${id}_${Date.now()}`;
      const r = await retryFn({
        data: { webhook_id: id, reason, idempotency_key: key },
      });
      if (!r.success) throw new Error(r.safe_message);
      return r.result;
    },
    onSuccess: (r) => {
      toast.success(`تمت إعادة المحاولة: ${r?.status ?? "started"}`);
      setRetryOn(null);
      setReason("");
      qc.invalidateQueries({ queryKey: ["rr_detail", request.id] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader><CardTitle className="text-sm">وسيلة الدفع</CardTitle></CardHeader>
        <CardContent className="grid gap-2 md:grid-cols-2 text-sm">
          <Stat label="Gateway ID" value={<span className="font-mono text-xs">{request.payment_gateway_id?.slice(0, 12) ?? "—"}</span>} />
          <Stat label="Method ID" value={<span className="font-mono text-xs">{request.payment_method_id?.slice(0, 12) ?? "—"}</span>} />
          <Stat label="Mode" value={request.payment_gateway_mode} />
          <Stat label="Payment Account Ref" value={request.payment_account_reference ? mask(request.payment_account_reference) : "—"} />
          <Stat label="External Ref" value={request.external_reference ?? "—"} />
          <Stat label="Provider Payment ID" value={request.provider_payment_id ? mask(request.provider_payment_id) : "—"} />
          <Stat label="Failure Code" value={request.failure_code ?? "—"} />
          <Stat label="Failure Reason" value={request.failure_reason ? String(request.failure_reason).slice(0, 120) : "—"} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">Webhooks المرتبطة ({webhooks.length})</CardTitle></CardHeader>
        <CardContent>
          {webhooks.length === 0 ? (
            <p className="text-xs text-muted-foreground">لا توجد webhooks.</p>
          ) : (
            <Table>
              <TableHeader><TableRow>
                <TableHead>Event</TableHead><TableHead>Signature</TableHead>
                <TableHead>الحالة</TableHead><TableHead>محاولات</TableHead>
                <TableHead>التاريخ</TableHead><TableHead className="text-left"></TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {webhooks.map((w) => {
                  const canRetry =
                    has("payment_webhooks.retry") &&
                    w.signature_valid !== false &&
                    !(w.processed === true && w.processing_state === "processed");
                  return (
                    <TableRow key={w.id}>
                      <TableCell className="text-xs">{w.event_type}</TableCell>
                      <TableCell>
                        {w.signature_valid ? (
                          <Badge className="bg-emerald-500/15 text-emerald-500">صحيح</Badge>
                        ) : (
                          <Badge variant="destructive">فشل</Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-xs">{w.processing_state ?? w.processing_status ?? "—"}</TableCell>
                      <TableCell className="text-xs font-mono">{w.retry_count ?? 0}</TableCell>
                      <TableCell className="text-xs">{fmtDate(w.created_at)}</TableCell>
                      <TableCell>
                        {canRetry && (
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => setRetryOn(w.id)}
                          >
                            <RefreshCw className="h-3.5 w-3.5 ml-1" /> إعادة
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {retryOn && (
        <Dialog open onOpenChange={() => setRetryOn(null)}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>إعادة معالجة Webhook</DialogTitle>
              <DialogDescription>
                يتطلب سببًا موثقًا (5 أحرف على الأقل). لن تُعاد المعالجة إن كان
                التوقيع غير صالح.
              </DialogDescription>
            </DialogHeader>
            <Textarea
              placeholder="السبب"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
            <DialogFooter>
              <Button variant="ghost" onClick={() => setRetryOn(null)}>
                إلغاء
              </Button>
              <Button
                disabled={reason.trim().length < 5 || mut.isPending}
                onClick={() =>
                  mut.mutate({ id: retryOn, reason: reason.trim() })
                }
              >
                تأكيد
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}

function ReceiptTab({
  receipts,
  onChanged,
}: {
  receipts: any[];
  onChanged: () => void;
}) {
  const { has } = usePermissions();
  const sign = useServerFn(getReceiptSignedUrl);
  const review = useServerFn(reviewReceipt);
  const [openReview, setOpenReview] = useState<{
    receiptId: string;
    decision: "approve" | "reject" | "request_more_information";
  } | null>(null);
  const [reason, setReason] = useState("");

  const viewReceipt = async (receiptId: string) => {
    const res = await sign({ data: { receipt_id: receiptId, reason: "admin viewing receipt", ttl_seconds: 60 } });
    if (!res.success) {
      toast.error(res.safe_message);
      return;
    }
    window.open(res.data.signed_url, "_blank", "noopener,noreferrer");
  };

  const reviewMut = useMutation({
    mutationFn: async (input: {
      receipt_id: string;
      decision: "approve" | "reject" | "request_more_information";
      reason: string;
    }) => {
      const r = await review({ data: input });
      if (!r.success) throw new Error(r.safe_message);
    },
    onSuccess: () => {
      toast.success("تم تنفيذ القرار");
      setOpenReview(null);
      setReason("");
      onChanged();
    },
    onError: (e: Error) => toast.error(e.message),
  });

  if (receipts.length === 0)
    return (
      <Card>
        <CardContent className="py-8 text-center text-sm text-muted-foreground">
          لم يُرفع أي إيصال بعد.
        </CardContent>
      </Card>
    );

  return (
    <>
      <div className="space-y-3">
        {receipts.map((r, idx) => (
          <Card key={r.id}>
            <CardHeader className="pb-3">
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="text-sm">
                    الإيصال {idx === 0 ? "الحالي" : `#${idx + 1}`}
                    {r.supersedes_receipt_id && (
                      <Badge variant="outline" className="mr-2 text-xs">بديل</Badge>
                    )}
                  </CardTitle>
                  <p className="text-xs text-muted-foreground mt-1 font-mono">{r.id}</p>
                </div>
                <div className="flex items-center gap-2">
                  <ScanBadge scan={r.malware_scan_status} quarantined={r.is_quarantined} />
                  <Badge>{r.status}</Badge>
                </div>
              </div>
            </CardHeader>
            <CardContent className="grid gap-2 md:grid-cols-3 text-sm">
              <Stat label="Sender" value={r.sender_name ? mask(r.sender_name) : "—"} />
              <Stat label="Paid Amount" value={r.paid_amount ? `${r.paid_amount} ${r.currency ?? ""}` : "—"} />
              <Stat label="Payment Ref" value={r.payment_reference ?? "—"} />
              <Stat label="Paid At" value={r.paid_at ? fmtDate(r.paid_at) : "—"} />
              <Stat label="نوع الملف" value={r.mime_type ?? "—"} />
              <Stat label="الحجم" value={r.size_bytes ? `${(r.size_bytes / 1024).toFixed(1)} KB` : "—"} />
              <Stat label="Submitted" value={r.submitted_at ? fmtDate(r.submitted_at) : "—"} />
              <Stat label="Reviewed" value={r.reviewed_at ? fmtDate(r.reviewed_at) : "—"} />
              <Stat label="Decision" value={r.review_decision ?? "—"} />
              {r.review_reason && (
                <div className="md:col-span-3 rounded-md bg-muted/50 p-2 text-xs">
                  <strong>سبب المراجعة:</strong> {r.review_reason}
                </div>
              )}

              {has("recharge_receipts.read") && (
                <div className="md:col-span-3 flex flex-wrap gap-2 pt-2 border-t">
                  <Button size="sm" variant="outline" onClick={() => viewReceipt(r.id)}>
                    <Eye className="h-3.5 w-3.5 ml-1" /> عرض الإيصال
                  </Button>
                  {has("recharge_requests.approve") &&
                    (r.status === "submitted" || r.status === "under_review") && (
                      <>
                        <Button
                          size="sm"
                          className="bg-emerald-600 hover:bg-emerald-700"
                          onClick={() => setOpenReview({ receiptId: r.id, decision: "approve" })}
                        >
                          اعتماد
                        </Button>
                        <Button
                          size="sm"
                          variant="destructive"
                          onClick={() => setOpenReview({ receiptId: r.id, decision: "reject" })}
                        >
                          رفض
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() =>
                            setOpenReview({ receiptId: r.id, decision: "request_more_information" })
                          }
                        >
                          طلب معلومات إضافية
                        </Button>
                      </>
                    )}
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {openReview && (
        <Dialog open onOpenChange={() => setOpenReview(null)}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                {openReview.decision === "approve"
                  ? "اعتماد الإيصال"
                  : openReview.decision === "reject"
                    ? "رفض الإيصال"
                    : "طلب معلومات إضافية"}
              </DialogTitle>
              <DialogDescription>
                هذا القرار يُسجّل في سجل التدقيق ولا يمكن تعديله. اذكر السبب (5 أحرف على الأقل).
              </DialogDescription>
            </DialogHeader>
            <Textarea
              placeholder="السبب…"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
            <DialogFooter>
              <Button variant="ghost" onClick={() => setOpenReview(null)}>
                إلغاء
              </Button>
              <Button
                disabled={reason.trim().length < 5 || reviewMut.isPending}
                onClick={() =>
                  reviewMut.mutate({
                    receipt_id: openReview.receiptId,
                    decision: openReview.decision,
                    reason: reason.trim(),
                  })
                }
              >
                تأكيد
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </>
  );
}

function TimelineTab({ events }: { events: any[] }) {
  if (events.length === 0)
    return <p className="text-sm text-muted-foreground text-center py-8">لا توجد أحداث.</p>;
  return (
    <div className="space-y-2">
      {events.map((e) => (
        <div
          key={e.id}
          className="flex items-start gap-3 border-r-2 border-primary/40 pr-4 pb-3"
        >
          <div className="flex-1">
            <div className="text-sm font-medium">
              {e.from_status ?? "—"} → <strong>{e.to_status}</strong>
            </div>
            <div className="text-xs text-muted-foreground">{fmtDate(e.created_at)}</div>
            {e.note && <div className="text-xs mt-1">{e.note}</div>}
            {e.actor_id && (
              <div className="text-xs text-muted-foreground mt-1 font-mono">
                actor: {e.actor_id.slice(0, 8)}
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

function LedgerTab({ ledger }: { ledger: any[] }) {
  if (ledger.length === 0)
    return <p className="text-sm text-muted-foreground text-center py-8">لا توجد قيود.</p>;
  return (
    <Card>
      <CardContent className="pt-4">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Direction</TableHead>
              <TableHead>Amount</TableHead>
              <TableHead>Balance After</TableHead>
              <TableHead>Reason</TableHead>
              <TableHead>التاريخ</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {ledger.map((l) => (
              <TableRow key={l.id}>
                <TableCell>
                  <Badge
                    className={
                      l.direction === "credit"
                        ? "bg-emerald-500/15 text-emerald-500"
                        : "bg-destructive/15 text-destructive"
                    }
                  >
                    {l.direction}
                  </Badge>
                </TableCell>
                <TableCell
                  className={
                    l.direction === "credit"
                      ? "text-emerald-500 font-mono"
                      : "text-destructive font-mono"
                  }
                >
                  {l.direction === "credit" ? "+" : "-"}
                  {l.amount}
                </TableCell>
                <TableCell className="font-mono">{l.balance_after}</TableCell>
                <TableCell className="text-xs">{l.reason}</TableCell>
                <TableCell className="text-xs">{fmtDate(l.created_at)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

function AuditTab({ audits }: { audits: any[] }) {
  if (audits.length === 0)
    return <p className="text-sm text-muted-foreground text-center py-8">لا توجد سجلات تدقيق.</p>;
  return (
    <div className="space-y-2">
      {audits.map((a) => (
        <Card key={a.id}>
          <CardContent className="py-3 grid gap-1 text-sm">
            <div className="flex justify-between">
              <strong>{a.action}</strong>
              <span className="text-xs text-muted-foreground">{fmtDate(a.created_at)}</span>
            </div>
            <div className="text-xs text-muted-foreground">
              actor: {a.actor_email ?? "—"}
            </div>
            {a.metadata && Object.keys(a.metadata).length > 0 && (
              <pre className="text-xs bg-muted/40 rounded p-2 overflow-x-auto">
                {JSON.stringify(a.metadata, null, 2)}
              </pre>
            )}
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

/* -------------------------- action bar -------------------------------- */

function ActionsBar({ request, onChanged }: { request: any; onChanged: () => void }) {
  const { has } = usePermissions();
  const qc = useQueryClient();
  const failFn = useServerFn(failRechargeRequest);
  const cancelFn = useServerFn(cancelRechargeRequest);
  const verifyFn = useServerFn(verifyRechargePayment);
  const [action, setAction] = useState<"fail" | "cancel" | "verify" | null>(null);
  const [reason, setReason] = useState("");

  const mut = useMutation({
    mutationFn: async ({ kind, reason }: { kind: "fail" | "cancel" | "verify"; reason: string }) => {
      if (kind === "verify") {
        const key = `verify_${request.id}_${Date.now()}`;
        const r = await verifyFn({
          data: { request_id: request.id, reason, idempotency_key: key },
        });
        if (!r.success) throw new Error(r.safe_message);
        return r.status;
      }
      const call = kind === "fail" ? failFn : cancelFn;
      const r = await call({ data: { request_id: request.id, reason } });
      if (!r.success) throw new Error(r.safe_message);
      return "ok";
    },
    onSuccess: (s) => {
      toast.success(s === "completed" ? "تم التحقق واعتماد الطلب" : "تم التنفيذ");
      setAction(null);
      setReason("");
      qc.invalidateQueries({ queryKey: ["rr_detail", request.id] });
      onChanged();
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const isTerminal = ["completed", "refunded", "failed", "cancelled"].includes(request.status);
  const canCancel = ["created", "pending_payment"].includes(request.status);
  const canVerify =
    has("recharge_requests.verify") &&
    ["pending_payment", "payment_received", "under_review", "failed"].includes(request.status);

  if (isTerminal && !["failed"].includes(request.status)) {
    return (
      <Card>
        <CardContent className="py-3 text-xs text-muted-foreground text-center">
          هذا الطلب في حالة نهائية ({request.status}) — استخدم Refund من دفعة 5C.
        </CardContent>
      </Card>
    );
  }

  return (
    <>
      <Card>
        <CardHeader><CardTitle className="text-sm">إجراءات إدارية</CardTitle></CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {canVerify && (
            <Button variant="default" size="sm" onClick={() => setAction("verify")}>
              <ShieldCheck className="h-3.5 w-3.5 ml-1" /> إعادة التحقق من الدفع
            </Button>
          )}
          {has("recharge_requests.fail") && !isTerminal && (
            <Button variant="destructive" size="sm" onClick={() => setAction("fail")}>
              <XCircle className="h-3.5 w-3.5 ml-1" /> Fail Request
            </Button>
          )}
          {has("recharge_requests.cancel") && canCancel && (
            <Button variant="outline" size="sm" onClick={() => setAction("cancel")}>
              <AlertTriangle className="h-3.5 w-3.5 ml-1" /> Cancel
            </Button>
          )}
          <p className="text-xs text-muted-foreground w-full pt-2">
            الاعتماد يتم من تبويب "الإيصال" أو عبر إعادة التحقق من الدفع.
            <code className="mx-1">complete_recharge_request</code>
            يعمل من السيرفر فقط.
          </p>
        </CardContent>
      </Card>

      {action && (
        <Dialog open onOpenChange={() => setAction(null)}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                {action === "fail" ? "إفشال الطلب" : action === "cancel" ? "إلغاء الطلب" : "إعادة التحقق من الدفع"}
              </DialogTitle>
              <DialogDescription>
                {action === "fail"
                  ? "سيُوضع الطلب في حالة failed مع تسجيل السبب."
                  : action === "cancel"
                    ? "الإلغاء متاح فقط قبل تقديم الدفع. لن يتم تعديل الرصيد."
                    : "سيتم مطابقة المبلغ/العملة/البوابة وإكمال الطلب إن نجح التحقق."}
              </DialogDescription>
            </DialogHeader>
            <Textarea
              placeholder="السبب (5 أحرف على الأقل)"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
            <DialogFooter>
              <Button variant="ghost" onClick={() => setAction(null)}>
                إلغاء
              </Button>
              <Button
                variant={action === "fail" ? "destructive" : "default"}
                disabled={reason.trim().length < 5 || mut.isPending}
                onClick={() => mut.mutate({ kind: action, reason: reason.trim() })}
              >
                تأكيد
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </>
  );
}

/* ------------------------------ misc ---------------------------------- */

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="rounded-md border p-2">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="mt-1 text-sm font-medium truncate">{value}</div>
    </div>
  );
}

function ScanBadge({ scan, quarantined }: { scan: string; quarantined: boolean }) {
  if (quarantined) return <Badge variant="destructive">Quarantined</Badge>;
  if (scan === "clean") return <Badge className="bg-emerald-500/15 text-emerald-500">Clean</Badge>;
  if (scan === "infected") return <Badge variant="destructive">Infected</Badge>;
  return <Badge variant="outline">{scan}</Badge>;
}

function mask(s: string): string {
  if (!s) return "—";
  if (s.length <= 8) return "•".repeat(s.length);
  return `${s.slice(0, 4)}…${s.slice(-4)}`;
}

/* -------------------------- Webhooks Tab ------------------------------ */

const WH_STATE_CLS: Record<string, string> = {
  received: "bg-blue-500/15 text-blue-500",
  processing: "bg-amber-500/15 text-amber-500",
  processed: "bg-emerald-500/15 text-emerald-500",
  failed: "bg-destructive/15 text-destructive",
  skipped: "bg-muted text-muted-foreground",
};

function WebhooksTab({ requestId }: { requestId: string }) {
  const { has } = usePermissions();
  const listFn = useServerFn(listRechargeWebhooks);
  const [openId, setOpenId] = useState<string | null>(null);

  const q = useQuery({
    queryKey: ["rr_webhooks", requestId],
    queryFn: () => listFn({ data: { request_id: requestId } }),
    refetchInterval: 15000,
  });

  if (!has("payment_webhooks.read")) {
    return <p className="text-sm text-muted-foreground text-center py-6">لا تملك صلاحية عرض الـ webhooks.</p>;
  }
  if (q.isLoading) return <Skeleton className="h-40" />;
  if (!q.data?.success) {
    return <p className="text-sm text-destructive">{q.data?.safe_message ?? "تعذر التحميل"}</p>;
  }
  const rows = q.data.webhooks;

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <CardTitle className="text-sm">Webhooks ({rows.length})</CardTitle>
        <Button variant="outline" size="sm" onClick={() => q.refetch()}>
          <RefreshCw className="h-3.5 w-3.5 ml-1" /> تحديث
        </Button>
      </CardHeader>
      <CardContent>
        {rows.length === 0 ? (
          <p className="text-xs text-muted-foreground text-center py-6">لا توجد webhooks لهذا الطلب.</p>
        ) : (
          <Table>
            <TableHeader><TableRow>
              <TableHead>Event</TableHead>
              <TableHead>Gateway</TableHead>
              <TableHead>Mode</TableHead>
              <TableHead>Provider Event ID</TableHead>
              <TableHead>Signature</TableHead>
              <TableHead>الحالة</TableHead>
              <TableHead>محاولات</TableHead>
              <TableHead>مستلم</TableHead>
              <TableHead></TableHead>
            </TableRow></TableHeader>
            <TableBody>
              {rows.map((w: any) => (
                <TableRow key={w.id}>
                  <TableCell className="text-xs">{w.event_type}</TableCell>
                  <TableCell className="text-xs">{w.gateway_name ?? "—"}</TableCell>
                  <TableCell>
                    <Badge variant={w.gateway_mode === "test" ? "outline" : "secondary"}>
                      {w.gateway_mode}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-xs font-mono">
                    {w.provider_event_id ? String(w.provider_event_id).slice(0, 24) : "—"}
                  </TableCell>
                  <TableCell>
                    {w.signature_valid === true ? (
                      <Badge className="bg-emerald-500/15 text-emerald-500">صحيح</Badge>
                    ) : w.signature_valid === false ? (
                      <Badge variant="destructive">فشل</Badge>
                    ) : (
                      <Badge variant="outline">—</Badge>
                    )}
                  </TableCell>
                  <TableCell>
                    <Badge className={WH_STATE_CLS[w.processing_state] ?? "bg-muted"}>
                      {w.processing_state}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-xs font-mono">{w.retry_count ?? 0}</TableCell>
                  <TableCell className="text-xs">{fmtDate(w.received_at)}</TableCell>
                  <TableCell>
                    <Button variant="ghost" size="sm" onClick={() => setOpenId(w.id)}>
                      <Eye className="h-3.5 w-3.5" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>

      {openId && <WebhookDetailSheet webhookId={openId} onClose={() => setOpenId(null)} onChanged={() => q.refetch()} />}
    </Card>
  );
}

function WebhookDetailSheet({
  webhookId,
  onClose,
  onChanged,
}: {
  webhookId: string;
  onClose: () => void;
  onChanged: () => void;
}) {
  const { has } = usePermissions();
  const detailFn = useServerFn(getRedactedWebhookDetail);
  const retryFn = useServerFn(retryPaymentWebhook);
  const qc = useQueryClient();
  const [reason, setReason] = useState("");
  const [retryOpen, setRetryOpen] = useState(false);

  const q = useQuery({
    queryKey: ["wh_detail", webhookId],
    queryFn: () => detailFn({ data: { webhook_id: webhookId } }),
  });

  const mut = useMutation({
    mutationFn: async (r: string) => {
      const key = `retry_wh_${webhookId}_${Date.now()}`;
      const res = await retryFn({
        data: { webhook_id: webhookId, reason: r, idempotency_key: key },
      });
      if (!res.success) throw new Error(res.safe_message);
    },
    onSuccess: () => {
      toast.success("بدأت إعادة المعالجة");
      setRetryOpen(false);
      setReason("");
      qc.invalidateQueries({ queryKey: ["wh_detail", webhookId] });
      onChanged();
    },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <Sheet open onOpenChange={onClose}>
      <SheetContent className="sm:max-w-2xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>تفاصيل Webhook</SheetTitle>
          <SheetDescription className="font-mono text-xs">{webhookId}</SheetDescription>
        </SheetHeader>

        {q.isLoading && <Skeleton className="h-64 mt-4" />}
        {q.data && !q.data.success && (
          <p className="text-destructive mt-4">{q.data.safe_message}</p>
        )}
        {q.data?.success && (
          <div className="space-y-4 mt-4">
            <WebhookSummary d={q.data.detail as any} />
            <WebhookValidationChecks d={q.data.detail as any} />
            <WebhookRedactedPayload d={q.data.detail as any} />
            <WebhookRetryHistory d={q.data.detail as any} />

            {has("payment_webhooks.retry") &&
              (q.data.detail as any).signature_valid === true &&
              (q.data.detail as any).processing_state !== "processed" && (
                <Button onClick={() => setRetryOpen(true)}>
                  <RefreshCw className="h-3.5 w-3.5 ml-1" /> إعادة المعالجة
                </Button>
              )}
          </div>
        )}

        {retryOpen && (
          <Dialog open onOpenChange={() => setRetryOpen(false)}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>إعادة معالجة Webhook</DialogTitle>
                <DialogDescription>
                  السبب مطلوب (5 أحرف على الأقل). لن تُعاد المعالجة إن كان
                  التوقيع غير صالح أو تم الوصول للحد الأقصى للمحاولات.
                </DialogDescription>
              </DialogHeader>
              <Textarea value={reason} onChange={(e) => setReason(e.target.value)} placeholder="السبب" />
              <DialogFooter>
                <Button variant="ghost" onClick={() => setRetryOpen(false)}>إلغاء</Button>
                <Button disabled={reason.trim().length < 5 || mut.isPending} onClick={() => mut.mutate(reason.trim())}>
                  تأكيد
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        )}
      </SheetContent>
    </Sheet>
  );
}

function WebhookSummary({ d }: { d: any }) {
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">Summary</CardTitle></CardHeader>
      <CardContent className="grid gap-2 md:grid-cols-2 text-sm">
        <Stat label="Gateway" value={d.gateway_name ?? "—"} />
        <Stat label="Provider" value={d.gateway_provider ?? "—"} />
        <Stat label="Mode" value={<Badge variant={d.gateway_mode === "test" ? "outline" : "secondary"}>{d.gateway_mode}</Badge>} />
        <Stat label="Event Type" value={d.event_type ?? "—"} />
        <Stat label="Provider Event ID" value={<span className="font-mono text-xs">{d.provider_event_id ?? "—"}</span>} />
        <Stat label="Processing State" value={<Badge className={WH_STATE_CLS[d.processing_state] ?? "bg-muted"}>{d.processing_state}</Badge>} />
        <Stat label="Attempts" value={String(d.retry_count ?? 0)} />
        <Stat label="Received" value={fmtDate(d.received_at)} />
        <Stat label="Processed" value={d.processed_at ? fmtDate(d.processed_at) : "—"} />
        <Stat label="Payload size" value={`${d.raw_payload_size ?? 0} bytes`} />
      </CardContent>
    </Card>
  );
}

function WebhookValidationChecks({ d }: { d: any }) {
  const check = (label: string, pass: boolean | null) => (
    <div className="flex items-center justify-between py-1 border-b last:border-b-0 text-sm">
      <span>{label}</span>
      {pass === true ? (
        <Badge className="bg-emerald-500/15 text-emerald-500">Passed</Badge>
      ) : pass === false ? (
        <Badge variant="destructive">Failed</Badge>
      ) : (
        <Badge variant="outline">N/A</Badge>
      )}
    </div>
  );
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">Validation Checks</CardTitle></CardHeader>
      <CardContent className="space-y-1">
        {check("Signature", d.signature_valid ?? null)}
        {check("Linked to Request", d.related_request_id ? true : false)}
        {check("Processed", d.processed ? true : d.processing_state === "failed" ? false : null)}
        {check("Idempotency Key", d.idempotency_key ? true : null)}
      </CardContent>
    </Card>
  );
}

function WebhookRedactedPayload({ d }: { d: any }) {
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">Redacted Payload</CardTitle></CardHeader>
      <CardContent>
        <pre className="text-xs bg-muted/40 rounded p-2 overflow-x-auto max-h-64" dir="ltr">
{JSON.stringify(d.redacted_payload ?? {}, null, 2)}
        </pre>
        <p className="text-xs text-muted-foreground mt-2">
          الأسرار وبيانات الدفع الحساسة محذوفة أو مقنّعة على السيرفر قبل الإرسال.
        </p>
      </CardContent>
    </Card>
  );
}

function WebhookRetryHistory({ d }: { d: any }) {
  const attempts = (d.attempts ?? []) as any[];
  if (attempts.length === 0) {
    return (
      <Card>
        <CardHeader><CardTitle className="text-sm">Retry History</CardTitle></CardHeader>
        <CardContent><p className="text-xs text-muted-foreground">لا توجد محاولات مسجلة.</p></CardContent>
      </Card>
    );
  }
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">Retry History ({attempts.length})</CardTitle></CardHeader>
      <CardContent>
        <Table>
          <TableHeader><TableRow>
            <TableHead>#</TableHead><TableHead>Trigger</TableHead><TableHead>Result</TableHead>
            <TableHead>Started</TableHead><TableHead>السبب</TableHead>
          </TableRow></TableHeader>
          <TableBody>
            {attempts.map((a) => (
              <TableRow key={a.id}>
                <TableCell className="font-mono text-xs">{a.attempt_number}</TableCell>
                <TableCell className="text-xs">{a.trigger_type}</TableCell>
                <TableCell className="text-xs">{a.result ?? "—"}</TableCell>
                <TableCell className="text-xs">{fmtDate(a.started_at)}</TableCell>
                <TableCell className="text-xs text-muted-foreground">{a.reason ?? "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
