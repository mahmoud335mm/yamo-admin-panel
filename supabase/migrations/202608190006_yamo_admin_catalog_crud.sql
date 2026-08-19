-- Yamo Chat V123: admin catalog CRUD.
--
-- Completes the panel sections that had a read view but no write path:
-- Finance Packages, Payment Methods, Withdrawal Settings, Coin/Pearl
-- Prices, Store (frames/entry effects/bubbles), Tasks & Daily Login,
-- VIP tiers, Analytics and Reports.
--
-- Every column referenced here was verified against the live definitions in
-- V90 (packages/methods) and V109 (store assets) before writing.
--
-- Pattern for all of them: yamo_admin_require(<perm>) -> mutate -> audit.
-- None of these touch a user balance.

begin;

-- ---------------------------------------------------------------------------
-- FINANCE: recharge packages (also drives "Coin Prices")
-- ---------------------------------------------------------------------------
drop function if exists public.admin_upsert_yamo_recharge_package(uuid, jsonb);
create function public.admin_upsert_yamo_recharge_package(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_id uuid := coalesce(p_id, gen_random_uuid()); v_before jsonb;
begin
  perform public.yamo_admin_require('economy.adjust');
  select to_jsonb(t) into v_before from public.yamo_recharge_packages t where t.id = v_id;

  insert into public.yamo_recharge_packages(
    id, country_code, package_key, title, coins, bonus_coins, price,
    currency_code, enabled, sort_order, updated_at)
  values (v_id,
    coalesce(p_payload->>'country_code','ALL'),
    coalesce(p_payload->>'package_key', v_id::text),
    coalesce(p_payload->>'title',''),
    coalesce((p_payload->>'coins')::bigint, 1),
    coalesce((p_payload->>'bonus_coins')::bigint, 0),
    coalesce((p_payload->>'price')::numeric, 1),
    coalesce(p_payload->>'currency_code','USD'),
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort_order')::integer, 0), now())
  on conflict (id) do update set
    country_code = coalesce(excluded.country_code, public.yamo_recharge_packages.country_code),
    title = coalesce(excluded.title, public.yamo_recharge_packages.title),
    coins = coalesce(excluded.coins, public.yamo_recharge_packages.coins),
    bonus_coins = coalesce(excluded.bonus_coins, public.yamo_recharge_packages.bonus_coins),
    price = coalesce(excluded.price, public.yamo_recharge_packages.price),
    currency_code = coalesce(excluded.currency_code, public.yamo_recharge_packages.currency_code),
    enabled = coalesce(excluded.enabled, public.yamo_recharge_packages.enabled),
    sort_order = coalesce(excluded.sort_order, public.yamo_recharge_packages.sort_order),
    updated_at = now();

  perform public.yamo_admin_log(
    case when v_before is null then 'recharge_package.create' else 'recharge_package.update' end,
    'yamo_recharge_packages', v_id::text, v_before, p_payload);
  return v_id;
end $$;
revoke all on function public.admin_upsert_yamo_recharge_package(uuid, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_recharge_package(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- FINANCE: payment methods
-- ---------------------------------------------------------------------------
drop function if exists public.admin_upsert_yamo_payment_method(uuid, jsonb);
create function public.admin_upsert_yamo_payment_method(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_id uuid := coalesce(p_id, gen_random_uuid()); v_before jsonb; v_flow text;
begin
  perform public.yamo_admin_require('economy.adjust');
  v_flow := coalesce(p_payload->>'flow','recharge');
  if v_flow not in ('recharge','withdrawal','both') then raise exception 'invalid_flow'; end if;
  select to_jsonb(t) into v_before from public.yamo_payment_methods t where t.id = v_id;

  insert into public.yamo_payment_methods(
    id, flow, country_code, method_key, display_name, instructions,
    receiver_label, receiver_value, enabled, sort_order, updated_at)
  values (v_id, v_flow,
    coalesce(p_payload->>'country_code','ALL'),
    coalesce(p_payload->>'method_key', v_id::text),
    coalesce(p_payload->>'display_name',''),
    coalesce(p_payload->>'instructions',''),
    p_payload->>'receiver_label', p_payload->>'receiver_value',
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort_order')::integer, 0), now())
  on conflict (id) do update set
    flow = coalesce(excluded.flow, public.yamo_payment_methods.flow),
    country_code = coalesce(excluded.country_code, public.yamo_payment_methods.country_code),
    display_name = coalesce(excluded.display_name, public.yamo_payment_methods.display_name),
    instructions = coalesce(excluded.instructions, public.yamo_payment_methods.instructions),
    receiver_label = coalesce(excluded.receiver_label, public.yamo_payment_methods.receiver_label),
    receiver_value = coalesce(excluded.receiver_value, public.yamo_payment_methods.receiver_value),
    enabled = coalesce(excluded.enabled, public.yamo_payment_methods.enabled),
    sort_order = coalesce(excluded.sort_order, public.yamo_payment_methods.sort_order),
    updated_at = now();

  perform public.yamo_admin_log(
    case when v_before is null then 'payment_method.create' else 'payment_method.update' end,
    'yamo_payment_methods', v_id::text, v_before, p_payload);
  return v_id;
end $$;
revoke all on function public.admin_upsert_yamo_payment_method(uuid, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_payment_method(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- FINANCE: withdrawal settings / packages (also "Pearl Prices")
-- ---------------------------------------------------------------------------
drop function if exists public.admin_upsert_yamo_withdraw_package(uuid, jsonb);
create function public.admin_upsert_yamo_withdraw_package(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_id uuid := coalesce(p_id, gen_random_uuid()); v_before jsonb;
begin
  perform public.yamo_admin_require('economy.adjust');
  select to_jsonb(t) into v_before from public.yamo_withdraw_packages t where t.id = v_id;

  insert into public.yamo_withdraw_packages(
    id, country_code, package_key, title, pearls, fee_pearls, payout_amount,
    currency_code, enabled, sort_order, updated_at)
  values (v_id,
    coalesce(p_payload->>'country_code','ALL'),
    coalesce(p_payload->>'package_key', v_id::text),
    coalesce(p_payload->>'title',''),
    coalesce((p_payload->>'pearls')::bigint, 1),
    coalesce((p_payload->>'fee_pearls')::bigint, 0),
    coalesce((p_payload->>'payout_amount')::numeric, 1),
    coalesce(p_payload->>'currency_code','USD'),
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort_order')::integer, 0), now())
  on conflict (id) do update set
    country_code = coalesce(excluded.country_code, public.yamo_withdraw_packages.country_code),
    title = coalesce(excluded.title, public.yamo_withdraw_packages.title),
    pearls = coalesce(excluded.pearls, public.yamo_withdraw_packages.pearls),
    fee_pearls = coalesce(excluded.fee_pearls, public.yamo_withdraw_packages.fee_pearls),
    payout_amount = coalesce(excluded.payout_amount, public.yamo_withdraw_packages.payout_amount),
    currency_code = coalesce(excluded.currency_code, public.yamo_withdraw_packages.currency_code),
    enabled = coalesce(excluded.enabled, public.yamo_withdraw_packages.enabled),
    sort_order = coalesce(excluded.sort_order, public.yamo_withdraw_packages.sort_order),
    updated_at = now();

  perform public.yamo_admin_log(
    case when v_before is null then 'withdraw_package.create' else 'withdraw_package.update' end,
    'yamo_withdraw_packages', v_id::text, v_before, p_payload);
  return v_id;
end $$;
revoke all on function public.admin_upsert_yamo_withdraw_package(uuid, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_withdraw_package(uuid, jsonb) to authenticated;

-- Pearl -> coin exchange offers (the in-app exchange rate).
drop function if exists public.admin_upsert_yamo_exchange_offer(text, jsonb);
create function public.admin_upsert_yamo_exchange_offer(p_offer_id text, p_payload jsonb)
returns text
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('economy.adjust');
  select to_jsonb(t) into v_before from public.yamo_pearl_exchange_offers t
  where t.id = p_offer_id;

  insert into public.yamo_pearl_exchange_offers(
    id, pearl_amount, coin_amount, enabled, sort_order, updated_at)
  values (p_offer_id,
    coalesce((p_payload->>'pearl_amount')::bigint, 1),
    coalesce((p_payload->>'coin_amount')::bigint, 1),
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort_order')::integer, 0), now())
  on conflict (id) do update set
    pearl_amount = coalesce(excluded.pearl_amount, public.yamo_pearl_exchange_offers.pearl_amount),
    coin_amount = coalesce(excluded.coin_amount, public.yamo_pearl_exchange_offers.coin_amount),
    enabled = coalesce(excluded.enabled, public.yamo_pearl_exchange_offers.enabled),
    sort_order = coalesce(excluded.sort_order, public.yamo_pearl_exchange_offers.sort_order),
    updated_at = now();

  perform public.yamo_admin_log('exchange_offer.upsert','yamo_pearl_exchange_offers',
    p_offer_id, v_before, p_payload);
  return p_offer_id;
end $$;
revoke all on function public.admin_upsert_yamo_exchange_offer(text, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_exchange_offer(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- STORE: frames / entry effects / chat bubbles
-- ---------------------------------------------------------------------------
drop function if exists public.admin_upsert_yamo_store_asset(text, text, jsonb);
create function public.admin_upsert_yamo_store_asset(
  p_asset_kind text, p_asset_key text, p_payload jsonb
)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('catalog.manage');
  if p_asset_kind not in ('frame','entry_effect','chat_bubble') then
    raise exception 'invalid_asset_kind';
  end if;
  select to_jsonb(t) into v_before from public.yamo_store_assets t
  where t.asset_kind = p_asset_kind and t.asset_key = p_asset_key;

  insert into public.yamo_store_assets(
    asset_kind, asset_key, name_ar, price_coins, duration_days,
    preview_url, enabled, sort_order)
  values (p_asset_kind, p_asset_key,
    coalesce(p_payload->>'name_ar', p_asset_key),
    coalesce((p_payload->>'price_coins')::bigint, 1),
    nullif(p_payload->>'duration_days','')::integer,
    p_payload->>'preview_url',
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort_order')::integer, 0))
  on conflict (asset_kind, asset_key) do update set
    name_ar = coalesce(excluded.name_ar, public.yamo_store_assets.name_ar),
    price_coins = coalesce(excluded.price_coins, public.yamo_store_assets.price_coins),
    duration_days = coalesce(excluded.duration_days, public.yamo_store_assets.duration_days),
    preview_url = coalesce(excluded.preview_url, public.yamo_store_assets.preview_url),
    enabled = coalesce(excluded.enabled, public.yamo_store_assets.enabled),
    sort_order = coalesce(excluded.sort_order, public.yamo_store_assets.sort_order);

  perform public.yamo_admin_log('store_asset.upsert','yamo_store_assets',
    p_asset_kind || ':' || p_asset_key, v_before, p_payload);
  return true;
end $$;
revoke all on function public.admin_upsert_yamo_store_asset(text, text, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_store_asset(text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- TASKS / DAILY LOGIN
-- ---------------------------------------------------------------------------
drop function if exists public.admin_upsert_yamo_task(text, jsonb);
create function public.admin_upsert_yamo_task(p_task_id text, p_payload jsonb)
returns text
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb; v_metric text;
begin
  perform public.yamo_admin_require('tasks.manage');
  v_metric := coalesce(p_payload->>'metric','MESSAGE_REPLIES');
  if v_metric not in ('PROFILE_COMPLETION_PERCENT','MESSAGE_REPLIES','ROOM_GIFT_COINS',
    'PAID_VOICE_MINUTES','PAID_VIDEO_MINUTES','AGENCY_TARGET_PEARLS','VERIFIED_INVITATIONS') then
    raise exception 'invalid_metric';
  end if;
  select to_jsonb(t) into v_before from public.yamo_tasks t where t.id = p_task_id;

  insert into public.yamo_tasks(id, section, title_ar, subtitle_ar, icon_key,
    metric, unit_label, reset_every_seconds, enabled, sort_order)
  values (p_task_id,
    coalesce(p_payload->>'section','normal'),
    coalesce(p_payload->>'title_ar',''),
    coalesce(p_payload->>'subtitle_ar',''),
    coalesce(p_payload->>'icon_key','task'),
    v_metric,
    coalesce(p_payload->>'unit_label',''),
    nullif(p_payload->>'reset_every_seconds','')::bigint,
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort_order')::integer, 0))
  on conflict (id) do update set
    section = coalesce(excluded.section, public.yamo_tasks.section),
    title_ar = coalesce(excluded.title_ar, public.yamo_tasks.title_ar),
    subtitle_ar = coalesce(excluded.subtitle_ar, public.yamo_tasks.subtitle_ar),
    icon_key = coalesce(excluded.icon_key, public.yamo_tasks.icon_key),
    metric = coalesce(excluded.metric, public.yamo_tasks.metric),
    unit_label = coalesce(excluded.unit_label, public.yamo_tasks.unit_label),
    reset_every_seconds = excluded.reset_every_seconds,
    enabled = coalesce(excluded.enabled, public.yamo_tasks.enabled),
    sort_order = coalesce(excluded.sort_order, public.yamo_tasks.sort_order);

  perform public.yamo_admin_log('task.upsert','yamo_tasks',p_task_id, v_before, p_payload);
  return p_task_id;
end $$;
revoke all on function public.admin_upsert_yamo_task(text, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_task(text, jsonb) to authenticated;

drop function if exists public.admin_upsert_yamo_task_milestone(text, jsonb);
create function public.admin_upsert_yamo_task_milestone(p_milestone_id text, p_payload jsonb)
returns text
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('tasks.manage');
  if (p_payload->>'task_id') is null then raise exception 'task_id_required'; end if;
  select to_jsonb(m) into v_before from public.yamo_task_milestones m where m.id = p_milestone_id;

  insert into public.yamo_task_milestones(id, task_id, target_value, reward_asset,
    reward_value, reward_asset_key, reward_title_ar, reward_icon_key, sort_order)
  values (p_milestone_id,
    p_payload->>'task_id',
    coalesce((p_payload->>'target_value')::bigint, 1),
    coalesce(p_payload->>'reward_asset','COINS'),
    coalesce((p_payload->>'reward_value')::bigint, 0),
    p_payload->>'reward_asset_key',
    coalesce(p_payload->>'reward_title_ar',''),
    coalesce(p_payload->>'reward_icon_key','reward'),
    coalesce((p_payload->>'sort_order')::integer, 0))
  on conflict (id) do update set
    target_value = coalesce(excluded.target_value, public.yamo_task_milestones.target_value),
    reward_asset = coalesce(excluded.reward_asset, public.yamo_task_milestones.reward_asset),
    reward_value = coalesce(excluded.reward_value, public.yamo_task_milestones.reward_value),
    reward_asset_key = excluded.reward_asset_key,
    reward_title_ar = coalesce(excluded.reward_title_ar, public.yamo_task_milestones.reward_title_ar),
    reward_icon_key = coalesce(excluded.reward_icon_key, public.yamo_task_milestones.reward_icon_key),
    sort_order = coalesce(excluded.sort_order, public.yamo_task_milestones.sort_order);

  perform public.yamo_admin_log('task_milestone.upsert','yamo_task_milestones',
    p_milestone_id, v_before, p_payload);
  return p_milestone_id;
end $$;
revoke all on function public.admin_upsert_yamo_task_milestone(text, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_task_milestone(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- VIP tiers
-- ---------------------------------------------------------------------------
drop function if exists public.admin_upsert_yamo_vip_tier(integer, jsonb);
create function public.admin_upsert_yamo_vip_tier(p_level integer, p_payload jsonb)
returns integer
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('catalog.manage');
  if p_level not between 1 and 4 then raise exception 'invalid_vip_level'; end if;
  select to_jsonb(t) into v_before from public.yamo_vip_tiers t where t.level = p_level;

  insert into public.yamo_vip_tiers(level, name_ar, price_coins, duration_days,
    frame_key, entry_effect_key, chat_bubble_key, enabled, sort_order)
  values (p_level,
    coalesce(p_payload->>'name_ar','VIP ' || p_level),
    coalesce((p_payload->>'price_coins')::bigint, 1),
    coalesce((p_payload->>'duration_days')::integer, 30),
    p_payload->>'frame_key', p_payload->>'entry_effect_key', p_payload->>'chat_bubble_key',
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort_order')::integer, p_level))
  on conflict (level) do update set
    name_ar = coalesce(excluded.name_ar, public.yamo_vip_tiers.name_ar),
    price_coins = coalesce(excluded.price_coins, public.yamo_vip_tiers.price_coins),
    duration_days = coalesce(excluded.duration_days, public.yamo_vip_tiers.duration_days),
    frame_key = coalesce(excluded.frame_key, public.yamo_vip_tiers.frame_key),
    entry_effect_key = coalesce(excluded.entry_effect_key, public.yamo_vip_tiers.entry_effect_key),
    chat_bubble_key = coalesce(excluded.chat_bubble_key, public.yamo_vip_tiers.chat_bubble_key),
    enabled = coalesce(excluded.enabled, public.yamo_vip_tiers.enabled),
    sort_order = coalesce(excluded.sort_order, public.yamo_vip_tiers.sort_order);

  perform public.yamo_admin_log('vip_tier.upsert','yamo_vip_tiers',
    p_level::text, v_before, p_payload);
  return p_level;
end $$;
revoke all on function public.admin_upsert_yamo_vip_tier(integer, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_vip_tier(integer, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- ANALYTICS + REPORTS
-- ---------------------------------------------------------------------------
drop function if exists public.get_yamo_admin_analytics(integer);
create function public.get_yamo_admin_analytics(p_days integer default 14)
returns table(day date, new_users bigint, messages bigint, gift_coins bigint,
  recharge_coins bigint, active_rooms bigint)
language sql stable security definer set search_path = public, auth, pg_temp as $$
  with days as (
    select generate_series(
      (current_date - (least(greatest(coalesce(p_days,14),1),90))::integer),
      current_date, '1 day')::date as day
  )
  select d.day,
    (select count(*) from public.yamo_user_levels u
      where u.updated_at::date = d.day),
    (select count(*) from public.yamo_messages m where m.sent_at::date = d.day),
    (select coalesce(sum(b.total_coins),0) from public.room_gift_batches b
      where b.created_at::date = d.day),
    (select coalesce(sum(r.coins),0) from public.yamo_recharge_requests r
      where r.status = 'completed' and r.updated_at::date = d.day),
    (select count(distinct p.room_id) from public.yamo_room_runtime_presence p
      where p.joined_at::date = d.day)
  from days d
  where public.yamo_admin_has_permission('economy.read')
     or public.yamo_admin_has_permission('users.read')
  order by d.day;
$$;
revoke all on function public.get_yamo_admin_analytics(integer) from public, anon;
grant execute on function public.get_yamo_admin_analytics(integer) to authenticated;

drop function if exists public.admin_resolve_yamo_post_report(uuid, text);
create function public.admin_resolve_yamo_post_report(p_report_id uuid, p_action text)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_post uuid;
begin
  perform public.yamo_admin_require('content.moderate');
  if p_action not in ('dismiss','remove_post') then raise exception 'invalid_action'; end if;
  select post_id into v_post from public.yamo_post_reports where id = p_report_id;
  if v_post is null then raise exception 'report_not_found'; end if;

  if p_action = 'remove_post' then
    update public.yamo_posts set deleted_at = now()
    where id = v_post and deleted_at is null;
  end if;
  delete from public.yamo_post_reports where id = p_report_id;

  perform public.yamo_admin_log('report.resolve','yamo_post_reports',
    p_report_id::text, null, jsonb_build_object('action',p_action,'post_id',v_post));
  return true;
end $$;
revoke all on function public.admin_resolve_yamo_post_report(uuid, text) from public, anon;
grant execute on function public.admin_resolve_yamo_post_report(uuid, text) to authenticated;

commit;
notify pgrst, 'reload schema';
