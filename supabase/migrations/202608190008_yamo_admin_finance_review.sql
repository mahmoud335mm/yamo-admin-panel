-- Yamo Admin finance review using the unified RBAC system.
begin;

create or replace function public.admin_review_recharge(p_request_id uuid,p_action text,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare r public.yamo_recharge_requests%rowtype; before_row jsonb;
begin
  perform public.yamo_admin_require('recharge.review');
  select * into r from public.yamo_recharge_requests where id=p_request_id for update;
  if r.id is null then raise exception 'recharge_request_not_found'; end if;
  before_row:=to_jsonb(r);
  if p_action='complete' then
    if r.status='completed' then return true; end if;
    if r.status not in('submitted','reviewing') then raise exception 'invalid_recharge_state'; end if;
    update public.wallets set coins=coins+r.coins,updated_at=now() where user_id=r.user_id;
    insert into public.yamo_wallet_events(user_id,asset,amount,reason,reference_id)
    values(r.user_id,'coins',r.coins,'recharge_completed',r.id::text);
    update public.yamo_recharge_requests set status='completed',updated_at=now(),
      receiver_snapshot=receiver_snapshot||jsonb_build_object('admin_note',coalesce(p_note,''),'settled_by',auth.uid()::text)
      where id=r.id;
  elsif p_action='reject' then
    if r.status='rejected' then return true; end if;
    if r.status not in('submitted','reviewing') then raise exception 'invalid_recharge_state'; end if;
    update public.yamo_recharge_requests set status='rejected',updated_at=now(),
      receiver_snapshot=receiver_snapshot||jsonb_build_object('admin_note',coalesce(p_note,''),'settled_by',auth.uid()::text)
      where id=r.id;
  else raise exception 'invalid_action'; end if;
  perform public.yamo_admin_log('recharge.'||p_action,'yamo_recharge_requests',r.id::text,before_row,
    jsonb_build_object('status',p_action),p_note);
  return true;
end $$;
revoke all on function public.admin_review_recharge(uuid,text,text) from public,anon;
grant execute on function public.admin_review_recharge(uuid,text,text) to authenticated;

create or replace function public.admin_review_withdrawal(p_request_id uuid,p_action text,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare r public.yamo_withdraw_requests%rowtype; before_row jsonb;
begin
  perform public.yamo_admin_require('withdraw.review');
  select * into r from public.yamo_withdraw_requests where id=p_request_id for update;
  if r.id is null then raise exception 'withdraw_request_not_found'; end if;
  before_row:=to_jsonb(r);
  if p_action='complete' then
    if r.status='completed' then return true; end if;
    if r.status not in('submitted','reviewing') then raise exception 'invalid_withdraw_state'; end if;
    update public.yamo_withdraw_requests set status='completed',updated_at=now() where id=r.id;
  elsif p_action='reject' then
    if r.status='rejected' then return true; end if;
    if r.status not in('submitted','reviewing') then raise exception 'invalid_withdraw_state'; end if;
    update public.wallets set pearls=pearls+r.pearls,updated_at=now() where user_id=r.user_id;
    insert into public.yamo_wallet_events(user_id,asset,amount,reason,reference_id)
    values(r.user_id,'pearls',r.pearls,'withdrawal_refund',r.id::text);
    update public.yamo_withdraw_requests set status='rejected',updated_at=now() where id=r.id;
  else raise exception 'invalid_action'; end if;
  perform public.yamo_admin_log('withdrawal.'||p_action,'yamo_withdraw_requests',r.id::text,before_row,
    jsonb_build_object('status',p_action),p_note);
  return true;
end $$;
revoke all on function public.admin_review_withdrawal(uuid,text,text) from public,anon;
grant execute on function public.admin_review_withdrawal(uuid,text,text) to authenticated;

commit;
notify pgrst,'reload schema';
