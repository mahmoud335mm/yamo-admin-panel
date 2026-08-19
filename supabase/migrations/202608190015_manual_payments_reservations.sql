-- Manual recharge/withdrawal production workflow.
-- New withdrawals reserve pearls without mutating the wallet until settlement.
begin;

alter table public.yamo_recharge_requests
  add column if not exists sender_name text,
  add column if not exists transaction_reference text,
  add column if not exists reviewed_by uuid,
  add column if not exists reviewed_at timestamptz,
  add column if not exists admin_note text;

alter table public.yamo_withdraw_requests
  add column if not exists payout_reference text,
  add column if not exists payout_proof_path text,
  add column if not exists reviewed_by uuid,
  add column if not exists reviewed_at timestamptz,
  add column if not exists admin_note text;

create table if not exists public.yamo_withdrawal_reservations (
  request_id uuid primary key references public.yamo_withdraw_requests(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount bigint not null check (amount > 0),
  state text not null check (state in ('reserved','settled','released','legacy_debited')),
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  released_at timestamptz
);
create index if not exists yamo_withdrawal_reservations_user_state_idx
  on public.yamo_withdrawal_reservations(user_id,state);

-- Requests created by the old RPC were already deducted. Mark them so the
-- new reviewer can finish/reject them without double debit or double refund.
insert into public.yamo_withdrawal_reservations(request_id,user_id,amount,state,created_at)
select w.id,w.user_id,w.pearls+w.fee_pearls,'legacy_debited',w.created_at
from public.yamo_withdraw_requests w
where w.status in ('submitted','reviewing')
on conflict(request_id) do nothing;

create or replace function public.get_yamo_available_pearls()
returns table(total_pearls bigint,reserved_pearls bigint,available_pearls bigint)
language sql stable security definer set search_path=public,auth,pg_temp as $$
  select coalesce(w.pearls,0),
    coalesce((select sum(r.amount) from public.yamo_withdrawal_reservations r
      where r.user_id=auth.uid() and r.state='reserved'),0)::bigint,
    greatest(coalesce(w.pearls,0)-coalesce((select sum(r.amount)
      from public.yamo_withdrawal_reservations r
      where r.user_id=auth.uid() and r.state='reserved'),0),0)::bigint
  from public.wallets w where w.user_id=auth.uid();
$$;

drop function if exists public.start_yamo_recharge(uuid,uuid,text,uuid);
drop function if exists public.start_yamo_recharge(uuid,uuid,text,text,uuid);
create function public.start_yamo_recharge(
  p_package_id uuid,p_payment_method_id uuid,p_sender_account text,
  p_sender_name text,p_idempotency_key uuid
) returns public.yamo_recharge_requests language plpgsql security definer
set search_path=public,auth,pg_temp as $$
declare v_user uuid:=auth.uid(); v_pkg public.yamo_recharge_packages%rowtype;
  v_method public.yamo_payment_methods%rowtype; v_row public.yamo_recharge_requests%rowtype;
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  if length(trim(coalesce(p_sender_account,''))) < 3 then raise exception 'invalid_sender_account'; end if;
  if length(trim(coalesce(p_sender_name,''))) < 2 then raise exception 'invalid_sender_name'; end if;
  select * into v_row from public.yamo_recharge_requests where user_id=v_user and idempotency_key=p_idempotency_key;
  if found then return v_row; end if;
  select * into strict v_pkg from public.yamo_recharge_packages where id=p_package_id and enabled;
  select * into strict v_method from public.yamo_payment_methods where id=p_payment_method_id and enabled
    and flow in ('recharge','both') and country_code in (v_pkg.country_code,'ALL');
  insert into public.yamo_recharge_requests(reference,user_id,package_id,payment_method_id,sender_account,
    sender_name,coins,paid_amount,currency_code,receiver_snapshot,idempotency_key)
  values('RC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),v_user,v_pkg.id,v_method.id,
    trim(p_sender_account),trim(p_sender_name),v_pkg.coins+v_pkg.bonus_coins,v_pkg.price,v_pkg.currency_code,
    jsonb_build_object('label',coalesce(v_method.receiver_label,v_method.display_name),
      'value',coalesce(v_method.receiver_value,''),'instructions',v_method.instructions),p_idempotency_key)
  returning * into v_row;
  return v_row;
end $$;

drop function if exists public.submit_yamo_recharge_proof(uuid,text);
drop function if exists public.submit_yamo_recharge_proof(uuid,text,text);
create function public.submit_yamo_recharge_proof(
  p_request_id uuid,p_proof_path text,p_transaction_reference text default null
) returns public.yamo_recharge_requests language plpgsql security definer
set search_path=public,auth,pg_temp as $$
declare v_row public.yamo_recharge_requests%rowtype;
begin
  if length(trim(coalesce(p_proof_path,'')))<3 then raise exception 'proof_required'; end if;
  update public.yamo_recharge_requests set proof_path=trim(p_proof_path),
    transaction_reference=nullif(trim(coalesce(p_transaction_reference,'')),''),status='submitted',updated_at=now()
  where id=p_request_id and user_id=auth.uid() and status='awaiting_payment' and expires_at>now()
  returning * into v_row;
  if v_row.id is null then raise exception 'invalid_or_expired_recharge_request'; end if;
  return v_row;
end $$;

drop function if exists public.start_yamo_withdrawal(uuid,uuid,jsonb,uuid);
create function public.start_yamo_withdrawal(
  p_package_id uuid,p_payment_method_id uuid,p_payout_details jsonb,p_idempotency_key uuid
) returns public.yamo_withdraw_requests language plpgsql security definer
set search_path=public,auth,pg_temp as $$
declare v_user uuid:=auth.uid(); v_pkg public.yamo_withdraw_packages%rowtype;
  v_method public.yamo_payment_methods%rowtype; v_row public.yamo_withdraw_requests%rowtype;
  v_wallet public.wallets%rowtype; v_reserved bigint; v_required bigint;
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  if length(trim(coalesce(p_payout_details->>'name','')))<2 then raise exception 'payout_name_required'; end if;
  if length(trim(coalesce(p_payout_details->>'account','')))<3 then raise exception 'payout_account_required'; end if;
  select * into v_row from public.yamo_withdraw_requests where user_id=v_user and idempotency_key=p_idempotency_key;
  if found then return v_row; end if;
  select * into strict v_pkg from public.yamo_withdraw_packages where id=p_package_id and enabled;
  select * into strict v_method from public.yamo_payment_methods where id=p_payment_method_id and enabled
    and flow in ('withdrawal','both') and country_code in (v_pkg.country_code,'ALL');
  select * into v_wallet from public.wallets where user_id=v_user for update;
  if v_wallet.user_id is null then raise exception 'wallet_not_found'; end if;
  select coalesce(sum(amount),0) into v_reserved from public.yamo_withdrawal_reservations
    where user_id=v_user and state='reserved';
  v_required:=v_pkg.pearls+v_pkg.fee_pearls;
  if v_wallet.pearls-v_reserved<v_required then raise exception 'insufficient_available_pearls'; end if;
  insert into public.yamo_withdraw_requests(reference,user_id,package_id,payment_method_id,pearls,fee_pearls,
    payout_amount,currency_code,payout_details,idempotency_key)
  values('WD-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),v_user,v_pkg.id,v_method.id,
    v_pkg.pearls,v_pkg.fee_pearls,v_pkg.payout_amount,v_pkg.currency_code,
    jsonb_build_object('name',trim(p_payout_details->>'name'),'account',trim(p_payout_details->>'account')),
    p_idempotency_key) returning * into v_row;
  insert into public.yamo_withdrawal_reservations(request_id,user_id,amount,state)
    values(v_row.id,v_user,v_required,'reserved');
  return v_row;
end $$;

drop function if exists public.admin_review_recharge(uuid,text,text);
drop function if exists public.admin_review_recharge(uuid,text,text,text);
create function public.admin_review_recharge(
  p_request_id uuid,p_action text,p_note text default null,p_transaction_reference text default null
) returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare r public.yamo_recharge_requests%rowtype; before_row jsonb;
begin
  perform public.yamo_admin_require('recharge.review');
  select * into r from public.yamo_recharge_requests where id=p_request_id for update;
  if r.id is null then raise exception 'recharge_request_not_found'; end if;
  before_row:=to_jsonb(r);
  if p_action='review' then
    if r.status='submitted' then update public.yamo_recharge_requests set status='reviewing',reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=r.id; end if;
  elsif p_action='complete' then
    if r.status='completed' then return true; end if;
    if r.status not in('submitted','reviewing') then raise exception 'invalid_recharge_state'; end if;
    update public.wallets set coins=coins+r.coins,updated_at=now() where user_id=r.user_id;
    if not found then raise exception 'wallet_not_found'; end if;
    insert into public.yamo_wallet_events(user_id,asset,amount,reason,reference_id)
      values(r.user_id,'coins',r.coins,'recharge_completed',r.id::text);
    update public.yamo_recharge_requests set status='completed',reviewed_by=auth.uid(),reviewed_at=now(),
      admin_note=p_note,transaction_reference=coalesce(nullif(trim(coalesce(p_transaction_reference,'')),''),transaction_reference),updated_at=now() where id=r.id;
  elsif p_action in('reject','request_proof') then
    if r.status not in('submitted','reviewing') then raise exception 'invalid_recharge_state'; end if;
    update public.yamo_recharge_requests set status=case when p_action='reject' then 'rejected' else 'awaiting_payment' end,
      proof_path=case when p_action='request_proof' then null else proof_path end,
      admin_note=p_note,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now(),
      expires_at=case when p_action='request_proof' then now()+interval '30 minutes' else expires_at end where id=r.id;
  else raise exception 'invalid_action'; end if;
  perform public.yamo_admin_log('recharge.'||p_action,'yamo_recharge_requests',r.id::text,before_row,jsonb_build_object('status',p_action),p_note);
  return true;
end $$;

drop function if exists public.admin_review_withdrawal(uuid,text,text);
drop function if exists public.admin_review_withdrawal(uuid,text,text,text,text);
create function public.admin_review_withdrawal(
  p_request_id uuid,p_action text,p_note text default null,
  p_payout_reference text default null,p_payout_proof_path text default null
) returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare r public.yamo_withdraw_requests%rowtype; h public.yamo_withdrawal_reservations%rowtype; before_row jsonb;
begin
  perform public.yamo_admin_require('withdraw.review');
  select * into r from public.yamo_withdraw_requests where id=p_request_id for update;
  if r.id is null then raise exception 'withdraw_request_not_found'; end if;
  before_row:=to_jsonb(r);
  select * into h from public.yamo_withdrawal_reservations where request_id=r.id for update;
  if h.request_id is null then raise exception 'withdrawal_reservation_not_found'; end if;
  if p_action='review' then
    if r.status='submitted' then update public.yamo_withdraw_requests set status='reviewing',reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=r.id; end if;
  elsif p_action='complete' then
    if r.status='completed' then return true; end if;
    if r.status not in('submitted','reviewing') then raise exception 'invalid_withdraw_state'; end if;
    if length(trim(coalesce(p_payout_reference,'')))<3 then raise exception 'payout_reference_required'; end if;
    if h.state='reserved' then
      update public.wallets set pearls=pearls-h.amount,updated_at=now() where user_id=r.user_id and pearls>=h.amount;
      if not found then raise exception 'insufficient_pearls_at_settlement'; end if;
      insert into public.yamo_wallet_events(user_id,asset,amount,reason,reference_id)
        values(r.user_id,'pearls',-h.amount,'withdrawal_completed',r.id::text);
      update public.yamo_withdrawal_reservations set state='settled',settled_at=now() where request_id=r.id;
    elsif h.state='legacy_debited' then
      update public.yamo_withdrawal_reservations set state='settled',settled_at=now() where request_id=r.id;
    else raise exception 'withdrawal_reservation_not_active'; end if;
    update public.yamo_withdraw_requests set status='completed',payout_reference=trim(p_payout_reference),
      payout_proof_path=nullif(trim(coalesce(p_payout_proof_path,'')),''),admin_note=p_note,
      reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=r.id;
  elsif p_action='reject' then
    if r.status='rejected' then return true; end if;
    if r.status not in('submitted','reviewing') then raise exception 'invalid_withdraw_state'; end if;
    if h.state='legacy_debited' then
      update public.wallets set pearls=pearls+h.amount,updated_at=now() where user_id=r.user_id;
      insert into public.yamo_wallet_events(user_id,asset,amount,reason,reference_id)
        values(r.user_id,'pearls',h.amount,'withdrawal_refund',r.id::text);
    elsif h.state<>'reserved' then raise exception 'withdrawal_reservation_not_active'; end if;
    update public.yamo_withdrawal_reservations set state='released',released_at=now() where request_id=r.id;
    update public.yamo_withdraw_requests set status='rejected',admin_note=p_note,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=r.id;
  else raise exception 'invalid_action'; end if;
  perform public.yamo_admin_log('withdrawal.'||p_action,'yamo_withdraw_requests',r.id::text,before_row,jsonb_build_object('status',p_action),p_note);
  return true;
end $$;

drop view if exists public.admin_recharge_requests;
create view public.admin_recharge_requests with (security_invoker=true) as
select r.id,r.reference,r.user_id,p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,
  r.sender_name,r.sender_account,r.coins,r.paid_amount,r.currency_code,r.status,r.transaction_reference,
  r.proof_path,r.expires_at,r.admin_note,r.reviewed_at,r.created_at,r.updated_at,m.display_name method_name
from public.yamo_recharge_requests r join public.profiles p on p.id=r.user_id
left join public.yamo_payment_methods m on m.id=r.payment_method_id
where public.yamo_admin_has_permission('recharge.review') or public.yamo_admin_has_permission('economy.read');

drop view if exists public.admin_withdrawal_requests;
create view public.admin_withdrawal_requests with (security_invoker=true) as
select w.id,w.reference,w.user_id,p.legacy_id,coalesce(p.display_name,p.legacy_id) display_name,
  w.pearls,w.fee_pearls,w.payout_amount,w.currency_code,w.status,w.payout_details,
  h.amount reserved_pearls,h.state reservation_state,w.payout_reference,w.payout_proof_path,
  w.admin_note,w.reviewed_at,w.created_at,w.updated_at,m.display_name method_name
from public.yamo_withdraw_requests w join public.profiles p on p.id=w.user_id
left join public.yamo_withdrawal_reservations h on h.request_id=w.id
left join public.yamo_payment_methods m on m.id=w.payment_method_id
where public.yamo_admin_has_permission('withdraw.review') or public.yamo_admin_has_permission('economy.read');

alter table public.yamo_withdrawal_reservations enable row level security;
revoke all on public.yamo_withdrawal_reservations from public,anon,authenticated;
revoke all on function public.get_yamo_available_pearls() from public,anon;
grant execute on function public.get_yamo_available_pearls() to authenticated;
revoke all on function public.start_yamo_recharge(uuid,uuid,text,text,uuid) from public,anon;
grant execute on function public.start_yamo_recharge(uuid,uuid,text,text,uuid) to authenticated;
revoke all on function public.submit_yamo_recharge_proof(uuid,text,text) from public,anon;
grant execute on function public.submit_yamo_recharge_proof(uuid,text,text) to authenticated;
revoke all on function public.start_yamo_withdrawal(uuid,uuid,jsonb,uuid) from public,anon;
grant execute on function public.start_yamo_withdrawal(uuid,uuid,jsonb,uuid) to authenticated;
revoke all on function public.admin_review_recharge(uuid,text,text,text) from public,anon;
grant execute on function public.admin_review_recharge(uuid,text,text,text) to authenticated;
revoke all on function public.admin_review_withdrawal(uuid,text,text,text,text) from public,anon;
grant execute on function public.admin_review_withdrawal(uuid,text,text,text,text) to authenticated;

commit;
notify pgrst,'reload schema';
