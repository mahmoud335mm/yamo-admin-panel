import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { Card, CardContent } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Loader2, ShoppingBag } from "lucide-react";
import { fmtDate, fmtNum, CHARGING_TXN_STATUS } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/pearl-purchases")({
  component: () => <PermissionGuard permission="pearl_purchases.read"><Page /></PermissionGuard>,
});

function Page() {
  const q = useQuery({
    queryKey: ["pearl_purchases"],
    queryFn: async () => {
      const { data, error } = await supabase.from("pearl_purchase_requests")
        .select("id, reference, agent_user_id, user_id, pearl_amount, price_amount, currency, status, created_at")
        .order("created_at", { ascending: false }).limit(100);
      if (error) throw error;
      return data ?? [];
    },
  });
  return (
    <div className="space-y-6">
      <div><h1 className="text-2xl font-bold">شراء اللؤلؤ</h1><p className="text-sm text-muted-foreground">طلبات شراء اللؤلؤ عبر وكلاء الشحن.</p></div>
      <Card><CardContent className="pt-4">
        {q.isLoading ? <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div> :
          (q.data ?? []).length === 0 ? <div className="flex flex-col items-center gap-2 py-16"><ShoppingBag className="h-10 w-10 text-muted-foreground" /><p className="text-sm text-muted-foreground">لا توجد طلبات</p></div> :
          <Table><TableHeader><TableRow><TableHead>المرجع</TableHead><TableHead>الوكيل</TableHead><TableHead>المشتري</TableHead><TableHead>اللؤلؤ</TableHead><TableHead>السعر</TableHead><TableHead>الحالة</TableHead><TableHead>التاريخ</TableHead></TableRow></TableHeader><TableBody>
            {q.data!.map((r) => (<TableRow key={r.id}>
              <TableCell className="font-mono text-xs">{r.reference}</TableCell>
              <TableCell className="font-mono text-xs">{r.agent_user_id.slice(0,8)}</TableCell>
              <TableCell className="font-mono text-xs">{r.user_id.slice(0,8)}</TableCell>
              <TableCell>{fmtNum(r.pearl_amount)}</TableCell>
              <TableCell>{fmtNum(r.price_amount)} {r.currency ?? ""}</TableCell>
              <TableCell><Badge variant="secondary">{CHARGING_TXN_STATUS[r.status] ?? r.status}</Badge></TableCell>
              <TableCell className="text-xs">{fmtDate(r.created_at)}</TableCell>
            </TableRow>))}
          </TableBody></Table>}
      </CardContent></Card>
    </div>
  );
}
