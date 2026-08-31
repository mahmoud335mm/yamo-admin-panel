-- Yamo Admin V214 — recover message sections table and all related RPCs.

create table if not exists public.yamo_message_sections (
  section_key text primary key check(section_key~'^[a-z0-9_]{2,60}$'),
  label_ar text not null,
  label_en text not null,
  icon_key text not null default 'message',
  sort_order integer not null default 100,
  enabled boolean not null default true,
  system_section boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

insert into public.yamo_message_sections(
  section_key,label_ar,label_en,icon_key,sort_order,enabled,system_section
) values
  ('conversations','المحادثات','Conversations','message',10,true,true),
  ('active_users','النشطون','Active','users',20,true,true),
  ('suggestions','اقتراحات','Suggestions','sparkles',30,true,true),
  ('calls','المكالمات','Calls','phone',40,true,true),
  ('requests','الطلبات','Requests','inbox',50,true,true)
on conflict(section_key) do nothing;

alter table public.yamo_message_sections enable row level security;
revoke all on public.yamo_message_sections from public,anon,authenticated;

create or replace function public.admin_get_message_sections()
returns jsonb
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
declare result jsonb;
begin
  perform public.yamo_admin_require('messages.read');
  select coalesce(
    jsonb_agg(to_jsonb(s)-'updated_by' order by s.sort_order,s.created_at),
    '[]'::jsonb
  ) into result
  from public.yamo_message_sections s;
  return result;
end $$;

revoke all on function public.admin_get_message_sections() from public,anon;
grant execute on function public.admin_get_message_sections() to authenticated;

create or replace function public.admin_upsert_message_section(p_section jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
declare admin_id uuid;section_id text;result jsonb;
begin
  admin_id:=public.yamo_admin_require('messages.manage');
  section_id:=lower(trim(coalesce(p_section->>'section_key','')));
  if section_id!~'^[a-z0-9_]{2,60}$' then raise exception 'invalid_section_key'; end if;

  insert into public.yamo_message_sections(
    section_key,label_ar,label_en,icon_key,sort_order,enabled,system_section,updated_by
  ) values(
    section_id,
    left(trim(coalesce(p_section->>'label_ar','قسم')),80),
    left(trim(coalesce(p_section->>'label_en','Section')),80),
    left(coalesce(p_section->>'icon_key','message'),40),
    coalesce((p_section->>'sort_order')::integer,100),
    coalesce((p_section->>'enabled')::boolean,true),
    coalesce((p_section->>'system_section')::boolean,false),
    admin_id
  )
  on conflict(section_key) do update set
    label_ar=excluded.label_ar,
    label_en=excluded.label_en,
    icon_key=excluded.icon_key,
    sort_order=excluded.sort_order,
    enabled=excluded.enabled,
    updated_at=now(),
    updated_by=admin_id;

  select to_jsonb(s)-'updated_by' into result
  from public.yamo_message_sections s where s.section_key=section_id;

  perform public.yamo_admin_log(
    'messages.section_upsert','message_section',section_id,null,result,
    'إضافة أو تعديل قسم الرسائل'
  );
  return result;
end $$;

revoke all on function public.admin_upsert_message_section(jsonb) from public,anon;
grant execute on function public.admin_upsert_message_section(jsonb) to authenticated;

create or replace function public.admin_delete_message_section(p_section_key text)
returns boolean
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
declare deleted_count integer;
begin
  perform public.yamo_admin_require('messages.manage');
  delete from public.yamo_message_sections
  where section_key=p_section_key and system_section=false;
  get diagnostics deleted_count=row_count;

  if deleted_count>0 then
    perform public.yamo_admin_log(
      'messages.section_delete','message_section',p_section_key,null,null,
      'حذف قسم مخصص من الرسائل'
    );
  end if;
  return deleted_count>0;
end $$;

revoke all on function public.admin_delete_message_section(text) from public,anon;
grant execute on function public.admin_delete_message_section(text) to authenticated;

notify pgrst,'reload schema';

-- Verification: this must return three rows.
select p.proname,pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'admin_get_message_sections',
    'admin_upsert_message_section',
    'admin_delete_message_section'
  )
order by p.proname;
