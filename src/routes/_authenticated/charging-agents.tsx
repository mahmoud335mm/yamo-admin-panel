import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Loader2, Plus, Search, UserCog } from "lucide-react";
import { toast } from "sonner";
import { AGENT_ROLE_LABELS, fmtDate } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-agents")({
  component: () => <PermissionGuard permission="charging_agents.read"><Page /></PermissionGuard>,
});

function Page() {
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("all");
  const [page, setPage] = useState(0);
  const size = 25;
  const { has } = usePermissions();

  const list = useQuery({
    queryKey: ["charging_agents", q, status, page],
    queryFn: async () => {
      let query = supabase.from("charging_agency_members")
        .select("id, member_role, status, assigned_at, user_id, agency_id, charging_agencies:agency_id(name, display_id), profiles:user_id(external_uid, display_name)", { count: "exact" })
        .order("assigned_at", { ascending: false })
        .range(page * size, page * size + size - 1);
      if (status !== "all") query = query.eq("status", status as never);
      const { data, count, error } = await query;
      if (error) throw error;
      let rows = data ?? [];
      if (q.trim()) {
        const t = q.trim().toLowerCase();
        rows = rows.filter((r) => {
          const p = r.profiles as { external_uid?: string; display_name?: string } | null;
          return p?.external_uid?.toLowerCase().includes(t) || p?.display_name?.toLowerCase().includes(t);
        });
      }
      return { rows, total: count ?? 0 };
    },
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div><h1 className="text-2xl font-bold">وكلاء الشحن</h1><p className="text-sm text-muted-foreground">تفعيل مستخدم كوكيل شحن وربطه بوكالة.</p></div>
        {has("charging_agents.activate") && <ActivateDialog onDone={() => list.refetch()} />}
      </div>
      <Card>
        <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <div className="relative flex-1"><Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input placeholder="بحث بالاسم أو UID…" value={q} onChange={(e) => setQ(e.target.value)} className="pr-9" /></div>
          <Select value={status} onValueChange={(v) => { setStatus(v); setPage(0); }}>
            <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
            <SelectContent><SelectItem value="all">الكل</SelectItem><SelectItem value="active">نشط</SelectItem><SelectItem value="suspended">موقوف</SelectItem><SelectItem value="terminated">منتهي</SelectItem></SelectContent>
          </Select>
        </CardHeader>
        <CardContent>
          {list.isLoading ? <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div> :
            list.data!.rows.length === 0 ? <div className="flex flex-col items-center gap-2 py-16 text-center"><UserCog className="h-10 w-10 text-muted-foreground" /><p className="text-sm text-muted-foreground">لا يوجد وكلاء</p></div> :
            <Table><TableHeader><TableRow><TableHead>الوكيل</TableHead><TableHead>الوكالة</TableHead><TableHead>الدور</TableHead><TableHead>الحالة</TableHead><TableHead>التاريخ</TableHead><TableHead></TableHead></TableRow></TableHeader><TableBody>
              {list.data!.rows.map((r) => {
                const p = r.profiles as { external_uid?: string; display_name?: string } | null;
                const ag = r.charging_agencies as { name?: string; display_id?: string } | null;
                return (<TableRow key={r.id}>
                  <TableCell><div className="font-medium">{p?.display_name ?? "-"}</div><div className="font-mono text-xs text-muted-foreground">{p?.external_uid ?? r.user_id.slice(0,8)}</div></TableCell>
                  <TableCell><Link to="/charging-agencies/$id" params={{ id: r.agency_id }} className="text-primary hover:underline">{ag?.name}</Link></TableCell>
                  <TableCell>{AGENT_ROLE_LABELS[r.member_role] ?? r.member_role}</TableCell>
                  <TableCell><Badge variant={r.status === "active" ? "default" : "secondary"}>{r.status}</Badge></TableCell>
                  <TableCell className="text-xs">{fmtDate(r.assigned_at)}</TableCell>
                  <TableCell><Link to="/charging-agents/$id" params={{ id: r.user_id }}><Button size="sm" variant="ghost">عرض</Button></Link></TableCell>
                </TableRow>);
              })}
            </TableBody></Table>}
        </CardContent>
      </Card>
    </div>
  );
}

function ActivateDialog({ onDone }: { onDone: () => void }) {
  const [open, setOpen] = useState(false);
  const [uid, setUid] = useState("");
  const [agencyId, setAgencyId] = useState("");
  const [role, setRole] = useState("charging_agent");
  const qc = useQueryClient();

  const agencies = useQuery({
    queryKey: ["charging_agencies_options"],
    enabled: open,
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_agencies").select("id, name, display_id").eq("status", "active").order("name");
      if (error) throw error;
      return data ?? [];
    },
  });

  const activate = useMutation({
    mutationFn: async () => {
      const { data: p, error } = await supabase.from("profiles").select("id").eq("external_uid", uid.trim()).maybeSingle();
      if (error) throw error;
      if (!p) throw new Error("لم يتم العثور على المستخدم");
      const args: Record<string, unknown> = { _user_id: p.id, _agency_id: agencyId, _member_role: role, _notes: null };
      const { error: e2 } = await supabase.rpc("activate_charging_agent", args as never);
      if (e2) throw e2;
    },
    onSuccess: () => { toast.success("تم تفعيل الوكيل"); qc.invalidateQueries({ queryKey: ["charging_agents"] }); setOpen(false); onDone(); },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild><Button><Plus className="ml-1 h-4 w-4" /> تفعيل وكيل</Button></DialogTrigger>
      <DialogContent dir="rtl">
        <DialogHeader><DialogTitle>تفعيل مستخدم كوكيل شحن</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label>UID المستخدم</Label><Input value={uid} onChange={(e) => setUid(e.target.value)} placeholder="YMU-000123" /></div>
          <div><Label>الوكالة</Label>
            <Select value={agencyId} onValueChange={setAgencyId}>
              <SelectTrigger><SelectValue placeholder={agencies.isLoading ? "…" : "اختر"} /></SelectTrigger>
              <SelectContent>{(agencies.data ?? []).map((a) => <SelectItem key={a.id} value={a.id}>{a.name} ({a.display_id})</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div><Label>الدور</Label>
            <Select value={role} onValueChange={setRole}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{Object.entries(AGENT_ROLE_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}</SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
          <Button onClick={() => activate.mutate()} disabled={!uid || !agencyId || activate.isPending}>{activate.isPending && <Loader2 className="ml-1 h-4 w-4 animate-spin" />}تفعيل</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
