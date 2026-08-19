import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Search, RefreshCw, Database, Loader2, ShieldCheck } from "lucide-react";
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

export type YamoModuleAction = {
  label: string;
  rpc: string;
  buildArgs: (row: Record<string, unknown>) => Record<string, unknown>;
  tone?: "default" | "destructive" | "outline";
  prompts?: { key: string; message: string; required?: boolean }[];
};

type Props = {
  title: string;
  description: string;
  source: string;
  columns: { key: string; label: string }[];
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

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black">{title}</h1>
          <p className="mt-1 text-sm text-muted-foreground">{description}</p>
        </div>
        <Badge variant="outline" className="gap-1">
          <Database className="h-3.5 w-3.5" /> بيانات Yamo المباشرة
        </Badge>
      </div>
      <Card>
        <CardHeader className="gap-3 pb-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <CardTitle className="text-base">السجلات</CardTitle>
              <CardDescription>{filtered.length} نتيجة</CardDescription>
            </div>
            <div className="flex gap-2">
              <div className="relative">
                <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="بحث…"
                  className="w-64 pr-9"
                />
              </div>
              <Button
                variant="outline"
                size="icon"
                onClick={() => rows.refetch()}
                aria-label="تحديث"
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
                {filtered.map((row, index) => (
                  <TableRow key={String(row.id ?? row.user_id ?? index)}>
                    {columns.map((c) => (
                      <TableCell key={c.key} className="max-w-72 truncate">
                        {readableValue(row[c.key])}
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
      </Card>
    </div>
  );
}
