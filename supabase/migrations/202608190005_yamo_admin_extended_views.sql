-- Read-only administrative projections for the remaining Yamo product areas.
-- Every view is guarded by the same RBAC functions introduced in V120.

begin;

create or replace view public.admin_vip_tiers as
select * from public.yamo_vip_tiers
where public.yamo_admin_has_permission('catalog.manage');

create or replace view public.admin_distinctive_id_offers as
select * from public.yamo_distinctive_id_offers
where public.yamo_admin_has_permission('catalog.manage');

create or replace view public.admin_relationships as
select * from public.yamo_relationships
where public.yamo_admin_has_permission('users.read');

create or replace view public.admin_families as
select * from public.yamo_families
where public.yamo_admin_has_permission('users.read');

create or replace view public.admin_store_assets as
select * from public.yamo_store_assets
where public.yamo_admin_has_permission('catalog.manage');

create or replace view public.admin_gifts as
select * from public.gifts
where public.yamo_admin_has_permission('catalog.manage');

create or replace view public.admin_games as
select * from public.yamo_game_types
where public.yamo_admin_has_permission('games.manage');

create or replace view public.admin_events as
select * from public.yamo_events
where public.yamo_admin_has_permission('events.manage');

create or replace view public.admin_tasks as
select * from public.yamo_tasks
where public.yamo_admin_has_permission('tasks.manage');

create or replace view public.admin_notifications as
select * from public.yamo_notifications
where public.yamo_admin_has_permission('notifications.send');

create or replace view public.admin_calls as
select * from public.yamo_calls
where public.yamo_admin_has_permission('content.moderate');

create or replace view public.admin_recharge_packages as
select * from public.yamo_recharge_packages
where public.yamo_admin_has_permission('economy.read');

create or replace view public.admin_payment_methods as
select * from public.yamo_payment_methods
where public.yamo_admin_has_permission('economy.read');

create or replace view public.admin_withdraw_packages as
select * from public.yamo_withdraw_packages
where public.yamo_admin_has_permission('economy.read');

create or replace view public.admin_exchange_offers as
select * from public.yamo_pearl_exchange_offers
where public.yamo_admin_has_permission('economy.read');

revoke all on public.admin_vip_tiers, public.admin_distinctive_id_offers,
  public.admin_relationships, public.admin_families, public.admin_store_assets,
  public.admin_gifts, public.admin_games, public.admin_events, public.admin_tasks,
  public.admin_notifications, public.admin_calls, public.admin_recharge_packages,
  public.admin_payment_methods, public.admin_withdraw_packages,
  public.admin_exchange_offers from public, anon;

grant select on public.admin_vip_tiers, public.admin_distinctive_id_offers,
  public.admin_relationships, public.admin_families, public.admin_store_assets,
  public.admin_gifts, public.admin_games, public.admin_events, public.admin_tasks,
  public.admin_notifications, public.admin_calls, public.admin_recharge_packages,
  public.admin_payment_methods, public.admin_withdraw_packages,
  public.admin_exchange_offers to authenticated;

commit;
