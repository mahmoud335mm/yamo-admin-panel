-- Yamo Admin V212 — message/call management dashboard, pricing and suggestions.
-- Additive migration. Run after 202608280001_yamo_admin_message_archive.sql.

begin;

insert into public.yamo_admin_permissions(permission,label_ar,category) values
  ('messages.manage','إدارة إعدادات الرسائل والاقتراحات','content'),
  ('messages.pricing','تعديل أسعار الرسائل والمكالمات والأرباح','finance')
on conflict(permission) do update set label_ar=excluded.label_ar,category=excluded.category;

insert into public.yamo_admin_role_permissions(role,permission) values
  ('super_admin','messages.manage'),('super_admin','messages.pricing'),
  ('admin','messages.manage'),('admin','messages.pricing')
on conflict do nothing;

create table if not exists public.yamo_message_settings (
  singleton boolean primary key default true check(singleton),
  text_price bigint not null default 10 check(text_price>=0),
  image_price bigint not null default 20 check(image_price>=0),
  voice_message_price bigint not null default 25 check(voice_message_price>=0),
  voice_minute_price bigint not null default 50 check(voice_minute_price>=0),
  video_minute_price bigint not null default 80 check(video_minute_price>=0),
  receiver_percent numeric(5,2) not null default 40 check(receiver_percent between 0 and 100),
  system_percent numeric(5,2) not null default 60 check(system_percent between 0 and 100),
  daily_free_messages integer not null default 0 check(daily_free_messages>=0),
  minimum_call_seconds integer not null default 60 check(minimum_call_seconds>=0),
  suggestions_per_day integer not null default 20 check(suggestions_per_day between 0 and 200),
  online_only boolean not null default true,
  prevent_repeat_days integer not null default 7 check(prevent_repeat_days between 0 and 365),
  pricing_enabled boolean not null default true,
  suggestions_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
insert into public.yamo_message_settings(singleton) values(true) on conflict do nothing;
alter table public.yamo_message_settings enable row level security;
revoke all on public.yamo_message_settings from public,anon,authenticated;

create table if not exists public.yamo_message_suggestion_pins (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  priority integer not null default 100,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
alter table public.yamo_message_suggestion_pins enable row level security;
revoke all on public.yamo_message_suggestion_pins from public,anon,authenticated;

create or replace function public.admin_get_message_settings()
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare result jsonb;
begin
  perform public.yamo_admin_require('messages.read');
  select to_jsonb(s)-'singleton'-'updated_by' into result from public.yamo_message_settings s where singleton=true;
  return coalesce(result,'{}'::jsonb);
end $$;
revoke all on function public.admin_get_message_settings() from public,anon;
grant execute on function public.admin_get_message_settings() to authenticated;

create or replace function public.admin_update_message_settings(p_settings jsonb)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare admin_id uuid;before_value jsonb;after_value jsonb;receiver numeric;system_share numeric;
begin
  admin_id:=public.yamo_admin_require('messages.pricing');
  select to_jsonb(s) into before_value from public.yamo_message_settings s where singleton=true;
  receiver:=least(100,greatest(0,coalesce((p_settings->>'receiver_percent')::numeric,40)));
  system_share:=least(100,greatest(0,coalesce((p_settings->>'system_percent')::numeric,100-receiver)));
  if round(receiver+system_share,2)<>100 then raise exception 'نسبة المستلمة والنظام يجب أن تساوي 100%%'; end if;
  update public.yamo_message_settings set
    text_price=greatest(0,coalesce((p_settings->>'text_price')::bigint,text_price)),
    image_price=greatest(0,coalesce((p_settings->>'image_price')::bigint,image_price)),
    voice_message_price=greatest(0,coalesce((p_settings->>'voice_message_price')::bigint,voice_message_price)),
    voice_minute_price=greatest(0,coalesce((p_settings->>'voice_minute_price')::bigint,voice_minute_price)),
    video_minute_price=greatest(0,coalesce((p_settings->>'video_minute_price')::bigint,video_minute_price)),
    receiver_percent=receiver,system_percent=system_share,
    daily_free_messages=greatest(0,coalesce((p_settings->>'daily_free_messages')::integer,daily_free_messages)),
    minimum_call_seconds=greatest(0,coalesce((p_settings->>'minimum_call_seconds')::integer,minimum_call_seconds)),
    suggestions_per_day=least(200,greatest(0,coalesce((p_settings->>'suggestions_per_day')::integer,suggestions_per_day))),
    online_only=coalesce((p_settings->>'online_only')::boolean,online_only),
    prevent_repeat_days=least(365,greatest(0,coalesce((p_settings->>'prevent_repeat_days')::integer,prevent_repeat_days))),
    pricing_enabled=coalesce((p_settings->>'pricing_enabled')::boolean,pricing_enabled),
    suggestions_enabled=coalesce((p_settings->>'suggestions_enabled')::boolean,suggestions_enabled),
    updated_at=now(),updated_by=admin_id where singleton=true;
  select to_jsonb(s)-'singleton'-'updated_by' into after_value from public.yamo_message_settings s where singleton=true;
  perform public.yamo_admin_log('messages.settings_update','message_settings','global',before_value,after_value,'تعديل أسعار وإعدادات الرسائل والمكالمات');
  return after_value;
end $$;
revoke all on function public.admin_update_message_settings(jsonb) from public,anon;
grant execute on function public.admin_update_message_settings(jsonb) to authenticated;

create or replace function public.admin_get_message_dashboard(p_days integer default 30)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare days_count integer:=least(365,greatest(1,coalesce(p_days,30)));result jsonb;
begin
  perform public.yamo_admin_require('messages.read');
  with base as (
    select a.* from public.yamo_message_archive a where a.sent_at>=now()-make_interval(days=>days_count)
  ), totals as (
    select count(*) total_messages,count(*) filter(where sent_at>=current_date) messages_today,
      count(*) filter(where kind in ('text','message')) text_count,
      count(*) filter(where kind='image') image_count,count(*) filter(where kind='voice') voice_count,
      count(*) filter(where kind in ('video','video_message')) video_count,count(*) filter(where read_at is not null) read_count,
      coalesce(sum(earning_pearls),0) earnings_paid from base
  ), active_profiles as (
    select distinct sender_id id from base where sent_at>=now()-interval '15 minutes'
    union select distinct receiver_id from base where sent_at>=now()-interval '15 minutes'
  ), active_stats as (
    select count(*) active_users,count(*) filter(where lower(coalesce(p.gender,''))='male') active_males,
      count(*) filter(where lower(coalesce(p.gender,''))='female') active_females
    from active_profiles a join public.profiles p on p.id=a.id
  ), chart_data as (
    select jsonb_agg(jsonb_build_object('label',to_char(message_day,'DD/MM'),'sent',sent_count,'replies',reply_count) order by message_day) chart
    from (
      select date_trunc('day',sent_at) as message_day,
        count(*) as sent_count,
        count(*) filter(where read_at is not null) as reply_count
      from base
      group by date_trunc('day',sent_at)
      order by message_day desc
      limit 30
    ) x
  )
  select jsonb_build_object('total_messages',t.total_messages,'messages_today',t.messages_today,
    'active_users',a.active_users,'active_males',a.active_males,'active_females',a.active_females,
    'response_rate',case when t.total_messages=0 then 0 else round(t.read_count*100.0/t.total_messages,1) end,
    'text_percent',case when t.total_messages=0 then 0 else round(t.text_count*100.0/t.total_messages,1) end,
    'image_percent',case when t.total_messages=0 then 0 else round(t.image_count*100.0/t.total_messages,1) end,
    'voice_percent',case when t.total_messages=0 then 0 else round(t.voice_count*100.0/t.total_messages,1) end,
    'video_percent',case when t.total_messages=0 then 0 else round(t.video_count*100.0/t.total_messages,1) end,
    'coins_spent',0,'earnings_paid',t.earnings_paid,'chart',coalesce(c.chart,'[]'::jsonb)) into result
  from totals t cross join active_stats a cross join chart_data c;
  return coalesce(result,'{}'::jsonb);
end $$;
revoke all on function public.admin_get_message_dashboard(integer) from public,anon;
grant execute on function public.admin_get_message_dashboard(integer) to authenticated;

create or replace function public.admin_get_active_message_users(p_gender text default 'all',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare result jsonb;
begin
  perform public.yamo_admin_require('messages.read');
  with pairs as (
    select least(sender_id,receiver_id) a_id,greatest(sender_id,receiver_id) b_id,count(*) message_count,
      extract(epoch from(max(sent_at)-min(sent_at)))/60 duration_minutes,max(sent_at) last_message_at,
      coalesce(sum(earning_pearls),0) coins_spent
    from public.yamo_message_archive where sent_at>=now()-interval '15 minutes' group by 1,2
  ) select coalesce(jsonb_agg(to_jsonb(x) order by x.last_message_at desc),'[]'::jsonb) into result from (
    select pa.legacy_id user_a_id,coalesce(pa.display_name,pa.legacy_id) user_a_name,pa.avatar_url user_a_avatar,pa.gender user_a_gender,
      pb.legacy_id user_b_id,coalesce(pb.display_name,pb.legacy_id) user_b_name,pb.avatar_url user_b_avatar,pb.gender user_b_gender,
      p.message_count,round(p.duration_minutes)::integer duration_minutes,p.coins_spent,p.last_message_at
    from pairs p join public.profiles pa on pa.id=p.a_id join public.profiles pb on pb.id=p.b_id
    where p_gender not in ('male','female') or lower(coalesce(pa.gender,''))=p_gender or lower(coalesce(pb.gender,''))=p_gender
    order by p.last_message_at desc limit least(500,greatest(1,coalesce(p_limit,100)))
  ) x;
  return result;
end $$;
revoke all on function public.admin_get_active_message_users(text,integer) from public,anon;
grant execute on function public.admin_get_active_message_users(text,integer) to authenticated;

create or replace function public.admin_get_message_suggestions(p_limit integer default 24)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare result jsonb;
begin
  perform public.yamo_admin_require('messages.read');
  select coalesce(jsonb_agg(to_jsonb(x) order by x.pin_priority desc,x.activity_at desc),'[]'::jsonb) into result from (
    select p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,p.avatar_url,p.gender,
      null::integer age,null::text country,0 level,0 vip_level,
      coalesce(a.activity_at>=now()-interval '15 minutes',false) is_online,coalesce(a.message_count,0) message_count,
      coalesce(pin.priority,0) pin_priority,coalesce(a.activity_at,p.created_at) activity_at
    from public.profiles p
    left join lateral (select max(m.sent_at) activity_at,count(*) message_count from public.yamo_message_archive m where m.sender_id=p.id or m.receiver_id=p.id) a on true
    left join public.yamo_message_suggestion_pins pin on pin.profile_id=p.id and pin.starts_at<=now() and (pin.ends_at is null or pin.ends_at>now())
    where nullif(trim(p.legacy_id),'') is not null
    order by coalesce(pin.priority,0) desc,coalesce(a.activity_at,p.created_at) desc
    limit least(100,greatest(1,coalesce(p_limit,24)))
  ) x;
  return result;
end $$;
revoke all on function public.admin_get_message_suggestions(integer) from public,anon;
grant execute on function public.admin_get_message_suggestions(integer) to authenticated;

create or replace function public.admin_pin_message_suggestion(p_legacy_id text,p_priority integer default 100,p_days integer default 30)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare admin_id uuid;profile_uuid uuid;
begin
  admin_id:=public.yamo_admin_require('messages.manage');
  select id into profile_uuid from public.profiles where lower(trim(legacy_id))=lower(trim(p_legacy_id)) limit 1;
  if profile_uuid is null then raise exception 'user_not_found'; end if;
  insert into public.yamo_message_suggestion_pins(profile_id,priority,starts_at,ends_at,created_by)
  values(profile_uuid,least(1000,greatest(0,coalesce(p_priority,100))),now(),now()+make_interval(days=>least(365,greatest(1,coalesce(p_days,30)))),admin_id)
  on conflict(profile_id) do update set priority=excluded.priority,starts_at=excluded.starts_at,ends_at=excluded.ends_at,created_by=excluded.created_by;
  perform public.yamo_admin_log('messages.suggestion_pin','profile',p_legacy_id,null,jsonb_build_object('priority',p_priority,'days',p_days),'تثبيت حساب في اقتراحات الرسائل');
  return true;
end $$;
revoke all on function public.admin_pin_message_suggestion(text,integer,integer) from public,anon;
grant execute on function public.admin_pin_message_suggestion(text,integer,integer) to authenticated;

commit;
notify pgrst,'reload schema';
