-- Yamo Chat V235 - Reset and rebuild the complete charging agency server.
-- Backs up the current charging schema, removes it, then creates a clean system.

begin;

-- Destructive reset requested by the owner. Keep a recoverable snapshot first.
create schema if not exists charging_backup_v235;
do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'charging_activity_ledger','charging_usdt_requests','charging_agent_profits',
    'charging_packages','charging_country_prices','charging_system_settings',
    'pearl_coin_exchange_rates','charging_price_rules','charging_pearl_transfers',
    'charging_coin_transfers','charging_agent_daily_stats','charging_agency_daily_stats',
    'charging_agent_settings','charging_agency_members','charging_agencies'
  ] loop
    if to_regclass('public.' || tbl) is not null then
      execute format('drop table if exists charging_backup_v235.%I', tbl);
      execute format('create table charging_backup_v235.%I as table public.%I', tbl, tbl);
    end if;
  end loop;
end $$;

drop table if exists public.charging_activity_ledger cascade;
drop table if exists public.charging_usdt_requests cascade;
drop table if exists public.charging_agent_profits cascade;
drop table if exists public.charging_packages cascade;
drop table if exists public.charging_country_prices cascade;
drop table if exists public.charging_system_settings cascade;
drop table if exists public.pearl_coin_exchange_rates cascade;
drop table if exists public.charging_price_rules cascade;
drop table if exists public.charging_pearl_transfers cascade;
drop table if exists public.charging_coin_transfers cascade;
drop table if exists public.charging_agent_daily_stats cascade;
drop table if exists public.charging_agency_daily_stats cascade;
drop table if exists public.charging_agent_settings cascade;
drop table if exists public.charging_agency_members cascade;
drop table if exists public.charging_agencies cascade;
drop sequence if exists public.charging_agency_display_id_seq cascade;
drop sequence if exists public.charging_transfer_reference_seq cascade;

create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.charging_agency_status as enum ('pending','active','suspended','under_review','closed');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.charging_agent_role as enum ('charging_agency_owner','charging_agency_deputy','charging_agent','charging_accountant','charging_supervisor','charging_region_manager','charging_country_manager');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.charging_agent_status as enum ('active','suspended','inactive');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.charging_txn_status as enum ('pending','completed','reversed','failed');
exception when duplicate_object then null; end $$;

create sequence if not exists public.charging_agency_display_id_seq start 1000;
create sequence if not exists public.charging_transfer_reference_seq start 100000;

create table if not exists public.charging_agencies (
  id uuid primary key default gen_random_uuid(),
  display_id text not null unique default ('CHG-' || nextval('public.charging_agency_display_id_seq')::text),
  name text not null check (length(trim(name)) between 2 and 100),
  owner_user_id uuid references public.profiles(id) on delete restrict,
  deputy_user_id uuid references public.profiles(id) on delete set null,
  country text,
  city text,
  default_currency text not null default 'USD',
  phone text,
  email text,
  logo_url text,
  cover_url text,
  level_id integer,
  commission_rate numeric(5,2) default 0 check (commission_rate between 0 and 100),
  daily_coin_transfer_limit bigint default 0 check (daily_coin_transfer_limit >= 0),
  monthly_coin_transfer_limit bigint default 0 check (monthly_coin_transfer_limit >= 0),
  daily_pearl_transfer_limit bigint default 0 check (daily_pearl_transfer_limit >= 0),
  monthly_pearl_transfer_limit bigint default 0 check (monthly_pearl_transfer_limit >= 0),
  min_coin_transfer bigint default 1 check (min_coin_transfer >= 0),
  max_coin_transfer bigint default 0 check (max_coin_transfer >= 0),
  min_pearl_transfer bigint default 1 check (min_pearl_transfer >= 0),
  max_pearl_transfer bigint default 0 check (max_pearl_transfer >= 0),
  can_sell_coins boolean not null default true,
  can_buy_pearls boolean not null default true,
  can_exchange_pearls_to_coins boolean not null default true,
  can_transfer_to_agents boolean not null default true,
  can_receive_from_agents boolean not null default true,
  supported_payment_methods jsonb not null default '[]'::jsonb,
  status public.charging_agency_status not null default 'active',
  admin_notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.charging_agency_members (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.charging_agencies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  member_role public.charging_agent_role not null default 'charging_agent',
  status public.charging_agent_status not null default 'active',
  assigned_by uuid references auth.users(id) on delete set null default auth.uid(),
  assigned_at timestamptz not null default now(),
  removed_at timestamptz
);
create unique index if not exists charging_agency_one_active_membership
  on public.charging_agency_members(user_id) where status = 'active' and removed_at is null;
create index if not exists charging_agency_members_agency_idx on public.charging_agency_members(agency_id,status);

create table if not exists public.charging_agent_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  agency_id uuid references public.charging_agencies(id) on delete set null,
  status public.charging_agent_status not null default 'active',
  daily_coin_limit bigint default 0,
  monthly_coin_limit bigint default 0,
  daily_pearl_limit bigint default 0,
  monthly_pearl_limit bigint default 0,
  min_coin_transfer bigint default 1,
  max_coin_transfer bigint default 0,
  min_pearl_transfer bigint default 1,
  max_pearl_transfer bigint default 0,
  can_sell_coins boolean not null default true,
  can_buy_pearls boolean not null default true,
  can_exchange_pearls_to_coins boolean not null default true,
  can_transfer_to_agents boolean not null default false,
  confirmation_pin_hash text,
  suspend_reason text,
  suspended_at timestamptz,
  suspended_by uuid references auth.users(id) on delete set null,
  activated_at timestamptz not null default now(),
  activated_by uuid references auth.users(id) on delete set null default auth.uid(),
  deactivated_at timestamptz,
  deactivated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.charging_agency_daily_stats (
  agency_id uuid not null references public.charging_agencies(id) on delete cascade,
  day date not null default current_date,
  coins_sent bigint not null default 0,
  pearls_sent bigint not null default 0,
  pearls_bought bigint not null default 0,
  pearls_exchanged bigint not null default 0,
  transfer_count bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (agency_id,day)
);

create table if not exists public.charging_agent_daily_stats (
  agent_user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null default current_date,
  coins_received bigint not null default 0,
  coins_sent bigint not null default 0,
  pearls_received bigint not null default 0,
  pearls_sent bigint not null default 0,
  pearls_bought bigint not null default 0,
  pearls_exchanged bigint not null default 0,
  transfer_count bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (agent_user_id,day)
);

create table if not exists public.charging_coin_transfers (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique default ('C-' || nextval('public.charging_transfer_reference_seq')::text),
  agency_id uuid references public.charging_agencies(id) on delete set null,
  agent_user_id uuid not null references public.profiles(id) on delete restrict,
  recipient_user_id uuid not null references public.profiles(id) on delete restrict,
  recipient_is_agent boolean not null default false,
  amount bigint not null check (amount > 0),
  sale_price numeric(18,2),
  commission_amount numeric(18,2) default 0,
  currency text default 'USD',
  status public.charging_txn_status not null default 'completed',
  payment_reference text,
  payment_method_id uuid,
  receipt_url text,
  note text,
  message_id uuid,
  idempotency_key text unique,
  reversed_by uuid references public.charging_coin_transfers(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz default now()
);
create index if not exists charging_coin_transfers_agency_idx on public.charging_coin_transfers(agency_id,created_at desc);

create table if not exists public.charging_pearl_transfers (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique default ('P-' || nextval('public.charging_transfer_reference_seq')::text),
  from_user_id uuid not null references public.profiles(id) on delete restrict,
  to_user_id uuid not null references public.profiles(id) on delete restrict,
  amount bigint not null check (amount > 0),
  status public.charging_txn_status not null default 'completed',
  note text,
  message_id uuid,
  idempotency_key text unique,
  created_at timestamptz not null default now(),
  completed_at timestamptz default now()
);

create table if not exists public.charging_price_rules (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid references public.charging_agencies(id) on delete cascade,
  agent_level_id integer,
  country text,
  currency text not null default 'USD',
  operation text not null check (operation in ('coin_sale','pearl_buy','pearl_exchange')),
  tier_from bigint not null default 0,
  tier_to bigint,
  unit_price numeric(18,6) not null,
  fee_percentage numeric(5,2) default 0 check (fee_percentage between 0 and 100),
  commission_percentage numeric(5,2) default 0 check (commission_percentage between 0 and 100),
  discount_percentage numeric(5,2) default 0 check (discount_percentage between 0 and 100),
  status text not null default 'active',
  version integer not null default 1,
  starts_at timestamptz default now(),
  ends_at timestamptz,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pearl_coin_exchange_rates (
  id uuid primary key default gen_random_uuid(),
  country text,
  pearl_amount_from bigint not null default 0,
  pearl_amount_to bigint,
  coins_per_pearl numeric(18,6) not null,
  fee_percentage numeric(5,2) default 0 check (fee_percentage between 0 and 100),
  min_exchange bigint default 1,
  max_exchange bigint default 0,
  status text not null default 'active',
  starts_at timestamptz default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.yamo_charging_admin_allowed()
returns boolean language plpgsql stable security definer set search_path='public','auth','pg_temp' as $$
declare ok boolean := false;
begin
  if auth.uid() is null then return false; end if;
  if to_regprocedure('public.yamo_admin_has_permission(text)') is not null then
    execute 'select public.yamo_admin_has_permission($1) or public.yamo_admin_has_permission($2)'
      into ok using 'economy.read','charging_agencies.read';
  end if;
  return coalesce(ok,false);
end $$;

create or replace function public.yamo_charging_require_admin()
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$
begin
  if not public.yamo_charging_admin_allowed() then raise exception 'admin_permission_required'; end if;
end $$;

create or replace function public.create_charging_agency(_name text,_country text,_city text,_default_currency text,_owner_user_id uuid,_deputy_user_id uuid,_phone text,_email text)
returns uuid language plpgsql security definer set search_path='public','auth','pg_temp' as $$
declare new_id uuid;
begin
  perform public.yamo_charging_require_admin();
  if _owner_user_id is null then raise exception 'owner_required'; end if;
  if nullif(trim(coalesce(_phone,'')),'') is null then raise exception 'whatsapp_required'; end if;
  if not exists(select 1 from public.profiles where id=_owner_user_id) then raise exception 'owner_not_found'; end if;
  insert into public.charging_agencies(name,country,city,default_currency,owner_user_id,deputy_user_id,phone,email)
  values(trim(_name),nullif(trim(_country),''),nullif(trim(_city),''),upper(coalesce(nullif(trim(_default_currency),''),'USD')),_owner_user_id,_deputy_user_id,trim(_phone),nullif(trim(_email),'')) returning id into new_id;
  insert into public.charging_agency_members(agency_id,user_id,member_role) values(new_id,_owner_user_id,'charging_agency_owner');
  insert into public.charging_agent_settings(user_id,agency_id,can_transfer_to_agents) values(_owner_user_id,new_id,true)
  on conflict(user_id) do update set agency_id=excluded.agency_id,status='active',updated_at=now();
  return new_id;
end $$;

create or replace function public.activate_charging_agent(_user_id uuid,_agency_id uuid,_member_role public.charging_agent_role default 'charging_agent',_notes text default null)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$
begin
  perform public.yamo_charging_require_admin();
  update public.charging_agency_members set status='inactive',removed_at=now() where user_id=_user_id and status='active';
  insert into public.charging_agency_members(agency_id,user_id,member_role,status) values(_agency_id,_user_id,_member_role,'active');
  insert into public.charging_agent_settings(user_id,agency_id,status) values(_user_id,_agency_id,'active')
  on conflict(user_id) do update set agency_id=excluded.agency_id,status='active',suspend_reason=null,suspended_at=null,updated_at=now();
end $$;

create or replace function public.suspend_charging_agency(_agency_id uuid,_reason text)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$ begin perform public.yamo_charging_require_admin(); if length(trim(coalesce(_reason,'')))<5 then raise exception 'reason_required'; end if; update public.charging_agencies set status='suspended',admin_notes=concat_ws(E'\n',admin_notes,'تعليق: '||_reason),updated_by=auth.uid(),updated_at=now() where id=_agency_id and deleted_at is null; end $$;
create or replace function public.reactivate_charging_agency(_agency_id uuid)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$ begin perform public.yamo_charging_require_admin(); update public.charging_agencies set status='active',updated_by=auth.uid(),updated_at=now() where id=_agency_id and deleted_at is null; end $$;
create or replace function public.close_charging_agency(_agency_id uuid,_reason text)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$ begin perform public.yamo_charging_require_admin(); if length(trim(coalesce(_reason,'')))<5 then raise exception 'reason_required'; end if; update public.charging_agencies set status='closed',admin_notes=concat_ws(E'\n',admin_notes,'إغلاق: '||_reason),updated_by=auth.uid(),updated_at=now() where id=_agency_id; update public.charging_agency_members set status='inactive',removed_at=now() where agency_id=_agency_id and status='active'; update public.charging_agent_settings set status='inactive',deactivated_at=now(),deactivated_by=auth.uid(),updated_at=now() where agency_id=_agency_id; end $$;
create or replace function public.suspend_charging_agent(_user_id uuid,_reason text)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$ begin perform public.yamo_charging_require_admin(); if length(trim(coalesce(_reason,'')))<5 then raise exception 'reason_required'; end if; update public.charging_agent_settings set status='suspended',suspend_reason=_reason,suspended_at=now(),suspended_by=auth.uid(),updated_at=now() where user_id=_user_id; update public.charging_agency_members set status='suspended' where user_id=_user_id and status='active'; end $$;
create or replace function public.reactivate_charging_agent(_user_id uuid)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$ begin perform public.yamo_charging_require_admin(); update public.charging_agent_settings set status='active',suspend_reason=null,suspended_at=null,suspended_by=null,updated_at=now() where user_id=_user_id; update public.charging_agency_members set status='active',removed_at=null where user_id=_user_id and status='suspended'; end $$;

create or replace function public.reverse_coin_transfer(_transfer_id uuid,_reason text)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$
declare t public.charging_coin_transfers; remaining bigint;
begin perform public.yamo_charging_require_admin(); if length(trim(coalesce(_reason,'')))<5 then raise exception 'reason_required'; end if; select * into t from public.charging_coin_transfers where id=_transfer_id for update; if t.id is null or t.status<>'completed' then raise exception 'invalid_transfer'; end if;
  update public.wallets set coins=coins-t.amount,updated_at=now() where user_id=t.recipient_user_id and coins>=t.amount returning coins into remaining; if remaining is null then raise exception 'recipient_balance_insufficient'; end if;
  update public.wallets set coins=coins+t.amount,updated_at=now() where user_id=t.agent_user_id;
  update public.charging_coin_transfers set status='reversed',note=concat_ws(E'\n',note,'عكس: '||_reason),completed_at=now() where id=t.id;
end $$;

create or replace function public.reverse_pearl_transfer(_transfer_id uuid,_reason text)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$
declare t public.charging_pearl_transfers; remaining bigint;
begin perform public.yamo_charging_require_admin(); if length(trim(coalesce(_reason,'')))<5 then raise exception 'reason_required'; end if; select * into t from public.charging_pearl_transfers where id=_transfer_id for update; if t.id is null or t.status<>'completed' then raise exception 'invalid_transfer'; end if;
  update public.wallets set pearls=pearls-t.amount,updated_at=now() where user_id=t.to_user_id and pearls>=t.amount returning pearls into remaining; if remaining is null then raise exception 'recipient_balance_insufficient'; end if;
  update public.wallets set pearls=pearls+t.amount,updated_at=now() where user_id=t.from_user_id;
  update public.charging_pearl_transfers set status='reversed',note=concat_ws(E'\n',note,'عكس: '||_reason),completed_at=now() where id=t.id;
end $$;

create or replace function public.yamo_charging_update_stats()
returns trigger language plpgsql security definer set search_path='public','auth','pg_temp' as $$
declare agency uuid;
begin
  if tg_table_name='charging_coin_transfers' then
    if new.status='completed' and (tg_op='INSERT' or old.status is distinct from new.status) then
      if new.agency_id is not null then
        insert into public.charging_agency_daily_stats(agency_id,day,coins_sent,transfer_count) values(new.agency_id,current_date,new.amount,1)
        on conflict(agency_id,day) do update set coins_sent=charging_agency_daily_stats.coins_sent+excluded.coins_sent,transfer_count=charging_agency_daily_stats.transfer_count+1,updated_at=now();
      end if;
      insert into public.charging_agent_daily_stats(agent_user_id,day,coins_sent,transfer_count) values(new.agent_user_id,current_date,new.amount,1)
      on conflict(agent_user_id,day) do update set coins_sent=charging_agent_daily_stats.coins_sent+excluded.coins_sent,transfer_count=charging_agent_daily_stats.transfer_count+1,updated_at=now();
    end if;
  else
    if new.status='completed' and (tg_op='INSERT' or old.status is distinct from new.status) then
      select agency_id into agency from public.charging_agent_settings where user_id=new.from_user_id;
      if agency is not null then insert into public.charging_agency_daily_stats(agency_id,day,pearls_sent,transfer_count) values(agency,current_date,new.amount,1) on conflict(agency_id,day) do update set pearls_sent=charging_agency_daily_stats.pearls_sent+excluded.pearls_sent,transfer_count=charging_agency_daily_stats.transfer_count+1,updated_at=now(); end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists charging_coin_stats_tr on public.charging_coin_transfers;
create trigger charging_coin_stats_tr after insert or update of status on public.charging_coin_transfers for each row execute function public.yamo_charging_update_stats();
drop trigger if exists charging_pearl_stats_tr on public.charging_pearl_transfers;
create trigger charging_pearl_stats_tr after insert or update of status on public.charging_pearl_transfers for each row execute function public.yamo_charging_update_stats();

alter table public.charging_agencies enable row level security;
alter table public.charging_agency_members enable row level security;
alter table public.charging_agent_settings enable row level security;
alter table public.charging_agency_daily_stats enable row level security;
alter table public.charging_agent_daily_stats enable row level security;
alter table public.charging_coin_transfers enable row level security;
alter table public.charging_pearl_transfers enable row level security;
alter table public.charging_price_rules enable row level security;
alter table public.pearl_coin_exchange_rates enable row level security;

do $$ declare tbl text; begin
  foreach tbl in array array['charging_agencies','charging_agency_members','charging_agent_settings','charging_agency_daily_stats','charging_agent_daily_stats','charging_coin_transfers','charging_pearl_transfers','charging_price_rules','pearl_coin_exchange_rates'] loop
    execute format('drop policy if exists charging_admin_read on public.%I',tbl);
    execute format('create policy charging_admin_read on public.%I for select to authenticated using (public.yamo_charging_admin_allowed())',tbl);
    execute format('grant select on public.%I to authenticated',tbl);
  end loop;
end $$;

grant execute on function public.create_charging_agency(text,text,text,text,uuid,uuid,text,text) to authenticated;
grant execute on function public.activate_charging_agent(uuid,uuid,public.charging_agent_role,text) to authenticated;
grant execute on function public.suspend_charging_agency(uuid,text) to authenticated;
grant execute on function public.reactivate_charging_agency(uuid) to authenticated;
grant execute on function public.close_charging_agency(uuid,text) to authenticated;
grant execute on function public.suspend_charging_agent(uuid,text) to authenticated;
grant execute on function public.reactivate_charging_agent(uuid) to authenticated;
grant execute on function public.reverse_coin_transfer(uuid,text) to authenticated;
grant execute on function public.reverse_pearl_transfer(uuid,text) to authenticated;

-- V233: unified controls, packages, commissions and smart country pricing.
create table if not exists public.charging_system_settings (
  id boolean primary key default true check (id),
  system_enabled boolean not null default true,
  coin_packages_enabled boolean not null default true,
  pearl_buy_enabled boolean not null default true,
  pearl_exchange_enabled boolean not null default true,
  usdt_packages_enabled boolean not null default true,
  default_agent_commission numeric(5,2) not null default 0 check (default_agent_commission between 0 and 100),
  fallback_country_code text not null default 'US',
  fallback_currency text not null default 'USD',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.charging_system_settings(id) values(true) on conflict(id) do nothing;

alter table public.charging_agent_settings add column if not exists commission_rate numeric(5,2);
alter table public.charging_agent_settings drop constraint if exists charging_agent_settings_commission_rate_check;
alter table public.charging_agent_settings add constraint charging_agent_settings_commission_rate_check check (commission_rate is null or commission_rate between 0 and 100);

create table if not exists public.charging_country_prices (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  currency text not null,
  operation text not null check (operation in ('coin_package','pearl_buy','pearl_exchange','usdt_package')),
  enabled boolean not null default true,
  exchange_rate_to_usd numeric(18,6),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(country_code,operation)
);

create table if not exists public.charging_packages (
  id uuid primary key default gen_random_uuid(),
  package_type text not null check (package_type in ('coin','pearl_buy','pearl_exchange','usdt')),
  name text not null,
  country_code text,
  currency text not null default 'USD',
  money_amount numeric(18,2) not null default 0 check (money_amount >= 0),
  coin_amount bigint not null default 0 check (coin_amount >= 0),
  pearl_amount bigint not null default 0 check (pearl_amount >= 0),
  usdt_amount numeric(18,2) not null default 0 check (usdt_amount >= 0),
  bonus_amount bigint not null default 0 check (bonus_amount >= 0),
  fee_percentage numeric(5,2) not null default 0 check (fee_percentage between 0 and 100),
  discount_percentage numeric(5,2) not null default 0 check (discount_percentage between 0 and 100),
  agent_only boolean not null default false,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists charging_packages_lookup_idx on public.charging_packages(package_type,country_code,enabled,sort_order);

create table if not exists public.charging_agent_profits (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.charging_agencies(id) on delete restrict,
  agent_user_id uuid not null references public.profiles(id) on delete restrict,
  operation_type text not null,
  operation_id uuid,
  gross_amount numeric(18,2) not null default 0,
  commission_rate numeric(5,2) not null check (commission_rate between 0 and 100),
  commission_amount numeric(18,2) not null default 0,
  platform_net numeric(18,2) not null default 0,
  currency text not null default 'USD',
  status text not null default 'pending' check (status in ('pending','approved','settled','reversed')),
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  unique(operation_type,operation_id)
);

create table if not exists public.charging_usdt_requests (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.charging_agencies(id) on delete restrict,
  agent_user_id uuid not null references public.profiles(id) on delete restrict,
  package_id uuid not null references public.charging_packages(id) on delete restrict,
  network text not null default 'TRC20',
  txid text not null unique,
  receipt_url text,
  usdt_amount numeric(18,2) not null,
  coin_amount bigint not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','credited','reversed')),
  reviewed_by uuid references auth.users(id) on delete set null,
  review_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create or replace function public.set_charging_system_enabled(_enabled boolean)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$
begin
  perform public.yamo_charging_require_admin();
  insert into public.charging_system_settings(id,system_enabled,updated_by,updated_at)
  values(true,_enabled,auth.uid(),now())
  on conflict(id) do update set system_enabled=excluded.system_enabled,updated_by=excluded.updated_by,updated_at=now();
end $$;

create or replace function public.set_charging_feature_enabled(_feature text,_enabled boolean)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$
begin
  perform public.yamo_charging_require_admin();
  if _feature not in ('coin_packages','pearl_buy','pearl_exchange','usdt_packages') then raise exception 'invalid_feature'; end if;
  update public.charging_system_settings set
    coin_packages_enabled=case when _feature='coin_packages' then _enabled else coin_packages_enabled end,
    pearl_buy_enabled=case when _feature='pearl_buy' then _enabled else pearl_buy_enabled end,
    pearl_exchange_enabled=case when _feature='pearl_exchange' then _enabled else pearl_exchange_enabled end,
    usdt_packages_enabled=case when _feature='usdt_packages' then _enabled else usdt_packages_enabled end,
    updated_by=auth.uid(),updated_at=now()
  where id=true;
end $$;

create or replace function public.set_charging_agency_commission(_agency_id uuid,_commission_rate numeric)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$
begin
  perform public.yamo_charging_require_admin();
  if _commission_rate < 0 or _commission_rate > 100 then raise exception 'invalid_commission_rate'; end if;
  update public.charging_agencies set commission_rate=_commission_rate,updated_by=auth.uid(),updated_at=now() where id=_agency_id;
  if not found then raise exception 'agency_not_found'; end if;
end $$;

create or replace function public.yamo_charging_effective_commission(_agency_id uuid,_agent_user_id uuid)
returns numeric language sql stable security definer set search_path='public','auth','pg_temp' as $$
  select coalesce(
    (select commission_rate from public.charging_agent_settings where user_id=_agent_user_id and agency_id=_agency_id),
    (select commission_rate from public.charging_agencies where id=_agency_id),
    (select default_agent_commission from public.charging_system_settings where id=true),0
  )::numeric;
$$;

create or replace function public.yamo_charging_operation_allowed(_agency_id uuid,_feature text)
returns boolean language sql stable security definer set search_path='public','auth','pg_temp' as $$
  select coalesce((select system_enabled and
    case _feature when 'coin_packages' then coin_packages_enabled when 'pearl_buy' then pearl_buy_enabled when 'pearl_exchange' then pearl_exchange_enabled when 'usdt_packages' then usdt_packages_enabled else false end
    from public.charging_system_settings where id=true),false)
    and coalesce((select status='active' from public.charging_agencies where id=_agency_id and deleted_at is null),false);
$$;

create or replace function public.admin_save_charging_package(
  _id uuid,_package_type text,_name text,_country_code text,_currency text,
  _money_amount numeric,_coin_amount bigint,_pearl_amount bigint,_usdt_amount numeric,
  _bonus_amount bigint,_fee_percentage numeric,_discount_percentage numeric,
  _agent_only boolean,_enabled boolean,_sort_order integer
) returns uuid language plpgsql security definer set search_path='public','auth','pg_temp' as $$
declare result_id uuid;
begin
  perform public.yamo_charging_require_admin();
  if _package_type not in ('coin','pearl_buy','pearl_exchange','usdt') then raise exception 'invalid_package_type'; end if;
  if length(trim(coalesce(_name,''))) < 2 then raise exception 'package_name_required'; end if;
  if coalesce(_fee_percentage,0) not between 0 and 100 or coalesce(_discount_percentage,0) not between 0 and 100 then raise exception 'invalid_percentage'; end if;
  if _id is null then
    insert into public.charging_packages(package_type,name,country_code,currency,money_amount,coin_amount,pearl_amount,usdt_amount,bonus_amount,fee_percentage,discount_percentage,agent_only,enabled,sort_order)
    values(_package_type,trim(_name),nullif(upper(trim(coalesce(_country_code,''))),''),upper(coalesce(nullif(trim(_currency),''),'USD')),greatest(coalesce(_money_amount,0),0),greatest(coalesce(_coin_amount,0),0),greatest(coalesce(_pearl_amount,0),0),greatest(coalesce(_usdt_amount,0),0),greatest(coalesce(_bonus_amount,0),0),coalesce(_fee_percentage,0),coalesce(_discount_percentage,0),coalesce(_agent_only,false),coalesce(_enabled,true),coalesce(_sort_order,0)) returning id into result_id;
  else
    update public.charging_packages set package_type=_package_type,name=trim(_name),country_code=nullif(upper(trim(coalesce(_country_code,''))),''),currency=upper(coalesce(nullif(trim(_currency),''),'USD')),money_amount=greatest(coalesce(_money_amount,0),0),coin_amount=greatest(coalesce(_coin_amount,0),0),pearl_amount=greatest(coalesce(_pearl_amount,0),0),usdt_amount=greatest(coalesce(_usdt_amount,0),0),bonus_amount=greatest(coalesce(_bonus_amount,0),0),fee_percentage=coalesce(_fee_percentage,0),discount_percentage=coalesce(_discount_percentage,0),agent_only=coalesce(_agent_only,false),enabled=coalesce(_enabled,true),sort_order=coalesce(_sort_order,0),updated_by=auth.uid(),updated_at=now() where id=_id returning id into result_id;
    if result_id is null then raise exception 'package_not_found'; end if;
  end if;
  return result_id;
end $$;

create or replace function public.admin_toggle_charging_package(_id uuid,_enabled boolean)
returns void language plpgsql security definer set search_path='public','auth','pg_temp' as $$
begin
  perform public.yamo_charging_require_admin();
  update public.charging_packages set enabled=_enabled,updated_by=auth.uid(),updated_at=now() where id=_id;
  if not found then raise exception 'package_not_found'; end if;
end $$;

alter table public.charging_system_settings enable row level security;
alter table public.charging_country_prices enable row level security;
alter table public.charging_packages enable row level security;
alter table public.charging_agent_profits enable row level security;
alter table public.charging_usdt_requests enable row level security;

do $$ declare tbl text; begin
  foreach tbl in array array['charging_system_settings','charging_country_prices','charging_packages','charging_agent_profits','charging_usdt_requests'] loop
    execute format('drop policy if exists charging_admin_read on public.%I',tbl);
    execute format('create policy charging_admin_read on public.%I for select to authenticated using (public.yamo_charging_admin_allowed())',tbl);
    execute format('grant select on public.%I to authenticated',tbl);
  end loop;
end $$;

grant execute on function public.set_charging_system_enabled(boolean) to authenticated;
grant execute on function public.set_charging_feature_enabled(text,boolean) to authenticated;
grant execute on function public.set_charging_agency_commission(uuid,numeric) to authenticated;
grant execute on function public.yamo_charging_effective_commission(uuid,uuid) to authenticated;
grant execute on function public.yamo_charging_operation_allowed(uuid,text) to authenticated;
grant execute on function public.admin_save_charging_package(uuid,text,text,text,text,numeric,bigint,bigint,numeric,bigint,numeric,numeric,boolean,boolean,integer) to authenticated;
grant execute on function public.admin_toggle_charging_package(uuid,boolean) to authenticated;

-- V234: one immutable activity ledger for every charging-related balance movement.
create table if not exists public.charging_activity_ledger (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid references public.charging_agencies(id) on delete set null,
  actor_user_id uuid references public.profiles(id) on delete set null,
  counterparty_user_id uuid references public.profiles(id) on delete set null,
  category text not null,
  direction text not null check (direction in ('in','out','internal','system')),
  asset text not null,
  amount numeric(20,2) not null default 0,
  status text not null default 'completed',
  source_table text not null,
  source_row_id text not null,
  entry_side text not null default 'main',
  reference text,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  recorded_at timestamptz not null default now(),
  unique(source_table,source_row_id,entry_side)
);
create index if not exists charging_activity_ledger_time_idx on public.charging_activity_ledger(occurred_at desc);
create index if not exists charging_activity_ledger_actor_idx on public.charging_activity_ledger(actor_user_id,occurred_at desc);
create index if not exists charging_activity_ledger_agency_idx on public.charging_activity_ledger(agency_id,occurred_at desc);

create or replace function public.yamo_capture_charging_coin_ledger()
returns trigger language plpgsql security definer set search_path='public','auth','pg_temp' as $$
begin
  insert into public.charging_activity_ledger(agency_id,actor_user_id,counterparty_user_id,category,direction,asset,amount,status,source_table,source_row_id,entry_side,reference,description,metadata,occurred_at)
  values(new.agency_id,new.agent_user_id,new.recipient_user_id,'coin_charge','out','coins',new.amount,new.status::text,'charging_coin_transfers',new.id::text,'agent',new.reference,'شحن كوينز من الوكيل إلى المستخدم',jsonb_build_object('sale_price',new.sale_price,'commission_amount',new.commission_amount,'currency',new.currency,'payment_method_id',new.payment_method_id),coalesce(new.completed_at,new.created_at))
  on conflict(source_table,source_row_id,entry_side) do update set amount=excluded.amount,status=excluded.status,metadata=excluded.metadata,occurred_at=excluded.occurred_at;
  return new;
end $$;

create or replace function public.yamo_capture_charging_pearl_ledger()
returns trigger language plpgsql security definer set search_path='public','auth','pg_temp' as $$
declare from_agency uuid; to_agency uuid; from_agent boolean; to_agent boolean;
begin
  select agency_id into from_agency from public.charging_agent_settings where user_id=new.from_user_id;
  select agency_id into to_agency from public.charging_agent_settings where user_id=new.to_user_id;
  from_agent := from_agency is not null; to_agent := to_agency is not null;
  insert into public.charging_activity_ledger(agency_id,actor_user_id,counterparty_user_id,category,direction,asset,amount,status,source_table,source_row_id,entry_side,reference,description,occurred_at)
  values(coalesce(from_agency,to_agency),new.from_user_id,new.to_user_id,case when from_agent and to_agent then 'agent_to_agent_pearl' when to_agent then 'user_to_agent_pearl' else 'pearl_transfer' end,'out','pearls',new.amount,new.status::text,'charging_pearl_transfers',new.id::text,'sender',new.reference,case when from_agent and to_agent then 'تحويل لؤلؤ من وكيل إلى وكيل' when to_agent then 'إرسال لؤلؤ من مستخدم إلى وكيل' else 'تحويل لؤلؤ' end,coalesce(new.completed_at,new.created_at))
  on conflict(source_table,source_row_id,entry_side) do update set amount=excluded.amount,status=excluded.status,description=excluded.description,occurred_at=excluded.occurred_at;
  return new;
end $$;

create or replace function public.yamo_capture_wallet_activity_ledger()
returns trigger language plpgsql security definer set search_path='public','auth','pg_temp' as $$
declare agency uuid; cat text; dir text;
begin
  select agency_id into agency from public.charging_agent_settings where user_id=new.user_id;
  cat := case
    when new.reason ilike '%game%' or new.reason ilike '%bet%' then 'game'
    when new.reason ilike '%withdraw%' then 'pearl_withdrawal'
    when new.reason ilike '%recharge%' or new.reason ilike '%charge%' then 'platform_charge'
    when new.reason ilike '%admin%' or new.reason ilike '%adjust%' then 'admin_funding'
    when new.reason ilike '%exchange%' then 'pearl_exchange'
    when new.reason ilike '%gift%' then 'gift'
    when new.reason ilike '%message%' then 'paid_message'
    when new.reason ilike '%call%' then 'paid_call'
    else 'wallet_activity' end;
  dir := case when new.amount>0 then 'in' when new.amount<0 then 'out' else 'system' end;
  insert into public.charging_activity_ledger(agency_id,actor_user_id,category,direction,asset,amount,status,source_table,source_row_id,entry_side,reference,description,metadata,occurred_at)
  values(agency,new.user_id,cat,dir,new.asset,abs(new.amount),'completed','yamo_wallet_events',new.id::text,'main',new.reference_id,new.reason,jsonb_build_object('signed_amount',new.amount,'reason',new.reason),new.created_at)
  on conflict(source_table,source_row_id,entry_side) do nothing;
  return new;
end $$;

drop trigger if exists charging_coin_activity_ledger_tr on public.charging_coin_transfers;
create trigger charging_coin_activity_ledger_tr after insert or update of status on public.charging_coin_transfers for each row execute function public.yamo_capture_charging_coin_ledger();
drop trigger if exists charging_pearl_activity_ledger_tr on public.charging_pearl_transfers;
create trigger charging_pearl_activity_ledger_tr after insert or update of status on public.charging_pearl_transfers for each row execute function public.yamo_capture_charging_pearl_ledger();
drop trigger if exists wallet_charging_activity_ledger_tr on public.yamo_wallet_events;
create trigger wallet_charging_activity_ledger_tr after insert on public.yamo_wallet_events for each row execute function public.yamo_capture_wallet_activity_ledger();

insert into public.charging_activity_ledger(agency_id,actor_user_id,counterparty_user_id,category,direction,asset,amount,status,source_table,source_row_id,entry_side,reference,description,metadata,occurred_at)
select t.agency_id,t.agent_user_id,t.recipient_user_id,'coin_charge','out','coins',t.amount,t.status::text,'charging_coin_transfers',t.id::text,'agent',t.reference,'شحن كوينز من الوكيل إلى المستخدم',jsonb_build_object('sale_price',t.sale_price,'commission_amount',t.commission_amount,'currency',t.currency),coalesce(t.completed_at,t.created_at) from public.charging_coin_transfers t
on conflict(source_table,source_row_id,entry_side) do nothing;

insert into public.charging_activity_ledger(agency_id,actor_user_id,category,direction,asset,amount,status,source_table,source_row_id,entry_side,reference,description,metadata,occurred_at)
select s.agency_id,e.user_id,case when e.reason ilike '%game%' or e.reason ilike '%bet%' then 'game' when e.reason ilike '%withdraw%' then 'pearl_withdrawal' when e.reason ilike '%recharge%' or e.reason ilike '%charge%' then 'platform_charge' when e.reason ilike '%admin%' or e.reason ilike '%adjust%' then 'admin_funding' when e.reason ilike '%exchange%' then 'pearl_exchange' else 'wallet_activity' end,case when e.amount>0 then 'in' when e.amount<0 then 'out' else 'system' end,e.asset,abs(e.amount),'completed','yamo_wallet_events',e.id::text,'main',e.reference_id,e.reason,jsonb_build_object('signed_amount',e.amount),e.created_at from public.yamo_wallet_events e left join public.charging_agent_settings s on s.user_id=e.user_id
on conflict(source_table,source_row_id,entry_side) do nothing;

alter table public.charging_activity_ledger enable row level security;
drop policy if exists charging_admin_read on public.charging_activity_ledger;
create policy charging_admin_read on public.charging_activity_ledger for select to authenticated using (public.yamo_charging_admin_allowed());
grant select on public.charging_activity_ledger to authenticated;

notify pgrst, 'reload schema';
commit;

select
  to_regclass('public.charging_agencies') is not null as agencies_ready,
  to_regclass('public.charging_coin_transfers') is not null as coin_transfers_ready,
  to_regclass('public.charging_activity_ledger') is not null as ledger_ready,
  to_regclass('public.charging_packages') is not null as packages_ready,
  to_regclass('charging_backup_v235.charging_agencies') is not null as backup_ready,
  to_regprocedure('public.create_charging_agency(text,text,text,text,uuid,uuid,text,text)') is not null as create_function_ready;
