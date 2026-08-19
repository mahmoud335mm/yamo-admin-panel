import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
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
import { Loader2, Plus, Search, Zap } from "lucide-react";
import { toast } from "sonner";
import { CHARGING_AGENCY_STATUS, fmtDate } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-agencies")({
  component: () => <PermissionGuard permission="charging_agencies.read"><Page /></PermissionGuard>,
});

function Page() {
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("all");
  const [page, setPage] = useState(0);
  const size = 25;
  const { has } = usePermissions();

  const list = useQuery({
    queryKey: ["charging_agencies", q, status, page],
    queryFn: async () => {
      let query = supabase.from("charging_agencies")
        .select("id, display_id, name, country, status, default_currency, created_at, owner_user_id", { count: "exact" })
        .order("created_at", { ascending: false })
        .range(page * size, page * size + size - 1);
      if (q.trim()) query = query.or(`name.ilike.%${q}%,display_id.ilike.%${q}%,country.ilike.%${q}%`);
      if (status !== "all") query = query.eq("status", status as never);
      const { data, count, error } = await query;
      if (error) throw error;
      return { rows: data ?? [], total: count ?? 0 };
    },
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">وكالات الشحن</h1>
          <p className="text-sm text-muted-foreground">إدارة كيانات وكالات الشحن، حالتها، ومالكيها.</p>
        </div>
        {has("charging_agencies.create") && <CreateDialog onDone={() => list.refetch()} />}
      </div>

      <Card>
        <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <div className="relative flex-1">
            <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input placeholder="بحث بالاسم أو الكود أو الدولة…" value={q} onChange={(e) => { setQ(e.target.value); setPage(0); }} className="pr-9" />
          </div>
          <Select value={status} onValueChange={(v) => { setStatus(v); setPage(0); }}>
            <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">كل الحالات</SelectItem>
              {Object.entries(CHARGING_AGENCY_STATUS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
            </SelectContent>
          </Select>
        </CardHeader>
        <CardContent>
          {list.isLoading ? (
            <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div>
          ) : list.isError ? (
            <div className="py-16 text-center text-sm text-destructive">فشل التحميل: {(list.error as Error).message}</div>
          ) : list.data!.rows.length === 0 ? (
            <div className="flex flex-col items-center gap-2 py-16 text-center">
              <Zap className="h-10 w-10 text-muted-foreground" />
              <p className="text-sm text-muted-foreground">لا توجد وكالات شحن حتى الآن.</p>
            </div>
          ) : (
            <>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>الكود</TableHead>
                    <TableHead>الاسم</TableHead>
                    <TableHead>الدولة</TableHead>
                    <TableHead>العملة</TableHead>
                    <TableHead>الحالة</TableHead>
                    <TableHead>تاريخ الإنشاء</TableHead>
                    <TableHead></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {list.data!.rows.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell className="font-mono text-xs">{r.display_id}</TableCell>
                      <TableCell className="font-medium">{r.name}</TableCell>
                      <TableCell>{r.country ?? "-"}</TableCell>
                      <TableCell>{r.default_currency ?? "-"}</TableCell>
                      <TableCell><Badge variant={r.status === "active" ? "default" : "secondary"}>{CHARGING_AGENCY_STATUS[r.status] ?? r.status}</Badge></TableCell>
                      <TableCell className="text-xs text-muted-foreground">{fmtDate(r.created_at)}</TableCell>
                      <TableCell>
                        <Link to="/charging-agencies/$id" params={{ id: r.id }}>
                          <Button size="sm" variant="ghost">عرض</Button>
                        </Link>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              <div className="mt-4 flex items-center justify-between text-sm text-muted-foreground">
                <span>الإجمالي: {list.data!.total}</span>
                <div className="flex items-center gap-2">
                  <Button size="sm" variant="outline" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>السابق</Button>
                  <span>صفحة {page + 1}</span>
                  <Button size="sm" variant="outline" disabled={(page + 1) * size >= list.data!.total} onClick={() => setPage((p) => p + 1)}>التالي</Button>
                </div>
              </div>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function CreateDialog({ onDone }: { onDone: () => void }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [country, setCountry] = useState("");
  const [city, setCity] = useState("");
  const [currency, setCurrency] = useState("USD");
  const [ownerUid, setOwnerUid] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const navigate = useNavigate();
  const qc = useQueryClient();

  const create = useMutation({
    mutationFn: async () => {
      let ownerId: string | null = null;
      if (ownerUid.trim()) {
        const { data: p, error } = await supabase.from("profiles").select("id").eq("external_uid", ownerUid.trim()).maybeSingle();
        if (error) throw error;
        if (!p) throw new Error("لم يتم العثور على المستخدم المالك بهذا UID");
        ownerId = p.id;
      }
      const args: Record<string, unknown> = {
        _name: name,
        _country: country || null,
        _city: city || null,
        _default_currency: currency || "USD",
        _owner_user_id: ownerId,
        _deputy_user_id: null,
        _phone: phone || null,
        _email: email || null,
      };
      const { data, error } = await supabase.rpc("create_charging_agency", args as never);
      if (error) throw error;
      return data as string;
    },
    onSuccess: (id) => {
      toast.success("تم إنشاء الوكالة");
      qc.invalidateQueries({ queryKey: ["charging_agencies"] });
      setOpen(false);
      onDone();
      if (id) navigate({ to: "/charging-agencies/$id", params: { id } });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild><Button><Plus className="ml-1 h-4 w-4" /> وكالة جديدة</Button></DialogTrigger>
      <DialogContent dir="rtl">
        <DialogHeader><DialogTitle>إنشاء وكالة شحن</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label>الاسم *</Label><Input value={name} onChange={(e) => setName(e.target.value)} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>الدولة</Label><Input value={country} onChange={(e) => setCountry(e.target.value)} /></div>
            <div><Label>المدينة</Label><Input value={city} onChange={(e) => setCity(e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>العملة</Label><Input value={currency} onChange={(e) => setCurrency(e.target.value)} /></div>
            <div><Label>UID المالك (اختياري)</Label><Input value={ownerUid} onChange={(e) => setOwnerUid(e.target.value)} placeholder="مثال: YMU-000123" /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>الهاتف</Label><Input value={phone} onChange={(e) => setPhone(e.target.value)} /></div>
            <div><Label>البريد</Label><Input value={email} onChange={(e) => setEmail(e.target.value)} /></div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
          <Button onClick={() => create.mutate()} disabled={!name || create.isPending}>{create.isPending && <Loader2 className="ml-1 h-4 w-4 animate-spin" />}إنشاء</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
