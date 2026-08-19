-- Yamo Chat admin completion: verification, support, moderation and releases.
begin;

insert into public.yamo_admin_permissions(permission,label_ar,category) values
  ('verification.manage','مراجعة التحقق من الهوية','users'),
  ('support.manage','إدارة تذاكر الدعم','support'),
  ('releases.manage','إدارة نسخ التطبيق','system')
on conflict(permission) do update set label_ar=excluded.label_ar,category=excluded.category;
insert into public.yamo_admin_role_permissions(role,permission)
select 'super_admin',permission from public.yamo_admin_permissions
on conflict do nothing;
insert into public.yamo_admin_role_permissions(role,permission) values
  ('admin','verification.manage'),('admin','support.manage'),('admin','releases.manage'),
  ('moderator','verification.manage'),('support','support.manage')
on conflict do nothing;

create table if not exists public.yamo_verification_requests(
  id uuid primary key default gen_random_uuid(), user_id uuid not null,
  request_type text not null default 'real_person', status text not null default 'pending'
    check(status in('pending','approved','rejected')),
  selfie_url text, document_url text, requested_gender text, note text,
  created_at timestamptz not null default now(), reviewed_at timestamptz, reviewed_by uuid
);
create index if not exists yamo_verification_pending_idx on public.yamo_verification_requests(status,created_at);

create table if not exists public.yamo_support_tickets(
  id uuid primary key default gen_random_uuid(), user_id uuid,
  category text not null default 'general', subject text not null, message text not null,
  priority text not null default 'normal' check(priority in('low','normal','high','urgent')),
  status text not null default 'open' check(status in('open','in_progress','resolved','closed')),
  admin_reply text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  assigned_to uuid, resolved_at timestamptz
);
create index if not exists yamo_support_tickets_queue_idx on public.yamo_support_tickets(status,priority,created_at);

create table if not exists public.yamo_moderation_actions(
  id uuid primary key default gen_random_uuid(), user_id uuid not null,
  action_type text not null check(action_type in('suspend','ban','room_ban','message_ban','post_ban','call_ban','warning')),
  reason text not null, starts_at timestamptz not null default now(), expires_at timestamptz,
  active boolean not null default true, created_by uuid not null default auth.uid(), created_at timestamptz not null default now(),
  revoked_at timestamptz, revoked_by uuid, revoke_reason text
);
create index if not exists yamo_moderation_actions_user_idx on public.yamo_moderation_actions(user_id,active,created_at desc);

create table if not exists public.yamo_app_releases(
  id uuid primary key default gen_random_uuid(), platform text not null check(platform in('android','ios')),
  version_name text not null, version_code integer not null check(version_code>0),
  download_url text, notes_ar text, minimum_supported_code integer not null default 1,
  force_update boolean not null default false, active boolean not null default true,
  published_at timestamptz not null default now(), created_by uuid not null default auth.uid(),
  unique(platform,version_code)
);

alter table public.yamo_verification_requests enable row level security;
alter table public.yamo_support_tickets enable row level security;
alter table public.yamo_moderation_actions enable row level security;
alter table public.yamo_app_releases enable row level security;

drop policy if exists verification_own_read on public.yamo_verification_requests;
create policy verification_own_read on public.yamo_verification_requests for select to authenticated
  using(user_id=auth.uid() or public.yamo_admin_has_permission('verification.manage'));
drop policy if exists verification_own_create on public.yamo_verification_requests;
create policy verification_own_create on public.yamo_verification_requests for insert to authenticated
  with check(user_id=auth.uid() and status='pending');
drop policy if exists support_own_read on public.yamo_support_tickets;
create policy support_own_read on public.yamo_support_tickets for select to authenticated
  using(user_id=auth.uid() or public.yamo_admin_has_permission('support.manage'));
drop policy if exists support_own_create on public.yamo_support_tickets;
create policy support_own_create on public.yamo_support_tickets for insert to authenticated
  with check(user_id=auth.uid() and status='open');
drop policy if exists moderation_admin_read on public.yamo_moderation_actions;
create policy moderation_admin_read on public.yamo_moderation_actions for select to authenticated
  using(public.yamo_admin_has_permission('users.moderate'));
drop policy if exists release_public_read on public.yamo_app_releases;
create policy release_public_read on public.yamo_app_releases for select to anon,authenticated
  using(active);

create or replace view public.admin_verification_requests with(security_invoker=true) as
select v.*,p.legacy_id,p.display_name from public.yamo_verification_requests v
left join public.profiles p on p.id=v.user_id
where public.yamo_admin_has_permission('verification.manage');
create or replace view public.admin_support_tickets with(security_invoker=true) as
select t.*,p.legacy_id,p.display_name from public.yamo_support_tickets t
left join public.profiles p on p.id=t.user_id
where public.yamo_admin_has_permission('support.manage');
create or replace view public.admin_moderation_actions with(security_invoker=true) as
select m.*,p.legacy_id,p.display_name from public.yamo_moderation_actions m
left join public.profiles p on p.id=m.user_id
where public.yamo_admin_has_permission('users.moderate');
create or replace view public.admin_app_releases with(security_invoker=true) as
select * from public.yamo_app_releases where public.yamo_admin_has_permission('releases.manage');
revoke all on public.admin_verification_requests,public.admin_support_tickets,
  public.admin_moderation_actions,public.admin_app_releases from public,anon;
grant select on public.admin_verification_requests,public.admin_support_tickets,
  public.admin_moderation_actions,public.admin_app_releases to authenticated;

create or replace function public.admin_review_verification(p_id uuid,p_action text,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare r public.yamo_verification_requests%rowtype;
begin
  perform public.yamo_admin_require('verification.manage');
  if p_action not in('approved','rejected') then raise exception 'invalid_action'; end if;
  select * into r from public.yamo_verification_requests where id=p_id for update;
  if r.id is null or r.status<>'pending' then raise exception 'request_not_pending'; end if;
  update public.yamo_verification_requests set status=p_action,note=p_note,reviewed_at=now(),reviewed_by=auth.uid() where id=p_id;
  perform public.yamo_admin_log('verification.'||p_action,'yamo_verification_requests',p_id::text,to_jsonb(r),null,p_note);
  return true;
end $$;

create or replace function public.admin_update_support_ticket(p_id uuid,p_status text,p_reply text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare b jsonb;
begin
  perform public.yamo_admin_require('support.manage');
  if p_status not in('open','in_progress','resolved','closed') then raise exception 'invalid_status'; end if;
  select to_jsonb(t) into b from public.yamo_support_tickets t where id=p_id for update;
  if b is null then raise exception 'ticket_not_found'; end if;
  update public.yamo_support_tickets set status=p_status,admin_reply=coalesce(p_reply,admin_reply),
    assigned_to=auth.uid(),updated_at=now(),resolved_at=case when p_status in('resolved','closed') then now() else null end where id=p_id;
  perform public.yamo_admin_log('support.'||p_status,'yamo_support_tickets',p_id::text,b,null,p_reply);
  return true;
end $$;

create or replace function public.admin_apply_moderation(p_legacy_id text,p_action text,p_reason text,p_days integer default null)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare u uuid; rid uuid; exp timestamptz;
begin
  perform public.yamo_admin_require('users.moderate');
  if p_action not in('suspend','ban','room_ban','message_ban','post_ban','call_ban','warning') then raise exception 'invalid_action'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'reason_required'; end if;
  if p_days is not null and (p_days<1 or p_days>3650) then raise exception 'invalid_duration'; end if;
  select id into u from public.profiles where legacy_id=p_legacy_id;
  if u is null then raise exception 'user_not_found'; end if;
  exp:=case when p_days is null then null else now()+(p_days||' days')::interval end;
  insert into public.yamo_moderation_actions(user_id,action_type,reason,expires_at) values(u,p_action,p_reason,exp) returning id into rid;
  if p_action in('suspend','ban') then update public.profiles set account_status=case when p_action='ban' then 'banned' else 'suspended' end where id=u; end if;
  perform public.yamo_admin_log('moderation.apply','profiles',p_legacy_id,null,jsonb_build_object('action',p_action,'days',p_days,'id',rid),p_reason);
  return rid;
end $$;

create or replace function public.admin_revoke_moderation(p_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare r public.yamo_moderation_actions%rowtype;
begin
  perform public.yamo_admin_require('users.moderate');
  select * into r from public.yamo_moderation_actions where id=p_id and active for update;
  if r.id is null then raise exception 'active_action_not_found'; end if;
  update public.yamo_moderation_actions set active=false,revoked_at=now(),revoked_by=auth.uid(),revoke_reason=p_reason where id=p_id;
  if r.action_type in('suspend','ban') and not exists(select 1 from public.yamo_moderation_actions where user_id=r.user_id and active and id<>r.id and action_type in('suspend','ban') and (expires_at is null or expires_at>now())) then
    update public.profiles set account_status='active' where id=r.user_id;
  end if;
  perform public.yamo_admin_log('moderation.revoke','yamo_moderation_actions',p_id::text,to_jsonb(r),null,p_reason);
  return true;
end $$;

create or replace function public.admin_upsert_app_release(p_platform text,p_version_name text,p_version_code integer,p_minimum_code integer,p_force boolean,p_url text,p_notes text)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare rid uuid;
begin
  perform public.yamo_admin_require('releases.manage');
  if p_platform not in('android','ios') or p_version_code<1 or p_minimum_code<1 or p_minimum_code>p_version_code then raise exception 'invalid_release'; end if;
  insert into public.yamo_app_releases(platform,version_name,version_code,minimum_supported_code,force_update,download_url,notes_ar)
  values(p_platform,p_version_name,p_version_code,p_minimum_code,p_force,p_url,p_notes)
  on conflict(platform,version_code) do update set version_name=excluded.version_name,minimum_supported_code=excluded.minimum_supported_code,
    force_update=excluded.force_update,download_url=excluded.download_url,notes_ar=excluded.notes_ar,active=true,published_at=now()
  returning id into rid;
  perform public.yamo_admin_log('app_release.upsert','yamo_app_releases',rid::text,null,jsonb_build_object('platform',p_platform,'version',p_version_name,'code',p_version_code,'force',p_force),p_notes);
  return rid;
end $$;

revoke all on function public.admin_review_verification(uuid,text,text),public.admin_update_support_ticket(uuid,text,text),
  public.admin_apply_moderation(text,text,text,integer),public.admin_revoke_moderation(uuid,text),
  public.admin_upsert_app_release(text,text,integer,integer,boolean,text,text) from public,anon;
grant execute on function public.admin_review_verification(uuid,text,text),public.admin_update_support_ticket(uuid,text,text),
  public.admin_apply_moderation(text,text,text,integer),public.admin_revoke_moderation(uuid,text),
  public.admin_upsert_app_release(text,text,integer,integer,boolean,text,text) to authenticated;

commit;
notify pgrst,'reload schema';
