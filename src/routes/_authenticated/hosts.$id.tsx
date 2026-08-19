import { createFileRoute, Link } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ArrowRight, Loader2, Ban, Play, UserMinus, Mic } from "lucide-react";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/hosts/$id")({
  component: () => <PermissionGuard permission="hosts.read"><HostDetail /></PermissionGuard>,
});

function HostDetail() {
  const { id } = Route.useParams();
  const qc = useQueryClient();
  const { has } = usePermissions();

  const h = useQuery({
    queryKey: ["host", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("hosts").select("*").eq("id", id).maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const agency = useQuery({
    queryKey: ["host", id, "agency"],
    enabled: !!h.data?.agency_id,
    queryFn: async () => (await supabase.from("agencies").select("id, code, name, status, bd_id").eq("id", h.data!.agency_id!).maybeSingle()).data,
  });

  const profile = useQuery({
    queryKey: ["host", id, "profile"],
    enabled: !!h.data?.user_id,
    queryFn: async () => (await supabase.from("profiles").select("id, display_name, username, avatar_url, country, status, verification, level, vip_level").eq("id", h.data!.user_id).maybeSingle()).data,
  });

  const earnings = useQuery({
    queryKey: ["host", id, "earnings"],
    queryFn: async () => (await supabase.from("host_earnings").select("*").eq("host_id", id).order("period_year", { ascending: false }).order("period_month", { ascending: false }).limit(12)).data ?? [],
  });

  const targets = useQuery({
    queryKey: ["host", id, "targets"],
    queryFn: async () => (await supabase.from("host_targets").select("*").eq("host_id", id).order("period_year", { ascending: false }).order("period_month", { ascending: false }).limit(6)).data ?? [],
  });

  const shifts = useQuery({
    queryKey: ["host", id, "shifts"],
    queryFn: async () => (await supabase.from("host_shifts").select("*").eq("host_id", id).order("started_at", { ascending: false }).limit(20)).data ?? [],
  });

  const transfers = useQuery({
    queryKey: ["host", id, "transfers"],
    enabled: !!h.data?.user_id,
    queryFn: async () => (await supabase.from("agency_host_transfer_requests").select("*").eq("host_user_id", h.data!.user_id).order("created_at", { ascending: false })).data ?? [],
  });

  const auditLogs = useQuery({
    queryKey: ["host", id, "audit"],
    queryFn: async () => (await supabase.from("audit_logs").select("id, actor_email, action, metadata, created_at").eq("entity_type", "hosts").eq("entity_id", id).order("created_at", { ascending: false }).limit(50)).data ?? [],
  });

  const suspend = useMutation({
    mutationFn: async (reason: string) => { const { error } = await supabase.rpc("suspend_host", { _host_id: id, _reason: reason } as never); if (error) throw error; },
    onSuccess: () => { toast.success("تم تعليق المضيف"); qc.invalidateQueries({ queryKey: ["host", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });
  const reactivate = useMutation({
    mutationFn: async () => { const { error } = await supabase.rpc("reactivate_host", { _host_id: id, _reason: "manual" } as never); if (error) throw error; },
    onSuccess: () => { toast.success("تم إعادة التفعيل"); qc.invalidateQueries({ queryKey: ["host", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });
  const remove = useMutation({
    mutationFn: async (reason: string) => { const { error } = await supabase.rpc("remove_host_from_agency", { _host_id: id, _reason: reason } as never); if (error) throw error; },
    onSuccess: () => { toast.success("تمت الإزالة"); qc.invalidateQueries({ queryKey: ["host", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });

  if (h.isLoading) return <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div>;
  if (!h.data) return <div className="py-16 text-center text-sm text-muted-foreground">المضيف غير موجود.</div>;
  const host = h.data;

  return (
    <div className="space-y-6">
      <Button variant="ghost" size="sm" asChild><Link to="/hosts"><ArrowRight className="ml-1 h-4 w-4" />رجوع</Link></Button>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-xl">
            <Mic className="h-5 w-5 text-primary" />
            {profile.data?.display_name ?? host.user_id.slice(0, 12) + "…"}
            {profile.data?.username && <span className="text-sm text-muted-foreground">@{profile.data.username}</span>}
          </CardTitle>
          <div className="mt-2 flex flex-wrap gap-2">
            <Badge variant={host.status === "active" ? "default" : "secondary"}>{host.status}</Badge>
            <Badge variant="secondary">H{host.level_id ?? "—"}</Badge>
            {profile.data?.verification === "verified" && <Badge>موثّق</Badge>}
            {agency.data && (
              <Link to="/agencies/$id" params={{ id: agency.data.id }}>
                <Badge variant="outline" className="cursor-pointer hover:bg-accent">{agency.data.code} — {agency.data.name}</Badge>
              </Link>
            )}
            {host.cooldown_until && new Date(host.cooldown_until) > new Date() && (
              <Badge variant="destructive">فترة تبريد حتى {new Date(host.cooldown_until).toLocaleDateString("ar")}</Badge>
            )}
          </div>
          <div className="mt-4 grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
            <Stat label="ساعات الشهر" value={String(host.monthly_hours)} />
            <Stat label="عملات الشهر" value={host.monthly_coins.toLocaleString()} />
            <Stat label="أرباح معلّقة" value={host.pending_earnings.toLocaleString()} />
            <Stat label="الدين" value={host.debt.toLocaleString()} highlight={host.debt > 0} />
            <Stat label="إجمالي الساعات" value={String(host.total_hours)} />
            <Stat label="إجمالي العملات" value={host.total_coins.toLocaleString()} />
            <Stat label="الانضمام" value={new Date(host.joined_at).toLocaleDateString("ar")} />
            <Stat label="المستوى" value={profile.data ? `Lv ${profile.data.level} / VIP ${profile.data.vip_level}` : "—"} />
          </div>
          <div className="mt-4 flex flex-wrap gap-2">
            {has("hosts.suspend") && host.status === "active" && (
              <ReasonDialog title="تعليق المضيف" trigger={<Button size="sm" variant="destructive"><Ban className="ml-1 h-3.5 w-3.5" />تعليق</Button>} onConfirm={(r) => suspend.mutate(r)} />
            )}
            {has("hosts.suspend") && host.status === "suspended" && (
              <Button size="sm" onClick={() => reactivate.mutate()}><Play className="ml-1 h-3.5 w-3.5" />إعادة تفعيل</Button>
            )}
            {has("hosts.remove") && host.agency_id && (
              <ReasonDialog title="إزالة من الوكالة (سبب إلزامي)" trigger={<Button size="sm" variant="outline"><UserMinus className="ml-1 h-3.5 w-3.5" />إزالة من الوكالة</Button>} onConfirm={(r) => remove.mutate(r)} />
            )}
          </div>
        </CardHeader>
      </Card>

      <Tabs defaultValue="earnings">
        <TabsList>
          <TabsTrigger value="earnings">الأرباح</TabsTrigger>
          <TabsTrigger value="targets">الأهداف</TabsTrigger>
          <TabsTrigger value="shifts">الجلسات</TabsTrigger>
          <TabsTrigger value="transfers">النقل ({transfers.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="audit">سجل العمليات</TabsTrigger>
        </TabsList>

        <TabsContent value="earnings">
          <Card><CardContent className="pt-6">
            {(earnings.data?.length ?? 0) === 0 ? <Empty text="لا أرباح مسجّلة." /> : (
              <Table><TableHeader><TableRow><TableHead>الفترة</TableHead><TableHead>إجمالي</TableHead><TableHead>حصة الوكالة</TableHead><TableHead>حصة BD</TableHead><TableHead>حصة المنصة</TableHead><TableHead>الصافي</TableHead><TableHead>الحالة</TableHead></TableRow></TableHeader>
                <TableBody>{earnings.data!.map((e) => (
                  <TableRow key={e.id}>
                    <TableCell>{e.period_year}/{String(e.period_month).padStart(2, "0")}</TableCell>
                    <TableCell className="font-mono">{e.gross_coins.toLocaleString()}</TableCell>
                    <TableCell className="font-mono">{e.agency_cut.toLocaleString()}</TableCell>
                    <TableCell className="font-mono">{e.bd_cut.toLocaleString()}</TableCell>
                    <TableCell className="font-mono">{e.platform_cut.toLocaleString()}</TableCell>
                    <TableCell className="font-mono font-bold">{e.net_coins.toLocaleString()}</TableCell>
                    <TableCell><Badge variant={e.status === "paid" ? "default" : "secondary"}>{e.status}</Badge></TableCell>
                  </TableRow>
                ))}</TableBody></Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="targets">
          <Card><CardContent className="pt-6">
            {(targets.data?.length ?? 0) === 0 ? <Empty text="لا أهداف محددة." /> : (
              <Table><TableHeader><TableRow><TableHead>الفترة</TableHead><TableHead>ساعات مستهدفة</TableHead><TableHead>محقّق</TableHead><TableHead>عملات مستهدفة</TableHead><TableHead>محقّق</TableHead><TableHead>الحالة</TableHead></TableRow></TableHeader>
                <TableBody>{targets.data!.map((t) => (
                  <TableRow key={t.id}>
                    <TableCell>{t.period_year}/{String(t.period_month).padStart(2, "0")}</TableCell>
                    <TableCell className="font-mono">{t.target_hours}</TableCell>
                    <TableCell className="font-mono">{t.achieved_hours} ({Math.round((Number(t.achieved_hours) / Math.max(Number(t.target_hours), 1)) * 100)}%)</TableCell>
                    <TableCell className="font-mono">{t.target_coins.toLocaleString()}</TableCell>
                    <TableCell className="font-mono">{t.achieved_coins.toLocaleString()} ({Math.round((Number(t.achieved_coins) / Math.max(Number(t.target_coins), 1)) * 100)}%)</TableCell>
                    <TableCell><Badge>{t.status}</Badge></TableCell>
                  </TableRow>
                ))}</TableBody></Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="shifts">
          <Card><CardContent className="pt-6">
            {(shifts.data?.length ?? 0) === 0 ? <Empty text="لا جلسات بث." /> : (
              <Table><TableHeader><TableRow><TableHead>البداية</TableHead><TableHead>النهاية</TableHead><TableHead>الدقائق</TableHead><TableHead>الغرفة</TableHead></TableRow></TableHeader>
                <TableBody>{shifts.data!.map((s) => (
                  <TableRow key={s.id}>
                    <TableCell className="text-xs">{new Date(s.started_at).toLocaleString("ar")}</TableCell>
                    <TableCell className="text-xs">{s.ended_at ? new Date(s.ended_at).toLocaleString("ar") : <Badge>جارٍ</Badge>}</TableCell>
                    <TableCell className="font-mono">{s.duration_min ?? "—"}</TableCell>
                    <TableCell className="font-mono text-xs">{s.room_id?.slice(0, 8) ?? "—"}</TableCell>
                  </TableRow>
                ))}</TableBody></Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="transfers">
          <Card><CardContent className="pt-6">
            {(transfers.data?.length ?? 0) === 0 ? <Empty text="لا طلبات نقل." /> : (
              <Table><TableHeader><TableRow><TableHead>من</TableHead><TableHead>إلى</TableHead><TableHead>الحالة</TableHead><TableHead>السبب</TableHead><TableHead>التاريخ</TableHead></TableRow></TableHeader>
                <TableBody>{transfers.data!.map((t) => (
                  <TableRow key={t.id}>
                    <TableCell className="font-mono text-xs">{t.from_agency_id?.slice(0, 8) ?? "—"}</TableCell>
                    <TableCell className="font-mono text-xs">{t.to_agency_id.slice(0, 8)}…</TableCell>
                    <TableCell><Badge>{t.status}</Badge></TableCell>
                    <TableCell className="max-w-xs truncate">{t.reason}</TableCell>
                    <TableCell className="text-xs">{new Date(t.created_at).toLocaleDateString("ar")}</TableCell>
                  </TableRow>
                ))}</TableBody></Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="audit">
          <Card><CardContent className="pt-6">
            {(auditLogs.data?.length ?? 0) === 0 ? <Empty text="لا سجلات." /> : (
              <Table><TableHeader><TableRow><TableHead>الوقت</TableHead><TableHead>المسؤول</TableHead><TableHead>العملية</TableHead></TableRow></TableHeader>
                <TableBody>{auditLogs.data!.map((a) => (
                  <TableRow key={a.id}>
                    <TableCell className="text-xs">{new Date(a.created_at).toLocaleString("ar")}</TableCell>
                    <TableCell className="text-xs">{a.actor_email ?? "—"}</TableCell>
                    <TableCell className="font-mono text-xs">{a.action}</TableCell>
                  </TableRow>
                ))}</TableBody></Table>
            )}
          </CardContent></Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}

function Stat({ label, value, highlight }: { label: string; value: string; highlight?: boolean }) {
  return (
    <div className="rounded-lg border bg-muted/30 p-3">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className={`mt-1 font-mono text-sm font-semibold ${highlight ? "text-destructive" : ""}`}>{value}</div>
    </div>
  );
}
function Empty({ text }: { text: string }) { return <div className="py-10 text-center text-sm text-muted-foreground">{text}</div>; }

function ReasonDialog({ trigger, title, onConfirm }: { trigger: React.ReactNode; title: string; onConfirm: (r: string) => void }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent dir="rtl">
        <DialogHeader><DialogTitle>{title}</DialogTitle></DialogHeader>
        <div className="space-y-2"><Label>السبب (5 أحرف على الأقل)</Label><Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} /></div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
          <Button disabled={reason.length < 5} onClick={() => { onConfirm(reason); setOpen(false); setReason(""); }}>تأكيد</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
