-- Yamo Admin V220 — dedicated instant-message studio and analytics
-- Run after V219. Safe to run more than once.
begin;

drop view if exists public.admin_instant_message_campaigns;
create view public.admin_instant_message_campaigns as
select c.*,
  case when c.deleted_at is not null then 'archived'
       when not c.enabled then 'stopped'
       when c.scheduled_at>now() then 'scheduled'
       when c.ends_at is not null and c.ends_at<=now() then 'expired'
       else 'active' end lifecycle_status,
  coalesce((select count(*) from public.yamo_notifications n where n.deep_link='yamo://campaign/'||c.id::text),0)::bigint recipient_count,
  coalesce((select count(*) from public.yamo_notifications n where n.deep_link='yamo://campaign/'||c.id::text),0)::bigint delivered_count,
  coalesce((select count(*) from public.yamo_notifications n where n.deep_link='yamo://campaign/'||c.id::text and n.read_at is not null),0)::bigint read_count,
  coalesce((select count(*) from public.yamo_notifications n join public.profiles p on p.id=n.user_id where n.deep_link='yamo://campaign/'||c.id::text and lower(coalesce(p.gender,'')) in('male','ذكر')),0)::bigint male_count,
  coalesce((select count(*) from public.yamo_notifications n join public.profiles p on p.id=n.user_id where n.deep_link='yamo://campaign/'||c.id::text and lower(coalesce(p.gender,'')) in('female','أنثى','انثى')),0)::bigint female_count,
  case when c.sent_count>0 then round(100.0*coalesce((select count(*) from public.yamo_notifications n where n.deep_link='yamo://campaign/'||c.id::text and n.read_at is not null),0)/c.sent_count,1) else 0 end read_rate
from public.yamo_campaigns c
where c.kind='instant_message' and (public.yamo_admin_has_permission('banners.read') or public.yamo_admin_has_permission('banners.manage'));
grant select on public.admin_instant_message_campaigns to authenticated;

commit;
select pg_notify('pgrst','reload schema');
