-- Yamo Admin Console bridge. Apply after V120, V121 and V122.
-- Idempotent, uses the same yamo_admin_* RBAC as the Android backend.

create or replace function public.preview_admin_invite(_token text)
returns table(email text, role text, status text)
language sql security definer set search_path = public, auth
as $$
  select i.email, i.role,
    case when i.status = 'pending' and i.expires_at < now() then 'expired' else i.status end
  from public.yamo_admin_invites i
  where i.token::text = _token
  limit 1
$$;
revoke all on function public.preview_admin_invite(text) from public;
grant execute on function public.preview_admin_invite(text) to anon, authenticated;

create or replace function public.accept_admin_invite(_token text)
returns void language plpgsql security definer set search_path = public, auth
as $$
declare v_invite public.yamo_admin_invites%rowtype; v_email text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_invite from public.yamo_admin_invites where token::text = _token for update;
  if v_invite.id is null then raise exception 'INVITE_INVALID'; end if;
  if v_invite.status <> 'pending' then raise exception 'INVITE_ALREADY_USED'; end if;
  if v_invite.expires_at < now() then
    update public.yamo_admin_invites set status='expired' where id=v_invite.id;
    raise exception 'INVITE_EXPIRED';
  end if;
  select lower(email) into v_email from auth.users where id=auth.uid();
  if v_email is distinct from lower(v_invite.email) then raise exception 'EMAIL_MISMATCH'; end if;
  insert into public.yamo_admin_users(user_id,email,full_name,is_active)
  select id,email,coalesce(raw_user_meta_data->>'full_name',email),true from auth.users where id=auth.uid()
  on conflict(user_id) do update set email=excluded.email,is_active=true;
  insert into public.yamo_admin_role_assignments(user_id,role,assigned_by)
  values(auth.uid(),v_invite.role,v_invite.created_by) on conflict do nothing;
  update public.yamo_admin_invites set status='accepted' where id=v_invite.id;
  perform public.yamo_admin_log('admin.invite.accept','yamo_admin_users',auth.uid()::text,null,jsonb_build_object('role',v_invite.role),null);
end $$;
revoke all on function public.accept_admin_invite(text) from public, anon;
grant execute on function public.accept_admin_invite(text) to authenticated;

create or replace function public.admin_create_invite(_email text, _role text, _days integer default 7)
returns uuid language plpgsql security definer set search_path = public, auth
as $$
declare v_id uuid; v_admin uuid;
begin
  v_admin := public.yamo_admin_require('admins.manage');
  if not exists(select 1 from public.yamo_admin_roles where role=_role) then raise exception 'INVALID_ROLE'; end if;
  insert into public.yamo_admin_invites(email,role,created_by,expires_at)
  values(lower(trim(_email)),_role,v_admin,now()+make_interval(days=>greatest(1,least(_days,30)))) returning id into v_id;
  perform public.yamo_admin_log('admin.invite.create','yamo_admin_invites',v_id::text,null,jsonb_build_object('email',lower(trim(_email)),'role',_role),null);
  return v_id;
end $$;
revoke all on function public.admin_create_invite(text,text,integer) from public, anon;
grant execute on function public.admin_create_invite(text,text,integer) to authenticated;

create or replace function public.admin_revoke_invite(_invite_id uuid)
returns void language plpgsql security definer set search_path=public,auth
as $$
begin
  perform public.yamo_admin_require('admins.manage');
  update public.yamo_admin_invites set status='revoked' where id=_invite_id and status='pending';
  perform public.yamo_admin_log('admin.invite.revoke','yamo_admin_invites',_invite_id::text,null,null,null);
end $$;
revoke all on function public.admin_revoke_invite(uuid) from public, anon;
grant execute on function public.admin_revoke_invite(uuid) to authenticated;

-- Direct table access remains read-only and permission scoped.
drop policy if exists yamo_admin_invites_read on public.yamo_admin_invites;
create policy yamo_admin_invites_read on public.yamo_admin_invites for select to authenticated
using (public.yamo_admin_has_permission('admins.manage'));
grant select on public.yamo_admin_invites to authenticated;
