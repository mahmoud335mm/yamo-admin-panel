import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Loader2 } from "lucide-react";

type UserResult = {
  user_id: string; legacy_id: string; display_name: string; avatar_url?: string | null;
  account_status?: string | null; entity_type?: string | null; agency_id?: string | null;
  agency_name?: string | null; host_status?: string | null;
};

export function UserAccountLookup({ label = "حساب المستخدم", value, onChange, placeholder = "اكتب الاسم أو ID", requireAvailable = false }:{
  label?: string; value: string; onChange: (legacyId: string, row?: UserResult) => void;
  placeholder?: string; requireAvailable?: boolean;
}) {
  const [text, setText] = useState(value);
  const [term, setTerm] = useState("");
  useEffect(() => { if (!value) setText(""); }, [value]);
  useEffect(() => { const id = setTimeout(() => setTerm(text.trim()), 250); return () => clearTimeout(id); }, [text]);
  const query = useQuery({
    queryKey: ["admin-user-account-suggestions", term], enabled: term.length > 0,
    queryFn: async () => { const { data, error } = await (supabase as any).rpc("admin_search_yamo_agency_entity", { p_query: term }); if (error) throw error; return (data ?? []) as UserResult[]; },
  });
  return <div className="space-y-1">
    <Label>{label}</Label>
    <div className="relative"><Input value={text} placeholder={placeholder} onChange={e => { setText(e.target.value); onChange(""); }}/>{query.isFetching && <Loader2 className="absolute left-3 top-3 h-4 w-4 animate-spin"/>}</div>
    {term && !value && <div className="max-h-56 overflow-auto rounded-lg border bg-background shadow-lg">
      {(query.data ?? []).map(r => { const unavailable = requireAvailable && Boolean(r.agency_id); return <button type="button" key={r.user_id} disabled={unavailable} className="flex w-full items-center gap-3 border-b p-3 text-right hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50" onClick={() => { setText(`${r.display_name} · ${r.legacy_id}`); onChange(r.legacy_id, r); }}>
        {r.avatar_url ? <img src={r.avatar_url} alt="" className="h-11 w-11 rounded-full border object-cover"/> : <span className="grid h-11 w-11 place-items-center rounded-full bg-primary/10 font-bold text-primary">{(r.display_name || "؟").slice(0,1)}</span>}
        <span className="min-w-0 flex-1"><b className="block truncate">{r.display_name}</b><small className="block text-muted-foreground" dir="ltr">ID {r.legacy_id} · {r.account_status || "active"}</small><small className="block text-muted-foreground">{r.agency_name ? `مرتبط بـ ${r.agency_name}` : "غير مرتبط بوكالة"}</small></span>
        <Badge variant={unavailable ? "destructive" : "outline"}>{unavailable ? "غير متاح" : "اختيار"}</Badge>
      </button>; })}
      {!query.isFetching && (query.data ?? []).length === 0 && <div className="p-5 text-center text-sm text-muted-foreground">لا توجد حسابات مطابقة</div>}
    </div>}
    {value && <p className="text-xs text-emerald-600">تم اختيار الحساب: <b dir="ltr">ID {value}</b></p>}
    {query.error && <p className="text-xs text-destructive">{(query.error as Error).message}</p>}
  </div>;
}
