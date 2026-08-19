import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Loader2, ArrowRight, PauseCircle, PlayCircle } from "lucide-react";
import { toast } from "sonner";
import { CHARGING_TXN_STATUS, AGENT_ROLE_LABELS, fmtDate, fmtNum } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-agents/$id")({
  component: () => <PermissionGuard permission="charging_agents.read"><Page /></PermissionGuard>,
});

function Page() {
  const { id } = Route.useParams();
  const qc = useQueryClient();
  const { has } = usePermissions();

  const profile = useQuery({
    queryKey: ["profile_short", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("profiles").select("id, external_uid, display_name, country, status").eq("id", id).maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const memberships = useQuery({
    queryKey: ["agent_memberships", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_agency_members")
        .select("id, member_role, status, assigned_at, agency_id, charging_agencies:agency_id(name, display_id)")
        .eq("user_id", id).order("assigned_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  const settings = useQuery({
    queryKey: ["agent_settings", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_agent_settings").select("*").eq("user_id", id).maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const wallet = useQuery({
    queryKey: ["wallet_short", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("wallets").select("account, balance").eq("user_id", id);
      if (error) throw error;
      return data ?? [];
    },
  });

  const coinTxns = useQuery({
    queryKey: ["agent_coin_txns", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_coin_transfers")
        .select("id, reference, amount, status, created_at, recipient_user_id")
        .eq("agent_user_id", id).order("created_at", { ascending: false }).limit(50);
      if (error) throw error;
      return data ?? [];
    },
  });

  const suspend = useMutation({
    mutationFn: async (reason: string) => {
      const { error } = await supabase.rpc("suspend_charging_agent", { _user_id: id, _reason: reason } as never);
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم التعليق"); qc.invalidateQueries(); },
    onError: (e: Error) => toast.error(e.message),
  });
  const reactivate = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("reactivate_charging_agent", { _user_id: id } as never);
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم التفعيل"); qc.invalidateQueries(); },
    onError: (e: Error) => toast.error(e.message),
  });

  if (profile.isLoading) return <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div>;
  if (!profile.data) return <div className="py-16 text-center text-muted-foreground">المستخدم غير موجود</div>;
  const p = profile.data;
  const active = memberships.data?.find((m) => m.status === "active");
  const coinBalance = wallet.data?.find((w) => w.account === "coins")?.balance ?? 0;
  const pearlBalance = wallet.data?.find((w) => w.account === "diamonds")?.balance ?? 0;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2"><Link to="/charging-agents"><Button size="sm" variant="ghost"><ArrowRight className="h-4 w-4" /></Button></Link>
            <h1 className="text-2xl font-bold">{p.display_name}</h1>
            {active && <Badge>{AGENT_ROLE_LABELS[active.member_role] ?? active.member_role}</Badge>}
          </div>
          <p className="font-mono text-xs text-muted-foreground">{p.external_uid ?? id.slice(0, 8)}</p>
        </div>
        <div className="flex gap-2">
          {active?.status === "active" && has("charging_agents.suspend") && <ReasonBtn label="تعليق الوكيل" onSubmit={(r) => suspend.mutate(r)} icon={<PauseCircle className="ml-1 h-4 w-4" />} />}
          {active && active.status !== "active" && has("charging_agents.suspend") && <Button variant="outline" onClick={() => reactivate.mutate()}><PlayCircle className="ml-1 h-4 w-4" /> إعادة تفعيل</Button>}
          <Link to="/users/$id" params={{ id }}><Button variant="ghost">الملف الكامل</Button></Link>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Stat title="رصيد الكوينز" value={fmtNum(coinBalance)} />
        <Stat title="رصيد اللؤلؤ" value={fmtNum(pearlBalance)} />
        <Stat title="الوكالة" value={(active?.charging_agencies as { name?: string } | null)?.name ?? "-"} />
      </div>

      <Tabs defaultValue="settings">
        <TabsList>
          <TabsTrigger value="settings">الإعدادات والحدود</TabsTrigger>
          <TabsTrigger value="memberships">العضويات</TabsTrigger>
          <TabsTrigger value="transfers">تحويلات الكوينز</TabsTrigger>
        </TabsList>
        <TabsContent value="settings">
          <Card><CardContent className="grid grid-cols-2 gap-3 pt-4 text-sm sm:grid-cols-3">
            <KV k="حد يومي كوينز" v={fmtNum(settings.data?.daily_coin_limit)} />
            <KV k="حد شهري كوينز" v={fmtNum(settings.data?.monthly_coin_limit)} />
            <KV k="حد يومي لؤلؤ" v={fmtNum(settings.data?.daily_pearl_limit)} />
            <KV k="حد شهري لؤلؤ" v={fmtNum(settings.data?.monthly_pearl_limit)} />
            <KV k="حد أدنى تحويل كوينز" v={fmtNum(settings.data?.min_coin_transfer)} />
            <KV k="حد أقصى تحويل كوينز" v={fmtNum(settings.data?.max_coin_transfer)} />
            <KV k="بيع الكوينز" v={settings.data?.can_sell_coins ? "نعم" : "لا"} />
            <KV k="شراء اللؤلؤ" v={settings.data?.can_buy_pearls ? "نعم" : "لا"} />
            <KV k="تبديل لؤلؤ→كوينز" v={settings.data?.can_exchange_pearls_to_coins ? "نعم" : "لا"} />
          </CardContent></Card>
        </TabsContent>
        <TabsContent value="memberships">
          <Card><CardContent className="pt-4">
            {(memberships.data ?? []).length === 0 ? <div className="py-6 text-center text-sm text-muted-foreground">لا عضويات</div> :
              <Table><TableHeader><TableRow><TableHead>الوكالة</TableHead><TableHead>الدور</TableHead><TableHead>الحالة</TableHead><TableHead>التاريخ</TableHead></TableRow></TableHeader><TableBody>
                {memberships.data!.map((m) => {
                  const ag = m.charging_agencies as { name?: string; display_id?: string } | null;
                  return (<TableRow key={m.id}>
                    <TableCell><Link to="/charging-agencies/$id" params={{ id: m.agency_id }} className="text-primary hover:underline">{ag?.name}</Link></TableCell>
                    <TableCell>{AGENT_ROLE_LABELS[m.member_role] ?? m.member_role}</TableCell>
                    <TableCell><Badge variant="secondary">{m.status}</Badge></TableCell>
                    <TableCell className="text-xs">{fmtDate(m.assigned_at)}</TableCell>
                  </TableRow>);
                })}
              </TableBody></Table>}
          </CardContent></Card>
        </TabsContent>
        <TabsContent value="transfers">
          <Card><CardContent className="pt-4">
            {(coinTxns.data ?? []).length === 0 ? <div className="py-6 text-center text-sm text-muted-foreground">لا تحويلات</div> :
              <Table><TableHeader><TableRow><TableHead>المرجع</TableHead><TableHead>المبلغ</TableHead><TableHead>الحالة</TableHead><TableHead>التاريخ</TableHead></TableRow></TableHeader><TableBody>
                {coinTxns.data!.map((t) => (<TableRow key={t.id}>
                  <TableCell className="font-mono text-xs">{t.reference}</TableCell>
                  <TableCell>{fmtNum(t.amount)}</TableCell>
                  <TableCell><Badge variant="secondary">{CHARGING_TXN_STATUS[t.status] ?? t.status}</Badge></TableCell>
                  <TableCell className="text-xs">{fmtDate(t.created_at)}</TableCell>
                </TableRow>))}
              </TableBody></Table>}
          </CardContent></Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}

function KV({ k, v }: { k: string; v: string }) { return (<div><div className="text-xs text-muted-foreground">{k}</div><div className="font-medium">{v}</div></div>); }
function Stat({ title, value }: { title: string; value: string }) { return (<Card><CardHeader><CardTitle className="text-xs text-muted-foreground">{title}</CardTitle></CardHeader><CardContent><div className="text-2xl font-bold">{value}</div></CardContent></Card>); }

function ReasonBtn({ label, onSubmit, icon }: { label: string; onSubmit: (r: string) => void; icon?: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  return (
    <>
      <Button variant="outline" onClick={() => setOpen(true)}>{icon}{label}</Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent dir="rtl">
          <DialogHeader><DialogTitle>{label}</DialogTitle></DialogHeader>
          <div><Label>السبب (5 أحرف على الأقل)</Label><Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} /></div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
            <Button disabled={reason.length < 5} onClick={() => { onSubmit(reason); setOpen(false); setReason(""); }}>تأكيد</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
