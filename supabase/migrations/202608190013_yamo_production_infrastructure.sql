-- Production infrastructure shared by Yamo Android and the admin console.
begin;

-- Preserve deletion audit records after auth.users is removed.
alter table public.yamo_account_deletion_requests add column if not exists original_user_id uuid;
update public.yamo_account_deletion_requests set original_user_id=user_id where original_user_id is null;
alter table public.yamo_account_deletion_requests alter column user_id drop not null;
alter table public.yamo_account_deletion_requests drop constraint if exists yamo_account_deletion_requests_user_id_fkey;
alter table public.yamo_account_deletion_requests add constraint yamo_account_deletion_requests_user_id_fkey
  foreign key(user_id) references auth.users(id) on delete set null;
create or replace view public.admin_account_deletion_requests as
select d.*,p.legacy_id,coalesce(p.display_name,p.legacy_id,d.original_user_id::text) display_name,w.coins,w.pearls
from public.yamo_account_deletion_requests d left join public.profiles p on p.id=d.user_id
left join public.wallets w on w.user_id=d.user_id
where public.yamo_admin_has_permission('users.moderate');

-- Media buckets. Public catalogue media is readable by everybody; personal
-- uploads are restricted to their owner and authorised administrators.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
  ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp','image/gif']),
  ('room-media','room-media',true,10485760,array['image/jpeg','image/png','image/webp','image/gif']),
  ('catalog-assets','catalog-assets',true,52428800,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','application/octet-stream']),
  ('banners','banners',true,10485760,array['image/jpeg','image/png','image/webp','image/gif']),
  ('verification','verification',false,10485760,array['image/jpeg','image/png','image/webp']),
  ('support-attachments','support-attachments',false,20971520,array['image/jpeg','image/png','image/webp','video/mp4','application/pdf'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists yamo_public_media_read on storage.objects;
create policy yamo_public_media_read on storage.objects for select to anon,authenticated
  using(bucket_id in('avatars','room-media','catalog-assets','banners'));
drop policy if exists yamo_owned_media_insert on storage.objects;
create policy yamo_owned_media_insert on storage.objects for insert to authenticated
  with check(bucket_id in('avatars','room-media','verification','support-attachments')
    and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists yamo_owned_media_update on storage.objects;
create policy yamo_owned_media_update on storage.objects for update to authenticated
  using((storage.foldername(name))[1]=auth.uid()::text)
  with check((storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists yamo_owned_media_delete on storage.objects;
create policy yamo_owned_media_delete on storage.objects for delete to authenticated
  using((storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists yamo_private_media_read on storage.objects;
create policy yamo_private_media_read on storage.objects for select to authenticated
  using(bucket_id in('verification','support-attachments') and
    ((storage.foldername(name))[1]=auth.uid()::text or
      public.yamo_admin_has_permission('verification.manage') or public.yamo_admin_has_permission('support.manage')));
drop policy if exists yamo_admin_catalog_storage on storage.objects;
create policy yamo_admin_catalog_storage on storage.objects for all to authenticated
  using(bucket_id in('catalog-assets','banners') and public.yamo_admin_has_permission('catalog.manage'))
  with check(bucket_id in('catalog-assets','banners') and public.yamo_admin_has_permission('catalog.manage'));

create table if not exists public.yamo_device_tokens(
  id uuid primary key default gen_random_uuid(), user_id uuid not null,
  token text not null unique, platform text not null check(platform in('android','ios','web')),
  device_id text, app_version text, enabled boolean not null default true,
  last_seen_at timestamptz not null default now(), created_at timestamptz not null default now()
);
create index if not exists yamo_device_tokens_user_idx on public.yamo_device_tokens(user_id,enabled);
alter table public.yamo_device_tokens enable row level security;
drop policy if exists device_tokens_own on public.yamo_device_tokens;
create policy device_tokens_own on public.yamo_device_tokens for all to authenticated
  using(user_id=auth.uid()) with check(user_id=auth.uid());

create table if not exists public.yamo_notification_deliveries(
  id uuid primary key default gen_random_uuid(), notification_id text not null,
  user_id uuid not null, device_token_id uuid not null references public.yamo_device_tokens(id) on delete cascade,
  status text not null default 'pending' check(status in('pending','processing','sent','failed','dead')),
  attempts integer not null default 0, provider_message_id text, last_error text,
  next_attempt_at timestamptz not null default now(), created_at timestamptz not null default now(), sent_at timestamptz,
  unique(notification_id,device_token_id)
);
create index if not exists yamo_notification_delivery_queue_idx on public.yamo_notification_deliveries(status,next_attempt_at);
alter table public.yamo_notification_deliveries enable row level security;
drop policy if exists notification_delivery_admin_read on public.yamo_notification_deliveries;
create policy notification_delivery_admin_read on public.yamo_notification_deliveries for select to authenticated
  using(public.yamo_admin_has_permission('notifications.send'));

create or replace function public.yamo_enqueue_notification_delivery()
returns trigger language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  insert into public.yamo_notification_deliveries(notification_id,user_id,device_token_id)
  select new.id::text,new.user_id,t.id from public.yamo_device_tokens t where t.user_id=new.user_id and t.enabled
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists yamo_notifications_enqueue_push on public.yamo_notifications;
create trigger yamo_notifications_enqueue_push after insert on public.yamo_notifications
for each row execute function public.yamo_enqueue_notification_delivery();

create table if not exists public.yamo_system_health_events(
  id uuid primary key default gen_random_uuid(), component text not null,
  status text not null check(status in('healthy','degraded','down','recovered')),
  message text, details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists yamo_system_health_latest_idx on public.yamo_system_health_events(component,created_at desc);
alter table public.yamo_system_health_events enable row level security;
drop policy if exists health_admin_read on public.yamo_system_health_events;
create policy health_admin_read on public.yamo_system_health_events for select to authenticated
  using(public.yamo_admin_has_permission('settings.manage') or public.yamo_admin_has_permission('audit.read'));

create or replace function public.register_yamo_device_token(p_token text,p_platform text,p_device_id text default null,p_app_version text default null)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare rid uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_platform not in('android','ios','web') or length(trim(p_token))<20 then raise exception 'invalid_device_token'; end if;
  insert into public.yamo_device_tokens(user_id,token,platform,device_id,app_version)
  values(auth.uid(),p_token,p_platform,p_device_id,p_app_version)
  on conflict(token) do update set user_id=auth.uid(),platform=excluded.platform,device_id=excluded.device_id,
    app_version=excluded.app_version,enabled=true,last_seen_at=now() returning id into rid;
  return rid;
end $$;

create or replace function public.get_yamo_app_release(p_platform text,p_version_code integer)
returns table(version_name text,version_code integer,minimum_supported_code integer,force_update boolean,download_url text,notes_ar text,update_required boolean)
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select r.version_name,r.version_code,r.minimum_supported_code,r.force_update,r.download_url,r.notes_ar,
    (p_version_code<r.minimum_supported_code or (r.force_update and p_version_code<r.version_code))
  from public.yamo_app_releases r where r.platform=p_platform and r.active order by r.version_code desc limit 1
$$;

create or replace function public.get_my_active_moderation()
returns table(action_type text,reason text,expires_at timestamptz)
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select m.action_type,m.reason,m.expires_at from public.yamo_moderation_actions m
  where m.user_id=auth.uid() and m.active and (m.expires_at is null or m.expires_at>now()) order by m.created_at desc
$$;

create or replace function public.yamo_expire_moderation_actions()
returns integer language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare n integer;
begin
  if auth.role()<>'service_role' then raise exception 'service_role_required'; end if;
  with expired as (update public.yamo_moderation_actions set active=false,revoked_at=now(),revoke_reason='expired automatically'
    where active and expires_at<=now() returning user_id,action_type)
  select count(*) into n from expired;
  update public.profiles p set account_status='active' where account_status='suspended'
    and not exists(select 1 from public.yamo_moderation_actions m where m.user_id=p.id and m.active
      and m.action_type in('suspend','ban') and (m.expires_at is null or m.expires_at>now()));
  return n;
end $$;

create or replace view public.admin_notification_deliveries as
select d.*,t.platform,t.app_version,n.title_ar,n.body_ar from public.yamo_notification_deliveries d
join public.yamo_device_tokens t on t.id=d.device_token_id
join public.yamo_notifications n on n.id::text=d.notification_id
where public.yamo_admin_has_permission('notifications.send');
create or replace view public.admin_system_health with(security_invoker=true) as
select * from public.yamo_system_health_events
where public.yamo_admin_has_permission('settings.manage') or public.yamo_admin_has_permission('audit.read');
revoke all on public.admin_notification_deliveries,public.admin_system_health from public,anon;
grant select on public.admin_notification_deliveries,public.admin_system_health to authenticated;

revoke all on function public.register_yamo_device_token(text,text,text,text),public.get_yamo_app_release(text,integer),
  public.get_my_active_moderation(),public.yamo_expire_moderation_actions() from public,anon;
grant execute on function public.register_yamo_device_token(text,text,text,text),public.get_my_active_moderation() to authenticated;
grant execute on function public.get_yamo_app_release(text,integer) to anon,authenticated;
grant execute on function public.yamo_expire_moderation_actions() to service_role;

commit;
notify pgrst,'reload schema';
