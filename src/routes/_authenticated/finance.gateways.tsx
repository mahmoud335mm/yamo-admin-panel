import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { PermissionGuard } from "@/components/permission-guard";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger, DialogDescription } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import {
  Plus, Search, Landmark, Play, Pause, Activity, Webhook, AlertTriangle,
  KeyRound, ArrowLeftRight, CheckCircle2, XCircle, RefreshCw, ShieldAlert, Eye
} from "lucide-react";
import { fmtDate } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/finance/gateways")({
  component: () => (
    <PermissionGuard permission="payment_gateways.read">
      <GatewaysPage />
    </PermissionGuard>
  ),
});

type Gateway = {
  id: string; code: string; name: string; provider: string;
  logo_url: string | null; mode: "test" | "live";
  supported_countries: string[] | null; supported_currencies: string[] | null;
  min_amount: number; max_amount: number | null;
  fixed_fee: number; percentage_fee: number;
  callback_url: string | null; webhook_url: string | null;
  webhook_secret_ref: string | null; api_key_secret_ref: string | null;
  status: "active" | "inactive" | "maintenance" | "deprecated";
  priority: number;
  health_status: "healthy" | "degraded" | "down" | "unknown" | "misconfigured";
  last_health_check_at: string | null;
  metadata: Record<string, unknown> | null;
  updated_at: string;
};

const HEALTH: Record<string, { label: string; cls: string }> = {
  healthy:       { label: "سليمة",     cls: "bg-emerald-500/15 text-emerald-500" },
  degraded:      { label: "متدهورة",   cls: "bg-orange-500/15 text-orange-500" },
  down:          { label: "متوقفة",    cls: "bg-destructive/15 text-destructive" },
  unknown:       { label: "غير محدد",  cls: "bg-muted text-muted-foreground" },
  misconfigured: { label: "غير مضبوطة", cls: "bg-yellow-500/15 text-yellow-600" },
};
const STATUS: Record<string, { label: string; cls: string }> = {
  active:      { label: "مفعّلة",  cls: "bg-emerald-500/15 text-emerald-500" },
  inactive:    { label: "موقوفة",  cls: "bg-muted text-muted-foreground" },
  maintenance: { label: "صيانة",   cls: "bg-orange-500/15 text-orange-500" },
  deprecated:  { label: "مهجورة",  cls: "bg-destructive/15 text-destructive" },
};

/* ============================================================ */
function GatewaysPage() {
  const { has } = usePermissions();
  const qc = useQueryClient();
  const [q, setQ] = useState("");
  const [mode, setMode] = useState<string>("all");
  const [status, setStatus] = useState<string>("all");
  const [health, setHealth] = useState<string>("all");
  const [openCreate, setOpenCreate] = useState(false);
  const [selected, setSelected] = useState<Gateway | null>(null);

  const listQ = useQuery({
    queryKey: ["payment_gateways", q, mode, status, health],
    queryFn: async () => {
      let query = supabase.from("payment_gateways").select("*").order("priority", { ascending: true });
      if (q) query = query.or(`code.ilike.%${q}%,name.ilike.%${q}%,provider.ilike.%${q}%`);
      if (mode !== "all") query = query.eq("mode", mode as "test" | "live");
      if (status !== "all") query = query.eq("status", status as Gateway["status"]);
      if (health !== "all") query = query.eq("health_status", health as Gateway["health_status"]);
      const { data, error } = await query;
      if (error) throw error;
      return (data ?? []) as Gateway[];
    },
  });

  const statsQ = useQuery({
    queryKey: ["payment_gateway_stats"],
    queryFn: async () => {
      const { data, error } = await supabase.from("payment_gateway_stats" as never).select("*");
      if (error) return [] as Array<{ gateway_id: string; success_count: number; failure_count: number; last_webhook_at: string | null; total_failures: number }>;
      return data as Array<{ gateway_id: string; success_count: number; failure_count: number; last_webhook_at: string | null; total_failures: number }>;
    },
  });

  const statsMap = new Map((statsQ.data ?? []).map((s) => [s.gateway_id, s]));

  const exportCsv = () => {
    const rows = listQ.data ?? [];
    const headers = ["code","name","provider","mode","status","health","priority","countries","currencies","min","max","fixed_fee","pct_fee","last_check"];
    const body = rows.map((g) => [
      g.code, g.name, g.provider, g.mode, g.status, g.health_status, g.priority,
      (g.supported_countries ?? []).join("|"), (g.supported_currencies ?? []).join("|"),
      g.min_amount, g.max_amount ?? "", g.fixed_fee, g.percentage_fee, g.last_health_check_at ?? "",
    ].join(","));
    const csv = [headers.join(","), ...body].join("\n");
    const blob = new Blob([csv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `payment_gateways_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click(); URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2"><Landmark className="h-6 w-6" /> بوابات الدفع</h1>
          <p className="text-sm text-muted-foreground">مزوّدو الدفع التقنيون المربوطون بمنصة يامو مع فصل واضح بين Test و Live.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => { listQ.refetch(); statsQ.refetch(); }}>
            <RefreshCw className="ml-1 h-3.5 w-3.5" /> تحديث
          </Button>
          <Button variant="outline" onClick={exportCsv} disabled={!listQ.data?.length}>تصدير CSV</Button>
          {has("payment_gateways.create") && (
            <Dialog open={openCreate} onOpenChange={setOpenCreate}>
              <DialogTrigger asChild><Button><Plus className="ml-1 h-4 w-4" /> بوابة جديدة</Button></DialogTrigger>
              <CreateDialog onDone={() => { setOpenCreate(false); qc.invalidateQueries({ queryKey: ["payment_gateways"] }); }} />
            </Dialog>
          )}
        </div>
      </div>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative flex-1 min-w-[220px]">
              <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="ابحث بالكود، الاسم، المزود…" className="pr-9" />
            </div>
            <Select value={mode} onValueChange={setMode}>
              <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">كل الأوضاع</SelectItem>
                <SelectItem value="test">Test</SelectItem>
                <SelectItem value="live">Live</SelectItem>
              </SelectContent>
            </Select>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">كل الحالات</SelectItem>
                {Object.entries(STATUS).map(([k, v]) => <SelectItem key={k} value={k}>{v.label}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={health} onValueChange={setHealth}>
              <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">كل حالات الصحة</SelectItem>
                {Object.entries(HEALTH).map(([k, v]) => <SelectItem key={k} value={k}>{v.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </CardHeader>
        <CardContent>
          {listQ.isLoading ? (
            <div className="space-y-2">{[...Array(4)].map((_, i) => <Skeleton key={i} className="h-12" />)}</div>
          ) : listQ.error ? (
            <div className="text-destructive text-sm">فشل التحميل: {(listQ.error as Error).message}</div>
          ) : !listQ.data?.length ? (
            <div className="text-center py-10 text-muted-foreground">لا توجد بوابات مطابقة.</div>
          ) : (
            <div className="overflow-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>البوابة</TableHead>
                    <TableHead>الوضع</TableHead>
                    <TableHead>الحالة</TableHead>
                    <TableHead>الصحة</TableHead>
                    <TableHead>الأولوية</TableHead>
                    <TableHead>الدول / العملات</TableHead>
                    <TableHead>الرسوم</TableHead>
                    <TableHead>نجاح / فشل</TableHead>
                    <TableHead>آخر Webhook</TableHead>
                    <TableHead>آخر فحص</TableHead>
                    <TableHead>إجراءات</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {listQ.data.map((g) => {
                    const s = statsMap.get(g.id);
                    return (
                      <TableRow key={g.id}>
                        <TableCell>
                          <div className="font-medium">{g.name}</div>
                          <div className="text-xs text-muted-foreground">{g.code} · {g.provider}</div>
                        </TableCell>
                        <TableCell>
                          <Badge className={g.mode === "live" ? "bg-emerald-600 text-white" : "bg-yellow-500/20 text-yellow-600"}>
                            {g.mode === "live" ? "LIVE" : "TEST"}
                          </Badge>
                        </TableCell>
                        <TableCell><Badge className={STATUS[g.status].cls}>{STATUS[g.status].label}</Badge></TableCell>
                        <TableCell><Badge className={HEALTH[g.health_status].cls}>{HEALTH[g.health_status].label}</Badge></TableCell>
                        <TableCell>{g.priority}</TableCell>
                        <TableCell className="text-xs">
                          {(g.supported_countries ?? []).slice(0, 3).join(", ") || "—"}<br />
                          <span className="text-muted-foreground">{(g.supported_currencies ?? []).join(", ") || "—"}</span>
                        </TableCell>
                        <TableCell className="text-xs">
                          {g.fixed_fee > 0 ? `${g.fixed_fee}` : "0"} + {g.percentage_fee}%
                        </TableCell>
                        <TableCell className="text-xs">
                          <span className="text-emerald-500">{s?.success_count ?? 0}</span> / <span className="text-destructive">{s?.failure_count ?? 0}</span>
                        </TableCell>
                        <TableCell className="text-xs">{s?.last_webhook_at ? fmtDate(s.last_webhook_at) : "—"}</TableCell>
                        <TableCell className="text-xs">{g.last_health_check_at ? fmtDate(g.last_health_check_at) : "—"}</TableCell>
                        <TableCell>
                          <Button size="sm" variant="ghost" onClick={() => setSelected(g)}><Eye className="h-4 w-4" /></Button>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {selected && <GatewayDrawer gateway={selected} onClose={() => setSelected(null)} onChanged={() => { qc.invalidateQueries({ queryKey: ["payment_gateways"] }); qc.invalidateQueries({ queryKey: ["payment_gateway_stats"] }); }} />}
    </div>
  );
}

/* ============================================================ */
function CreateDialog({ onDone }: { onDone: () => void }) {
  const [code, setCode] = useState(""); const [name, setName] = useState(""); const [provider, setProvider] = useState("");
  const [countries, setCountries] = useState(""); const [currencies, setCurrencies] = useState("");
  const [minA, setMinA] = useState("0"); const [maxA, setMaxA] = useState("");
  const [fixedFee, setFixedFee] = useState("0"); const [pctFee, setPctFee] = useState("0");
  const [priority, setPriority] = useState("100");
  const [webhookUrl, setWebhookUrl] = useState(""); const [callbackUrl, setCallbackUrl] = useState("");
  const [logo, setLogo] = useState("");

  const mut = useMutation({
    mutationFn: async () => {
      if (!code.trim() || code.length < 2) throw new Error("الكود مطلوب (حرفان على الأقل)");
      if (!name.trim() || !provider.trim()) throw new Error("الاسم والمزود مطلوبان");
      const { data, error } = await supabase.rpc("create_payment_gateway", {
        _code: code.trim(), _name: name.trim(), _provider: provider.trim(), _mode: "test",
        _logo_url: logo.trim() || undefined,
        _countries: countries.split(",").map((s) => s.trim().toUpperCase()).filter(Boolean),
        _currencies: currencies.split(",").map((s) => s.trim().toUpperCase()).filter(Boolean),
        _min_amount: Number(minA) || 0, _max_amount: maxA ? Number(maxA) : undefined,
        _fixed_fee: Number(fixedFee) || 0, _percentage_fee: Number(pctFee) || 0,
        _priority: Number(priority) || 100,
        _callback_url: callbackUrl.trim() || undefined, _webhook_url: webhookUrl.trim() || undefined,
      });
      if (error) throw error; return data;
    },
    onSuccess: () => { toast.success("تم إنشاء البوابة (Test، موقوفة)"); onDone(); },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
      <DialogHeader>
        <DialogTitle>بوابة دفع جديدة</DialogTitle>
        <DialogDescription>تُنشأ البوابة في وضع Test وحالة موقوفة. لا يمكن الانتقال إلى Live قبل إعداد الأسرار والدول والعملات.</DialogDescription>
      </DialogHeader>
      <div className="grid grid-cols-2 gap-3">
        <div><Label>الكود *</Label><Input value={code} onChange={(e) => setCode(e.target.value)} placeholder="STC_PAY" /></div>
        <div><Label>المزود *</Label><Input value={provider} onChange={(e) => setProvider(e.target.value)} placeholder="stcpay / stripe / paytabs" /></div>
        <div className="col-span-2"><Label>الاسم *</Label><Input value={name} onChange={(e) => setName(e.target.value)} placeholder="STC Pay" /></div>
        <div className="col-span-2"><Label>الشعار (URL)</Label><Input value={logo} onChange={(e) => setLogo(e.target.value)} /></div>
        <div><Label>الدول (مفصولة بفواصل)</Label><Input value={countries} onChange={(e) => setCountries(e.target.value)} placeholder="SA, AE, EG" /></div>
        <div><Label>العملات</Label><Input value={currencies} onChange={(e) => setCurrencies(e.target.value)} placeholder="SAR, USD" /></div>
        <div><Label>الحد الأدنى</Label><Input type="number" value={minA} onChange={(e) => setMinA(e.target.value)} /></div>
        <div><Label>الحد الأقصى</Label><Input type="number" value={maxA} onChange={(e) => setMaxA(e.target.value)} /></div>
        <div><Label>رسوم ثابتة</Label><Input type="number" value={fixedFee} onChange={(e) => setFixedFee(e.target.value)} /></div>
        <div><Label>رسوم نسبية %</Label><Input type="number" step="0.01" value={pctFee} onChange={(e) => setPctFee(e.target.value)} /></div>
        <div><Label>الأولوية</Label><Input type="number" value={priority} onChange={(e) => setPriority(e.target.value)} /></div>
        <div className="col-span-2"><Label>Callback URL</Label><Input value={callbackUrl} onChange={(e) => setCallbackUrl(e.target.value)} /></div>
        <div className="col-span-2"><Label>Webhook URL</Label><Input value={webhookUrl} onChange={(e) => setWebhookUrl(e.target.value)} /></div>
      </div>
      <DialogFooter>
        <Button disabled={mut.isPending} onClick={() => mut.mutate()}>{mut.isPending ? "جارٍ الإنشاء…" : "إنشاء"}</Button>
      </DialogFooter>
    </DialogContent>
  );
}

/* ============================================================ */
function GatewayDrawer({ gateway, onClose, onChanged }: { gateway: Gateway; onClose: () => void; onChanged: () => void }) {
  const [tab, setTab] = useState("overview");
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-5xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {gateway.name}
            <Badge className={gateway.mode === "live" ? "bg-emerald-600 text-white" : "bg-yellow-500/20 text-yellow-600"}>
              {gateway.mode === "live" ? "LIVE" : "TEST"}
            </Badge>
            <Badge className={STATUS[gateway.status].cls}>{STATUS[gateway.status].label}</Badge>
            <Badge className={HEALTH[gateway.health_status].cls}>{HEALTH[gateway.health_status].label}</Badge>
          </DialogTitle>
          <DialogDescription>{gateway.code} · {gateway.provider}</DialogDescription>
        </DialogHeader>

        <Tabs value={tab} onValueChange={setTab}>
          <TabsList className="grid grid-cols-6">
            <TabsTrigger value="overview">نظرة عامة</TabsTrigger>
            <TabsTrigger value="edit">التعديل</TabsTrigger>
            <TabsTrigger value="secrets"><KeyRound className="ml-1 h-3.5 w-3.5" /> الأسرار</TabsTrigger>
            <TabsTrigger value="health"><Activity className="ml-1 h-3.5 w-3.5" /> الصحة</TabsTrigger>
            <TabsTrigger value="webhooks"><Webhook className="ml-1 h-3.5 w-3.5" /> Webhooks</TabsTrigger>
            <TabsTrigger value="failures"><AlertTriangle className="ml-1 h-3.5 w-3.5" /> الأعطال</TabsTrigger>
          </TabsList>

          <TabsContent value="overview"><OverviewTab g={gateway} onChanged={onChanged} /></TabsContent>
          <TabsContent value="edit"><EditTab g={gateway} onChanged={onChanged} /></TabsContent>
          <TabsContent value="secrets"><SecretsTab g={gateway} onChanged={onChanged} /></TabsContent>
          <TabsContent value="health"><HealthTab g={gateway} onChanged={onChanged} /></TabsContent>
          <TabsContent value="webhooks"><WebhooksTab gatewayId={gateway.id} /></TabsContent>
          <TabsContent value="failures"><FailuresTab gatewayId={gateway.id} onChanged={onChanged} /></TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}

/* ------------------- OVERVIEW ------------------- */
function OverviewTab({ g, onChanged }: { g: Gateway; onChanged: () => void }) {
  const { has } = usePermissions();
  const [reason, setReason] = useState("");
  const [confirmMode, setConfirmMode] = useState<"live" | "test" | null>(null);

  const enable = useMutation({
    mutationFn: async () => { const { error } = await supabase.rpc("enable_payment_gateway", { _id: g.id, _reason: reason }); if (error) throw error; },
    onSuccess: () => { toast.success("تم التفعيل"); setReason(""); onChanged(); },
    onError: (e: Error) => toast.error(e.message),
  });
  const disable = useMutation({
    mutationFn: async () => { const { error } = await supabase.rpc("disable_payment_gateway", { _id: g.id, _reason: reason }); if (error) throw error; },
    onSuccess: () => { toast.success("تم التعطيل"); setReason(""); onChanged(); },
    onError: (e: Error) => toast.error(e.message),
  });
  const changeMode = useMutation({
    mutationFn: async (m: "test" | "live") => {
      const { error } = await supabase.rpc("change_payment_gateway_mode", { _id: g.id, _new_mode: m, _reason: reason });
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم تغيير الوضع"); setReason(""); setConfirmMode(null); onChanged(); },
    onError: (e: Error) => { toast.error(e.message); },
  });

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Stat label="الأولوية" value={String(g.priority)} />
        <Stat label="الحد الأدنى / الأقصى" value={`${g.min_amount} — ${g.max_amount ?? "∞"}`} />
        <Stat label="الرسوم" value={`${g.fixed_fee} + ${g.percentage_fee}%`} />
        <Stat label="آخر تحديث" value={fmtDate(g.updated_at)} />
      </div>
      <Card><CardContent className="pt-4 space-y-2 text-sm">
        <Row k="الدول المدعومة"  v={(g.supported_countries ?? []).join(", ") || "—"} />
        <Row k="العملات المدعومة" v={(g.supported_currencies ?? []).join(", ") || "—"} />
        <Row k="Callback URL"    v={g.callback_url || "—"} />
        <Row k="Webhook URL"     v={g.webhook_url || "—"} />
        <Row k="Webhook Secret"  v={g.webhook_secret_ref ? "✓ Configured" : "✗ Missing"} />
        <Row k="API Key"         v={g.api_key_secret_ref ? "✓ Configured" : "✗ Missing"} />
      </CardContent></Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">الإجراءات الحساسة</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <Textarea placeholder="السبب (5 أحرف على الأقل)" value={reason} onChange={(e) => setReason(e.target.value)} />
          <div className="flex flex-wrap gap-2">
            {has("payment_gateways.enable") && g.status !== "active" && (
              <Button size="sm" onClick={() => enable.mutate()} disabled={reason.trim().length < 5 || enable.isPending}>
                <Play className="ml-1 h-3.5 w-3.5" /> تفعيل
              </Button>
            )}
            {has("payment_gateways.disable") && g.status === "active" && (
              <Button size="sm" variant="destructive" onClick={() => disable.mutate()} disabled={reason.trim().length < 5 || disable.isPending}>
                <Pause className="ml-1 h-3.5 w-3.5" /> تعطيل
              </Button>
            )}
            {has("payment_gateways.change_mode") && (
              <Button size="sm" variant="outline" onClick={() => setConfirmMode(g.mode === "live" ? "test" : "live")}>
                <ArrowLeftRight className="ml-1 h-3.5 w-3.5" /> تحويل إلى {g.mode === "live" ? "TEST" : "LIVE"}
              </Button>
            )}
          </div>
        </CardContent>
      </Card>

      {confirmMode && (
        <Dialog open onOpenChange={() => setConfirmMode(null)}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2"><ShieldAlert className="h-5 w-5 text-orange-500" /> تأكيد تغيير الوضع</DialogTitle>
              <DialogDescription>
                سيتم تحويل البوابة إلى <b>{confirmMode === "live" ? "LIVE" : "TEST"}</b>.
                {confirmMode === "live" && " يستلزم Live توفر الأسرار وWebhook URL ودولة وعملة على الأقل."}
              </DialogDescription>
            </DialogHeader>
            <Textarea placeholder="السبب (5 أحرف على الأقل)" value={reason} onChange={(e) => setReason(e.target.value)} />
            <DialogFooter>
              <Button variant="ghost" onClick={() => setConfirmMode(null)}>إلغاء</Button>
              <Button disabled={reason.trim().length < 5 || changeMode.isPending} onClick={() => changeMode.mutate(confirmMode)}>
                {changeMode.isPending ? "…" : "تأكيد"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return <div className="rounded-lg border p-3"><div className="text-xs text-muted-foreground">{label}</div><div className="mt-1 text-lg font-semibold">{value}</div></div>;
}
function Row({ k, v }: { k: string; v: string }) {
  return <div className="flex justify-between border-b py-1 last:border-0"><span className="text-muted-foreground">{k}</span><span className="font-mono text-xs">{v}</span></div>;
}

/* ------------------- EDIT ------------------- */
function EditTab({ g, onChanged }: { g: Gateway; onChanged: () => void }) {
  const { has } = usePermissions();
  const [name, setName] = useState(g.name);
  const [provider, setProvider] = useState(g.provider);
  const [countries, setCountries] = useState((g.supported_countries ?? []).join(", "));
  const [currencies, setCurrencies] = useState((g.supported_currencies ?? []).join(", "));
  const [minA, setMinA] = useState(String(g.min_amount));
  const [maxA, setMaxA] = useState(g.max_amount ? String(g.max_amount) : "");
  const [fixedFee, setFixedFee] = useState(String(g.fixed_fee));
  const [pctFee, setPctFee] = useState(String(g.percentage_fee));
  const [priority, setPriority] = useState(String(g.priority));
  const [webhookUrl, setWebhookUrl] = useState(g.webhook_url ?? "");
  const [callbackUrl, setCallbackUrl] = useState(g.callback_url ?? "");
  const [reason, setReason] = useState("");

  const mut = useMutation({
    mutationFn: async () => {
      const patch = {
        name, provider,
        supported_countries: countries.split(",").map((s) => s.trim().toUpperCase()).filter(Boolean),
        supported_currencies: currencies.split(",").map((s) => s.trim().toUpperCase()).filter(Boolean),
        min_amount: Number(minA), max_amount: maxA ? Number(maxA) : undefined,
        fixed_fee: Number(fixedFee), percentage_fee: Number(pctFee),
        priority: Number(priority),
        callback_url: callbackUrl || undefined, webhook_url: webhookUrl || undefined,
      };
      const { error } = await supabase.rpc("update_payment_gateway", { _id: g.id, _patch: patch, _reason: reason || undefined });
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم الحفظ"); onChanged(); },
    onError: (e: Error) => toast.error(e.message),
  });

  const canEdit = has("payment_gateways.update");
  return (
    <div className="grid grid-cols-2 gap-3">
      <div><Label>الاسم</Label><Input value={name} onChange={(e) => setName(e.target.value)} disabled={!canEdit} /></div>
      <div><Label>المزود</Label><Input value={provider} onChange={(e) => setProvider(e.target.value)} disabled={!canEdit} /></div>
      <div><Label>الدول</Label><Input value={countries} onChange={(e) => setCountries(e.target.value)} disabled={!canEdit} /></div>
      <div><Label>العملات</Label><Input value={currencies} onChange={(e) => setCurrencies(e.target.value)} disabled={!canEdit} /></div>
      <div><Label>الحد الأدنى</Label><Input type="number" value={minA} onChange={(e) => setMinA(e.target.value)} disabled={!canEdit} /></div>
      <div><Label>الحد الأقصى</Label><Input type="number" value={maxA} onChange={(e) => setMaxA(e.target.value)} disabled={!canEdit} /></div>
      <div><Label>رسوم ثابتة</Label><Input type="number" value={fixedFee} onChange={(e) => setFixedFee(e.target.value)} disabled={!canEdit} /></div>
      <div><Label>رسوم نسبية %</Label><Input type="number" step="0.01" value={pctFee} onChange={(e) => setPctFee(e.target.value)} disabled={!canEdit} /></div>
      <div><Label>الأولوية</Label><Input type="number" value={priority} onChange={(e) => setPriority(e.target.value)} disabled={!canEdit} /></div>
      <div className="col-span-2"><Label>Callback URL</Label><Input value={callbackUrl} onChange={(e) => setCallbackUrl(e.target.value)} disabled={!canEdit} /></div>
      <div className="col-span-2"><Label>Webhook URL</Label><Input value={webhookUrl} onChange={(e) => setWebhookUrl(e.target.value)} disabled={!canEdit} /></div>
      <div className="col-span-2"><Label>سبب التعديل (اختياري)</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} /></div>
      <div className="col-span-2 flex justify-end">
        <Button disabled={!canEdit || mut.isPending} onClick={() => mut.mutate()}>{mut.isPending ? "…" : "حفظ التعديلات"}</Button>
      </div>
    </div>
  );
}

/* ------------------- SECRETS ------------------- */
function SecretsTab({ g, onChanged }: { g: Gateway; onChanged: () => void }) {
  const { has } = usePermissions();
  const [kind, setKind] = useState<"webhook" | "api_key">("webhook");
  const [ref, setRef] = useState("");
  const [reason, setReason] = useState("");

  const mut = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("mark_gateway_secret_configured", { _id: g.id, _secret_kind: kind, _ref: ref, _reason: reason });
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم تسجيل تدوير السر (القيمة الفعلية تُخزَّن Backend)"); setRef(""); setReason(""); onChanged(); },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <div className="space-y-4">
      <Card><CardContent className="pt-4 space-y-2 text-sm">
        <Row k="Webhook Secret" v={g.webhook_secret_ref ? "✓ Configured" : "✗ Missing"} />
        <Row k="API Key"        v={g.api_key_secret_ref ? "✓ Configured" : "✗ Missing"} />
      </CardContent></Card>

      {has("payment_gateways.rotate_secret") ? (
        <Card>
          <CardHeader><CardTitle className="text-sm">تدوير سر</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <p className="text-xs text-muted-foreground">
              القيمة الفعلية للسر تُحفظ في Backend Secrets ولا تُرسل أبدًا إلى المتصفح. هذا الحقل يسجّل فقط <b>مرجعًا</b> للاسم داخل Backend Secrets (مثال: <code>STC_PAY_WEBHOOK</code>).
            </p>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>نوع السر</Label>
                <Select value={kind} onValueChange={(v) => setKind(v as "webhook" | "api_key")}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="webhook">Webhook Secret</SelectItem>
                    <SelectItem value="api_key">API Key</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div><Label>مرجع السر في Backend</Label><Input value={ref} onChange={(e) => setRef(e.target.value)} placeholder="STC_PAY_WEBHOOK" /></div>
            </div>
            <Textarea placeholder="السبب (5 أحرف على الأقل)" value={reason} onChange={(e) => setReason(e.target.value)} />
            <div className="flex justify-end">
              <Button disabled={!ref.trim() || reason.trim().length < 5 || mut.isPending} onClick={() => mut.mutate()}>
                {mut.isPending ? "…" : "تسجيل التدوير"}
              </Button>
            </div>
          </CardContent>
        </Card>
      ) : (
        <div className="text-sm text-muted-foreground">تحتاج صلاحية <code>payment_gateways.rotate_secret</code>.</div>
      )}
    </div>
  );
}

/* ------------------- HEALTH ------------------- */
function HealthTab({ g, onChanged }: { g: Gateway; onChanged: () => void }) {
  const { has } = usePermissions();
  const lastHealth = (g.metadata as { last_health?: { status?: string; response_ms?: number; http_status?: number; error?: string; checked_at?: string } } | null)?.last_health;

  const record = useMutation({
    mutationFn: async (status: "healthy" | "degraded" | "down") => {
      // In production this is triggered from a server-side scheduled function that
      // actually reaches out to the provider. Here we record the observed status.
      const { error } = await supabase.rpc("record_gateway_health_check", {
        _id: g.id, _new_status: status, _response_ms: 0, _http_status: 200, _error: undefined,
      });
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم تسجيل حالة الصحة"); onChanged(); },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Stat label="الحالة الحالية" value={HEALTH[g.health_status].label} />
        <Stat label="آخر فحص" value={g.last_health_check_at ? fmtDate(g.last_health_check_at) : "لم يتم"} />
        <Stat label="زمن الاستجابة" value={lastHealth?.response_ms != null ? `${lastHealth.response_ms} ms` : "—"} />
        <Stat label="HTTP" value={lastHealth?.http_status != null ? String(lastHealth.http_status) : "—"} />
      </div>
      {lastHealth?.error && (
        <Card><CardContent className="pt-4 text-sm text-destructive">آخر خطأ: {lastHealth.error}</CardContent></Card>
      )}
      {has("payment_gateways.test") && (
        <Card>
          <CardHeader><CardTitle className="text-sm">تسجيل نتيجة فحص</CardTitle></CardHeader>
          <CardContent className="flex gap-2">
            <Button size="sm" onClick={() => record.mutate("healthy")} disabled={record.isPending}><CheckCircle2 className="ml-1 h-3.5 w-3.5" /> Healthy</Button>
            <Button size="sm" variant="outline" onClick={() => record.mutate("degraded")} disabled={record.isPending}>Degraded</Button>
            <Button size="sm" variant="destructive" onClick={() => record.mutate("down")} disabled={record.isPending}><XCircle className="ml-1 h-3.5 w-3.5" /> Down</Button>
          </CardContent>
        </Card>
      )}
      <p className="text-xs text-muted-foreground">
        الاتصال الفعلي بالمزود يتم من Backend عبر Server Function مجدولة، ولا يجري أبدًا من المتصفح لتفادي كشف الأسرار.
      </p>
    </div>
  );
}

/* ------------------- WEBHOOKS ------------------- */
function WebhooksTab({ gatewayId }: { gatewayId: string }) {
  const { has } = usePermissions();
  const qc = useQueryClient();
  const [signatureFilter, setSignatureFilter] = useState<string>("all");

  const q = useQuery({
    queryKey: ["payment_webhooks", gatewayId, signatureFilter],
    queryFn: async () => {
      let query = supabase.from("payment_webhooks").select("*").eq("gateway_id", gatewayId).order("received_at", { ascending: false }).limit(100);
      if (signatureFilter === "valid") query = query.eq("signature_valid", true);
      if (signatureFilter === "invalid") query = query.eq("signature_valid", false);
      const { data, error } = await query;
      if (error) throw error;
      return data ?? [];
    },
  });

  const retry = useMutation({
    mutationFn: async (id: string) => {
      const reason = window.prompt("سبب إعادة المحاولة (5 أحرف على الأقل):", "إعادة معالجة يدوية");
      if (!reason || reason.trim().length < 5) throw new Error("السبب مطلوب (5 أحرف على الأقل)");
      const idempotency_key = `webhook-retry-${id}-${Date.now()}-${crypto.randomUUID().slice(0,8)}`;
      const { error } = await supabase.rpc("retry_payment_webhook", {
        _webhook_id: id, _reason: reason.trim(), _idempotency_key: idempotency_key,
      });
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تمت إعادة المحاولة"); qc.invalidateQueries({ queryKey: ["payment_webhooks"] }); },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <div className="space-y-3">
      <Select value={signatureFilter} onValueChange={setSignatureFilter}>
        <SelectTrigger className="w-56"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="all">كل التوقيعات</SelectItem>
          <SelectItem value="valid">توقيع صحيح</SelectItem>
          <SelectItem value="invalid">توقيع غير صحيح</SelectItem>
        </SelectContent>
      </Select>
      {q.isLoading ? <Skeleton className="h-40" /> : !q.data?.length ? (
        <div className="text-center py-10 text-muted-foreground">لا توجد Webhooks لهذه البوابة.</div>
      ) : (
        <Table>
          <TableHeader><TableRow>
            <TableHead>External ID</TableHead><TableHead>الحدث</TableHead>
            <TableHead>التوقيع</TableHead><TableHead>الحالة</TableHead>
            <TableHead>المحاولات</TableHead><TableHead>الاستلام</TableHead>
            <TableHead>الخطأ</TableHead><TableHead />
          </TableRow></TableHeader>
          <TableBody>
            {q.data.map((w) => (
              <TableRow key={w.id}>
                <TableCell className="font-mono text-xs">{w.external_id}</TableCell>
                <TableCell>{w.event_type}</TableCell>
                <TableCell>{w.signature_valid ? <Badge className="bg-emerald-500/15 text-emerald-500">صحيح</Badge> : <Badge variant="destructive">غير صحيح</Badge>}</TableCell>
                <TableCell>{w.processed ? <Badge className="bg-emerald-500/15 text-emerald-500">تمت المعالجة</Badge> : w.processing_error ? <Badge variant="destructive">فشل</Badge> : <Badge variant="secondary">قيد الانتظار</Badge>}</TableCell>
                <TableCell>{w.retry_count ?? 0}</TableCell>
                <TableCell className="text-xs">{fmtDate(w.received_at)}</TableCell>
                <TableCell className="text-xs text-destructive max-w-[200px] truncate">{w.processing_error ?? "—"}</TableCell>
                <TableCell>
                  {has("payment_webhooks.retry") && !w.processed && (
                    <Button size="sm" variant="ghost" onClick={() => retry.mutate(w.id)} disabled={retry.isPending}>
                      <RefreshCw className="h-3.5 w-3.5" />
                    </Button>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
      <p className="text-xs text-muted-foreground">
        بيانات Payload الحساسة (Authorization، مفاتيح API، أرقام بطاقات) تُنقّى تلقائيًا قبل التخزين.
      </p>
    </div>
  );
}

/* ------------------- FAILURES ------------------- */
function FailuresTab({ gatewayId, onChanged }: { gatewayId: string; onChanged: () => void }) {
  const { has } = usePermissions();
  const qc = useQueryClient();
  const [selected, setSelected] = useState<{ id: string; note: string } | null>(null);

  const q = useQuery({
    queryKey: ["payment_failures", gatewayId],
    queryFn: async () => {
      const { data, error } = await supabase.from("payment_failures").select("*").eq("gateway_id", gatewayId).order("created_at", { ascending: false }).limit(100);
      if (error) throw error; return data ?? [];
    },
  });

  const resolve = useMutation({
    mutationFn: async ({ id, note }: { id: string; note: string }) => {
      const { error } = await supabase.rpc("resolve_payment_failure", { _id: id, _resolution_note: note });
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم حل العطل"); setSelected(null); qc.invalidateQueries({ queryKey: ["payment_failures"] }); onChanged(); },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <div className="space-y-3">
      {q.isLoading ? <Skeleton className="h-40" /> : !q.data?.length ? (
        <div className="text-center py-10 text-muted-foreground">لا توجد أعطال مسجلة.</div>
      ) : (
        <Table>
          <TableHeader><TableRow>
            <TableHead>النوع</TableHead><TableHead>Code</TableHead>
            <TableHead>الرسالة</TableHead><TableHead>الحالة</TableHead>
            <TableHead>التاريخ</TableHead><TableHead />
          </TableRow></TableHeader>
          <TableBody>
            {q.data.map((f) => {
              const details = (f.details ?? {}) as { status?: string };
              const resolved = details.status === "resolved";
              return (
                <TableRow key={f.id}>
                  <TableCell>{f.failure_type}</TableCell>
                  <TableCell className="font-mono text-xs">{f.error_code ?? "—"}</TableCell>
                  <TableCell className="max-w-[300px] truncate text-xs">{f.error_message ?? "—"}</TableCell>
                  <TableCell>{resolved ? <Badge className="bg-emerald-500/15 text-emerald-500">تم الحل</Badge> : <Badge variant="destructive">مفتوح</Badge>}</TableCell>
                  <TableCell className="text-xs">{fmtDate(f.created_at)}</TableCell>
                  <TableCell>
                    {has("payment_failures.resolve") && !resolved && (
                      <Button size="sm" variant="ghost" onClick={() => setSelected({ id: f.id, note: "" })}>حل</Button>
                    )}
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}

      {selected && (
        <Dialog open onOpenChange={() => setSelected(null)}>
          <DialogContent>
            <DialogHeader><DialogTitle>حل العطل</DialogTitle></DialogHeader>
            <Textarea placeholder="ملاحظة الحل (5 أحرف على الأقل)" value={selected.note} onChange={(e) => setSelected({ ...selected, note: e.target.value })} />
            <DialogFooter>
              <Button variant="ghost" onClick={() => setSelected(null)}>إلغاء</Button>
              <Button disabled={selected.note.trim().length < 5 || resolve.isPending} onClick={() => resolve.mutate({ id: selected.id, note: selected.note })}>تسجيل الحل</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}
