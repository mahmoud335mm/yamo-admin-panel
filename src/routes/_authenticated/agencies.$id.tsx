import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ArrowRight, Loader2, Ban, Play, XCircle, Trophy } from "lucide-react";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/agencies/$id")({
  component: () => <PermissionGuard permission="agencies.read"><AgencyDetail /></PermissionGuard>,
});

function AgencyDetail() {
  const { id } = Route.useParams();
  const qc = useQueryClient();
  const { has } = usePermissions();

  const a = useQuery({
    queryKey: ["agency", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("agencies").select("*").eq("id", id).maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const hosts = useQuery({
    queryKey: ["agency", id, "hosts"],
    queryFn: async () => (await supabase.from("hosts").select("id, user_id, status, level_id, monthly_coins, monthly_hours, joined_at").eq("agency_id", id).order("joined_at", { ascending: false })).data ?? [],
  });

  const violations = useQuery({
    queryKey: ["agency", id, "violations"],
    queryFn: async () => (await supabase.from("agency_violations").select("*").eq("agency_id", id).order("created_at", { ascending: false })).data ?? [],
  });

  const history = useQuery({
    queryKey: ["agency", id, "history"],
    queryFn: async () => (await supabase.from("agency_level_history").select("*").eq("agency_id", id).order("created_at", { ascending: false })).data ?? [],
  });

  const suspend = useMutation({
    mutationFn: async (reason: string) => {
      const { error } = await supabase.rpc("suspend_agency", { _agency_id: id, _reason: reason });
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم إيقاف الوكالة"); qc.invalidateQueries({ queryKey: ["agency", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });
  const reactivate = useMutation({
    mutationFn: async () => { const { error } = await supabase.rpc("reactivate_agency", { _agency_id: id, _reason: "manual" }); if (error) throw error; },
    onSuccess: () => { toast.success("تم إعادة تفعيل الوكالة"); qc.invalidateQueries({ queryKey: ["agency", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });
  const close = useMutation({
    mutationFn: async (reason: string) => { const { error } = await supabase.rpc("close_agency", { _agency_id: id, _reason: reason }); if (error) throw error; },
    onSuccess: () => { toast.success("تم إغلاق الوكالة"); qc.invalidateQueries({ queryKey: ["agency", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });
  const updateLevel = useMutation({
    mutationFn: async (v: { level: number; reason: string }) => {
      const { error } = await supabase.rpc("update_agency_level", { _agency_id: id, _new_level: v.level, _reason: v.reason });
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم تحديث المستوى"); qc.invalidateQueries({ queryKey: ["agency", id] }); },
    onError: (e: Error) => toast.error(e.message),
  });

  if (a.isLoading) return <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div>;
  if (!a.data) return <div className="py-16 text-center text-sm text-muted-foreground">لم يتم العثور على الوكالة.</div>;
  const ag = a.data;

  return (
    <div className="space-y-6">
      <Button variant="ghost" size="sm" asChild><Link to="/agencies"><ArrowRight className="ml-1 h-4 w-4" />رجوع</Link></Button>

      <Card>
        <CardHeader>
          <CardTitle className="text-xl">{ag.name} <span className="text-sm text-muted-foreground">({ag.code})</span></CardTitle>
          <CardDescription className="mt-1 flex flex-wrap gap-2">
            <Badge>{ag.country ?? "—"}</Badge>
            <Badge variant="secondary">Lv {ag.level_id}</Badge>
            <Badge variant={ag.status === "active" ? "default" : "destructive"}>{ag.status}</Badge>
            <Badge variant="secondary">مضيفون: {ag.active_hosts}/{ag.total_hosts}</Badge>
            <Badge variant="outline">عملات الشهر: {ag.monthly_coins.toLocaleString("en-US")}</Badge>
          </CardDescription>
          <div className="mt-3 flex flex-wrap gap-2">
            {has("agencies.suspend") && ag.status === "active" && (
              <ReasonDialog trigger={<Button size="sm" variant="destructive"><Ban className="ml-1 h-3.5 w-3.5" />إيقاف</Button>} title="إيقاف الوكالة" onConfirm={(r) => suspend.mutate(r)} />
            )}
            {has("agencies.suspend") && ag.status === "suspended" && (
              <Button size="sm" onClick={() => reactivate.mutate()}><Play className="ml-1 h-3.5 w-3.5" />إعادة تفعيل</Button>
            )}
            {has("agencies.close") && ag.status !== "closed" && (
              <ReasonDialog trigger={<Button size="sm" variant="outline"><XCircle className="ml-1 h-3.5 w-3.5" />إغلاق</Button>} title="إغلاق الوكالة (لا يجب وجود مضيفين نشطين)" onConfirm={(r) => close.mutate(r)} />
            )}
            {has("agencies.level") && (
              <LevelDialog current={ag.level_id ?? 1} onConfirm={(level, reason) => updateLevel.mutate({ level, reason })} />
            )}
          </div>
        </CardHeader>
      </Card>

      <Tabs defaultValue="hosts">
        <TabsList>
          <TabsTrigger value="hosts">المضيفون ({hosts.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="violations">المخالفات ({violations.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="history">سجل المستويات ({history.data?.length ?? 0})</TabsTrigger>
        </TabsList>

        <TabsContent value="hosts">
          <Card><CardContent className="pt-6">
            {hosts.isLoading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : (hosts.data?.length ?? 0) === 0 ? (
              <div className="py-8 text-center text-sm text-muted-foreground">لا مضيفون.</div>
            ) : (
              <Table>
                <TableHeader><TableRow><TableHead>User ID</TableHead><TableHead>الحالة</TableHead><TableHead>المستوى</TableHead><TableHead>ساعات الشهر</TableHead><TableHead>عملات الشهر</TableHead><TableHead>الانضمام</TableHead></TableRow></TableHeader>
                <TableBody>{hosts.data!.map((h) => (
                  <TableRow key={h.id}>
                    <TableCell className="font-mono text-xs">{h.user_id.slice(0, 8)}…</TableCell>
                    <TableCell><Badge variant={h.status === "active" ? "default" : "secondary"}>{h.status}</Badge></TableCell>
                    <TableCell>H{h.level_id}</TableCell>
                    <TableCell className="font-mono">{h.monthly_hours}</TableCell>
                    <TableCell className="font-mono">{h.monthly_coins.toLocaleString("en-US")}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">{new Date(h.joined_at).toLocaleDateString("ar-EG-u-nu-latn")}</TableCell>
                  </TableRow>
                ))}</TableBody>
              </Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="violations">
          <Card><CardContent className="pt-6">
            {(violations.data?.length ?? 0) === 0 ? <div className="py-8 text-center text-sm text-muted-foreground">لا مخالفات.</div> :
              <Table><TableHeader><TableRow><TableHead>النوع</TableHead><TableHead>الشدة</TableHead><TableHead>السبب</TableHead><TableHead>التاريخ</TableHead></TableRow></TableHeader>
                <TableBody>{violations.data!.map((v) => (
                  <TableRow key={v.id}><TableCell>{v.type}</TableCell><TableCell><Badge variant="destructive">{v.severity}</Badge></TableCell><TableCell>{v.reason}</TableCell><TableCell className="text-xs">{new Date(v.created_at).toLocaleString("ar-EG-u-nu-latn")}</TableCell></TableRow>
                ))}</TableBody></Table>}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="history">
          <Card><CardContent className="pt-6">
            {(history.data?.length ?? 0) === 0 ? <div className="py-8 text-center text-sm text-muted-foreground">لا تغييرات.</div> :
              <Table><TableHeader><TableRow><TableHead>من</TableHead><TableHead>إلى</TableHead><TableHead>السبب</TableHead><TableHead>التاريخ</TableHead></TableRow></TableHeader>
                <TableBody>{history.data!.map((h) => (
                  <TableRow key={h.id}><TableCell>Lv {h.old_level ?? "—"}</TableCell><TableCell><Badge>Lv {h.new_level}</Badge></TableCell><TableCell>{h.reason ?? "—"}</TableCell><TableCell className="text-xs">{new Date(h.created_at).toLocaleString("ar-EG-u-nu-latn")}</TableCell></TableRow>
                ))}</TableBody></Table>}
          </CardContent></Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}

function ReasonDialog({ trigger, title, onConfirm }: { trigger: React.ReactNode; title: string; onConfirm: (reason: string) => void }) {
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

function LevelDialog({ current, onConfirm }: { current: number; onConfirm: (level: number, reason: string) => void }) {
  const [open, setOpen] = useState(false);
  const [level, setLevel] = useState(String(current));
  const [reason, setReason] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild><Button size="sm" variant="outline"><Trophy className="ml-1 h-3.5 w-3.5" />تعديل المستوى</Button></DialogTrigger>
      <DialogContent dir="rtl">
        <DialogHeader><DialogTitle>تعديل مستوى الوكالة</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1"><Label>المستوى الجديد</Label>
            <Select value={level} onValueChange={setLevel}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{[1,2,3,4,5].map((n) => <SelectItem key={n} value={String(n)}>Lv {n}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="space-y-1"><Label>السبب</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
          <Button disabled={reason.length < 3} onClick={() => { onConfirm(Number(level), reason); setOpen(false); }}>حفظ</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
