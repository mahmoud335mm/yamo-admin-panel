import { createFileRoute, Link, useRouter } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { PermissionGuard } from "@/components/permission-guard";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import {
  ArrowRight, RefreshCw, ShieldCheck, X, Play, CheckCheck, Ban, AlertTriangle, Undo2,
} from "lucide-react";
import { fmtDate } from "@/lib/charging-utils";
import {
  getRechargeRefundDetail,
  approveRechargeRefundFn, secondApproveRechargeRefundFn,
  rejectRechargeRefundFn, cancelRechargeRefundFn, executeRechargeRefundFn,
  getRefundFeatureFlags,
} from "@/lib/refunds/refunds.functions";
import { usePermissions } from "@/hooks/use-permissions";
import { refreshRefundStatus } from "@/lib/refunds/refresh-refund-status.functions";
import { retryGatewayRefund } from "@/lib/refunds/retry-gateway-refund.functions";

export const Route = createFileRoute("/_authenticated/finance/recharge-refunds/$id")({
  component: () => (
    <PermissionGuard permission="recharge_refunds.read">
      <RefundDetailPage />
    </PermissionGuard>
  ),
});

/* eslint-disable @typescript-eslint/no-explicit-any */

function genIdem(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function RefundDetailPage() {
  const { id } = Route.useParams();
  const router = useRouter();
  const { has } = usePermissions();
  const getFn = useServerFn(getRechargeRefundDetail);
  const flagsFn = useServerFn(getRefundFeatureFlags);
  const q = useQuery({
    queryKey: ["refund", id],
    queryFn: () => getFn({ data: { refund_id: id } }),
  });
  const flagsQ = useQuery({ queryKey: ["refund_flags"], queryFn: () => flagsFn(), staleTime: 30_000 });

  if (q.isLoading) return <Skeleton className="h-96" />;
  if (!q.data?.success) return (
    <div className="p-6 text-center text-destructive">
      {q.data?.safe_message ?? "تعذّر التحميل"}
      <div className="mt-3"><Link to="/finance/recharge-refunds"><Button variant="outline" size="sm">عودة</Button></Link></div>
    </div>
  );

  const d = q.data.data as any;
  const r = d.refund;
  const flags = flagsQ.data;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Link to="/finance/recharge-refunds"><Button variant="ghost" size="sm"><ArrowRight className="h-4 w-4 ml-1" /> عودة</Button></Link>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Undo2 className="h-5 w-5" /> استرداد {r.refund_reference}
        </h1>
        <Badge variant="outline">{r.status}</Badge>
        {r.requires_second_approval && <Badge variant="destructive">Two-Eyes مطلوب</Badge>}
        <div className="mr-auto flex gap-2">
          <Button variant="outline" size="sm" onClick={() => q.refetch()}>
            <RefreshCw className="ml-1 h-3.5 w-3.5" /> تحديث
          </Button>
        </div>
      </div>

      {flags && !flags.execution && (
        <div className="flex items-center gap-2 rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-700 dark:text-amber-400">
          <AlertTriangle className="h-3.5 w-3.5" /> تنفيذ الاسترداد معطل — enable_refund_execution=false
        </div>
      )}

      <ActionsBar refund={r} has={has} onDone={() => { q.refetch(); router.invalidate(); }} />

      <Tabs defaultValue="overview">
        <TabsList className="flex-wrap h-auto">
          <TabsTrigger value="overview">النظرة العامة</TabsTrigger>
          <TabsTrigger value="preflight">Preflight</TabsTrigger>
          <TabsTrigger value="reviews">المراجعات</TabsTrigger>
          <TabsTrigger value="gateway">Gateway</TabsTrigger>
          <TabsTrigger value="reversal">عكس المحفظة</TabsTrigger>
          <TabsTrigger value="ledger">Ledger</TabsTrigger>
          <TabsTrigger value="timeline">Timeline</TabsTrigger>
          <TabsTrigger value="audit">Audit</TabsTrigger>
          <TabsTrigger value="messages">رسائل النظام</TabsTrigger>
        </TabsList>

        <TabsContent value="overview">
          <OverviewTab d={d} />
        </TabsContent>
        <TabsContent value="preflight">
          <PreflightTab r={r} />
        </TabsContent>
        <TabsContent value="reviews">
          <ReviewsTab d={d} />
        </TabsContent>
        <TabsContent value="gateway">
          <GatewayTab d={d} onDone={() => q.refetch()} />
        </TabsContent>
        <TabsContent value="reversal">
          <ReversalTab r={r} ledger={d.ledger} />
        </TabsContent>
        <TabsContent value="ledger">
          <LedgerTab rows={d.ledger} />
        </TabsContent>
        <TabsContent value="timeline">
          <TimelineTab d={d} />
        </TabsContent>
        <TabsContent value="audit">
          <AuditTab rows={d.audit} />
        </TabsContent>
        <TabsContent value="messages">
          <MessagesTab refundId={r.id} />
        </TabsContent>
      </Tabs>
    </div>
  );
}

/* ---------------- Actions ---------------- */

function ActionsBar({ refund, has, onDone }: { refund: any; has: (p: string) => boolean; onDone: () => void }) {
  const [action, setAction] = useState<"approve" | "second_approve" | "reject" | "cancel" | "execute" | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const s = refund.status as string;

  const canApprove = has("recharge_refunds.approve") && ["requested", "pending_review"].includes(s);
  const canSecond = has("recharge_refunds.second_approve") && s === "pending_second_review";
  const canReject = has("recharge_refunds.reject") && ["requested","pending_review","pending_second_review","manual_review"].includes(s);
  const canCancel = has("recharge_refunds.cancel") && !["completed","partially_completed","failed","cancelled","rejected"].includes(s);
  const canExecute = has("recharge_refunds.execute") && s === "approved";

  const approve = useServerFn(approveRechargeRefundFn);
  const second = useServerFn(secondApproveRechargeRefundFn);
  const reject = useServerFn(rejectRechargeRefundFn);
  const cancel = useServerFn(cancelRechargeRefundFn);
  const execute = useServerFn(executeRechargeRefundFn);

  async function submit() {
    if (reason.trim().length < 5) { toast.error("السبب مطلوب (5 أحرف على الأقل)"); return; }
    setBusy(true);
    try {
      let res: any;
      const args = { refund_id: refund.id, reason: reason.trim() };
      if (action === "approve") res = await approve({ data: args });
      else if (action === "second_approve") res = await second({ data: args });
      else if (action === "reject") res = await reject({ data: args });
      else if (action === "cancel") res = await cancel({ data: args });
      else if (action === "execute") res = await execute({ data: { ...args, idempotency_key: genIdem("exec") } });
      if (!res?.success) { toast.error(res?.safe_message ?? "فشل التنفيذ"); return; }
      toast.success("تم تنفيذ الإجراء");
      setAction(null); setReason("");
      onDone();
    } catch (e) { toast.error(e instanceof Error ? e.message : "خطأ"); }
    finally { setBusy(false); }
  }

  const btns = [
    canApprove && { key: "approve", label: "اعتماد", icon: ShieldCheck, variant: "default" as const },
    canSecond && { key: "second_approve", label: "اعتماد ثانٍ", icon: CheckCheck, variant: "default" as const },
    canExecute && { key: "execute", label: "تنفيذ", icon: Play, variant: "default" as const },
    canReject && { key: "reject", label: "رفض", icon: Ban, variant: "destructive" as const },
    canCancel && { key: "cancel", label: "إلغاء", icon: X, variant: "outline" as const },
  ].filter(Boolean) as Array<{ key: any; label: string; icon: any; variant: any }>;

  if (btns.length === 0) return null;
  return (
    <Card>
      <CardContent className="p-3 flex flex-wrap gap-2">
        {btns.map((b) => (
          <Button key={b.key} size="sm" variant={b.variant} onClick={() => { setAction(b.key); setReason(""); }}>
            <b.icon className="ml-1 h-3.5 w-3.5" /> {b.label}
          </Button>
        ))}
        {action && (
          <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => !busy && setAction(null)}>
            <div className="bg-background rounded-lg p-4 w-full max-w-md space-y-3" onClick={(e) => e.stopPropagation()}>
              <h3 className="font-semibold">{btns.find((b) => b.key === action)?.label} — {refund.refund_reference}</h3>
              <Textarea placeholder="السبب (5 أحرف على الأقل، يُسجَّل في سجل التدقيق)" value={reason} onChange={(e) => setReason(e.target.value)} rows={4} />
              <div className="flex justify-end gap-2">
                <Button variant="ghost" onClick={() => setAction(null)} disabled={busy}>إلغاء</Button>
                <Button onClick={submit} disabled={busy || reason.trim().length < 5}>تأكيد</Button>
              </div>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

/* ---------------- Tabs ---------------- */

function KV({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-2 border-b border-border/50 py-1.5 text-xs">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-mono">{value ?? "—"}</span>
    </div>
  );
}

function OverviewTab({ d }: { d: any }) {
  const r = d.refund;
  const req = d.recharge_request;
  const gw = d.gateway;
  return (
    <div className="grid md:grid-cols-2 gap-4">
      <Card>
        <CardHeader><CardTitle className="text-sm">الاسترداد</CardTitle></CardHeader>
        <CardContent className="text-sm space-y-1">
          <KV label="المرجع" value={r.refund_reference} />
          <KV label="النوع" value={r.refund_type} />
          <KV label="النطاق" value={r.refund_scope} />
          <KV label="المطلوب" value={`${Number(r.requested_amount).toFixed(2)} ${r.currency_code}`} />
          <KV label="المعتمد" value={`${Number(r.approved_amount ?? 0).toFixed(2)} ${r.currency_code}`} />
          <KV label="عكس كوينز" value={`${r.coins_actually_reversed ?? 0} / ${r.base_coins_to_reverse ?? 0}`} />
          <KV label="عكس بونص" value={`${r.bonus_actually_reversed ?? 0} / ${r.bonus_coins_to_reverse ?? 0}`} />
          <KV label="غير مسترد (كوينز)" value={r.unrecovered_coin_amount ?? 0} />
          <KV label="غير مسترد (بونص)" value={r.unrecovered_bonus_amount ?? 0} />
          <KV label="Provider Ref" value={r.provider_refund_id_masked} />
          <KV label="Idempotency" value={r.idempotency_key_masked} />
          <KV label="تم الطلب" value={fmtDate(r.requested_at)} />
          <KV label="تم التنفيذ" value={r.executed_at ? fmtDate(r.executed_at) : "—"} />
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle className="text-sm">طلب الشحن الأصلي</CardTitle></CardHeader>
        <CardContent className="text-sm space-y-1">
          {req ? <>
            <KV label="Request Ref" value={<Link to="/finance/recharge-requests/$id" params={{ id: req.id }} className="text-primary hover:underline">{req.request_reference}</Link>} />
            <KV label="المبلغ" value={`${Number(req.final_amount ?? 0).toFixed(2)} ${req.currency_code}`} />
            <KV label="الكوينز" value={`${req.coin_amount ?? 0} + بونص ${req.bonus_amount ?? 0}`} />
            <KV label="الحالة" value={req.status} />
            <KV label="Payment" value={req.payment_status} />
            <KV label="Mode" value={req.payment_gateway_mode} />
            <KV label="External Ref" value={req.external_reference ?? "—"} />
          </> : <div className="text-muted-foreground">لا يوجد طلب مرتبط</div>}
          <div className="pt-2 border-t mt-2 text-xs text-muted-foreground">Gateway</div>
          {gw ? <>
            <KV label="الاسم" value={gw.name} />
            <KV label="النوع" value={gw.provider_type} />
            <KV label="Mode" value={gw.mode} />
            <KV label="Status" value={gw.status} />
          </> : <div className="text-xs text-muted-foreground">لا يوجد Gateway</div>}
        </CardContent>
      </Card>
    </div>
  );
}

function PreflightTab({ r }: { r: any }) {
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">Preflight (لقطة وقت الطلب)</CardTitle></CardHeader>
      <CardContent className="text-sm space-y-1">
        <KV label="النوع" value={r.refund_type} />
        <KV label="النطاق" value={r.refund_scope} />
        <KV label="مبلغ الطلب" value={`${r.requested_amount} ${r.currency_code}`} />
        <KV label="كوينز مطلوب عكسها" value={r.base_coins_to_reverse} />
        <KV label="بونص مطلوب عكسها" value={r.bonus_coins_to_reverse} />
        <KV label="Bonus Policy" value={r.bonus_policy ?? "—"} />
        <KV label="Two-Eyes مطلوب" value={r.requires_second_approval ? "نعم" : "لا"} />
        <KV label="Policy ID" value={r.policy_id ?? "—"} />
        <KV label="Policy Version" value={r.policy_version ?? "—"} />
        <p className="text-xs text-muted-foreground pt-2">
          هذه اللقطة تم حسابها بواسطة <code>preview_recharge_refund</code> وقت إنشاء الطلب. أي انحراف بين هذه القيم ووقت التنفيذ يُحوِّل الحالة إلى <code>manual_review</code>.
        </p>
      </CardContent>
    </Card>
  );
}

function ReviewsTab({ d }: { d: any }) {
  const r = d.refund;
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">المراجعات (Two-Eyes)</CardTitle></CardHeader>
      <CardContent className="text-sm space-y-1">
        <KV label="طلب المراجعة الثانية" value={r.requires_second_approval ? "نعم" : "لا"} />
        <KV label="اعتماد أول (Requested by)" value={r.requested_by ?? "—"} />
        <KV label="Approved by" value={r.approved_by ?? "—"} />
        <KV label="Approved at" value={r.approved_at ? fmtDate(r.approved_at) : "—"} />
        <KV label="Second Approved by" value={r.second_approved_by ?? "—"} />
        <KV label="Second Approved at" value={r.second_approved_at ? fmtDate(r.second_approved_at) : "—"} />
        <KV label="Rejected by" value={r.rejected_by ?? "—"} />
        <KV label="Rejected at" value={r.rejected_at ? fmtDate(r.rejected_at) : "—"} />
        <KV label="Executed by" value={r.executed_by ?? "—"} />
        <KV label="Executed at" value={r.executed_at ? fmtDate(r.executed_at) : "—"} />
        <p className="text-xs text-muted-foreground pt-2">
          فصل الأدوار مضمون على مستوى الـ RPC: نفس المستخدم لا يستطيع الاعتماد الأول والثاني، ولا التنفيذ بعد اعتماد ثانٍ خاص به.
        </p>
      </CardContent>
    </Card>
  );
}

function GatewayTab({ d, onDone }: { d: any; onDone: () => void }) {
  const r = d.refund;
  const { has } = usePermissions();
  const refresh = useServerFn(refreshRefundStatus);
  const retry = useServerFn(retryGatewayRefund);
  const [busy, setBusy] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [modal, setModal] = useState<"refresh" | "retry" | null>(null);

  async function run() {
    if (reason.trim().length < 5) { toast.error("السبب مطلوب (5 أحرف على الأقل)"); return; }
    setBusy(modal); try {
      const args = { refund_id: r.id, reason: reason.trim(), idempotency_key: genIdem(modal!) };
      const res: any = modal === "refresh" ? await refresh({ data: args }) : await retry({ data: args });
      if (!res?.success) { toast.error(res?.safe_message ?? "فشل"); return; }
      toast.success("تم"); setModal(null); setReason(""); onDone();
    } catch (e) { toast.error(e instanceof Error ? e.message : "خطأ"); }
    finally { setBusy(null); }
  }

  return (
    <div className="space-y-3">
      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle className="text-sm">حالة البوابة</CardTitle>
          <div className="flex gap-2">
            {has("recharge_refunds.refresh_status") && (
              <Button size="sm" variant="outline" onClick={() => setModal("refresh")}>تحديث الحالة من البوابة</Button>
            )}
            {has("recharge_refunds.retry_gateway") && (
              <Button size="sm" variant="outline" onClick={() => setModal("retry")}>إعادة محاولة</Button>
            )}
          </div>
        </CardHeader>
        <CardContent className="text-sm">
          <KV label="Provider Refund ID" value={r.provider_refund_id_masked} />
          <KV label="Retry Attempts" value={r.retry_attempt_count ?? 0} />
          <KV label="Retry Backoff Until" value={r.retry_backoff_until ? fmtDate(r.retry_backoff_until) : "—"} />
          <KV label="Status Refresh Count" value={r.status_refresh_count ?? 0} />
          <KV label="Last Status Refresh" value={r.last_status_refresh_at ? fmtDate(r.last_status_refresh_at) : "—"} />
          <KV label="Gateway Mode" value={r.gateway_mode} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">Attempts ({d.attempts.length})</CardTitle></CardHeader>
        <CardContent>
          {!d.can_read_attempts ? (
            <div className="text-xs text-muted-foreground py-4">لا تملك صلاحية <code>recharge_refunds.read_attempts</code></div>
          ) : d.attempts.length === 0 ? (
            <div className="text-xs text-muted-foreground py-4">لا محاولات بعد.</div>
          ) : (
            <Table>
              <TableHeader><TableRow>
                <TableHead>#</TableHead><TableHead>Trigger</TableHead><TableHead>Status</TableHead>
                <TableHead>Provider Ref</TableHead><TableHead>Failure</TableHead>
                <TableHead>Started</TableHead><TableHead>Finished</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {d.attempts.map((a: any) => (
                  <TableRow key={a.id}>
                    <TableCell>{a.attempt_number}</TableCell>
                    <TableCell className="text-xs">{a.trigger_type}</TableCell>
                    <TableCell><Badge variant="outline">{a.status}</Badge></TableCell>
                    <TableCell className="font-mono text-xs">{a.provider_refund_id_masked ?? "—"}</TableCell>
                    <TableCell className="text-xs">{a.failure_code ? `${a.failure_code}: ${a.safe_error ?? ""}` : "—"}</TableCell>
                    <TableCell className="text-xs">{fmtDate(a.started_at)}</TableCell>
                    <TableCell className="text-xs">{a.finished_at ? fmtDate(a.finished_at) : "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">Webhooks ({d.webhooks.length})</CardTitle></CardHeader>
        <CardContent>
          {!d.can_read_attempts ? (
            <div className="text-xs text-muted-foreground py-4">لا تملك صلاحية <code>recharge_refunds.read_attempts</code></div>
          ) : d.webhooks.length === 0 ? (
            <div className="text-xs text-muted-foreground py-4">لا webhooks بعد.</div>
          ) : (
            <Table>
              <TableHeader><TableRow>
                <TableHead>Event</TableHead><TableHead>Sig</TableHead><TableHead>TS</TableHead><TableHead>Replay</TableHead>
                <TableHead>State</TableHead><TableHead>Validation</TableHead>
                <TableHead>Received</TableHead><TableHead>Processed</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {d.webhooks.map((w: any) => (
                  <TableRow key={w.id}>
                    <TableCell className="text-xs">{w.normalized_event_type ?? "—"}</TableCell>
                    <TableCell>{w.signature_verified ? "✓" : "✗"}</TableCell>
                    <TableCell>{w.timestamp_verified ? "✓" : "✗"}</TableCell>
                    <TableCell>{w.replay_check_passed ? "✓" : "✗"}</TableCell>
                    <TableCell><Badge variant="outline">{w.processing_state}</Badge></TableCell>
                    <TableCell className="text-xs">{w.validation_status}</TableCell>
                    <TableCell className="text-xs">{fmtDate(w.received_at)}</TableCell>
                    <TableCell className="text-xs">{w.processed_at ? fmtDate(w.processed_at) : "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {modal && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => !busy && setModal(null)}>
          <div className="bg-background rounded-lg p-4 w-full max-w-md space-y-3" onClick={(e) => e.stopPropagation()}>
            <h3 className="font-semibold">{modal === "refresh" ? "تحديث الحالة من البوابة" : "إعادة محاولة الاسترداد"}</h3>
            <Textarea placeholder="السبب" value={reason} onChange={(e) => setReason(e.target.value)} rows={3} />
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setModal(null)} disabled={!!busy}>إلغاء</Button>
              <Button onClick={run} disabled={!!busy || reason.trim().length < 5}>تأكيد</Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function ReversalTab({ r, ledger }: { r: any; ledger: any[] }) {
  const reversalRows = ledger.filter((l) => l.ledger_side === "reversal" || String(l.reason ?? "").toLowerCase().includes("refund"));
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">عكس المحفظة</CardTitle></CardHeader>
      <CardContent className="text-sm space-y-1">
        <KV label="كوينز — مطلوب عكسها" value={r.base_coins_to_reverse ?? 0} />
        <KV label="كوينز — تم عكسها" value={r.coins_actually_reversed ?? 0} />
        <KV label="كوينز — غير مسترد" value={r.unrecovered_coin_amount ?? 0} />
        <KV label="بونص — مطلوب عكسها" value={r.bonus_coins_to_reverse ?? 0} />
        <KV label="بونص — تم عكسها" value={r.bonus_actually_reversed ?? 0} />
        <KV label="بونص — غير مسترد" value={r.unrecovered_bonus_amount ?? 0} />
        <KV label="السماح بالرصيد السالب" value={r.override_insufficient_balance ? "نعم" : "لا"} />
        <div className="pt-3 text-xs text-muted-foreground">قيود العكس ({reversalRows.length}):</div>
        <LedgerTab rows={reversalRows} compact />
      </CardContent>
    </Card>
  );
}

function LedgerTab({ rows, compact = false }: { rows: any[]; compact?: boolean }) {
  if (!rows.length) return <div className="text-xs text-muted-foreground py-4">لا قيود.</div>;
  return (
    <Card className={compact ? "border-0 shadow-none" : ""}>
      {!compact && <CardHeader><CardTitle className="text-sm">قيود المحفظة</CardTitle></CardHeader>}
      <CardContent className={compact ? "p-0" : ""}>
        <Table>
          <TableHeader><TableRow>
            <TableHead>Side</TableHead><TableHead>Group</TableHead><TableHead>Account</TableHead>
            <TableHead>Dir</TableHead><TableHead>Amount</TableHead><TableHead>Balance</TableHead>
            <TableHead>Reason</TableHead><TableHead>Ref</TableHead><TableHead>Time</TableHead>
          </TableRow></TableHeader>
          <TableBody>
            {rows.map((l: any) => (
              <TableRow key={l.id}>
                <TableCell className="text-xs">{l.ledger_side ?? "—"}</TableCell>
                <TableCell className="font-mono text-xs">{l.transaction_group_id?.slice(0, 8) ?? "—"}</TableCell>
                <TableCell className="text-xs">{l.account}</TableCell>
                <TableCell><Badge variant={l.direction === "credit" ? "default" : "outline"}>{l.direction}</Badge></TableCell>
                <TableCell className="font-mono text-xs">{l.amount}</TableCell>
                <TableCell className="font-mono text-xs">{l.balance_after}</TableCell>
                <TableCell className="text-xs">{l.reason ?? "—"}</TableCell>
                <TableCell className="text-xs">{l.reference ?? "—"}</TableCell>
                <TableCell className="text-xs">{fmtDate(l.created_at)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

function TimelineTab({ d }: { d: any }) {
  const r = d.refund;
  const events: Array<{ at: string; label: string; detail?: string }> = [];
  const push = (at: string | null, label: string, detail?: string) => { if (at) events.push({ at, label, detail }); };
  push(r.created_at, "أُنشئ", r.refund_reference);
  push(r.requested_at, "طُلب", r.status);
  push(r.approved_at, "اعتماد أول");
  push(r.second_approved_at, "اعتماد ثانٍ");
  push(r.gateway_confirmed_at, "أكدته البوابة");
  push(r.reversal_started_at, "بدأ عكس المحفظة");
  push(r.reversal_completed_at, "انتهى عكس المحفظة");
  push(r.executed_at, "تم التنفيذ");
  push(r.rejected_at, "رُفض");
  push(r.cancelled_at, "أُلغي");
  d.attempts.forEach((a: any) => {
    push(a.started_at, `Attempt #${a.attempt_number} (${a.trigger_type})`, a.status);
    if (a.finished_at) push(a.finished_at, `Attempt #${a.attempt_number} انتهى`, a.failure_code ?? a.status);
  });
  d.webhooks.forEach((w: any) => {
    push(w.received_at, `Webhook: ${w.normalized_event_type}`, w.processing_state);
    if (w.processed_at) push(w.processed_at, `Webhook تمت المعالجة`, w.validation_status);
  });
  events.sort((a, b) => a.at.localeCompare(b.at));
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">Timeline</CardTitle></CardHeader>
      <CardContent>
        {events.length === 0 ? <div className="text-xs text-muted-foreground">لا أحداث.</div> : (
          <ol className="border-r-2 border-border pr-4 space-y-3">
            {events.map((e, i) => (
              <li key={i} className="relative">
                <span className="absolute right-[-1.25rem] top-1 h-3 w-3 rounded-full bg-primary" />
                <div className="text-xs text-muted-foreground">{fmtDate(e.at)}</div>
                <div className="text-sm font-medium">{e.label}</div>
                {e.detail && <div className="text-xs text-muted-foreground">{e.detail}</div>}
              </li>
            ))}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}

function AuditTab({ rows }: { rows: any[] }) {
  if (!rows.length) return <div className="text-xs text-muted-foreground py-4">لا سجلات.</div>;
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">Audit ({rows.length})</CardTitle></CardHeader>
      <CardContent>
        <Table>
          <TableHeader><TableRow>
            <TableHead>Action</TableHead><TableHead>Actor</TableHead><TableHead>Reason</TableHead><TableHead>When</TableHead>
          </TableRow></TableHeader>
          <TableBody>
            {rows.map((a: any) => (
              <TableRow key={a.id}>
                <TableCell className="text-xs font-mono">{a.action}</TableCell>
                <TableCell className="text-xs font-mono">{a.actor_id?.slice(0, 8) ?? "—"}</TableCell>
                <TableCell className="text-xs">{a.reason ?? "—"}</TableCell>
                <TableCell className="text-xs">{fmtDate(a.created_at)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

function MessagesTab({ refundId }: { refundId: string }) {
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">رسائل النظام</CardTitle></CardHeader>
      <CardContent className="text-xs text-muted-foreground py-4">
        رسائل النظام تُنشأ تلقائياً في المحادثة بين المستخدم والنظام عند اكتمال الاسترداد
        (<code>transaction_message_outbox</code>). العرض التفصيلي متاح في مديول الرسائل — Refund ID:{" "}
        <span className="font-mono">{refundId.slice(0, 8)}…</span>
      </CardContent>
    </Card>
  );
}

// Silence unused warning
export const _u = { Input, useState };
