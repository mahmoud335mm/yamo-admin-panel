-- Yamo Admin V211 — immutable message/media archive and audited conversation viewer.
-- Additive migration. Run after the existing V210 migrations.

begin;

insert into public.yamo_admin_permissions(permission,label_ar,category)
values('messages.read','عرض أرشيف الرسائل والوسائط','content')
on conflict(permission) do update set label_ar=excluded.label_ar,category=excluded.category;

insert into public.yamo_admin_role_permissions(role,permission) values
  ('super_admin','messages.read'),('admin','messages.read'),('auditor','messages.read')
on conflict do nothing;

alter table public.yamo_messages
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists earning_pearls bigint not null default 0,
  add column if not exists archived_at timestamptz not null default now();

create table if not exists public.yamo_message_archive (
  message_id uuid primary key,
  sender_id uuid not null,
  receiver_id uuid not null,
  body text,
  kind text not null,
  media_url text,
  duration_seconds integer not null default 0,
  earning_pearls bigint not null default 0,
  sent_at timestamptz not null,
  read_at timestamptz,
  deleted_at timestamptz,
  deleted_by uuid,
  delete_reason text,
  snapshot jsonb not null default '{}'::jsonb,
  first_archived_at timestamptz not null default now(),
  last_archived_at timestamptz not null default now()
);
create index if not exists yamo_message_archive_users_idx on public.yamo_message_archive(sender_id,receiver_id,sent_at desc);
create index if not exists yamo_message_archive_deleted_idx on public.yamo_message_archive(deleted_at desc) where deleted_at is not null;
alter table public.yamo_message_archive enable row level security;
revoke all on public.yamo_message_archive from public,anon,authenticated;

create or replace function public.yamo_archive_message_snapshot()
returns trigger language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_row public.yamo_messages%rowtype;
begin
  if tg_op='DELETE' then v_row:=old; else v_row:=new; end if;
  insert into public.yamo_message_archive(
    message_id,sender_id,receiver_id,body,kind,media_url,duration_seconds,
    earning_pearls,sent_at,read_at,deleted_at,deleted_by,delete_reason,snapshot)
  values(
    v_row.id,v_row.sender_id,v_row.receiver_id,v_row.body,v_row.kind,v_row.media_url,
    coalesce(v_row.duration_seconds,0),coalesce(v_row.earning_pearls,0),v_row.sent_at,
    v_row.read_at,case when tg_op='DELETE' then coalesce(v_row.deleted_at,now()) else v_row.deleted_at end,
    v_row.deleted_by,case when tg_op='DELETE' then coalesce(v_row.delete_reason,'hard_delete_blocked') else v_row.delete_reason end,
    to_jsonb(v_row))
  on conflict(message_id) do update set
    body=excluded.body,kind=excluded.kind,media_url=excluded.media_url,
    duration_seconds=excluded.duration_seconds,earning_pearls=excluded.earning_pearls,
    read_at=excluded.read_at,deleted_at=coalesce(excluded.deleted_at,public.yamo_message_archive.deleted_at),
    deleted_by=coalesce(excluded.deleted_by,public.yamo_message_archive.deleted_by),
    delete_reason=coalesce(excluded.delete_reason,public.yamo_message_archive.delete_reason),
    snapshot=excluded.snapshot,last_archived_at=now();
  if tg_op='DELETE' then return null; end if;
  return new;
end $$;
revoke all on function public.yamo_archive_message_snapshot() from public,anon,authenticated;

drop trigger if exists yamo_message_archive_after_write on public.yamo_messages;
create trigger yamo_message_archive_after_write after insert or update on public.yamo_messages
for each row execute function public.yamo_archive_message_snapshot();
drop trigger if exists yamo_message_prevent_hard_delete on public.yamo_messages;
create trigger yamo_message_prevent_hard_delete before delete on public.yamo_messages
for each row execute function public.yamo_archive_message_snapshot();

insert into public.yamo_message_archive(
  message_id,sender_id,receiver_id,body,kind,media_url,duration_seconds,
  earning_pearls,sent_at,read_at,deleted_at,deleted_by,delete_reason,snapshot)
select m.id,m.sender_id,m.receiver_id,m.body,m.kind,m.media_url,coalesce(m.duration_seconds,0),
  coalesce(m.earning_pearls,0),m.sent_at,m.read_at,m.deleted_at,m.deleted_by,m.delete_reason,to_jsonb(m)
from public.yamo_messages m
on conflict(message_id) do nothing;

create or replace function public.delete_my_yamo_message(p_message_id uuid,p_reason text default 'user_deleted')
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  update public.yamo_messages set deleted_at=coalesce(deleted_at,now()),deleted_by=auth.uid(),delete_reason=left(coalesce(nullif(trim(p_reason),''),'user_deleted'),120)
  where id=p_message_id and sender_id=auth.uid();
  return found;
end $$;
revoke all on function public.delete_my_yamo_message(uuid,text) from public,anon;
grant execute on function public.delete_my_yamo_message(uuid,text) to authenticated;

create or replace function public.admin_search_message_user(p_legacy_id text)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_admin uuid; v_result jsonb;
begin
  v_admin:=public.yamo_admin_require('messages.read');
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_result from (
    select p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,p.avatar_url,p.gender,
      (select count(*) from public.yamo_message_archive a where a.sender_id=p.id or a.receiver_id=p.id) message_count
    from public.profiles p where lower(trim(p.legacy_id))=lower(trim(p_legacy_id)) limit 1
  ) x;
  perform public.yamo_admin_log('messages.user_search','profile',trim(p_legacy_id),null,jsonb_build_object('result_count',jsonb_array_length(v_result)),'بحث في أرشيف الرسائل');
  return v_result;
end $$;
revoke all on function public.admin_search_message_user(text) from public,anon;
grant execute on function public.admin_search_message_user(text) to authenticated;

create or replace function public.admin_get_message_threads(p_user_legacy_id text,p_days integer default 30)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_user uuid; v_result jsonb;
begin
  perform public.yamo_admin_require('messages.read');
  select id into v_user from public.profiles where lower(trim(legacy_id))=lower(trim(p_user_legacy_id)) limit 1;
  if v_user is null then raise exception 'user_not_found'; end if;
  with base as (
    select a.*,case when a.sender_id=v_user then a.receiver_id else a.sender_id end peer_id
    from public.yamo_message_archive a where (a.sender_id=v_user or a.receiver_id=v_user)
      and a.sent_at>=now()-make_interval(days=>least(greatest(coalesce(p_days,30),1),3650))
  ), ranked as (select b.*,row_number() over(partition by peer_id order by sent_at desc) rn from base b), totals as (
    select peer_id,count(*) message_count,count(*) filter(where deleted_at is not null) deleted_count from base group by peer_id
  )
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_sent_at desc),'[]'::jsonb) into v_result from (
    select p.legacy_id peer_legacy_id,coalesce(p.display_name,p.legacy_id) peer_name,p.avatar_url peer_avatar_url,
      r.body last_body,r.kind last_kind,r.sent_at last_sent_at,t.message_count,t.deleted_count
    from ranked r join totals t using(peer_id) join public.profiles p on p.id=r.peer_id where r.rn=1
  ) x;
  return v_result;
end $$;
revoke all on function public.admin_get_message_threads(text,integer) from public,anon;
grant execute on function public.admin_get_message_threads(text,integer) to authenticated;

create or replace function public.admin_get_message_conversation(p_user_legacy_id text,p_peer_legacy_id text,p_days integer default 30,p_access_reason text default 'admin_review')
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_user uuid;v_peer uuid;v_result jsonb;v_admin uuid;
begin
  v_admin:=public.yamo_admin_require('messages.read');
  select id into v_user from public.profiles where lower(trim(legacy_id))=lower(trim(p_user_legacy_id)) limit 1;
  select id into v_peer from public.profiles where lower(trim(legacy_id))=lower(trim(p_peer_legacy_id)) limit 1;
  if v_user is null or v_peer is null then raise exception 'user_not_found'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.sent_at),'[]'::jsonb) into v_result from (
    select a.message_id,sp.legacy_id sender_legacy_id,coalesce(sp.display_name,sp.legacy_id) sender_name,sp.avatar_url sender_avatar_url,
      rp.legacy_id receiver_legacy_id,coalesce(rp.display_name,rp.legacy_id) receiver_name,rp.avatar_url receiver_avatar_url,
      a.body,a.kind,a.media_url,a.duration_seconds,a.earning_pearls,a.sent_at,a.read_at,a.deleted_at,dp.legacy_id deleted_by_legacy_id
    from public.yamo_message_archive a join public.profiles sp on sp.id=a.sender_id join public.profiles rp on rp.id=a.receiver_id
    left join public.profiles dp on dp.id=a.deleted_by
    where ((a.sender_id=v_user and a.receiver_id=v_peer) or (a.sender_id=v_peer and a.receiver_id=v_user))
      and a.sent_at>=now()-make_interval(days=>least(greatest(coalesce(p_days,30),1),3650))
  ) x;
  perform public.yamo_admin_log('messages.conversation_view','conversation',least(p_user_legacy_id,p_peer_legacy_id)||':'||greatest(p_user_legacy_id,p_peer_legacy_id),null,
    jsonb_build_object('message_count',jsonb_array_length(v_result),'days',p_days),left(coalesce(nullif(trim(p_access_reason),''),'admin_review'),240));
  return v_result;
end $$;
revoke all on function public.admin_get_message_conversation(text,text,integer,text) from public,anon;
grant execute on function public.admin_get_message_conversation(text,text,integer,text) to authenticated;

-- Chat media is immutable: neither user nor normal service operations can
-- physically delete it while this trigger is enabled.
create or replace function public.yamo_preserve_chat_media()
returns trigger language plpgsql security definer set search_path=public,storage,auth,pg_temp as $$
begin
  if old.bucket_id='chat-media' then
    raise exception 'chat_media_is_admin_retained';
  end if;
  return old;
end $$;
drop trigger if exists yamo_preserve_chat_media_delete on storage.objects;
create trigger yamo_preserve_chat_media_delete before delete on storage.objects
for each row execute function public.yamo_preserve_chat_media();

commit;
notify pgrst,'reload schema';
