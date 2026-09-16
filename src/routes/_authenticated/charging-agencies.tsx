import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  ArrowDownRight,
  ArrowUpRight,
  Banknote,
  Coins,
  Loader2,
  MoreHorizontal,
  Plus,
  RefreshCw,
  Search,
  Users,
  Zap,
} from "lucide-react";
import { toast } from "sonner";
import { CHARGING_AGENCY_STATUS, fmtDate, fmtNum } from "@/lib/charging-utils";
import worldCountries from "world-countries";
import { ChargingAgentsPanel } from "./charging-agents";
import { ChargingPricingPanel } from "./charging-pricing";
import { ChargingCoinTransfersPanel } from "./charging-coin-transfers";
import { ChargingPearlTransfersPanel } from "./charging-pearl-transfers";
import { ChargingLedgerPanel } from "./charging-ledger";
import { ChargingFinancialControl } from "@/components/charging-financial-control";

const COUNTRY_OPTIONS = worldCountries
  .filter((country) => country.status === "officially-assigned")
  .map((country) => ({
    code: country.cca2,
    name: country.translations.ara?.common ?? country.name.common,
    flag: country.flag,
    dial: `${country.idd.root ?? ""}${country.idd.suffixes?.[0] ?? ""}`,
    currency: Object.keys(country.currencies ?? {})[0] ?? "USD",
  }))
  .sort((a, b) => a.name.localeCompare(b.name, "ar"));

export const Route = createFileRoute("/_authenticated/charging-agencies")({
  component: () => (
    <PermissionGuard permission="charging_agencies.read">
      <Page />
    </PermissionGuard>
  ),
});
type Owner = {
  id: string;
  legacy_id: string | null;
  display_name: string | null;
  avatar_url: string | null;
};
type Wallet = { user_id: string; coins: number | null; pearls: number | null };
type Stat = {
  agency_id: string;
  day: string;
  coins_sent: number | null;
  transfer_count: number | null;
};

function Page() {
  const [section, setSection] = useState("agencies");
  const [selectedAgencyId, setSelectedAgencyId] = useState("");
  const [agencyTerm, setAgencyTerm] = useState("");
  const agencyChoices = useQuery({
    queryKey: ["charging_agency_selector", agencyTerm],
    queryFn: async () => {
      let query = supabase.from("charging_agencies").select("*").is("deleted_at", null).order("name").limit(50);
      const term = agencyTerm.trim().replace(/[(),%]/g, "");
      if (term) query = query.or(`name.ilike.%${term}%,display_id.ilike.%${term}%`);
      const { data, error } = await query;
      if (error) throw error;
      return data ?? [];
    },
  });
  const selectedAgency = useQuery({
    queryKey: ["charging_agency", selectedAgencyId],
    enabled: Boolean(selectedAgencyId),
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_agencies").select("*").eq("id", selectedAgencyId).maybeSingle();
      if (error) throw error;
      return data;
    },
  });
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("all");
  const [country, setCountry] = useState("all");
  const [page, setPage] = useState(0);
  const size = 25;
  const { has } = usePermissions();
  const qc = useQueryClient();
  const system = useQuery({
    queryKey: ["charging_system_settings"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("charging_system_settings")
        .select(
          "system_enabled,coin_packages_enabled,pearl_buy_enabled,pearl_exchange_enabled,usdt_packages_enabled,default_agent_commission",
        )
        .eq("id", true)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });
  const toggleSystem = useMutation({
    mutationFn: async (enabled: boolean) => {
      const { error } = await supabase.rpc("set_charging_system_enabled", {
        _enabled: enabled,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["charging_system_settings"] });
      toast.success("تم تطبيق حالة نظام وكالة الشحن فورًا");
    },
    onError: (error: Error) => toast.error(error.message),
  });
  const toggleFeature = useMutation({
    mutationFn: async ({ feature, enabled }: { feature: string; enabled: boolean }) => {
      const { error } = await supabase.rpc("set_charging_feature_enabled", {
        _feature: feature,
        _enabled: enabled,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["charging_system_settings"] });
      toast.success("تم تحديث الخدمة فورًا");
    },
    onError: (error: Error) => toast.error(error.message),
  });
  const list = useQuery({
    queryKey: ["charging_agencies_command_center", q, status, country, page],
    queryFn: async () => {
      let query = supabase
        .from("charging_agencies")
        .select(
          "id,display_id,name,country,city,status,default_currency,created_at,updated_at,owner_user_id,logo_url,commission_rate,daily_coin_transfer_limit",
          { count: "exact" },
        )
        .is("deleted_at", null)
        .order("updated_at", { ascending: false })
        .range(page * size, page * size + size - 1);
      if (q.trim())
        query = query.or(
          `name.ilike.%${q.trim()}%,display_id.ilike.%${q.trim()}%,country.ilike.%${q.trim()}%`,
        );
      if (status !== "all") query = query.eq("status", status as never);
      if (country !== "all") query = query.eq("country", country);
      const { data, count, error } = await query;
      if (error) throw error;
      const rows = data ?? [];
      const ownersIds = [...new Set(rows.map((r) => r.owner_user_id).filter(Boolean))] as string[];
      const agenciesIds = rows.map((r) => r.id);
      const today = new Date().toISOString().slice(0, 10);
      const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
      const [op, wa, st, me] = await Promise.all([
        ownersIds.length
          ? supabase
              .from("profiles")
              .select("id,legacy_id,display_name,avatar_url")
              .in("id", ownersIds)
          : Promise.resolve({ data: [], error: null }),
        ownersIds.length
          ? supabase.from("wallets").select("user_id,coins,pearls").in("user_id", ownersIds)
          : Promise.resolve({ data: [], error: null }),
        agenciesIds.length
          ? supabase
              .from("charging_agency_daily_stats")
              .select("agency_id,day,coins_sent,transfer_count")
              .in("agency_id", agenciesIds)
              .gte("day", yesterday)
          : Promise.resolve({ data: [], error: null }),
        agenciesIds.length
          ? supabase
              .from("charging_agency_members")
              .select("agency_id")
              .in("agency_id", agenciesIds)
              .eq("status", "active")
          : Promise.resolve({ data: [], error: null }),
      ]);
      if (op.error) throw op.error;
      if (wa.error) throw wa.error;
      if (st.error) throw st.error;
      if (me.error) throw me.error;
      const owners = new Map((op.data as Owner[]).map((x) => [x.id, x]));
      const wallets = new Map((wa.data as Wallet[]).map((x) => [x.user_id, x]));
      const stats = st.data as Stat[];
      const memberCounts = new Map<string, number>();
      for (const m of me.data ?? [])
        memberCounts.set(m.agency_id, (memberCounts.get(m.agency_id) ?? 0) + 1);
      return {
        total: count ?? 0,
        rows: rows.map((r) => {
          const current = stats.find((s) => s.agency_id === r.id && s.day === today);
          const previous = stats.find((s) => s.agency_id === r.id && s.day === yesterday);
          const now = Number(current?.coins_sent ?? 0),
            before = Number(previous?.coins_sent ?? 0);
          return {
            ...r,
            owner: r.owner_user_id ? owners.get(r.owner_user_id) : undefined,
            wallet: r.owner_user_id ? wallets.get(r.owner_user_id) : undefined,
            today: current,
            members: memberCounts.get(r.id) ?? 0,
            trend: before ? ((now - before) / before) * 100 : now ? 100 : 0,
          };
        }),
      };
    },
  });
  const countries = useQuery({
    queryKey: ["charging_agency_countries"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("charging_agencies")
        .select("country")
        .is("deleted_at", null);
      if (error) throw error;
      return [...new Set((data ?? []).map((x) => x.country).filter(Boolean))] as string[];
    },
  });
  const totals = useMemo(() => {
    const rows = list.data?.rows ?? [];
    return {
      active: rows.filter((r) => r.status === "active").length,
      coins: rows.reduce((s, r) => s + Number(r.wallet?.coins ?? 0), 0),
      transfers: rows.reduce((s, r) => s + Number(r.today?.transfer_count ?? 0), 0),
      volume: rows.reduce((s, r) => s + Number(r.today?.coins_sent ?? 0), 0),
    };
  }, [list.data]);
  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ["charging_agencies_command_center"] });
    await qc.invalidateQueries({ queryKey: ["charging_agency_countries"] });
    toast.success("تم تحديث بيانات وكالات الشحن");
  };
  return (
    <div className="space-y-6" dir="rtl">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-black">إدارة وكالات الشحن</h1>
            <Badge className="bg-gradient-to-l from-violet-600 to-orange-500 text-white" dir="ltr">
              V241
            </Badge>
          </div>
          <p className="mt-1 text-sm text-muted-foreground">
            منظومة جديدة موحّدة لإدارة الوكالات والوكلاء والأسعار والتحويلات والسجل في الوقت الفعلي.
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={refresh} disabled={list.isFetching}>
            <RefreshCw className={`ml-2 h-4 w-4 ${list.isFetching ? "animate-spin" : ""}`} />
            تحديث
          </Button>
          {has("charging_agencies.create") && <CreateDialog onDone={() => list.refetch()} />}
        </div>
      </div>
      {section === "settings" && <><Card
        className={
          system.data?.system_enabled === false ? "border-red-500/40" : "border-emerald-500/30"
        }
      >
        <CardContent className="flex flex-col gap-4 p-5 md:flex-row md:items-center md:justify-between">
          <div>
            <div className="flex items-center gap-2">
              <b>تشغيل منظومة وكالة الشحن</b>
              <Badge
                className={
                  system.data?.system_enabled === false
                    ? "bg-red-500/15 text-red-500"
                    : "bg-emerald-500/15 text-emerald-500"
                }
              >
                {system.data?.system_enabled === false ? "متوقفة" : "تعمل الآن"}
              </Badge>
            </div>
            <p className="mt-1 text-xs text-muted-foreground">
              عند الإيقاف تُمنع عمليات الشحن والسحب والتبديل وUSDT فورًا دون حذف البيانات.
            </p>
          </div>
          <Switch
            checked={system.data?.system_enabled ?? true}
            disabled={system.isLoading || toggleSystem.isPending}
            onCheckedChange={(enabled) => toggleSystem.mutate(enabled)}
          />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <b>تشغيل وإيقاف خدمات الشحن</b>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {[
            ["coin_packages", "باقات شحن الكوينز", system.data?.coin_packages_enabled],
            ["pearl_buy", "شراء وسحب اللؤلؤ", system.data?.pearl_buy_enabled],
            ["pearl_exchange", "تبديل اللؤلؤ إلى كوينز", system.data?.pearl_exchange_enabled],
            ["usdt_packages", "باقات USDT للوكلاء", system.data?.usdt_packages_enabled],
          ].map(([feature, label, enabled]) => (
            <label
              key={String(feature)}
              className="flex items-center justify-between rounded-xl border p-4"
            >
              <span className="text-sm font-medium">{String(label)}</span>
              <Switch
                checked={Boolean(enabled)}
                disabled={!system.data?.system_enabled || toggleFeature.isPending}
                onCheckedChange={(value) =>
                  toggleFeature.mutate({ feature: String(feature), enabled: value })
                }
              />
            </label>
          ))}
        </CardContent>
      </Card>
      </>}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Metric
          title="إجمالي الوكالات"
          value={list.data?.total ?? 0}
          sub={`${fmtNum(totals.active)} وكالة نشطة`}
          icon={<Users />}
        />
        <Metric
          title="الرصيد المتاح"
          value={totals.coins}
          sub="كوينز لدى ملاك الوكالات"
          icon={<Coins />}
          orange
        />
        <Metric
          title="تحويلات اليوم"
          value={totals.transfers}
          sub={`${fmtNum(totals.volume)} كوينز`}
          icon={<RefreshCw />}
        />
        <Metric
          title="حجم حركة اليوم"
          value={totals.volume}
          sub="إجمالي الكوينز المحولة"
          icon={<Banknote />}
          orange
        />
      </div>
      <div className="flex flex-wrap gap-2 rounded-2xl border bg-card p-3">
        {[
          ["agencies", "نظرة عامة"],
          ["finance", "التحكم المالي"],
          ["ledger", "السجلات"],
          ["agents", "الوكلاء"],
          ["pricing", "الأسعار والباقات"],
          ["settings", "الإعدادات"],
        ].map(([key, label]) => (
          <Button
            key={key}
            size="sm"
            variant={section === key ? "default" : "outline"}
            onClick={() => setSection(key)}
          >
            {label}
          </Button>
        ))}
      </div>
      {(section === "finance" || section === "settings") && <Card className="rounded-2xl shadow-none"><CardHeader><b>اختيار وكالة الشحن</b><p className="text-sm text-muted-foreground">ابحث باسم الوكالة أو معرفها ثم اخترها لعرض أرصدتها والتحكم فيها.</p></CardHeader><CardContent className="space-y-4"><Input placeholder="اسم الوكالة أو CHG-ID…" value={agencyTerm} onChange={(e) => setAgencyTerm(e.target.value)} /><select className="w-full rounded-xl border bg-background p-3" value={selectedAgencyId} onChange={(e) => setSelectedAgencyId(e.target.value)}><option value="">اختر الوكالة</option>{selectedAgency.data && !agencyChoices.data?.some((a) => a.id === selectedAgencyId) && <option value={selectedAgencyId}>{selectedAgency.data.name} — {selectedAgency.data.display_id}</option>}{agencyChoices.data?.map((a) => <option key={a.id} value={a.id}>{a.name} — {a.display_id}</option>)}</select>{agencyChoices.error && <p role="alert" className="text-destructive">تعذر تحميل الاقتراحات: {agencyChoices.error.message}</p>}{selectedAgency.isFetching && <Loader2 className="h-5 w-5 animate-spin" />}{selectedAgency.error && <p role="alert" className="text-destructive">تعذر تحميل الوكالة: {selectedAgency.error.message}</p>}{selectedAgency.data && <ChargingFinancialControl key={`${selectedAgencyId}-${section}`} agency={selectedAgency.data} view={section === "finance" ? "finance" : "settings"} />}</CardContent></Card>}
      {section === "agencies" && (
        <Card className="overflow-hidden">
          <CardHeader className="border-b bg-muted/20">
            <div className="flex flex-col gap-3 xl:flex-row">
              <div className="relative flex-1">
                <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  placeholder="ابحث باسم الوكالة أو الكود أو الدولة…"
                  value={q}
                  onChange={(e) => {
                    setQ(e.target.value);
                    setPage(0);
                  }}
                  className="pr-9"
                />
              </div>
              <Select
                value={status}
                onValueChange={(v) => {
                  setStatus(v);
                  setPage(0);
                }}
              >
                <SelectTrigger className="xl:w-44">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">كل الحالات</SelectItem>
                  {Object.entries(CHARGING_AGENCY_STATUS).map(([k, v]) => (
                    <SelectItem key={k} value={k}>
                      {v}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select
                value={country}
                onValueChange={(v) => {
                  setCountry(v);
                  setPage(0);
                }}
              >
                <SelectTrigger className="xl:w-44">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">كل الدول</SelectItem>
                  {(countries.data ?? []).map((x) => (
                    <SelectItem key={x} value={x}>
                      {x}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {list.isLoading ? (
              <div className="py-20">
                <Loader2 className="mx-auto h-7 w-7 animate-spin" />
              </div>
            ) : list.isError ? (
              <div className="py-20 text-center text-destructive">
                فشل التحميل: {(list.error as Error).message}
              </div>
            ) : !list.data!.rows.length ? (
              <div className="flex flex-col items-center gap-3 py-20">
                <Zap className="h-12 w-12 text-muted-foreground" />
                <span>لا توجد وكالات مطابقة</span>
              </div>
            ) : (
              <>
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow className="bg-muted/30">
                        <TableHead>#</TableHead>
                        <TableHead>الوكالة</TableHead>
                        <TableHead>المالك / ID</TableHead>
                        <TableHead>الكوينز</TableHead>
                        <TableHead>اللؤلؤ</TableHead>
                        <TableHead>حد اليوم</TableHead>
                        <TableHead>الوكلاء</TableHead>
                        <TableHead>الأداء</TableHead>
                        <TableHead>الحالة</TableHead>
                        <TableHead>آخر تحديث</TableHead>
                        <TableHead />
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {list.data!.rows.map((r, i) => (
                        <TableRow key={r.id}>
                          <TableCell className="font-mono" dir="ltr">
                            {page * size + i + 1}
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-3">
                              <Avatar className="h-11 w-11 border-2 border-primary/20">
                                <AvatarImage src={r.logo_url ?? undefined} />
                                <AvatarFallback>{r.name.slice(0, 2)}</AvatarFallback>
                              </Avatar>
                              <div>
                                <Link
                                  to="/charging-agencies/$id"
                                  params={{ id: r.id }}
                                  className="font-bold hover:text-primary"
                                >
                                  {r.name}
                                </Link>
                                <div
                                  className="font-mono text-[11px] text-muted-foreground"
                                  dir="ltr"
                                >
                                  {r.display_id} · {r.country ?? "-"}
                                </div>
                              </div>
                            </div>
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-2">
                              <Avatar className="h-8 w-8">
                                <AvatarImage src={r.owner?.avatar_url ?? undefined} />
                                <AvatarFallback>
                                  {r.owner?.display_name?.slice(0, 1) ?? "?"}
                                </AvatarFallback>
                              </Avatar>
                              <div>
                                <div className="text-sm">{r.owner?.display_name ?? "غير محدد"}</div>
                                <div
                                  className="font-mono text-[11px] text-muted-foreground"
                                  dir="ltr"
                                >
                                  {r.owner?.legacy_id ?? "-"}
                                </div>
                              </div>
                            </div>
                          </TableCell>
                          <TableCell className="font-mono" dir="ltr">
                            {fmtNum(r.wallet?.coins ?? 0)}
                          </TableCell>
                          <TableCell className="font-mono" dir="ltr">
                            {fmtNum(r.wallet?.pearls ?? 0)}
                          </TableCell>
                          <TableCell className="font-mono text-xs" dir="ltr">
                            {fmtNum(r.daily_coin_transfer_limit ?? 0)}
                          </TableCell>
                          <TableCell className="font-mono" dir="ltr">
                            {r.members}
                          </TableCell>
                          <TableCell>
                            <Trend value={r.trend} />
                          </TableCell>
                          <TableCell>
                            <Status status={r.status} />
                          </TableCell>
                          <TableCell className="text-xs text-muted-foreground">
                            {fmtDate(r.updated_at)}
                          </TableCell>
                          <TableCell>
                            <Link to="/charging-agencies/$id" params={{ id: r.id }}>
                              <Button size="icon" variant="ghost">
                                <MoreHorizontal className="h-4 w-4" />
                              </Button>
                            </Link>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
                <div className="flex justify-between border-t p-4 text-sm">
                  <span>
                    الإجمالي:{" "}
                    <b className="font-mono" dir="ltr">
                      {fmtNum(list.data!.total)}
                    </b>
                  </span>
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={!page}
                      onClick={() => setPage((x) => x - 1)}
                    >
                      السابق
                    </Button>
                    <span className="p-2 font-mono" dir="ltr">
                      {page + 1}
                    </span>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={(page + 1) * size >= list.data!.total}
                      onClick={() => setPage((x) => x + 1)}
                    >
                      التالي
                    </Button>
                  </div>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      )}
      {section === "agents" && <ChargingAgentsPanel />}
      {section === "pricing" && <ChargingPricingPanel />}
      {section === "coins" && <ChargingCoinTransfersPanel />}
      {section === "pearls" && <ChargingPearlTransfersPanel />}
      {section === "ledger" && <><div className="flex gap-2"><Button variant="outline" onClick={() => setSection("coins")}>تحويلات الكوينز</Button><Button variant="outline" onClick={() => setSection("pearls")}>تحويلات اللؤلؤ</Button></div><ChargingLedgerPanel /></>}
      {(section === "coins" || section === "pearls") && <Button variant="outline" onClick={() => setSection("ledger")}>الرجوع إلى السجلات</Button>}
      {section === "ledger" && <Card className="rounded-2xl shadow-none"><CardHeader><b>سجل تعديلات الإدارة لوكالة محددة</b></CardHeader><CardContent><select className="mb-4 w-full rounded-xl border bg-background p-3" value={selectedAgencyId} onChange={(e) => setSelectedAgencyId(e.target.value)}><option value="">اختر الوكالة لعرض تعديلات الإدارة والعكس</option>{agencyChoices.data?.map((a) => <option key={a.id} value={a.id}>{a.name} — {a.display_id}</option>)}</select>{selectedAgency.data && <ChargingFinancialControl key={selectedAgencyId} agency={selectedAgency.data} view="logs" />}</CardContent></Card>}
    </div>
  );
}

function Metric({
  title,
  value,
  sub,
  icon,
  orange,
}: {
  title: string;
  value: number;
  sub: string;
  icon: React.ReactNode;
  orange?: boolean;
}) {
  return (
    <Card>
      <CardContent className="flex items-center justify-between p-5">
        <div>
          <p className="text-sm text-muted-foreground">{title}</p>
          <p className="mt-2 font-mono text-2xl font-black" dir="ltr">
            {fmtNum(value)}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">{sub}</p>
        </div>
        <div
          className={`grid h-12 w-12 place-items-center rounded-2xl ${orange ? "bg-orange-500/15 text-orange-500" : "bg-primary/15 text-primary"}`}
        >
          {icon}
        </div>
      </CardContent>
    </Card>
  );
}
function Nav({
  to,
  label,
  active,
}: {
  to:
    | "/charging-agencies"
    | "/charging-agents"
    | "/charging-coin-transfers"
    | "/charging-pearl-transfers"
    | "/charging-ledger"
    | "/charging-pricing";
  label: string;
  active?: boolean;
}) {
  return (
    <Link to={to}>
      <Button size="sm" variant={active ? "default" : "outline"}>
        {label}
      </Button>
    </Link>
  );
}
function Trend({ value }: { value: number }) {
  const up = value >= 0;
  return (
    <span
      className={`flex items-center gap-1 font-mono text-xs font-bold ${up ? "text-emerald-500" : "text-red-500"}`}
      dir="ltr"
    >
      {up ? <ArrowUpRight className="h-4 w-4" /> : <ArrowDownRight className="h-4 w-4" />}
      {up ? "+" : ""}
      {value.toFixed(1)}%
    </span>
  );
}
function Status({ status }: { status: string }) {
  return (
    <Badge
      className={
        status === "active"
          ? "bg-emerald-500/15 text-emerald-500"
          : status === "suspended" || status === "closed"
            ? "bg-red-500/15 text-red-500"
            : "bg-amber-500/15 text-amber-500"
      }
    >
      {CHARGING_AGENCY_STATUS[status] ?? status}
    </Badge>
  );
}

function CreateDialog({ onDone }: { onDone: () => void }) {
  const [open, setOpen] = useState(false),
    [name, setName] = useState(""),
    [country, setCountry] = useState(""),
    [currency, setCurrency] = useState("USD"),
    [ownerQuery, setOwnerQuery] = useState(""),
    [owner, setOwner] = useState<Owner | null>(null),
    [dialCode, setDialCode] = useState("+20"),
    [commission, setCommission] = useState("0"),
    [phone, setPhone] = useState("");
  const navigate = useNavigate();
  const qc = useQueryClient();
  const suggestions = useQuery({
    queryKey: ["charging_owner_suggestions", ownerQuery],
    enabled: open && ownerQuery.trim().length > 0,
    queryFn: async () => {
      const term = ownerQuery.trim();
      const { data, error } = await supabase
        .from("profiles")
        .select("id,legacy_id,display_name,avatar_url")
        .or(`legacy_id.ilike.%${term}%,display_name.ilike.%${term}%`)
        .limit(8);
      if (error) throw error;
      return data as Owner[];
    },
  });
  const create = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc("create_charging_agency", {
        _name: name.trim(),
        _country: country || null,
        _city: null,
        _default_currency: currency,
        _owner_user_id: owner?.id ?? null,
        _deputy_user_id: null,
        _phone: phone ? `${dialCode}${phone.replace(/^0+/, "")}` : null,
        _email: null,
      } as never);
      if (error) throw error;
      const agencyId = data as string;
      const { error: commissionError } = await supabase.rpc("set_charging_agency_commission", {
        _agency_id: agencyId,
        _commission_rate: Number(commission || 0),
      } as never);
      if (commissionError) throw commissionError;
      return agencyId;
    },
    onSuccess: (id) => {
      toast.success("تم إنشاء وكالة الشحن");
      qc.invalidateQueries({ queryKey: ["charging_agencies_command_center"] });
      setOpen(false);
      onDone();
      if (id) navigate({ to: "/charging-agencies/$id", params: { id } });
    },
    onError: (e: Error) => toast.error(e.message),
  });
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button className="bg-orange-500 text-white hover:bg-orange-600">
          <Plus className="ml-2 h-4 w-4" />
          إضافة وكالة شحن
        </Button>
      </DialogTrigger>
      <DialogContent dir="rtl" className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>إنشاء وكالة شحن</DialogTitle>
        </DialogHeader>
        <div className="grid gap-4 py-2 sm:grid-cols-2">
          <div className="sm:col-span-2">
            <Label>اسم الوكالة *</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="relative sm:col-span-2">
            <Label>المالك — ابحث بالاسم أو ID *</Label>
            <Input
              value={ownerQuery}
              onChange={(e) => {
                setOwnerQuery(e.target.value);
                setOwner(null);
              }}
            />
            {!owner && suggestions.data?.length ? (
              <div className="absolute z-50 mt-1 w-full rounded-lg border bg-popover p-1 shadow-xl">
                {suggestions.data.map((x) => (
                  <button
                    key={x.id}
                    type="button"
                    className="flex w-full items-center gap-3 rounded-md p-2 text-right hover:bg-muted"
                    onClick={() => {
                      setOwner(x);
                      setOwnerQuery(`${x.display_name} · ${x.legacy_id}`);
                    }}
                  >
                    <Avatar className="h-9 w-9">
                      <AvatarImage src={x.avatar_url ?? undefined} />
                      <AvatarFallback>{x.display_name?.slice(0, 1)}</AvatarFallback>
                    </Avatar>
                    <span>
                      <b className="block">{x.display_name}</b>
                      <small className="font-mono" dir="ltr">
                        {x.legacy_id}
                      </small>
                    </span>
                  </button>
                ))}
              </div>
            ) : null}
          </div>
          <div>
            <Label>واتساب *</Label>
            <div className="flex gap-2" dir="ltr">
              <Input className="w-24" value={dialCode} readOnly />
              <Input
                value={phone}
                onChange={(e) => setPhone(e.target.value.replace(/\D/g, ""))}
                placeholder="1001234567"
              />
            </div>
          </div>
          <div>
            <Label>الدولة</Label>
            <Select
              value={country}
              onValueChange={(code) => {
                const selected = COUNTRY_OPTIONS.find((item) => item.code === code);
                setCountry(code);
                if (selected) {
                  setDialCode(selected.dial);
                  setCurrency(selected.currency);
                }
              }}
            >
              <SelectTrigger>
                <SelectValue placeholder="اختر الدولة" />
              </SelectTrigger>
              <SelectContent className="max-h-72">
                {COUNTRY_OPTIONS.map((item) => (
                  <SelectItem key={item.code} value={item.code}>
                    {item.flag} {item.name} ({item.dial})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>العملة</Label>
            <Input
              dir="ltr"
              value={currency}
              onChange={(e) => setCurrency(e.target.value.toUpperCase())}
            />
          </div>
          <div>
            <Label>نسبة ربح الوكيل %</Label>
            <Input
              dir="ltr"
              type="number"
              min="0"
              max="100"
              step="0.01"
              value={commission}
              onChange={(e) => setCommission(e.target.value)}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            إلغاء
          </Button>
          <Button
            disabled={
              !name.trim() ||
              !owner ||
              !country ||
              !phone.trim() ||
              Number(commission) < 0 ||
              Number(commission) > 100 ||
              create.isPending
            }
            onClick={() => create.mutate()}
          >
            {create.isPending && <Loader2 className="ml-2 h-4 w-4 animate-spin" />}إنشاء
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
