-- Yamo V216: real banners + instant messages + targeting + destinations
begin;

insert into public.yamo_admin_permissions(permission,label_ar,category) values
('banners.manage','إدارة البنرات والرسائل الفورية','content')
on conflict(permission) do update set label_ar=excluded.label_ar,category=excluded.category;

insert into public.yamo_admin_role_permissions(role,permission) values
('super_admin','banners.manage'),('admin','banners.manage')
on conflict do nothing;

create table if not exists public.yamo_campaigns(
  id uuid primary key default gen_random_uuid(),
  kind text not null check(kind in('banner','instant_message')),
  title_ar text not null,
  title_en text,
  body_ar text not null default '',
  body_en text,
  image_url text,
  content_mode text not null default 'image_text' check(content_mode in('image','image_text')),
  destination_type text not null default 'page' check(destination_type in('room','event','activity','user','agency','page')),
  destination_value text,
  segment text not null default 'all' check(segment in('all','vip','hosts','male','female')),
  placement text check(placement is null or placement in('home','rooms','messages')),
  button_ar text,
  button_en text,
  scheduled_at timestamptz not null default now(),
  ends_at timestamptz,
  enabled boolean not null default true,
  sent_count bigint not null default 0,
  click_count bigint not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists yamo_campaigns_active_idx on public.yamo_campaigns(kind,enabled,scheduled_at,ends_at);
alter table public.yamo_campaigns add column if not exists content_mode text not null default 'image_text';
alter table public.yamo_campaigns enable row level security;

drop view if exists public.admin_yamo_campaigns;
create view public.admin_yamo_campaigns as
select * from public.yamo_campaigns
where public.yamo_admin_has_permission('banners.read') or public.yamo_admin_has_permission('banners.manage');
grant select on public.admin_yamo_campaigns to authenticated;

drop function if exists public.admin_save_yamo_campaign(text,text,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,boolean);
drop function if exists public.admin_save_yamo_campaign(text,text,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,boolean,text);
create function public.admin_save_yamo_campaign(
  p_kind text,p_title_ar text,p_title_en text default null,p_body_ar text default '',p_body_en text default null,
  p_image_url text default null,p_destination_type text default 'page',p_destination_value text default null,
  p_segment text default 'all',p_placement text default null,p_button_ar text default null,p_button_en text default null,
  p_scheduled_at timestamptz default null,p_ends_at timestamptz default null,p_enabled boolean default true,p_content_mode text default 'image_text'
) returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_id uuid; v_count bigint:=0;
begin
  perform public.yamo_admin_require('banners.manage');
  if p_kind not in('banner','instant_message') then raise exception 'invalid_campaign_kind'; end if;
  if length(trim(coalesce(p_title_ar,'')))=0 and length(trim(coalesce(p_image_url,'')))=0 then raise exception 'title_or_image_required'; end if;
  if p_kind='banner' and length(trim(coalesce(p_image_url,'')))=0 then raise exception 'banner_image_required'; end if;
  if p_destination_type not in('room','event','activity','user','agency','page') then raise exception 'invalid_destination'; end if;
  if p_segment not in('all','vip','hosts','male','female') then raise exception 'invalid_segment'; end if;
  insert into public.yamo_campaigns(kind,title_ar,title_en,body_ar,body_en,image_url,content_mode,destination_type,destination_value,segment,placement,button_ar,button_en,scheduled_at,ends_at,enabled,created_by)
  values(p_kind,coalesce(nullif(trim(coalesce(p_title_ar,'')),''),'يامو'),nullif(trim(coalesce(p_title_en,'')),''),coalesce(p_body_ar,''),nullif(trim(coalesce(p_body_en,'')),''),nullif(trim(coalesce(p_image_url,'')),''),case when p_content_mode='image' then 'image' else 'image_text' end,p_destination_type,nullif(trim(coalesce(p_destination_value,'')),''),p_segment,case when p_kind='banner' then coalesce(p_placement,'home') else null end,nullif(trim(coalesce(p_button_ar,'')),''),nullif(trim(coalesce(p_button_en,'')),''),coalesce(p_scheduled_at,now()),p_ends_at,p_enabled,auth.uid()) returning id into v_id;

  if p_kind='instant_message' and p_enabled and coalesce(p_scheduled_at,now())<=now() then
    insert into public.yamo_notifications(user_id,kind,title_ar,body_ar,deep_link)
    select p.id,'system',coalesce(nullif(trim(coalesce(p_title_ar,'')),''),'يامو'),coalesce(p_body_ar,''),'yamo://campaign/'||v_id::text
    from public.profiles p where case p_segment
      when 'all' then true
      when 'male' then lower(coalesce(p.gender,'')) in('male','ذكر')
      when 'female' then lower(coalesce(p.gender,'')) in('female','أنثى','انثى')
      when 'vip' then exists(select 1 from public.yamo_vip_subscriptions v where v.user_id=p.id and v.expires_at>now())
      when 'hosts' then exists(select 1 from public.yamo_agency_hosts h where h.user_id=p.id and h.removed_at is null)
      else false end;
    get diagnostics v_count=row_count;
    update public.yamo_campaigns set sent_count=v_count where id=v_id;
  end if;
  perform public.yamo_admin_log('campaign.create','yamo_campaigns',v_id::text,null,jsonb_build_object('kind',p_kind,'segment',p_segment,'recipients',v_count),'إنشاء حملة يامو');
  return v_id;
end $$;
revoke all on function public.admin_save_yamo_campaign(text,text,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,boolean,text) from public,anon;
grant execute on function public.admin_save_yamo_campaign(text,text,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,boolean,text) to authenticated;

create or replace function public.admin_set_yamo_campaign_state(p_id uuid,p_enabled boolean default null,p_delete boolean default false)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  perform public.yamo_admin_require('banners.manage');
  if p_delete then delete from public.yamo_campaigns where id=p_id;
  else update public.yamo_campaigns set enabled=coalesce(p_enabled,enabled),updated_at=now() where id=p_id; end if;
  perform public.yamo_admin_log(case when p_delete then 'campaign.delete' else 'campaign.state' end,'yamo_campaigns',p_id::text,null,jsonb_build_object('enabled',p_enabled),null);
  return found;
end $$;
grant execute on function public.admin_set_yamo_campaign_state(uuid,boolean,boolean) to authenticated;

drop function if exists public.get_yamo_active_banners(text,text);
create function public.get_yamo_active_banners(p_placement text default 'home',p_language text default 'ar')
returns table(id uuid,title text,body text,image_url text,content_mode text,destination_type text,destination_value text,button_text text)
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select c.id,case when lower(p_language)='en' then coalesce(c.title_en,c.title_ar) else c.title_ar end,
    case when lower(p_language)='en' then coalesce(c.body_en,c.body_ar) else c.body_ar end,c.image_url,c.content_mode,c.destination_type,c.destination_value,
    case when lower(p_language)='en' then coalesce(c.button_en,c.button_ar,'View now') else coalesce(c.button_ar,'عرض الآن') end
  from public.yamo_campaigns c left join public.profiles me on me.id=auth.uid()
  where c.kind='banner' and c.enabled and c.placement=coalesce(p_placement,'home') and c.scheduled_at<=now() and (c.ends_at is null or c.ends_at>now())
    and case c.segment when 'all' then true when 'male' then lower(coalesce(me.gender,'')) in('male','ذكر') when 'female' then lower(coalesce(me.gender,'')) in('female','أنثى','انثى')
      when 'vip' then exists(select 1 from public.yamo_vip_subscriptions v where v.user_id=auth.uid() and v.expires_at>now())
      when 'hosts' then exists(select 1 from public.yamo_agency_hosts h where h.user_id=auth.uid() and h.removed_at is null) else false end
  order by c.scheduled_at desc limit 12
$$;
grant execute on function public.get_yamo_active_banners(text,text) to authenticated;

create or replace function public.get_yamo_active_instant_messages(p_language text default 'ar')
returns table(id uuid,title text,body text,image_url text,destination_type text,destination_value text,button_text text)
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select c.id,case when lower(p_language)='en' then coalesce(c.title_en,c.title_ar) else c.title_ar end,
    case when lower(p_language)='en' then coalesce(c.body_en,c.body_ar) else c.body_ar end,c.image_url,c.destination_type,c.destination_value,
    case when lower(p_language)='en' then coalesce(c.button_en,c.button_ar,'View now') else coalesce(c.button_ar,'عرض الآن') end
  from public.yamo_campaigns c left join public.profiles me on me.id=auth.uid()
  where c.kind='instant_message' and c.enabled and c.scheduled_at<=now() and (c.ends_at is null or c.ends_at>now())
    and case c.segment when 'all' then true when 'male' then lower(coalesce(me.gender,'')) in('male','ذكر') when 'female' then lower(coalesce(me.gender,'')) in('female','أنثى','انثى')
      when 'vip' then exists(select 1 from public.yamo_vip_subscriptions v where v.user_id=auth.uid() and v.expires_at>now())
      when 'hosts' then exists(select 1 from public.yamo_agency_hosts h where h.user_id=auth.uid() and h.removed_at is null) else false end
  order by c.scheduled_at desc limit 10
$$;
grant execute on function public.get_yamo_active_instant_messages(text) to authenticated;

create or replace function public.track_yamo_campaign_click(p_campaign_id uuid) returns boolean
language plpgsql security definer set search_path=public,auth,pg_temp as $$ begin
  if auth.uid() is null then return false; end if;
  update public.yamo_campaigns set click_count=click_count+1 where id=p_campaign_id and enabled;
  return found;
end $$;
grant execute on function public.track_yamo_campaign_click(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('campaign-media','campaign-media',true,8388608,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "campaign media admin upload" on storage.objects;
create policy "campaign media admin upload" on storage.objects for insert to authenticated with check(bucket_id='campaign-media' and public.yamo_admin_has_permission('banners.manage'));
drop policy if exists "campaign media public read" on storage.objects;
create policy "campaign media public read" on storage.objects for select to public using(bucket_id='campaign-media');

commit;
select pg_notify('pgrst','reload schema');
