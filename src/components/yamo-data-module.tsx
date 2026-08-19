import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Search, RefreshCw, Database, Loader2, ShieldCheck, ChevronLeft, ChevronRight,
  ImageOff, SlidersHorizontal, MoreHorizontal,
  Download,
} from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { readableValue, yamoRows, yamoRpc } from "@/lib/yamo-admin";
import { formatInteger } from "@/lib/format";

export type YamoModuleAction = {
  label: string;
  rpc: string;
  buildArgs: (row: Record<string, unknown>) => Record<string, unknown>;
  tone?: "default" | "destructive" | "outline";
  prompts?: { key: string; message: string; required?: boolean }[];
};

type ModuleColumn = {
  key: string;
  label: string;
  kind?: "text" | "image" | "status" | "number";
};

type Props = {
  title: string;
  description: string;
  source: string;
  columns: ModuleColumn[];
  actions?: YamoModuleAction[];
  emptyText?: string;
};

export function YamoDataModule({
  title,
  description,
  source,
  columns,
  actions = [],
  emptyText,
}: Props) {
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const pageSize = 20;
  const client = useQueryClient();
  const rows = useQuery({
    queryKey: ["yamo-admin", source],
    queryFn: () => yamoRows(source),
  });
  const action = useMutation({
    mutationFn: async ({ item, row }: { item: YamoModuleAction; row: Record<string, unknown> }) =>
      yamoRpc(item.rpc, item.buildArgs(row)),
    onSuccess: async () => {
      toast.success("تم تنفيذ الإجراء وتسجيله في سجل العمليات");
      await client.invalidateQueries({ queryKey: ["yamo-admin", source] });
    },
    onError: (error: Error) => toast.error(error.message),
  });
  const filtered = useMemo(() => {
    const needle = query.trim().toLocaleLowerCase("ar");
    if (!needle) return rows.data ?? [];
    return (rows.data ?? []).filter((row) =>
      columns.some(({ key }) => readableValue(row[key]).toLocaleLowerCase("ar").includes(needle)),
    );
  }, [columns, query, rows.data]);
  const pageCount = Math.max(1, Math.ceil(filtered.length / pageSize));
  const visibleRows = filtered.slice((page - 1) * pageSize, page * pageSize);

  const updateQuery = (value: string) => {
    setQuery(value);
    setPage(1);
  };

  const exportCsv = () => {
    const escape = (value: unknown) => `"${readableValue(value).replaceAll('"', '""')}"`;
    const csv = [
      columns.map((column) => escape(column.label)).join(","),
      ...filtered.map((row) => columns.map((column) => escape(row[column.key])).join(",")),
    ].join("\n");
    const blob = new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${source}-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-4 rounded-3xl border bg-card/70 p-5 shadow-sm backdrop-blur-xl">
        <div>
          <h1 className="text-2xl font-black tracking-tight md:text-3xl">{title}</h1>
          <p className="mt-1 text-sm text-muted-foreground">{description}</p>
        </div>
        <Badge variant="outline" className="gap-2 rounded-xl bg-emerald-500/5 px-3 py-2 text-emerald-600 dark:text-emerald-400">
          <span className="h-2 w-2 animate-pulse rounded-full bg-emerald-500" /> بيانات مباشرة
        </Badge>
      </div>
      <Card className="overflow-hidden border-border/70 bg-card/90 backdrop-blur-xl">
        <CardHeader className="gap-3 pb-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <CardTitle className="flex items-center gap-2 text-base">
                <Database className="h-4 w-4 text-violet-500" /> السجلات
              </CardTitle>
              <CardDescription>{formatInteger(filtered.length)} نتيجة</CardDescription>
            </div>
            <div className="flex gap-2">
              <div className="relative">
                <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  value={query}
                  onChange={(e) => updateQuery(e.target.value)}
                  placeholder="بحث بالاسم أو ID أو الحالة…"
                  className="w-72 rounded-xl bg-background/70 pr-9"
                />
              </div>
              <Button variant="outline" size="icon" className="rounded-xl" aria-label="الفلاتر">
                <SlidersHorizontal className="h-4 w-4" />
              </Button>
              <Button variant="outline" size="icon" className="rounded-xl" aria-label="تصدير CSV" onClick={exportCsv} disabled={filtered.length === 0}>
                <Download className="h-4 w-4" />
              </Button>
              <Button
                variant="outline"
                size="icon"
                onClick={() => rows.refetch()}
                className="rounded-xl"
                aria-label="تحديث البيانات"
              >
                <RefreshCw className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {rows.isLoading ? (
            <div className="grid h-40 place-items-center">
              <Loader2 className="h-6 w-6 animate-spin" />
            </div>
          ) : rows.error ? (
            <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-5 text-sm text-destructive">
              تعذر قراءة {source}: {(rows.error as Error).message}
            </div>
          ) : filtered.length === 0 ? (
            <div className="grid h-40 place-items-center text-sm text-muted-foreground">
              {emptyText ?? "لا توجد بيانات حتى الآن"}
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  {columns.map((c) => (
                    <TableHead key={c.key}>{c.label}</TableHead>
                  ))}
                  {actions.length > 0 && <TableHead>الإجراءات</TableHead>}
                </TableRow>
              </TableHeader>
              <TableBody>
                {visibleRows.map((row, index) => (
                  <TableRow key={String(row.id ?? row.user_id ?? index)}>
                    {columns.map((c) => (
                      <TableCell key={c.key} className="max-w-80">
                        <SmartCell column={c} value={row[c.key]} row={row} />
                      </TableCell>
                    ))}
                    {actions.length > 0 && (
                      <TableCell>
                        <div className="flex flex-wrap gap-1">
                          {actions.map((item) => (
                            <Button
                              key={item.rpc}
                              size="sm"
                              variant={item.tone ?? "outline"}
                              className="rounded-xl"
                              disabled={action.isPending}
                              onClick={() => {
                                if (
                                  item.tone === "destructive" &&
                                  !window.confirm(
                                    "هذا إجراء مؤثر وقد لا يمكن التراجع عنه. هل تريد المتابعة؟",
                                  )
                                )
                                  return;
                                const extra: Record<string, unknown> = {};
                                for (const field of item.prompts ?? []) {
                                  const value = window.prompt(field.message);
                                  if (value === null) return;
                                  if (field.required && !value.trim()) {
                                    toast.error("هذا البيان مطلوب لإتمام الإجراء");
                                    return;
                                  }
                                  extra[field.key] = value.trim() || null;
                                }
                                action.mutate({
                                  item: {
                                    ...item,
                                    buildArgs: (current) => ({
                                      ...item.buildArgs(current),
                                      ...extra,
                                    }),
                                  },
                                  row,
                                });
                              }}
                            >
                              <ShieldCheck className="ml-1 h-3.5 w-3.5" />
                              {item.label}
                            </Button>
                          ))}
                        </div>
                      </TableCell>
                    )}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
        {!rows.isLoading && !rows.error && filtered.length > 0 && (
          <div className="flex flex-wrap items-center justify-between gap-3 border-t bg-muted/20 px-5 py-3 text-xs text-muted-foreground">
            <span>
              عرض {formatInteger((page - 1) * pageSize + 1)}–{formatInteger(Math.min(page * pageSize, filtered.length))} من {formatInteger(filtered.length)}
            </span>
            <div className="flex items-center gap-2">
              <Button variant="outline" size="icon" className="h-8 w-8 rounded-lg" disabled={page === 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>
                <ChevronRight className="h-4 w-4" />
              </Button>
              <span className="min-w-20 text-center text-foreground">{formatInteger(page)} / {formatInteger(pageCount)}</span>
              <Button variant="outline" size="icon" className="h-8 w-8 rounded-lg" disabled={page === pageCount} onClick={() => setPage((p) => Math.min(pageCount, p + 1))}>
                <ChevronLeft className="h-4 w-4" />
              </Button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}

function SmartCell({ column, value, row }: { column: ModuleColumn; value: unknown; row: Record<string, unknown> }) {
  const text = readableValue(value);
  const key = column.key.toLowerCase();
  const looksLikeImage = column.kind === "image" || /(avatar|image|cover|banner|preview|icon|photo|media_url)/.test(key);
  const url = typeof value === "string" && /^https?:\/\//.test(value) ? value : null;

  if (looksLikeImage) {
    return url ? (
      <div className="flex items-center gap-3">
        <img src={url} alt={column.label} loading="lazy" className="h-11 w-11 rounded-xl border bg-muted object-cover shadow-sm" />
        <span className="max-w-44 truncate text-xs text-muted-foreground" dir="ltr">{url.split("/").pop()}</span>
      </div>
    ) : (
      <div className="grid h-11 w-11 place-items-center rounded-xl border border-dashed bg-muted/50 text-muted-foreground">
        <ImageOff className="h-4 w-4" />
      </div>
    );
  }

  if (column.kind === "status" || /(status|active|enabled|verified)$/.test(key)) {
    const positive = value === true || /^(active|enabled|approved|completed|verified|online|true)$/i.test(String(value));
    const negative = value === false || /^(blocked|disabled|rejected|failed|banned|false)$/i.test(String(value));
    return <Badge variant="outline" className={`rounded-lg ${positive ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600" : negative ? "border-red-500/30 bg-red-500/10 text-red-600" : "border-orange-500/30 bg-orange-500/10 text-orange-600"}`}>{text}</Badge>;
  }

  if (column.kind === "number" || typeof value === "number") {
    return <span className="font-semibold tabular-nums" dir="ltr">{text}</span>;
  }

  const identity = key === "display_name" || key === "name" || key === "title";
  return (
    <div className="flex min-w-0 items-center gap-2">
      {identity && <MoreHorizontal className="h-4 w-4 shrink-0 text-violet-500" />}
      <span className="block truncate" title={text}>{text}</span>
    </div>
  );
}
