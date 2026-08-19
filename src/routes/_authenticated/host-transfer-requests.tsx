import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Loader2, ArrowRightLeft, Check, X, Play } from "lucide-react";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/host-transfer-requests")({
  component: () => <PermissionGuard permission="hosts.transfer"><TransfersPage /></PermissionGuard>,
});

const STATUS_AR: Record<string, string> = {
  pending: "قيد المراجعة", source_approved: "موافقة المصدر", target_approved: "موافقة الهدف",
  bd_approved: "موافقة BD", completed: "مكتمل", rejected: "مرفوض", cancelled: "ملغى",
};

function TransfersPage() {
  const [status, setStatus] = useState("pending");
  const qc = useQueryClient();
  const { has } = usePermissions();

  const q = useQuery({
    queryKey: ["transfers", status],
    queryFn: async () => {
      let query = supabase.from("agency_host_transfer_requests")
        .select("id, host_user_id, from_agency_id, to_agency_id, status, reason, source_decision, target_decision, bd_decision, admin_decision, created_at")
        .order("created_at", { ascending: false }).limit(100);
      if (status !== "all") query = query.eq("status", status);
      const { data, error } = await query;
      if (error) throw error;
      return data ?? [];
    },
  });

  const act = useMutation({
    mutationFn: async (v: { fn: "approve_host_transfer_source" | "approve_host_transfer_target" | "approve_host_transfer_bd" | "approve_host_transfer_admin" | "cancel_host_transfer" | "execute_host_transfer"; id: string; approve?: boolean; note: string }) => {
      const args: Record<string, unknown> = { _request_id: v.id };
      if (v.fn !== "cancel_host_transfer" && v.fn !== "execute_host_transfer") { args._approve = v.approve; args._note = v.note; }
      if (v.fn === "cancel_host_transfer") args._reason = v.note;
      const { error } = await supabase.rpc(v.fn as never, args as never);
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم"); qc.invalidateQueries({ queryKey: ["transfers"] }); },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div><h1 className="text-2xl font-bold">طلبات نقل المضيفين</h1>
          <p className="text-sm text-muted-foreground">تدفق موافقات متعدد المراحل: المصدر ← الهدف ← BD ← الإدارة.</p></div>
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">الكل</SelectItem>
            {Object.entries(STATUS_AR).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      <Card>
        <CardContent className="pt-6">
          {q.isLoading ? <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div> :
            (q.data?.length ?? 0) === 0 ? (
              <div className="flex flex-col items-center gap-2 py-16"><ArrowRightLeft className="h-10 w-10 text-muted-foreground" /><p className="text-sm text-muted-foreground">لا توجد طلبات في هذه الحالة.</p></div>
            ) : (
              <Table>
                <TableHeader><TableRow>
                  <TableHead>المضيف</TableHead><TableHead>من</TableHead><TableHead>إلى</TableHead>
                  <TableHead>الحالة</TableHead><TableHead>المصدر</TableHead><TableHead>الهدف</TableHead>
                  <TableHead>BD</TableHead><TableHead>الإدارة</TableHead><TableHead>إجراءات</TableHead>
                </TableRow></TableHeader>
                <TableBody>{q.data!.map((r) => (
                  <TableRow key={r.id}>
                    <TableCell className="font-mono text-xs">{r.host_user_id.slice(0, 8)}…</TableCell>
                    <TableCell className="font-mono text-xs">{r.from_agency_id?.slice(0, 8) ?? "—"}</TableCell>
                    <TableCell className="font-mono text-xs">{r.to_agency_id.slice(0, 8)}…</TableCell>
                    <TableCell><Badge variant={r.status === "completed" ? "default" : r.status === "rejected" || r.status === "cancelled" ? "destructive" : "secondary"}>{STATUS_AR[r.status] ?? r.status}</Badge></TableCell>
                    <TableCell>{decisionBadge(r.source_decision)}</TableCell>
                    <TableCell>{decisionBadge(r.target_decision)}</TableCell>
                    <TableCell>{decisionBadge(r.bd_decision)}</TableCell>
                    <TableCell>{decisionBadge(r.admin_decision)}</TableCell>
                    <TableCell>
                      {has("hosts.transfer") && r.status !== "completed" && r.status !== "rejected" && r.status !== "cancelled" && (
                        <div className="flex gap-1">
                          <ActionDialog label="موافقة المصدر" onConfirm={(n) => act.mutate({ fn: "approve_host_transfer_source", id: r.id, approve: true, note: n })} />
                          <ActionDialog label="موافقة الهدف" onConfirm={(n) => act.mutate({ fn: "approve_host_transfer_target", id: r.id, approve: true, note: n })} />
                          <ActionDialog label="موافقة BD" onConfirm={(n) => act.mutate({ fn: "approve_host_transfer_bd", id: r.id, approve: true, note: n })} />
                          <ActionDialog label="موافقة الإدارة" onConfirm={(n) => act.mutate({ fn: "approve_host_transfer_admin", id: r.id, approve: true, note: n })} />
                          {r.status === "bd_approved" && (
                            <Button size="sm" variant="default" onClick={() => act.mutate({ fn: "execute_host_transfer", id: r.id, note: "" })}><Play className="h-3 w-3" /></Button>
                          )}
                          <ActionDialog label="إلغاء" destructive onConfirm={(n) => act.mutate({ fn: "cancel_host_transfer", id: r.id, note: n })} />
                        </div>
                      )}
                    </TableCell>
                  </TableRow>
                ))}</TableBody>
              </Table>
            )}
        </CardContent>
      </Card>
    </div>
  );
}

function decisionBadge(d: string | null) {
  if (!d) return <span className="text-xs text-muted-foreground">—</span>;
  return <Badge variant={d === "approve" ? "default" : "destructive"} className="text-[10px]">{d === "approve" ? <Check className="h-3 w-3" /> : <X className="h-3 w-3" />}</Badge>;
}

function ActionDialog({ label, onConfirm, destructive }: { label: string; onConfirm: (note: string) => void; destructive?: boolean }) {
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild><Button size="sm" variant={destructive ? "destructive" : "outline"} className="text-[10px] px-2">{label}</Button></DialogTrigger>
      <DialogContent dir="rtl">
        <DialogHeader><DialogTitle>{label}</DialogTitle></DialogHeader>
        <div className="space-y-2"><Label>ملاحظة (اختيارية للموافقة، مطلوبة للإلغاء)</Label><Textarea value={note} onChange={(e) => setNote(e.target.value)} rows={3} /></div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
          <Button disabled={destructive && note.length < 5} onClick={() => { onConfirm(note); setOpen(false); setNote(""); }}>تأكيد</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
