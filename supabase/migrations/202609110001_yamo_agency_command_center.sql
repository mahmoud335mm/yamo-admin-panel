-- Yamo Admin V223 — complete agency command center.
-- Run after 202609090001 and 202609090002.
begin;

drop function if exists public.admin_search_yamo_agency_entity(text);
create or replace function public.admin_search_yamo_agency_entity(p_query text)
returns table(
  entity_type text,user_id uuid,legacy_id text,display_name text,avatar_url text,
  account_status text,level integer,vip_level integer,coins bigint,pearls bigint,
  agency_id uuid,agency_name text,agency_level integer,host_status text,
  joined_at timestamptz,total_pearls bigint
)
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare q text:=lower(trim(coalesce(p_query,'')));
begin
  perform public.yamo_admin_require('agency.manage');
  if length(q)<1 then return; end if;
  return query
  select case when a.id is not null then 'agency_owner' when h.user_id is not null then 'host' else 'user' end,
    p.id,p.legacy_id,coalesce(p.display_name,p.legacy_id),p.avatar_url,p.account_status,
    coalesce(ul.level,0),case when vs.expires_at>now() then coalesce(vs.level,0) else 0 end,
    coalesce(w.coins,0),coalesce(w.pearls,0),coalesce(a.id,h.agency_id),
    coalesce(a.name,ha.name),coalesce(a.tree_depth,ha.tree_depth),
    case when h.user_id is null then null when h.removed_at is null then 'active' else 'removed' end,
    h.joined_at,coalesce((select sum(e.pearls) from public.yamo_agency_host_earnings e where e.user_id=p.id),0)::bigint
  from public.profiles p
  left join public.wallets w on w.user_id=p.id
  left join public.yamo_user_levels ul on ul.user_id=p.id
  left join lateral(select x.level,x.expires_at from public.yamo_vip_subscriptions x where x.user_id=p.id order by x.expires_at desc limit 1) vs on true
  left join public.yamo_agencies a on a.owner_id=p.id
  left join lateral(select x.* from public.yamo_agency_hosts x where x.user_id=p.id order by x.joined_at desc limit 1) h on true
  left join public.yamo_agencies ha on ha.id=h.agency_id
  where lower(coalesce(p.legacy_id,'')) like q||'%'
     or lower(coalesce(p.display_name,'')) like '%'||q||'%'
     or lower(coalesce(a.name,ha.name,'')) like '%'||q||'%'
     or lower(coalesce(a.host_invite_code,a.invite_code,''))=q
     or lower(coalesce(a.agency_invite_code,''))=q
  order by case when lower(coalesce(p.legacy_id,''))=q then 0
                when lower(coalesce(p.legacy_id,'')) like q||'%' then 1 else 2 end,
           p.display_name
  limit 20;
end $$;

create or replace function public.admin_get_yamo_agency_dashboard(p_days integer default 7)
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare d integer:=greatest(1,least(coalesce(p_days,7),365)); r jsonb;
begin
  perform public.yamo_admin_require('agency.manage');
  with bounds as (select now()-make_interval(days=>d) cur_from,now()-make_interval(days=>d*2) prev_from),
  earned as (
    select
      coalesce(sum(e.pearls) filter(where e.earned_at>=b.cur_from),0)::bigint gross_now,
      coalesce(sum(e.pearls) filter(where e.earned_at>=b.prev_from and e.earned_at<b.cur_from),0)::bigint gross_before,
      coalesce(sum(e.pearls) filter(where e.earned_at>=b.cur_from and lower(e.source) like '%message%'),0)::bigint messages_now,
      coalesce(sum(e.pearls) filter(where e.earned_at>=b.cur_from and lower(e.source) like '%call%'),0)::bigint calls_now,
      coalesce(sum(e.pearls) filter(where e.earned_at>=b.cur_from and lower(e.source) like '%gift%'),0)::bigint gifts_now
    from public.yamo_agency_host_earnings e cross join bounds b
  ), allocated as (
    select coalesce(sum(x.commission_pearls) filter(where x.earned_at>=b.cur_from),0)::bigint commission_now,
      coalesce(sum(x.commission_pearls) filter(where x.earned_at>=b.prev_from and x.earned_at<b.cur_from),0)::bigint commission_before
    from public.yamo_agency_commission_allocations x cross join bounds b
  )
  select jsonb_build_object(
    'period_days',d,'agencies_active',(select count(*) from public.yamo_agencies where disabled_at is null),
    'hosts_active',(select count(*) from public.yamo_agency_hosts where removed_at is null),
    'gross_now',e.gross_now,'gross_before',e.gross_before,
    'commission_now',a.commission_now,'commission_before',a.commission_before,
    'messages_now',e.messages_now,'calls_now',e.calls_now,'gifts_now',e.gifts_now,
    'pending_settlements',(select count(*) from public.yamo_agency_settlements where status in('pending','calculated')),
    'failed_settlements',(select count(*) from public.yamo_agency_settlements where status in('failed','cancelled'))
  ) into r from earned e cross join allocated a;
  return coalesce(r,'{}'::jsonb);
end $$;

create or replace function public.admin_get_yamo_agency_details(p_agency_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare r jsonb;
begin
  perform public.yamo_admin_require('agency.manage');
  select jsonb_build_object(
    'agency',to_jsonb(a),
    'owner',jsonb_build_object('id',p.id,'legacy_id',p.legacy_id,'name',coalesce(p.display_name,p.legacy_id),'avatar_url',p.avatar_url,'account_status',p.account_status),
    'parent',(select jsonb_build_object('id',pa.id,'name',pa.name,'owner_legacy_id',pp.legacy_id) from public.yamo_agencies pa join public.profiles pp on pp.id=pa.owner_id where pa.id=a.parent_agency_id),
    'children',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'depth',c.tree_depth,'owner_legacy_id',cp.legacy_id,'disabled_at',c.disabled_at) order by c.name) from public.yamo_agencies c join public.profiles cp on cp.id=c.owner_id where c.parent_agency_id=a.id),'[]'::jsonb),
    'hosts_total',(select count(*) from public.yamo_agency_hosts h where h.agency_id=a.id),
    'hosts_active',(select count(*) from public.yamo_agency_hosts h where h.agency_id=a.id and h.removed_at is null),
    'hosts_new',(select count(*) from public.yamo_agency_hosts h where h.agency_id=a.id and h.removed_at is null and h.joined_at>=now()-interval '30 days'),
    'earnings_by_source',coalesce((select jsonb_object_agg(source,total) from(select source,sum(pearls)::bigint total from public.yamo_agency_host_earnings where agency_id=a.id group by source)s),'{}'::jsonb),
    'gross_pearls',coalesce((select sum(pearls) from public.yamo_agency_host_earnings where agency_id=a.id),0),
    'commission_pearls',coalesce((select sum(commission_pearls) from public.yamo_agency_commission_allocations where beneficiary_agency_id=a.id),0),
    'losses_pearls',coalesce((select sum(amount_pearls) from public.yamo_agency_adjustments where agency_id=a.id and kind in('loss','penalty','refund')),0),
    'recent_settlements',coalesce((select jsonb_agg(to_jsonb(x) order by x.period_end desc) from(select * from public.yamo_agency_settlements where agency_id=a.id order by period_end desc limit 24)x),'[]'::jsonb),
    'tasks',coalesce((select jsonb_agg(jsonb_build_object('legacy_id',tp.legacy_id,'name',tp.display_name,'period_start',t.period_start,'period_end',t.period_end,'unique_people',t.unique_people,'calls_count',t.calls_count,'messages_count',t.messages_count,'earned_pearls',t.earned_pearls,'completed',t.completed,'rewarded',t.rewarded) order by t.period_start desc) from public.yamo_agency_host_task_periods t join public.profiles tp on tp.id=t.host_user_id where t.agency_id=a.id),'[]'::jsonb),
    'hosts',coalesce((select jsonb_agg(jsonb_build_object('user_id',hp.id,'legacy_id',hp.legacy_id,'name',coalesce(hp.display_name,hp.legacy_id),'avatar_url',hp.avatar_url,'account_status',hp.account_status,'joined_at',h.joined_at,'removed_at',h.removed_at,'task_started_at',h.task_started_at,'task_ends_at',h.task_ends_at,'earned_pearls',coalesce((select sum(e.pearls) from public.yamo_agency_host_earnings e where e.user_id=h.user_id and e.agency_id=a.id),0)) order by h.joined_at desc) from public.yamo_agency_hosts h join public.profiles hp on hp.id=h.user_id where h.agency_id=a.id),'[]'::jsonb),
    'audit_logs',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from(select id,actor_email,action,note,created_at,before_state,after_state from public.yamo_admin_audit_logs where (entity_type='yamo_agencies' and entity_id=a.id::text) or (entity_type in('yamo_agency_hosts','yamo_agency_settlements') and (after_state->>'agency_id'=a.id::text or before_state->>'agency_id'=a.id::text)) order by created_at desc limit 100)l),'[]'::jsonb)
  ) into r from public.yamo_agencies a join public.profiles p on p.id=a.owner_id where a.id=p_agency_id;
  return coalesce(r,'{}'::jsonb);
end $$;

create or replace function public.admin_run_yamo_agency_settlement(p_from date,p_to date,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare n integer; started_at timestamptz:=clock_timestamp();
begin
  perform public.yamo_admin_require('agency.manage');
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'invalid_period'; end if;
  n:=public.yamo_process_agency_settlement_period(p_from,p_to);
  update public.yamo_agency_settlements set automatic=false
    where period_start=p_from and period_end=p_to and created_at>=started_at;
  perform public.yamo_admin_log('agency.manual_settlement','yamo_agency_settlements',p_from||':'||p_to,null,jsonb_build_object('processed',n),p_reason);
  return jsonb_build_object('processed',n,'from',p_from,'to',p_to);
end $$;

revoke all on function public.admin_search_yamo_agency_entity(text),public.admin_get_yamo_agency_dashboard(integer),public.admin_get_yamo_agency_details(uuid),public.admin_run_yamo_agency_settlement(date,date,text) from public,anon;
grant execute on function public.admin_search_yamo_agency_entity(text),public.admin_get_yamo_agency_dashboard(integer),public.admin_get_yamo_agency_details(uuid),public.admin_run_yamo_agency_settlement(date,date,text) to authenticated;

commit;
notify pgrst,'reload schema';
