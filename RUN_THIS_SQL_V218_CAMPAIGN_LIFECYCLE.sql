-- Yamo Admin V218 — campaign destination preview and complete lifecycle
-- Run once after V217 in Supabase SQL Editor.
begin;

alter table public.yamo_campaigns add column if not exists deleted_at timestamptz;
alter table public.yamo_campaigns add column if not exists deleted_by uuid references auth.users(id);
alter table public.yamo_campaigns add column if not exists last_renewed_at timestamptz;
alter table public.yamo_campaigns add column if not exists revision integer not null default 1;
create index if not exists yamo_campaigns_lifecycle_idx on public.yamo_campaigns(deleted_at,kind,enabled,scheduled_at desc,ends_at);

create table if not exists public.yamo_campaign_history(
  id bigint generated always as identity primary key,
  campaign_id uuid not null references public.yamo_campaigns(id) on delete restrict,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  actor_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists yamo_campaign_history_campaign_idx on public.yamo_campaign_history(campaign_id,created_at desc);
alter table public.yamo_campaign_history enable row level security;

drop view if exists public.admin_yamo_campaign_history;
create view public.admin_yamo_campaign_history as
select h.*,c.kind,c.title_ar from public.yamo_campaign_history h join public.yamo_campaigns c on c.id=h.campaign_id
where public.yamo_admin_has_permission('banners.manage');
grant select on public.admin_yamo_campaign_history to authenticated;

drop view if exists public.admin_yamo_campaigns;
create view public.admin_yamo_campaigns as
select c.*,
 case when c.deleted_at is not null then 'archived'
      when not c.enabled then 'stopped'
      when c.scheduled_at>now() then 'scheduled'
      when c.ends_at is not null and c.ends_at<=now() then 'expired'
      else 'active' end lifecycle_status,
 case when c.ends_at is null then null else greatest(0,extract(epoch from(c.ends_at-now()))::bigint) end remaining_seconds
from public.yamo_campaigns c
where public.yamo_admin_has_permission('banners.read') or public.yamo_admin_has_permission('banners.manage');
grant select on public.admin_yamo_campaigns to authenticated;

create or replace function public.admin_lookup_yamo_campaign_destination(p_type text,p_value text)
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare v jsonb; q text; src text;
begin
  perform public.yamo_admin_require('banners.manage');
  if p_type='page' then
    if lower(trim(coalesce(p_value,'')))=any(array['home','posts','rooms','messages','profile','vip','tasks','agencies','events']) then
      return jsonb_build_object('found',true,'type','page','id',lower(trim(p_value)),'title','صفحة داخل التطبيق','subtitle',lower(trim(p_value)),'status','available');
    end if;
    return jsonb_build_object('found',false,'type','page','message','اسم الصفحة غير مدعوم');
  end if;
  src:=case p_type when 'user' then 'admin_profiles' when 'room' then 'admin_rooms' when 'event' then 'admin_events' when 'activity' then 'admin_events' when 'agency' then 'admin_agencies' else null end;
  if src is null or nullif(trim(coalesce(p_value,'')),'') is null then return jsonb_build_object('found',false,'type',p_type,'message','أدخل ID صحيح'); end if;
  -- Admin views are used deliberately: lookup follows the same real data and permissions as the panel.
  if p_type='user' then
    q:=format('select to_jsonb(x) from public.%I x where coalesce(x.legacy_id::text,'''')=$1 or x.id::text=$1 limit 1',src);
  elsif p_type='room' then
    q:=format('select to_jsonb(x) from public.%I x where coalesce(x.room_id::text,'''')=$1 limit 1',src);
  else
    q:=format('select to_jsonb(x) from public.%I x where x.id::text=$1 limit 1',src);
  end if;
  execute q into v using trim(p_value);
  if v is null then return jsonb_build_object('found',false,'type',p_type,'id',trim(p_value),'message','لم يتم العثور على الوجهة'); end if;
  return jsonb_build_object('found',true,'type',p_type,'id',coalesce(v->>'id',v->>'room_id',v->>'legacy_id'),
    'title',coalesce(v->>'display_name',v->>'title_ar',v->>'title',v->>'name','بدون اسم'),
    'subtitle',coalesce(v->>'legacy_id',v->>'slug',v->>'invite_code',v->>'owner_legacy_id',''),
    'image_url',coalesce(v->>'avatar_url',v->>'cover_url',v->>'banner_url',''),
    'status',coalesce(v->>'status',case when v->>'disabled_at' is null then 'active' else 'disabled' end),'raw',v);
exception when undefined_table or undefined_column then
  return jsonb_build_object('found',false,'type',p_type,'message','عرض الإدارة الخاص بهذه الوجهة غير مثبت');
end $$;
revoke all on function public.admin_lookup_yamo_campaign_destination(text,text) from public,anon;
grant execute on function public.admin_lookup_yamo_campaign_destination(text,text) to authenticated;

create or replace function public.admin_set_yamo_campaign_state(p_id uuid,p_enabled boolean default null,p_delete boolean default false)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare old_row jsonb; new_row jsonb; action_name text;
begin
  perform public.yamo_admin_require('banners.manage');
  select to_jsonb(c) into old_row from public.yamo_campaigns c where c.id=p_id for update;
  if old_row is null then raise exception 'campaign_not_found'; end if;
  if p_delete then
    update public.yamo_campaigns set enabled=false,deleted_at=now(),deleted_by=auth.uid(),updated_at=now(),revision=revision+1 where id=p_id;
    action_name:='archive';
  else
    update public.yamo_campaigns set enabled=coalesce(p_enabled,enabled),deleted_at=case when p_enabled=true then null else deleted_at end,
      deleted_by=case when p_enabled=true then null else deleted_by end,updated_at=now(),revision=revision+1 where id=p_id;
    action_name:=case when p_enabled then 'start' else 'stop' end;
  end if;
  select to_jsonb(c) into new_row from public.yamo_campaigns c where c.id=p_id;
  insert into public.yamo_campaign_history(campaign_id,action,old_data,new_data,actor_id) values(p_id,action_name,old_row,new_row,auth.uid());
  perform public.yamo_admin_log('campaign.'||action_name,'yamo_campaigns',p_id::text,old_row,new_row,'إدارة حالة الحملة');
  return true;
end $$;
grant execute on function public.admin_set_yamo_campaign_state(uuid,boolean,boolean) to authenticated;

create or replace function public.admin_renew_yamo_campaign(p_id uuid,p_days integer default null,p_ends_at timestamptz default null)
returns timestamptz language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare old_row jsonb; new_row jsonb; new_end timestamptz;
begin
  perform public.yamo_admin_require('banners.manage');
  if p_days is null and p_ends_at is null then raise exception 'renewal_period_required'; end if;
  if p_days is not null and (p_days<1 or p_days>3650) then raise exception 'invalid_renewal_days'; end if;
  select to_jsonb(c),case when p_ends_at is not null then p_ends_at else greatest(now(),coalesce(c.ends_at,now()))+make_interval(days=>p_days) end
    into old_row,new_end from public.yamo_campaigns c where c.id=p_id for update;
  if old_row is null then raise exception 'campaign_not_found'; end if;
  if new_end<=now() then raise exception 'renewal_must_be_future'; end if;
  update public.yamo_campaigns set ends_at=new_end,enabled=true,deleted_at=null,deleted_by=null,last_renewed_at=now(),updated_at=now(),revision=revision+1 where id=p_id;
  select to_jsonb(c) into new_row from public.yamo_campaigns c where c.id=p_id;
  insert into public.yamo_campaign_history(campaign_id,action,old_data,new_data,actor_id) values(p_id,'renew',old_row,new_row,auth.uid());
  perform public.yamo_admin_log('campaign.renew','yamo_campaigns',p_id::text,old_row,new_row,'تجديد الحملة');
  return new_end;
end $$;
revoke all on function public.admin_renew_yamo_campaign(uuid,integer,timestamptz) from public,anon;
grant execute on function public.admin_renew_yamo_campaign(uuid,integer,timestamptz) to authenticated;

create or replace function public.admin_update_yamo_campaign(p_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare old_row jsonb; new_row jsonb;
begin
  perform public.yamo_admin_require('banners.manage');
  select to_jsonb(c) into old_row from public.yamo_campaigns c where c.id=p_id for update;
  if old_row is null then raise exception 'campaign_not_found'; end if;
  update public.yamo_campaigns set
    title_ar=coalesce(nullif(trim(p_payload->>'title_ar'),''),title_ar),title_en=case when p_payload?'title_en' then nullif(trim(p_payload->>'title_en'),'') else title_en end,
    body_ar=coalesce(p_payload->>'body_ar',body_ar),body_en=case when p_payload?'body_en' then nullif(trim(p_payload->>'body_en'),'') else body_en end,
    image_url=case when p_payload?'image_url' then nullif(trim(p_payload->>'image_url'),'') else image_url end,
    content_mode=coalesce(p_payload->>'content_mode',content_mode),destination_type=coalesce(p_payload->>'destination_type',destination_type),
    destination_value=case when p_payload?'destination_value' then nullif(trim(p_payload->>'destination_value'),'') else destination_value end,
    segment=coalesce(p_payload->>'segment',segment),placement=case when p_payload?'placement' then nullif(p_payload->>'placement','') else placement end,
    button_ar=case when p_payload?'button_ar' then nullif(trim(p_payload->>'button_ar'),'') else button_ar end,
    button_en=case when p_payload?'button_en' then nullif(trim(p_payload->>'button_en'),'') else button_en end,
    scheduled_at=coalesce((p_payload->>'scheduled_at')::timestamptz,scheduled_at),
    ends_at=case when p_payload?'ends_at' then nullif(p_payload->>'ends_at','')::timestamptz else ends_at end,
    enabled=coalesce((p_payload->>'enabled')::boolean,enabled),updated_at=now(),revision=revision+1 where id=p_id;
  select to_jsonb(c) into new_row from public.yamo_campaigns c where c.id=p_id;
  insert into public.yamo_campaign_history(campaign_id,action,old_data,new_data,actor_id) values(p_id,'edit',old_row,new_row,auth.uid());
  perform public.yamo_admin_log('campaign.edit','yamo_campaigns',p_id::text,old_row,new_row,'تعديل الحملة');
  return p_id;
end $$;
revoke all on function public.admin_update_yamo_campaign(uuid,jsonb) from public,anon;
grant execute on function public.admin_update_yamo_campaign(uuid,jsonb) to authenticated;

-- Archived campaigns must never reach the app.
create or replace function public.get_yamo_active_banners(p_placement text default 'home',p_language text default 'ar')
returns table(id uuid,title text,body text,image_url text,content_mode text,destination_type text,destination_value text,button_text text)
language sql stable security definer set search_path=public,auth,pg_temp as $$
 select c.id,case when lower(p_language)='en' then coalesce(c.title_en,c.title_ar) else c.title_ar end,
 case when lower(p_language)='en' then coalesce(c.body_en,c.body_ar) else c.body_ar end,c.image_url,c.content_mode,c.destination_type,c.destination_value,
 case when lower(p_language)='en' then coalesce(c.button_en,c.button_ar,'View now') else coalesce(c.button_ar,'عرض الآن') end
 from public.yamo_campaigns c left join public.profiles me on me.id=auth.uid()
 where c.deleted_at is null and c.kind='banner' and c.enabled and c.placement=coalesce(p_placement,'home') and c.scheduled_at<=now() and(c.ends_at is null or c.ends_at>now())
 and case c.segment when 'all' then true when 'male' then lower(coalesce(me.gender,'')) in('male','ذكر') when 'female' then lower(coalesce(me.gender,'')) in('female','أنثى','انثى')
 when 'vip' then exists(select 1 from public.yamo_vip_subscriptions v where v.user_id=auth.uid() and v.expires_at>now()) when 'hosts' then exists(select 1 from public.yamo_agency_hosts h where h.user_id=auth.uid() and h.removed_at is null) else false end
 order by c.scheduled_at desc limit 12 $$;
grant execute on function public.get_yamo_active_banners(text,text) to authenticated;

create or replace function public.get_yamo_active_instant_messages(p_language text default 'ar')
returns table(id uuid,title text,body text,image_url text,destination_type text,destination_value text,button_text text)
language sql stable security definer set search_path=public,auth,pg_temp as $$
 select c.id,case when lower(p_language)='en' then coalesce(c.title_en,c.title_ar) else c.title_ar end,
 case when lower(p_language)='en' then coalesce(c.body_en,c.body_ar) else c.body_ar end,c.image_url,c.destination_type,c.destination_value,
 case when lower(p_language)='en' then coalesce(c.button_en,c.button_ar,'View now') else coalesce(c.button_ar,'عرض الآن') end
 from public.yamo_campaigns c left join public.profiles me on me.id=auth.uid()
 where c.deleted_at is null and c.kind='instant_message' and c.enabled and c.scheduled_at<=now() and(c.ends_at is null or c.ends_at>now())
 and case c.segment when 'all' then true when 'male' then lower(coalesce(me.gender,'')) in('male','ذكر') when 'female' then lower(coalesce(me.gender,'')) in('female','أنثى','انثى')
 when 'vip' then exists(select 1 from public.yamo_vip_subscriptions v where v.user_id=auth.uid() and v.expires_at>now()) when 'hosts' then exists(select 1 from public.yamo_agency_hosts h where h.user_id=auth.uid() and h.removed_at is null) else false end
 order by c.scheduled_at desc limit 10 $$;
grant execute on function public.get_yamo_active_instant_messages(text) to authenticated;

commit;
select pg_notify('pgrst','reload schema');
