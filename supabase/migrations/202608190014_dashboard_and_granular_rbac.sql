-- Executive dashboard and per-admin permission overrides.
begin;

insert into public.yamo_admin_permissions(permission,label_ar,category) values
  ('dashboard.view','عرض لوحة المؤشرات','dashboard'),
  ('users.suspend','إيقاف المستخدم مؤقتًا','users'),
  ('users.ban','حظر المستخدم نهائيًا','users'),
  ('users.warn','إرسال تحذير للمستخدم','users'),
  ('users.room_ban','منع المستخدم من الغرف','users'),
  ('users.message_ban','منع المستخدم من الرسائل','users'),
  ('users.post_ban','منع المستخدم من المنشورات','users'),
  ('users.call_ban','منع المستخدم من المكالمات','users'),
  ('notifications.events_send','إرسال إشعارات الحفلات والفعاليات','notifications'),
  ('notifications.marketing_send','إرسال الإعلانات الجماعية','notifications'),
  ('notifications.system_send','إرسال إشعارات النظام','notifications'),
  ('banners.manage','إدارة بنرات الرئيسية','content')
on conflict(permission) do update set label_ar=excluded.label_ar,category=excluded.category;

insert into public.yamo_admin_role_permissions(role,permission)
select 'super_admin',permission from public.yamo_admin_permissions on conflict do nothing;
insert into public.yamo_admin_role_permissions(role,permission) values
  ('admin','dashboard.view'),('finance','dashboard.view'),('moderator','dashboard.view'),
  ('agency_manager','dashboard.view'),('support','dashboard.view'),('auditor','dashboard.view'),('viewer','dashboard.view'),
  ('admin','users.suspend'),('admin','users.ban'),('admin','users.warn'),('admin','users.room_ban'),
  ('admin','users.message_ban'),('admin','users.post_ban'),('admin','users.call_ban'),
  ('moderator','users.suspend'),('moderator','users.warn'),('moderator','users.room_ban'),
  ('moderator','users.message_ban'),('moderator','users.post_ban'),('moderator','users.call_ban'),
  ('admin','notifications.events_send'),('admin','notifications.marketing_send'),('admin','notifications.system_send'),
  ('admin','banners.manage')
on conflict do nothing;

create table if not exists public.yamo_admin_permission_overrides(
  user_id uuid not null references public.yamo_admin_users(user_id) on delete cascade,
  permission text not null references public.yamo_admin_permissions(permission) on delete cascade,
  effect text not null check(effect in('grant','deny')),
  assigned_by uuid references auth.users(id), assigned_at timestamptz not null default now(),
  primary key(user_id,permission)
);
alter table public.yamo_admin_permission_overrides enable row level security;
revoke all on public.yamo_admin_permission_overrides from public,anon,authenticated;
grant select on public.yamo_admin_permission_overrides to authenticated;
drop policy if exists admin_permission_overrides_read on public.yamo_admin_permission_overrides;
create policy admin_permission_overrides_read on public.yamo_admin_permission_overrides for select to authenticated
  using(user_id=auth.uid() or public.yamo_admin_has_permission('admins.manage'));

create or replace function public.yamo_admin_has_permission(p_permission text)
returns boolean language sql stable security definer set search_path=public,auth,pg_temp as $$
  select exists(select 1 from public.yamo_admin_users u where u.user_id=auth.uid() and u.is_active)
    and not exists(select 1 from public.yamo_admin_permission_overrides o
      where o.user_id=auth.uid() and o.permission=p_permission and o.effect='deny')
    and (exists(select 1 from public.yamo_admin_permission_overrides o
      where o.user_id=auth.uid() and o.permission=p_permission and o.effect='grant')
      or exists(select 1 from public.yamo_admin_role_assignments ra
        join public.yamo_admin_role_permissions rp on rp.role=ra.role
        where ra.user_id=auth.uid() and rp.permission=p_permission));
$$;

create or replace function public.get_yamo_admin_me()
returns table(user_id uuid,email text,full_name text,is_active boolean,roles text[],permissions text[])
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select u.user_id,u.email,u.full_name,u.is_active,
    coalesce((select array_agg(distinct ra.role) from public.yamo_admin_role_assignments ra where ra.user_id=u.user_id),'{}'),
    coalesce((select array_agg(p.permission order by p.permission) from public.yamo_admin_permissions p
      where public.yamo_admin_has_permission(p.permission)),'{}')
  from public.yamo_admin_users u where u.user_id=auth.uid();
$$;

create or replace view public.admin_permission_catalog as
select permission,label_ar,category from public.yamo_admin_permissions
where public.yamo_admin_has_permission('admins.manage');
create or replace view public.admin_user_permissions as
select u.user_id,u.email,p.permission,p.label_ar,p.category,
  exists(select 1 from public.yamo_admin_role_assignments ra join public.yamo_admin_role_permissions rp on rp.role=ra.role
    where ra.user_id=u.user_id and rp.permission=p.permission) role_granted,
  o.effect override_effect,
  case when o.effect='deny' then false when o.effect='grant' then true else
    exists(select 1 from public.yamo_admin_role_assignments ra join public.yamo_admin_role_permissions rp on rp.role=ra.role
      where ra.user_id=u.user_id and rp.permission=p.permission) end effective
from public.yamo_admin_users u cross join public.yamo_admin_permissions p
left join public.yamo_admin_permission_overrides o on o.user_id=u.user_id and o.permission=p.permission
where public.yamo_admin_has_permission('admins.manage');
revoke all on public.admin_permission_catalog,public.admin_user_permissions from public,anon;
grant select on public.admin_permission_catalog,public.admin_user_permissions to authenticated;

create or replace function public.admin_set_yamo_permission_override(p_user_id uuid,p_permission text,p_effect text)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare me uuid:=public.yamo_admin_require('admins.manage'); old jsonb;
begin
  if not exists(select 1 from public.yamo_admin_role_assignments where user_id=me and role='super_admin') then raise exception 'super_admin_required'; end if;
  if not exists(select 1 from public.yamo_admin_users where user_id=p_user_id) then raise exception 'admin_not_found'; end if;
  if not exists(select 1 from public.yamo_admin_permissions where permission=p_permission) then raise exception 'permission_not_found'; end if;
  if p_effect not in('grant','deny','inherit') then raise exception 'invalid_effect'; end if;
  if p_user_id=me and p_permission='admins.manage' and p_effect='deny' then raise exception 'cannot_remove_own_admin_management'; end if;
  if p_effect='deny' and exists(select 1 from public.yamo_admin_role_assignments where user_id=p_user_id and role='super_admin') then raise exception 'cannot_deny_super_admin'; end if;
  select to_jsonb(o) into old from public.yamo_admin_permission_overrides o where user_id=p_user_id and permission=p_permission;
  if p_effect='inherit' then delete from public.yamo_admin_permission_overrides where user_id=p_user_id and permission=p_permission;
  else insert into public.yamo_admin_permission_overrides(user_id,permission,effect,assigned_by)
    values(p_user_id,p_permission,p_effect,me) on conflict(user_id,permission) do update set effect=excluded.effect,assigned_by=me,assigned_at=now(); end if;
  perform public.yamo_admin_log('rbac.permission_override','yamo_admin_permission_overrides',p_user_id::text,old,
    jsonb_build_object('permission',p_permission,'effect',p_effect));
  return true;
end $$;
revoke all on function public.admin_set_yamo_permission_override(uuid,text,text) from public,anon;
grant execute on function public.admin_set_yamo_permission_override(uuid,text,text) to authenticated;

create or replace view public.admin_moderation_actions as
select m.*,p.legacy_id,p.display_name from public.yamo_moderation_actions m
left join public.profiles p on p.id=m.user_id
where public.yamo_admin_has_permission('users.moderate') or public.yamo_admin_has_permission('users.suspend')
  or public.yamo_admin_has_permission('users.ban') or public.yamo_admin_has_permission('users.warn')
  or public.yamo_admin_has_permission('users.room_ban') or public.yamo_admin_has_permission('users.message_ban')
  or public.yamo_admin_has_permission('users.post_ban') or public.yamo_admin_has_permission('users.call_ban');
create or replace view public.admin_notifications as
select * from public.yamo_notifications where public.yamo_admin_has_permission('notifications.send')
  or public.yamo_admin_has_permission('notifications.events_send') or public.yamo_admin_has_permission('notifications.marketing_send')
  or public.yamo_admin_has_permission('notifications.system_send');

create or replace function public.admin_apply_moderation(p_legacy_id text,p_action text,p_reason text,p_days integer default null)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare u uuid; rid uuid; exp timestamptz; needed text;
begin
  needed:=case p_action when 'suspend' then 'users.suspend' when 'ban' then 'users.ban'
    when 'warning' then 'users.warn' when 'room_ban' then 'users.room_ban'
    when 'message_ban' then 'users.message_ban' when 'post_ban' then 'users.post_ban'
    when 'call_ban' then 'users.call_ban' else null end;
  if needed is null then raise exception 'invalid_action'; end if;
  perform public.yamo_admin_require(needed);
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
declare r public.yamo_moderation_actions%rowtype; needed text;
begin
  select * into r from public.yamo_moderation_actions where id=p_id and active for update;
  if r.id is null then raise exception 'active_action_not_found'; end if;
  needed:=case r.action_type when 'suspend' then 'users.suspend' when 'ban' then 'users.ban'
    when 'warning' then 'users.warn' when 'room_ban' then 'users.room_ban'
    when 'message_ban' then 'users.message_ban' when 'post_ban' then 'users.post_ban'
    when 'call_ban' then 'users.call_ban' else null end;
  perform public.yamo_admin_require(needed);
  update public.yamo_moderation_actions set active=false,revoked_at=now(),revoked_by=auth.uid(),revoke_reason=p_reason where id=p_id;
  if r.action_type in('suspend','ban') and not exists(select 1 from public.yamo_moderation_actions where user_id=r.user_id and active and id<>r.id and action_type in('suspend','ban') and (expires_at is null or expires_at>now())) then
    update public.profiles set account_status='active' where id=r.user_id;
  end if;
  perform public.yamo_admin_log('moderation.revoke','yamo_moderation_actions',p_id::text,to_jsonb(r),null,p_reason);
  return true;
end $$;

create or replace function public.admin_broadcast_yamo_notification_v2(p_title text,p_body text,p_deep_link text,p_segment text,p_category text)
returns bigint language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare needed text; v_count bigint;
begin
  needed:=case p_category when 'event' then 'notifications.events_send' when 'marketing' then 'notifications.marketing_send' when 'system' then 'notifications.system_send' else null end;
  if needed is null then raise exception 'invalid_category'; end if;
  perform public.yamo_admin_require(needed);
  if length(trim(coalesce(p_title,'')))=0 then raise exception 'title_required'; end if;
  insert into public.yamo_notifications(user_id,kind,title_ar,body_ar,deep_link)
  select p.id,'system',p_title,coalesce(p_body,''),p_deep_link from public.profiles p where case p_segment
    when 'all' then true when 'vip' then exists(select 1 from public.yamo_vip_subscriptions v where v.user_id=p.id and v.expires_at>now())
    when 'hosts' then exists(select 1 from public.yamo_agency_hosts h where h.user_id=p.id and h.removed_at is null) else false end;
  get diagnostics v_count=row_count;
  perform public.yamo_admin_log('notification.'||p_category,'yamo_notifications',p_segment,null,jsonb_build_object('title',p_title,'recipients',v_count));
  return v_count;
end $$;
revoke all on function public.admin_broadcast_yamo_notification_v2(text,text,text,text,text) from public,anon;
grant execute on function public.admin_broadcast_yamo_notification_v2(text,text,text,text,text) to authenticated;

create or replace function public.admin_set_yamo_banner(p_key text,p_value jsonb)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare old jsonb;
begin
  perform public.yamo_admin_require('banners.manage');
  select config_value into old from public.app_config where config_key=p_key;
  insert into public.app_config(config_key,config_value) values(p_key,p_value)
  on conflict(config_key) do update set config_value=excluded.config_value;
  perform public.yamo_admin_log('banner.set','app_config',p_key,old,p_value);
  return true;
end $$;
revoke all on function public.admin_set_yamo_banner(text,jsonb) from public,anon;
grant execute on function public.admin_set_yamo_banner(text,jsonb) to authenticated;

create or replace function public.get_yamo_admin_dashboard_v2(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare bd_count bigint:=0; charging_count bigint:=0; currency text:='EGP'; result jsonb; trend jsonb;
  revenue_today numeric:=0; expense_today numeric:=0; revenue_period numeric:=0; expense_period numeric:=0;
begin
  perform public.yamo_admin_require('dashboard.view');
  select coalesce((select coalesce(config_value->>'currency',config_value->>'value',nullif(trim(both '"' from config_value::text),''))
    from public.app_config where config_key='dashboard_currency'),'EGP') into currency;
  if to_regclass('public.bd_managers') is not null then execute 'select count(*) from public.bd_managers where status<>''inactive''' into bd_count; end if;
  if to_regclass('public.charging_agencies') is not null then execute 'select count(*) from public.charging_agencies where deleted_at is null' into charging_count; end if;
  select coalesce(sum(paid_amount),0) into revenue_today from public.yamo_recharge_requests where status='completed' and currency_code=currency and updated_at::date=current_date;
  select coalesce(sum(payout_amount),0) into expense_today from public.yamo_withdraw_requests where status='completed' and currency_code=currency and updated_at::date=current_date;
  select coalesce(sum(paid_amount),0) into revenue_period from public.yamo_recharge_requests where status='completed' and currency_code=currency and updated_at>=current_date-least(greatest(coalesce(p_days,30),7),90);
  select coalesce(sum(payout_amount),0) into expense_period from public.yamo_withdraw_requests where status='completed' and currency_code=currency and updated_at>=current_date-least(greatest(coalesce(p_days,30),7),90);
  select jsonb_agg(jsonb_build_object('day',to_char(d.day,'MM-DD'),'revenue',d.revenue,'expenses',d.expenses,'profit',d.revenue-d.expenses,'new_users',d.new_users) order by d.day) into trend
  from (select day,
    (select coalesce(sum(r.paid_amount),0) from public.yamo_recharge_requests r where r.status='completed' and r.currency_code=currency and r.updated_at::date=day) revenue,
    (select coalesce(sum(w.payout_amount),0) from public.yamo_withdraw_requests w where w.status='completed' and w.currency_code=currency and w.updated_at::date=day) expenses,
    (select count(*) from public.yamo_user_levels l where l.updated_at::date=day) new_users
    from generate_series(current_date-(least(greatest(coalesce(p_days,30),7),90)-1),current_date,'1 day') as gs(day)) d;
  result:=jsonb_build_object(
    'users_total',(select count(*) from public.profiles),
    'males',(select count(*) from public.profiles where lower(gender::text) in('male','m','ذكر')),
    'females',(select count(*) from public.profiles where lower(gender::text) in('female','f','أنثى','انثى')),
    'agencies',(select count(*) from public.yamo_agencies where disabled_at is null),
    'bd_managers',bd_count,'charging_agencies',charging_count,
    'rooms_total',(select count(*) from public.yamo_owned_rooms),
    'rooms_live',(select count(distinct room_id) from public.yamo_room_runtime_presence where left_at is null),
    'admins_active',(select count(*) from public.yamo_admin_users where is_active),
    'reports_open',(select count(*) from public.yamo_post_reports),
    'support_open',(select count(*) from public.yamo_support_tickets where status in('open','in_progress')),
    'verification_pending',(select count(*) from public.yamo_verification_requests where status='pending'),
    'recharge_pending',(select count(*) from public.yamo_recharge_requests where status in('submitted','reviewing')),
    'withdraw_pending',(select count(*) from public.yamo_withdraw_requests where status in('submitted','reviewing')),
    'gift_coins_today',(select coalesce(sum(total_coins),0) from public.room_gift_batches where created_at::date=current_date),
    'currency',currency,'revenue_today',revenue_today,'expenses_today',expense_today,
    'profit_today',revenue_today-expense_today,'profit_period',revenue_period-expense_period,
    'trend',coalesce(trend,'[]'::jsonb));
  return result;
end $$;
revoke all on function public.get_yamo_admin_dashboard_v2(integer) from public,anon;
grant execute on function public.get_yamo_admin_dashboard_v2(integer) to authenticated;

commit;
notify pgrst,'reload schema';
