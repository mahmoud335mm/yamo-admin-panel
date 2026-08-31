-- Minimal and safe recovery for admin_get_message_settings().
-- The yamo_message_settings table must already exist.

create or replace function public.admin_get_message_settings()
returns jsonb
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
declare result jsonb;
begin
  perform public.yamo_admin_require('messages.read');

  select to_jsonb(s)-'singleton'-'updated_by'
  into result
  from public.yamo_message_settings s
  where s.singleton=true;

  return coalesce(result,'{}'::jsonb);
end $$;

revoke all on function public.admin_get_message_settings() from public,anon;
grant execute on function public.admin_get_message_settings() to authenticated;

notify pgrst,'reload schema';

-- Verification: exactly one row must appear.
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='admin_get_message_settings';
