-- Yamo Chat V120: Admin panel foundation on the YAMO database.
--
-- Source of truth = Yamo DB. This migration deliberately does NOT apply the
-- admin panel's own migrations, because:
--   * its public.wallets is incompatible with Yamo's (row-per-currency vs
--     coins/pearls columns, FK to profiles vs auth.users) AND it grants
--     INSERT/UPDATE on wallets directly to `authenticated`, which would let
--     any signed-in user edit their own balance. Applying it would undo the
--     entire Wallet phase.
--   * it ships a full parallel economy (transactions, wallet_ledger,
--     recharge_requests, withdrawal_requests, payment_methods, agencies,
--     hosts, 25 charging_* tables). Yamo already has all of these.
-- See Yamo_Admin_Schema_Map.md for the full conflict report.
--
-- Everything created here is prefixed yamo_admin_* (or yamo_event*) so it
-- can never collide with app tables. Nothing existing is dropped or altered.

begin;

-- ---------------------------------------------------------------------------
-- RBAC
-- ---------------------------------------------------------------------------
create table if not exists public.yamo_admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  is_active boolean not null default true,
  last_login_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.yamo_admin_roles (
  role text primary key,
  label_ar text not null,
  description text not null default '',
  sort_order integer not null default 0
);
insert into public.yamo_admin_roles(role, label_ar, description, sort_order) values
  ('super_admin', 'مدير عام', 'كل الصلاحيات', 1),
  ('admin', 'مدير', 'إدارة عامة بدون صلاحيات النظام', 2),
  ('finance', 'مالية', 'الشحن والسحب والمعاملات', 3),
  ('moderator', 'إشراف', 'المحتوى والبلاغات والحظر', 4),
  ('agency_manager', 'إدارة الوكالات', 'الوكالات والمضيفين', 5),
  ('support', 'دعم', 'قراءة بيانات المستخدمين', 6),
  ('auditor', 'مدقق', 'قراءة فقط مع سجل العمليات', 7),
  ('viewer', 'مشاهد', 'قراءة فقط', 8)
on conflict (role) do update set label_ar = excluded.label_ar,
  description = excluded.description, sort_order = excluded.sort_order;

create table if not exists public.yamo_admin_permissions (
  permission text primary key,
  label_ar text not null,
  category text not null default 'general'
);
insert into public.yamo_admin_permissions(permission, label_ar, category) values
  ('users.read','عرض المستخدمين','users'),
  ('users.moderate','حظر/إيقاف المستخدمين','users'),
  ('economy.read','عرض البيانات المالية','finance'),
  ('economy.adjust','تعديل الأرصدة','finance'),
  ('recharge.review','مراجعة طلبات الشحن','finance'),
  ('withdraw.review','مراجعة طلبات السحب','finance'),
  ('catalog.manage','إدارة الهدايا والمتجر','catalog'),
  ('rooms.manage','إدارة الغرف','content'),
  ('content.moderate','إدارة المنشورات والبلاغات','content'),
  ('agency.manage','إدارة الوكالات','agency'),
  ('tasks.manage','إدارة المهام','engagement'),
  ('events.manage','إدارة الأحداث','engagement'),
  ('notifications.send','إرسال الإشعارات','engagement'),
  ('games.manage','إعدادات الألعاب','games'),
  ('settings.manage','الإعدادات العامة','system'),
  ('admins.manage','إدارة المشرفين','system'),
  ('audit.read','عرض سجل العمليات','system')
on conflict (permission) do update set label_ar = excluded.label_ar,
  category = excluded.category;

create table if not exists public.yamo_admin_role_permissions (
  role text not null references public.yamo_admin_roles(role) on delete cascade,
  permission text not null references public.yamo_admin_permissions(permission) on delete cascade,
  primary key (role, permission)
);

-- Default grants.
insert into public.yamo_admin_role_permissions(role, permission)
select 'super_admin', permission from public.yamo_admin_permissions
on conflict do nothing;
insert into public.yamo_admin_role_permissions(role, permission) values
  ('admin','users.read'),('admin','users.moderate'),('admin','economy.read'),
  ('admin','catalog.manage'),('admin','rooms.manage'),('admin','content.moderate'),
  ('admin','agency.manage'),('admin','tasks.manage'),('admin','events.manage'),
  ('admin','notifications.send'),('admin','games.manage'),('admin','audit.read'),
  ('finance','economy.read'),('finance','recharge.review'),('finance','withdraw.review'),
  ('finance','economy.adjust'),('finance','users.read'),
  ('moderator','users.read'),('moderator','users.moderate'),('moderator','content.moderate'),
  ('moderator','rooms.manage'),
  ('agency_manager','agency.manage'),('agency_manager','users.read'),
  ('support','users.read'),
  ('auditor','users.read'),('auditor','economy.read'),('auditor','audit.read'),
  ('viewer','users.read')
on conflict do nothing;

create table if not exists public.yamo_admin_role_assignments (
  user_id uuid not null references public.yamo_admin_users(user_id) on delete cascade,
  role text not null references public.yamo_admin_roles(role) on delete cascade,
  assigned_at timestamptz not null default now(),
  assigned_by uuid references auth.users(id),
  primary key (user_id, role)
);

create table if not exists public.yamo_admin_invites (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  role text not null references public.yamo_admin_roles(role),
  token uuid not null default gen_random_uuid() unique,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days')
);

create table if not exists public.yamo_admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id),
  actor_email text,
  action text not null,
  entity_type text not null default '',
  entity_id text,
  before_state jsonb,
  after_state jsonb,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists yamo_admin_audit_logs_idx
  on public.yamo_admin_audit_logs(created_at desc);
create index if not exists yamo_admin_audit_logs_entity_idx
  on public.yamo_admin_audit_logs(entity_type, entity_id);

-- ---------------------------------------------------------------------------
-- Permission helper. Used by every admin RPC.
-- ---------------------------------------------------------------------------
create or replace function public.yamo_admin_has_permission(p_permission text)
returns boolean
language sql stable security definer set search_path = public, auth, pg_temp as $$
  select exists (
    select 1
    from public.yamo_admin_users u
    join public.yamo_admin_role_assignments ra on ra.user_id = u.user_id
    join public.yamo_admin_role_permissions rp on rp.role = ra.role
    where u.user_id = auth.uid()
      and u.is_active
      and rp.permission = p_permission
  );
$$;

create or replace function public.yamo_admin_require(p_permission text)
returns uuid
language plpgsql stable security definer set search_path = public, auth, pg_temp as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'authentication_required'; end if;
  if not public.yamo_admin_has_permission(p_permission) then
    raise exception 'permission_denied:%', p_permission;
  end if;
  return v_me;
end $$;

create or replace function public.yamo_admin_log(
  p_action text, p_entity_type text, p_entity_id text,
  p_before jsonb default null, p_after jsonb default null, p_note text default null
)
returns void
language plpgsql security definer set search_path = public, auth, pg_temp as $$
begin
  insert into public.yamo_admin_audit_logs(
    actor_id, actor_email, action, entity_type, entity_id, before_state, after_state, note)
  select auth.uid(), u.email, p_action, p_entity_type, p_entity_id, p_before, p_after, p_note
  from public.yamo_admin_users u where u.user_id = auth.uid();
end $$;
revoke all on function public.yamo_admin_log(text, text, text, jsonb, jsonb, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS: admins read their own admin identity; everything else is RPC-only.
-- ---------------------------------------------------------------------------
alter table public.yamo_admin_users enable row level security;
alter table public.yamo_admin_roles enable row level security;
alter table public.yamo_admin_permissions enable row level security;
alter table public.yamo_admin_role_permissions enable row level security;
alter table public.yamo_admin_role_assignments enable row level security;
alter table public.yamo_admin_invites enable row level security;
alter table public.yamo_admin_audit_logs enable row level security;

revoke all on public.yamo_admin_users, public.yamo_admin_roles,
  public.yamo_admin_permissions, public.yamo_admin_role_permissions,
  public.yamo_admin_role_assignments, public.yamo_admin_invites,
  public.yamo_admin_audit_logs from anon, authenticated;
grant select on public.yamo_admin_users, public.yamo_admin_roles,
  public.yamo_admin_permissions, public.yamo_admin_role_permissions,
  public.yamo_admin_role_assignments, public.yamo_admin_audit_logs to authenticated;

drop policy if exists yamo_admin_users_read on public.yamo_admin_users;
create policy yamo_admin_users_read on public.yamo_admin_users for select to authenticated
using (user_id = auth.uid() or public.yamo_admin_has_permission('admins.manage'));

drop policy if exists yamo_admin_roles_read on public.yamo_admin_roles;
create policy yamo_admin_roles_read on public.yamo_admin_roles for select to authenticated
using (public.yamo_admin_has_permission('users.read'));

drop policy if exists yamo_admin_permissions_read on public.yamo_admin_permissions;
create policy yamo_admin_permissions_read on public.yamo_admin_permissions for select to authenticated
using (public.yamo_admin_has_permission('users.read'));

drop policy if exists yamo_admin_role_permissions_read on public.yamo_admin_role_permissions;
create policy yamo_admin_role_permissions_read on public.yamo_admin_role_permissions
for select to authenticated using (public.yamo_admin_has_permission('users.read'));

drop policy if exists yamo_admin_role_assignments_read on public.yamo_admin_role_assignments;
create policy yamo_admin_role_assignments_read on public.yamo_admin_role_assignments
for select to authenticated
using (user_id = auth.uid() or public.yamo_admin_has_permission('admins.manage'));

drop policy if exists yamo_admin_audit_read on public.yamo_admin_audit_logs;
create policy yamo_admin_audit_read on public.yamo_admin_audit_logs for select to authenticated
using (public.yamo_admin_has_permission('audit.read'));

-- Who am I / what can I do.
drop function if exists public.get_yamo_admin_me();
create function public.get_yamo_admin_me()
returns table(user_id uuid, email text, full_name text, is_active boolean,
  roles text[], permissions text[])
language sql stable security definer set search_path = public, auth, pg_temp as $$
  select u.user_id, u.email, u.full_name, u.is_active,
    coalesce(array_agg(distinct ra.role) filter (where ra.role is not null), '{}'),
    coalesce(array_agg(distinct rp.permission) filter (where rp.permission is not null), '{}')
  from public.yamo_admin_users u
  left join public.yamo_admin_role_assignments ra on ra.user_id = u.user_id
  left join public.yamo_admin_role_permissions rp on rp.role = ra.role
  where u.user_id = auth.uid()
  group by u.user_id, u.email, u.full_name, u.is_active;
$$;
revoke all on function public.get_yamo_admin_me() from public, anon;
grant execute on function public.get_yamo_admin_me() to authenticated;

-- ---------------------------------------------------------------------------
-- EVENT BUILDER. Data-driven so a new event needs no APK release.
-- ---------------------------------------------------------------------------
create table if not exists public.yamo_events (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title_ar text not null,
  description_ar text not null default '',
  banner_url text,
  cover_url text,
  event_type text not null default 'generic',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'draft' check (status in ('draft','scheduled','live','ended','archived')),
  -- Which leaderboard metric ranks participants. Reuses the same metric
  -- vocabulary as the task system so no new engine is needed.
  leaderboard_metric text check (leaderboard_metric in
    ('ROOM_GIFT_COINS','GIFT_PEARLS_RECEIVED','AGENCY_TARGET_PEARLS','MESSAGE_REPLIES', null)),
  target_room_ids text[] not null default '{}',
  join_conditions jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists yamo_events_live_idx on public.yamo_events(status, starts_at desc);

create table if not exists public.yamo_event_rewards (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.yamo_events(id) on delete cascade,
  rank_from integer not null default 1 check (rank_from >= 1),
  rank_to integer not null default 1 check (rank_to >= 1),
  reward_asset text not null check (reward_asset in ('COINS','PEARLS','PROFILE_FRAME','ENTRANCE_EFFECT','VIP')),
  reward_value bigint not null default 0 check (reward_value >= 0),
  reward_asset_key text,
  title_ar text not null default '',
  sort_order integer not null default 0,
  check (rank_to >= rank_from)
);

create table if not exists public.yamo_event_tasks (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.yamo_events(id) on delete cascade,
  title_ar text not null,
  metric text not null,
  target_value bigint not null check (target_value > 0),
  reward_asset text not null default 'COINS',
  reward_value bigint not null default 0,
  sort_order integer not null default 0
);

create table if not exists public.yamo_event_participants (
  event_id uuid not null references public.yamo_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  score bigint not null default 0,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

alter table public.yamo_events enable row level security;
alter table public.yamo_event_rewards enable row level security;
alter table public.yamo_event_tasks enable row level security;
alter table public.yamo_event_participants enable row level security;

revoke all on public.yamo_events, public.yamo_event_rewards,
  public.yamo_event_tasks, public.yamo_event_participants from anon, authenticated;
grant select on public.yamo_events, public.yamo_event_rewards,
  public.yamo_event_tasks, public.yamo_event_participants to authenticated;

-- Players see only published events; admins with events.manage see all.
drop policy if exists yamo_events_read on public.yamo_events;
create policy yamo_events_read on public.yamo_events for select to authenticated
using (status in ('scheduled','live','ended') or public.yamo_admin_has_permission('events.manage'));

drop policy if exists yamo_event_rewards_read on public.yamo_event_rewards;
create policy yamo_event_rewards_read on public.yamo_event_rewards for select to authenticated
using (true);

drop policy if exists yamo_event_tasks_read on public.yamo_event_tasks;
create policy yamo_event_tasks_read on public.yamo_event_tasks for select to authenticated
using (true);

drop policy if exists yamo_event_participants_read on public.yamo_event_participants;
create policy yamo_event_participants_read on public.yamo_event_participants
for select to authenticated using (true);

-- Event CRUD (admin, permission-gated, audited).
drop function if exists public.upsert_yamo_event(uuid, jsonb);
create function public.upsert_yamo_event(p_event_id uuid, p_payload jsonb)
returns uuid
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_me uuid := public.yamo_admin_require('events.manage');
        v_id uuid; v_before jsonb;
begin
  if p_event_id is null then
    insert into public.yamo_events(
      slug, title_ar, description_ar, banner_url, cover_url, event_type,
      starts_at, ends_at, status, leaderboard_metric, target_room_ids,
      join_conditions, metadata, created_by)
    values (
      coalesce(p_payload->>'slug', gen_random_uuid()::text),
      coalesce(p_payload->>'title_ar',''),
      coalesce(p_payload->>'description_ar',''),
      p_payload->>'banner_url', p_payload->>'cover_url',
      coalesce(p_payload->>'event_type','generic'),
      (p_payload->>'starts_at')::timestamptz,
      (p_payload->>'ends_at')::timestamptz,
      coalesce(p_payload->>'status','draft'),
      nullif(p_payload->>'leaderboard_metric',''),
      coalesce((select array_agg(value::text) from jsonb_array_elements_text(
        coalesce(p_payload->'target_room_ids','[]'::jsonb)) as value), '{}'),
      coalesce(p_payload->'join_conditions','{}'::jsonb),
      coalesce(p_payload->'metadata','{}'::jsonb),
      v_me)
    returning id into v_id;
    perform public.yamo_admin_log('event.create','yamo_events',v_id::text,null,p_payload);
  else
    select to_jsonb(e) into v_before from public.yamo_events e where e.id = p_event_id;
    if v_before is null then raise exception 'event_not_found'; end if;
    update public.yamo_events set
      title_ar = coalesce(p_payload->>'title_ar', title_ar),
      description_ar = coalesce(p_payload->>'description_ar', description_ar),
      banner_url = coalesce(p_payload->>'banner_url', banner_url),
      cover_url = coalesce(p_payload->>'cover_url', cover_url),
      event_type = coalesce(p_payload->>'event_type', event_type),
      starts_at = coalesce((p_payload->>'starts_at')::timestamptz, starts_at),
      ends_at = coalesce((p_payload->>'ends_at')::timestamptz, ends_at),
      status = coalesce(p_payload->>'status', status),
      leaderboard_metric = coalesce(nullif(p_payload->>'leaderboard_metric',''), leaderboard_metric),
      join_conditions = coalesce(p_payload->'join_conditions', join_conditions),
      metadata = coalesce(p_payload->'metadata', metadata),
      updated_at = now()
    where id = p_event_id returning id into v_id;
    perform public.yamo_admin_log('event.update','yamo_events',v_id::text,v_before,p_payload);
  end if;
  return v_id;
end $$;
revoke all on function public.upsert_yamo_event(uuid, jsonb) from public, anon;
grant execute on function public.upsert_yamo_event(uuid, jsonb) to authenticated;

drop function if exists public.set_yamo_event_status(uuid, text);
create function public.set_yamo_event_status(p_event_id uuid, p_status text)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_before text;
begin
  perform public.yamo_admin_require('events.manage');
  if p_status not in ('draft','scheduled','live','ended','archived') then
    raise exception 'invalid_status';
  end if;
  select status into v_before from public.yamo_events where id = p_event_id;
  if v_before is null then raise exception 'event_not_found'; end if;
  update public.yamo_events set status = p_status, updated_at = now() where id = p_event_id;
  perform public.yamo_admin_log('event.status','yamo_events',p_event_id::text,
    to_jsonb(v_before), to_jsonb(p_status));
  return true;
end $$;
revoke all on function public.set_yamo_event_status(uuid, text) from public, anon;
grant execute on function public.set_yamo_event_status(uuid, text) to authenticated;

-- Live leaderboard, derived from real ledgers (never client-reported).
drop function if exists public.get_yamo_event_leaderboard(uuid, integer);
create function public.get_yamo_event_leaderboard(p_event_id uuid, p_limit integer default 50)
returns table(rank bigint, legacy_id text, display_name text, avatar_url text, score bigint)
language plpgsql stable security definer set search_path = public, auth, pg_temp as $$
declare v_e public.yamo_events%rowtype;
begin
  select * into v_e from public.yamo_events where id = p_event_id;
  if v_e.id is null then raise exception 'event_not_found'; end if;

  if v_e.leaderboard_metric = 'ROOM_GIFT_COINS' then
    return query
    select row_number() over (order by sum(b.total_coins) desc),
      p.legacy_id, coalesce(p.display_name, p.legacy_id), p.avatar_url,
      sum(b.total_coins)::bigint
    from public.room_gift_batches b
    join public.profiles p on p.id = b.sender_id
    where b.created_at between v_e.starts_at and v_e.ends_at
      and (cardinality(v_e.target_room_ids) = 0 or b.room_id = any(v_e.target_room_ids))
    group by p.id, p.legacy_id, p.display_name, p.avatar_url
    order by 5 desc limit least(greatest(coalesce(p_limit,50),1),200);

  elsif v_e.leaderboard_metric = 'GIFT_PEARLS_RECEIVED' then
    return query
    select row_number() over (order by sum(t.coins) desc),
      p.legacy_id, coalesce(p.display_name, p.legacy_id), p.avatar_url,
      sum(t.coins)::bigint
    from public.room_gift_transactions t
    join public.profiles p on p.id = t.receiver_id
    where t.created_at between v_e.starts_at and v_e.ends_at
      and (cardinality(v_e.target_room_ids) = 0 or t.room_id = any(v_e.target_room_ids))
    group by p.id, p.legacy_id, p.display_name, p.avatar_url
    order by 5 desc limit least(greatest(coalesce(p_limit,50),1),200);

  else
    return query
    select row_number() over (order by ep.score desc),
      p.legacy_id, coalesce(p.display_name, p.legacy_id), p.avatar_url, ep.score
    from public.yamo_event_participants ep
    join public.profiles p on p.id = ep.user_id
    where ep.event_id = p_event_id
    order by ep.score desc limit least(greatest(coalesce(p_limit,50),1),200);
  end if;
end $$;
revoke all on function public.get_yamo_event_leaderboard(uuid, integer) from public, anon;
grant execute on function public.get_yamo_event_leaderboard(uuid, integer) to authenticated;

commit;
notify pgrst, 'reload schema';
