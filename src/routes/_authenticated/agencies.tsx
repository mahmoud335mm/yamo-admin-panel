import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { YamoDataModule } from "@/components/yamo-data-module";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { ArrowDownRight, ArrowUpRight, Building2, CalendarDays, Copy, GitBranch, Info, Loader2, Plus, RefreshCw, Save, Search, Users, WalletCards } from "lucide-react";
import { toast } from "sonner";
import { UserAccountLookup } from "@/components/user-account-lookup";

type TreeAgency = {
  agency_id: string; parent_agency_id: string | null; name: string; owner_id: string;
  owner_legacy_id: string; owner_name: string; owner_avatar_url?: string|null; agency_type?:string; host_invite_code: string;
  agency_invite_code: string; tree_depth: number; commission_percent: number;
  disabled_at: string | null; direct_hosts: number; direct_commission_pearls: number; created_at: string;
  creation_source?: string; opening_code?: string|null; created_by_name?: string|null; created_by_legacy_id?: string|null;
};
type Rate = { depth: number; rate: number; active: boolean };
type AgencyConfig = { enabled: boolean; total_percent: number; maximum_depth: number;
  allow_sub_agencies: boolean; minimum_settlement_pearls: number; rates: Rate[] };
type FinanceConfig = { agency_percent:number;parent_agency_percent:number;platform_percent:number;
  platform_agency_invite_code?:string;
  minimum_settlement_pearls:number;settlement_frequency:string;below_target_action:string;
  automatic_settlements:boolean;host_task_days:number;host_task_unique_people:number;
  host_task_reward_pearls:number;agency_task_reward_pearls:number;
  male_recharge_threshold_coins:number;male_recharge_agency_percent:number };
type AgencyDashboard = { period_days:number;agencies_active:number;hosts_active:number;
  gross_now:number;gross_before:number;commission_now:number;commission_before:number;
  messages_now:number;calls_now:number;gifts_now:number;pending_settlements:number;failed_settlements:number };
type AgencyHealth = { automatic_settlements_enabled:boolean;cron_active:boolean;last_cron_run?:string|null;last_cron_status?:string|null;official_account_bound:boolean;agency_messages_enabled:boolean;duplicate_protection:boolean };
const db = supabase as any;

export const Route = createFileRoute("/_authenticated/agencies")({
  component: () => <PermissionGuard permission="agencies.read"><AgenciesPage /></PermissionGuard>,
});

function AgenciesPage() {
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [showDisabled, setShowDisabled] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);
  const tree = useQuery({ queryKey: ["yamo-agency-tree-admin"], queryFn: async () => {
    const { data, error } = await db.rpc("admin_get_yamo_agency_tree"); if (error) throw error;
    return (data ?? []) as TreeAgency[];
  }});
  const config = useQuery({ queryKey: ["yamo-agency-config-admin"], queryFn: async () => {
    const { data, error } = await db.rpc("admin_get_yamo_agency_config"); if (error) throw error;
    return (data ?? {}) as AgencyConfig;
  }});
  const finance = useQuery({ queryKey:["yamo-agency-finance-config"],queryFn:async()=>{
    const {data,error}=await db.rpc("admin_get_yamo_agency_finance_config");if(error)throw error;return (data??{}) as FinanceConfig;
  }});
  const dashboard = useQuery({ queryKey:["yamo-agency-dashboard",7],queryFn:async()=>{
    const {data,error}=await db.rpc("admin_get_yamo_agency_dashboard",{p_days:7});if(error)throw error;return (data??{}) as AgencyDashboard;
  }});
  const health = useQuery({ queryKey:["yamo-agency-health"],queryFn:async()=>{const{data,error}=await db.rpc("admin_get_yamo_agency_health");if(error)throw error;return (data??{}) as AgencyHealth;}});
  const refresh = async () => {
    if (refreshing) return;
    setRefreshing(true);
    try {
      await Promise.all([
        tree.refetch(), config.refetch(), finance.refetch(), dashboard.refetch(),
        health.refetch(),
        qc.refetchQueries({ queryKey: ["yamo-data", "admin_agency_settlements"], type: "active" }),
        qc.refetchQueries({ queryKey: ["agency-details"], type: "active" }),
      ]);
      setLastRefresh(new Date()); toast.success("تم جلب أحدث بيانات الوكالات من السيرفر");
    } catch (error) { toast.error(error instanceof Error ? error.message : "تعذر تحديث البيانات"); }
    finally { setRefreshing(false); }
  };
  const visible = useMemo(() => {
    const q = search.trim().toLowerCase();
    return (tree.data ?? []).filter((a) => (showDisabled || !a.disabled_at) && (!q ||
      [a.name,a.owner_name,a.owner_legacy_id,a.host_invite_code,a.agency_invite_code]
        .some((v) => String(v ?? "").toLowerCase().includes(q))));
  }, [tree.data, search, showDisabled]);
  const totals = useMemo(() => ({
    agencies:(tree.data??[]).filter(a=>!a.disabled_at).length,
    roots:(tree.data??[]).filter(a=>!a.parent_agency_id&&!a.disabled_at).length,
    hosts:(tree.data??[]).reduce((n,a)=>n+Number(a.direct_hosts||0),0),
    commission:(tree.data??[]).reduce((n,a)=>n+Number(a.direct_commission_pearls||0),0),
  }), [tree.data]);

  return <div className="space-y-6" dir="rtl">
    <div className="flex flex-wrap items-center justify-between gap-3"><div>
      <h1 className="text-2xl font-bold">إدارة شجرة الوكالات</h1>
      <p className="text-sm text-muted-foreground">نفس نظام الوكالات المتصل بتطبيق يامو — الأكواد والفروع والأرباح والتسويات.</p>
    </div><div className="flex flex-wrap items-center gap-2"><CreateRootDialog agencies={tree.data??[]} onDone={()=>void refresh()}/><Button variant="outline" disabled={refreshing} onClick={()=>void refresh()}>{refreshing?<Loader2 className="ml-2 h-4 w-4 animate-spin"/>:<RefreshCw className="ml-2 h-4 w-4"/>}تحديث الآن</Button>{lastRefresh&&<span className="text-xs text-muted-foreground">آخر تحديث: {lastRefresh.toLocaleTimeString("ar-EG-u-nu-latn")}</span>}</div></div>
    <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <TrendStat icon={<Building2/>} label="الوكالات النشطة" value={dashboard.data?.agencies_active??totals.agencies}/>
      <TrendStat icon={<Users/>} label="المضيفون النشطون" value={dashboard.data?.hosts_active??totals.hosts}/>
      <TrendStat icon={<WalletCards/>} label="دخل آخر 7 أيام" value={dashboard.data?.gross_now??0} current={dashboard.data?.gross_now} previous={dashboard.data?.gross_before}/>
      <TrendStat icon={<ArrowUpRight/>} label="عمولة آخر 7 أيام" value={dashboard.data?.commission_now??0} current={dashboard.data?.commission_now} previous={dashboard.data?.commission_before}/>
    </div>
    <div className="grid gap-3 sm:grid-cols-3 xl:grid-cols-5">
      <SourceStat label="الرسائل" value={dashboard.data?.messages_now}/><SourceStat label="المكالمات" value={dashboard.data?.calls_now}/><SourceStat label="الهدايا" value={dashboard.data?.gifts_now}/><SourceStat label="تسويات معلقة" value={dashboard.data?.pending_settlements}/><SourceStat label="تسويات فاشلة" value={dashboard.data?.failed_settlements} danger/>
    </div>
    <Card><CardHeader><CardTitle>حالة تكامل نظام الوكالات</CardTitle><CardDescription>فحص حي من قاعدة البيانات؛ اللون الأخضر يعني أن الجزء مفعّل، وليس مجرد إعداد ظاهر في الواجهة.</CardDescription></CardHeader><CardContent className="grid gap-2 sm:grid-cols-2 xl:grid-cols-5"><Health label="التسوية التلقائية" ok={health.data?.automatic_settlements_enabled&&health.data?.cron_active}/><Health label="منع تكرار الصرف" ok={health.data?.duplicate_protection}/><Health label="رسائل الوكالات" ok={health.data?.agency_messages_enabled}/><Health label="حساب يامو الرسمي" ok={health.data?.official_account_bound}/><Health label="آخر تشغيل" ok={health.data?.last_cron_status==="succeeded"} note={health.data?.last_cron_run?new Date(health.data.last_cron_run).toLocaleString("ar-EG-u-nu-latn"):"لا يوجد تشغيل مسجل"}/></CardContent></Card>
    <Tabs defaultValue="tree" className="space-y-4"><TabsList className="h-auto flex-wrap">
      <TabsTrigger value="tree">الشجرة والأكواد</TabsTrigger><TabsTrigger value="rates">النسب والتسوية</TabsTrigger>
      <TabsTrigger value="search">بحث شامل</TabsTrigger><TabsTrigger value="transfers">النقل والمدد</TabsTrigger><TabsTrigger value="settlements">التسويات</TabsTrigger>
    </TabsList>
    <TabsContent value="tree"><div className="space-y-4"><Card className="border-primary/30"><CardContent className="flex flex-wrap items-center justify-between gap-3 p-4"><div><b>إدارة يامو — الوكالة الأم</b><p className="text-xs text-muted-foreground">الكود التالي يفتح وكالة رئيسية مباشرة تحت الإدارة من داخل التطبيق.</p></div><Code value={finance.data?.platform_agency_invite_code??"AG-YM-ROOT01"} onCopy={v=>navigator.clipboard.writeText(v).then(()=>toast.success("تم نسخ كود الإدارة"))}/></CardContent></Card><Card><CardHeader><CardTitle>الوكالات</CardTitle><CardDescription>وكالة رئيسية تحت الإدارة، ثم الوكالات الفرعية أسفلها مع بروفايل القائد.</CardDescription></CardHeader><CardContent className="space-y-4">
      <div className="flex flex-wrap gap-3"><div className="relative min-w-64 flex-1"><Search className="absolute right-3 top-2.5 h-4 w-4 text-muted-foreground"/><Input className="pr-9" value={search} onChange={e=>setSearch(e.target.value)} placeholder="بحث بالاسم أو ID أو الكود"/></div><label className="flex items-center gap-2 text-sm"><Switch checked={showDisabled} onCheckedChange={setShowDisabled}/>عرض المعطلة</label></div>
      {tree.isLoading?<Loader2 className="mx-auto h-6 w-6 animate-spin"/>:tree.error?<div className="rounded-md border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">{(tree.error as Error).message}</div>:
      <div className="overflow-x-auto"><Table><TableHeader><TableRow><TableHead>الوكالة/المالك</TableHead><TableHead>الإنشاء</TableHead><TableHead>المستوى</TableHead><TableHead>كود المضيف</TableHead><TableHead>كود فتح وكالة</TableHead><TableHead>المضيفون</TableHead><TableHead>العمولة</TableHead><TableHead>الحالة</TableHead><TableHead>إجراءات</TableHead></TableRow></TableHeader><TableBody>{visible.map(a=><AgencyRow key={a.agency_id} agency={a} onDone={()=>void refresh()}/>)}</TableBody></Table></div>}
    </CardContent></Card></div></TabsContent>
    <TabsContent value="rates"><FinanceSettings config={finance.data} loading={finance.isLoading} onDone={refresh}/></TabsContent>
    <TabsContent value="search"><AgencyEntitySearch/></TabsContent>
    <TabsContent value="transfers"><div className="space-y-4"><ParentTermPanel agencies={tree.data??[]} onDone={refresh}/><TransferPanel agencies={tree.data??[]} onDone={refresh}/></div></TabsContent>
    <TabsContent value="settlements"><div className="space-y-4"><ManualSettlement onDone={refresh}/><YamoDataModule title="تسويات الوكالات" description="تلقائية ويدوية مع رقم مرجعي ومنع الصرف المكرر" source="admin_agency_settlements"
      columns={[{key:"agency_name",label:"الوكالة"},{key:"period_start",label:"من"},{key:"period_end",label:"إلى"},{key:"gross_pearls",label:"إجمالي اللؤلؤ"},{key:"losses_pearls",label:"الخسائر"},{key:"net_pearls",label:"الصافي"},{key:"target_pearls",label:"التارجت"},{key:"platform_pearls",label:"للمنصة"},{key:"status",label:"الحالة"}]}
      actions={[{label:"تأكيد التسوية",rpc:"admin_set_agency_settlement_status",buildArgs:r=>({p_id:r.id,p_status:"settled",p_reason:"اعتماد من إدارة الوكالات"})},{label:"إلغاء التسوية",rpc:"admin_set_agency_settlement_status",tone:"destructive",buildArgs:r=>({p_id:r.id,p_status:"cancelled",p_reason:"إلغاء من إدارة الوكالات"})}]}/></div></TabsContent>
    </Tabs>
  </div>;
}

function TrendStat({icon,label,value,current,previous}:{icon:React.ReactNode;label:string;value:string|number;current?:number;previous?:number}) {
  const hasTrend=current!==undefined&&previous!==undefined;
  const change=hasTrend?(Number(previous)===0?(Number(current)>0?100:0):((Number(current)-Number(previous))/Math.abs(Number(previous)))*100):0;
  const up=change>=0;
  return <Card><CardContent className="flex items-center gap-3 p-4"><span className="rounded-lg bg-primary/10 p-2 text-primary">{icon}</span><div className="min-w-0 flex-1"><div className="flex items-center justify-between gap-2"><div className="text-xl font-bold" dir="ltr">{typeof value==="number"?value.toLocaleString("en-US"):value}</div>{hasTrend&&<span className={`flex items-center text-xs font-bold ${up?"text-emerald-600":"text-red-600"}`} dir="ltr">{up?<ArrowUpRight className="h-4 w-4"/>:<ArrowDownRight className="h-4 w-4"/>}{change>0?"+":""}{change.toFixed(1)}%</span>}</div><div className="text-xs text-muted-foreground">{label}</div></div></CardContent></Card>;
}
function SourceStat({label,value=0,danger=false}:{label:string;value?:number;danger?:boolean}) { return <div className="rounded-xl border bg-card p-3"><div className="text-xs text-muted-foreground">{label}</div><div className={`mt-1 text-lg font-bold ${danger&&value>0?"text-red-600":""}`} dir="ltr">{Number(value||0).toLocaleString("en-US")}</div></div>; }
function Health({label,ok,note}:{label:string;ok?:boolean;note?:string}){return <div className="rounded-lg border p-3"><div className="flex items-center gap-2"><span className={`h-2.5 w-2.5 rounded-full ${ok?"bg-emerald-500":"bg-red-500"}`}/><b className="text-sm">{label}</b></div><p className="mt-1 text-xs text-muted-foreground">{note??(ok?"يعمل":"يحتاج مراجعة")}</p></div>}

function AgencyRow({agency:a,onDone}:{agency:TreeAgency;onDone:()=>void}) {
  const m=useMutation({mutationFn:async(i:{rpc:string;args:Record<string,unknown>})=>{const {error}=await db.rpc(i.rpc,i.args);if(error)throw error;},onSuccess:()=>{toast.success("تم التنفيذ والمزامنة مع التطبيق");onDone();},onError:(e:Error)=>toast.error(e.message)});
  const copy=(v:string)=>navigator.clipboard.writeText(v).then(()=>toast.success("تم نسخ الكود"));
  return <TableRow className={a.disabled_at?"opacity-60":""}><TableCell><div style={{paddingInlineStart:`${Math.min(a.tree_depth,8)*18}px`}} className="flex items-center gap-2">{a.tree_depth>0?<GitBranch className="h-4 w-4 text-orange-500"/>:<Building2 className="h-4 w-4 text-primary"/>}<UserPhoto src={a.owner_avatar_url} name={a.owner_name}/><div><div className="font-semibold">{a.name}</div><div className="text-xs text-muted-foreground">القائد: {a.owner_name} · ID {a.owner_legacy_id}</div></div></div></TableCell>
    <TableCell className="min-w-44 text-xs"><div>{new Date(a.created_at).toLocaleString("ar-EG-u-nu-latn")}</div><div className="text-muted-foreground">{a.creation_source==="app"?"من التطبيق":"من لوحة التحكم"}{a.created_by_name?` · ${a.created_by_name}`:""}</div><div className="font-mono text-primary">{a.opening_code||"بدون كود مسجل"}</div></TableCell><TableCell><Badge variant="outline">{a.parent_agency_id?"وكالة فرعية":"وكالة رئيسية تحت الإدارة"}</Badge></TableCell><TableCell><Code value={a.host_invite_code} onCopy={copy}/></TableCell><TableCell><Code value={a.agency_invite_code} onCopy={copy}/></TableCell><TableCell>{a.direct_hosts}</TableCell><TableCell>{Number(a.direct_commission_pearls).toLocaleString("en-US")}</TableCell><TableCell><Badge variant={a.disabled_at?"destructive":"default"}>{a.disabled_at?"معطلة":"نشطة"}</Badge></TableCell>
    <TableCell><div className="flex flex-wrap gap-1"><AgencyInfoDialog agency={a}/><Button size="sm" variant="outline" onClick={()=>m.mutate({rpc:"admin_regenerate_yamo_agency_code",args:{p_agency_id:a.agency_id,p_kind:"host"}})}>كود مضيف جديد</Button><Button size="sm" variant="outline" onClick={()=>m.mutate({rpc:"admin_regenerate_yamo_agency_code",args:{p_agency_id:a.agency_id,p_kind:"agency"}})}>كود فرع جديد</Button><Button size="sm" variant={a.disabled_at?"default":"destructive"} onClick={()=>m.mutate({rpc:"admin_set_agency_disabled",args:{p_agency_id:a.agency_id,p_disabled:!a.disabled_at,p_reason:a.disabled_at?"إعادة تفعيل من لوحة الشجرة":"تعطيل من لوحة الشجرة"}})}>{a.disabled_at?"تفعيل":"تعطيل"}</Button></div></TableCell></TableRow>;
}
function Code({value,onCopy}:{value:string;onCopy:(v:string)=>void}) { return <button className="flex items-center gap-1 font-mono text-xs text-primary" onClick={()=>onCopy(value)}><Copy className="h-3.5 w-3.5"/>{value||"—"}</button>; }

function CreateRootDialog({agencies,onDone}:{agencies:TreeAgency[];onDone:()=>void}) {
  const [open,setOpen]=useState(false),[owner,setOwner]=useState(""),[name,setName]=useState(""),[country,setCountry]=useState(""),[whatsapp,setWhatsapp]=useState(""),[parent,setParent]=useState("ROOT"),[days,setDays]=useState("30"),[permanent,setPermanent]=useState(false);
  const whatsappValid=/^\+[0-9]{8,15}$/.test(whatsapp.trim());
  const m=useMutation({mutationFn:async()=>{if(!whatsappValid)throw new Error("اكتب واتساب صحيحاً مع كود الدولة مثل +201001234567");const {error}=await db.rpc("admin_create_yamo_agency_v2",{p_owner_legacy_id:owner,p_name:name,p_parent_id:parent==="ROOT"?null:parent,p_duration_days:Number(days),p_permanent:permanent,p_country_code:country,p_whatsapp:whatsapp});if(error)throw error;},onSuccess:()=>{toast.success("تم فتح الوكالة وتوليد الكودين");setOpen(false);onDone();},onError:(e:Error)=>toast.error(e.message)});
  return <Dialog open={open} onOpenChange={setOpen}><DialogTrigger asChild><Button><Plus className="ml-2 h-4 w-4"/>فتح وكالة</Button></DialogTrigger><DialogContent dir="rtl" className="max-w-2xl"><DialogHeader><DialogTitle>فتح وكالة رئيسية أو فرعية</DialogTitle></DialogHeader><div className="grid gap-3"><OwnerLookup value={owner} set={setOwner}/><Field label="اسم الوكالة" value={name} set={setName}/><AgencySelect label="تتبع" value={parent} set={setParent} agencies={agencies} allowRoot/>{parent!=="ROOT"&&<><Field label="مدة التبعية بالأيام" value={days} set={setDays} type="number"/><label className="flex items-center justify-between rounded-md border p-3"><span>ربط دائم</span><Switch checked={permanent} onCheckedChange={setPermanent}/></label></>}<Field label="كود الدولة" value={country} set={setCountry}/><Field label="واتساب إجباري مع كود الدولة" value={whatsapp} set={setWhatsapp}/>{whatsapp&&!whatsappValid&&<p className="text-xs text-destructive">مثال صحيح: +201001234567</p>}</div><DialogFooter><Button variant="outline" onClick={()=>setOpen(false)}>إلغاء</Button><Button disabled={!owner.trim()||name.trim().length<2||!whatsappValid||m.isPending} onClick={()=>m.mutate()}>{m.isPending&&<Loader2 className="ml-2 h-4 w-4 animate-spin"/>}إنشاء وتوليد الأكواد</Button></DialogFooter></DialogContent></Dialog>;
}

function OwnerLookup({value,set}:{value:string;set:(v:string)=>void}){return <UserAccountLookup label="قائد الوكالة" value={value} onChange={set} placeholder="ابدأ بكتابة ID أو اسم القائد" requireAvailable/>}

function AgencySettings({config,loading,onDone}:{config?:AgencyConfig;loading:boolean;onDone:()=>void}) {
  const [total,setTotal]=useState("10"),[depth,setDepth]=useState("6"),[allow,setAllow]=useState(true),[rates,setRates]=useState<Rate[]>([]);
  useEffect(()=>{if(config){setTotal(String(config.total_percent??10));setDepth(String(config.maximum_depth??6));setAllow(config.allow_sub_agencies!==false);setRates(config.rates??[]);}},[config]);
  const save=useMutation({mutationFn:async()=>{const active=rates.filter(r=>r.active).map(r=>({depth:r.depth,rate:Number(r.rate)}));const {error}=await db.rpc("admin_save_yamo_agency_settings",{p_total_percent:Number(total),p_maximum_depth:Number(depth),p_allow_sub_agencies:allow,p_rates:active});if(error)throw error;},onSuccess:()=>{toast.success("تم حفظ النسب؛ العمليات الجديدة فقط ستستخدمها");onDone();},onError:(e:Error)=>toast.error(e.message)});
  const setRate=(d:number,v:string)=>setRates(old=>[...old.filter(r=>r.depth!==d),{depth:d,rate:Number(v||0),active:true}].sort((a,b)=>a.depth-b.depth));
  if(loading)return <Loader2 className="mx-auto h-6 w-6 animate-spin"/>;
  return <Card><CardHeader><CardTitle>نسب شجرة الأرباح</CardTitle><CardDescription>المستوى 0 هو وكالة المضيف المباشرة، ثم الوكالة الأم. السجلات القديمة لا تتغير.</CardDescription></CardHeader><CardContent className="space-y-5"><div className="grid gap-4 md:grid-cols-3"><Field label="إجمالي حصة الوكالات %" value={total} set={setTotal} type="number"/><Field label="أقصى عمق للشجرة" value={depth} set={setDepth} type="number"/><label className="flex items-center justify-between rounded-md border p-3"><span>السماح بفتح فروع</span><Switch checked={allow} onCheckedChange={setAllow}/></label></div><div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{Array.from({length:Math.min(Math.max(Number(depth)||1,1),10)},(_,d)=>{const r=rates.find(x=>x.depth===d);return <Field key={d} label={d===0?"الوكالة المباشرة %":`المستوى الأعلى ${d} %`} value={String(r?.rate??0)} set={v=>setRate(d,v)} type="number"/>;})}</div><div className="flex items-center justify-between rounded-md bg-muted p-3 text-sm"><span>مجموع نسب المستويات</span><strong>{rates.filter(r=>r.active).reduce((n,r)=>n+Number(r.rate||0),0).toFixed(2)}% من حد {Number(total||0).toFixed(2)}%</strong></div><Button onClick={()=>save.mutate()} disabled={save.isPending}><Save className="ml-2 h-4 w-4"/>حفظ وتطبيق على العمليات الجديدة</Button></CardContent></Card>;
}

function FinanceSettings({config,loading,onDone}:{config?:FinanceConfig;loading:boolean;onDone:()=>void}) {
  const [agency,setAgency]=useState("10"),[parent,setParent]=useState("0"),[platform,setPlatform]=useState("0"),[target,setTarget]=useState("500000");
  const [frequency,setFrequency]=useState("weekly"),[below,setBelow]=useState("platform"),[automatic,setAutomatic]=useState(true);
  const [taskDays,setTaskDays]=useState("14"),[people,setPeople]=useState("10"),[hostReward,setHostReward]=useState("10000"),[agencyReward,setAgencyReward]=useState("10000");
  const [rechargeTarget,setRechargeTarget]=useState("100000"),[rechargePercent,setRechargePercent]=useState("0");
  useEffect(()=>{if(!config)return;setAgency(String(config.agency_percent??10));setParent(String(config.parent_agency_percent??0));setPlatform(String(config.platform_percent??0));setTarget(String(config.minimum_settlement_pearls??500000));setFrequency(config.settlement_frequency??"weekly");setBelow(config.below_target_action??"platform");setAutomatic(config.automatic_settlements!==false);setTaskDays(String(config.host_task_days??14));setPeople(String(config.host_task_unique_people??10));setHostReward(String(config.host_task_reward_pearls??10000));setAgencyReward(String(config.agency_task_reward_pearls??10000));setRechargeTarget(String(config.male_recharge_threshold_coins??100000));setRechargePercent(String(config.male_recharge_agency_percent??0));},[config]);
  const total=Number(agency||0)+Number(parent||0)+Number(platform||0);
  const save=useMutation({mutationFn:async()=>{if(total>100)throw new Error("مجموع النسب لا يمكن أن يتجاوز 100%");const {error}=await db.rpc("admin_save_yamo_agency_finance_config",{p_agency_percent:Number(agency),p_parent_percent:Number(parent),p_platform_percent:Number(platform),p_minimum_target:Number(target),p_frequency:frequency,p_below_target_action:below,p_automatic:automatic,p_host_task_days:Number(taskDays),p_unique_people:Number(people),p_host_reward:Number(hostReward),p_agency_reward:Number(agencyReward),p_male_recharge_threshold:Number(rechargeTarget),p_male_recharge_percent:Number(rechargePercent)});if(error)throw error;},onSuccess:()=>{toast.success("تم حفظ النظام وسيُطبق تلقائياً");onDone();},onError:(e:Error)=>toast.error(e.message)});
  if(loading)return <Loader2 className="mx-auto h-6 w-6 animate-spin"/>;
  return <div className="grid gap-4 xl:grid-cols-2"><Card><CardHeader><CardTitle>النسب والتارجت</CardTitle><CardDescription>أرقام إنجليزية من 0 إلى 100، ومجموعها لا يتجاوز 100%.</CardDescription></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 sm:grid-cols-3"><Field label="نسبة الوكالة %" value={agency} set={setAgency} type="number"/><Field label="نسبة الوكالة الأم %" value={parent} set={setParent} type="number"/><Field label="نسبة المنصة %" value={platform} set={setPlatform} type="number"/></div><div className={`rounded-md p-3 text-sm ${total>100?"bg-destructive/10 text-destructive":"bg-muted"}`}>المجموع: <b dir="ltr">{total}%</b></div><Field label="الحد الأدنى للتارجت (لؤلؤ)" value={target} set={setTarget} type="number"/><SelectField label="موعد التسوية" value={frequency} set={setFrequency} options={[["weekly","أسبوعي"],["monthly","شهري"]]}/><SelectField label="أقل من التارجت" value={below} set={setBelow} options={[["platform","يذهب إلى أرباح المنصة"],["carry","يُرحّل للفترة التالية"]]}/><label className="flex items-center justify-between rounded-md border p-3"><span>تشغيل التسوية التلقائية</span><Switch checked={automatic} onCheckedChange={setAutomatic}/></label></CardContent></Card>
  <Card><CardHeader><CardTitle>مهام المضيف ومكافأة الشحن</CardTitle><CardDescription>تبدأ من تاريخ تسجيل المضيف وتتجدد أسبوعياً حتى نهاية مدته.</CardDescription></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 sm:grid-cols-2"><Field label="مدة المضيف بالأيام" value={taskDays} set={setTaskDays} type="number"/><Field label="أشخاص مختلفون أسبوعياً" value={people} set={setPeople} type="number"/><Field label="مكافأة المضيف (لؤلؤ)" value={hostReward} set={setHostReward} type="number"/><Field label="مكافأة الوكالة (لؤلؤ)" value={agencyReward} set={setAgencyReward} type="number"/><Field label="حد شحن الذكر (كوينز)" value={rechargeTarget} set={setRechargeTarget} type="number"/><Field label="نسبة الوكيل من الشحن %" value={rechargePercent} set={setRechargePercent} type="number"/></div><Button className="w-full" disabled={save.isPending||total>100} onClick={()=>save.mutate()}><Save className="ml-2 h-4 w-4"/>حفظ وتطبيق النظام</Button></CardContent></Card></div>;
}

function AgencyEntitySearch(){
  const[q,setQ]=useState("");
  const[term,setTerm]=useState("");
  useEffect(()=>{const id=setTimeout(()=>setTerm(q.trim()),250);return()=>clearTimeout(id)},[q]);
  const results=useQuery({queryKey:["agency-smart-search",term],enabled:term.length>0,queryFn:async()=>{const{data,error}=await db.rpc("admin_search_yamo_agency_entity",{p_query:term});if(error)throw error;return data??[];}});
  return <Card><CardHeader><CardTitle>البحث الذكي عن الحسابات والوكالات</CardTitle><CardDescription>تظهر الاقتراحات أثناء الكتابة بالصورة وبيانات الحساب الحقيقية.</CardDescription></CardHeader><CardContent className="space-y-4"><div className="relative"><Search className="absolute right-3 top-3 h-4 w-4 text-muted-foreground"/><Input className="pr-9" value={q} onChange={e=>setQ(e.target.value)} placeholder="اكتب ID أو الاسم أو كود الوكالة"/>{results.isFetching&&<Loader2 className="absolute left-3 top-3 h-4 w-4 animate-spin"/>}</div>{term&&<div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{(results.data??[]).map((r:any)=><div key={`${r.entity_type}-${r.user_id}-${r.agency_id??"none"}`} className="flex items-center gap-3 rounded-xl border bg-card p-3"><UserPhoto src={r.avatar_url} name={r.display_name}/><div className="min-w-0 flex-1"><div className="truncate font-semibold">{r.display_name}</div><div className="text-xs text-muted-foreground" dir="ltr">ID {r.legacy_id}</div><div className="mt-1 flex flex-wrap gap-1"><Badge variant="outline">{entityLabel(r.entity_type)}</Badge>{r.host_status&&<Badge variant={r.host_status==="active"?"default":"secondary"}>{r.host_status==="active"?"مضيف نشط":"مضيف سابق"}</Badge>}<Badge variant="secondary">LV {r.level??0}</Badge>{r.vip_level>0&&<Badge>VIP {r.vip_level}</Badge>}</div><div className="mt-2 text-xs">{r.agency_name?`${r.agency_name} · مستوى ${r.agency_level}`:"غير مرتبط بوكالة"}</div><div className="mt-1 flex gap-3 text-xs text-muted-foreground"><span dir="ltr">◉ {Number(r.coins||0).toLocaleString("en-US")}</span><span dir="ltr">◆ {Number(r.pearls||0).toLocaleString("en-US")}</span></div></div>{r.agency_id&&<AgencyQuickDetails agencyId={r.agency_id} agencyName={r.agency_name}/>}</div>)}{!results.isFetching&&(results.data??[]).length===0&&<div className="col-span-full rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">لا توجد نتائج مطابقة.</div>}</div>}</CardContent></Card>
}

function entityLabel(v:string){return v==="agency_owner"?"مالك وكالة":v==="host"?"مضيف":"مستخدم"}
function UserPhoto({src,name,size="h-12 w-12"}:{src?:string|null;name?:string;size?:string}){return src?<img src={src} alt={name??""} className={`${size} shrink-0 rounded-full border object-cover`}/>:<div className={`${size} grid shrink-0 place-items-center rounded-full bg-primary/10 font-bold text-primary`}>{(name??"؟").slice(0,1)}</div>}
function AgencyQuickDetails({agencyId,agencyName}:{agencyId:string;agencyName?:string}){const stub={agency_id:agencyId,name:agencyName??"الوكالة"} as TreeAgency;return <AgencyInfoDialog agency={stub}/>}

function AgencyInfoDialog({agency}:{agency:TreeAgency}){
  const[open,setOpen]=useState(false);
  const q=useQuery({queryKey:["agency-details",agency.agency_id],enabled:open,queryFn:async()=>{const{data,error}=await db.rpc("admin_get_yamo_agency_details",{p_agency_id:agency.agency_id});if(error)throw error;return data as any;}});
  const d=q.data;
  return <Dialog open={open} onOpenChange={setOpen}><DialogTrigger asChild><Button size="sm" variant="outline"><Info className="ml-1 h-4 w-4"/>معلومات</Button></DialogTrigger><DialogContent dir="rtl" className="max-h-[92vh] max-w-6xl overflow-y-auto"><DialogHeader><DialogTitle>مركز وكالة {agency.name}</DialogTitle></DialogHeader>{q.isLoading?<Loader2 className="mx-auto h-6 w-6 animate-spin"/>:d?<div className="space-y-4"><div className="flex flex-wrap items-center gap-3 rounded-xl border p-4"><UserPhoto src={d.owner?.avatar_url} name={d.owner?.name} size="h-16 w-16"/><div><div className="text-lg font-bold">{d.agency?.name??agency.name}</div><div className="text-sm">المالك: {d.owner?.name} · <b dir="ltr">ID {d.owner?.legacy_id}</b></div><div className="mt-1 flex gap-2"><Badge variant={d.agency?.disabled_at?"destructive":"default"}>{d.agency?.disabled_at?"موقوفة":"نشطة"}</Badge><Badge variant="outline">المستوى {d.agency?.tree_depth??0}</Badge>{d.parent&&<Badge variant="secondary">تتبع: {d.parent.name}</Badge>}</div></div><div className="mr-auto text-xs text-muted-foreground"><div>تاريخ الإنشاء: <b dir="ltr">{new Date(d.agency?.created_at).toLocaleString("ar-EG-u-nu-latn")}</b></div><div>طريقة الإنشاء: <b>{d.agency?.creation_source==="app"?"المستخدم من التطبيق":d.agency?.creation_source==="admin"?"لوحة التحكم":"نظام قديم"}</b></div><div>كود الفتح: <b dir="ltr">{d.agency?.opening_code??"—"}</b></div><div>كود المضيف: <b dir="ltr">{d.agency?.host_invite_code??d.agency?.invite_code??"—"}</b></div><div>كود الفرع: <b dir="ltr">{d.agency?.agency_invite_code??"—"}</b></div></div></div><div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6"><Mini label="إجمالي اللؤلؤ" value={d.gross_pearls}/><Mini label="حصة الوكالة" value={d.commission_pearls}/><Mini label="الخسائر" value={d.losses_pearls}/><Mini label="كل المضيفين" value={d.hosts_total}/><Mini label="النشطون" value={d.hosts_active}/><Mini label="الجدد 30 يوم" value={d.hosts_new}/></div><Tabs defaultValue="income"><TabsList className="h-auto flex-wrap"><TabsTrigger value="income">الأرباح</TabsTrigger><TabsTrigger value="hosts">الأعضاء</TabsTrigger><TabsTrigger value="branches">الفروع</TabsTrigger><TabsTrigger value="tasks">المهام</TabsTrigger><TabsTrigger value="settlements">التسويات</TabsTrigger><TabsTrigger value="history">السجل</TabsTrigger></TabsList><TabsContent value="income"><div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">{Object.entries(d.earnings_by_source??{}).map(([k,v])=><div key={k} className="flex justify-between rounded-md border p-3"><span>{sourceLabel(k)}</span><b dir="ltr">{Number(v).toLocaleString("en-US")}</b></div>)}</div></TabsContent><TabsContent value="hosts"><HostMembers agencyId={agency.agency_id} hosts={d.hosts??[]} onDone={()=>q.refetch()}/></TabsContent><TabsContent value="branches"><DataList empty="لا توجد وكالات فرعية">{(d.children??[]).map((c:any)=><div key={c.id} className="flex items-center justify-between border-b p-3"><span><b>{c.name}</b> · ID {c.owner_legacy_id}</span><Badge variant={c.disabled_at?"destructive":"outline"}>L{c.depth}</Badge></div>)}</DataList></TabsContent><TabsContent value="tasks"><DataList empty="لا توجد مهام مسجلة">{(d.tasks??[]).map((t:any,i:number)=><div key={i} className="grid gap-2 border-b p-3 text-sm sm:grid-cols-5"><span>{t.name} · {t.legacy_id}</span><span>الأشخاص: <b>{t.unique_people}</b></span><span>مكالمات: <b>{t.calls_count}</b></span><span>رسائل: <b>{t.messages_count}</b></span><Badge variant={t.completed?"default":"secondary"}>{t.completed?(t.rewarded?"اكتملت وصُرفت":"اكتملت"):"لم تكتمل"}</Badge></div>)}</DataList></TabsContent><TabsContent value="settlements"><DataList empty="لا توجد تسويات">{(d.recent_settlements??[]).map((s:any)=><div key={s.id} className="grid gap-2 border-b p-3 text-sm sm:grid-cols-6"><span>{s.period_start} ← {s.period_end}</span><span>إجمالي <b>{Number(s.gross_pearls||0).toLocaleString("en-US")}</b></span><span>صافي <b>{Number(s.net_pearls||0).toLocaleString("en-US")}</b></span><span>تارجت <b>{Number(s.target_pearls||0).toLocaleString("en-US")}</b></span><Badge variant={s.target_achieved?"default":"secondary"}>{s.target_achieved?"محقق":"أقل من التارجت"}</Badge><Badge variant="outline">{s.automatic?"تلقائية":"يدوية"}</Badge></div>)}</DataList></TabsContent><TabsContent value="history"><DataList empty="لا يوجد سجل عمليات">{(d.audit_logs??[]).map((l:any)=><div key={l.id} className="flex flex-wrap items-center justify-between gap-2 border-b p-3 text-sm"><div><b>{actionLabel(l.action)}</b><div className="text-xs text-muted-foreground">{l.note||"بدون ملاحظة"} · {l.actor_email||"النظام"}</div></div><span dir="ltr" className="text-xs">{new Date(l.created_at).toLocaleString("ar-EG-u-nu-latn")}</span></div>)}</DataList></TabsContent></Tabs></div>:<p>لا توجد بيانات</p>}</DialogContent></Dialog>
}

function DataList({children,empty}:{children:React.ReactNode;empty:string}){const count=Array.isArray(children)?children.length:children?1:0;return <div className="max-h-80 overflow-auto rounded-lg border">{count?children:<div className="p-8 text-center text-sm text-muted-foreground">{empty}</div>}</div>}
function sourceLabel(v:string){const x=v.toLowerCase();return x.includes("message")?"الرسائل":x.includes("call")?"المكالمات":x.includes("room")&&x.includes("gift")?"هدايا الغرف":x.includes("gift")?"الهدايا الخاصة":v}
function actionLabel(v:string){return v.replaceAll("agency.","وكالة: ").replaceAll("host.","مضيف: ").replaceAll("_"," ")}
function HostMembers({agencyId,hosts,onDone}:{agencyId:string;hosts:any[];onDone:()=>void}){const[reason,setReason]=useState("تعديل عضوية المضيف من مركز الوكالات");const m=useMutation({mutationFn:async(h:any)=>{const{error}=await db.rpc("admin_set_host_removed",{p_agency_id:agencyId,p_user_id:h.user_id,p_removed:!h.removed_at,p_reason:reason});if(error)throw error;},onSuccess:()=>{toast.success("تم تحديث المضيف");onDone()},onError:(e:Error)=>toast.error(e.message)});return <div className="space-y-3"><Input value={reason} onChange={e=>setReason(e.target.value)} placeholder="سبب العملية"/><DataList empty="لا يوجد مضيفون">{hosts.map(h=><div key={h.user_id} className="flex flex-wrap items-center gap-3 border-b p-3"><UserPhoto src={h.avatar_url} name={h.name}/><div className="min-w-48 flex-1"><b>{h.name}</b><div className="text-xs text-muted-foreground">ID {h.legacy_id} · انضم {new Date(h.joined_at).toLocaleString("ar-EG-u-nu-latn")}</div><div className="text-xs">الطريقة: {h.joined_via==="app_code"?"كود من التطبيق":h.joined_via==="admin"?"إضافة من اللوحة":h.joined_via??"قديم"} · الكود: <b dir="ltr">{h.joined_code??"—"}</b></div><div className="text-xs">الدخل: {Number(h.earned_pearls||0).toLocaleString("en-US")} · نهاية المهمة: {h.task_ends_at?new Date(h.task_ends_at).toLocaleDateString("ar-EG-u-nu-latn"):"دائم"}</div></div><Badge variant={h.removed_at?"secondary":"default"}>{h.removed_at?"تمت الإزالة":"نشط"}</Badge><Button size="sm" variant={h.removed_at?"outline":"destructive"} disabled={reason.trim().length<3||m.isPending} onClick={()=>m.mutate(h)}>{h.removed_at?"إعادة العضوية":"إزالة"}</Button></div>)}</DataList></div>}

function Mini({label,value}:{label:string;value:any}){return <div className="rounded-lg border p-3"><div className="text-xs text-muted-foreground">{label}</div><div className="text-lg font-bold">{Number(value||0).toLocaleString("en-US")}</div></div>}
function SelectField({label,value,set,options}:{label:string;value:string;set:(v:string)=>void;options:string[][]}){return <div className="space-y-1"><Label>{label}</Label><select className="h-10 w-full rounded-md border bg-background px-3" value={value} onChange={e=>set(e.target.value)}>{options.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></div>}

function ManualSettlement({onDone}:{onDone:()=>void}){const today=new Date();const end=new Date(today);end.setDate(end.getDate()-1);const start=new Date(end);start.setDate(start.getDate()-6);const iso=(d:Date)=>d.toISOString().slice(0,10);const[from,setFrom]=useState(iso(start)),[to,setTo]=useState(iso(end)),[reason,setReason]=useState("تسوية يدوية من مركز الوكالات");const m=useMutation({mutationFn:async()=>{const{data,error}=await db.rpc("admin_run_yamo_agency_settlement",{p_from:from,p_to:to,p_reason:reason});if(error)throw error;return data},onSuccess:(d:any)=>{toast.success(`تمت معالجة ${d?.processed??0} وكالة بدون تكرار صرف`);onDone()},onError:(e:Error)=>toast.error(e.message)});return <Card><CardHeader><CardTitle>تشغيل تسوية يدوية آمنة</CardTitle><CardDescription>لن تُصرف نفس الوكالة مرتين لنفس الفترة؛ لكل عملية رقم مرجعي فريد.</CardDescription></CardHeader><CardContent className="grid gap-3 md:grid-cols-4"><Field label="من" value={from} set={setFrom} type="date"/><Field label="إلى" value={to} set={setTo} type="date"/><Field label="سبب التسوية" value={reason} set={setReason}/><Button className="self-end" disabled={!from||!to||reason.trim().length<3||m.isPending} onClick={()=>m.mutate()}>{m.isPending?<Loader2 className="ml-2 h-4 w-4 animate-spin"/>:<CalendarDays className="ml-2 h-4 w-4"/>}تنفيذ التسوية</Button></CardContent></Card>}

function TransferPanel({agencies,onDone}:{agencies:TreeAgency[];onDone:()=>void}) {
  const [host,setHost]=useState(""),[hostTarget,setHostTarget]=useState(""),[agency,setAgency]=useState(""),[parent,setParent]=useState("ROOT"),[reason,setReason]=useState("");
  const m=useMutation({mutationFn:async(i:{rpc:string;args:Record<string,unknown>})=>{const {error}=await db.rpc(i.rpc,i.args);if(error)throw error;},onSuccess:()=>{toast.success("تم النقل مع الاحتفاظ بالأرباح القديمة");onDone();},onError:(e:Error)=>toast.error(e.message)});
  return <div className="grid gap-4 lg:grid-cols-2"><Card><CardHeader><CardTitle>نقل مضيف</CardTitle><CardDescription>الأرباح القديمة تبقى للوكالة السابقة، والجديدة تحتسب للوكالة الجديدة.</CardDescription></CardHeader><CardContent className="space-y-3"><UserAccountLookup label="المضيف" value={host} onChange={setHost} placeholder="اكتب اسم المضيف أو ID"/><AgencySelect label="الوكالة الجديدة" value={hostTarget} set={setHostTarget} agencies={agencies}/><Reason value={reason} set={setReason}/><Button disabled={!host||!hostTarget||reason.length<3||m.isPending} onClick={()=>m.mutate({rpc:"admin_transfer_yamo_host",args:{p_host_legacy_id:host,p_to_agency_id:hostTarget,p_reason:reason}})}>نقل المضيف</Button></CardContent></Card>
  <Card><CardHeader><CardTitle>نقل وكالة وفرعها</CardTitle><CardDescription>ينقل الشجرة التابعة بالكامل مع منع الدوائر وتجاوز أقصى عمق.</CardDescription></CardHeader><CardContent className="space-y-3"><AgencySelect label="الوكالة المطلوب نقلها" value={agency} set={setAgency} agencies={agencies}/><AgencySelect label="الوكالة الأم الجديدة" value={parent} set={setParent} agencies={agencies.filter(a=>a.agency_id!==agency)} allowRoot/><Reason value={reason} set={setReason}/><Button disabled={!agency||reason.length<3||m.isPending} onClick={()=>m.mutate({rpc:"admin_transfer_yamo_agency",args:{p_agency_id:agency,p_new_parent_id:parent==="ROOT"?null:parent,p_reason:reason}})}>نقل الوكالة</Button></CardContent></Card></div>;
}

function ParentTermPanel({agencies,onDone}:{agencies:TreeAgency[];onDone:()=>void}){
  const[agency,setAgency]=useState(""),[parent,setParent]=useState("ROOT"),[days,setDays]=useState("30"),[permanent,setPermanent]=useState(false),[reason,setReason]=useState("ربط أو تجديد مدة الوكالة الفرعية");
  const m=useMutation({mutationFn:async()=>{const{error}=await db.rpc("admin_set_yamo_agency_parent_term",{p_agency_id:agency,p_parent_id:parent==="ROOT"?null:parent,p_duration_days:Number(days),p_permanent:permanent,p_reason:reason});if(error)throw error;},onSuccess:()=>{toast.success("تم حفظ تبعية الوكالة ومدتها");onDone();},onError:(e:Error)=>toast.error(e.message)});
  return <Card><CardHeader><CardTitle>تبعية الوكالة ومدة استفادة الوكالة الأم</CardTitle><CardDescription>بعد انتهاء المدة تتحول الوكالة الفرعية تلقائياً إلى وكالة رئيسية. اختر دائم لإلغاء تاريخ الانتهاء.</CardDescription></CardHeader><CardContent className="grid gap-3 md:grid-cols-2"><AgencySelect label="الوكالة الفرعية" value={agency} set={setAgency} agencies={agencies}/><AgencySelect label="الوكالة الأم" value={parent} set={setParent} agencies={agencies.filter(a=>a.agency_id!==agency)} allowRoot/><Field label="المدة بالأيام" value={days} set={setDays} type="number"/><label className="flex items-center justify-between rounded-md border p-3"><span>ربط دائم</span><Switch checked={permanent} onCheckedChange={setPermanent}/></label><div className="md:col-span-2"><Reason value={reason} set={setReason}/></div><Button className="md:col-span-2" disabled={!agency||(!permanent&&parent!=="ROOT"&&Number(days)<=0)||m.isPending} onClick={()=>m.mutate()}>حفظ المدة والتبعية</Button></CardContent></Card>
}

function AgencySelect({label,value,set,agencies,allowRoot=false}:{label:string;value:string;set:(v:string)=>void;agencies:TreeAgency[];allowRoot?:boolean}) { return <div className="space-y-1"><Label>{label}</Label><select className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={value} onChange={e=>set(e.target.value)}>{allowRoot&&<option value="ROOT">إدارة يامو الأم ← وكالة رئيسية</option>}{!allowRoot&&<option value="">اختر الوكالة</option>}{agencies.filter(a=>!a.disabled_at).map(a=><option key={a.agency_id} value={a.agency_id}>{"— ".repeat(Math.min(a.tree_depth,5))}{a.name} · القائد {a.owner_name} · ID {a.owner_legacy_id}</option>)}</select></div>; }
function Field({label,value,set,type="text"}:{label:string;value:string;set:(v:string)=>void;type?:string}) { return <div className="space-y-1"><Label>{label}</Label><Input type={type} value={value} onChange={e=>set(e.target.value)}/></div>; }
function Reason({value,set}:{value:string;set:(v:string)=>void}) { return <div className="space-y-1"><Label>سبب العملية</Label><Textarea value={value} onChange={e=>set(e.target.value)} placeholder="سبب واضح يظهر في سجل الإدارة"/></div>; }
