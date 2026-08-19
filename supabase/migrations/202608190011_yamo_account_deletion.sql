-- Seven-day account deletion workflow. Final auth-user removal is deliberately
-- left to a scheduled service-role job after an approved request becomes due.
begin;

create table if not exists public.yamo_account_deletion_requests(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check(status in('pending','approved','rejected','cancelled','completed')),
  reason text,
  requested_at timestamptz not null default now(),
  eligible_at timestamptz not null default(now()+interval '7 days'),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id),
  admin_note text
);
create unique index if not exists yamo_account_deletion_one_open
on public.yamo_account_deletion_requests(user_id) where status in('pending','approved');
alter table public.yamo_account_deletion_requests enable row level security;
revoke all on public.yamo_account_deletion_requests from anon,authenticated;
grant select on public.yamo_account_deletion_requests to authenticated;
drop policy if exists yamo_deletion_read_own on public.yamo_account_deletion_requests;
create policy yamo_deletion_read_own on public.yamo_account_deletion_requests for select to authenticated
using(user_id=auth.uid() or public.yamo_admin_has_permission('users.moderate'));

create or replace function public.request_yamo_account_deletion(p_reason text default null)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare u uuid:=auth.uid(); w public.wallets%rowtype; id_out uuid;
begin
  if u is null then raise exception 'authentication_required'; end if;
  if not exists(select 1 from public.profiles where id=u and account_status='active') then raise exception 'account_not_active'; end if;
  select * into w from public.wallets where user_id=u;
  if coalesce(w.coins,0)<5000 or coalesce(w.pearls,0)<7000 then raise exception 'deletion_balance_conditions_not_met'; end if;
  insert into public.yamo_account_deletion_requests(user_id,reason) values(u,p_reason) returning id into id_out;
  update public.profiles set account_status='pending_deletion' where id=u;
  return id_out;
end $$;
revoke all on function public.request_yamo_account_deletion(text) from public,anon;
grant execute on function public.request_yamo_account_deletion(text) to authenticated;

create or replace view public.admin_account_deletion_requests as
select d.*,p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,w.coins,w.pearls
from public.yamo_account_deletion_requests d join public.profiles p on p.id=d.user_id
left join public.wallets w on w.user_id=d.user_id
where public.yamo_admin_has_permission('users.moderate');
revoke all on public.admin_account_deletion_requests from public,anon;
grant select on public.admin_account_deletion_requests to authenticated;

create or replace function public.admin_review_account_deletion(p_id uuid,p_action text,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare r public.yamo_account_deletion_requests%rowtype;
begin
  perform public.yamo_admin_require('users.moderate');
  if p_action not in('approve','reject') then raise exception 'invalid_action'; end if;
  select * into r from public.yamo_account_deletion_requests where id=p_id for update;
  if r.id is null or r.status<>'pending' then raise exception 'request_not_pending'; end if;
  update public.yamo_account_deletion_requests set status=case when p_action='approve' then 'approved' else 'rejected' end,
    resolved_at=now(),resolved_by=auth.uid(),admin_note=p_note where id=p_id;
  if p_action='reject' then update public.profiles set account_status='active' where id=r.user_id; end if;
  perform public.yamo_admin_log('account_deletion.'||p_action,'yamo_account_deletion_requests',p_id::text,to_jsonb(r),null,p_note);
  return true;
end $$;
revoke all on function public.admin_review_account_deletion(uuid,text,text) from public,anon;
grant execute on function public.admin_review_account_deletion(uuid,text,text) to authenticated;

commit;
notify pgrst,'reload schema';
