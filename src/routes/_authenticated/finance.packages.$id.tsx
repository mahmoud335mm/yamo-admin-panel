import { createFileRoute, Link, useParams } from "@tanstack/react-router";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { toast } from "sonner";
import { ArrowRight, PlayCircle, PauseCircle, Archive, Copy, RotateCcw, AlertCircle } from "lucide-react";
import { fmtNum, fmtDate } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/finance/packages/$id")({
  component: PackageDetail,
});

const PKG_STATUS: Record<string, { label: string; color: string }> = {
  draft: { label: "مسودة", color: "bg-muted" },
  review: { label: "مراجعة", color: "bg-blue-500/15 text-blue-500" },
  published: { label: "منشورة", color: "bg-emerald-500/15 text-emerald-500" },
  paused: { label: "موقوفة", color: "bg-orange-500/15 text-orange-500" },
  expired: { label: "منتهية", color: "bg-muted" },
  archived: { label: "مؤرشفة", color: "bg-destructive/15 text-destructive" },
};

function PackageDetail() {
  const { id } = useParams({ from: "/_authenticated/finance/packages/$id" });
  const { has } = usePermissions();
  const qc = useQueryClient();

  const pkg = useQuery({
    queryKey: ["recharge_packages", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("recharge_packages").select("*").eq("id", id).maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const prices = useQuery({
    queryKey: ["recharge_package_prices", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("recharge_package_prices").select("*").eq("package_id", id).order("created_at");
      if (error) throw error;
      return data;
    },
  });

  const bonuses = useQuery({
    queryKey: ["recharge_package_bonuses", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("recharge_package_bonuses").select("*").eq("package_id", id).order("created_at");
      if (error) throw error;
      return data;
    },
  });

  const targets = useQuery({
    queryKey: ["recharge_package_targets", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("recharge_package_targets").select("*").eq("package_id", id).order("created_at");
      if (error) throw error;
      return data;
    },
  });

  const versions = useQuery({
    queryKey: ["recharge_package_versions", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("recharge_package_versions").select("*").eq("package_id", id).order("version", { ascending: false });
      if (error) throw error;
      return data;
    },
  });

  const stats = useQuery({
    queryKey: ["recharge_package_stats", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("recharge_package_stats").select("*").eq("package_id", id).order("stat_date", { ascending: false }).limit(30);
      if (error) throw error;
      return data;
    },
  });

  const invalidate = () => qc.invalidateQueries({ queryKey: ["recharge_packages"] });

  const publish  = useMutation({ mutationFn: async () => { const { error } = await supabase.rpc("publish_recharge_package", { _id: id }); if (error) throw error; }, onSuccess: () => { toast.success("تم النشر"); invalidate(); }, onError: (e: Error) => toast.error(e.message) });
  const dup      = useMutation({ mutationFn: async () => { const { data, error } = await supabase.rpc("duplicate_recharge_package", { _id: id }); if (error) throw error; return data as string; }, onSuccess: (newId) => toast.success(`تم النسخ (${String(newId).slice(0, 8)})`), onError: (e: Error) => toast.error(e.message) });

  const [pauseReason, setPauseReason] = useState("");
  const [archiveReason, setArchiveReason] = useState("");
  const [rollbackVersion, setRollbackVersion] = useState<number | null>(null);

  const pause = useMutation({
    mutationFn: async () => { const { error } = await supabase.rpc("pause_recharge_package", { _id: id, _reason: pauseReason }); if (error) throw error; },
    onSuccess: () => { toast.success("تم الإيقاف"); invalidate(); setPauseReason(""); }, onError: (e: Error) => toast.error(e.message),
  });
  const archive = useMutation({
    mutationFn: async () => { const { error } = await supabase.rpc("archive_recharge_package", { _id: id, _reason: archiveReason }); if (error) throw error; },
    onSuccess: () => { toast.success("تمت الأرشفة"); invalidate(); setArchiveReason(""); }, onError: (e: Error) => toast.error(e.message),
  });
  const rollback = useMutation({
    mutationFn: async () => { if (rollbackVersion == null) throw new Error("اختر إصدارًا"); const { error } = await supabase.rpc("rollback_recharge_package", { _id: id, _to_version: rollbackVersion }); if (error) throw error; },
    onSuccess: () => { toast.success("تمت العودة للنسخة"); invalidate(); setRollbackVersion(null); }, onError: (e: Error) => toast.error(e.message),
  });

  if (pkg.isLoading) return <Skeleton className="h-64" />;
  if (pkg.isError) return <Card className="border-destructive"><CardContent className="p-4 text-sm text-destructive flex items-center gap-2"><AlertCircle className="h-4 w-4" /> {(pkg.error as Error).message}</CardContent></Card>;
  if (!pkg.data) return <Card><CardContent className="p-8 text-center text-sm text-muted-foreground">الباقة غير موجودة.</CardContent></Card>;

  const p = pkg.data;
  const status = PKG_STATUS[p.status] ?? { label: p.status, color: "bg-muted" };
  const canPublish = has("recharge_packages.publish") && (p.status === "draft" || p.status === "review" || p.status === "paused");
  const canPause = has("recharge_packages.publish") && p.status === "published";
  const canArchive = has("recharge_packages.archive") && p.status !== "archived";
  const canRollback = has("recharge_packages.publish") && (versions.data?.length ?? 0) > 0;

  return (
    <div className="space-y-4">
      <Link to="/finance/packages" className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
        <ArrowRight className="h-3 w-3" /> عودة إلى الباقات
      </Link>

      <Card>
        <CardHeader className="flex flex-row flex-wrap items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <CardTitle>{p.name_ar}</CardTitle>
              <Badge className={`${status.color} border-0`}>{status.label}</Badge>
              <Badge variant="outline" className="text-[10px]">v{p.version}</Badge>
            </div>
            <p className="text-xs text-muted-foreground font-mono">{p.code} · {p.name_en}</p>
            <p className="text-sm mt-2">
              <span className="text-muted-foreground">إجمالي: </span>
              <span className="font-bold">{fmtNum(p.total_coins)}</span> كوينز
              <span className="text-muted-foreground"> ({fmtNum(p.base_coins)} + {fmtNum(p.bonus_coins)} Bonus)</span>
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            {canPublish && <Button size="sm" onClick={() => publish.mutate()} disabled={publish.isPending}><PlayCircle className="ml-1 h-4 w-4" /> نشر</Button>}
            {canPause && (
              <AlertDialog>
                <AlertDialogTrigger asChild><Button size="sm" variant="outline"><PauseCircle className="ml-1 h-4 w-4" /> إيقاف</Button></AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader><AlertDialogTitle>إيقاف الباقة</AlertDialogTitle><AlertDialogDescription>لن تظهر للمستخدمين حتى يُعاد نشرها.</AlertDialogDescription></AlertDialogHeader>
                  <div className="grid gap-1"><Label>السبب (إلزامي)</Label><Textarea value={pauseReason} onChange={(e) => setPauseReason(e.target.value)} /></div>
                  <AlertDialogFooter><AlertDialogCancel>إلغاء</AlertDialogCancel><AlertDialogAction disabled={pauseReason.length < 5 || pause.isPending} onClick={() => pause.mutate()}>تأكيد</AlertDialogAction></AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            )}
            {has("recharge_packages.create") && <Button size="sm" variant="outline" onClick={() => dup.mutate()} disabled={dup.isPending}><Copy className="ml-1 h-4 w-4" /> نسخ</Button>}
            {canArchive && (
              <AlertDialog>
                <AlertDialogTrigger asChild><Button size="sm" variant="destructive"><Archive className="ml-1 h-4 w-4" /> أرشفة</Button></AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader><AlertDialogTitle>أرشفة الباقة</AlertDialogTitle><AlertDialogDescription>هذا الإجراء يُخرج الباقة من التطبيق نهائيًا.</AlertDialogDescription></AlertDialogHeader>
                  <div className="grid gap-1"><Label>السبب (إلزامي)</Label><Textarea value={archiveReason} onChange={(e) => setArchiveReason(e.target.value)} /></div>
                  <AlertDialogFooter><AlertDialogCancel>إلغاء</AlertDialogCancel><AlertDialogAction disabled={archiveReason.length < 5 || archive.isPending} onClick={() => archive.mutate()}>أرشف</AlertDialogAction></AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            )}
          </div>
        </CardHeader>
      </Card>

      <Tabs defaultValue="prices">
        <TabsList>
          <TabsTrigger value="prices">الأسعار ({prices.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="bonuses">Bonuses ({bonuses.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="targets">الاستهداف ({targets.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="stats">إحصاءات</TabsTrigger>
          <TabsTrigger value="versions">الإصدارات ({versions.data?.length ?? 0})</TabsTrigger>
        </TabsList>

        <TabsContent value="prices">
          <Card><CardContent className="p-0">
            {(prices.data?.length ?? 0) === 0 && <p className="p-6 text-sm text-muted-foreground text-center">لم تُضف أسعار بعد. أضف صفوفًا في جدول <code>recharge_package_prices</code> عبر SQL أو أداة الأسعار الموحّدة.</p>}
            {prices.data?.map((r) => (
              <div key={r.id} className="flex items-center justify-between border-b p-3 text-sm last:border-b-0">
                <span>{r.country_code ?? "كل الدول"} · {r.currency_code}</span>
                <span className="font-bold">{fmtNum(Number(r.price))} {r.currency_code}</span>
                <Badge variant={r.active ? "default" : "outline"}>{r.active ? "نشط" : "معطّل"}</Badge>
              </div>
            ))}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="bonuses">
          <Card><CardContent className="p-4 text-sm text-muted-foreground">
            {(bonuses.data?.length ?? 0) === 0 ? "لا Bonuses موسمية." : <pre className="text-xs overflow-auto">{JSON.stringify(bonuses.data, null, 2)}</pre>}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="targets">
          <Card><CardContent className="p-4 text-sm text-muted-foreground">
            {(targets.data?.length ?? 0) === 0 ? "الباقة متاحة لجميع الجماهير (لا استهداف)." : <pre className="text-xs overflow-auto">{JSON.stringify(targets.data, null, 2)}</pre>}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="stats">
          <Card><CardContent className="p-0">
            {(stats.data?.length ?? 0) === 0 && <p className="p-6 text-sm text-muted-foreground text-center">لا إحصاءات بعد.</p>}
            {stats.data?.map((s) => (
              <div key={s.id} className="grid grid-cols-4 gap-2 border-b p-3 text-sm last:border-b-0">
                <span>{s.stat_date}</span>
                <span>مشاهدات: <b>{fmtNum(s.views_count)}</b></span>
                <span>مشتريات: <b>{fmtNum(s.purchases_count)}</b></span>
                <span>إيراد: <b>{fmtNum(Math.round(Number(s.revenue_amount)))}</b></span>
              </div>
            ))}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="versions">
          <Card><CardContent className="p-0">
            {(versions.data?.length ?? 0) === 0 && <p className="p-6 text-sm text-muted-foreground text-center">لا إصدارات محفوظة.</p>}
            {versions.data?.map((v) => (
              <div key={v.id} className="flex items-center justify-between border-b p-3 text-sm last:border-b-0">
                <div>
                  <div className="font-medium">v{v.version}</div>
                  <div className="text-[11px] text-muted-foreground">{fmtDate(v.created_at)}</div>
                </div>
                {canRollback && p.version !== v.version && (
                  <AlertDialog>
                    <AlertDialogTrigger asChild><Button size="sm" variant="outline" onClick={() => setRollbackVersion(v.version)}><RotateCcw className="ml-1 h-3 w-3" /> استرجاع</Button></AlertDialogTrigger>
                    <AlertDialogContent>
                      <AlertDialogHeader><AlertDialogTitle>الرجوع إلى الإصدار v{v.version}</AlertDialogTitle>
                        <AlertDialogDescription>سيتم استبدال الحالة الحالية بمحتوى هذا الإصدار مع تسجيل الحدث في Audit Log.</AlertDialogDescription>
                      </AlertDialogHeader>
                      <AlertDialogFooter><AlertDialogCancel>إلغاء</AlertDialogCancel><AlertDialogAction disabled={rollback.isPending} onClick={() => rollback.mutate()}>تأكيد</AlertDialogAction></AlertDialogFooter>
                    </AlertDialogContent>
                  </AlertDialog>
                )}
              </div>
            ))}
          </CardContent></Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
