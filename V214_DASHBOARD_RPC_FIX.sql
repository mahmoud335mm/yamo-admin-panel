-- Yamo Admin V214 — recover the missing message dashboard RPC.
-- Requires the V211 table public.yamo_message_archive.

create or replace function public.admin_get_message_dashboard(p_days integer default 30)
returns jsonb
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
declare
  days_count integer:=least(365,greatest(1,coalesce(p_days,30)));
  result jsonb;
begin
  perform public.yamo_admin_require('messages.read');

  with base as (
    select a.*
    from public.yamo_message_archive a
    where a.sent_at>=now()-make_interval(days=>days_count)
  ), totals as (
    select
      count(*) as total_messages,
      count(*) filter(where sent_at>=current_date) as messages_today,
      count(*) filter(where kind in ('text','message')) as text_count,
      count(*) filter(where kind='image') as image_count,
      count(*) filter(where kind='voice') as voice_count,
      count(*) filter(where kind in ('video','video_message')) as video_count,
      count(*) filter(where read_at is not null) as read_count,
      coalesce(sum(earning_pearls),0) as earnings_paid
    from base
  ), active_profiles as (
    select distinct sender_id as profile_id from base where sent_at>=now()-interval '15 minutes'
    union
    select distinct receiver_id as profile_id from base where sent_at>=now()-interval '15 minutes'
  ), active_stats as (
    select
      count(*) as active_users,
      count(*) filter(where lower(coalesce(p.gender,''))='male') as active_males,
      count(*) filter(where lower(coalesce(p.gender,''))='female') as active_females
    from active_profiles a
    join public.profiles p on p.id=a.profile_id
  ), chart_data as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'label',to_char(message_day,'DD/MM'),
          'sent',sent_count,
          'replies',reply_count
        ) order by message_day
      ),
      '[]'::jsonb
    ) as chart
    from (
      select
        date_trunc('day',sent_at) as message_day,
        count(*) as sent_count,
        count(*) filter(where read_at is not null) as reply_count
      from base
      group by date_trunc('day',sent_at)
      order by message_day desc
      limit 30
    ) x
  )
  select jsonb_build_object(
    'total_messages',t.total_messages,
    'messages_today',t.messages_today,
    'active_users',a.active_users,
    'active_males',a.active_males,
    'active_females',a.active_females,
    'response_rate',case when t.total_messages=0 then 0 else round(t.read_count*100.0/t.total_messages,1) end,
    'text_percent',case when t.total_messages=0 then 0 else round(t.text_count*100.0/t.total_messages,1) end,
    'image_percent',case when t.total_messages=0 then 0 else round(t.image_count*100.0/t.total_messages,1) end,
    'voice_percent',case when t.total_messages=0 then 0 else round(t.voice_count*100.0/t.total_messages,1) end,
    'video_percent',case when t.total_messages=0 then 0 else round(t.video_count*100.0/t.total_messages,1) end,
    'coins_spent',0,
    'earnings_paid',t.earnings_paid,
    'chart',c.chart
  ) into result
  from totals t
  cross join active_stats a
  cross join chart_data c;

  return coalesce(result,'{}'::jsonb);
end $$;

revoke all on function public.admin_get_message_dashboard(integer) from public,anon;
grant execute on function public.admin_get_message_dashboard(integer) to authenticated;

notify pgrst,'reload schema';

-- Verification: this must return one row with argument "p_days integer".
select p.proname,pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='admin_get_message_dashboard';
