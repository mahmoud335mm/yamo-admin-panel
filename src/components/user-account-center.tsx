import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { fmtNum, fmtDate } from "@/lib/charging-utils";
import { toast } from "sonner";
import { UserNetworkSignals } from "@/components/user-network-signals";

export function UserAccountCenter({ id }: { id: string }) {
  const qc = useQueryClient();
  const { has } = usePermissions();
  const [tab, setTab] = useState("wallet");
  const [page, setPage] = useState(0);
  const [status, setStatus] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const user = useQuery({ queryKey: ["user", id], queryFn: async () => {
    const { data, error } = await supabase.from("admin_profiles").select("*").eq("id", id).maybeSingle();
    if (error) throw error; return data;
  }, refetchInterval: 30000 });
  const sources: Record<string, { table: string; field: string; order: string; select?: string }> = {
    wallet: { table: "yamo_wallet_events", field: "user_id", order: "created_at" },
    earnings: { table: "yamo_agency_host_earnings", field: "user_id", order: "earned_at" },
    agencies: { table: "yamo_agency_hosts", field: "user_id", order: "joined_at", select: "agency_id,joined_at,removed_at,yamo_agencies:agency_id(name)" },
    recharge: { table: "yamo_recharge_requests", field: "user_id", order: "created_at" },
    games: { table: "game_bets", field: "user_id", order: "created_at" },
    devices: { table: "device_account_bindings", field: "user_id", order: "bound_at", select: "id,platform,bound_at,last_seen_at,released_at,release_reason" },
    bans: { table: "account_bans", field: "user_id", order: "created_at" },
  };
  const source = sources[tab];
  const records = useQuery({ queryKey: ["user-records", id, tab, page], enabled: Boolean(source) && user.isSuccess && Boolean(user.data), queryFn: async () => {
    const { data, error } = await (supabase as any).from(source.table).select(source.select ?? "*", { count: "exact" }).eq(source.field, id).order(source.order, { ascending: false }).range(page * 25, page * 25 + 24);
    if (error) throw error; return (data ?? []) as Record<string, unknown>[];
  }});
  const changeStatus = useMutation({ mutationFn: async () => {
    if (!has("users.moderate")) throw new Error("ليست لديك صلاحية إدارة حالة المستخدمين");
    if (!user.data || !status || reason.trim().length < 10) throw new Error("سبب القرار مطلوب — 10 أحرف على الأقل");
    const { error } = await supabase.rpc("admin_set_yamo_account_status" as never, { p_legacy_id: user.data.legacy_id, p_status: status, p_note: reason.trim() } as never);
    if (error) throw error;
  }, onSuccess: () => { setStatus(null); setReason(""); toast.success("تم تعديل حالة الحساب"); qc.invalidateQueries({ queryKey: ["user", id] }); qc.invalidateQueries({ queryKey: ["users"] }); }, onError: (e: Error) => toast.error(e.message) });
  if (user.isLoading) return <p>جاري التحميل…</p>;
  if (user.error) return <p role="alert" className="text-destructive">تعذر قراءة الحساب: {user.error.message}</p>;
  if (!user.data) return <p>الحساب غير موجود أو غير متاح لصلاحياتك.</p>;
  const u = user.data;
  return <div className="space-y-5" dir="rtl"><Button asChild variant="outline"><Link to="/users">الرجوع إلى المستخدمين</Link></Button><Card className="rounded-2xl shadow-none"><CardContent className="flex flex-wrap items-center gap-5 p-6"><Avatar className="h-20 w-20"><AvatarImage src={u.avatar_url ?? undefined} /><AvatarFallback>{u.display_name?.slice(0, 1)}</AvatarFallback></Avatar><div className="flex-1"><h1 className="text-2xl font-bold">{u.display_name}</h1><p dir="ltr">{u.legacy_id}</p><p className="mt-2 text-muted-foreground">حالة الحساب: {u.account_status === "active" ? "نشط" : u.account_status === "banned" ? "محظور" : u.account_status} · LV {u.level ?? "—"} · VIP {u.vip_level ?? 0}</p></div><div><span>كوينز</span><b className="block text-xl" dir="ltr">{fmtNum(u.coins)}</b></div><div><span>لؤلؤ</span><b className="block text-xl" dir="ltr">{fmtNum(u.pearls)}</b></div>{has("users.moderate") && <Button variant={u.account_status === "banned" ? "outline" : "destructive"} onClick={() => { setReason(""); setStatus(u.account_status === "banned" ? "active" : "banned"); }}>{u.account_status === "banned" ? "فك حظر الحساب" : "حظر الحساب"}</Button>}</CardContent></Card>
    <div className="flex flex-wrap gap-2 rounded-xl border bg-card p-3">{[["wallet", "المعاملات"], ["earnings", "الأرباح"], ["agencies", "الوكالات"], ["recharge", "الشحن"], ["games", "الألعاب"], ["devices", "الأجهزة"], ["bans", "الحظر"], ["recovery", "الاسترجاع والترابط"]].map(([key, label]) => <Button key={key} variant={tab === key ? "default" : "outline"} onClick={() => { setTab(key); setPage(0); }}>{label}</Button>)}</div>
    {tab === "recovery" ? <Card><CardContent className="p-6 text-muted-foreground">تغيير بريد الدخول وفك ربط الأجهزة والحسابات واسترجاع الحساب المحذوف تحتاج مسارات استرجاع وتدقيق على السيرفر. لا توجد عمليات حذف نهائي أو تغيير بريد مباشر في هذه المرحلة. مشاركة الشبكة أو المنطقة وحدها ليست دليلًا لربط الحسابات.</CardContent></Card> : <Card className="rounded-2xl shadow-none"><CardContent className="space-y-4 p-5">{tab === "devices" && <UserNetworkSignals id={id} />}<p className="text-xs text-muted-foreground">بيانات المصدر الفعلي، بدون سجلات تجريبية. البيانات المعروضة خاضعة لصلاحيات الحساب الإداري.</p>{records.isLoading && <p>جاري قراءة السجل…</p>}{records.error && <p role="alert" className="text-destructive">مصدر السجل يحتاج مراجعة أو صلاحية: {(records.error as Error).message}</p>}{records.isSuccess && !records.data.length && <p>لا توجد سجلات متاحة من هذا المصدر لهذا الحساب.</p>}{records.data?.map((row, i) => <div key={String(row.id ?? i)} className="rounded-xl border p-4"><div className="grid gap-3 sm:grid-cols-3">{Object.entries(row).filter(([key]) => !["metadata", "snapshot", "payout_details", "proof_path"].includes(key)).map(([key, value]) => <div key={key}><span className="text-xs text-muted-foreground">{({ id: "معرف السجل", source: "مصدر الربح", pearls: "اللؤلؤ", amount: "المبلغ", asset: "الرصيد", reason: "نوع العملية", reference_id: "مرجع العملية", created_at: "التاريخ", earned_at: "تاريخ الربح", joined_at: "تاريخ الانضمام", removed_at: "تاريخ الإزالة", agency_id: "معرف الوكالة", yamo_agencies: "الوكالة", status: "الحالة", user_id: "معرف الحساب" } as Record<string, string>)[key] ?? key}</span><p className="break-all text-sm">{value == null ? "—" : key.endsWith("_at") ? fmtDate(String(value)) : typeof value === "object" ? JSON.stringify(value) : String(value)}</p></div>)}</div></div>)}<div className="flex items-center gap-3"><Button variant="outline" disabled={!page || records.isFetching} onClick={() => setPage(page - 1)}>السابق</Button><span dir="ltr">{page + 1}</span><Button variant="outline" disabled={(records.data?.length ?? 0) < 25 || records.isFetching} onClick={() => setPage(page + 1)}>التالي</Button><Button variant="outline" onClick={() => records.refetch()}>تحديث السجل</Button></div></CardContent></Card>}
    <Dialog open={status !== null} onOpenChange={(open) => { if (!open && !changeStatus.isPending) setStatus(null); }}><DialogContent><DialogHeader><DialogTitle>تأكيد {status === "banned" ? "حظر الحساب" : "فك الحظر"}</DialogTitle></DialogHeader><p>{u.display_name} · {u.legacy_id}</p><Input placeholder="سبب القرار — 10 أحرف على الأقل" value={reason} onChange={(e) => setReason(e.target.value)} /><Button disabled={reason.trim().length < 10 || changeStatus.isPending} onClick={() => changeStatus.mutate()}>تأكيد التنفيذ</Button></DialogContent></Dialog>
  </div>;
}
