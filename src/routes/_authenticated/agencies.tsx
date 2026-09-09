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
import { Building2, Copy, GitBranch, KeyRound, Loader2, Plus, RefreshCw, Save, Search, Users } from "lucide-react";
import { toast } from "sonner";

type TreeAgency = {
  agency_id: string; parent_agency_id: string | null; name: string; owner_id: string;
  owner_legacy_id: string; owner_name: string; host_invite_code: string;
  agency_invite_code: string; tree_depth: number; commission_percent: number;
  disabled_at: string | null; direct_hosts: number; direct_commission_pearls: number; created_at: string;
};
type Rate = { depth: number; rate: number; active: boolean };
type AgencyConfig = { enabled: boolean; total_percent: number; maximum_depth: number;
  allow_sub_agencies: boolean; minimum_settlement_pearls: number; rates: Rate[] };
const db = supabase as any;

export const Route = createFileRoute("/_authenticated/agencies")({
  component: () => <PermissionGuard permission="agencies.read"><AgenciesPage /></PermissionGuard>,
});

function AgenciesPage() {
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [showDisabled, setShowDisabled] = useState(true);
  const tree = useQuery({ queryKey: ["yamo-agency-tree-admin"], queryFn: async () => {
    const { data, error } = await db.rpc("admin_get_yamo_agency_tree"); if (error) throw error;
    return (data ?? []) as TreeAgency[];
  }});
  const config = useQuery({ queryKey: ["yamo-agency-config-admin"], queryFn: async () => {
    const { data, error } = await db.rpc("admin_get_yamo_agency_config"); if (error) throw error;
    return (data ?? {}) as AgencyConfig;
  }});
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["yamo-agency-tree-admin"] });
    qc.invalidateQueries({ queryKey: ["yamo-agency-config-admin"] });
    qc.invalidateQueries({ queryKey: ["yamo-data", "admin_agency_settlements"] });
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
    </div><div className="flex gap-2"><CreateRootDialog onDone={refresh}/><Button variant="outline" onClick={refresh}><RefreshCw className="ml-2 h-4 w-4"/>تحديث</Button></div></div>
    <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <Stat icon={<Building2/>} label="الوكالات النشطة" value={totals.agencies}/>
      <Stat icon={<GitBranch/>} label="الوكالات الرئيسية" value={totals.roots}/>
      <Stat icon={<Users/>} label="المضيفون النشطون" value={totals.hosts}/>
      <Stat icon={<KeyRound/>} label="عمولات محفوظة" value={totals.commission.toLocaleString("en-US")}/>
    </div>
    <Tabs defaultValue="tree" className="space-y-4"><TabsList className="h-auto flex-wrap">
      <TabsTrigger value="tree">الشجرة والأكواد</TabsTrigger><TabsTrigger value="rates">النسب والإعدادات</TabsTrigger>
      <TabsTrigger value="transfers">النقل والإدارة</TabsTrigger><TabsTrigger value="settlements">التسويات</TabsTrigger>
    </TabsList>
    <TabsContent value="tree"><Card><CardHeader><CardTitle>الوكالات</CardTitle><CardDescription>كل فرع ظاهر تحت الوكالة التابعة له، مع الكودين الحقيقيين.</CardDescription></CardHeader><CardContent className="space-y-4">
      <div className="flex flex-wrap gap-3"><div className="relative min-w-64 flex-1"><Search className="absolute right-3 top-2.5 h-4 w-4 text-muted-foreground"/><Input className="pr-9" value={search} onChange={e=>setSearch(e.target.value)} placeholder="بحث بالاسم أو ID أو الكود"/></div><label className="flex items-center gap-2 text-sm"><Switch checked={showDisabled} onCheckedChange={setShowDisabled}/>عرض المعطلة</label></div>
      {tree.isLoading?<Loader2 className="mx-auto h-6 w-6 animate-spin"/>:tree.error?<div className="rounded-md border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">{(tree.error as Error).message}</div>:
      <div className="overflow-x-auto"><Table><TableHeader><TableRow><TableHead>الوكالة/المالك</TableHead><TableHead>المستوى</TableHead><TableHead>كود المضيف</TableHead><TableHead>كود فتح وكالة</TableHead><TableHead>المضيفون</TableHead><TableHead>العمولة</TableHead><TableHead>الحالة</TableHead><TableHead>إجراءات</TableHead></TableRow></TableHeader><TableBody>{visible.map(a=><AgencyRow key={a.agency_id} agency={a} onDone={refresh}/>)}</TableBody></Table></div>}
    </CardContent></Card></TabsContent>
    <TabsContent value="rates"><AgencySettings config={config.data} loading={config.isLoading} onDone={refresh}/></TabsContent>
    <TabsContent value="transfers"><TransferPanel agencies={tree.data??[]} onDone={refresh}/></TabsContent>
    <TabsContent value="settlements"><YamoDataModule title="تسويات الوكالات" description="اعتماد أو إلغاء الفترات المالية المسجلة" source="admin_agency_settlements"
      columns={[{key:"agency_name",label:"الوكالة"},{key:"period_start",label:"من"},{key:"period_end",label:"إلى"},{key:"host_pearls",label:"أرباح المضيفين"},{key:"commission_pearls",label:"حصة الوكالة"},{key:"commission_percent",label:"النسبة"},{key:"status",label:"الحالة"}]}
      actions={[{label:"تأكيد التسوية",rpc:"admin_set_agency_settlement_status",buildArgs:r=>({p_id:r.id,p_status:"settled",p_reason:"اعتماد من إدارة الوكالات"})},{label:"إلغاء التسوية",rpc:"admin_set_agency_settlement_status",tone:"destructive",buildArgs:r=>({p_id:r.id,p_status:"cancelled",p_reason:"إلغاء من إدارة الوكالات"})}]}/></TabsContent>
    </Tabs>
  </div>;
}

function Stat({icon,label,value}:{icon:React.ReactNode;label:string;value:string|number}) { return <Card><CardContent className="flex items-center gap-3 p-4"><span className="rounded-lg bg-primary/10 p-2 text-primary">{icon}</span><div><div className="text-xl font-bold">{value}</div><div className="text-xs text-muted-foreground">{label}</div></div></CardContent></Card>; }

function AgencyRow({agency:a,onDone}:{agency:TreeAgency;onDone:()=>void}) {
  const m=useMutation({mutationFn:async(i:{rpc:string;args:Record<string,unknown>})=>{const {error}=await db.rpc(i.rpc,i.args);if(error)throw error;},onSuccess:()=>{toast.success("تم التنفيذ والمزامنة مع التطبيق");onDone();},onError:(e:Error)=>toast.error(e.message)});
  const copy=(v:string)=>navigator.clipboard.writeText(v).then(()=>toast.success("تم نسخ الكود"));
  return <TableRow className={a.disabled_at?"opacity-60":""}><TableCell><div style={{paddingInlineStart:`${Math.min(a.tree_depth,8)*18}px`}} className="flex items-start gap-2">{a.tree_depth>0?<GitBranch className="mt-1 h-4 w-4 text-orange-500"/>:<Building2 className="mt-1 h-4 w-4 text-primary"/>}<div><div className="font-semibold">{a.name}</div><div className="text-xs text-muted-foreground">{a.owner_name} · ID {a.owner_legacy_id}</div></div></div></TableCell>
    <TableCell><Badge variant="outline">L{a.tree_depth}</Badge></TableCell><TableCell><Code value={a.host_invite_code} onCopy={copy}/></TableCell><TableCell><Code value={a.agency_invite_code} onCopy={copy}/></TableCell><TableCell>{a.direct_hosts}</TableCell><TableCell>{Number(a.direct_commission_pearls).toLocaleString("en-US")}</TableCell><TableCell><Badge variant={a.disabled_at?"destructive":"default"}>{a.disabled_at?"معطلة":"نشطة"}</Badge></TableCell>
    <TableCell><div className="flex flex-wrap gap-1"><Button size="sm" variant="outline" onClick={()=>m.mutate({rpc:"admin_regenerate_yamo_agency_code",args:{p_agency_id:a.agency_id,p_kind:"host"}})}>تجديد مضيف</Button><Button size="sm" variant="outline" onClick={()=>m.mutate({rpc:"admin_regenerate_yamo_agency_code",args:{p_agency_id:a.agency_id,p_kind:"agency"}})}>تجديد فرع</Button><Button size="sm" variant={a.disabled_at?"default":"destructive"} onClick={()=>m.mutate({rpc:"admin_set_agency_disabled",args:{p_agency_id:a.agency_id,p_disabled:!a.disabled_at,p_reason:a.disabled_at?"إعادة تفعيل من لوحة الشجرة":"تعطيل من لوحة الشجرة"}})}>{a.disabled_at?"تفعيل":"تعطيل"}</Button></div></TableCell></TableRow>;
}
function Code({value,onCopy}:{value:string;onCopy:(v:string)=>void}) { return <button className="flex items-center gap-1 font-mono text-xs text-primary" onClick={()=>onCopy(value)}><Copy className="h-3.5 w-3.5"/>{value||"—"}</button>; }

function CreateRootDialog({onDone}:{onDone:()=>void}) {
  const [open,setOpen]=useState(false),[owner,setOwner]=useState(""),[name,setName]=useState(""),[country,setCountry]=useState(""),[whatsapp,setWhatsapp]=useState("");
  const m=useMutation({mutationFn:async()=>{const {error}=await db.rpc("admin_create_root_yamo_agency",{p_owner_legacy_id:owner,p_name:name,p_country_code:country,p_whatsapp:whatsapp});if(error)throw error;},onSuccess:()=>{toast.success("تم فتح الوكالة وتوليد الكودين");setOpen(false);onDone();},onError:(e:Error)=>toast.error(e.message)});
  return <Dialog open={open} onOpenChange={setOpen}><DialogTrigger asChild><Button><Plus className="ml-2 h-4 w-4"/>فتح وكالة رئيسية</Button></DialogTrigger><DialogContent dir="rtl"><DialogHeader><DialogTitle>فتح وكالة رئيسية</DialogTitle></DialogHeader><div className="grid gap-3"><Field label="ID مالك الوكالة" value={owner} set={setOwner}/><Field label="اسم الوكالة" value={name} set={setName}/><Field label="كود الدولة (اختياري)" value={country} set={setCountry}/><Field label="واتساب (اختياري)" value={whatsapp} set={setWhatsapp}/></div><DialogFooter><Button variant="outline" onClick={()=>setOpen(false)}>إلغاء</Button><Button disabled={!owner.trim()||!name.trim()||m.isPending} onClick={()=>m.mutate()}>{m.isPending&&<Loader2 className="ml-2 h-4 w-4 animate-spin"/>}إنشاء وتوليد الأكواد</Button></DialogFooter></DialogContent></Dialog>;
}

function AgencySettings({config,loading,onDone}:{config?:AgencyConfig;loading:boolean;onDone:()=>void}) {
  const [total,setTotal]=useState("10"),[depth,setDepth]=useState("6"),[allow,setAllow]=useState(true),[rates,setRates]=useState<Rate[]>([]);
  useEffect(()=>{if(config){setTotal(String(config.total_percent??10));setDepth(String(config.maximum_depth??6));setAllow(config.allow_sub_agencies!==false);setRates(config.rates??[]);}},[config]);
  const save=useMutation({mutationFn:async()=>{const active=rates.filter(r=>r.active).map(r=>({depth:r.depth,rate:Number(r.rate)}));const {error}=await db.rpc("admin_save_yamo_agency_settings",{p_total_percent:Number(total),p_maximum_depth:Number(depth),p_allow_sub_agencies:allow,p_rates:active});if(error)throw error;},onSuccess:()=>{toast.success("تم حفظ النسب؛ العمليات الجديدة فقط ستستخدمها");onDone();},onError:(e:Error)=>toast.error(e.message)});
  const setRate=(d:number,v:string)=>setRates(old=>[...old.filter(r=>r.depth!==d),{depth:d,rate:Number(v||0),active:true}].sort((a,b)=>a.depth-b.depth));
  if(loading)return <Loader2 className="mx-auto h-6 w-6 animate-spin"/>;
  return <Card><CardHeader><CardTitle>نسب شجرة الأرباح</CardTitle><CardDescription>المستوى 0 هو وكالة المضيف المباشرة، ثم الوكالة الأم. السجلات القديمة لا تتغير.</CardDescription></CardHeader><CardContent className="space-y-5"><div className="grid gap-4 md:grid-cols-3"><Field label="إجمالي حصة الوكالات %" value={total} set={setTotal} type="number"/><Field label="أقصى عمق للشجرة" value={depth} set={setDepth} type="number"/><label className="flex items-center justify-between rounded-md border p-3"><span>السماح بفتح فروع</span><Switch checked={allow} onCheckedChange={setAllow}/></label></div><div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{Array.from({length:Math.min(Math.max(Number(depth)||1,1),10)},(_,d)=>{const r=rates.find(x=>x.depth===d);return <Field key={d} label={d===0?"الوكالة المباشرة %":`المستوى الأعلى ${d} %`} value={String(r?.rate??0)} set={v=>setRate(d,v)} type="number"/>;})}</div><div className="flex items-center justify-between rounded-md bg-muted p-3 text-sm"><span>مجموع نسب المستويات</span><strong>{rates.filter(r=>r.active).reduce((n,r)=>n+Number(r.rate||0),0).toFixed(2)}% من حد {Number(total||0).toFixed(2)}%</strong></div><Button onClick={()=>save.mutate()} disabled={save.isPending}><Save className="ml-2 h-4 w-4"/>حفظ وتطبيق على العمليات الجديدة</Button></CardContent></Card>;
}

function TransferPanel({agencies,onDone}:{agencies:TreeAgency[];onDone:()=>void}) {
  const [host,setHost]=useState(""),[hostTarget,setHostTarget]=useState(""),[agency,setAgency]=useState(""),[parent,setParent]=useState("ROOT"),[reason,setReason]=useState("");
  const m=useMutation({mutationFn:async(i:{rpc:string;args:Record<string,unknown>})=>{const {error}=await db.rpc(i.rpc,i.args);if(error)throw error;},onSuccess:()=>{toast.success("تم النقل مع الاحتفاظ بالأرباح القديمة");onDone();},onError:(e:Error)=>toast.error(e.message)});
  return <div className="grid gap-4 lg:grid-cols-2"><Card><CardHeader><CardTitle>نقل مضيف</CardTitle><CardDescription>الأرباح القديمة تبقى للوكالة السابقة، والجديدة تحتسب للوكالة الجديدة.</CardDescription></CardHeader><CardContent className="space-y-3"><Field label="ID المضيف" value={host} set={setHost}/><AgencySelect label="الوكالة الجديدة" value={hostTarget} set={setHostTarget} agencies={agencies}/><Reason value={reason} set={setReason}/><Button disabled={!host||!hostTarget||reason.length<3||m.isPending} onClick={()=>m.mutate({rpc:"admin_transfer_yamo_host",args:{p_host_legacy_id:host,p_to_agency_id:hostTarget,p_reason:reason}})}>نقل المضيف</Button></CardContent></Card>
  <Card><CardHeader><CardTitle>نقل وكالة وفرعها</CardTitle><CardDescription>ينقل الشجرة التابعة بالكامل مع منع الدوائر وتجاوز أقصى عمق.</CardDescription></CardHeader><CardContent className="space-y-3"><AgencySelect label="الوكالة المطلوب نقلها" value={agency} set={setAgency} agencies={agencies}/><AgencySelect label="الوكالة الأم الجديدة" value={parent} set={setParent} agencies={agencies.filter(a=>a.agency_id!==agency)} allowRoot/><Reason value={reason} set={setReason}/><Button disabled={!agency||reason.length<3||m.isPending} onClick={()=>m.mutate({rpc:"admin_transfer_yamo_agency",args:{p_agency_id:agency,p_new_parent_id:parent==="ROOT"?null:parent,p_reason:reason}})}>نقل الوكالة</Button></CardContent></Card></div>;
}

function AgencySelect({label,value,set,agencies,allowRoot=false}:{label:string;value:string;set:(v:string)=>void;agencies:TreeAgency[];allowRoot?:boolean}) { return <div className="space-y-1"><Label>{label}</Label><select className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={value} onChange={e=>set(e.target.value)}>{allowRoot&&<option value="ROOT">بدون أم — وكالة رئيسية</option>}{!allowRoot&&<option value="">اختر الوكالة</option>}{agencies.filter(a=>!a.disabled_at).map(a=><option key={a.agency_id} value={a.agency_id}>{"— ".repeat(Math.min(a.tree_depth,5))}{a.name} · {a.owner_legacy_id}</option>)}</select></div>; }
function Field({label,value,set,type="text"}:{label:string;value:string;set:(v:string)=>void;type?:string}) { return <div className="space-y-1"><Label>{label}</Label><Input type={type} value={value} onChange={e=>set(e.target.value)}/></div>; }
function Reason({value,set}:{value:string;set:(v:string)=>void}) { return <div className="space-y-1"><Label>سبب العملية</Label><Textarea value={value} onChange={e=>set(e.target.value)} placeholder="سبب واضح يظهر في سجل الإدارة"/></div>; }
