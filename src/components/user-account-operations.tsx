import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { fmtDate } from "@/lib/charging-utils";
import { toast } from "sonner";
import { ActiveAccountDevices } from "@/components/active-account-devices";

type Related = { user_id: string; legacy_id: string; display_name: string; avatar_url: string | null; agencies: { agency_id: string; joined_at: string; removed_at: string | null }[] };
type Context = { profile: { created_at: string; last_seen_at: string }; coins: string; pearls: string; locked_pearls: string; presence: { is_online: boolean; last_heartbeat_at: string; last_seen_at: string } | null; related_accounts: Related[] };
type Operation = { p_user_id: string; p_asset: string; p_amount: string; p_reason: string; p_idempotency_key: string };
const n = (v: string) => BigInt(v).toLocaleString("en-US");
async function rpc<T>(name: string, params: Record<string, unknown>): Promise<T> { const { data, error } = await supabase.rpc(name as never, params as never); if (error) throw error; return data as unknown as T; }

export function UserAccountOperations({ id }: { id: string }) {
  const { has } = usePermissions(); const qc = useQueryClient();
  const [amount, setAmount] = useState(""); const [reason, setReason] = useState("");
  const [asset, setAsset] = useState("coins"); const [debit, setDebit] = useState(false);
  const [pending, setPending] = useState<Operation | null>(null);
  const context = useQuery({ queryKey: ["user-account-context", id], queryFn: () => rpc<Context>("admin_get_yamo_user_account_context", { p_user_id: id }), refetchInterval: 15000 });
  const adjustment = useMutation({ mutationFn: (p: Operation) => rpc<{ operation_number: string; balance_after: string }>("admin_adjust_yamo_user_wallet_v243", p), onSuccess: (result) => {
    toast.success(`تم حفظ العملية ${result.operation_number} — الرصيد بعدها ${n(result.balance_after)}`); setPending(null); setAmount(""); setReason("");
    qc.invalidateQueries({ queryKey: ["user-account-context", id] }); qc.invalidateQueries({ queryKey: ["user", id] }); qc.invalidateQueries({ queryKey: ["users"] }); qc.invalidateQueries({ queryKey: ["user-records", id] });
  }, onError: (e: Error) => toast.error(e.message) });
  if (context.isLoading) return <p>جاري قراءة الحضور والترابط…</p>;
  if (context.error) return <p role="alert" className="rounded-xl border p-4 text-destructive">تعذر قراءة مركز الحساب. تأكد من تركيب ملف السيرفر V243: {context.error.message}</p>;
  if (!context.data) return null;
  const c = context.data;
  const online = c.presence?.is_online && Date.now() - Date.parse(c.presence.last_heartbeat_at) < 120000;
  function prepare() {
    if (!/^[1-9][0-9]*$/.test(amount) || BigInt(amount) > 9223372036854775807n || reason.trim().length < 10) { toast.error("المبلغ الصحيح والسبب مطلوبان — 10 أحرف على الأقل"); return; }
    const current = BigInt(asset === "coins" ? c.coins : c.pearls);
    if (debit && current - BigInt(amount) < (asset === "pearls" ? BigInt(c.locked_pearls) : 0n)) { toast.error("الرصيد المتاح لا يسمح بالخصم"); return; }
    setPending({ p_user_id: id, p_asset: asset, p_amount: `${debit ? "-" : ""}${amount}`, p_reason: reason.trim(), p_idempotency_key: crypto.randomUUID() });
  }
  return <div dir="rtl" className="space-y-4"><Card className="rounded-2xl shadow-none"><CardContent className="grid gap-4 p-5 sm:grid-cols-3"><div>الحضور: <b>{online ? "أونلاين" : "غير متصل / لا يوجد حضور حديث"}</b></div><div>تاريخ التسجيل: {fmtDate(c.profile.created_at)}</div><div>آخر ظهور: {fmtDate(c.presence?.last_seen_at ?? c.profile.last_seen_at)}</div></CardContent></Card>
    {has("economy.adjust") && <Card className="rounded-2xl shadow-none"><CardContent className="space-y-4 p-5"><h2 className="font-bold">إضافة وخصم الأرصدة</h2><div className="grid gap-3 sm:grid-cols-4"><select className="rounded-xl border bg-background p-3" value={asset} onChange={(e) => setAsset(e.target.value)}><option value="coins">كوينز</option><option value="pearls">لؤلؤ</option></select><select className="rounded-xl border bg-background p-3" value={debit ? "debit" : "credit"} onChange={(e) => setDebit(e.target.value === "debit")}><option value="credit">إضافة</option><option value="debit">خصم</option></select><Input dir="ltr" inputMode="numeric" placeholder="المبلغ" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, ""))} /><Input placeholder="سبب العملية" value={reason} onChange={(e) => setReason(e.target.value)} /></div><p>الرصيد الحالي: <b dir="ltr">{n(asset === "coins" ? c.coins : c.pearls)}</b> {asset === "pearls" && <>· لؤلؤ محجوز: <b dir="ltr">{n(c.locked_pearls)}</b></>}</p><Button onClick={prepare} disabled={context.isFetching || adjustment.isPending}>مراجعة وتأكيد العملية</Button><p className="text-xs text-muted-foreground">تُحفظ العملية في سجل المحفظة وسجل تدقيق مستقل. رسائل حساب يامو الرسمي ليست مربوطة بهذه العملية بعد.</p></CardContent></Card>}
    <Card className="rounded-2xl shadow-none"><CardContent className="space-y-4 p-5"><h2 className="font-bold">حسابات ظهرت على نفس معرف تثبيت التطبيق: <span dir="ltr">{c.related_accounts.length}</span></h2><p className="text-xs text-muted-foreground">يشمل الروابط السابقة والحالية. هذا دليل مشاركة معرف تثبيت، وليس إثبات ملكية الحسابات لشخص واحد. لا يتم الحظر أو نقل الوكالات تلقائيًا.</p>{c.related_accounts.map((r) => <div className="flex flex-wrap items-center gap-3 rounded-xl border p-4" key={r.user_id}><Avatar><AvatarImage src={r.avatar_url ?? undefined} /><AvatarFallback>{r.display_name?.slice(0, 1)}</AvatarFallback></Avatar><div className="flex-1"><b>{r.display_name}</b><p dir="ltr">{r.legacy_id}</p>{r.agencies.map((a, i) => <p key={i} className="text-xs text-muted-foreground">وكالة: {a.agency_id} · انضم {fmtDate(a.joined_at)} · {a.removed_at ? `أزيل ${fmtDate(a.removed_at)}` : "عضوية حالية"}</p>)}</div><Button variant="outline" asChild><Link to="/users/$id" params={{ id: r.user_id }}>فتح الحساب</Link></Button></div>)}{!c.related_accounts.length && <p className="text-muted-foreground">لا توجد حسابات أخرى مرتبطة بمعرف التثبيت المسجل.</p>}</CardContent></Card>
    <Dialog open={Boolean(pending)} onOpenChange={(open) => { if (!open && !adjustment.isPending) setPending(null); }}><DialogContent><DialogHeader><DialogTitle>تأكيد تعديل الرصيد</DialogTitle></DialogHeader>{pending && <><p>{BigInt(pending.p_amount) > 0n ? "إضافة" : "خصم"} <b dir="ltr">{n(pending.p_amount)}</b> {pending.p_asset === "coins" ? "كوينز" : "لؤلؤ"}</p><p>{pending.p_reason}</p><p>الرصيد يُفحص لحظة التنفيذ. عند فشل الطلب، إعادة المحاولة بنفس النافذة تستخدم نفس مفتاح العملية.</p><Button disabled={adjustment.isPending} onClick={() => adjustment.mutate(pending)}>تأكيد التنفيذ</Button></>}</DialogContent></Dialog>
    <ActiveAccountDevices key={id} id={id} />
  </div>;
}
