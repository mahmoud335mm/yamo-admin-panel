-- Yamo Chat V122: admin write RPCs.
--
-- Every admin mutation in the panel goes through one of these. Each:
--   * calls yamo_admin_require(<permission>) - a normal user calling the
--     RPC directly gets permission_denied, so RBAC is enforced server-side
--     and not by hiding buttons in the UI,
--   * mutates atomically,
--   * writes a yamo_admin_audit_logs row for sensitive actions.
--
-- NO function here writes public.wallets with free-form SQL except
-- admin_adjust_yamo_wallet, which is deliberately constrained and fully
-- audited (see its comment).

begin;

-- ---------------------------------------------------------------------------
-- DASHBOARD
-- ---------------------------------------------------------------------------
drop function if exists public.get_yamo_admin_dashboard();
create function public.get_yamo_admin_dashboard()
returns jsonb
language plpgsql stable security definer set search_path = public, auth, pg_temp as $$
begin
  perform public.yamo_admin_require('users.read');
  return jsonb_build_object(
    'users_total', (select count(*) from public.profiles),
    'rooms_total', (select count(*) from public.yamo_owned_rooms),
    'rooms_live', (select count(distinct room_id) from public.yamo_room_runtime_presence
      where left_at is null),
    'posts_total', (select count(*) from public.yamo_posts where deleted_at is null),
    'messages_24h', (select count(*) from public.yamo_messages
      where sent_at > now() - interval '24 hours'),
    'coins_in_circulation', (select coalesce(sum(coins),0) from public.wallets),
    'pearls_in_circulation', (select coalesce(sum(pearls),0) from public.wallets),
    'recharge_pending', (select count(*) from public.yamo_recharge_requests
      where status in ('submitted','reviewing')),
    'withdraw_pending', (select count(*) from public.yamo_withdraw_requests
      where status in ('submitted','reviewing')),
    'gift_coins_24h', (select coalesce(sum(total_coins),0) from public.room_gift_batches
      where created_at > now() - interval '24 hours'),
    'vip_active', (select count(*) from public.yamo_vip_subscriptions where expires_at > now()),
    'agencies_total', (select count(*) from public.yamo_agencies where disabled_at is null),
    'families_total', (select count(*) from public.yamo_families where disbanded_at is null),
    'reports_open', (select count(*) from public.yamo_post_reports)
  );
end $$;
revoke all on function public.get_yamo_admin_dashboard() from public, anon;
grant execute on function public.get_yamo_admin_dashboard() to authenticated;

-- ---------------------------------------------------------------------------
-- USERS: moderation. Uses profiles.account_status (already exists).
-- ---------------------------------------------------------------------------
drop function if exists public.admin_set_yamo_account_status(text, text, text);
create function public.admin_set_yamo_account_status(
  p_legacy_id text, p_status text, p_note text default null
)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_target uuid; v_before text;
begin
  perform public.yamo_admin_require('users.moderate');
  if p_status not in ('active','suspended','banned') then raise exception 'invalid_status'; end if;
  select id, account_status into v_target, v_before from public.profiles
  where legacy_id = p_legacy_id;
  if v_target is null then raise exception 'user_not_found'; end if;

  update public.profiles set account_status = p_status where id = v_target;
  perform public.yamo_admin_log('user.status','profiles',p_legacy_id,
    to_jsonb(v_before), to_jsonb(p_status), p_note);
  return true;
end $$;
revoke all on function public.admin_set_yamo_account_status(text, text, text) from public, anon;
grant execute on function public.admin_set_yamo_account_status(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- WALLET ADJUSTMENT — the only admin path that changes a balance directly.
-- Constrained on purpose: bounded amount, mandatory reason, idempotency key,
-- writes a yamo_wallet_events row (so it appears in the user's own history)
-- AND an audit row. Cannot push a balance negative.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_adjust_yamo_wallet(text, text, bigint, text, uuid);
create function public.admin_adjust_yamo_wallet(
  p_legacy_id text, p_asset text, p_amount bigint, p_reason text, p_idempotency_key uuid
)
returns table(coins bigint, pearls bigint)
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_admin uuid; v_target uuid; v_w public.wallets%rowtype;
begin
  v_admin := public.yamo_admin_require('economy.adjust');
  if p_asset not in ('coins','pearls') then raise exception 'invalid_asset'; end if;
  if p_amount = 0 then raise exception 'invalid_amount'; end if;
  if abs(p_amount) > 100000000 then raise exception 'amount_exceeds_limit'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'reason_required'; end if;

  -- Idempotent: the same key can never apply twice.
  if exists (select 1 from public.yamo_wallet_events
    where reason = 'admin_adjustment' and reference_id = p_idempotency_key::text) then
    select * into v_w from public.wallets w where w.user_id =
      (select id from public.profiles where legacy_id = p_legacy_id);
    return query select v_w.coins, v_w.pearls;
    return;
  end if;

  select id into v_target from public.profiles where legacy_id = p_legacy_id;
  if v_target is null then raise exception 'user_not_found'; end if;

  if p_asset = 'coins' then
    update public.wallets set coins = coins + p_amount, updated_at = now()
    where user_id = v_target and coins + p_amount >= 0 returning * into v_w;
  else
    update public.wallets set pearls = pearls + p_amount, updated_at = now()
    where user_id = v_target and pearls + p_amount >= 0 returning * into v_w;
  end if;
  if v_w.user_id is null then raise exception 'insufficient_balance_or_user_missing'; end if;

  insert into public.yamo_wallet_events(user_id, asset, amount, reason, reference_id)
  values (v_target, p_asset, p_amount, 'admin_adjustment', p_idempotency_key::text);

  perform public.yamo_admin_log('wallet.adjust','wallets',p_legacy_id, null,
    jsonb_build_object('asset',p_asset,'amount',p_amount), p_reason);

  return query select v_w.coins, v_w.pearls;
end $$;
revoke all on function public.admin_adjust_yamo_wallet(text, text, bigint, text, uuid)
  from public, anon;
grant execute on function public.admin_adjust_yamo_wallet(text, text, bigint, text, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- GIFT CATALOG
-- ---------------------------------------------------------------------------
drop function if exists public.admin_upsert_yamo_gift(text, jsonb);
create function public.admin_upsert_yamo_gift(p_gift_id text, p_payload jsonb)
returns text
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('catalog.manage');
  select to_jsonb(g) into v_before from public.gifts g where g.id = p_gift_id;

  insert into public.gifts(id, name_ar, price_coins, sort_order, active,
    image_url, animation_url, category, duration_seconds)
  values (p_gift_id,
    coalesce(p_payload->>'name_ar',''),
    coalesce((p_payload->>'price_coins')::bigint, 1),
    coalesce((p_payload->>'sort_order')::integer, 0),
    coalesce((p_payload->>'active')::boolean, true),
    p_payload->>'image_url', p_payload->>'animation_url',
    coalesce(p_payload->>'category','الهدايا'),
    nullif(p_payload->>'duration_seconds','')::integer)
  on conflict (id) do update set
    name_ar = coalesce(excluded.name_ar, public.gifts.name_ar),
    price_coins = coalesce(excluded.price_coins, public.gifts.price_coins),
    sort_order = coalesce(excluded.sort_order, public.gifts.sort_order),
    active = coalesce(excluded.active, public.gifts.active),
    image_url = coalesce(excluded.image_url, public.gifts.image_url),
    animation_url = coalesce(excluded.animation_url, public.gifts.animation_url),
    category = coalesce(excluded.category, public.gifts.category),
    duration_seconds = coalesce(excluded.duration_seconds, public.gifts.duration_seconds);

  perform public.yamo_admin_log(
    case when v_before is null then 'gift.create' else 'gift.update' end,
    'gifts', p_gift_id, v_before, p_payload);
  return p_gift_id;
end $$;
revoke all on function public.admin_upsert_yamo_gift(text, jsonb) from public, anon;
grant execute on function public.admin_upsert_yamo_gift(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- ROOMS
-- ---------------------------------------------------------------------------
drop function if exists public.admin_set_yamo_room_featured(text, boolean, integer);
create function public.admin_set_yamo_room_featured(
  p_room_id text, p_featured boolean, p_sort_order integer default 0
)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
begin
  perform public.yamo_admin_require('rooms.manage');
  if not exists(select 1 from public.yamo_owned_rooms where room_id = p_room_id) then
    raise exception 'room_not_found';
  end if;
  if p_featured then
    insert into public.yamo_featured_rooms(room_id, sort_order, enabled)
    values (p_room_id, coalesce(p_sort_order,0), true)
    on conflict (room_id) do update set enabled = true,
      sort_order = coalesce(p_sort_order,0), updated_at = now();
  else
    update public.yamo_featured_rooms set enabled = false, updated_at = now()
    where room_id = p_room_id;
  end if;
  perform public.yamo_admin_log('room.featured','yamo_owned_rooms',p_room_id,
    null, to_jsonb(p_featured));
  return true;
end $$;
revoke all on function public.admin_set_yamo_room_featured(text, boolean, integer)
  from public, anon;
grant execute on function public.admin_set_yamo_room_featured(text, boolean, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- POSTS moderation (admin can remove any post; delete_yamo_post is author-only)
-- ---------------------------------------------------------------------------
drop function if exists public.admin_remove_yamo_post(uuid, text);
create function public.admin_remove_yamo_post(p_post_id uuid, p_reason text default null)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('content.moderate');
  select to_jsonb(p) into v_before from public.yamo_posts p where p.id = p_post_id;
  if v_before is null then raise exception 'post_not_found'; end if;
  update public.yamo_posts set deleted_at = now()
  where id = p_post_id and deleted_at is null;
  perform public.yamo_admin_log('post.remove','yamo_posts',p_post_id::text,
    v_before, null, p_reason);
  return true;
end $$;
revoke all on function public.admin_remove_yamo_post(uuid, text) from public, anon;
grant execute on function public.admin_remove_yamo_post(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- VIP grant (admin comp / support) - reuses the VIP subscription table.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_grant_yamo_vip(text, integer, integer, text);
create function public.admin_grant_yamo_vip(
  p_legacy_id text, p_level integer, p_days integer, p_reason text default null
)
returns timestamptz
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_target uuid; v_expiry timestamptz;
begin
  perform public.yamo_admin_require('users.moderate');
  if p_level not between 1 and 4 then raise exception 'invalid_vip_level'; end if;
  if p_days < 1 or p_days > 3650 then raise exception 'invalid_duration'; end if;
  select id into v_target from public.profiles where legacy_id = p_legacy_id;
  if v_target is null then raise exception 'user_not_found'; end if;

  select greatest(coalesce(expires_at, now()), now()) + (p_days || ' days')::interval
  into v_expiry from public.yamo_vip_subscriptions where user_id = v_target;
  if v_expiry is null then v_expiry := now() + (p_days || ' days')::interval; end if;

  insert into public.yamo_vip_subscriptions(user_id, level, expires_at)
  values (v_target, p_level, v_expiry)
  on conflict (user_id) do update set level = p_level,
    expires_at = v_expiry, updated_at = now();

  perform public.yamo_admin_log('vip.grant','yamo_vip_subscriptions',p_legacy_id,
    null, jsonb_build_object('level',p_level,'days',p_days), p_reason);
  return v_expiry;
end $$;
revoke all on function public.admin_grant_yamo_vip(text, integer, integer, text)
  from public, anon;
grant execute on function public.admin_grant_yamo_vip(text, integer, integer, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- GAMES: odds/limits are admin-tunable but never exposed to players.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_update_yamo_game_type(text, jsonb);
create function public.admin_update_yamo_game_type(p_game_type text, p_payload jsonb)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('games.manage');
  select to_jsonb(t) into v_before from public.yamo_game_types t
  where t.game_type = p_game_type;
  if v_before is null then raise exception 'game_not_found'; end if;

  update public.yamo_game_types set
    name_ar = coalesce(p_payload->>'name_ar', name_ar),
    min_bet_coins = coalesce((p_payload->>'min_bet_coins')::bigint, min_bet_coins),
    max_bet_coins = coalesce((p_payload->>'max_bet_coins')::bigint, max_bet_coins),
    win_probability = coalesce((p_payload->>'win_probability')::numeric, win_probability),
    win_multiplier = coalesce((p_payload->>'win_multiplier')::numeric, win_multiplier),
    enabled = coalesce((p_payload->>'enabled')::boolean, enabled)
  where game_type = p_game_type;

  perform public.yamo_admin_log('game.update','yamo_game_types',p_game_type,
    v_before, p_payload);
  return true;
end $$;
revoke all on function public.admin_update_yamo_game_type(text, jsonb) from public, anon;
grant execute on function public.admin_update_yamo_game_type(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS: admin broadcast (queues real rows + push outbox via trigger)
-- ---------------------------------------------------------------------------
drop function if exists public.admin_broadcast_yamo_notification(text, text, text, text);
create function public.admin_broadcast_yamo_notification(
  p_title text, p_body text, p_deep_link text default null, p_segment text default 'all'
)
returns bigint
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_count bigint;
begin
  perform public.yamo_admin_require('notifications.send');
  if length(trim(coalesce(p_title,''))) = 0 then raise exception 'title_required'; end if;

  insert into public.yamo_notifications(user_id, kind, title_ar, body_ar, deep_link)
  select p.id, 'system', p_title, coalesce(p_body,''), p_deep_link
  from public.profiles p
  where case p_segment
    when 'all' then true
    when 'vip' then exists(select 1 from public.yamo_vip_subscriptions v
      where v.user_id = p.id and v.expires_at > now())
    when 'hosts' then exists(select 1 from public.yamo_agency_hosts h
      where h.user_id = p.id and h.removed_at is null)
    else false end;

  get diagnostics v_count = row_count;
  perform public.yamo_admin_log('notification.broadcast','yamo_notifications',p_segment,
    null, jsonb_build_object('title',p_title,'recipients',v_count));
  return v_count;
end $$;
revoke all on function public.admin_broadcast_yamo_notification(text, text, text, text)
  from public, anon;
grant execute on function public.admin_broadcast_yamo_notification(text, text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- SETTINGS: app_config CRUD (banners, tunables) - no APK release needed.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_set_yamo_app_config(text, jsonb);
create function public.admin_set_yamo_app_config(p_key text, p_value jsonb)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before jsonb;
begin
  perform public.yamo_admin_require('settings.manage');
  select config_value into v_before from public.app_config where config_key = p_key;
  insert into public.app_config(config_key, config_value)
  values (p_key, p_value)
  on conflict (config_key) do update set config_value = excluded.config_value;
  perform public.yamo_admin_log('config.set','app_config',p_key, v_before, p_value);
  return true;
end $$;
revoke all on function public.admin_set_yamo_app_config(text, jsonb) from public, anon;
grant execute on function public.admin_set_yamo_app_config(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- RBAC management
-- ---------------------------------------------------------------------------
drop function if exists public.admin_assign_yamo_role(uuid, text, boolean);
create function public.admin_assign_yamo_role(
  p_user_id uuid, p_role text, p_grant boolean default true
)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_admin uuid;
begin
  v_admin := public.yamo_admin_require('admins.manage');
  if not exists(select 1 from public.yamo_admin_roles where role = p_role) then
    raise exception 'role_not_found';
  end if;
  -- Nobody can remove their own last super_admin role and lock everyone out.
  if not p_grant and p_user_id = v_admin and p_role = 'super_admin'
     and (select count(*) from public.yamo_admin_role_assignments
          where role = 'super_admin') <= 1 then
    raise exception 'cannot_remove_last_super_admin';
  end if;

  if p_grant then
    insert into public.yamo_admin_role_assignments(user_id, role, assigned_by)
    values (p_user_id, p_role, v_admin) on conflict do nothing;
  else
    delete from public.yamo_admin_role_assignments
    where user_id = p_user_id and role = p_role;
  end if;
  perform public.yamo_admin_log('rbac.assign','yamo_admin_role_assignments',
    p_user_id::text, null, jsonb_build_object('role',p_role,'grant',p_grant));
  return true;
end $$;
revoke all on function public.admin_assign_yamo_role(uuid, text, boolean) from public, anon;
grant execute on function public.admin_assign_yamo_role(uuid, text, boolean) to authenticated;

commit;
notify pgrst, 'reload schema';
