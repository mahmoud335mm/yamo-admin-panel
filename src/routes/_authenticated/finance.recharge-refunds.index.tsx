import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useState, useEffect } from "react";
import { PermissionGuard } from "@/components/permission-guard";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { RefreshCw, Search, Eye, ChevronRight, ChevronLeft, Undo2, AlertTriangle } from "lucide-react";
import { fmtDate } from "@/lib/charging-utils";
import { listRechargeRefunds, listRefundStats, getRefundFeatureFlags } from "@/lib/refunds/refunds.functions";

export const Route = createFileRoute("/_authenticated/finance/recharge-refunds/")({
  component: () => (
    <PermissionGuard permission="recharge_refunds.read">
      <RefundsListPage />
    </PermissionGuard>
  ),
});

const STATUS: Record<string, { label: string; cls: string }> = {
  requested: { label: "مطلوب", cls: "bg-muted text-muted-foreground" },
  pending_review: { label: "بانتظار المراجعة", cls: "bg-amber-500/15 text-amber-600" },
  pending_second_review: { label: "بانتظار مراجعة ثانية", cls: "bg-amber-500/15 text-amber-600" },
  approved: { label: "معتمد", cls: "bg-blue-500/15 text-blue-500" },
  processing_gateway: { label: "قيد المعالجة", cls: "bg-blue-500/15 text-blue-500" },
  gateway_confirmed: { label: "أكدته البوابة", cls: "bg-blue-500/15 text-blue-500" },
  reversing_wallet: { label: "عكس المحفظة", cls: "bg-blue-500/15 text-blue-500" },
  manual_review: { label: "مراجعة يدوية", cls: "bg-orange-500/15 text-orange-500" },
  completed: { label: "مكتمل", cls: "bg-emerald-500/15 text-emerald-600" },
  partially_completed: { label: "مكتمل جزئي", cls: "bg-emerald-500/15 text-emerald-600" },
  failed: { label: "فشل", cls: "bg-destructive/15 text-destructive" },
  rejected: { label: "مرفوض", cls: "bg-destructive/15 text-destructive" },
  cancelled: { label: "ملغى", cls: "bg-muted text-muted-foreground" },
};

function useDebounced<T>(v: T, ms = 350) {
  const [d, setD] = useState(v);
  useEffect(() => { const t = setTimeout(() => setD(v), ms); return () => clearTimeout(t); }, [v, ms]);
  return d;
}

function RefundsListPage() {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<string>("all");
  const [type, setType] = useState<string>("all");
  const [mode, setMode] = useState<string>("all");
  const [manualOnly, setManualOnly] = useState(false);
  const [page, setPage] = useState(1);
  const dSearch = useDebounced(search);
  const list = useServerFn(listRechargeRefunds);
  const stats = useServerFn(listRefundStats);
  const flagsFn = useServerFn(getRefundFeatureFlags);

  const flagsQ = useQuery({ queryKey: ["refund_flags"], queryFn: () => flagsFn(), staleTime: 30_000 });
  const statsQ = useQuery({ queryKey: ["refund_stats"], queryFn: () => stats(), staleTime: 15_000 });
  const listQ = useQuery({
    queryKey: ["refunds", { dSearch, status, type, mode, manualOnly, page }],
    queryFn: () => list({
      data: {
        page, page_size: 25,
        search: dSearch || undefined,
        status: status !== "all" ? [status] : undefined,
        refund_type: type !== "all" ? [type as "full" | "partial"] : undefined,
        gateway_mode: mode !== "all" ? [mode as "test" | "live"] : undefined,
        manual_review_only: manualOnly || undefined,
      },
    }),
    placeholderData: (prev) => prev,
  });

  const result = listQ.data;
  const rows = result?.success ? result.data.rows : [];
  const total = result?.success ? result.data.total : 0;
  const pages = Math.max(1, Math.ceil(total / 25));

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Undo2 className="h-6 w-6" /> استرداد الشحن
          </h1>
          <p className="text-sm text-muted-foreground">
            متابعة كل طلب استرداد فردي: من المعاينة إلى التنفيذ وعكس المحفظة.
          </p>
        </div>
        <Button variant="outline" onClick={() => { listQ.refetch(); statsQ.refetch(); }}>
          <RefreshCw className="ml-1 h-3.5 w-3.5" /> تحديث
        </Button>
      </div>

      {flagsQ.data && !flagsQ.data.execution && (
        <div className="flex items-center gap-2 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-amber-700 dark:text-amber-400">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          تنفيذ الاسترداد معطل حالياً (enable_refund_execution=false). الإجراءات الحرجة ستُرفض حتى يُفعّله سوبر أدمن.
        </div>
      )}

      {statsQ.data?.success && (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
          <KPI label="الإجمالي" value={statsQ.data.data.total} />
          <KPI label="بانتظار مراجعة" value={(statsQ.data.data.by_status.pending_review ?? 0) + (statsQ.data.data.by_status.pending_second_review ?? 0)} />
          <KPI label="مراجعة يدوية" value={statsQ.data.data.by_status.manual_review ?? 0} />
          <KPI label="قيد المعالجة" value={(statsQ.data.data.by_status.processing_gateway ?? 0) + (statsQ.data.data.by_status.reversing_wallet ?? 0)} />
          <KPI label="مكتمل" value={(statsQ.data.data.by_status.completed ?? 0) + (statsQ.data.data.by_status.partially_completed ?? 0)} />
        </div>
      )}

      <Card>
        <CardHeader>
          <div className="grid gap-2 md:grid-cols-5">
            <div className="relative md:col-span-2">
              <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }}
                     placeholder="Refund Ref أو Provider Ref…" className="pr-9" />
            </div>
            <Select value={status} onValueChange={(v) => { setStatus(v); setPage(1); }}>
              <SelectTrigger><SelectValue placeholder="الحالة" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">كل الحالات</SelectItem>
                {Object.entries(STATUS).map(([k, v]) => <SelectItem key={k} value={k}>{v.label}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={type} onValueChange={(v) => { setType(v); setPage(1); }}>
              <SelectTrigger><SelectValue placeholder="النوع" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">كل الأنواع</SelectItem>
                <SelectItem value="full">كامل</SelectItem>
                <SelectItem value="partial">جزئي</SelectItem>
              </SelectContent>
            </Select>
            <Select value={mode} onValueChange={(v) => { setMode(v); setPage(1); }}>
              <SelectTrigger><SelectValue placeholder="Mode" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Test + Live</SelectItem>
                <SelectItem value="live">Live فقط</SelectItem>
                <SelectItem value="test">Test فقط</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="flex items-center gap-2 pt-2">
            <label className="text-xs flex items-center gap-1 cursor-pointer">
              <input type="checkbox" checked={manualOnly} onChange={(e) => { setManualOnly(e.target.checked); setPage(1); }} />
              مراجعة يدوية فقط
            </label>
          </div>
        </CardHeader>
        <CardContent>
          {listQ.isLoading ? <Skeleton className="h-64" />
            : result && !result.success ? <div className="text-center py-10 text-destructive">{result.safe_message}</div>
            : rows.length === 0 ? <div className="text-center py-10 text-muted-foreground">لا توجد استردادات مطابقة.</div>
            : <>
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Refund Ref</TableHead>
                      <TableHead>النوع</TableHead>
                      <TableHead>المبلغ</TableHead>
                      <TableHead>الحالة</TableHead>
                      <TableHead>Two-Eyes</TableHead>
                      <TableHead>Mode</TableHead>
                      <TableHead>عكس/غير مسترد</TableHead>
                      <TableHead>التاريخ</TableHead>
                      <TableHead />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((r) => {
                      const sl = STATUS[r.status] ?? { label: r.status, cls: "bg-muted" };
                      return (
                        <TableRow key={r.id}>
                          <TableCell className="font-mono text-xs">{r.refund_reference}</TableCell>
                          <TableCell><Badge variant="outline">{r.refund_type}</Badge></TableCell>
                          <TableCell>{Number(r.approved_amount ?? r.requested_amount ?? 0).toFixed(2)} {r.currency_code}</TableCell>
                          <TableCell><Badge className={sl.cls}>{sl.label}</Badge></TableCell>
                          <TableCell>{r.requires_second_approval ? <Badge variant="destructive">مطلوب</Badge> : <span className="text-xs text-muted-foreground">—</span>}</TableCell>
                          <TableCell><Badge variant={r.gateway_mode === "test" ? "outline" : "secondary"}>{r.gateway_mode ?? "—"}</Badge></TableCell>
                          <TableCell className="text-xs">
                            {Number(r.coins_actually_reversed ?? 0)} / {Number(r.unrecovered_coin_amount ?? 0)}
                          </TableCell>
                          <TableCell className="text-xs">{fmtDate(r.created_at)}</TableCell>
                          <TableCell>
                            <Link to="/finance/recharge-refunds/$id" params={{ id: r.id }}>
                              <Button size="sm" variant="ghost"><Eye className="h-4 w-4" /></Button>
                            </Link>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </div>
              <div className="flex items-center justify-between pt-3 text-xs text-muted-foreground">
                <div>إجمالي {total} — صفحة {page} من {pages}</div>
                <div className="flex gap-1">
                  <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
                    <ChevronRight className="h-4 w-4" /> السابق
                  </Button>
                  <Button size="sm" variant="outline" disabled={page >= pages} onClick={() => setPage((p) => p + 1)}>
                    التالي <ChevronLeft className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </>}
        </CardContent>
      </Card>
    </div>
  );
}

function KPI({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="text-xs text-muted-foreground">{label}</div>
        <div className="text-2xl font-bold mt-1">{value}</div>
      </CardContent>
    </Card>
  );
}
