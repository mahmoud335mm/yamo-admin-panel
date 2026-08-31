-- Yamo Admin V214 emergency recovery for missing message settings RPCs.
-- Run this file alone in Supabase SQL Editor, then wait 10 seconds and refresh the panel.

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

create or replace function public.admin_get_message_settings()
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare result jsonb;
begin
  perform public.yamo_admin_require('messages.read');
  select to_jsonb(s)-'singleton'-'updated_by' into result
  from public.yamo_message_settings s where singleton=true;
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
  if round(receiver+system_share,2)<>100 then raise exception 'receiver_and_system_percent_must_equal_100'; end if;
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

insert into public.yamo_admin_permissions(permission,label_ar,category) values
  ('messages.manage','إدارة إعدادات الرسائل والاقتراحات','content'),
  ('messages.pricing','تعديل أسعار الرسائل والمكالمات والأرباح','finance')
on conflict(permission) do update set label_ar=excluded.label_ar,category=excluded.category;

insert into public.yamo_admin_role_permissions(role,permission) values
  ('super_admin','messages.manage'),('super_admin','messages.pricing'),
  ('admin','messages.manage'),('admin','messages.pricing')
on conflict do nothing;

notify pgrst,'reload schema';

-- Verification: this must return exactly two rows.
select p.proname,pg_get_function_identity_arguments(p.oid) arguments
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('admin_get_message_settings','admin_update_message_settings')
order by p.proname;
