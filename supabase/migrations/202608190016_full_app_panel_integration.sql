-- Final app/panel contract bridge: reversible seven-day deletion and schema cache refresh.
begin;

create or replace function public.cancel_yamo_account_deletion()
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare u uuid:=auth.uid(); changed boolean:=false;
begin
  if u is null then raise exception 'authentication_required'; end if;
  update public.yamo_account_deletion_requests
  set status='cancelled',resolved_at=now()
  where user_id=u and status in('pending','approved');
  changed:=found;
  if changed then
    update public.profiles set account_status='active'
    where id=u and account_status='pending_deletion';
  end if;
  return changed;
end $$;
revoke all on function public.cancel_yamo_account_deletion() from public,anon;
grant execute on function public.cancel_yamo_account_deletion() to authenticated;

commit;
notify pgrst,'reload schema';
