import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Loader2 } from "lucide-react";
import { fmtNum, fmtDate } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-pricing")({
  component: () => <PermissionGuard permission="charging_pricing.read"><Page /></PermissionGuard>,
});

function Page() {
  const rules = useQuery({
    queryKey: ["charging_price_rules"],
    queryFn: async () => {
      const { data, error } = await supabase.from("charging_price_rules")
        .select("id, country, currency, operation, tier_from, tier_to, unit_price, fee_percentage, commission_percentage, status, starts_at")
        .order("created_at", { ascending: false }).limit(100);
      if (error) throw error;
      return data ?? [];
    },
  });
  const rates = useQuery({
    queryKey: ["pearl_coin_exchange_rates"],
    queryFn: async () => {
      const { data, error } = await supabase.from("pearl_coin_exchange_rates")
        .select("id, country, pearl_amount_from, pearl_amount_to, coins_per_pearl, fee_percentage, min_exchange, max_exchange, status, starts_at")
        .order("created_at", { ascending: false }).limit(100);
      if (error) throw error;
      return data ?? [];
    },
  });

  return (
    <div className="space-y-6">
      <div><h1 className="text-2xl font-bold">أسعار وكالات الشحن</h1><p className="text-sm text-muted-foreground">قواعد التسعير وأسعار تبديل اللؤلؤ إلى كوينز.</p></div>
      <Tabs defaultValue="rules">
        <TabsList>
          <TabsTrigger value="rules">قواعد التسعير</TabsTrigger>
          <TabsTrigger value="rates">أسعار التبديل</TabsTrigger>
        </TabsList>
        <TabsContent value="rules">
          <Card><CardHeader><CardTitle className="text-sm">قواعد الأسعار</CardTitle></CardHeader><CardContent>
            {rules.isLoading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> :
              (rules.data ?? []).length === 0 ? <div className="py-8 text-center text-sm text-muted-foreground">لا توجد قواعد</div> :
              <Table><TableHeader><TableRow><TableHead>الدولة</TableHead><TableHead>العملة</TableHead><TableHead>العملية</TableHead><TableHead>الشريحة</TableHead><TableHead>السعر</TableHead><TableHead>رسوم</TableHead><TableHead>عمولة</TableHead><TableHead>الحالة</TableHead></TableRow></TableHeader><TableBody>
                {rules.data!.map((r) => (<TableRow key={r.id}>
                  <TableCell>{r.country ?? "الكل"}</TableCell>
                  <TableCell>{r.currency ?? "-"}</TableCell>
                  <TableCell>{r.operation}</TableCell>
                  <TableCell className="text-xs">{fmtNum(r.tier_from)} - {r.tier_to ? fmtNum(r.tier_to) : "∞"}</TableCell>
                  <TableCell>{fmtNum(r.unit_price)}</TableCell>
                  <TableCell>{r.fee_percentage ?? 0}%</TableCell>
                  <TableCell>{r.commission_percentage ?? 0}%</TableCell>
                  <TableCell><Badge variant="secondary">{r.status}</Badge></TableCell>
                </TableRow>))}
              </TableBody></Table>}
          </CardContent></Card>
        </TabsContent>
        <TabsContent value="rates">
          <Card><CardHeader><CardTitle className="text-sm">أسعار تبديل اللؤلؤ إلى كوينز</CardTitle></CardHeader><CardContent>
            {rates.isLoading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> :
              (rates.data ?? []).length === 0 ? <div className="py-8 text-center text-sm text-muted-foreground">لا توجد أسعار</div> :
              <Table><TableHeader><TableRow><TableHead>الدولة</TableHead><TableHead>الشريحة (لؤلؤ)</TableHead><TableHead>كوينز/لؤلؤ</TableHead><TableHead>رسوم</TableHead><TableHead>حد أدنى</TableHead><TableHead>حد أقصى</TableHead><TableHead>الحالة</TableHead><TableHead>البدء</TableHead></TableRow></TableHeader><TableBody>
                {rates.data!.map((r) => (<TableRow key={r.id}>
                  <TableCell>{r.country ?? "الكل"}</TableCell>
                  <TableCell className="text-xs">{fmtNum(r.pearl_amount_from)} - {r.pearl_amount_to ? fmtNum(r.pearl_amount_to) : "∞"}</TableCell>
                  <TableCell>{fmtNum(r.coins_per_pearl)}</TableCell>
                  <TableCell>{r.fee_percentage ?? 0}%</TableCell>
                  <TableCell>{fmtNum(r.min_exchange)}</TableCell>
                  <TableCell>{fmtNum(r.max_exchange)}</TableCell>
                  <TableCell><Badge variant="secondary">{r.status}</Badge></TableCell>
                  <TableCell className="text-xs">{fmtDate(r.starts_at)}</TableCell>
                </TableRow>))}
              </TableBody></Table>}
          </CardContent></Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
