import { createFileRoute } from "@tanstack/react-router";
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
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { Loader2, Search, Undo2, Sparkle } from "lucide-react";
import { toast } from "sonner";
import { CHARGING_TXN_STATUS, fmtDate, fmtNum } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-pearl-transfers")({
  component: () => <PermissionGuard permission="charging_pearl_transfers.read"><Page /></PermissionGuard>,
});

function Page() {
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("all");
  const [page, setPage] = useState(0);
  const size = 25;
  const { has } = usePermissions();
  const qc = useQueryClient();

  const list = useQuery({
    queryKey: ["cpearl_transfers", q, status, page],
    queryFn: async () => {
      let query = supabase.from("charging_pearl_transfers")
        .select("id, reference, amount, status, created_at, from_user_id, to_user_id, note", { count: "exact" })
        .order("created_at", { ascending: false })
        .range(page * size, page * size + size - 1);
      if (status !== "all") query = query.eq("status", status as never);
      if (q.trim()) query = query.ilike("reference", `%${q.trim()}%`);
      const { data, count, error } = await query;
      if (error) throw error;
      return { rows: data ?? [], total: count ?? 0 };
    },
  });

  const [reverseId, setReverseId] = useState<string | null>(null);
  const [reason, setReason] = useState("");

  const reverse = useMutation({
    mutationFn: async () => {
      if (!reverseId) return;
      const { error } = await supabase.rpc("reverse_pearl_transfer", { _transfer_id: reverseId, _reason: reason } as never);
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم عكس التحويل"); qc.invalidateQueries({ queryKey: ["cpearl_transfers"] }); setReverseId(null); setReason(""); },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <div className="space-y-6">
      <div><h1 className="text-2xl font-bold">تحويلات اللؤلؤ</h1><p className="text-sm text-muted-foreground">تحويلات اللؤلؤ بين الحسابات.</p></div>
      <Card>
        <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <div className="relative flex-1"><Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input placeholder="بحث بالمرجع…" value={q} onChange={(e) => setQ(e.target.value)} className="pr-9" /></div>
          <Select value={status} onValueChange={(v) => { setStatus(v); setPage(0); }}>
            <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
            <SelectContent><SelectItem value="all">الكل</SelectItem>{Object.entries(CHARGING_TXN_STATUS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}</SelectContent>
          </Select>
        </CardHeader>
        <CardContent>
          {list.isLoading ? <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div> :
            list.data!.rows.length === 0 ? <div className="flex flex-col items-center gap-2 py-16"><Sparkle className="h-10 w-10 text-muted-foreground" /><p className="text-sm text-muted-foreground">لا توجد تحويلات</p></div> :
            <Table><TableHeader><TableRow><TableHead>المرجع</TableHead><TableHead>من</TableHead><TableHead>إلى</TableHead><TableHead>المبلغ</TableHead><TableHead>الحالة</TableHead><TableHead>التاريخ</TableHead><TableHead></TableHead></TableRow></TableHeader><TableBody>
              {list.data!.rows.map((r) => (<TableRow key={r.id}>
                <TableCell className="font-mono text-xs">{r.reference}</TableCell>
                <TableCell className="font-mono text-xs">{r.from_user_id.slice(0,8)}</TableCell>
                <TableCell className="font-mono text-xs">{r.to_user_id.slice(0,8)}</TableCell>
                <TableCell>{fmtNum(r.amount)}</TableCell>
                <TableCell><Badge variant={r.status === "completed" ? "default" : "secondary"}>{CHARGING_TXN_STATUS[r.status] ?? r.status}</Badge></TableCell>
                <TableCell className="text-xs">{fmtDate(r.created_at)}</TableCell>
                <TableCell>{r.status === "completed" && has("charging_pearl_transfers.reverse") && <Button size="sm" variant="ghost" onClick={() => setReverseId(r.id)}><Undo2 className="ml-1 h-4 w-4" />عكس</Button>}</TableCell>
              </TableRow>))}
            </TableBody></Table>}
        </CardContent>
      </Card>
      <Dialog open={!!reverseId} onOpenChange={(o) => !o && setReverseId(null)}>
        <DialogContent dir="rtl">
          <DialogHeader><DialogTitle>عكس تحويل اللؤلؤ</DialogTitle></DialogHeader>
          <div><Label>السبب (5 أحرف على الأقل)</Label><Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} /></div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setReverseId(null)}>إلغاء</Button>
            <Button variant="destructive" disabled={reason.length < 5 || reverse.isPending} onClick={() => reverse.mutate()}>{reverse.isPending && <Loader2 className="ml-1 h-4 w-4 animate-spin" />}تأكيد</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
