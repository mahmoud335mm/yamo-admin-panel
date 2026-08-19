-- Remaining operational controls for agencies, hosts, rooms and entitlements.
begin;

create or replace view public.admin_vip_subscriptions as
select s.user_id,p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,
  s.level,s.started_at,s.expires_at,s.auto_renew,s.updated_at
from public.yamo_vip_subscriptions s join public.profiles p on p.id=s.user_id
where public.yamo_admin_has_permission('users.read');

create or replace view public.admin_distinctive_assignments as
select d.user_id,p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,
  d.offer_id,d.display_value,d.tier,d.purchased_at,d.expires_at,d.equipped,d.updated_at
from public.yamo_distinctive_ids d join public.profiles p on p.id=d.user_id
where public.yamo_admin_has_permission('users.read');

revoke all on public.admin_vip_subscriptions,public.admin_distinctive_assignments from public,anon;
grant select on public.admin_vip_subscriptions,public.admin_distinctive_assignments to authenticated;

create or replace function public.admin_set_agency_disabled(p_agency_id uuid,p_disabled boolean,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare b jsonb;
begin
  perform public.yamo_admin_require('agency.manage');
  select to_jsonb(a) into b from public.yamo_agencies a where id=p_agency_id;
  if b is null then raise exception 'agency_not_found'; end if;
  update public.yamo_agencies set disabled_at=case when p_disabled then now() else null end where id=p_agency_id;
  perform public.yamo_admin_log('agency.status','yamo_agencies',p_agency_id::text,b,
    jsonb_build_object('disabled',p_disabled),p_reason);
  return true;
end $$;
revoke all on function public.admin_set_agency_disabled(uuid,boolean,text) from public,anon;
grant execute on function public.admin_set_agency_disabled(uuid,boolean,text) to authenticated;

create or replace function public.admin_set_host_removed(p_agency_id uuid,p_user_id uuid,p_removed boolean,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare b jsonb;
begin
  perform public.yamo_admin_require('agency.manage');
  select to_jsonb(h) into b from public.yamo_agency_hosts h where agency_id=p_agency_id and user_id=p_user_id;
  if b is null then raise exception 'host_not_found'; end if;
  update public.yamo_agency_hosts set removed_at=case when p_removed then now() else null end
  where agency_id=p_agency_id and user_id=p_user_id;
  perform public.yamo_admin_log('host.status','yamo_agency_hosts',p_user_id::text,b,
    jsonb_build_object('removed',p_removed,'agency_id',p_agency_id),p_reason);
  return true;
end $$;
revoke all on function public.admin_set_host_removed(uuid,uuid,boolean,text) from public,anon;
grant execute on function public.admin_set_host_removed(uuid,uuid,boolean,text) to authenticated;

create or replace function public.admin_delete_owned_room(p_room_id text,p_reason text)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare b jsonb;
begin
  perform public.yamo_admin_require('rooms.manage');
  select to_jsonb(r) into b from public.yamo_owned_rooms r where room_id=p_room_id;
  if b is null then raise exception 'room_not_found'; end if;
  delete from public.yamo_featured_rooms where room_id=p_room_id;
  delete from public.yamo_owned_rooms where room_id=p_room_id;
  perform public.yamo_admin_log('room.delete','yamo_owned_rooms',p_room_id,b,null,p_reason);
  return true;
end $$;
revoke all on function public.admin_delete_owned_room(text,text) from public,anon;
grant execute on function public.admin_delete_owned_room(text,text) to authenticated;

create or replace function public.admin_revoke_yamo_vip(p_legacy_id text,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare u uuid; b jsonb;
begin
  perform public.yamo_admin_require('users.moderate');
  select id into u from public.profiles where legacy_id=p_legacy_id;
  select to_jsonb(s) into b from public.yamo_vip_subscriptions s where user_id=u;
  if u is null then raise exception 'user_not_found'; end if;
  delete from public.yamo_vip_subscriptions where user_id=u;
  perform public.yamo_admin_log('vip.revoke','yamo_vip_subscriptions',p_legacy_id,b,null,p_reason);
  return true;
end $$;
revoke all on function public.admin_revoke_yamo_vip(text,text) from public,anon;
grant execute on function public.admin_revoke_yamo_vip(text,text) to authenticated;

create or replace function public.admin_revoke_distinctive_id(p_legacy_id text,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare u uuid; b jsonb;
begin
  perform public.yamo_admin_require('users.moderate');
  select id into u from public.profiles where legacy_id=p_legacy_id;
  select to_jsonb(d) into b from public.yamo_distinctive_ids d where user_id=u;
  if u is null then raise exception 'user_not_found'; end if;
  delete from public.yamo_distinctive_ids where user_id=u;
  perform public.yamo_admin_log('distinctive_id.revoke','yamo_distinctive_ids',p_legacy_id,b,null,p_reason);
  return true;
end $$;
revoke all on function public.admin_revoke_distinctive_id(text,text) from public,anon;
grant execute on function public.admin_revoke_distinctive_id(text,text) to authenticated;

create or replace function public.admin_set_admin_active(p_user_id uuid,p_active boolean)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  perform public.yamo_admin_require('admins.manage');
  if p_user_id=auth.uid() and not p_active then raise exception 'cannot_disable_self'; end if;
  update public.yamo_admin_users set is_active=p_active where user_id=p_user_id;
  if not found then raise exception 'admin_not_found'; end if;
  perform public.yamo_admin_log('admin.status','yamo_admin_users',p_user_id::text,null,
    jsonb_build_object('active',p_active),null);
  return true;
end $$;
revoke all on function public.admin_set_admin_active(uuid,boolean) from public,anon;
grant execute on function public.admin_set_admin_active(uuid,boolean) to authenticated;

commit;
notify pgrst,'reload schema';
