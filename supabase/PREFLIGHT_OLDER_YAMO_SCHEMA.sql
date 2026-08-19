-- Preflight for Yamo databases created by the early manual-payment prototype.
-- Must run before every app/admin migration because V119 already reads these
-- columns. Existing data and existing columns are left unchanged.

alter table if exists public.yamo_recharge_requests
  add column if not exists paid_amount numeric(14,2) not null default 0,
  add column if not exists currency_code text not null default 'EGP',
  add column if not exists sender_account text not null default '',
  add column if not exists proof_path text,
  add column if not exists expires_at timestamptz not null default (now() + interval '30 minutes'),
  add column if not exists updated_at timestamptz not null default now();

alter table if exists public.yamo_withdraw_requests
  add column if not exists fee_pearls bigint not null default 0,
  add column if not exists payout_amount numeric(14,2) not null default 0,
  add column if not exists currency_code text not null default 'EGP',
  add column if not exists payout_details jsonb not null default '{}'::jsonb,
  add column if not exists updated_at timestamptz not null default now();

-- The first push-token implementation keyed rows by user_id and only stored
-- token/platform. Production delivery needs a stable token-row UUID plus
-- runtime metadata. A UNIQUE index is sufficient for downstream foreign keys
-- even when the legacy table already has a different primary key.
alter table if exists public.yamo_device_tokens
  add column if not exists id uuid not null default gen_random_uuid(),
  add column if not exists device_id text,
  add column if not exists app_version text,
  add column if not exists enabled boolean not null default true,
  add column if not exists last_seen_at timestamptz not null default now(),
  add column if not exists created_at timestamptz not null default now();
create unique index if not exists yamo_device_tokens_id_uidx
  on public.yamo_device_tokens(id);

-- Reconcile the early seven-day deletion schema (execute_after/completed_at)
-- with the final app/panel contract. Keep the legacy columns and backfill the
-- final names so no existing request is lost.
alter table if exists public.yamo_account_deletion_requests
  add column if not exists reason text,
  add column if not exists eligible_at timestamptz,
  add column if not exists resolved_at timestamptz,
  add column if not exists resolved_by uuid references auth.users(id),
  add column if not exists admin_note text;

update public.yamo_account_deletion_requests
set eligible_at=coalesce(eligible_at,execute_after,requested_at+interval '7 days'),
    resolved_at=coalesce(resolved_at,completed_at)
where eligible_at is null or (resolved_at is null and completed_at is not null);

alter table if exists public.yamo_account_deletion_requests
  alter column eligible_at set default (now()+interval '7 days');

do $$
declare c record;
begin
  for c in select conname from pg_constraint
    where conrelid='public.yamo_account_deletion_requests'::regclass
      and contype='c' and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.yamo_account_deletion_requests drop constraint %I',c.conname);
  end loop;
end $$;
alter table if exists public.yamo_account_deletion_requests
  add constraint yamo_account_deletion_status_check
  check(status in('pending','approved','rejected','cancelled','completed')) not valid;

-- Remove only generated admin compatibility views from earlier/partial panel
-- installs. PostgreSQL cannot remove or reorder columns with CREATE OR REPLACE
-- VIEW (42P16). All of these views are rebuilt later in this same bundle.
do $$
declare v record;
begin
  for v in
    select schemaname,viewname from pg_views
    where schemaname='public' and viewname like 'admin\_%' escape '\'
  loop
    execute format('drop view if exists %I.%I cascade',v.schemaname,v.viewname);
  end loop;
end $$;
