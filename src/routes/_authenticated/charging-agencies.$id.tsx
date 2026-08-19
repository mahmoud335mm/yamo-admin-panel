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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Loader2, ArrowRight, ShieldAlert, Power, PauseCircle, PlayCircle } from "lucide-react";
import { toast } from "sonner";
import { CHARGING_AGENCY_STATUS, CHARGING_TXN_STATUS, AGENT_ROLE_LABELS, fmtDate, fmtNum } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-agencies/$id")({
  component: () => <PermissionGuard permission="charging_agencies.read"><Page /></PermissionGuard>,
});

function Page() {
  const { id } = Route.useParams();
  const qc = useQueryClient();
  const { has } = usePermissions();

  const agency = useQuery({
    queryKey: ["charging_agency", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_agencies").select("*").eq("id", id).maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const members = useQuery({
    queryKey: ["charging_agency_members", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_agency_members")
        .select("id, member_role, status, assigned_at, user_id, profiles:user_id(external_uid, display_name)")
        .eq("agency_id", id).order("assigned_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  const coinTxns = useQuery({
    queryKey: ["charging_agency_coin_txns", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_coin_transfers")
        .select("id, reference, amount, status, created_at, agent_user_id, recipient_user_id")
        .eq("agency_id", id).order("created_at", { ascending: false }).limit(50);
      if (error) throw error;
      return data ?? [];
    },
  });

  const suspend = useMutation({
    mutationFn: async (reason: string) => {
      const { error } = await supabase.rpc("suspend_charging_agency", { _agency_id: id, _reason: reason } as never);
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم التعليق"); qc.invalidateQueries({ queryKey: ["charging_agency", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });

  const reactivate = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("reactivate_charging_agency", { _agency_id: id } as never);
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم التفعيل"); qc.invalidateQueries({ queryKey: ["charging_agency", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });

  const close = useMutation({
    mutationFn: async (reason: string) => {
      const { error } = await supabase.rpc("close_charging_agency", { _agency_id: id, _reason: reason } as never);
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم الإغلاق"); qc.invalidateQueries({ queryKey: ["charging_agency", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });

  if (agency.isLoading) return <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div>;
  if (!agency.data) return <div className="py-16 text-center text-muted-foreground">الوكالة غير موجودة</div>;
  const a = agency.data;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2"><Link to="/charging-agencies"><Button size="sm" variant="ghost"><ArrowRight className="h-4 w-4" /></Button></Link>
            <h1 className="text-2xl font-bold">{a.name}</h1>
            <Badge>{CHARGING_AGENCY_STATUS[a.status] ?? a.status}</Badge>
          </div>
          <p className="mt-1 font-mono text-xs text-muted-foreground">{a.display_id}</p>
        </div>
        <div className="flex gap-2">
          {a.status === "active" && has("charging_agencies.suspend") && <ReasonAction label="تعليق" icon={<PauseCircle className="ml-1 h-4 w-4" />} variant="outline" onSubmit={(r) => suspend.mutate(r)} />}
          {a.status === "suspended" && has("charging_agencies.suspend") && <Button variant="outline" onClick={() => reactivate.mutate()}><PlayCircle className="ml-1 h-4 w-4" /> إعادة تفعيل</Button>}
          {a.status !== "closed" && has("charging_agencies.close") && <ReasonAction label="إغلاق" icon={<Power className="ml-1 h-4 w-4" />} variant="destructive" onSubmit={(r) => close.mutate(r)} />}
        </div>
      </div>

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">نظرة عامة</TabsTrigger>
          <TabsTrigger value="agents">الوكلاء</TabsTrigger>
          <TabsTrigger value="transfers">تحويلات الكوينز</TabsTrigger>
        </TabsList>
        <TabsContent value="overview" className="space-y-4">
          <Card><CardHeader><CardTitle className="text-sm">التفاصيل</CardTitle></CardHeader><CardContent className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3">
            <KV k="الدولة" v={a.country ?? "-"} /> <KV k="المدينة" v={a.city ?? "-"} /> <KV k="العملة" v={a.default_currency ?? "-"} />
            <KV k="الهاتف" v={a.phone ?? "-"} /> <KV k="البريد" v={a.email ?? "-"} /> <KV k="المستوى" v={String(a.level_id ?? "-")} />
            <KV k="الحد اليومي كوينز" v={fmtNum(a.daily_coin_transfer_limit)} /><KV k="الحد الشهري كوينز" v={fmtNum(a.monthly_coin_transfer_limit)} />
            <KV k="تاريخ الإنشاء" v={fmtDate(a.created_at)} />
          </CardContent></Card>
        </TabsContent>
        <TabsContent value="agents">
          <Card><CardContent className="pt-4">
            {members.isLoading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> :
              members.data!.length === 0 ? <div className="py-8 text-center text-sm text-muted-foreground">لا يوجد وكلاء</div> :
              <Table><TableHeader><TableRow><TableHead>الوكيل</TableHead><TableHead>الدور</TableHead><TableHead>الحالة</TableHead><TableHead>تاريخ التعيين</TableHead></TableRow></TableHeader><TableBody>
                {members.data!.map((m) => {
                  const p = m.profiles as { external_uid?: string; display_name?: string } | null;
                  return (<TableRow key={m.id}>
                    <TableCell><Link to="/charging-agents/$id" params={{ id: m.user_id }} className="text-primary hover:underline">{p?.display_name ?? "-"}</Link><div className="font-mono text-xs text-muted-foreground">{p?.external_uid ?? m.user_id.slice(0,8)}</div></TableCell>
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
            {coinTxns.isLoading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> :
              coinTxns.data!.length === 0 ? <div className="py-8 text-center text-sm text-muted-foreground">لا توجد تحويلات</div> :
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

function KV({ k, v }: { k: string; v: string }) {
  return (<div><div className="text-xs text-muted-foreground">{k}</div><div className="font-medium">{v}</div></div>);
}

function ReasonAction({ label, icon, variant, onSubmit }: { label: string; icon?: React.ReactNode; variant: "outline" | "destructive"; onSubmit: (r: string) => void }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  return (
    <>
      <Button variant={variant} onClick={() => setOpen(true)}>{icon}{label}</Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent dir="rtl">
          <DialogHeader><DialogTitle>{label} — السبب</DialogTitle></DialogHeader>
          <div><Label>السبب (5 أحرف على الأقل)</Label><Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} /></div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
            <Button variant={variant} disabled={reason.length < 5} onClick={() => { onSubmit(reason); setOpen(false); setReason(""); }}>{label}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
