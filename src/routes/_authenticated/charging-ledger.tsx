import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Loader2, RefreshCw, Search } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { fmtDate, fmtNum } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-ledger")({
  component: () => (
    <PermissionGuard permission="charging_agencies.read">
      <Page />
    </PermissionGuard>
  ),
});
type Person = {
  id: string;
  legacy_id: string | null;
  display_name: string | null;
  avatar_url: string | null;
};
const LABELS: Record<string, string> = {
  coin_charge: "شحن كوينز",
  user_to_agent_pearl: "مستخدم ← وكيل",
  agent_to_agent_pearl: "وكيل ← وكيل",
  pearl_transfer: "تحويل لؤلؤ",
  platform_charge: "شحن من المنصة",
  admin_funding: "تمويل من الإدارة",
  game: "لعب",
  pearl_withdrawal: "سحب لؤلؤ",
  pearl_exchange: "تبديل لؤلؤ",
  gift: "هدايا",
  paid_message: "رسائل مدفوعة",
  paid_call: "مكالمات مدفوعة",
  wallet_activity: "حركة محفظة",
};
function Page() {
  const [q, setQ] = useState(""),
    [category, setCategory] = useState("all"),
    [asset, setAsset] = useState("all");
  const log = useQuery({
    queryKey: ["charging_activity_ledger"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("charging_activity_ledger")
        .select("*")
        .order("occurred_at", { ascending: false })
        .limit(500);
      if (error) throw error;
      const rows = data ?? [];
      const ids = [
        ...new Set(rows.flatMap((r) => [r.actor_user_id, r.counterparty_user_id]).filter(Boolean)),
      ] as string[];
      const agencyIds = [...new Set(rows.map((r) => r.agency_id).filter(Boolean))] as string[];
      const [peopleResult, agencyResult] = await Promise.all([
        ids.length
          ? supabase.from("profiles").select("id,legacy_id,display_name,avatar_url").in("id", ids)
          : Promise.resolve({ data: [] }),
        agencyIds.length
          ? supabase.from("charging_agencies").select("id,name,display_id").in("id", agencyIds)
          : Promise.resolve({ data: [] }),
      ]);
      const people = new Map(((peopleResult.data ?? []) as Person[]).map((p) => [p.id, p]));
      const agencies = new Map((agencyResult.data ?? []).map((a) => [a.id, a]));
      return rows.map((r) => ({
        ...r,
        actor: r.actor_user_id ? people.get(r.actor_user_id) : null,
        counterparty: r.counterparty_user_id ? people.get(r.counterparty_user_id) : null,
        agency: r.agency_id ? agencies.get(r.agency_id) : null,
      }));
    },
  });
  const rows = useMemo(() => {
    const term = q.trim().toLowerCase();
    return (log.data ?? []).filter(
      (r) =>
        (category === "all" || r.category === category) &&
        (asset === "all" || r.asset === asset) &&
        (!term ||
          [
            r.reference,
            r.description,
            r.actor?.legacy_id,
            r.actor?.display_name,
            r.counterparty?.legacy_id,
            r.counterparty?.display_name,
            r.agency?.name,
          ].some((v) =>
            String(v ?? "")
              .toLowerCase()
              .includes(term),
          )),
    );
  }, [log.data, q, category, asset]);
  return (
    <div className="space-y-6" dir="rtl">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black">السجل المالي الشامل</h1>
          <p className="text-sm text-muted-foreground">
            كل حركة للوكلاء والمستخدمين والمنصة والإدارة في مكان واحد.
          </p>
        </div>
        <div className="flex gap-2">
          <Link to="/charging-agencies">
            <Button variant="outline">
              <ArrowRight className="ml-2 h-4 w-4" />
              وكالة الشحن
            </Button>
          </Link>
          <Button variant="outline" onClick={() => log.refetch()}>
            <RefreshCw className="ml-2 h-4 w-4" />
            تحديث
          </Button>
        </div>
      </div>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">البحث والتصفية</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3 md:grid-cols-3">
          <div className="relative">
            <Search className="absolute right-3 top-3 h-4 w-4 text-muted-foreground" />
            <Input
              className="pr-9"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="اسم، ID، وكالة أو رقم عملية"
            />
          </div>
          <Select value={category} onValueChange={setCategory}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">كل أنواع العمليات</SelectItem>
              {Object.entries(LABELS).map(([k, v]) => (
                <SelectItem key={k} value={k}>
                  {v}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={asset} onValueChange={setAsset}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">كل الأرصدة</SelectItem>
              <SelectItem value="coins">كوينز</SelectItem>
              <SelectItem value="pearls">لؤلؤ</SelectItem>
              <SelectItem value="USDT">USDT</SelectItem>
            </SelectContent>
          </Select>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-0">
          {log.isLoading ? (
            <div className="py-20">
              <Loader2 className="mx-auto animate-spin" />
            </div>
          ) : log.isError ? (
            <div className="py-20 text-center text-destructive">{(log.error as Error).message}</div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>التاريخ</TableHead>
                    <TableHead>العملية</TableHead>
                    <TableHead>المرسل/الحساب</TableHead>
                    <TableHead>المستلم</TableHead>
                    <TableHead>الوكالة</TableHead>
                    <TableHead>الرصيد</TableHead>
                    <TableHead>القيمة</TableHead>
                    <TableHead>الاتجاه</TableHead>
                    <TableHead>الحالة</TableHead>
                    <TableHead>المرجع</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell className="whitespace-nowrap text-xs">
                        {fmtDate(r.occurred_at)}
                      </TableCell>
                      <TableCell>
                        <b>{LABELS[r.category] ?? r.category}</b>
                        <div className="max-w-52 truncate text-xs text-muted-foreground">
                          {r.description}
                        </div>
                      </TableCell>
                      <TableCell>
                        <PersonCell p={r.actor} />
                      </TableCell>
                      <TableCell>
                        <PersonCell p={r.counterparty} />
                      </TableCell>
                      <TableCell>
                        {r.agency?.name ?? "-"}
                        <div className="font-mono text-xs" dir="ltr">
                          {r.agency?.display_id}
                        </div>
                      </TableCell>
                      <TableCell>{r.asset}</TableCell>
                      <TableCell className="font-mono font-bold" dir="ltr">
                        {fmtNum(r.amount)}
                      </TableCell>
                      <TableCell>
                        <Badge variant="secondary">{r.direction}</Badge>
                      </TableCell>
                      <TableCell>
                        <Badge>{r.status}</Badge>
                      </TableCell>
                      <TableCell className="max-w-40 truncate font-mono text-xs" dir="ltr">
                        {r.reference ?? r.source_row_id}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
function PersonCell({ p }: { p: Person | null | undefined }) {
  if (!p) return <span>-</span>;
  return (
    <div className="flex min-w-40 items-center gap-2">
      <Avatar className="h-8 w-8">
        <AvatarImage src={p.avatar_url ?? undefined} />
        <AvatarFallback>{p.display_name?.slice(0, 1) ?? "?"}</AvatarFallback>
      </Avatar>
      <div>
        <div className="text-sm">{p.display_name ?? "مستخدم"}</div>
        <div className="font-mono text-xs text-muted-foreground" dir="ltr">
          {p.legacy_id}
        </div>
      </div>
    </div>
  );
}
