import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
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
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Loader2,
  ArrowRight,
  Power,
  PauseCircle,
  PlayCircle,
  Coins,
  Gem,
  Users,
  Activity,
  RefreshCw,
  ShieldCheck,
} from "lucide-react";
import { toast } from "sonner";
import { ChargingFinancialControl } from "@/components/charging-financial-control";
import { ChargingPricingPanel } from "./charging-pricing";
import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip, CartesianGrid } from "recharts";
import {
  CHARGING_AGENCY_STATUS,
  CHARGING_TXN_STATUS,
  AGENT_ROLE_LABELS,
  fmtDate,
  fmtNum,
} from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-agencies/$id")({
  component: () => (
    <PermissionGuard permission="charging_agencies.read">
      <Page />
    </PermissionGuard>
  ),
});

function Page() {
  const { id } = Route.useParams();
  const qc = useQueryClient();
  const { has } = usePermissions();
  const [tab, setTab] = useState("overview");
  const [memberSearch, setMemberSearch] = useState("");
  const refresh = () => Promise.all([
    qc.invalidateQueries({ queryKey: ["charging_agency", id] }),
    qc.invalidateQueries({ queryKey: ["charging_agency_owner"] }),
    qc.invalidateQueries({ queryKey: ["charging_agency_stats", id] }),
    qc.invalidateQueries({ queryKey: ["charging_agency_members", id] }),
    qc.invalidateQueries({ queryKey: ["charging_agency_coin_txns", id] }),
    qc.invalidateQueries({ queryKey: ["charging_agency_pearl_txns", id] }),
    qc.invalidateQueries({ queryKey: ["charging_financial_control", id] }),
  ]);

  const agency = useQuery({
    queryKey: ["charging_agency", id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("charging_agencies")
        .select("*")
        .eq("id", id)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const owner = useQuery({
    queryKey: ["charging_agency_owner", agency.data?.owner_user_id],
    enabled: Boolean(agency.data?.owner_user_id),
    queryFn: async () => {
      const ownerId = agency.data!.owner_user_id!;
      const [{ data: profile, error: profileError }, { data: wallet, error: walletError }] =
        await Promise.all([
          supabase
            .from("profiles")
            .select("id,legacy_id,display_name,avatar_url")
            .eq("id", ownerId)
            .maybeSingle(),
          supabase.from("wallets").select("coins,pearls").eq("user_id", ownerId).maybeSingle(),
        ]);
      if (profileError) throw profileError;
      if (walletError) throw walletError;
      return { profile, wallet };
    },
  });

  const stats = useQuery({
    queryKey: ["charging_agency_stats", id],
    queryFn: async () => {
      const since = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);
      const { data, error } = await supabase
        .from("charging_agency_daily_stats")
        .select("day,coins_sent,pearls_sent,pearls_bought,pearls_exchanged,transfer_count")
        .eq("agency_id", id)
        .gte("day", since)
        .order("day", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  const members = useQuery({
    queryKey: ["charging_agency_members", id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("charging_agency_members")
        .select(
          "id, member_role, status, assigned_at, user_id, profiles:user_id(legacy_id, display_name, avatar_url)",
        )
        .eq("agency_id", id)
        .order("assigned_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  const coinTxns = useQuery({
    queryKey: ["charging_agency_coin_txns", id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("charging_coin_transfers")
        .select("id, reference, amount, status, created_at, agent_user_id, recipient_user_id")
        .eq("agency_id", id)
        .order("created_at", { ascending: false })
        .limit(50);
      if (error) throw error;
      return data ?? [];
    },
  });

  const pearlTxns = useQuery({
    queryKey: ["charging_agency_pearl_txns", id, members.data],
    enabled: members.isSuccess,
    queryFn: async () => {
      const ids = members.data!.map((m) => m.user_id);
      if (agency.data?.owner_user_id) ids.push(agency.data.owner_user_id);
      if (!ids.length) return [];
      const unique = [...new Set(ids)];
      const { data, error } = await supabase
        .from("charging_pearl_transfers")
        .select("id,reference,amount,status,created_at,from_user_id,to_user_id")
        .or(`from_user_id.in.(${unique.join(",")}),to_user_id.in.(${unique.join(",")})`)
        .order("created_at", { ascending: false })
        .limit(50);
      if (error) throw error;
      return data ?? [];
    },
  });

  const suspend = useMutation({
    mutationFn: async (reason: string) => {
      const { error } = await supabase.rpc("suspend_charging_agency", {
        _agency_id: id,
        _reason: reason,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("تم التعليق");
      qc.invalidateQueries({ queryKey: ["charging_agency", id] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const reactivate = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("reactivate_charging_agency", {
        _agency_id: id,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("تم التفعيل");
      qc.invalidateQueries({ queryKey: ["charging_agency", id] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const close = useMutation({
    mutationFn: async (reason: string) => {
      const { error } = await supabase.rpc("close_charging_agency", {
        _agency_id: id,
        _reason: reason,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("تم الإغلاق");
      qc.invalidateQueries({ queryKey: ["charging_agency", id] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  if (agency.isLoading)
    return (
      <div className="py-16 text-center">
        <Loader2 className="mx-auto h-6 w-6 animate-spin" />
      </div>
    );
  if (agency.error) return <div role="alert" className="rounded-xl border p-6 text-destructive">تعذر تحميل الوكالة: {agency.error.message}<Button className="mr-3" variant="outline" onClick={() => agency.refetch()}>إعادة المحاولة</Button></div>;
  if (!agency.data)
    return <div className="py-16 text-center text-muted-foreground">الوكالة غير موجودة</div>;
  const a = agency.data;
  const monthStats = stats.data ?? [];
  const monthCoins = monthStats.reduce((sum, row) => sum + Number(row.coins_sent ?? 0), 0);
  const monthPearls = monthStats.reduce(
    (sum, row) => sum + Number(row.pearls_sent ?? 0) + Number(row.pearls_bought ?? 0),
    0,
  );
  const monthTransfers = monthStats.reduce((sum, row) => sum + Number(row.transfer_count ?? 0), 0);

  return (
    <div className="space-y-6" dir="rtl">
      <div className="flex items-center justify-between"><div><h1 className="text-2xl font-bold">إدارة وكالة الشحن</h1><p className="mt-1 text-sm text-muted-foreground">الأرصدة والعمليات والوكلاء وإعدادات الوكالة</p></div><Button variant="outline" onClick={refresh} disabled={agency.isFetching}><RefreshCw className={`ml-2 h-4 w-4 ${agency.isFetching ? "animate-spin" : ""}`} />تحديث</Button></div>
      <div className="flex flex-wrap items-center justify-between gap-4 rounded-2xl border bg-card p-5">
        <div>
          <div className="flex items-center gap-3">
            <Link to="/charging-agencies">
              <Button size="sm" variant="ghost">
                <ArrowRight className="h-4 w-4" />
              </Button>
            </Link>
            <Avatar className="h-12 w-12 border-2 border-primary/20">
              <AvatarImage src={owner.data?.profile?.avatar_url ?? a.logo_url ?? undefined} />
              <AvatarFallback>{a.name.slice(0, 2)}</AvatarFallback>
            </Avatar>
            <h1 className="text-2xl font-bold">{a.name}</h1>
            <Badge>{CHARGING_AGENCY_STATUS[a.status] ?? a.status}</Badge>
          </div>
          <p className="mt-2 text-sm text-muted-foreground">{owner.data?.profile?.display_name ?? "—"} · <span dir="ltr">{owner.data?.profile?.legacy_id ?? "—"}</span> · <span dir="ltr">{a.display_id}</span></p>
        </div>
        <div className="flex gap-2">
          {has("charging_finance.manage") && <Button variant="outline" onClick={() => setTab("settings")}>تعديل البيانات</Button>}
          {a.status === "active" && has("charging_agencies.suspend") && (
            <ReasonAction
              label="تعليق"
              icon={<PauseCircle className="ml-1 h-4 w-4" />}
              variant="outline"
              onSubmit={(r) => suspend.mutate(r)}
            />
          )}
          {a.status === "suspended" && has("charging_agencies.suspend") && (
            <Button variant="outline" onClick={() => reactivate.mutate()}>
              <PlayCircle className="ml-1 h-4 w-4" /> إعادة تفعيل
            </Button>
          )}
          {a.status !== "closed" && has("charging_agencies.close") && (
            <ReasonAction
              label="إغلاق"
              icon={<Power className="ml-1 h-4 w-4" />}
              variant="destructive"
              onSubmit={(r) => close.mutate(r)}
            />
          )}
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Summary
          label="رصيد الكوينز"
          value={owner.isSuccess ? fmtNum(owner.data?.wallet?.coins ?? 0) : "—"}
          hint="رصيد مالك الوكالة"
          icon={<Coins />}
        />
        <Summary
          label="رصيد اللؤلؤ"
          value={owner.isSuccess ? fmtNum(owner.data?.wallet?.pearls ?? 0) : "—"}
          hint="الرصيد الحالي"
          icon={<Gem />}
          orange
        />
        <Summary
          label="حركة آخر 30 يومًا"
          value={fmtNum(monthCoins)}
          hint={`${fmtNum(monthTransfers)} عملية`}
          icon={<Activity />}
        />
        <Summary
          label="حركة اللؤلؤ"
          value={fmtNum(monthPearls)}
          hint={`${fmtNum(members.data?.length ?? 0)} وكيل`}
          icon={<Users />}
          orange
        />
      </div>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="h-auto w-full flex-wrap justify-start gap-2 rounded-xl border bg-muted/30 p-2">
          <TabsTrigger value="overview">نظرة عامة</TabsTrigger>
          <TabsTrigger value="finance">التحكم المالي</TabsTrigger>
          <TabsTrigger value="logs">السجلات</TabsTrigger>
          <TabsTrigger value="agents">الوكلاء</TabsTrigger>
          <TabsTrigger value="pricing">الباقات والأسعار</TabsTrigger>
          <TabsTrigger value="settings">الإعدادات</TabsTrigger>
        </TabsList>
        <TabsContent value="finance"><ChargingFinancialControl agency={a} view="finance" /></TabsContent>
        <TabsContent value="logs"><ChargingFinancialControl agency={a} view="logs" /><div className="mt-4 flex gap-3"><Button variant="outline" onClick={() => setTab("transfers")}>تحويلات الكوينز</Button><Button variant="outline" onClick={() => setTab("pearls")}>تحويلات اللؤلؤ</Button></div></TabsContent>
        <TabsContent value="pricing"><p className="mb-4 rounded-xl border bg-muted/20 p-4 text-sm">هذه أسعار المنصة العامة وتُطبّق على وكالات الشحن، وليست أسعارًا خاصة بهذه الوكالة.</p><PermissionGuard permission="charging_pricing.read"><ChargingPricingPanel /></PermissionGuard></TabsContent>
        {(tab === "transfers" || tab === "pearls") && <Button variant="outline" onClick={() => setTab("logs")}>الرجوع إلى السجلات</Button>}
        <TabsContent value="overview" className="space-y-4">
          <Card className="rounded-2xl shadow-none"><CardHeader className="flex flex-row items-center justify-between"><CardTitle className="text-base">حركة الكوينز خلال آخر 30 يومًا</CardTitle><Button variant="outline" onClick={() => setTab("finance")}>تعديل الرصيد</Button></CardHeader><CardContent>{stats.error ? <p role="alert" className="text-destructive">تعذر تحميل المؤشرات: {stats.error.message}</p> : stats.isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : monthStats.length === 0 ? <p className="py-10 text-center text-muted-foreground">لا توجد حركة مسجلة لهذه الفترة.</p> : <div className="h-64" dir="ltr"><ResponsiveContainer width="100%" height="100%"><AreaChart data={[...monthStats].reverse()}><CartesianGrid strokeDasharray="3 3" vertical={false} /><XAxis dataKey="day" tickFormatter={(v: string) => v.slice(5)} /><YAxis tickFormatter={(v: number) => new Intl.NumberFormat("en-US", { notation: "compact" }).format(v)} /><Tooltip formatter={(v) => [fmtNum(Number(v)), "كوينز مرسلة"]} /><Area type="monotone" dataKey="coins_sent" stroke="var(--primary)" fill="var(--primary)" fillOpacity={0.12} /></AreaChart></ResponsiveContainer></div>}</CardContent></Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-sm">بيانات الوكالة والمالك</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 text-sm sm:grid-cols-3">
              <div className="col-span-2 flex items-center gap-3 rounded-xl border bg-muted/20 p-3 sm:col-span-3">
                <Avatar className="h-12 w-12">
                  <AvatarImage src={owner.data?.profile?.avatar_url ?? undefined} />
                  <AvatarFallback>
                    {owner.data?.profile?.display_name?.slice(0, 1) ?? "?"}
                  </AvatarFallback>
                </Avatar>
                <div>
                  <b>{owner.data?.profile?.display_name ?? "مالك غير محدد"}</b>
                  <div className="font-mono text-xs text-muted-foreground" dir="ltr">
                    {owner.data?.profile?.legacy_id ?? "-"}
                  </div>
                </div>
              </div>
              <KV k="الدولة" v={a.country ?? "-"} />{" "}
              <KV k="العملة" v={a.default_currency ?? "-"} />
              <KV k="الهاتف" v={a.phone ?? "-"} />{" "}
              <KV k="المستوى" v={String(a.level_id ?? "-")} />
              <KV k="الحد اليومي كوينز" v={fmtNum(a.daily_coin_transfer_limit)} />
              <KV k="الحد الشهري كوينز" v={fmtNum(a.monthly_coin_transfer_limit)} />
              <KV k="تاريخ الإنشاء" v={fmtDate(a.created_at)} />
              <KV k="نسبة العمولة" v={`${a.commission_rate ?? 0}%`} />
              <KV k="آخر تحديث" v={fmtDate(a.updated_at)} />
            </CardContent>
          </Card>
        </TabsContent>
        <TabsContent value="agents">
          <Card>
            <CardHeader><div className="flex flex-wrap items-center justify-between gap-3"><CardTitle>وكلاء هذه الوكالة</CardTitle><Link to="/charging-agents"><Button variant="outline">إدارة وإضافة الوكلاء</Button></Link></div><Input placeholder="بحث باسم الوكيل أو ID…" value={memberSearch} onChange={(e) => setMemberSearch(e.target.value)} /></CardHeader>
            <CardContent className="pt-4">
              {members.error && <p role="alert" className="text-destructive">تعذر تحميل الوكلاء: {members.error.message}</p>}
              {members.isLoading ? (
                <Loader2 className="mx-auto h-5 w-5 animate-spin" />
              ) : !members.data?.length ? (
                <div className="py-8 text-center text-sm text-muted-foreground">لا يوجد وكلاء</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>الوكيل</TableHead>
                      <TableHead>الدور</TableHead>
                      <TableHead>الحالة</TableHead>
                      <TableHead>تاريخ التعيين</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {members.data.filter((m) => { const p = m.profiles as { legacy_id?: string; display_name?: string } | null; return `${p?.display_name ?? ""} ${p?.legacy_id ?? ""}`.toLowerCase().includes(memberSearch.trim().toLowerCase()); }).map((m) => {
                      const p = m.profiles as { legacy_id?: string; display_name?: string; avatar_url?: string } | null;
                      return (
                        <TableRow key={m.id}>
                          <TableCell>
                            <Avatar className="mb-2 h-10 w-10"><AvatarImage src={p?.avatar_url ?? undefined} /><AvatarFallback>{p?.display_name?.slice(0, 1) ?? "؟"}</AvatarFallback></Avatar>
                            <Link
                              to="/charging-agents/$id"
                              params={{ id: m.user_id }}
                              className="text-primary hover:underline"
                            >
                              {p?.display_name ?? "-"}
                            </Link>
                            <div className="font-mono text-xs text-muted-foreground">
                              {p?.legacy_id ?? m.user_id.slice(0, 8)}
                            </div>
                          </TableCell>
                          <TableCell>{AGENT_ROLE_LABELS[m.member_role] ?? m.member_role}</TableCell>
                          <TableCell>
                            <Badge variant="secondary">{m.status}</Badge>
                          </TableCell>
                          <TableCell className="text-xs">{fmtDate(m.assigned_at)}</TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>
        <TabsContent value="transfers">
          <Card>
            <CardContent className="pt-4">
              {coinTxns.error && <p role="alert" className="text-destructive">تعذر تحميل التحويلات: {coinTxns.error.message}</p>}
              {coinTxns.isLoading ? (
                <Loader2 className="mx-auto h-5 w-5 animate-spin" />
              ) : !coinTxns.data?.length ? (
                <div className="py-8 text-center text-sm text-muted-foreground">
                  لا توجد تحويلات
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>المرجع</TableHead>
                      <TableHead>المبلغ</TableHead>
                      <TableHead>الحالة</TableHead>
                      <TableHead>التاريخ</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {coinTxns.data?.map((t) => (
                      <TableRow key={t.id}>
                        <TableCell className="font-mono text-xs">{t.reference}</TableCell>
                        <TableCell>{fmtNum(t.amount)}</TableCell>
                        <TableCell>
                          <Badge variant="secondary">
                            {CHARGING_TXN_STATUS[t.status] ?? t.status}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs">{fmtDate(t.created_at)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>
        <TabsContent value="pearls">
          <Card>
            <CardContent className="pt-4">
              {pearlTxns.error && <p role="alert" className="text-destructive">تعذر تحميل تحويلات اللؤلؤ: {pearlTxns.error.message}</p>}
              {pearlTxns.isLoading ? (
                <Loader2 className="mx-auto h-5 w-5 animate-spin" />
              ) : !pearlTxns.data?.length ? (
                <div className="py-8 text-center text-sm text-muted-foreground">
                  لا توجد تحويلات لؤلؤ
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>المرجع</TableHead>
                      <TableHead>المبلغ</TableHead>
                      <TableHead>من</TableHead>
                      <TableHead>إلى</TableHead>
                      <TableHead>الحالة</TableHead>
                      <TableHead>التاريخ</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {pearlTxns.data.map((t) => (
                      <TableRow key={t.id}>
                        <TableCell className="font-mono text-xs" dir="ltr">
                          {t.reference}
                        </TableCell>
                        <TableCell className="font-mono" dir="ltr">
                          {fmtNum(t.amount)}
                        </TableCell>
                        <TableCell className="font-mono text-xs" dir="ltr">
                          {t.from_user_id.slice(0, 8)}
                        </TableCell>
                        <TableCell className="font-mono text-xs" dir="ltr">
                          {t.to_user_id.slice(0, 8)}
                        </TableCell>
                        <TableCell>
                          <Badge variant="secondary">
                            {CHARGING_TXN_STATUS[t.status] ?? t.status}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs">{fmtDate(t.created_at)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>
        <TabsContent value="settings" className="space-y-4">
          <ChargingFinancialControl agency={a} view="settings" />
          <div className="grid gap-4 md:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-sm">
                  <RefreshCw className="h-4 w-4" />
                  حدود التحويل
                </CardTitle>
              </CardHeader>
              <CardContent className="grid grid-cols-2 gap-4">
                <KV k="كوينز يومي" v={fmtNum(a.daily_coin_transfer_limit)} />
                <KV k="كوينز شهري" v={fmtNum(a.monthly_coin_transfer_limit)} />
                <KV k="لؤلؤ يومي" v={fmtNum(a.daily_pearl_transfer_limit)} />
                <KV k="لؤلؤ شهري" v={fmtNum(a.monthly_pearl_transfer_limit)} />
                <KV k="أقل تحويل كوينز" v={fmtNum(a.min_coin_transfer)} />
                <KV k="أقصى تحويل كوينز" v={fmtNum(a.max_coin_transfer)} />
              </CardContent>
            </Card>
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-sm">
                  <ShieldCheck className="h-4 w-4" />
                  الصلاحيات التشغيلية
                </CardTitle>
              </CardHeader>
              <CardContent className="grid grid-cols-2 gap-3">
                <Flag label="بيع الكوينز" value={a.can_sell_coins} />
                <Flag label="شراء اللؤلؤ" value={a.can_buy_pearls} />
                <Flag label="التحويل للوكلاء" value={a.can_transfer_to_agents} />
                <Flag label="الاستلام من الوكلاء" value={a.can_receive_from_agents} />
                <Flag label="تبديل اللؤلؤ" value={a.can_exchange_pearls_to_coins} />
              </CardContent>
            </Card>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}

function Summary({
  label,
  value,
  hint,
  icon,
  orange,
}: {
  label: string;
  value: string;
  hint: string;
  icon: React.ReactNode;
  orange?: boolean;
}) {
  return (
    <Card className="rounded-2xl shadow-none">
      <CardContent className="flex items-center justify-between p-5">
        <div>
          <div className="text-xs text-muted-foreground">{label}</div>
          <div className="mt-2 font-mono text-2xl font-black" dir="ltr">
            {value}
          </div>
          <div className="mt-1 text-xs text-muted-foreground">{hint}</div>
        </div>
        <div
          className={`rounded-2xl p-3 ${orange ? "bg-orange-500/15 text-orange-500" : "bg-primary/15 text-primary"}`}
        >
          {icon}
        </div>
      </CardContent>
    </Card>
  );
}

function Flag({ label, value }: { label: string; value: boolean }) {
  return (
    <div className="flex items-center justify-between rounded-lg border p-3 text-sm">
      <span>{label}</span>
      <Badge
        className={value ? "bg-emerald-500/15 text-emerald-500" : "bg-red-500/15 text-red-500"}
      >
        {value ? "مسموح" : "موقوف"}
      </Badge>
    </div>
  );
}

function KV({ k, v }: { k: string; v: string }) {
  return (
    <div>
      <div className="text-xs text-muted-foreground">{k}</div>
      <div className="font-medium">{v}</div>
    </div>
  );
}

function ReasonAction({
  label,
  icon,
  variant,
  onSubmit,
}: {
  label: string;
  icon?: React.ReactNode;
  variant: "outline" | "destructive";
  onSubmit: (r: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  return (
    <>
      <Button variant={variant} onClick={() => setOpen(true)}>
        {icon}
        {label}
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent dir="rtl">
          <DialogHeader>
            <DialogTitle>{label} — السبب</DialogTitle>
          </DialogHeader>
          <div>
            <Label>السبب (5 أحرف على الأقل)</Label>
            <Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>
              إلغاء
            </Button>
            <Button
              variant={variant}
              disabled={reason.length < 5}
              onClick={() => {
                onSubmit(reason);
                setOpen(false);
                setReason("");
              }}
            >
              {label}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
