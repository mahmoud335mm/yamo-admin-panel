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
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Loader2, Plus, Megaphone } from "lucide-react";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/bd")({
  component: () => <PermissionGuard permission="bd.read"><BDPage /></PermissionGuard>,
});

function BDPage() {
  const { has } = usePermissions();
  const q = useQuery({
    queryKey: ["bd_managers"],
    queryFn: async () => {
      const { data, error } = await supabase.from("bd_managers")
        .select("id, code, display_name, phone, email, country, level_id, status, created_at")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div><h1 className="text-2xl font-bold">نظام BD</h1>
          <p className="text-sm text-muted-foreground">مديرو تطوير الأعمال المسؤولون عن الوكالات.</p></div>
        {has("bd.write") && <CreateBDDialog />}
      </div>
      <Card>
        <CardContent className="pt-6">
          {q.isLoading ? <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div> :
            (q.data?.length ?? 0) === 0 ? (
              <div className="flex flex-col items-center gap-2 py-16"><Megaphone className="h-10 w-10 text-muted-foreground" /><p className="text-sm text-muted-foreground">لا يوجد مديرو BD.</p></div>
            ) : (
              <Table>
                <TableHeader><TableRow>
                  <TableHead>الكود</TableHead><TableHead>الاسم</TableHead><TableHead>الهاتف</TableHead>
                  <TableHead>الدولة</TableHead><TableHead>المستوى</TableHead><TableHead>الحالة</TableHead>
                </TableRow></TableHeader>
                <TableBody>{q.data!.map((b) => (
                  <TableRow key={b.id} className="cursor-pointer hover:bg-muted/50">
                    <TableCell className="font-mono text-xs"><Link to="/bd/$id" params={{ id: b.id }} className="hover:underline">{b.code}</Link></TableCell>
                    <TableCell><Link to="/bd/$id" params={{ id: b.id }} className="font-medium hover:underline">{b.display_name}</Link></TableCell>
                    <TableCell>{b.phone ?? "—"}</TableCell>
                    <TableCell>{b.country ?? "—"}</TableCell>
                    <TableCell>BD{b.level_id ?? "—"}</TableCell>
                    <TableCell><Badge variant={b.status === "active" ? "default" : "destructive"}>{b.status}</Badge></TableCell>
                  </TableRow>
                ))}</TableBody>
              </Table>
            )}
        </CardContent>
      </Card>
    </div>
  );
}

function CreateBDDialog() {
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({ code: "", display_name: "", phone: "", email: "", country: "" });
  const qc = useQueryClient();
  const create = useMutation({
    mutationFn: async () => {
      const args = {
        _code: form.code, _display_name: form.display_name,
        _phone: form.phone || "", _email: form.email || "",
        _country: form.country || "", _level: 1,
        _admin_user_id: null as unknown as string,
      };
      const { error } = await supabase.rpc("create_bd_manager", args);
      if (error) throw error;
    },
    onSuccess: () => { toast.success("تم إنشاء مدير BD"); qc.invalidateQueries({ queryKey: ["bd_managers"] }); setOpen(false); setForm({ code: "", display_name: "", phone: "", email: "", country: "" }); },
    onError: (e: Error) => toast.error(e.message),
  });
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild><Button><Plus className="ml-1 h-4 w-4" />مدير BD جديد</Button></DialogTrigger>
      <DialogContent dir="rtl">
        <DialogHeader><DialogTitle>مدير BD جديد</DialogTitle></DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1"><Label>الكود</Label><Input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} placeholder="BD-01" /></div>
          <div className="space-y-1"><Label>الاسم</Label><Input value={form.display_name} onChange={(e) => setForm({ ...form, display_name: e.target.value })} /></div>
          <div className="space-y-1"><Label>الهاتف</Label><Input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></div>
          <div className="space-y-1"><Label>البريد</Label><Input value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} type="email" /></div>
          <div className="space-y-1"><Label>الدولة</Label><Input value={form.country} onChange={(e) => setForm({ ...form, country: e.target.value })} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
          <Button disabled={create.isPending || !form.code || !form.display_name} onClick={() => create.mutate()}>
            {create.isPending && <Loader2 className="ml-1 h-4 w-4 animate-spin" />}إنشاء
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
