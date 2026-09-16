import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { toast } from "sonner";
import { fmtDate } from "@/lib/charging-utils";

type Agent = { user_id: string; legacy_id: string; name: string; avatar_url: string | null; coins: string; pearls: string };
type Log = { id: string; reference: string; target_user_id: string; target_name: string; target_legacy_id: string; asset: string; amount: string | null; balance_before: string; balance_after: string; reason: string; admin_name: string; action: string; reversal_of: string | null; reversed: boolean; created_at: string; snapshot_before?: unknown; snapshot_after?: unknown };
type Activity = { id: string; actor_name: string; actor_legacy_id: string; asset: string; amount: string; reason: string; reference_id: string; created_at: string };
type Bundle = { agents: Agent[]; logs: Log[]; activity: Activity[] };
type Agency = { id: string; name: string; phone: string | null; country: string | null; status: string; commission_rate: number | null; daily_coin_transfer_limit: number | null; monthly_coin_transfer_limit: number | null; daily_pearl_transfer_limit: number | null; monthly_pearl_transfer_limit: number | null };
type Pending = { key: string; userId: string; asset: string; amount: string; reason: string; reversalId?: string };
const number = (value: string | null | undefined) => {
  try { return BigInt(value || "0").toLocaleString("en-US"); } catch { return "—"; }
};
async function rpc<T>(name: string, params: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(name as never, params as never);
  if (error) throw error;
  return data as unknown as T;
}

export function ChargingFinancialControl({ agency, view = "finance" }: { agency: Agency; view?: "finance" | "logs" | "settings" }) {
  const { has } = usePermissions();
  const qc = useQueryClient();
  const [page, setPage] = useState(0);
  const [assetFilter, setAssetFilter] = useState("all");
  const [userId, setUserId] = useState("");
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("");
  const [asset, setAsset] = useState("coins");
  const [debit, setDebit] = useState(false);
  const [pending, setPending] = useState<Pending | null>(null);
  const [edit, setEdit] = useState(false);
  const [form, setForm] = useState<Record<string, string>>({});
  const [editKey, setEditKey] = useState("");
  const [editReason, setEditReason] = useState("");
  const [editConfirmed, setEditConfirmed] = useState(false);
  const [detail, setDetail] = useState<Log | null>(null);
  const bundle = useQuery({
    queryKey: ["charging_financial_control", agency.id, page, assetFilter],
    enabled: has("charging_finance.read"),
    queryFn: () => rpc<Bundle>("admin_get_charging_financial_control", { p_agency_id: agency.id, p_page: page, p_asset: assetFilter }),
    refetchInterval: 15000,
  });
  const agents = bundle.data?.agents ?? [];
  const selected = agents.find((a) => a.user_id === userId) ?? agents[0];
  const refresh = async () => {
    await Promise.all([
      qc.invalidateQueries({ queryKey: ["charging_financial_control", agency.id] }),
      qc.invalidateQueries({ queryKey: ["charging_agency"] }),
      qc.invalidateQueries({ queryKey: ["charging_agency_owner"] }),
      qc.invalidateQueries({ queryKey: ["charging_agencies_command_center"] }),
      qc.invalidateQueries({ queryKey: ["charging_activity_ledger"] }),
    ]);
  };
  const adjustment = useMutation({
    mutationFn: (p: Pending) => rpc("admin_adjust_charging_wallet", {
      p_agency_id: agency.id, p_user_id: p.userId, p_asset: p.asset, p_amount: p.amount,
      p_reason: p.reason, p_idempotency_key: p.key, p_reversal_of: p.reversalId ?? null,
    }),
    onSuccess: async () => { setPending(null); setAmount(""); setReason(""); toast.success("تم تنفيذ العملية وتسجيلها"); await refresh(); },
    onError: (e: Error) => toast.error(e.message),
  });
  const editing = useMutation({
    mutationFn: () => rpc("admin_edit_charging_agency", { p_agency_id: agency.id, p_changes: form, p_reason: editReason, p_idempotency_key: editKey }),
    onSuccess: async () => { setEdit(false); toast.success("تم تحديث الوكالة وحفظ سجل التعديل"); await refresh(); },
    onError: (e: Error) => toast.error(e.message),
  });
  function prepare(asset: string, debit: boolean) {
    if (!selected || !/^[1-9][0-9]*$/.test(amount) || BigInt(amount) > 9223372036854775807n || reason.trim().length < 10) {
      toast.error("اختر الوكيل وأدخل مبلغًا صحيحًا وسببًا لا يقل عن 10 أحرف"); return;
    }
    if (debit && BigInt(amount) > BigInt(asset === "coins" ? selected.coins : selected.pearls)) { toast.error("الرصيد لا يسمح بالخصم"); return; }
    setPending({ key: crypto.randomUUID(), userId: selected.user_id, asset, amount: `${debit ? "-" : ""}${amount}`, reason: reason.trim() });
  }
  function openEdit() {
    const keys = ["name", "phone", "country", "status", "commission_rate", "daily_coin_transfer_limit", "monthly_coin_transfer_limit", "daily_pearl_transfer_limit", "monthly_pearl_transfer_limit"] as const;
    setForm(Object.fromEntries(keys.map((k) => [k, String(agency[k] ?? (k.includes("limit") || k === "commission_rate" ? 0 : ""))])));
    setEditReason(""); setEditConfirmed(false); setEditKey(crypto.randomUUID()); setEdit(true);
  }
  if (!has("charging_finance.read")) return <Card><CardContent className="p-6 text-muted-foreground">ليس لديك صلاحية عرض التحكم المالي. اطلب من المسؤول منح صلاحية قراءة المالية.</CardContent></Card>;
  const target = agents.find((a) => a.user_id === pending?.userId);
  return <Card dir="rtl" className="rounded-2xl border shadow-none">
    <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2"><CardTitle>{view === "logs" ? "السجلات المالية وتعديلات الإدارة" : view === "settings" ? "إعدادات وكالة الشحن" : "تنفيذ عملية مالية"}</CardTitle><div className="flex gap-2"><Button variant="outline" onClick={() => refresh()} disabled={bundle.isFetching}>تحديث</Button>{has("charging_finance.manage") && <Button variant="outline" onClick={openEdit}>تعديل البيانات / إيقاف وتشغيل</Button>}</div></CardHeader>
    <CardContent className="space-y-5">
      {bundle.error && <p role="alert" className="text-destructive">تعذر قراءة السجل: {bundle.error.message}</p>}
      {bundle.isLoading && <p>جاري التحميل…</p>}
      {view === "finance" && <><div className="grid gap-5 md:grid-cols-3"><div><Label>حساب الوكيل</Label><select className="mt-2 w-full rounded-xl border bg-background p-3" value={selected?.user_id ?? ""} onChange={(e) => setUserId(e.target.value)}>{agents.map((a) => <option key={a.user_id} value={a.user_id}>{a.name} — {a.legacy_id}</option>)}</select></div><div><Label>قيمة الإضافة أو الخصم</Label><Input dir="ltr" inputMode="numeric" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, ""))} /></div><div><Label>سبب العملية — إجباري</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} /></div></div>
      {selected && <div className="flex items-center gap-3"><Avatar><AvatarImage src={selected.avatar_url ?? undefined} /><AvatarFallback>{selected.name?.slice(0, 1)}</AvatarFallback></Avatar><span>{selected.name} · {selected.legacy_id} · كوينز: <b dir="ltr">{number(selected.coins)}</b> · لؤلؤ: <b dir="ltr">{number(selected.pearls)}</b></span></div>}
      <div className="grid gap-5 sm:grid-cols-2"><div><Label>نوع الرصيد</Label><div className="mt-2 flex gap-2"><Button variant={asset === "coins" ? "default" : "outline"} onClick={() => setAsset("coins")}>كوينز</Button><Button variant={asset === "pearls" ? "default" : "outline"} onClick={() => setAsset("pearls")}>لؤلؤ</Button></div></div><div><Label>نوع العملية</Label><div className="mt-2 flex gap-2"><Button variant={!debit ? "default" : "outline"} disabled={!has("charging_finance.credit")} onClick={() => setDebit(false)}>إضافة</Button><Button variant={debit ? "destructive" : "outline"} disabled={!has("charging_finance.debit")} onClick={() => setDebit(true)}>خصم</Button></div></div></div>
      {selected && <div className="grid grid-cols-2 gap-4 rounded-xl border bg-muted/20 p-5"><div><p className="text-xs text-muted-foreground">الرصيد الحالي</p><b className="mt-2 block text-xl" dir="ltr">{number(asset === "coins" ? selected.coins : selected.pearls)}</b></div><div><p className="text-xs text-muted-foreground">الرصيد المتوقع بعد العملية</p><b className="mt-2 block text-xl" dir="ltr">{amount && /^[1-9][0-9]*$/.test(amount) ? number((BigInt(asset === "coins" ? selected.coins : selected.pearls) + (debit ? -BigInt(amount) : BigInt(amount))).toString()) : "—"}</b></div></div>}
      <Button className="w-full" disabled={bundle.isFetching || adjustment.isPending || !has(debit ? "charging_finance.debit" : "charging_finance.credit")} onClick={() => prepare(asset, debit)}>مراجعة وتأكيد العملية</Button>
      <p className="text-xs text-muted-foreground">يُفحص الرصيد النهائي لحظة التنفيذ. لا تُحذف السجلات؛ تصحيح الأخطاء بعملية عكسية مستقلة.</p></>}
      {view === "settings" && <div className="grid gap-4 sm:grid-cols-2">{[["اسم الوكالة", agency.name], ["رقم الهاتف", agency.phone], ["الدولة", agency.country], ["الحالة", agency.status === "active" ? "نشطة" : "متوقفة"], ["نسبة الربح", `${agency.commission_rate ?? 0}%`], ["حد الكوينز اليومي", agency.daily_coin_transfer_limit], ["حد الكوينز الشهري", agency.monthly_coin_transfer_limit], ["حد اللؤلؤ اليومي", agency.daily_pearl_transfer_limit], ["حد اللؤلؤ الشهري", agency.monthly_pearl_transfer_limit]].map(([label, value]) => <div key={String(label)} className="rounded-xl border bg-muted/20 p-4"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-2 font-semibold">{String(value ?? "—")}</p></div>)}</div>}
      {view === "logs" && <><Label>سبب عكس العملية — إجباري عند العكس</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="أدخل سببًا لا يقل عن 10 أحرف" />
      <div className="flex flex-wrap items-center gap-2"><Label>تصفية السجلات</Label><select className="rounded border bg-background p-2" value={assetFilter} onChange={(e) => { setAssetFilter(e.target.value); setPage(0); }}><option value="all">كل الأرصدة والتعديلات</option><option value="coins">كوينز</option><option value="pearls">لؤلؤ</option></select><Button variant="outline" disabled={page === 0} onClick={() => setPage(page - 1)}>السابق</Button><span dir="ltr">{page + 1}</span><Button variant="outline" disabled={(bundle.data?.logs.length ?? 0) < 50 && (bundle.data?.activity.length ?? 0) < 50} onClick={() => setPage(page + 1)}>التالي</Button></div>
      <h3 className="font-bold">سجل تعديلات الإدارة</h3><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr>{["العملية", "الوكيل", "الرصيد", "قبل ← بعد", "المسؤول والسبب", "التاريخ", "تحكم"].map((h) => <th key={h} className="p-2 text-right">{h}</th>)}</tr></thead><tbody>{bundle.data?.logs.map((l) => <tr key={l.id} className="border-t"><td className="p-2" dir="ltr">{l.reference}</td><td>{l.target_name ?? "تعديل وكالة"}<br />{l.target_legacy_id}</td><td>{l.asset === "coins" ? "كوينز" : l.asset === "pearls" ? "لؤلؤ" : "بيانات"} {l.amount && number(l.amount)}</td><td dir="ltr">{l.amount ? `${number(l.balance_before)} → ${number(l.balance_after)}` : "—"}</td><td>{l.admin_name}<br />{l.reason}</td><td>{fmtDate(l.created_at)}</td><td><Button size="sm" variant="outline" onClick={() => setDetail(l)}>تفاصيل</Button>{l.amount && !l.reversal_of && !l.reversed && has("charging_finance.reverse") && <Button size="sm" variant="outline" onClick={() => {
        if (reason.trim().length < 10) { toast.error("اكتب سبب العكس في حقل السبب أولًا"); return; }
        setPending({ key: crypto.randomUUID(), userId: l.target_user_id, asset: l.asset, amount: (-BigInt(l.amount!)).toString(), reason, reversalId: l.id });
      }}>عكس العملية</Button>}{l.reversed && <span>تم العكس</span>}</td></tr>)}</tbody></table>{bundle.data?.logs.length === 0 && <p className="p-4">لا توجد تعديلات إدارية بهذه الصفحة.</p>}</div>
      <h3 className="font-bold">جميع حركات محافظ الوكلاء</h3><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr>{["الوكيل", "نوع العملية", "القيمة", "المرجع", "التاريخ"].map((h) => <th key={h} className="p-2 text-right">{h}</th>)}</tr></thead><tbody>{bundle.data?.activity.map((l) => <tr className="border-t" key={l.id}><td className="p-2">{l.actor_name} · {l.actor_legacy_id}</td><td>{l.reason}</td><td dir="ltr">{number(l.amount)} {l.asset === "coins" ? "كوينز" : "لؤلؤ"}</td><td>{l.reference_id}</td><td>{fmtDate(l.created_at)}</td></tr>)}</tbody></table></div>
      </>}
    </CardContent>
    <Dialog open={pending !== null} onOpenChange={(open) => { if (!open && !adjustment.isPending) setPending(null); }}><DialogContent><DialogHeader><DialogTitle>تأكيد العملية المالية</DialogTitle></DialogHeader>{pending && <><p>{target?.name ?? pending.userId} · {target?.legacy_id}</p><p>{pending.reversalId ? "عملية عكسية" : BigInt(pending.amount) > 0n ? "إضافة" : "خصم"}: <b dir="ltr">{number(pending.amount)}</b> {pending.asset === "coins" ? "كوينز" : "لؤلؤ"}</p><p>{pending.reason}</p><p>سيتم حفظ المسؤول والرصيد قبل العملية وبعدها. لا يمكن حذف العملية.</p><Button disabled={adjustment.isPending} onClick={() => adjustment.mutate(pending)}>تأكيد التنفيذ</Button></>}</DialogContent></Dialog>
    <Dialog open={edit} onOpenChange={(open) => { if (!editing.isPending) setEdit(open); }}><DialogContent className="max-h-[85vh] overflow-y-auto"><DialogHeader><DialogTitle>تعديل وكالة الشحن</DialogTitle></DialogHeader>{[["name", "اسم الوكالة"], ["phone", "واتساب — رمز الدولة + الرقم"], ["country", "رمز الدولة مثل EG"], ["commission_rate", "نسبة العمولة 0–100"], ["daily_coin_transfer_limit", "حد الكوينز اليومي"], ["monthly_coin_transfer_limit", "حد الكوينز الشهري"], ["daily_pearl_transfer_limit", "حد اللؤلؤ اليومي"], ["monthly_pearl_transfer_limit", "حد اللؤلؤ الشهري"]].map(([key, label]) => <div key={key}><Label>{label}</Label><Input dir={key === "name" ? "rtl" : "ltr"} value={form[key] ?? ""} onChange={(e) => { setEditConfirmed(false); setForm({ ...form, [key]: e.target.value }); }} /></div>)}<Label>حالة الوكالة</Label><select className="rounded border bg-background p-2" value={form.status} onChange={(e) => { setEditConfirmed(false); setForm({ ...form, status: e.target.value }); }}><option value="active">نشطة</option><option value="suspended">متوقفة — منع التحويلات</option></select><Label>سبب التعديل</Label><Textarea value={editReason} onChange={(e) => { setEditConfirmed(false); setEditReason(e.target.value); }} /><label className="flex gap-2"><input type="checkbox" checked={editConfirmed} onChange={(e) => setEditConfirmed(e.target.checked)} />أؤكد مراجعة البيانات وحالة الوكالة</label><Button disabled={!editConfirmed || editReason.trim().length < 10 || editing.isPending} onClick={() => editing.mutate()}>حفظ التعديل</Button></DialogContent></Dialog>
    <Dialog open={detail !== null} onOpenChange={(open) => { if (!open) setDetail(null); }}><DialogContent className="max-h-[85vh] overflow-y-auto"><DialogHeader><DialogTitle>تفاصيل العملية {detail?.reference}</DialogTitle></DialogHeader><p>{detail?.admin_name} · {detail && fmtDate(detail.created_at)}</p><p>{detail?.reason}</p>{detail?.snapshot_before != null && <><Label>البيانات قبل التعديل</Label><pre dir="ltr" className="overflow-auto text-xs">{JSON.stringify(detail.snapshot_before, null, 2)}</pre><Label>البيانات بعد التعديل</Label><pre dir="ltr" className="overflow-auto text-xs">{JSON.stringify(detail.snapshot_after, null, 2)}</pre></>}</DialogContent></Dialog>
  </Card>;
}
