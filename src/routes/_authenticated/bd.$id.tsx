import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ArrowRight, Loader2, Megaphone } from "lucide-react";

export const Route = createFileRoute("/_authenticated/bd/$id")({
  component: () => <PermissionGuard permission="bd.read"><BDDetail /></PermissionGuard>,
});

function BDDetail() {
  const { id } = Route.useParams();

  const b = useQuery({
    queryKey: ["bd", id],
    queryFn: async () => (await supabase.from("bd_managers").select("*").eq("id", id).maybeSingle()).data,
  });

  const agencies = useQuery({
    queryKey: ["bd", id, "agencies"],
    queryFn: async () => (await supabase.from("agencies").select("id, code, name, status, active_hosts, total_hosts, monthly_coins, level_id").eq("bd_id", id).order("monthly_coins", { ascending: false })).data ?? [],
  });

  const commissions = useQuery({
    queryKey: ["bd", id, "commissions"],
    queryFn: async () => (await supabase.from("bd_commissions").select("*").eq("bd_id", id).order("period_year", { ascending: false }).order("period_month", { ascending: false }).limit(12)).data ?? [],
  });

  const audit = useQuery({
    queryKey: ["bd", id, "audit"],
    queryFn: async () => (await supabase.from("audit_logs").select("id, actor_email, action, metadata, created_at").eq("entity_type", "bd_managers").eq("entity_id", id).order("created_at", { ascending: false }).limit(50)).data ?? [],
  });

  if (b.isLoading) return <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div>;
  if (!b.data) return <div className="py-16 text-center text-sm text-muted-foreground">مدير BD غير موجود.</div>;
  const bd = b.data;

  const totalHosts = (agencies.data ?? []).reduce((s, a) => s + a.total_hosts, 0);
  const activeHosts = (agencies.data ?? []).reduce((s, a) => s + a.active_hosts, 0);
  const monthlyCoins = (agencies.data ?? []).reduce((s, a) => s + Number(a.monthly_coins), 0);
  const totalCommission = (commissions.data ?? []).reduce((s, c) => s + Number(c.commission_coins), 0);

  return (
    <div className="space-y-6">
      <Button variant="ghost" size="sm" asChild><Link to="/bd"><ArrowRight className="ml-1 h-4 w-4" />رجوع</Link></Button>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Megaphone className="h-5 w-5 text-primary" />{bd.display_name} <span className="text-sm text-muted-foreground">({bd.code})</span></CardTitle>
          <div className="mt-2 flex flex-wrap gap-2">
            <Badge variant={bd.status === "active" ? "default" : "destructive"}>{bd.status}</Badge>
            <Badge variant="secondary">BD Lv {bd.level_id ?? "—"}</Badge>
            {bd.country && <Badge variant="outline">{bd.country}</Badge>}
            {bd.phone && <Badge variant="outline">{bd.phone}</Badge>}
            {bd.email && <Badge variant="outline">{bd.email}</Badge>}
          </div>
          <div className="mt-4 grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
            <Stat label="عدد الوكالات" value={String(agencies.data?.length ?? 0)} />
            <Stat label="مضيفون نشطون" value={`${activeHosts} / ${totalHosts}`} />
            <Stat label="عملات الشهر" value={monthlyCoins.toLocaleString()} />
            <Stat label="إجمالي العمولة" value={totalCommission.toLocaleString()} />
          </div>
        </CardHeader>
      </Card>

      <Tabs defaultValue="agencies">
        <TabsList>
          <TabsTrigger value="agencies">الوكالات ({agencies.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="commissions">العمولات ({commissions.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="audit">سجل العمليات</TabsTrigger>
        </TabsList>

        <TabsContent value="agencies">
          <Card><CardContent className="pt-6">
            {(agencies.data?.length ?? 0) === 0 ? <Empty text="لا وكالات مرتبطة." /> : (
              <Table><TableHeader><TableRow><TableHead>الكود</TableHead><TableHead>الاسم</TableHead><TableHead>الحالة</TableHead><TableHead>المستوى</TableHead><TableHead>مضيفون</TableHead><TableHead>عملات الشهر</TableHead></TableRow></TableHeader>
                <TableBody>{agencies.data!.map((a) => (
                  <TableRow key={a.id}>
                    <TableCell className="font-mono text-xs"><Link to="/agencies/$id" params={{ id: a.id }} className="hover:underline">{a.code}</Link></TableCell>
                    <TableCell><Link to="/agencies/$id" params={{ id: a.id }} className="font-medium hover:underline">{a.name}</Link></TableCell>
                    <TableCell><Badge variant={a.status === "active" ? "default" : "destructive"}>{a.status}</Badge></TableCell>
                    <TableCell>Lv {a.level_id ?? "—"}</TableCell>
                    <TableCell className="font-mono">{a.active_hosts}/{a.total_hosts}</TableCell>
                    <TableCell className="font-mono">{a.monthly_coins.toLocaleString()}</TableCell>
                  </TableRow>
                ))}</TableBody></Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="commissions">
          <Card><CardContent className="pt-6">
            {(commissions.data?.length ?? 0) === 0 ? <Empty text="لا عمولات." /> : (
              <Table><TableHeader><TableRow><TableHead>الفترة</TableHead><TableHead>الوكالة</TableHead><TableHead>إجمالي</TableHead><TableHead>نسبة العمولة</TableHead><TableHead>العمولة</TableHead><TableHead>الحالة</TableHead></TableRow></TableHeader>
                <TableBody>{commissions.data!.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell>{c.period_year}/{String(c.period_month).padStart(2, "0")}</TableCell>
                    <TableCell className="font-mono text-xs">{c.agency_id?.slice(0, 8) ?? "—"}</TableCell>
                    <TableCell className="font-mono">{c.gross_coins.toLocaleString()}</TableCell>
                    <TableCell className="font-mono">{c.commission_pct}%</TableCell>
                    <TableCell className="font-mono font-bold">{c.commission_coins.toLocaleString()}</TableCell>
                    <TableCell><Badge variant={c.status === "paid" ? "default" : "secondary"}>{c.status}</Badge></TableCell>
                  </TableRow>
                ))}</TableBody></Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="audit">
          <Card><CardContent className="pt-6">
            {(audit.data?.length ?? 0) === 0 ? <Empty text="لا سجلات." /> : (
              <Table><TableHeader><TableRow><TableHead>الوقت</TableHead><TableHead>المسؤول</TableHead><TableHead>العملية</TableHead></TableRow></TableHeader>
                <TableBody>{audit.data!.map((a) => (
                  <TableRow key={a.id}>
                    <TableCell className="text-xs">{new Date(a.created_at).toLocaleString("ar-EG-u-nu-latn")}</TableCell>
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

function Stat({ label, value }: { label: string; value: string }) {
  return <div className="rounded-lg border bg-muted/30 p-3"><div className="text-xs text-muted-foreground">{label}</div><div className="mt-1 font-mono text-sm font-semibold">{value}</div></div>;
}
function Empty({ text }: { text: string }) { return <div className="py-10 text-center text-sm text-muted-foreground">{text}</div>; }
