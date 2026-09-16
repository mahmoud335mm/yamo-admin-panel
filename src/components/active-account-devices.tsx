import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { fmtDate } from "@/lib/charging-utils";
import { toast } from "sonner";

type Device = { installation_id: string; platform: string; bound_at: string; last_seen_at: string };
export function ActiveAccountDevices({ id }: { id: string }) {
  const { has } = usePermissions(); const qc = useQueryClient();
  const [selected, setSelected] = useState<Device | null>(null); const [reason, setReason] = useState("");
  const devices = useQuery({ queryKey: ["active-account-devices", id], refetchInterval: 15000, queryFn: async () => {
    const { data, error } = await supabase.rpc("admin_get_yamo_active_devices_v247" as never, { p_user_id: id } as never);
    if (error) throw error; return data as unknown as Device[];
  }});
  const release = useMutation({ mutationFn: async () => {
    if (!selected || reason.trim().length < 10) throw new Error("سبب فك الارتباط مطلوب");
    const { error } = await supabase.rpc("admin_release_yamo_active_device_v247" as never, { p_user_id: id, p_installation_id: selected.installation_id, p_reason: reason.trim() } as never);
    if (error) throw error;
  }, onSuccess: () => {
    toast.success("تم فك ارتباط الجهاز دون حذف الحساب"); setSelected(null); setReason("");
    qc.invalidateQueries({ queryKey: ["active-account-devices", id] }); qc.invalidateQueries({ queryKey: ["user-account-context", id] });
  }, onError: (e: Error) => toast.error(e.message) });
  return <Card className="rounded-2xl shadow-none"><CardContent className="space-y-4 p-5"><h2 className="font-bold">الأجهزة المرتبطة ببوابة الدخول</h2>
    <p className="text-xs text-muted-foreground">فك الارتباط يسمح بتسجيل حساب آخر على الجهاز، ولا يحذف الحساب أو الأموال ولا يلغي الحظر.</p>
    {devices.isLoading && <p>جاري التحميل…</p>}{devices.error && <p role="alert" className="text-destructive">تعذر قراءة الأجهزة: {devices.error.message}</p>}
    {devices.data?.map((d) => <div key={d.installation_id} className="rounded-xl border p-4 space-y-2"><p>{d.platform} · الربط: {fmtDate(d.bound_at)}</p><p>آخر نشاط: {fmtDate(d.last_seen_at)}</p>{has("users.devices.release") && <Button variant="outline" onClick={() => { setReason(""); setSelected(d); }}>فك ارتباط الجهاز</Button>}</div>)}
    {devices.isSuccess && !devices.data?.length && <p>لا يوجد جهاز مرتبط حاليًا ببوابة الدخول.</p>}
    <Dialog open={!!selected} onOpenChange={(open) => { if (!open && !release.isPending) setSelected(null); }}><DialogContent><DialogHeader><DialogTitle>تأكيد فك ارتباط الجهاز</DialogTitle></DialogHeader><p>لن يُحذف الحساب القديم. قد يعيد دخوله ربط الجهاز به؛ سجّل الحساب الجديد بعد فك الارتباط.</p><Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="سبب العملية — 10 أحرف على الأقل" /><Button disabled={reason.trim().length < 10 || release.isPending} onClick={() => release.mutate()}>تأكيد فك الارتباط</Button></DialogContent></Dialog>
  </CardContent></Card>;
}
