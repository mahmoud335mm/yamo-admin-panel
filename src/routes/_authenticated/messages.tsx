import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery } from "@tanstack/react-query";
import { AlertTriangle, CheckCheck, Eye, FileAudio, Image as ImageIcon, Loader2, LockKeyhole, MessageSquareText, Search, ShieldCheck, UserRound } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { yamoRpc } from "@/lib/yamo-admin";
import { formatDateTime, formatInteger } from "@/lib/format";

type Thread = { peer_legacy_id:string; peer_name:string; peer_avatar_url?:string|null; last_body?:string|null; last_kind?:string|null; last_sent_at?:string|null; message_count:number; deleted_count:number };
type Message = { message_id:string; sender_legacy_id:string; sender_name:string; sender_avatar_url?:string|null; receiver_legacy_id:string; receiver_name:string; receiver_avatar_url?:string|null; body?:string|null; kind:string; media_url?:string|null; duration_seconds?:number|null; earning_pearls?:number|null; sent_at?:string|null; read_at?:string|null; deleted_at?:string|null; deleted_by_legacy_id?:string|null };
type UserResult = { legacy_id:string; display_name:string; avatar_url?:string|null; gender?:string|null; message_count:number };

export const Route = createFileRoute("/_authenticated/messages")({ component: MessagesArchive });

function rows<T>(value:unknown):T[]{
  if(Array.isArray(value)) return value as T[];
  if(value && typeof value === "object" && Array.isArray((value as {rows?:unknown[]}).rows)) return (value as {rows:T[]}).rows;
  return [];
}

function Avatar({url,name,size="md"}:{url?:string|null;name:string;size?:"sm"|"md"|"lg"}){
  const dimensions=size==="lg"?"h-14 w-14":size==="sm"?"h-8 w-8":"h-11 w-11";
  return url?<img src={url} alt={`صورة ${name}`} className={`${dimensions} shrink-0 rounded-2xl object-cover ring-1 ring-border`}/>:<div className={`${dimensions} grid shrink-0 place-items-center rounded-2xl bg-gradient-to-br from-orange-500 to-violet-600 text-sm font-black text-white`}>{name.trim().charAt(0)||<UserRound className="h-4 w-4"/>}</div>;
}

function MessagesArchive(){
  const [draftId,setDraftId]=useState("");
  const [userId,setUserId]=useState("");
  const [days,setDays]=useState("30");
  const [selectedPeer,setSelectedPeer]=useState<string|null>(null);
  const [previewImage,setPreviewImage]=useState<string|null>(null);
  const search=useMutation({mutationFn:(legacyId:string)=>yamoRpc<unknown>("admin_search_message_user",{p_legacy_id:legacyId}),onSuccess:(raw)=>{const first=rows<UserResult>(raw)[0];setUserId(first?.legacy_id??"");setSelectedPeer(null)}});
  const userQuery=useQuery({queryKey:["admin-message-user",userId],queryFn:()=>yamoRpc<unknown>("admin_search_message_user",{p_legacy_id:userId}),enabled:Boolean(userId)});
  const user=rows<UserResult>(userQuery.data)[0];
  const threadsQuery=useQuery({queryKey:["admin-message-threads",userId,days],queryFn:()=>yamoRpc<unknown>("admin_get_message_threads",{p_user_legacy_id:userId,p_days:Number(days)}),enabled:Boolean(userId)});
  const threads=rows<Thread>(threadsQuery.data);
  const activePeer=selectedPeer??threads[0]?.peer_legacy_id??null;
  const conversationQuery=useQuery({queryKey:["admin-message-conversation",userId,activePeer,days],queryFn:()=>yamoRpc<unknown>("admin_get_message_conversation",{p_user_legacy_id:userId,p_peer_legacy_id:activePeer,p_days:Number(days),p_access_reason:"مراجعة إدارية من قسم الرسائل"}),enabled:Boolean(userId&&activePeer)});
  const messages=rows<Message>(conversationQuery.data);
  const currentThread=threads.find((thread)=>thread.peer_legacy_id===activePeer);
  const deletedTotal=useMemo(()=>threads.reduce((sum,thread)=>sum+Number(thread.deleted_count||0),0),[threads]);
  const runSearch=()=>{const clean=draftId.trim();if(clean)search.mutate(clean)};
  return <div className="space-y-5">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><h1 className="text-2xl font-black">أرشيف الرسائل والمحادثات</h1><p className="text-sm text-muted-foreground">عرض إداري محمي للرسائل والوسائط الأصلية بما فيها العناصر المحذوفة من المستخدمين</p></div><Badge variant="outline" className="gap-2 px-3 py-1.5"><ShieldCheck className="h-4 w-4 text-emerald-500"/>عرض فقط ومسجل</Badge></div>
    <Card><CardContent className="grid gap-3 p-4 md:grid-cols-[1fr_180px_auto]"><div className="relative"><Search className="absolute right-3 top-3 h-4 w-4 text-muted-foreground"/><Input value={draftId} onChange={(event)=>setDraftId(event.target.value.replace(/[^A-Za-z0-9_-]/g,""))} onKeyDown={(event)=>event.key==="Enter"&&runSearch()} placeholder="اكتب ID المستخدم — أرقام أو حروف إنجليزية" className="pr-10" inputMode="text" autoCapitalize="none" autoCorrect="off" spellCheck={false}/></div><Select value={days} onValueChange={setDays}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent><SelectItem value="7">آخر 7 أيام</SelectItem><SelectItem value="30">آخر 30 يومًا</SelectItem><SelectItem value="90">آخر 90 يومًا</SelectItem><SelectItem value="3650">كل الرسائل</SelectItem></SelectContent></Select><Button onClick={runSearch} disabled={!draftId.trim()||search.isPending} className="gap-2">{search.isPending?<Loader2 className="h-4 w-4 animate-spin"/>:<Eye className="h-4 w-4"/>}عرض السجل</Button></CardContent></Card>
    {search.isError&&<div className="rounded-xl border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">تعذر البحث: {(search.error as Error).message}</div>}
    {search.isSuccess&&!userId&&<div className="rounded-xl border p-6 text-center text-muted-foreground">لم يتم العثور على مستخدم بهذا الـ ID</div>}
    {user&&<div className="grid gap-4 xl:grid-cols-[290px_1fr]">
      <Card className="overflow-hidden"><CardHeader className="border-b bg-gradient-to-l from-violet-500/10 to-orange-500/10 p-4"><div className="flex items-center gap-3"><Avatar url={user.avatar_url} name={user.display_name} size="lg"/><div><CardTitle>{user.display_name}</CardTitle><p className="mt-1 text-xs text-muted-foreground">ID {user.legacy_id} · {user.gender==="female"?"أنثى":user.gender==="male"?"ذكر":"غير محدد"}</p></div></div><div className="mt-3 flex gap-2"><Badge variant="secondary">{formatInteger(user.message_count)} رسالة</Badge><Badge variant="outline">{formatInteger(threads.length)} محادثة</Badge>{deletedTotal>0&&<Badge variant="destructive">{formatInteger(deletedTotal)} محذوفة</Badge>}</div></CardHeader><ScrollArea className="h-[560px]"><div className="divide-y">{threadsQuery.isLoading&&<div className="grid place-items-center p-12"><Loader2 className="h-6 w-6 animate-spin"/></div>}{threads.map((thread)=><button key={thread.peer_legacy_id} onClick={()=>setSelectedPeer(thread.peer_legacy_id)} className={`flex w-full items-center gap-3 p-3 text-right transition-colors hover:bg-muted/70 ${activePeer===thread.peer_legacy_id?"bg-violet-500/10":""}`}><Avatar url={thread.peer_avatar_url} name={thread.peer_name}/><span className="min-w-0 flex-1"><strong className="block truncate text-sm">{thread.peer_name}</strong><span className="mt-1 block truncate text-xs text-muted-foreground">{thread.last_kind==="image"?"صورة":thread.last_kind==="voice"?"رسالة صوتية":thread.last_body||"بدون نص"}</span></span><span className="text-left text-[10px] text-muted-foreground">{thread.last_sent_at?formatDateTime(thread.last_sent_at):"—"}<small className="mt-1 block">{formatInteger(thread.message_count)}</small></span></button>)}{!threadsQuery.isLoading&&threads.length===0&&<div className="p-10 text-center text-sm text-muted-foreground">لا توجد محادثات في المدة المحددة</div>}</div></ScrollArea></Card>
      <Card className="overflow-hidden"><CardHeader className="flex flex-row items-center justify-between gap-3 border-b p-4"><div><CardTitle className="flex items-center gap-2"><MessageSquareText className="h-5 w-5 text-violet-500"/>{user.display_name} × {currentThread?.peer_name??"اختر محادثة"}</CardTitle><p className="mt-1 text-xs text-muted-foreground">ID {user.legacy_id}{activePeer?` ↔ ID ${activePeer}`:""}</p></div><div className="flex items-center gap-2 text-xs text-muted-foreground"><LockKeyhole className="h-4 w-4 text-emerald-500"/>تم تسجيل فتح المحادثة</div></CardHeader><ScrollArea className="h-[515px] bg-muted/25"><div className="flex min-h-full flex-col gap-3 p-5">{conversationQuery.isLoading&&<div className="grid flex-1 place-items-center"><Loader2 className="h-7 w-7 animate-spin"/></div>}{messages.map((message)=>{const mine=message.sender_legacy_id===user.legacy_id;const deleted=Boolean(message.deleted_at);return <div key={message.message_id} className={`flex max-w-[82%] gap-2 ${mine?"self-start":"self-end flex-row-reverse"}`}><Avatar url={message.sender_avatar_url} name={message.sender_name} size="sm"/><div className={`rounded-2xl p-3 shadow-sm ${deleted?"border border-dashed border-red-400/50 bg-red-500/10":mine?"bg-gradient-to-br from-violet-600 to-fuchsia-600 text-white":"border bg-card"}`}>{deleted&&<div className="mb-2 flex items-center gap-1 text-xs font-bold text-red-500"><AlertTriangle className="h-3.5 w-3.5"/>حذفها المستخدم {message.deleted_at?formatDateTime(message.deleted_at):""}</div>}{message.kind==="image"&&message.media_url&&<button type="button" onClick={()=>setPreviewImage(message.media_url!)} className="mb-2 block overflow-hidden rounded-xl"><img src={message.media_url} alt="صورة داخل المحادثة" className="max-h-64 w-full object-contain"/></button>}{message.kind==="voice"&&<div className="mb-2 flex min-w-52 items-center gap-3 rounded-xl bg-black/10 p-3"><FileAudio className="h-5 w-5"/><div className="h-1 flex-1 rounded-full bg-current/20"><div className="h-1 w-2/3 rounded-full bg-current/60"/></div><span className="text-xs">{message.duration_seconds??0}ث</span></div>}{message.media_url&&message.kind!=="image"&&message.kind!=="voice"&&<a href={message.media_url} target="_blank" rel="noreferrer" className="mb-2 flex items-center gap-2 underline"><ImageIcon className="h-4 w-4"/>فتح المرفق</a>}{message.body&&<p className="whitespace-pre-wrap text-sm">{message.body}</p>}<div className={`mt-2 flex flex-wrap items-center justify-end gap-2 text-[10px] ${mine&&!deleted?"text-white/70":"text-muted-foreground"}`}><span>{message.sender_name}</span><span>{message.sent_at?formatDateTime(message.sent_at):"—"}</span>{message.read_at&&<CheckCheck className="h-3.5 w-3.5"/>}{Number(message.earning_pearls??0)>0&&<span className="font-bold text-emerald-500">+{formatInteger(message.earning_pearls)} لؤلؤ</span>}</div></div></div>})}{!conversationQuery.isLoading&&activePeer&&messages.length===0&&<div className="grid flex-1 place-items-center text-sm text-muted-foreground">لا توجد رسائل في المدة المحددة</div>}</div></ScrollArea><div className="flex items-center gap-2 border-t bg-card p-3 text-xs text-muted-foreground"><ShieldCheck className="h-4 w-4 text-emerald-500"/>عرض فقط — لا يمكن للمسؤول تعديل الرسائل أو الإرسال باسم المستخدمين</div></Card>
    </div>}
    {!user&&!search.isPending&&<Card><CardContent className="grid min-h-80 place-items-center text-center"><div><MessageSquareText className="mx-auto mb-3 h-10 w-10 text-violet-500"/><h2 className="font-bold">ابحث عن مستخدم لعرض محادثاته</h2><p className="mt-2 text-sm text-muted-foreground">كل عملية بحث وفتح محادثة تُحفظ تلقائيًا في سجل الإدارة</p></div></CardContent></Card>}
    <Dialog open={Boolean(previewImage)} onOpenChange={(open)=>!open&&setPreviewImage(null)}><DialogContent className="max-w-4xl"><DialogHeader><DialogTitle>معاينة الصورة الأصلية</DialogTitle></DialogHeader>{previewImage&&<img src={previewImage} alt="معاينة الصورة الأصلية" className="max-h-[75vh] w-full rounded-xl object-contain"/>}</DialogContent></Dialog>
  </div>;
}
