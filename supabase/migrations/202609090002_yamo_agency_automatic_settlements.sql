-- Yamo Chat V147 — automatic agency targets, settlements and searchable details.
-- Prerequisites: V145 agency tree + V221 admin bridge.
begin;

alter table public.yamo_agency_config
  add column if not exists agency_percent numeric(5,2) not null default 10,
  add column if not exists parent_agency_percent numeric(5,2) not null default 0,
  add column if not exists platform_percent numeric(5,2) not null default 0,
  add column if not exists settlement_frequency text not null default 'weekly',
  add column if not exists settlement_weekday integer not null default 1,
  add column if not exists settlement_hour integer not null default 0,
  add column if not exists below_target_action text not null default 'platform',
  add column if not exists automatic_settlements boolean not null default true,
  add column if not exists host_task_days integer not null default 14,
  add column if not exists host_task_unique_people integer not null default 10,
  add column if not exists host_task_reward_pearls bigint not null default 10000,
  add column if not exists agency_task_reward_pearls bigint not null default 10000,
  add column if not exists male_recharge_threshold_coins bigint not null default 100000,
  add column if not exists male_recharge_agency_percent numeric(5,2) not null default 0;

alter table public.yamo_agencies
  add column if not exists parent_benefit_started_at timestamptz,
  add column if not exists parent_benefit_ends_at timestamptz,
  add column if not exists parent_benefit_permanent boolean not null default false,
  add column if not exists promoted_to_root_at timestamptz;

alter table public.yamo_agency_hosts
  add column if not exists task_started_at timestamptz,
  add column if not exists task_ends_at timestamptz;

alter table public.yamo_agency_host_earnings
  add column if not exists counterparty_user_id uuid references auth.users(id);

update public.yamo_agency_hosts set task_started_at=coalesce(task_started_at,joined_at),
  task_ends_at=coalesce(task_ends_at,joined_at + interval '14 days')
where removed_at is null;

alter table public.yamo_agency_settlements
  add column if not exists gross_pearls bigint not null default 0,
  add column if not exists losses_pearls bigint not null default 0,
  add column if not exists net_pearls bigint not null default 0,
  add column if not exists target_pearls bigint not null default 0,
  add column if not exists target_achieved boolean not null default false,
  add column if not exists platform_pearls bigint not null default 0,
  add column if not exists source_breakdown jsonb not null default '{}'::jsonb,
  add column if not exists failure_reason text,
  add column if not exists automatic boolean not null default false,
  add column if not exists payout_reference text;

create unique index if not exists yamo_agency_settlement_payout_ref_uq
  on public.yamo_agency_settlements(payout_reference) where payout_reference is not null;

create table if not exists public.yamo_agency_adjustments(
  id uuid primary key default gen_random_uuid(), agency_id uuid not null references public.yamo_agencies(id),
  amount_pearls bigint not null, kind text not null check(kind in('loss','penalty','refund','bonus')),
  reason text not null, reference_id text, occurred_at timestamptz not null default now(),
  created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique(agency_id,kind,reference_id)
);

create table if not exists public.yamo_agency_host_task_periods(
  id uuid primary key default gen_random_uuid(), agency_id uuid not null references public.yamo_agencies(id),
  host_user_id uuid not null references auth.users(id), period_start date not null, period_end date not null,
  unique_people integer not null default 0, calls_count integer not null default 0,
  messages_count integer not null default 0, earned_pearls bigint not null default 0,
  completed boolean not null default false, rewarded boolean not null default false,
  host_reward_pearls bigint not null default 0, agency_reward_pearls bigint not null default 0,
  rewarded_at timestamptz, created_at timestamptz not null default now(),
  unique(host_user_id,period_start,period_end)
);

create table if not exists public.yamo_agency_carry_balances(
  agency_id uuid primary key references public.yamo_agencies(id),
  pearls bigint not null default 0 check(pearls>=0),updated_at timestamptz not null default now()
);

drop view if exists public.admin_agency_settlements;
create view public.admin_agency_settlements with (security_invoker=true) as
select s.id,s.agency_id,a.name agency_name,s.period_start,s.period_end,s.host_pearls,
 s.commission_pearls,s.commission_percent,s.gross_pearls,s.losses_pearls,s.net_pearls,
 s.target_pearls,s.target_achieved,s.platform_pearls,s.source_breakdown,s.failure_reason,
 s.automatic,s.payout_reference,s.status,s.created_at,s.settled_at
from public.yamo_agency_settlements s join public.yamo_agencies a on a.id=s.agency_id
where public.yamo_admin_has_permission('agency.manage') or public.yamo_admin_has_permission('economy.read');
grant select on public.admin_agency_settlements to authenticated;

create or replace function public.admin_save_yamo_agency_finance_config(
  p_agency_percent numeric,p_parent_percent numeric,p_platform_percent numeric,
  p_minimum_target bigint,p_frequency text,p_below_target_action text,
  p_automatic boolean,p_host_task_days integer,p_unique_people integer,
  p_host_reward bigint,p_agency_reward bigint,p_male_recharge_threshold bigint,
  p_male_recharge_percent numeric
) returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  perform public.yamo_admin_require('agency.manage');
  if p_agency_percent not between 0 and 100 or p_parent_percent not between 0 and 100
     or p_platform_percent not between 0 and 100 or
     p_agency_percent+p_parent_percent+p_platform_percent>100 then raise exception 'percent_total_must_be_0_to_100'; end if;
  if p_minimum_target<0 then raise exception 'invalid_minimum_target'; end if;
  if p_frequency not in('weekly','monthly') then raise exception 'invalid_frequency'; end if;
  if p_below_target_action not in('platform','carry') then raise exception 'invalid_below_target_action'; end if;
  update public.yamo_agency_config set agency_percent=p_agency_percent,
    parent_agency_percent=p_parent_percent,platform_percent=p_platform_percent,
    total_agency_commission_percent=p_agency_percent+p_parent_percent,
    default_commission_percent=p_agency_percent,minimum_settlement_pearls=p_minimum_target,
    settlement_frequency=p_frequency,below_target_action=p_below_target_action,
    automatic_settlements=p_automatic,host_task_days=greatest(p_host_task_days,0),
    host_task_unique_people=greatest(p_unique_people,0),host_task_reward_pearls=greatest(p_host_reward,0),
    agency_task_reward_pearls=greatest(p_agency_reward,0),
    male_recharge_threshold_coins=greatest(p_male_recharge_threshold,0),
    male_recharge_agency_percent=p_male_recharge_percent,updated_at=now() where id='main';
  insert into public.yamo_agency_level_rates(depth_from_host,commission_percent,active,updated_at,updated_by)
  values(0,p_agency_percent,true,now(),auth.uid()),(1,p_parent_percent,p_parent_percent>0,now(),auth.uid())
  on conflict(depth_from_host) do update set commission_percent=excluded.commission_percent,
    active=excluded.active,updated_at=now(),updated_by=auth.uid();
  update public.yamo_agency_level_rates set active=false,updated_at=now(),updated_by=auth.uid()
    where depth_from_host>1;
  return true;
end $$;

create or replace function public.yamo_capture_male_recharge_agency_reward()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_agency uuid; v_rate numeric; v_threshold bigint; v_reward bigint; v_gender text;
begin
  if new.status<>'completed' or old.status='completed' then return new; end if;
  select lower(coalesce(gender::text,'')) into v_gender from public.profiles where id=new.user_id;
  if v_gender not in('male','ذكر') then return new; end if;
  select male_recharge_threshold_coins,male_recharge_agency_percent into v_threshold,v_rate
    from public.yamo_agency_config where id='main';
  if new.coins<coalesce(v_threshold,0) or coalesce(v_rate,0)<=0 then return new; end if;
  select agency_id into v_agency from public.yamo_agency_hosts
    where user_id=new.user_id and removed_at is null order by joined_at desc limit 1;
  if v_agency is null then return new; end if;
  v_reward:=floor(new.coins*v_rate/100.0);
  insert into public.yamo_agency_adjustments(agency_id,amount_pearls,kind,reason,reference_id)
  values(v_agency,v_reward,'bonus','male_recharge',new.id::text)
  on conflict(agency_id,kind,reference_id) do nothing;
  return new;
end $$;

drop trigger if exists yamo_capture_male_recharge_agency_reward_tr on public.yamo_recharge_requests;
create trigger yamo_capture_male_recharge_agency_reward_tr after update of status
on public.yamo_recharge_requests for each row execute function public.yamo_capture_male_recharge_agency_reward();

create or replace function public.admin_set_yamo_agency_parent_term(
  p_agency_id uuid,p_parent_id uuid,p_duration_days integer,p_permanent boolean,p_reason text
) returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  perform public.yamo_admin_require('agency.manage');
  perform public.yamo_validate_agency_tree(p_agency_id,p_parent_id);
  if p_parent_id is not null and not p_permanent and coalesce(p_duration_days,0)<=0 then raise exception 'duration_required'; end if;
  update public.yamo_agencies set parent_agency_id=p_parent_id,
    parent_benefit_started_at=case when p_parent_id is null then null else now() end,
    parent_benefit_ends_at=case when p_parent_id is null or p_permanent then null else now()+make_interval(days=>p_duration_days) end,
    parent_benefit_permanent=coalesce(p_permanent,false),promoted_to_root_at=null where id=p_agency_id;
  if not found then raise exception 'agency_not_found'; end if;
  perform public.yamo_admin_log('agency.parent_term','yamo_agencies',p_agency_id::text,null,
    jsonb_build_object('parent',p_parent_id,'days',p_duration_days,'permanent',p_permanent),p_reason);
  return true;
end $$;

create or replace function public.admin_create_yamo_agency_v2(
  p_owner_legacy_id text,p_name text,p_parent_id uuid,p_duration_days integer,
  p_permanent boolean,p_country_code text default '',p_whatsapp text default ''
) returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_owner uuid; v_id uuid; v_rate numeric;
begin
  perform public.yamo_admin_require('agency.manage');
  select id into v_owner from public.profiles where legacy_id=trim(p_owner_legacy_id);
  if v_owner is null then raise exception 'owner_not_found'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'agency_name_required'; end if;
  if exists(select 1 from public.yamo_agencies where owner_id=v_owner and disabled_at is null) then raise exception 'owner_already_has_agency'; end if;
  if exists(select 1 from public.yamo_agency_hosts where user_id=v_owner and removed_at is null) then raise exception 'host_must_leave_agency_first'; end if;
  if p_parent_id is not null and not p_permanent and coalesce(p_duration_days,0)<=0 then raise exception 'duration_required'; end if;
  select agency_percent into v_rate from public.yamo_agency_config where id='main';
  insert into public.yamo_agencies(name,owner_id,parent_agency_id,country_code,whatsapp_number,
    invite_code,commission_percent,parent_benefit_started_at,parent_benefit_ends_at,parent_benefit_permanent)
  values(trim(p_name),v_owner,p_parent_id,coalesce(p_country_code,''),coalesce(p_whatsapp,''),
    public.yamo_generate_agency_code('HT-YM'),coalesce(v_rate,10),case when p_parent_id is null then null else now() end,
    case when p_parent_id is null or p_permanent then null else now()+make_interval(days=>p_duration_days) end,
    p_parent_id is not null and coalesce(p_permanent,false)) returning id into v_id;
  insert into public.yamo_account_roles(user_id,role,agency_agent_id,updated_at)
  values(v_owner,'agency_agent',(select owner_id from public.yamo_agencies where id=p_parent_id),now())
  on conflict(user_id) do update set role='agency_agent',agency_agent_id=excluded.agency_agent_id,updated_at=now();
  return v_id;
end $$;

create or replace function public.yamo_promote_expired_sub_agencies()
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
  update public.yamo_agencies set parent_agency_id=null,tree_depth=0,promoted_to_root_at=now()
  where parent_agency_id is not null and not parent_benefit_permanent
    and parent_benefit_ends_at is not null and parent_benefit_ends_at<=now() and disabled_at is null;
  get diagnostics n=row_count;
  with recursive depths as (
    select id,0 depth from public.yamo_agencies where parent_agency_id is null
    union all select a.id,d.depth+1 from public.yamo_agencies a join depths d on a.parent_agency_id=d.id
  ) update public.yamo_agencies a set tree_depth=d.depth from depths d where a.id=d.id and a.tree_depth<>d.depth;
  return n;
end $$;

create or replace function public.yamo_refresh_weekly_host_tasks(p_day date default current_date)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_start date:=date_trunc('week',p_day)::date; v_end date:=v_start+6; n integer; x record;
begin
  insert into public.yamo_agency_host_task_periods(agency_id,host_user_id,period_start,period_end,
    calls_count,messages_count,unique_people,earned_pearls,completed)
  select h.agency_id,h.user_id,v_start,v_end,
    count(*) filter(where e.source ilike '%call%')::integer,
    count(*) filter(where e.source ilike '%message%')::integer,
    count(distinct coalesce(e.counterparty_user_id::text,nullif(e.reference_id,'')))::integer,coalesce(sum(e.pearls),0),
    count(distinct coalesce(e.counterparty_user_id::text,nullif(e.reference_id,''))) >= c.host_task_unique_people
  from public.yamo_agency_hosts h cross join public.yamo_agency_config c
  left join public.yamo_agency_host_earnings e on e.user_id=h.user_id
    and e.earned_at>=v_start and e.earned_at<v_end+1
  where h.removed_at is null and h.task_started_at<=v_end+1 and (h.task_ends_at is null or h.task_ends_at>=v_start)
  group by h.agency_id,h.user_id,c.host_task_unique_people
  on conflict(host_user_id,period_start,period_end) do update set calls_count=excluded.calls_count,
    messages_count=excluded.messages_count,unique_people=excluded.unique_people,
    earned_pearls=excluded.earned_pearls,completed=excluded.completed;
  get diagnostics n=row_count;
  for x in select t.id,t.host_user_id,t.agency_id,c.host_task_reward_pearls host_reward,
      c.agency_task_reward_pearls agency_reward
    from public.yamo_agency_host_task_periods t cross join public.yamo_agency_config c
    where t.period_start=v_start and t.completed and not t.rewarded for update of t skip locked loop
    update public.yamo_agency_host_task_periods set rewarded=true,host_reward_pearls=x.host_reward,
      agency_reward_pearls=x.agency_reward,rewarded_at=now() where id=x.id;
    if x.host_reward>0 then
      update public.wallets set pearls=pearls+x.host_reward,updated_at=now() where user_id=x.host_user_id;
      insert into public.yamo_wallet_events(user_id,asset,amount,reason,reference_id)
      values(x.host_user_id,'pearls',x.host_reward,'weekly_host_task','host-task:'||x.id);
    end if;
    if x.agency_reward>0 then
      insert into public.yamo_agency_adjustments(agency_id,amount_pearls,kind,reason,reference_id)
      values(x.agency_id,x.agency_reward,'bonus','weekly_host_task','agency-task:'||x.id)
      on conflict(agency_id,kind,reference_id) do nothing;
    end if;
  end loop;
  return n;
end $$;

create or replace function public.yamo_process_agency_settlement_period(p_from date,p_to date)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare a record; c public.yamo_agency_config%rowtype; v_gross bigint; v_comm bigint; v_loss bigint; v_bonus bigint;
  v_net bigint; v_ok boolean; v_platform bigint; v_carry bigint; v_breakdown jsonb; n integer:=0; v_ref text; v_created boolean;
begin
  select * into c from public.yamo_agency_config where id='main';
  for a in select * from public.yamo_agencies where disabled_at is null loop
    select coalesce(sum(gross_pearls),0),coalesce(sum(commission_pearls),0),
      coalesce(jsonb_object_agg(source,total), '{}'::jsonb) into v_gross,v_comm,v_breakdown
    from (select source,sum(gross_pearls)::bigint gross_pearls,sum(commission_pearls)::bigint total
      from public.yamo_agency_commission_allocations where beneficiary_agency_id=a.id
      and earned_at>=p_from and earned_at<p_to+1 group by source) s;
    select coalesce(sum(amount_pearls),0) into v_loss from public.yamo_agency_adjustments
      where agency_id=a.id and kind in('loss','penalty','refund') and occurred_at>=p_from and occurred_at<p_to+1;
    select coalesce(sum(amount_pearls),0) into v_bonus from public.yamo_agency_adjustments
      where agency_id=a.id and kind='bonus' and occurred_at>=p_from and occurred_at<p_to+1;
    select coalesce(pearls,0) into v_carry from public.yamo_agency_carry_balances where agency_id=a.id;
    v_carry:=coalesce(v_carry,0);
    v_net:=greatest(v_comm+v_bonus+v_carry-v_loss,0); v_ok:=v_gross>=c.minimum_settlement_pearls;
    v_platform:=case when not v_ok and c.below_target_action='platform' then v_net else floor(v_gross*c.platform_percent/100.0) end;
    v_ref:='agency-settlement:'||a.id||':'||p_from||':'||p_to;
    insert into public.yamo_agency_settlements(agency_id,period_start,period_end,host_pearls,
      commission_pearls,commission_percent,gross_pearls,losses_pearls,net_pearls,target_pearls,
      target_achieved,platform_pearls,source_breakdown,status,failure_reason,automatic,payout_reference,settled_at)
    values(a.id,p_from,p_to,v_gross,case when v_ok then v_net else 0 end,a.commission_percent,
      v_gross,v_loss,case when v_ok then v_net else 0 end,c.minimum_settlement_pearls,v_ok,v_platform,v_breakdown,
      case when v_ok then 'settled' else 'below_target' end,
      case when v_ok then null else 'minimum_target_not_reached' end,true,v_ref,now())
    on conflict(agency_id,period_start,period_end) do nothing;
    v_created:=found;
    if v_created then
      insert into public.yamo_agency_carry_balances(agency_id,pearls,updated_at)
      values(a.id,case when not v_ok and c.below_target_action='carry' then v_net else 0 end,now())
      on conflict(agency_id) do update set pearls=excluded.pearls,updated_at=now();
    end if;
    if v_created and v_ok and v_net>0 then
      update public.wallets set pearls=pearls+v_net,updated_at=now() where user_id=a.owner_id;
      if not found then raise exception 'agency_owner_wallet_not_found'; end if;
      insert into public.yamo_wallet_events(user_id,asset,amount,reason,reference_id)
      values(a.owner_id,'pearls',v_net,'automatic_agency_settlement',v_ref);
    end if;
    if v_created then n:=n+1; end if;
  end loop; return n;
end $$;

create or replace function public.yamo_process_due_agency_settlements()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c public.yamo_agency_config%rowtype; f date; t date; n integer:=0; promoted integer:=0; tasks integer:=0;
begin
  select * into c from public.yamo_agency_config where id='main';
  promoted:=public.yamo_promote_expired_sub_agencies();
  tasks:=public.yamo_refresh_weekly_host_tasks(current_date);
  if not c.automatic_settlements then return jsonb_build_object('disabled',true,'promoted',promoted,'tasks',tasks); end if;
  if c.settlement_frequency='monthly' then f:=(date_trunc('month',current_date)-interval '1 month')::date; t:=(date_trunc('month',current_date)-interval '1 day')::date;
  else f:=(date_trunc('week',current_date)-interval '1 week')::date; t:=(date_trunc('week',current_date)-interval '1 day')::date; end if;
  n:=public.yamo_process_agency_settlement_period(f,t);
  return jsonb_build_object('processed',n,'from',f,'to',t,'promoted',promoted,'tasks',tasks);
end $$;

create or replace function public.admin_get_yamo_agency_finance_config()
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare r jsonb; begin perform public.yamo_admin_require('agency.manage');
select to_jsonb(c) into r from public.yamo_agency_config c where id='main'; return coalesce(r,'{}'); end $$;

create or replace function public.get_yamo_agency_live_config()
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare r jsonb; begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select jsonb_build_object('minimum_target_pearls',c.minimum_settlement_pearls,
    'frequency',c.settlement_frequency,'automatic',c.automatic_settlements,
    'agency_percent',c.agency_percent,'parent_percent',c.parent_agency_percent,
    'host_task_days',c.host_task_days,'host_task_unique_people',c.host_task_unique_people,
    'host_reward_pearls',c.host_task_reward_pearls,'agency_reward_pearls',c.agency_task_reward_pearls,
    'male_recharge_threshold_coins',c.male_recharge_threshold_coins,
    'male_recharge_percent',c.male_recharge_agency_percent) into r
  from public.yamo_agency_config c where c.id='main'; return coalesce(r,'{}');
end $$;

create or replace function public.admin_search_yamo_agency_entity(p_query text)
returns table(entity_type text,legacy_id text,display_name text,agency_id uuid,agency_name text,
  agency_level integer,host_status text,joined_at timestamptz,total_pearls bigint)
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
begin perform public.yamo_admin_require('agency.manage'); return query
select case when a.id is not null then 'agency_owner' when h.user_id is not null then 'host' else 'user' end,
 p.legacy_id,p.display_name,coalesce(a.id,h.agency_id),coalesce(a.name,ha.name),coalesce(a.tree_depth,ha.tree_depth),
 case when h.user_id is null then null when h.removed_at is null then 'active' else 'removed' end,h.joined_at,
 coalesce((select sum(e.pearls) from public.yamo_agency_host_earnings e where e.user_id=p.id),0)::bigint
from public.profiles p left join public.yamo_agencies a on a.owner_id=p.id
left join lateral(select * from public.yamo_agency_hosts x where x.user_id=p.id order by x.joined_at desc limit 1) h on true
left join public.yamo_agencies ha on ha.id=h.agency_id
where lower(p.legacy_id)=lower(trim(p_query)) or lower(coalesce(p.display_name,'')) like '%'||lower(trim(p_query))||'%'
   or lower(coalesce(a.name,ha.name,'')) like '%'||lower(trim(p_query))||'%' limit 50; end $$;

create or replace function public.admin_get_yamo_agency_details(p_agency_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare r jsonb; begin perform public.yamo_admin_require('agency.manage');
select jsonb_build_object('agency',to_jsonb(a),'owner',jsonb_build_object('legacy_id',p.legacy_id,'name',p.display_name),
 'hosts_total',(select count(*) from public.yamo_agency_hosts h where h.agency_id=a.id),
 'hosts_active',(select count(*) from public.yamo_agency_hosts h where h.agency_id=a.id and h.removed_at is null),
 'hosts_new',(select count(*) from public.yamo_agency_hosts h where h.agency_id=a.id and h.removed_at is null and h.joined_at>=now()-interval '30 days'),
 'earnings_by_source',coalesce((select jsonb_object_agg(source,total) from(select source,sum(pearls)::bigint total from public.yamo_agency_host_earnings where agency_id=a.id group by source)s),'{}'::jsonb),
 'gross_pearls',coalesce((select sum(pearls) from public.yamo_agency_host_earnings where agency_id=a.id),0),
 'commission_pearls',coalesce((select sum(commission_pearls) from public.yamo_agency_commission_allocations where beneficiary_agency_id=a.id),0),
 'losses_pearls',coalesce((select sum(amount_pearls) from public.yamo_agency_adjustments where agency_id=a.id and kind in('loss','penalty','refund')),0),
 'recent_settlements',coalesce((select jsonb_agg(to_jsonb(x) order by x.period_end desc) from(select * from public.yamo_agency_settlements where agency_id=a.id limit 12)x),'[]'::jsonb),
 'hosts',coalesce((select jsonb_agg(jsonb_build_object('legacy_id',hp.legacy_id,'name',hp.display_name,'joined_at',h.joined_at,'removed_at',h.removed_at,'task_ends_at',h.task_ends_at)) from public.yamo_agency_hosts h join public.profiles hp on hp.id=h.user_id where h.agency_id=a.id),'[]'::jsonb)) into r
from public.yamo_agencies a join public.profiles p on p.id=a.owner_id where a.id=p_agency_id; return coalesce(r,'{}'); end $$;

-- Daily maintenance; settlement function itself is idempotent per agency/period.
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    if exists(select 1 from cron.job where jobname='yamo-agency-auto-settlements') then
      perform cron.unschedule((select jobid from cron.job where jobname='yamo-agency-auto-settlements' limit 1));
    end if;
    perform cron.schedule('yamo-agency-auto-settlements','15 0 * * *','select public.yamo_process_due_agency_settlements();');
  end if;
exception when others then raise notice 'Cron was not configured: %',sqlerrm; end $$;

revoke all on function public.admin_save_yamo_agency_finance_config(numeric,numeric,numeric,bigint,text,text,boolean,integer,integer,bigint,bigint,bigint,numeric),
 public.admin_set_yamo_agency_parent_term(uuid,uuid,integer,boolean,text),
 public.admin_create_yamo_agency_v2(text,text,uuid,integer,boolean,text,text),
 public.admin_get_yamo_agency_finance_config(),public.admin_search_yamo_agency_entity(text),
 public.admin_get_yamo_agency_details(uuid) from public,anon;
grant execute on function public.admin_save_yamo_agency_finance_config(numeric,numeric,numeric,bigint,text,text,boolean,integer,integer,bigint,bigint,bigint,numeric),
 public.admin_set_yamo_agency_parent_term(uuid,uuid,integer,boolean,text),
 public.admin_create_yamo_agency_v2(text,text,uuid,integer,boolean,text,text),
 public.admin_get_yamo_agency_finance_config(),public.admin_search_yamo_agency_entity(text),
 public.admin_get_yamo_agency_details(uuid) to authenticated;
grant execute on function public.yamo_process_due_agency_settlements() to postgres,service_role;
grant execute on function public.get_yamo_agency_live_config() to authenticated;

commit;
notify pgrst,'reload schema';
