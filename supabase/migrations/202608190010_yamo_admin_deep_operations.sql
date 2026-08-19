-- Deep operational modules: level rules, inventory grants, task rewards,
-- agency settlements, room presence and gift history.
begin;

create or replace view public.admin_level_rules as select * from public.yamo_level_rules
where public.yamo_admin_has_permission('settings.manage');
create or replace view public.admin_user_assets as
select a.user_id,p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,
  a.asset_kind,a.asset_key,a.granted_at,a.expires_at
from public.yamo_user_assets a join public.profiles p on p.id=a.user_id
where public.yamo_admin_has_permission('catalog.manage');
create or replace view public.admin_task_milestones as select * from public.yamo_task_milestones
where public.yamo_admin_has_permission('tasks.manage');
create or replace view public.admin_room_presence as
select r.room_id,r.user_id,p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,
  r.joined_at,r.last_seen_at,r.left_at
from public.yamo_room_runtime_presence r join public.profiles p on p.id=r.user_id
where public.yamo_admin_has_permission('rooms.manage');
create or replace view public.admin_gift_batches as
select b.id,b.room_id,b.sender_id,p.legacy_id sender_legacy_id,b.gift_id,b.quantity,
  b.receiver_count,b.total_coins,b.balance_after,b.created_at
from public.room_gift_batches b join public.profiles p on p.id=b.sender_id
where public.yamo_admin_has_permission('economy.read');

revoke all on public.admin_level_rules,public.admin_user_assets,public.admin_task_milestones,
  public.admin_room_presence,public.admin_gift_batches from public,anon;
grant select on public.admin_level_rules,public.admin_user_assets,public.admin_task_milestones,
  public.admin_room_presence,public.admin_gift_batches to authenticated;

create or replace function public.admin_upsert_level_rule(p_rule_key text,p_payload jsonb)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare b jsonb;
begin
  perform public.yamo_admin_require('settings.manage');
  select to_jsonb(r) into b from public.yamo_level_rules r where rule_key=p_rule_key;
  insert into public.yamo_level_rules(rule_key,title_ar,icon_key,coins_required,points_granted,enabled,sort_order,updated_at)
  values(p_rule_key,coalesce(p_payload->>'title_ar',p_rule_key),coalesce(p_payload->>'icon_key','star'),
    coalesce((p_payload->>'coins_required')::bigint,1),coalesce((p_payload->>'points_granted')::bigint,1),
    coalesce((p_payload->>'enabled')::boolean,true),coalesce((p_payload->>'sort_order')::integer,0),now())
  on conflict(rule_key) do update set title_ar=excluded.title_ar,icon_key=excluded.icon_key,
    coins_required=excluded.coins_required,points_granted=excluded.points_granted,
    enabled=excluded.enabled,sort_order=excluded.sort_order,updated_at=now();
  perform public.yamo_admin_log('level_rule.upsert','yamo_level_rules',p_rule_key,b,p_payload,null);
  return true;
end $$;
revoke all on function public.admin_upsert_level_rule(text,jsonb) from public,anon;
grant execute on function public.admin_upsert_level_rule(text,jsonb) to authenticated;

create or replace function public.admin_grant_user_asset(p_legacy_id text,p_asset_kind text,p_asset_key text,p_days integer,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare u uuid; exp timestamptz;
begin
  perform public.yamo_admin_require('catalog.manage');
  select id into u from public.profiles where legacy_id=p_legacy_id;
  if u is null then raise exception 'user_not_found'; end if;
  if not exists(select 1 from public.yamo_store_assets where asset_kind=p_asset_kind and asset_key=p_asset_key) then raise exception 'asset_not_found'; end if;
  if p_days is not null and (p_days<1 or p_days>3650) then raise exception 'invalid_duration'; end if;
  exp:=case when p_days is null then null else now()+(p_days||' days')::interval end;
  insert into public.yamo_user_assets(user_id,asset_kind,asset_key,expires_at)
  values(u,p_asset_kind,p_asset_key,exp)
  on conflict(user_id,asset_kind,asset_key) do update set granted_at=now(),expires_at=excluded.expires_at;
  perform public.yamo_admin_log('asset.grant','yamo_user_assets',p_legacy_id,null,
    jsonb_build_object('kind',p_asset_kind,'key',p_asset_key,'days',p_days),p_reason);
  return true;
end $$;
revoke all on function public.admin_grant_user_asset(text,text,text,integer,text) from public,anon;
grant execute on function public.admin_grant_user_asset(text,text,text,integer,text) to authenticated;

create or replace function public.admin_revoke_user_asset(p_user_id uuid,p_asset_kind text,p_asset_key text,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare b jsonb;
begin
  perform public.yamo_admin_require('catalog.manage');
  select to_jsonb(a) into b from public.yamo_user_assets a where user_id=p_user_id and asset_kind=p_asset_kind and asset_key=p_asset_key;
  delete from public.yamo_equipped_assets where user_id=p_user_id and asset_kind=p_asset_kind and asset_key=p_asset_key;
  delete from public.yamo_user_assets where user_id=p_user_id and asset_kind=p_asset_kind and asset_key=p_asset_key;
  perform public.yamo_admin_log('asset.revoke','yamo_user_assets',p_user_id::text,b,null,p_reason);
  return true;
end $$;
revoke all on function public.admin_revoke_user_asset(uuid,text,text,text) from public,anon;
grant execute on function public.admin_revoke_user_asset(uuid,text,text,text) to authenticated;

create or replace function public.admin_set_agency_settlement_status(p_id uuid,p_status text,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare b jsonb;
begin
  perform public.yamo_admin_require('agency.manage');
  if p_status not in('settled','cancelled') then raise exception 'invalid_status'; end if;
  select to_jsonb(s) into b from public.yamo_agency_settlements s where id=p_id for update;
  if b is null then raise exception 'settlement_not_found'; end if;
  update public.yamo_agency_settlements set status=p_status,
    settled_at=case when p_status='settled' then now() else null end,
    settled_by=case when p_status='settled' then auth.uid() else null end where id=p_id;
  perform public.yamo_admin_log('agency_settlement.'||p_status,'yamo_agency_settlements',p_id::text,b,null,p_reason);
  return true;
end $$;
revoke all on function public.admin_set_agency_settlement_status(uuid,text,text) from public,anon;
grant execute on function public.admin_set_agency_settlement_status(uuid,text,text) to authenticated;

create or replace function public.admin_remove_room_presence(p_room_id text,p_user_id uuid,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  perform public.yamo_admin_require('rooms.manage');
  update public.yamo_room_runtime_presence set left_at=now(),last_seen_at=now()
  where room_id=p_room_id and user_id=p_user_id and left_at is null;
  perform public.yamo_admin_log('room.presence.remove','yamo_room_runtime_presence',p_room_id,
    null,jsonb_build_object('user_id',p_user_id),p_reason);
  return true;
end $$;
revoke all on function public.admin_remove_room_presence(text,uuid,text) from public,anon;
grant execute on function public.admin_remove_room_presence(text,uuid,text) to authenticated;

commit;
notify pgrst,'reload schema';
