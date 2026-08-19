import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { BarChart3, Loader2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { yamoRpc } from "@/lib/yamo-admin";

function AnalyticsPage() {
  const query = useQuery({
    queryKey: ["yamo-admin", "analytics", 30],
    queryFn: () => yamoRpc<Record<string, unknown>[]>("get_yamo_admin_analytics", { p_days: 30 }),
  });
  const rows = query.data ?? [];
  const total = (key: string) => rows.reduce((sum, row) => sum + Number(row[key] ?? 0), 0);
  if (query.isLoading)
    return (
      <div className="grid h-64 place-items-center">
        <Loader2 className="h-7 w-7 animate-spin" />
      </div>
    );
  return (
    <div className="space-y-5">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-black">
          <BarChart3 />
          تقارير Yamo الحقيقية
        </h1>
        <p className="text-sm text-muted-foreground">
          آخر 30 يوم محسوبة من سجلات التطبيق وليس بيانات تجريبية
        </p>
      </div>
      <div className="grid gap-3 md:grid-cols-4">
        {[
          { l: "مستخدمون جدد", k: "new_users" },
          { l: "الرسائل", k: "messages" },
          { l: "كوينز الهدايا", k: "gift_coins" },
          { l: "كوينز الشحن", k: "recharge_coins" },
        ].map((x) => (
          <Card key={x.k}>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm text-muted-foreground">{x.l}</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-black">
              {total(x.k).toLocaleString("ar-EG")}
            </CardContent>
          </Card>
        ))}
      </div>
      <Card>
        <CardContent className="overflow-x-auto pt-6">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>اليوم</TableHead>
                <TableHead>مستخدمون</TableHead>
                <TableHead>رسائل</TableHead>
                <TableHead>هدايا</TableHead>
                <TableHead>شحن</TableHead>
                <TableHead>غرف نشطة</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row) => (
                <TableRow key={String(row.day)}>
                  <TableCell>{String(row.day)}</TableCell>
                  <TableCell>{String(row.new_users ?? 0)}</TableCell>
                  <TableCell>{String(row.messages ?? 0)}</TableCell>
                  <TableCell>{String(row.gift_coins ?? 0)}</TableCell>
                  <TableCell>{String(row.recharge_coins ?? 0)}</TableCell>
                  <TableCell>{String(row.active_rooms ?? 0)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
export const Route = createFileRoute("/_authenticated/analytics")({ component: AnalyticsPage });
