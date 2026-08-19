-- Yamo Chat V121: admin panel compatibility layer.
--
-- The panel's 57 routes query table names from its own legacy schema
-- (audit_logs, profiles, recharge_requests, wallets, wallet_ledger,
-- withdrawal_requests, agencies, hosts, admin_users, ...). Rather than
-- rewrite every page - and rather than create the legacy tables and end up
-- with two economies - this migration exposes those names as READ-ONLY
-- VIEWS over the real Yamo tables.
--
-- Why views:
--   * The panel's read queries work unchanged against real Yamo data.
--   * A view cannot be written to by the client here (no INSERT/UPDATE
--     grants), so no page can mutate money by accident. Every write must
--     go through an admin RPC (V122).
--   * Nothing in the app schema is renamed or altered.
--
-- IMPORTANT: `wallets` is NOT viewable under that name - the real Yamo
-- table already occupies it, and the panel's expectations for that name
-- (id/account/balance/reserved) do not match. The panel's wallet pages are
-- pointed at `admin_wallets` instead (see below), which exposes the Yamo
-- shape honestly rather than faking the legacy one.

begin;

-- Guard: every view is permission-gated at the row level, so a normal
-- authenticated user selecting from them gets nothing.

-- ---------------------------------------------------------------------------
-- Users / profiles
-- ---------------------------------------------------------------------------
create or replace view public.admin_profiles
with (security_invoker = true) as
select
  p.id,
  p.legacy_id,
  coalesce(p.display_name, p.legacy_id) as display_name,
  p.avatar_url,
  -- NOTE: profiles has no bio/country_code columns (verified against the
  -- actual schema); account_status/language_code are what exist.
  p.gender,
  p.account_status,
  p.language_code,
  -- profiles.created_at is not guaranteed by our migrations (the table is
  -- provisioned outside them), so it is deliberately not selected here.
  w.coins,
  w.pearls,
  l.level,
  l.current_points,
  case when v.expires_at > now() then v.level else 0 end as vip_level,
  v.expires_at as vip_expires_at
from public.profiles p
left join public.wallets w on w.user_id = p.id
left join public.yamo_user_levels l on l.user_id = p.id
left join public.yamo_vip_subscriptions v on v.user_id = p.id
where public.yamo_admin_has_permission('users.read');

-- ---------------------------------------------------------------------------
-- Finance reads
-- ---------------------------------------------------------------------------
create or replace view public.admin_wallets
with (security_invoker = true) as
select w.user_id, p.legacy_id, coalesce(p.display_name, p.legacy_id) as display_name,
  w.coins, w.pearls, w.updated_at
from public.wallets w
join public.profiles p on p.id = w.user_id
where public.yamo_admin_has_permission('economy.read');

-- The panel calls this "wallet_ledger"; in Yamo it is yamo_wallet_events.
create or replace view public.admin_wallet_ledger
with (security_invoker = true) as
select e.id, e.user_id, p.legacy_id, e.asset, e.amount, e.reason,
  e.reference_id, e.created_at
from public.yamo_wallet_events e
join public.profiles p on p.id = e.user_id
where public.yamo_admin_has_permission('economy.read');

create or replace view public.admin_recharge_requests
with (security_invoker = true) as
select r.id, r.reference, r.user_id, p.legacy_id,
  coalesce(p.display_name, p.legacy_id) as display_name,
  r.coins, r.paid_amount, r.currency_code, r.status, r.sender_account,
  r.proof_path, r.expires_at, r.created_at, r.updated_at,
  m.display_name as method_name
from public.yamo_recharge_requests r
join public.profiles p on p.id = r.user_id
left join public.yamo_payment_methods m on m.id = r.payment_method_id
where public.yamo_admin_has_permission('recharge.review')
   or public.yamo_admin_has_permission('economy.read');

create or replace view public.admin_withdrawal_requests
with (security_invoker = true) as
select w.id, w.reference, w.user_id, p.legacy_id,
  coalesce(p.display_name, p.legacy_id) as display_name,
  w.pearls, w.fee_pearls, w.payout_amount, w.currency_code, w.status,
  w.payout_details, w.created_at, w.updated_at
from public.yamo_withdraw_requests w
join public.profiles p on p.id = w.user_id
where public.yamo_admin_has_permission('withdraw.review')
   or public.yamo_admin_has_permission('economy.read');

create or replace view public.admin_pearl_coin_exchanges
with (security_invoker = true) as
select x.id, x.user_id, p.legacy_id, x.offer_id, x.pearl_amount,
  x.coin_amount, x.created_at
from public.yamo_pearl_exchanges x
join public.profiles p on p.id = x.user_id
where public.yamo_admin_has_permission('economy.read');

-- ---------------------------------------------------------------------------
-- Agency / hosts
-- ---------------------------------------------------------------------------
create or replace view public.admin_agencies
with (security_invoker = true) as
select a.id, a.name, a.owner_id, p.legacy_id as owner_legacy_id,
  a.country_code, a.invite_code, a.commission_percent, a.created_at,
  a.disabled_at,
  (select count(*) from public.yamo_agency_hosts h
    where h.agency_id = a.id and h.removed_at is null) as host_count
from public.yamo_agencies a
join public.profiles p on p.id = a.owner_id
where public.yamo_admin_has_permission('agency.manage');

create or replace view public.admin_hosts
with (security_invoker = true) as
select h.agency_id, h.user_id, p.legacy_id,
  coalesce(p.display_name, p.legacy_id) as display_name,
  h.joined_at, h.removed_at,
  coalesce((select sum(e.pearls) from public.yamo_agency_host_earnings e
    where e.user_id = h.user_id and e.agency_id = h.agency_id), 0) as total_pearls
from public.yamo_agency_hosts h
join public.profiles p on p.id = h.user_id
where public.yamo_admin_has_permission('agency.manage');

create or replace view public.admin_agency_settlements
with (security_invoker = true) as
select s.id, s.agency_id, a.name as agency_name, s.period_start, s.period_end,
  s.host_pearls, s.commission_pearls, s.commission_percent, s.status,
  s.created_at, s.settled_at
from public.yamo_agency_settlements s
join public.yamo_agencies a on a.id = s.agency_id
where public.yamo_admin_has_permission('agency.manage')
   or public.yamo_admin_has_permission('economy.read');

-- ---------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------
create or replace view public.admin_posts
with (security_invoker = true) as
select po.id, po.author_id, p.legacy_id, coalesce(p.display_name, p.legacy_id) as display_name,
  po.body, po.kind, po.media_url, po.like_count, po.comment_count,
  po.share_count, po.deleted_at, po.created_at,
  (select count(*) from public.yamo_post_reports r where r.post_id = po.id) as report_count
from public.yamo_posts po
join public.profiles p on p.id = po.author_id
where public.yamo_admin_has_permission('content.moderate');

create or replace view public.admin_post_reports
with (security_invoker = true) as
select r.id, r.post_id, r.reporter_id, p.legacy_id as reporter_legacy_id,
  r.reason, r.created_at, po.body as post_body, po.author_id
from public.yamo_post_reports r
join public.profiles p on p.id = r.reporter_id
join public.yamo_posts po on po.id = r.post_id
where public.yamo_admin_has_permission('content.moderate');

create or replace view public.admin_rooms
with (security_invoker = true) as
select r.room_id, r.title, r.category, r.owner_user_id,
  p.legacy_id as owner_legacy_id, r.announcement, r.cover_url, r.created_at,
  (select count(*) from public.yamo_room_runtime_presence pr
    where pr.room_id = r.room_id and pr.left_at is null) as occupancy,
  exists(select 1 from public.yamo_featured_rooms f
    where f.room_id = r.room_id and f.enabled) as featured
from public.yamo_owned_rooms r
join public.profiles p on p.id = r.owner_user_id
where public.yamo_admin_has_permission('rooms.manage');

-- ---------------------------------------------------------------------------
-- Admin infrastructure (panel expects these names)
-- ---------------------------------------------------------------------------
create or replace view public.admin_users_view
with (security_invoker = true) as
select u.user_id as id, u.email, u.full_name, u.is_active, u.last_login_at,
  u.created_at,
  coalesce(array_agg(ra.role) filter (where ra.role is not null), '{}') as roles
from public.yamo_admin_users u
left join public.yamo_admin_role_assignments ra on ra.user_id = u.user_id
where public.yamo_admin_has_permission('admins.manage')
group by u.user_id, u.email, u.full_name, u.is_active, u.last_login_at, u.created_at;

create or replace view public.admin_audit_logs
with (security_invoker = true) as
select l.id, l.actor_id, l.actor_email, l.action, l.entity_type, l.entity_id,
  l.before_state, l.after_state, l.note, l.created_at
from public.yamo_admin_audit_logs l
where public.yamo_admin_has_permission('audit.read');

-- Grants: SELECT only. No client write path to any of these.
grant select on
  public.admin_profiles, public.admin_wallets, public.admin_wallet_ledger,
  public.admin_recharge_requests, public.admin_withdrawal_requests,
  public.admin_pearl_coin_exchanges, public.admin_agencies, public.admin_hosts,
  public.admin_agency_settlements, public.admin_posts, public.admin_post_reports,
  public.admin_rooms, public.admin_users_view, public.admin_audit_logs
  to authenticated;

commit;
notify pgrst, 'reload schema';
