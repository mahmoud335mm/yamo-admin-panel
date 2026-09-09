-- Yamo Admin V221 - control panel bridge for the V145 agency tree.
-- Run AFTER RUN_THIS_SQL_V145_AGENCY_TREE.sql from the Android project.
begin;

create or replace function public.admin_get_yamo_agency_tree()
returns table(
  agency_id uuid,parent_agency_id uuid,name text,owner_id uuid,owner_legacy_id text,
  owner_name text,host_invite_code text,agency_invite_code text,tree_depth integer,
  commission_percent numeric,disabled_at timestamptz,direct_hosts bigint,
  direct_commission_pearls bigint,created_at timestamptz
)
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
begin
  perform public.yamo_admin_require('agency.manage');
  return query
  select a.id,a.parent_agency_id,a.name,a.owner_id,p.legacy_id,
    coalesce(p.display_name,p.legacy_id),coalesce(a.host_invite_code,a.invite_code),
    a.agency_invite_code,a.tree_depth,a.commission_percent,a.disabled_at,
    (select count(*) from public.yamo_agency_hosts h where h.agency_id=a.id and h.removed_at is null),
    coalesce((select sum(x.commission_pearls) from public.yamo_agency_commission_allocations x
      where x.beneficiary_agency_id=a.id),0)::bigint,a.created_at
  from public.yamo_agencies a join public.profiles p on p.id=a.owner_id
  order by a.tree_depth,a.created_at;
end $$;

create or replace function public.admin_get_yamo_agency_config()
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare result jsonb;
begin
  perform public.yamo_admin_require('agency.manage');
  select jsonb_build_object(
    'enabled',c.enabled,
    'total_percent',coalesce(c.total_agency_commission_percent,c.default_commission_percent),
    'maximum_depth',c.maximum_tree_depth,
    'allow_sub_agencies',c.allow_sub_agencies,
    'minimum_settlement_pearls',c.minimum_settlement_pearls,
    'rates',coalesce((select jsonb_agg(jsonb_build_object(
      'depth',r.depth_from_host,'rate',r.commission_percent,'active',r.active)
      order by r.depth_from_host) from public.yamo_agency_level_rates r),'[]'::jsonb)
  ) into result from public.yamo_agency_config c where c.id='main';
  return coalesce(result,'{}'::jsonb);
end $$;

create or replace function public.admin_create_root_yamo_agency(
  p_owner_legacy_id text,p_name text,p_country_code text default '',p_whatsapp text default ''
) returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_owner uuid; v_id uuid; v_rate numeric;
begin
  perform public.yamo_admin_require('agency.manage');
  select id into v_owner from public.profiles where legacy_id=trim(p_owner_legacy_id);
  if v_owner is null then raise exception 'owner_not_found'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'agency_name_required'; end if;
  if exists(select 1 from public.yamo_agencies where owner_id=v_owner and disabled_at is null)
    then raise exception 'owner_already_has_agency'; end if;
  if exists(select 1 from public.yamo_agency_hosts where user_id=v_owner and removed_at is null)
    then raise exception 'host_must_leave_agency_first'; end if;
  select coalesce(total_agency_commission_percent,default_commission_percent,10)
    into v_rate from public.yamo_agency_config where id='main';
  insert into public.yamo_agencies(name,owner_id,parent_agency_id,country_code,
    whatsapp_number,invite_code,commission_percent)
  values(trim(p_name),v_owner,null,coalesce(p_country_code,''),coalesce(p_whatsapp,''),
    public.yamo_generate_agency_code('HT-YM'),v_rate) returning id into v_id;
  insert into public.yamo_account_roles(user_id,role,updated_at)
  values(v_owner,'agency_agent',now())
  on conflict(user_id) do update set role='agency_agent',agency_agent_id=null,updated_at=now();
  perform public.yamo_admin_log('agency.create_root','yamo_agencies',v_id::text,null,
    jsonb_build_object('owner_legacy_id',p_owner_legacy_id,'name',trim(p_name)),null);
  return v_id;
end $$;

create or replace function public.admin_regenerate_yamo_agency_code(p_agency_id uuid,p_kind text)
returns text language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_code text; v_before jsonb;
begin
  perform public.yamo_admin_require('agency.manage');
  select to_jsonb(a) into v_before from public.yamo_agencies a where a.id=p_agency_id;
  if v_before is null then raise exception 'agency_not_found'; end if;
  if p_kind='host' then
    v_code:=public.yamo_generate_agency_code('HT-YM');
    update public.yamo_agencies set host_invite_code=v_code,invite_code=v_code where id=p_agency_id;
  elsif p_kind='agency' then
    v_code:=public.yamo_generate_agency_code('AG-YM');
    update public.yamo_agencies set agency_invite_code=v_code where id=p_agency_id;
  else raise exception 'invalid_code_kind'; end if;
  perform public.yamo_admin_log('agency.code_regenerate','yamo_agencies',p_agency_id::text,
    v_before,jsonb_build_object('kind',p_kind),null);
  return v_code;
end $$;

-- Atomic settings save used by the panel. No partial update if validation fails.
create or replace function public.admin_save_yamo_agency_settings(
  p_total_percent numeric,p_maximum_depth integer,p_allow_sub_agencies boolean,p_rates jsonb
) returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_sum numeric;
begin
  perform public.yamo_admin_require('agency.manage');
  if p_total_percent<0 or p_total_percent>90 then raise exception 'invalid_total_agency_share'; end if;
  if p_maximum_depth<0 or p_maximum_depth>32 then raise exception 'invalid_maximum_depth'; end if;
  if jsonb_typeof(p_rates)<>'array' then raise exception 'rates_must_be_array'; end if;
  if exists(select 1 from jsonb_to_recordset(p_rates) as x(depth integer,rate numeric)
    where depth<0 or depth>32 or rate<0 or rate>90) then raise exception 'invalid_agency_rate'; end if;
  select coalesce(sum(rate),0) into v_sum from jsonb_to_recordset(p_rates) as x(depth integer,rate numeric);
  if v_sum>p_total_percent then raise exception 'level_rates_exceed_total_agency_share'; end if;
  update public.yamo_agency_config set total_agency_commission_percent=p_total_percent,
    maximum_tree_depth=p_maximum_depth,allow_sub_agencies=p_allow_sub_agencies,updated_at=now()
  where id='main';
  update public.yamo_agency_level_rates set active=false,updated_at=now(),updated_by=auth.uid();
  insert into public.yamo_agency_level_rates(depth_from_host,commission_percent,active,updated_at,updated_by)
  select depth,rate,true,now(),auth.uid() from jsonb_to_recordset(p_rates) as x(depth integer,rate numeric)
  on conflict(depth_from_host) do update set commission_percent=excluded.commission_percent,
    active=true,updated_at=now(),updated_by=auth.uid();
  perform public.yamo_admin_log('agency.settings','yamo_agency_config','main',null,
    jsonb_build_object('total_percent',p_total_percent,'maximum_depth',p_maximum_depth,
      'allow_sub_agencies',p_allow_sub_agencies,'rates',p_rates),null);
  return true;
end $$;

revoke all on function public.admin_get_yamo_agency_tree(),
  public.admin_get_yamo_agency_config(),
  public.admin_create_root_yamo_agency(text,text,text,text),
  public.admin_regenerate_yamo_agency_code(uuid,text),
  public.admin_save_yamo_agency_settings(numeric,integer,boolean,jsonb) from public,anon;
grant execute on function public.admin_get_yamo_agency_tree(),
  public.admin_get_yamo_agency_config(),
  public.admin_create_root_yamo_agency(text,text,text,text),
  public.admin_regenerate_yamo_agency_code(uuid,text),
  public.admin_save_yamo_agency_settings(numeric,integer,boolean,jsonb) to authenticated;

commit;
