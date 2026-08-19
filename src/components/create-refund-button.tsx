import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Undo2, AlertTriangle } from "lucide-react";
import { toast } from "sonner";
import { usePermissions } from "@/hooks/use-permissions";
import {
  checkRefundEligibility, previewRechargeRefundFn, requestRechargeRefundFn, getRefundFeatureFlags,
} from "@/lib/refunds/refunds.functions";

/* eslint-disable @typescript-eslint/no-explicit-any */

function genIdem(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

const SCOPES = [
  { value: "money_only", label: "المال فقط" },
  { value: "money_and_base_coins", label: "المال + كوينز أساسية" },
  { value: "money_and_all_coins", label: "المال + كل الكوينز (بونص)" },
  { value: "administrative_compensation", label: "تعويض إداري" },
  { value: "technical_failure", label: "فشل تقني" },
] as const;

export function CreateRefundButton({ rechargeRequestId }: { rechargeRequestId: string }) {
  const { has } = usePermissions();
  const [open, setOpen] = useState(false);

  if (!has("recharge_refunds.request")) return null;

  return (
    <>
      <Button variant="outline" size="sm" onClick={() => setOpen(true)}>
        <Undo2 className="h-3.5 w-3.5 ml-1" /> إنشاء استرداد
      </Button>
      {open && (
        <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4" onClick={() => setOpen(false)}>
          <div className="bg-background rounded-lg w-full max-w-2xl max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <RefundWizard requestId={rechargeRequestId} onClose={() => setOpen(false)} />
          </div>
        </div>
      )}
    </>
  );
}

function RefundWizard({ requestId, onClose }: { requestId: string; onClose: () => void }) {
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);
  const [refundType, setRefundType] = useState<"full" | "partial">("full");
  const [refundScope, setRefundScope] = useState<string>("money_only");
  const [amount, setAmount] = useState<string>("");
  const [bonusPolicy, setBonusPolicy] = useState<string>("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [preview, setPreview] = useState<any>(null);

  const navigate = useNavigate();
  const check = useServerFn(checkRefundEligibility);
  const previewFn = useServerFn(previewRechargeRefundFn);
  const requestFn = useServerFn(requestRechargeRefundFn);
  const flagsFn = useServerFn(getRefundFeatureFlags);

  const eligQ = useQuery({
    queryKey: ["refund_elig", requestId],
    queryFn: () => check({ data: { recharge_request_id: requestId } }),
  });
  const flagsQ = useQuery({ queryKey: ["refund_flags"], queryFn: () => flagsFn(), staleTime: 30_000 });

  const elig = eligQ.data?.success ? eligQ.data.data : null;
  const flags = flagsQ.data;

  async function runPreview() {
    setBusy(true);
    try {
      const amt = refundType === "full" ? (elig?.remaining_refundable ?? 0) : Number(amount);
      if (!amt || amt <= 0) { toast.error("المبلغ مطلوب"); return; }
      const res: any = await previewFn({
        data: {
          recharge_request_id: requestId,
          refund_type: refundType,
          refund_scope: refundScope as any,
          requested_amount: amt,
          bonus_policy: bonusPolicy || undefined,
        },
      });
      if (!res?.success) { toast.error(res?.safe_message ?? "فشل المعاينة"); return; }
      setPreview(res.data);
      setStep(3);
    } finally { setBusy(false); }
  }

  async function submit() {
    if (reason.trim().length < 5) { toast.error("السبب مطلوب (5 أحرف على الأقل)"); return; }
    setBusy(true);
    try {
      const amt = refundType === "full" ? (elig?.remaining_refundable ?? 0) : Number(amount);
      const res: any = await requestFn({
        data: {
          recharge_request_id: requestId,
          refund_type: refundType,
          refund_scope: refundScope as any,
          requested_amount: amt,
          bonus_policy: bonusPolicy || undefined,
          reason: reason.trim(),
          idempotency_key: genIdem("refund_req"),
        },
      });
      if (!res?.success) { toast.error(res?.safe_message ?? "فشل الإنشاء"); return; }
      toast.success("تم إنشاء طلب الاسترداد");
      const refundId = res.data?.id ?? res.data?.refund_id;
      onClose();
      if (refundId) navigate({ to: "/finance/recharge-refunds/$id", params: { id: refundId } });
    } finally { setBusy(false); }
  }

  if (eligQ.isLoading) return <div className="p-6">جارٍ التحقق...</div>;
  if (!elig) return <div className="p-6 text-destructive">{eligQ.data?.safe_message ?? "خطأ"}</div>;
  if (!elig.can_request) {
    return (
      <div className="p-6 space-y-3">
        <div className="flex items-center gap-2 text-destructive"><AlertTriangle className="h-4 w-4" /> غير قابل للاسترداد</div>
        <div className="text-sm space-y-1">
          <div>حالة الطلب: <Badge>{elig.request_status}</Badge></div>
          <div>الأصلي: {elig.original_amount} {elig.currency}</div>
          <div>مسترد سابقاً: {elig.already_refunded}</div>
          <div>المتبقي: {elig.remaining_refundable}</div>
          <div>يوجد استرداد نشط: {elig.has_active_refund ? "نعم" : "لا"}</div>
          {!elig.can_request_permission && <div className="text-destructive">لا تملك صلاحية recharge_refunds.request</div>}
        </div>
        <Button variant="outline" onClick={onClose}>إغلاق</Button>
      </div>
    );
  }

  return (
    <div className="p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="font-semibold flex items-center gap-2"><Undo2 className="h-4 w-4" /> إنشاء طلب استرداد — الخطوة {step}/4</h3>
        <Button variant="ghost" size="sm" onClick={onClose}>×</Button>
      </div>
      {flags && !flags.admin_ui && (
        <div className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-700 dark:text-amber-400 flex items-center gap-2">
          <AlertTriangle className="h-3.5 w-3.5" /> واجهة الاسترداد معطلة (enable_refund_admin_ui=false) — الطلب سيُرفض عند الإرسال.
        </div>
      )}

      {step === 1 && (
        <div className="space-y-3 text-sm">
          <div className="text-xs text-muted-foreground">
            المتاح للاسترداد: <span className="font-mono">{elig.remaining_refundable} {elig.currency}</span>
            {" · "}الأصلي: {elig.original_amount} · مسترد سابقاً: {elig.already_refunded}
          </div>
          <div>
            <label className="text-xs">النوع</label>
            <div className="flex gap-2 mt-1">
              <Button variant={refundType === "full" ? "default" : "outline"} size="sm" onClick={() => setRefundType("full")}>كامل</Button>
              <Button variant={refundType === "partial" ? "default" : "outline"} size="sm" onClick={() => setRefundType("partial")}>جزئي</Button>
            </div>
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={onClose}>إلغاء</Button>
            <Button onClick={() => setStep(2)}>التالي</Button>
          </div>
        </div>
      )}

      {step === 2 && (
        <div className="space-y-3 text-sm">
          <div>
            <label className="text-xs">النطاق</label>
            <Select value={refundScope} onValueChange={setRefundScope}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {SCOPES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          {refundType === "partial" && (
            <div>
              <label className="text-xs">المبلغ ({elig.currency}) — بحد أقصى {elig.remaining_refundable}</label>
              <Input type="number" step="0.01" min="0.01" max={elig.remaining_refundable}
                     value={amount} onChange={(e) => setAmount(e.target.value)} />
            </div>
          )}
          <div>
            <label className="text-xs">Bonus Policy (اختياري)</label>
            <Input value={bonusPolicy} onChange={(e) => setBonusPolicy(e.target.value)} placeholder="proportional / full_recover / none" />
          </div>
          <div className="flex justify-between gap-2">
            <Button variant="ghost" onClick={() => setStep(1)}>السابق</Button>
            <div className="flex gap-2">
              <Button variant="ghost" onClick={onClose}>إلغاء</Button>
              <Button onClick={runPreview} disabled={busy}>معاينة (Preflight)</Button>
            </div>
          </div>
        </div>
      )}

      {step === 3 && preview && (
        <div className="space-y-3 text-sm">
          <div className="text-xs text-muted-foreground">Preflight — من <code>preview_recharge_refund</code></div>
          <div className="rounded border border-border bg-muted/30 p-3 text-xs font-mono whitespace-pre-wrap max-h-72 overflow-y-auto">
            {JSON.stringify(preview, null, 2)}
          </div>
          {preview.requires_second_approval && (
            <div className="text-xs text-amber-600 dark:text-amber-400">⚠ سيتطلب هذا الطلب اعتماد Two-Eyes.</div>
          )}
          <div className="flex justify-between gap-2">
            <Button variant="ghost" onClick={() => setStep(2)}>السابق</Button>
            <div className="flex gap-2">
              <Button variant="ghost" onClick={onClose}>إلغاء</Button>
              <Button onClick={() => setStep(4)}>التالي</Button>
            </div>
          </div>
        </div>
      )}

      {step === 4 && (
        <div className="space-y-3 text-sm">
          <div className="text-xs text-muted-foreground">مراجعة نهائية — يتم إنشاء الطلب فقط، بدون تنفيذ.</div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="text-muted-foreground">النوع</div><div>{refundType}</div>
            <div className="text-muted-foreground">النطاق</div><div>{refundScope}</div>
            <div className="text-muted-foreground">المبلغ</div>
            <div>{refundType === "full" ? elig.remaining_refundable : amount} {elig.currency}</div>
            <div className="text-muted-foreground">Bonus Policy</div><div>{bonusPolicy || "—"}</div>
          </div>
          <div>
            <label className="text-xs">السبب (يُسجَّل في Audit)</label>
            <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="5 أحرف على الأقل" />
          </div>
          <div className="flex justify-between gap-2">
            <Button variant="ghost" onClick={() => setStep(3)}>السابق</Button>
            <div className="flex gap-2">
              <Button variant="ghost" onClick={onClose}>إلغاء</Button>
              <Button onClick={submit} disabled={busy || reason.trim().length < 5}>إنشاء الطلب</Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
