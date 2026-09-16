import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { fmtDate } from "@/lib/charging-utils";
type Signals = { signals: { ip: string; country: string | null; city: string | null; last_seen_at: string }[]; same_ip_accounts: { user_id: string; legacy_id: string; display_name: string }[] };
export function UserNetworkSignals({ id }: { id: string }) {
  const { has } = usePermissions();
  const query = useQuery({ queryKey: ["user-network-signals",id], enabled: has("users.moderate"), queryFn: async () => {
    const { data,error } = await supabase.rpc("admin_get_yamo_network_signals" as never,{ p_user_id:id } as never);
    if(error) throw error; return data as unknown as Signals;
  }});
  if (!has("users.moderate")) return null;
  return <div className="space-y-3"><h3 className="font-semibold">مؤشرات الشبكة والمنطقة التقريبية</h3><p className="text-xs text-muted-foreground">مشاركة عنوان الإنترنت لا تثبت مشاركة الواي فاي أو ملكية الحسابات. المنطقة تقريبية، ولا يُنفَّذ حظر أو ربط تلقائي بسببها. الفترة المعروضة آخر 30 يومًا.</p>{query.isLoading && <p>جاري قراءة المؤشرات…</p>}{query.error && <p role="alert" className="text-destructive">تعذر قراءة مؤشرات الشبكة: {(query.error as Error).message}</p>}{query.isSuccess && !query.data.signals.length && <p>لا توجد اتصالات مسجلة بعد. يلزم تركيب السيرفر ونشر مسار التسجيل وتحديث التطبيق.</p>}{query.data?.signals.map((s,i) => <div key={i} className="rounded-xl border p-3"><span dir="ltr">{s.ip}</span> · {s.country ?? "دولة غير متاحة"} · {s.city ?? "منطقة غير متاحة"} · {fmtDate(s.last_seen_at)}</div>)}{query.data?.same_ip_accounts.map((a) => <Link className="block text-primary underline" key={a.user_id} to="/users/$id" params={{ id:a.user_id }}>{a.display_name} · {a.legacy_id} — شارك عنوان الإنترنت</Link>)}</div>;
}
