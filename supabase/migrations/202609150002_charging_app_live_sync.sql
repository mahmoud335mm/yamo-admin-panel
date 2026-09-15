-- Yamo Chat V238 - App bridge for the charging-agency control panel.
begin;

create or replace function public.get_yamo_charging_app_config(p_country_code text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path='public','auth','pg_temp'
as $$
declare
  uid uuid := auth.uid();
  country_code text := upper(nullif(trim(coalesce(p_country_code,'')),''));
  settings_row public.charging_system_settings;
  member_agency uuid;
  member_status text;
begin
  if uid is null then raise exception 'authentication_required'; end if;
  select * into settings_row from public.charging_system_settings where id=true;
  select agency_id,status::text into member_agency,member_status
  from public.charging_agent_settings where user_id=uid;

  return jsonb_build_object(
    'system_enabled',coalesce(settings_row.system_enabled,false),
    'coin_packages_enabled',coalesce(settings_row.coin_packages_enabled,false),
    'pearl_buy_enabled',coalesce(settings_row.pearl_buy_enabled,false),
    'pearl_exchange_enabled',coalesce(settings_row.pearl_exchange_enabled,false),
    'usdt_packages_enabled',coalesce(settings_row.usdt_packages_enabled,false),
    'is_charging_agent',member_agency is not null and member_status='active',
    'agency_id',member_agency,
    'agency_active',coalesce((select status='active' from public.charging_agencies where id=member_agency and deleted_at is null),false),
    'refresh_seconds',15,
    'packages',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'type',p.package_type,'name',p.name,'country_code',p.country_code,
        'currency',p.currency,'money_amount',p.money_amount,'coin_amount',p.coin_amount,
        'pearl_amount',p.pearl_amount,'usdt_amount',p.usdt_amount,'bonus_amount',p.bonus_amount,
        'fee_percentage',p.fee_percentage,'discount_percentage',p.discount_percentage,
        'agent_only',p.agent_only,'sort_order',p.sort_order
      ) order by p.sort_order,p.money_amount)
      from public.charging_packages p
      where p.enabled=true
        and (p.starts_at is null or p.starts_at<=now())
        and (p.ends_at is null or p.ends_at>now())
        and (p.country_code is null or p.country_code=country_code)
        and (not p.agent_only or (member_agency is not null and member_status='active'))
    ),'[]'::jsonb)
  );
end $$;

revoke all on function public.get_yamo_charging_app_config(text) from public;
grant execute on function public.get_yamo_charging_app_config(text) to authenticated;
notify pgrst,'reload schema';
commit;

select to_regprocedure('public.get_yamo_charging_app_config(text)') is not null as app_sync_ready;
