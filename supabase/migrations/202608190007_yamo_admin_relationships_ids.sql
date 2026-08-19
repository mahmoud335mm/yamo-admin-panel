-- Administrative write paths for distinctive IDs, relationships and families.
begin;

create or replace function public.admin_upsert_distinctive_offer(p_id text, p_payload jsonb)
returns text language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('catalog.manage');
  select to_jsonb(t) into v_before from public.yamo_distinctive_id_offers t where t.id=p_id;
  insert into public.yamo_distinctive_id_offers(id,display_value,tier,price_coins,validity_days,enabled,sort_order)
  values(p_id,p_payload->>'display_value',coalesce(p_payload->>'tier','rare'),
    coalesce((p_payload->>'price_coins')::bigint,1),nullif(p_payload->>'validity_days','')::integer,
    coalesce((p_payload->>'enabled')::boolean,true),coalesce((p_payload->>'sort_order')::integer,0))
  on conflict(id) do update set display_value=excluded.display_value,tier=excluded.tier,
    price_coins=excluded.price_coins,validity_days=excluded.validity_days,
    enabled=excluded.enabled,sort_order=excluded.sort_order;
  perform public.yamo_admin_log('distinctive_offer.upsert','yamo_distinctive_id_offers',p_id,v_before,p_payload,null);
  return p_id;
end $$;
revoke all on function public.admin_upsert_distinctive_offer(text,jsonb) from public,anon;
grant execute on function public.admin_upsert_distinctive_offer(text,jsonb) to authenticated;

create or replace function public.admin_grant_distinctive_id(p_legacy_id text,p_offer_id text,p_days integer,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_user uuid; v_offer public.yamo_distinctive_id_offers%rowtype; v_exp timestamptz;
begin
  perform public.yamo_admin_require('users.moderate');
  select id into v_user from public.profiles where legacy_id=p_legacy_id;
  select * into v_offer from public.yamo_distinctive_id_offers where id=p_offer_id;
  if v_user is null then raise exception 'user_not_found'; end if;
  if v_offer.id is null then raise exception 'offer_not_found'; end if;
  if p_days is not null and (p_days < 1 or p_days > 3650) then raise exception 'invalid_duration'; end if;
  v_exp := case when p_days is null then null else now()+(p_days||' days')::interval end;
  delete from public.yamo_distinctive_ids where display_value=v_offer.display_value and user_id<>v_user;
  insert into public.yamo_distinctive_ids(user_id,offer_id,display_value,tier,expires_at,equipped,updated_at)
  values(v_user,v_offer.id,v_offer.display_value,v_offer.tier,v_exp,true,now())
  on conflict(user_id) do update set offer_id=excluded.offer_id,display_value=excluded.display_value,
    tier=excluded.tier,expires_at=excluded.expires_at,equipped=true,updated_at=now();
  perform public.yamo_admin_log('distinctive_id.grant','yamo_distinctive_ids',p_legacy_id,null,
    jsonb_build_object('offer_id',p_offer_id,'days',p_days),p_reason);
  return true;
end $$;
revoke all on function public.admin_grant_distinctive_id(text,text,integer,text) from public,anon;
grant execute on function public.admin_grant_distinctive_id(text,text,integer,text) to authenticated;

create or replace function public.admin_end_relationship(p_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('users.moderate');
  select to_jsonb(t) into v_before from public.yamo_relationships t where id=p_id;
  if v_before is null then raise exception 'relationship_not_found'; end if;
  update public.yamo_relationships set status='ended',ended_at=now(),updated_at=now() where id=p_id;
  perform public.yamo_admin_log('relationship.end','yamo_relationships',p_id::text,v_before,null,p_reason);
  return true;
end $$;
revoke all on function public.admin_end_relationship(uuid,text) from public,anon;
grant execute on function public.admin_end_relationship(uuid,text) to authenticated;

create or replace function public.admin_disband_family(p_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('users.moderate');
  select to_jsonb(t) into v_before from public.yamo_families t where id=p_id;
  if v_before is null then raise exception 'family_not_found'; end if;
  update public.yamo_families set disbanded_at=now() where id=p_id and disbanded_at is null;
  perform public.yamo_admin_log('family.disband','yamo_families',p_id::text,v_before,null,p_reason);
  return true;
end $$;
revoke all on function public.admin_disband_family(uuid,text) from public,anon;
grant execute on function public.admin_disband_family(uuid,text) to authenticated;

commit;
notify pgrst,'reload schema';
