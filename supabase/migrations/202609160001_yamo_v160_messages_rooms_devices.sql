-- Yamo production sync patch — 2026-09-16
-- Messages/presence/pins/hearts, manual host sync, room cup shifts,
-- sequential room ids, complete device release, and visible ban numbers.
begin;

-- ---------------------------------------------------------------------------
-- Real presence used by Messages/Calls. Heartbeats expire quickly so a stale
-- boolean can never leave the green online dot stuck on indefinitely.
-- ---------------------------------------------------------------------------
create table if not exists public.yamo_presence_v160 (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_online boolean not null default false,
  last_heartbeat_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
alter table public.yamo_presence_v160 enable row level security;
revoke all on public.yamo_presence_v160 from public,anon,authenticated;

create or replace function public.set_yamo_presence_v160(p_online boolean)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  insert into public.yamo_presence_v160(user_id,is_online,last_heartbeat_at,last_seen_at)
  values(auth.uid(),coalesce(p_online,false),now(),now())
  on conflict(user_id) do update set
    is_online=excluded.is_online,
    last_heartbeat_at=now(),
    last_seen_at=now();
  return true;
end $$;
revoke all on function public.set_yamo_presence_v160(boolean) from public,anon;
grant execute on function public.set_yamo_presence_v160(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Per-user conversation pinning + male/female chat-heart friendship layer.
-- ---------------------------------------------------------------------------
create table if not exists public.yamo_conversation_preferences_v160 (
  user_id uuid not null references auth.users(id) on delete cascade,
  peer_id uuid not null references auth.users(id) on delete cascade,
  pinned boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key(user_id,peer_id),
  check(user_id<>peer_id)
);
create table if not exists public.yamo_chat_hearts_v160 (
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  heart_count bigint not null default 0 check(heart_count>=0),
  updated_at timestamptz not null default now(),
  primary key(user_a,user_b),
  check(user_a<user_b)
);
create table if not exists public.yamo_friendships_v160 (
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  source text not null default 'chat_hearts',
  primary key(user_a,user_b),
  check(user_a<user_b)
);
alter table public.yamo_conversation_preferences_v160 enable row level security;
alter table public.yamo_chat_hearts_v160 enable row level security;
alter table public.yamo_friendships_v160 enable row level security;
revoke all on public.yamo_conversation_preferences_v160,public.yamo_chat_hearts_v160,public.yamo_friendships_v160 from public,anon,authenticated;

create or replace function public.set_yamo_conversation_pinned_v160(p_peer_legacy_id text,p_pinned boolean)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare peer uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select id into peer from public.profiles where lower(trim(legacy_id))=lower(trim(p_peer_legacy_id)) limit 1;
  if peer is null or peer=auth.uid() then raise exception 'peer_not_found'; end if;
  insert into public.yamo_conversation_preferences_v160(user_id,peer_id,pinned,updated_at)
  values(auth.uid(),peer,coalesce(p_pinned,false),now())
  on conflict(user_id,peer_id) do update set pinned=excluded.pinned,updated_at=now();
  return true;
end $$;
revoke all on function public.set_yamo_conversation_pinned_v160(text,boolean) from public,anon;
grant execute on function public.set_yamo_conversation_pinned_v160(text,boolean) to authenticated;

create or replace function public.register_yamo_chat_heart_v160(p_peer_legacy_id text,p_mutual_follow boolean default false)
returns table(heart_count bigint,became_friends boolean)
language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare me uuid:=auth.uid(); peer uuid; g_me text; g_peer text; a uuid; b uuid; v bigint:=0; created_friend boolean:=false;
begin
  if me is null then raise exception 'authentication_required'; end if;
  select id,lower(coalesce(gender,'')) into peer,g_peer from public.profiles where lower(trim(legacy_id))=lower(trim(p_peer_legacy_id)) limit 1;
  select lower(coalesce(gender,'')) into g_me from public.profiles where id=me;
  if peer is null or peer=me then raise exception 'peer_not_found'; end if;
  a:=least(me,peer); b:=greatest(me,peer);
  select h.heart_count into v from public.yamo_chat_hearts_v160 h where h.user_a=a and h.user_b=b;
  v:=coalesce(v,0);
  -- Mutual follows are free-chat mode: the heart strip is hidden and frozen.
  if coalesce(p_mutual_follow,false) then
    return query select v,exists(select 1 from public.yamo_friendships_v160 f where f.user_a=a and f.user_b=b);
    return;
  end if;
  if not ((g_me='male' and g_peer='female') or (g_me='female' and g_peer='male')) then
    return query select v,false; return;
  end if;
  insert into public.yamo_chat_hearts_v160(user_a,user_b,heart_count,updated_at)
  values(a,b,2,now())
  on conflict(user_a,user_b) do update set heart_count=public.yamo_chat_hearts_v160.heart_count+2,updated_at=now()
  returning public.yamo_chat_hearts_v160.heart_count into v;
  if v>=100 then
    insert into public.yamo_friendships_v160(user_a,user_b,source) values(a,b,'chat_hearts') on conflict do nothing;
    created_friend:=true;
  end if;
  return query select v,created_friend;
end $$;
revoke all on function public.register_yamo_chat_heart_v160(text,boolean) from public,anon;
grant execute on function public.register_yamo_chat_heart_v160(text,boolean) to authenticated;

create or replace function public.get_my_yamo_friend_ids_v160()
returns table(legacy_id text)
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select p.legacy_id
  from public.yamo_friendships_v160 f
  join public.profiles p on p.id=case when f.user_a=auth.uid() then f.user_b else f.user_a end
  where auth.uid()=f.user_a or auth.uid()=f.user_b
$$;
revoke all on function public.get_my_yamo_friend_ids_v160() from public,anon;
grant execute on function public.get_my_yamo_friend_ids_v160() to authenticated;

create or replace function public.get_yamo_conversation_meta_v160(p_peer_legacy_ids text[])
returns table(
  peer_legacy_id text,pinned boolean,active_room_id text,heart_count bigint,
  peer_online boolean,peer_gender text,explicit_friend boolean
)
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select p.legacy_id,
    coalesce(pref.pinned,false),
    room.room_id,
    coalesce(h.heart_count,0),
    coalesce((pr.is_online and pr.last_heartbeat_at>=now()-interval '90 seconds'),false)
      or room.room_id is not null,
    lower(coalesce(p.gender,'')),
    (f.user_a is not null)
  from public.profiles p
  left join public.yamo_conversation_preferences_v160 pref on pref.user_id=auth.uid() and pref.peer_id=p.id
  left join public.yamo_presence_v160 pr on pr.user_id=p.id
  left join lateral(
    select rp.room_id from public.yamo_room_runtime_presence rp
    where rp.user_id=p.id and rp.left_at is null and rp.last_seen_at>=now()-interval '90 seconds'
    order by rp.last_seen_at desc limit 1
  ) room on true
  left join public.yamo_chat_hearts_v160 h on h.user_a=least(auth.uid(),p.id) and h.user_b=greatest(auth.uid(),p.id)
  left join public.yamo_friendships_v160 f on f.user_a=least(auth.uid(),p.id) and f.user_b=greatest(auth.uid(),p.id)
  where p.legacy_id=any(coalesce(p_peer_legacy_ids,array[]::text[]))
$$;
revoke all on function public.get_yamo_conversation_meta_v160(text[]) from public,anon;
grant execute on function public.get_yamo_conversation_meta_v160(text[]) to authenticated;

-- Persist call state inside the normal conversation stream.
create or replace function public.record_yamo_call_event_v160(
  p_peer_legacy_id text,p_status text,p_duration_seconds integer default 0,p_video boolean default false,p_call_id text default null
) returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare peer uuid; mid uuid; label text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select id into peer from public.profiles where lower(trim(legacy_id))=lower(trim(p_peer_legacy_id)) limit 1;
  if peer is null then raise exception 'peer_not_found'; end if;
  label:=case lower(coalesce(p_status,''))
    when 'rejected' then 'تم رفض المكالمة'
    when 'no_answer' then 'لم يتم الرد على المكالمة'
    when 'ended' then 'تم انتهاء المكالمة'
    when 'answered' then 'تم الرد على المكالمة'
    else 'مكالمة'
  end;
  insert into public.yamo_messages(sender_id,receiver_id,body,kind,duration_seconds,media_url,sent_at)
  values(auth.uid(),peer,label,'call',greatest(0,coalesce(p_duration_seconds,0)),
    case when nullif(trim(coalesce(p_call_id,'')),'') is null then (case when p_video then 'video' else 'voice' end)
         else (case when p_video then 'video:' else 'voice:' end)||trim(p_call_id) end,now())
  returning id into mid;
  return mid;
end $$;
revoke all on function public.record_yamo_call_event_v160(text,text,integer,boolean,text) from public,anon;
grant execute on function public.record_yamo_call_event_v160(text,text,integer,boolean,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Host/agency role resolution. Manual host assignment from the admin panel is
-- authoritative even when there is no invitation-binding row.
-- ---------------------------------------------------------------------------
create or replace function public.get_yamo_my_role_binding_v160()
returns table(role text,invitation_code text,agency_name text,bound_at timestamptz)
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
begin
  if auth.uid() is null then return; end if;
  if exists(select 1 from public.yamo_agency_hosts h where h.user_id=auth.uid() and h.removed_at is null) then
    return query
    select 'host'::text,coalesce(a.host_invite_code,a.invite_code),a.name,h.joined_at
    from public.yamo_agency_hosts h join public.yamo_agencies a on a.id=h.agency_id
    where h.user_id=auth.uid() and h.removed_at is null order by h.joined_at desc limit 1;
    return;
  end if;
  if exists(select 1 from public.yamo_agencies a where a.owner_id=auth.uid() and a.disabled_at is null) then
    return query
    select 'agency_agent'::text,coalesce(a.agency_invite_code,a.invite_code),a.name,a.created_at
    from public.yamo_agencies a where a.owner_id=auth.uid() and a.disabled_at is null order by a.created_at desc limit 1;
    return;
  end if;
  return query
  select b.role,b.invitation_code,a.name,b.bound_at
  from public.yamo_invitation_bindings b
  left join public.yamo_agencies a on coalesce(a.host_invite_code,a.invite_code)=b.invitation_code or a.agency_invite_code=b.invitation_code
  where b.user_id=auth.uid() order by b.bound_at desc limit 1;
end $$;
revoke all on function public.get_yamo_my_role_binding_v160() from public,anon;
grant execute on function public.get_yamo_my_role_binding_v160() to authenticated;

-- ---------------------------------------------------------------------------
-- Sequential room IDs for every newly-created room.
-- Existing room ids remain untouched to avoid breaking references.
-- ---------------------------------------------------------------------------
create sequence if not exists public.yamo_room_public_id_seq start 100001;
do $$
declare mx bigint;
begin
  select coalesce(max(room_id::bigint),100000) into mx from public.yamo_owned_rooms where room_id~'^[0-9]+$';
  perform setval('public.yamo_room_public_id_seq',greatest(mx,100000),true);
end $$;
create or replace function public.yamo_assign_sequential_room_id_v160()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
  new.room_id:=nextval('public.yamo_room_public_id_seq')::text;
  return new;
end $$;
drop trigger if exists yamo_owned_room_sequential_id_v160 on public.yamo_owned_rooms;
create trigger yamo_owned_room_sequential_id_v160 before insert on public.yamo_owned_rooms
for each row execute function public.yamo_assign_sequential_room_id_v160();

-- ---------------------------------------------------------------------------
-- Room cup shift scheduling from the control panel + server-authoritative
-- supporters/receivers/rooms leaderboards.
-- ---------------------------------------------------------------------------
create table if not exists public.yamo_room_cup_config_v160 (
  singleton boolean primary key default true check(singleton),
  timezone_name text not null default 'Africa/Cairo',
  shift_start time not null default '00:00',
  shift_hours integer not null default 24 check(shift_hours between 1 and 168),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
insert into public.yamo_room_cup_config_v160(singleton) values(true) on conflict do nothing;
alter table public.yamo_room_cup_config_v160 enable row level security;
revoke all on public.yamo_room_cup_config_v160 from public,anon,authenticated;

create or replace function public.get_yamo_room_cup_config_v160()
returns jsonb language sql stable security definer set search_path=public,auth,pg_temp as $$
  select jsonb_build_object('timezone',timezone_name,'shift_start',to_char(shift_start,'HH24:MI'),'shift_hours',shift_hours,'updated_at',updated_at)
  from public.yamo_room_cup_config_v160 where singleton=true
$$;
revoke all on function public.get_yamo_room_cup_config_v160() from public,anon;
grant execute on function public.get_yamo_room_cup_config_v160() to authenticated;

create or replace function public.admin_get_yamo_room_cup_config_v160()
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare result jsonb;
begin
  perform public.yamo_admin_require('settings.manage');
  select jsonb_build_object('timezone',timezone_name,'shift_start',to_char(shift_start,'HH24:MI'),'shift_hours',shift_hours,'updated_at',updated_at)
    into result from public.yamo_room_cup_config_v160 where singleton=true;
  return coalesce(result,'{}'::jsonb);
end $$;
revoke all on function public.admin_get_yamo_room_cup_config_v160() from public,anon;
grant execute on function public.admin_get_yamo_room_cup_config_v160() to authenticated;

create or replace function public.admin_set_yamo_room_cup_config_v160(p_timezone text,p_shift_start text,p_shift_hours integer)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare admin_id uuid; parsed_start time; result jsonb;
begin
  admin_id:=public.yamo_admin_require('settings.manage');
  begin parsed_start:=trim(p_shift_start)::time; exception when others then raise exception 'invalid_shift_start'; end;
  if coalesce(p_shift_hours,0)<1 or p_shift_hours>168 then raise exception 'invalid_shift_hours'; end if;
  if not exists(select 1 from pg_timezone_names where name=trim(p_timezone)) then raise exception 'invalid_timezone'; end if;
  update public.yamo_room_cup_config_v160 set timezone_name=trim(p_timezone),shift_start=parsed_start,shift_hours=p_shift_hours,updated_at=now(),updated_by=admin_id where singleton=true;
  select jsonb_build_object('timezone',timezone_name,'shift_start',to_char(shift_start,'HH24:MI'),'shift_hours',shift_hours,'updated_at',updated_at) into result from public.yamo_room_cup_config_v160 where singleton=true;
  perform public.yamo_admin_log('room_cup.schedule','yamo_room_cup_config_v160','global',null,result,'تعديل توقيت كأس الغرف');
  return result;
end $$;
revoke all on function public.admin_set_yamo_room_cup_config_v160(text,text,integer) from public,anon;
grant execute on function public.admin_set_yamo_room_cup_config_v160(text,text,integer) to authenticated;

create or replace function public.yamo_room_cup_window_start_v160(p_period text)
returns timestamptz language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare tz text; st time; shift_len integer; local_now timestamp; base timestamp; anchor timestamp; steps bigint;
begin
  select timezone_name,shift_start,shift_hours into tz,st,shift_len from public.yamo_room_cup_config_v160 where singleton=true;
  local_now:=now() at time zone tz;
  if lower(p_period)='monthly' then
    base:=date_trunc('month',local_now)+st;
    if local_now<base then base:=base-interval '1 month'; end if;
  elsif lower(p_period)='weekly' then
    base:=date_trunc('week',local_now)+st;
    if local_now<base then base:=base-interval '7 days'; end if;
  else
    -- DAILY means the live operational shift. It can be 1..168 hours and is
    -- anchored to one stable local reference so 48/72-hour shifts do not
    -- accidentally reset at each midnight.
    anchor:=timestamp '2000-01-03 00:00:00'+st;
    steps:=floor(extract(epoch from (local_now-anchor))/(greatest(1,shift_len)*3600.0));
    base:=anchor+(steps*greatest(1,shift_len))*interval '1 hour';
  end if;
  return base at time zone tz;
end $$;
revoke all on function public.yamo_room_cup_window_start_v160(text) from public,anon,authenticated;

create or replace function public.get_yamo_room_cup_v160(p_room_id text,p_board text,p_period text,p_limit integer default 100)
returns table(legacy_user_id text,total_coins bigint,display_name text,avatar_url text,country_flag text)
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare since_at timestamptz:=public.yamo_room_cup_window_start_v160(p_period); lim integer:=least(100,greatest(1,coalesce(p_limit,100)));
begin
  if lower(p_board)='received' then
    return query select p.legacy_id,sum(t.coins)::bigint,coalesce(p.display_name,p.legacy_id),p.avatar_url,coalesce(p.country_flag,'')
    from public.room_gift_transactions t join public.profiles p on p.id=t.receiver_id
    where t.room_id=p_room_id and t.created_at>=since_at
    group by p.id,p.legacy_id,p.display_name,p.avatar_url,p.country_flag order by 2 desc limit lim;
  elsif lower(p_board)='rooms' then
    return query select r.room_id,sum(b.total_coins)::bigint,r.title,r.cover_url,''::text
    from public.room_gift_batches b join public.yamo_owned_rooms r on r.room_id=b.room_id
    where b.created_at>=since_at
    group by r.room_id,r.title,r.cover_url order by 2 desc limit lim;
  else
    return query select p.legacy_id,sum(b.total_coins)::bigint,coalesce(p.display_name,p.legacy_id),p.avatar_url,coalesce(p.country_flag,'')
    from public.room_gift_batches b join public.profiles p on p.id=b.sender_id
    where b.room_id=p_room_id and b.created_at>=since_at
    group by p.id,p.legacy_id,p.display_name,p.avatar_url,p.country_flag order by 2 desc limit lim;
  end if;
end $$;
revoke all on function public.get_yamo_room_cup_v160(text,text,text,integer) from public,anon;
grant execute on function public.get_yamo_room_cup_v160(text,text,text,integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Complete device unbind. History is preserved, while the active binding row
-- is deleted so the installation is immediately free for another account.
-- ---------------------------------------------------------------------------
create table if not exists public.device_account_bindings (
  id uuid primary key default gen_random_uuid(),
  installation_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'android',
  bound_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  released_at timestamptz,
  release_reason text
);
alter table public.device_account_bindings add column if not exists installation_id text;
alter table public.device_account_bindings add column if not exists platform text default 'android';
alter table public.device_account_bindings add column if not exists bound_at timestamptz default now();
alter table public.device_account_bindings add column if not exists last_seen_at timestamptz default now();
alter table public.device_account_bindings add column if not exists released_at timestamptz;
alter table public.device_account_bindings add column if not exists release_reason text;
create index if not exists device_account_bindings_installation_idx on public.device_account_bindings(installation_id,last_seen_at desc);
create index if not exists device_account_bindings_user_idx on public.device_account_bindings(user_id,last_seen_at desc);

create table if not exists public.yamo_device_binding_history_v160 (
  id uuid primary key default gen_random_uuid(),
  binding_id uuid,
  installation_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text,
  bound_at timestamptz,
  last_seen_at timestamptz,
  released_at timestamptz not null default now(),
  release_reason text,
  released_by uuid references auth.users(id) on delete set null
);
alter table public.yamo_device_binding_history_v160 enable row level security;
revoke all on public.device_account_bindings,public.yamo_device_binding_history_v160 from public,anon,authenticated;

insert into public.yamo_admin_permissions(permission,label_ar,category) values
 ('users.devices.release','فك ارتباط أجهزة تسجيل الدخول','users')
on conflict(permission) do update set label_ar=excluded.label_ar,category=excluded.category;
insert into public.yamo_admin_role_permissions(role,permission) values
 ('super_admin','users.devices.release'),('admin','users.devices.release') on conflict do nothing;

create or replace function public.admin_get_yamo_active_devices_v247(p_user_id uuid)
returns table(installation_id text,platform text,bound_at timestamptz,last_seen_at timestamptz)
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
begin
  perform public.yamo_admin_require('users.read');
  return query select d.installation_id,coalesce(d.platform,'android'),d.bound_at,d.last_seen_at
  from public.device_account_bindings d where d.user_id=p_user_id and d.released_at is null
  order by d.last_seen_at desc;
end $$;
revoke all on function public.admin_get_yamo_active_devices_v247(uuid) from public,anon;
grant execute on function public.admin_get_yamo_active_devices_v247(uuid) to authenticated;

create or replace function public.admin_release_yamo_active_device_v247(p_user_id uuid,p_installation_id text,p_reason text)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare affected integer;
begin
  perform public.yamo_admin_require('users.devices.release');
  if length(trim(coalesce(p_reason,'')))<10 then raise exception 'reason_too_short'; end if;
  insert into public.yamo_device_binding_history_v160(binding_id,installation_id,user_id,platform,bound_at,last_seen_at,released_at,release_reason,released_by)
  select id,installation_id,user_id,platform,bound_at,last_seen_at,now(),left(trim(p_reason),500),auth.uid()
  from public.device_account_bindings where installation_id=p_installation_id and released_at is null;
  delete from public.device_account_bindings where installation_id=p_installation_id and released_at is null;
  get diagnostics affected=row_count;
  if affected=0 then raise exception 'active_device_binding_not_found'; end if;
  perform public.yamo_admin_log('user.device_release','device_account_bindings',p_installation_id,
    null,jsonb_build_object('requested_user_id',p_user_id,'released_rows',affected),p_reason);
  return true;
end $$;
revoke all on function public.admin_release_yamo_active_device_v247(uuid,text,text) from public,anon;
grant execute on function public.admin_release_yamo_active_device_v247(uuid,text,text) to authenticated;

create or replace function public.admin_get_yamo_related_accounts_v160(p_user_id uuid)
returns table(user_id uuid,legacy_id text,display_name text,avatar_url text,last_seen_at timestamptz,active_binding boolean)
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
begin
  perform public.yamo_admin_require('users.read');
  return query
  with install_ids as (
    select installation_id from public.device_account_bindings where user_id=p_user_id
    union select installation_id from public.yamo_device_binding_history_v160 where user_id=p_user_id
  ), links as (
    select d.user_id,d.last_seen_at,true active from public.device_account_bindings d where d.installation_id in(select installation_id from install_ids)
    union all
    select h.user_id,h.last_seen_at,false active from public.yamo_device_binding_history_v160 h where h.installation_id in(select installation_id from install_ids)
  )
  select p.id,p.legacy_id,coalesce(p.display_name,p.legacy_id),p.avatar_url,max(l.last_seen_at),bool_or(l.active)
  from links l join public.profiles p on p.id=l.user_id
  where p.id<>p_user_id group by p.id,p.legacy_id,p.display_name,p.avatar_url order by max(l.last_seen_at) desc;
end $$;
revoke all on function public.admin_get_yamo_related_accounts_v160(uuid) from public,anon;
grant execute on function public.admin_get_yamo_related_accounts_v160(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Human-readable ban numbers. The normal account-status RPC is upgraded so a
-- ban created from Users immediately has a number, and unban revokes it.
-- ---------------------------------------------------------------------------
create sequence if not exists public.yamo_ban_number_seq start 100001;
alter table public.yamo_moderation_actions add column if not exists ban_number bigint;
alter table public.yamo_moderation_actions alter column ban_number set default nextval('public.yamo_ban_number_seq');
update public.yamo_moderation_actions set ban_number=nextval('public.yamo_ban_number_seq') where ban_number is null;
create unique index if not exists yamo_moderation_actions_ban_number_uidx on public.yamo_moderation_actions(ban_number);

create or replace function public.admin_set_yamo_account_status(p_legacy_id text,p_status text,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_target uuid;v_before text;rid uuid;
begin
  perform public.yamo_admin_require('users.moderate');
  if p_status not in('active','suspended','banned') then raise exception 'invalid_status'; end if;
  if length(trim(coalesce(p_note,'')))<3 then raise exception 'reason_required'; end if;
  select id,account_status into v_target,v_before from public.profiles where legacy_id=p_legacy_id;
  if v_target is null then raise exception 'user_not_found'; end if;
  update public.profiles set account_status=p_status where id=v_target;
  if p_status='banned' and not exists(select 1 from public.yamo_moderation_actions where user_id=v_target and active and action_type='ban') then
    insert into public.yamo_moderation_actions(user_id,action_type,reason,expires_at)
    values(v_target,'ban',left(trim(p_note),500),null) returning id into rid;
  elsif p_status='suspended' and not exists(select 1 from public.yamo_moderation_actions where user_id=v_target and active and action_type='suspend') then
    insert into public.yamo_moderation_actions(user_id,action_type,reason,expires_at)
    values(v_target,'suspend',left(trim(p_note),500),null) returning id into rid;
  elsif p_status='active' then
    update public.yamo_moderation_actions set active=false,revoked_at=now(),revoked_by=auth.uid(),revoke_reason=left(trim(p_note),500)
    where user_id=v_target and active and action_type in('ban','suspend');
  end if;
  perform public.yamo_admin_log('user.status','profiles',p_legacy_id,to_jsonb(v_before),to_jsonb(p_status),p_note);
  return true;
end $$;
revoke all on function public.admin_set_yamo_account_status(text,text,text) from public,anon;
grant execute on function public.admin_set_yamo_account_status(text,text,text) to authenticated;

create or replace function public.admin_get_yamo_active_ban_number_v160(p_user_id uuid)
returns bigint language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare result bigint;
begin
  perform public.yamo_admin_require('users.read');
  select ban_number into result from public.yamo_moderation_actions
  where user_id=p_user_id and active and action_type='ban' order by created_at desc limit 1;
  return result;
end $$;
revoke all on function public.admin_get_yamo_active_ban_number_v160(uuid) from public,anon;
grant execute on function public.admin_get_yamo_active_ban_number_v160(uuid) to authenticated;

commit;
notify pgrst,'reload schema';
