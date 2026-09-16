import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Loader2 } from "lucide-react";
import { fmtNum } from "@/lib/charging-utils";

export function UsersCommandCenter() {
  const [search, setSearch] = useState("");
  const [term, setTerm] = useState("");
  const [page, setPage] = useState(0);
  const users = useQuery({ queryKey: ["users", term, page], queryFn: async () => {
    let query = supabase.from("admin_profiles").select("*", { count: "exact" }).order("legacy_id").range(page * 24, page * 24 + 23);
    const safe = term.trim().replace(/[(),%]/g, "");
    if (safe) query = query.or(`legacy_id.ilike.%${safe}%,display_name.ilike.%${safe}%`);
    const { data, error, count } = await query;
    if (error) throw error;
    return { rows: data ?? [], count: count ?? 0 };
  }, refetchInterval: 30000 });
  return <div dir="rtl" className="space-y-6"><div className="flex items-center justify-between"><div><h1 className="text-3xl font-bold">مركز المستخدمين</h1><p className="mt-2 text-muted-foreground">الحسابات الحقيقية وأرصدتها · V242</p></div><Button variant="outline" disabled={users.isFetching} onClick={() => users.refetch()}>تحديث</Button></div>
    <form className="flex gap-3 rounded-2xl border bg-card p-4" onSubmit={(e) => { e.preventDefault(); setTerm(search); setPage(0); }}><Input placeholder="ابحث باسم الحساب أو ID" value={search} onChange={(e) => setSearch(e.target.value)} /><Button type="submit">بحث</Button></form>
    {users.error && <p role="alert" className="text-destructive">تعذر قراءة المستخدمين: {users.error.message}</p>}
    {users.isLoading && <Loader2 className="mx-auto h-6 w-6 animate-spin" />}
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">{users.data?.rows.map((u) => <Card key={u.id} className="rounded-2xl shadow-none"><CardContent className="space-y-4 p-5"><div className="flex items-center gap-3"><Avatar className="h-14 w-14"><AvatarImage src={u.avatar_url ?? undefined} /><AvatarFallback>{u.display_name?.slice(0, 1) ?? "؟"}</AvatarFallback></Avatar><div className="min-w-0 flex-1"><h2 className="truncate font-bold">{u.display_name}</h2><p className="text-xs text-muted-foreground" dir="ltr">{u.legacy_id}</p></div><Badge variant={u.account_status === "banned" ? "destructive" : "secondary"}>{u.account_status === "active" ? "نشط" : u.account_status === "banned" ? "محظور" : u.account_status}</Badge></div><div className="grid grid-cols-2 gap-3 rounded-xl bg-muted/30 p-3"><div><span className="text-xs text-muted-foreground">كوينز</span><b className="block" dir="ltr">{fmtNum(u.coins)}</b></div><div><span className="text-xs text-muted-foreground">لؤلؤ</span><b className="block" dir="ltr">{fmtNum(u.pearls)}</b></div></div><div className="flex gap-2"><Badge variant="outline">LV {u.level ?? "—"}</Badge><Badge variant="outline">VIP {u.vip_level ?? 0}</Badge></div><Button className="w-full" variant="outline" asChild><Link to="/users/$id" params={{ id: u.id }}>فتح مركز الحساب</Link></Button></CardContent></Card>)}</div>
    {users.isSuccess && !users.data.rows.length && <p className="py-12 text-center text-muted-foreground">لا توجد حسابات مطابقة.</p>}
    <div className="flex items-center justify-between"><span>الحسابات: <b dir="ltr">{fmtNum(users.data?.count ?? 0)}</b></span><div className="flex items-center gap-3"><Button variant="outline" disabled={!page || users.isFetching} onClick={() => setPage(page - 1)}>السابق</Button><span dir="ltr">{page + 1}</span><Button variant="outline" disabled={users.isFetching || (page + 1) * 24 >= (users.data?.count ?? 0)} onClick={() => setPage(page + 1)}>التالي</Button></div></div>
  </div>;
}
