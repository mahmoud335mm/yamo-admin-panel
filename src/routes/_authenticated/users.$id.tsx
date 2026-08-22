import { createFileRoute, Link } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Loader2, ArrowRight, Ban, ShieldCheck, Trash2, RotateCcw, LogOut, MessageSquareOff } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { usePermissions } from "@/hooks/use-permissions";

export const Route = createFileRoute("/_authenticated/users/$id")({
  component: () => <PermissionGuard permission="users.read"><UserDetail /></PermissionGuard>,
});

type Action =
  | { kind: "ban_perm" } | { kind: "ban_temp" } | { kind: "unban" }
  | { kind: "verify" } | { kind: "unverify" }
  | { kind: "level"; current: number } | { kind: "vip"; current: number } | { kind: "gender"; current: string }
  | { kind: "comm"; channel: "message"|"call"|"room"|"post"; banned: boolean }
  | { kind: "sessions" } | { kind: "soft_delete" } | { kind: "restore" };

function UserDetail() {
  const { id } = Route.useParams();
  const qc = useQueryClient();
  const { has } = usePermissions();
  const [action, setAction] = useState<Action | null>(null);
  const [reason, setReason] = useState("");
  const [numValue, setNumValue] = useState<number>(0);
  const [strValue, setStrValue] = useState<string>("");
  const [untilDays, setUntilDays] = useState<number>(7);

  const u = useQuery({
    queryKey: ["user", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("profiles")
        .select("*, wallets(*), user_devices(*), user_penalties(*), transactions(*)")
        .eq("id", id).maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const ledger = useQuery({
    queryKey: ["user", id, "ledger"],
    queryFn: async () => (await supabase.from("wallet_ledger").select("*").eq("user_id", id).order("created_at", { ascending: false }).limit(50)).data ?? [],
  });

  const history = useQuery({
    queryKey: ["user", id, "history"],
    queryFn: async () => (await supabase.from("user_edit_history").select("*").eq("user_id", id).order("created_at", { ascending: false }).limit(50)).data ?? [],
  });

  const runRpc = useMutation({
    mutationFn: async () => {
      if (!action) throw new Error("no action");
      const needsReason = ["ban_perm","ban_temp","unban","level","vip","gender","comm","sessions","soft_delete","restore"].includes(action.kind);
      if (needsReason && reason.trim().length < 5) throw new Error("السبب مطلوب (5 أحرف على الأقل)");
      switch (action.kind) {
        case "ban_perm": { const { error } = await supabase.rpc("admin_ban_user", { _user_id: id, _reason: reason }); if (error) throw error; break; }
        case "ban_temp": {
          const until = new Date(Date.now() + untilDays * 86400000).toISOString();
          const { error } = await supabase.rpc("admin_ban_user", { _user_id: id, _reason: reason, _until: until }); if (error) throw error; break;
        }
        case "unban":     { const { error } = await supabase.rpc("admin_unban_user", { _user_id: id, _reason: reason }); if (error) throw error; break; }
        case "verify":    { const { error } = await supabase.rpc("admin_verify_user", { _user_id: id, _verified: true, _reason: reason || undefined }); if (error) throw error; break; }
        case "unverify":  { const { error } = await supabase.rpc("admin_verify_user", { _user_id: id, _verified: false, _reason: reason || undefined }); if (error) throw error; break; }
        case "level":     { const { error } = await supabase.rpc("admin_update_level", { _user_id: id, _level: numValue, _reason: reason }); if (error) throw error; break; }
        case "vip":       { const { error } = await supabase.rpc("admin_update_vip", { _user_id: id, _vip: numValue, _reason: reason }); if (error) throw error; break; }
        case "gender":    { const { error } = await supabase.rpc("admin_update_gender", { _user_id: id, _gender: strValue, _reason: reason }); if (error) throw error; break; }
        case "comm":      { const { error } = await supabase.rpc("admin_toggle_comm_ban", { _user_id: id, _channel: action.channel, _banned: !action.banned, _reason: reason }); if (error) throw error; break; }
        case "sessions":  { const { error } = await supabase.rpc("admin_terminate_sessions", { _user_id: id, _reason: reason }); if (error) throw error; break; }
        case "soft_delete":{ const { error } = await supabase.rpc("admin_soft_delete_user", { _user_id: id, _reason: reason }); if (error) throw error; break; }
        case "restore":   { const { error } = await supabase.rpc("admin_restore_user", { _user_id: id, _reason: reason }); if (error) throw error; break; }
      }
    },
    onSuccess: () => {
      toast.success("تم التنفيذ");
      setAction(null); setReason(""); setNumValue(0); setStrValue("");
      qc.invalidateQueries({ queryKey: ["user", id] });
      qc.invalidateQueries({ queryKey: ["user", id, "history"] });
      qc.invalidateQueries({ queryKey: ["users"] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const open = (a: Action) => {
    setAction(a); setReason("");
    if (a.kind === "level") setNumValue(a.current);
    if (a.kind === "vip") setNumValue(a.current);
    if (a.kind === "gender") setStrValue(a.current);
  };

  if (u.isLoading) return <div className="py-16 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin" /></div>;
  if (!u.data) return <div className="py-16 text-center text-sm text-muted-foreground">لم يتم العثور على المستخدم.</div>;
  const p = u.data;
  type Wallet = { account: string; balance: number; reserved: number };
  const wallets = (p.wallets as Wallet[] | null) ?? [];

  return (
    <div className="space-y-6">
      <Button variant="ghost" size="sm" asChild><Link to="/users"><ArrowRight className="ml-1 h-4 w-4" />رجوع</Link></Button>

      <Card>
        <CardHeader className="flex flex-row items-start gap-4">
          <Avatar className="h-16 w-16"><AvatarFallback className="text-xl">{(p.display_name ?? "?").slice(0,1)}</AvatarFallback></Avatar>
          <div className="flex-1">
            <CardTitle className="text-xl">{p.display_name ?? "—"} <span className="text-sm text-muted-foreground">@{p.username}</span></CardTitle>
            <CardDescription className="mt-1 flex flex-wrap gap-2">
              <Badge variant="outline">UID: {p.external_uid}</Badge>
              <Badge>{p.country}</Badge>
              <Badge variant="secondary">Lv {p.level}</Badge>
              <Badge variant="secondary">VIP {p.vip_level}</Badge>
              <Badge variant="secondary">{p.gender}</Badge>
              <Badge variant={p.status === "active" ? "default" : "destructive"}>{p.status}</Badge>
              <Badge variant="secondary">{p.verification}</Badge>
              {p.deleted_at && <Badge variant="destructive">محذوف</Badge>}
            </CardDescription>
            <div className="mt-3 flex flex-wrap gap-2">
              {has("users.ban") && p.status !== "banned" && (
                <>
                  <Button size="sm" variant="destructive" onClick={() => open({ kind: "ban_perm" })}><Ban className="ml-1 h-3.5 w-3.5" />حظر دائم</Button>
                  <Button size="sm" variant="outline" onClick={() => open({ kind: "ban_temp" })}>حظر مؤقت</Button>
                </>
              )}
              {has("users.ban") && p.status === "banned" && (
                <Button size="sm" variant="default" onClick={() => open({ kind: "unban" })}>إلغاء الحظر</Button>
              )}
              {has("users.verify") && p.verification !== "verified" && (
                <Button size="sm" variant="outline" onClick={() => open({ kind: "verify" })}><ShieldCheck className="ml-1 h-3.5 w-3.5" />توثيق</Button>
              )}
              {has("users.verify") && p.verification === "verified" && (
                <Button size="sm" variant="outline" onClick={() => open({ kind: "unverify" })}>إلغاء التوثيق</Button>
              )}
              {has("users.write") && <Button size="sm" variant="outline" onClick={() => open({ kind: "level", current: p.level })}>تعديل المستوى</Button>}
              {has("users.write") && <Button size="sm" variant="outline" onClick={() => open({ kind: "vip", current: p.vip_level })}>تعديل VIP</Button>}
              {has("users.write") && <Button size="sm" variant="outline" onClick={() => open({ kind: "gender", current: p.gender })}>تعديل الجنس</Button>}
              {has("users.write") && <Button size="sm" variant="outline" onClick={() => open({ kind: "sessions" })}><LogOut className="ml-1 h-3.5 w-3.5" />إنهاء الجلسات</Button>}
              {has("users.write") && !p.deleted_at && <Button size="sm" variant="destructive" onClick={() => open({ kind: "soft_delete" })}><Trash2 className="ml-1 h-3.5 w-3.5" />حذف مؤقت</Button>}
              {has("users.write") && p.deleted_at && <Button size="sm" variant="default" onClick={() => open({ kind: "restore" })}><RotateCcw className="ml-1 h-3.5 w-3.5" />استرجاع</Button>}
            </div>
            {has("users.ban") && (
              <div className="mt-3 flex flex-wrap gap-2">
                {(["message","call","room","post"] as const).map((ch) => {
                  const banned = (p as unknown as Record<string, boolean>)[`${ch}_ban`];
                  return (
                    <Button key={ch} size="sm" variant={banned ? "destructive" : "outline"} onClick={() => open({ kind: "comm", channel: ch, banned })}>
                      <MessageSquareOff className="ml-1 h-3.5 w-3.5" />
                      {ch}: {banned ? "محظور" : "مسموح"}
                    </Button>
                  );
                })}
              </div>
            )}
          </div>
        </CardHeader>
      </Card>

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">نظرة عامة</TabsTrigger>
          <TabsTrigger value="wallet">المحفظة</TabsTrigger>
          <TabsTrigger value="ledger">دفتر الأستاذ</TabsTrigger>
          <TabsTrigger value="history">سجل التعديلات</TabsTrigger>
          <TabsTrigger value="devices">الأجهزة</TabsTrigger>
          <TabsTrigger value="penalties">العقوبات</TabsTrigger>
        </TabsList>

        <TabsContent value="overview">
          <Card><CardContent className="grid gap-3 pt-6 text-sm md:grid-cols-2">
            <Info label="الهاتف" value={p.phone ?? "—"} />
            <Info label="اللغة" value={p.language ?? "—"} />
            <Info label="الجنس" value={p.gender} />
            <Info label="تاريخ الميلاد" value={p.birth_date ?? "—"} />
            <Info label="الوكالة" value={p.agency_id ?? "غير مرتبط"} />
            <Info label="BD" value={p.bd_id ?? "غير مرتبط"} />
            <Info label="آخر ظهور" value={p.last_seen_at ? new Date(p.last_seen_at).toLocaleString("ar-EG-u-nu-latn") : "—"} />
            <Info label="تاريخ الإنشاء" value={new Date(p.created_at).toLocaleString("ar-EG-u-nu-latn")} />
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="wallet">
          <Card><CardContent className="grid gap-4 pt-6 md:grid-cols-3">
            {wallets.map((w) => (
              <div key={w.account} className="rounded-lg border p-4">
                <div className="text-xs text-muted-foreground">{w.account}</div>
                <div className="mt-1 text-2xl font-bold">{w.balance.toLocaleString("en-US")}</div>
                <div className="text-xs text-muted-foreground">محجوز: {w.reserved.toLocaleString("en-US")}</div>
              </div>
            ))}
            {wallets.length === 0 && <div className="col-span-3 text-center text-sm text-muted-foreground">لا توجد محافظ.</div>}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="ledger">
          <Card><CardContent className="pt-6">
            {ledger.isLoading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : (
              <Table>
                <TableHeader><TableRow>
                  <TableHead>الوقت</TableHead><TableHead>الحساب</TableHead><TableHead>الاتجاه</TableHead>
                  <TableHead>السبب</TableHead><TableHead>المبلغ</TableHead><TableHead>الرصيد بعد</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {ledger.data?.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell className="text-xs">{new Date(r.created_at).toLocaleString("ar-EG-u-nu-latn")}</TableCell>
                      <TableCell>{r.account}</TableCell>
                      <TableCell><Badge variant={r.direction === "credit" ? "default" : "destructive"}>{r.direction}</Badge></TableCell>
                      <TableCell>{r.reason}</TableCell>
                      <TableCell className="font-mono">{r.amount.toLocaleString("en-US")}</TableCell>
                      <TableCell className="font-mono">{r.balance_after.toLocaleString("en-US")}</TableCell>
                    </TableRow>
                  ))}
                  {(ledger.data?.length ?? 0) === 0 && <TableRow><TableCell colSpan={6} className="py-8 text-center text-sm text-muted-foreground">لا توجد قيود.</TableCell></TableRow>}
                </TableBody>
              </Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="history">
          <Card><CardContent className="pt-6">
            {history.isLoading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : (
              <Table>
                <TableHeader><TableRow><TableHead>الوقت</TableHead><TableHead>الحقل</TableHead><TableHead>من</TableHead><TableHead>إلى</TableHead><TableHead>السبب</TableHead></TableRow></TableHeader>
                <TableBody>
                  {history.data?.map((h) => (
                    <TableRow key={h.id}>
                      <TableCell className="text-xs">{new Date(h.created_at).toLocaleString("ar-EG-u-nu-latn")}</TableCell>
                      <TableCell><Badge variant="secondary">{h.field}</Badge></TableCell>
                      <TableCell className="font-mono text-xs">{JSON.stringify(h.old_value)}</TableCell>
                      <TableCell className="font-mono text-xs">{JSON.stringify(h.new_value)}</TableCell>
                      <TableCell className="text-xs text-muted-foreground">{h.reason ?? "—"}</TableCell>
                    </TableRow>
                  ))}
                  {(history.data?.length ?? 0) === 0 && <TableRow><TableCell colSpan={5} className="py-8 text-center text-sm text-muted-foreground">لا يوجد سجل.</TableCell></TableRow>}
                </TableBody>
              </Table>
            )}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="devices">
          <Card><CardContent className="pt-6 text-sm">
            {(() => {
              type Dev = { id: string; device_id: string; platform: string | null; app_version: string | null; last_seen_at: string | null };
              const list = (p.user_devices as Dev[] | null) ?? [];
              if (list.length === 0) return <div className="py-8 text-center text-muted-foreground">لا توجد أجهزة مسجّلة.</div>;
              return list.map((d) => (
                <div key={d.id} className="flex items-center justify-between border-b py-2 last:border-0">
                  <div><div className="font-mono text-xs">{d.device_id}</div><div className="text-xs text-muted-foreground">{d.platform} · {d.app_version}</div></div>
                  <div className="text-xs text-muted-foreground">{d.last_seen_at ?? "—"}</div>
                </div>
              ));
            })()}
          </CardContent></Card>
        </TabsContent>

        <TabsContent value="penalties">
          <Card><CardContent className="pt-6">
            {(() => {
              type Pen = { id: string; type: string; reason: string; active: boolean; created_at: string };
              const list = (p.user_penalties as Pen[] | null) ?? [];
              if (list.length === 0) return <div className="py-8 text-center text-sm text-muted-foreground">لا توجد عقوبات.</div>;
              return (
                <Table>
                  <TableHeader><TableRow><TableHead>النوع</TableHead><TableHead>السبب</TableHead><TableHead>نشطة</TableHead><TableHead>التاريخ</TableHead></TableRow></TableHeader>
                  <TableBody>
                    {list.map((pen) => (
                      <TableRow key={pen.id}>
                        <TableCell><Badge variant="destructive">{pen.type}</Badge></TableCell>
                        <TableCell>{pen.reason}</TableCell>
                        <TableCell>{pen.active ? <Badge>نعم</Badge> : <Badge variant="outline">لا</Badge>}</TableCell>
                        <TableCell className="text-xs">{new Date(pen.created_at).toLocaleString("ar-EG-u-nu-latn")}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              );
            })()}
          </CardContent></Card>
        </TabsContent>
      </Tabs>

      <Dialog open={!!action} onOpenChange={(v) => { if (!v) { setAction(null); setReason(""); } }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>تأكيد العملية</DialogTitle>
            <DialogDescription>سيتم تسجيل هذه العملية في سجل التعديلات والمراجعة.</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            {action?.kind === "ban_temp" && (
              <div><Label>المدة (أيام)</Label><Input type="number" min={1} max={365} value={untilDays} onChange={(e) => setUntilDays(Number(e.target.value))} /></div>
            )}
            {action?.kind === "level" && <div><Label>المستوى (0-200)</Label><Input type="number" min={0} max={200} value={numValue} onChange={(e) => setNumValue(Number(e.target.value))} /></div>}
            {action?.kind === "vip" && <div><Label>VIP (0-20)</Label><Input type="number" min={0} max={20} value={numValue} onChange={(e) => setNumValue(Number(e.target.value))} /></div>}
            {action?.kind === "gender" && (
              <div><Label>الجنس</Label>
                <select className="w-full rounded-md border bg-background px-3 py-2 text-sm" value={strValue} onChange={(e) => setStrValue(e.target.value)}>
                  <option value="male">ذكر</option><option value="female">أنثى</option><option value="other">آخر</option>
                </select>
              </div>
            )}
            <div>
              <Label>السبب (إلزامي، 5 أحرف على الأقل)</Label>
              <Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setAction(null)}>إلغاء</Button>
            <Button onClick={() => runRpc.mutate()} disabled={runRpc.isPending || reason.trim().length < 5}>
              {runRpc.isPending && <Loader2 className="ml-1 h-4 w-4 animate-spin" />}تأكيد
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Info({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="flex justify-between border-b pb-2">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}
