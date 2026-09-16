begin;

-- ==========================================================================
-- V161 — one cup ledger/window for the global cup and the in-room cup.
-- DAILY is the configurable operational shift from yamo_room_cup_config_v160.
-- ==========================================================================
create or replace function public.get_yamo_general_cup(
  p_board text,
  p_period text,
  p_limit integer default 100
)
returns table(
  entity_id text,
  legacy_user_id text,
  total_coins bigint,
  title text,
  country_flag text,
  room_display_id text
)
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare
  since_at timestamptz := public.yamo_room_cup_window_start_v160(p_period);
  lim integer := least(100,greatest(1,coalesce(p_limit,100)));
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;

  if lower(coalesce(p_board,''))='receivers' then
    return query
    select
      p.legacy_id::text,
      p.legacy_id::text,
      sum(t.coins)::bigint,
      coalesce(p.display_name,p.legacy_id)::text,
      coalesce(p.country_flag,'')::text,
      null::text
    from public.room_gift_transactions t
    join public.profiles p on p.id=t.receiver_id
    where t.created_at>=since_at
    group by p.id,p.legacy_id,p.display_name,p.country_flag
    order by 3 desc
    limit lim;

  elsif lower(coalesce(p_board,''))='rooms' then
    return query
    select
      r.room_id::text,
      null::text,
      sum(b.total_coins)::bigint,
      coalesce(r.title,r.room_id)::text,
      ''::text,
      r.room_id::text
    from public.room_gift_batches b
    join public.yamo_owned_rooms r on r.room_id=b.room_id
    where b.created_at>=since_at
    group by r.room_id,r.title
    order by 3 desc
    limit lim;

  else
    return query
    select
      p.legacy_id::text,
      p.legacy_id::text,
      sum(b.total_coins)::bigint,
      coalesce(p.display_name,p.legacy_id)::text,
      coalesce(p.country_flag,'')::text,
      null::text
    from public.room_gift_batches b
    join public.profiles p on p.id=b.sender_id
    where b.created_at>=since_at
    group by p.id,p.legacy_id,p.display_name,p.country_flag
    order by 3 desc
    limit lim;
  end if;
end $$;
revoke all on function public.get_yamo_general_cup(text,text,integer) from public,anon;
grant execute on function public.get_yamo_general_cup(text,text,integer) to authenticated;

-- ==========================================================================
-- Very small account guard used while the app is open. The Android app polls
-- this lightweight function so an admin ban takes effect without waiting for
-- app restart or another feature refresh.
-- ==========================================================================
create or replace function public.get_yamo_session_guard_v161()
returns table(
  allowed boolean,
  account_status text,
  ban_number bigint,
  legacy_id text
)
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select
    coalesce(p.account_status,'active')='active' as allowed,
    coalesce(p.account_status,'active')::text as account_status,
    (
      select m.ban_number
      from public.yamo_moderation_actions m
      where m.user_id=p.id and m.active and m.action_type='ban'
      order by m.created_at desc
      limit 1
    ) as ban_number,
    p.legacy_id::text
  from public.profiles p
  where p.id=auth.uid()
  limit 1
$$;
revoke all on function public.get_yamo_session_guard_v161() from public,anon;
grant execute on function public.get_yamo_session_guard_v161() to authenticated;

-- Mark the account-status change as an immediately effective security action.
-- The app guard above observes this profiles.account_status value directly.
create index if not exists profiles_account_status_guard_idx on public.profiles(id,account_status);
create index if not exists yamo_moderation_active_guard_idx
  on public.yamo_moderation_actions(user_id,active,action_type,created_at desc);

commit;
notify pgrst,'reload schema';
