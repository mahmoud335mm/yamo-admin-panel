-- ============================================================================
-- Yamo Chat — FIRST SUPER ADMIN BOOTSTRAP
--
-- ⚠️ RUN THIS MANUALLY in the Supabase SQL Editor (service role).
-- It is NOT part of the migration chain and was NOT executed for you —
-- I have no database access from the authoring environment.
--
-- WHY THIS IS MANUAL:
-- yamo_admin_users starts empty, and admin_assign_yamo_role() requires the
-- 'admins.manage' permission. That is a deliberate chicken-and-egg: there is
-- no RPC anywhere that lets an account promote itself, because such an RPC
-- would be a backdoor for every user. The only way in is here, with the
-- service role, by a human who already controls the database.
--
-- PREREQUISITES:
--   1. RUN_THIS_SQL_V120.sql has been applied (creates the RBAC tables).
--   2. The person has already signed up in the app / Supabase Auth, so a
--      row exists in auth.users for their email.
-- ============================================================================

-- STEP 1 — find the auth user id. Replace the email.
-- select id, email from auth.users where email = 'you@example.com';

-- STEP 2 — promote them. Replace the email in BOTH places below, then run.
do $$
declare
  v_email text := 'REPLACE_WITH_YOUR_EMAIL@example.com';
  v_user_id uuid;
begin
  select id into v_user_id from auth.users where email = v_email;
  if v_user_id is null then
    raise exception 'No auth.users row for %. Sign up in the app first.', v_email;
  end if;

  insert into public.yamo_admin_users(user_id, email, full_name, is_active)
  values (v_user_id, v_email, 'Super Admin', true)
  on conflict (user_id) do update set is_active = true, email = excluded.email;

  insert into public.yamo_admin_role_assignments(user_id, role, assigned_by)
  values (v_user_id, 'super_admin', v_user_id)
  on conflict do nothing;

  insert into public.yamo_admin_audit_logs(actor_id, actor_email, action, entity_type, entity_id, note)
  values (v_user_id, v_email, 'rbac.bootstrap', 'yamo_admin_users', v_user_id::text,
    'First super_admin created manually via bootstrap SQL');

  raise notice 'super_admin granted to % (%)', v_email, v_user_id;
end $$;

-- STEP 3 — verify. Should list super_admin and every permission.
-- select * from public.get_yamo_admin_me();

-- ============================================================================
-- AFTER THIS: create all further admins from the panel (Admins page), which
-- goes through admin_assign_yamo_role() and is fully audited. Do not reuse
-- this script for routine admin creation.
--
-- SAFETY NOTE: admin_assign_yamo_role() refuses to remove the last
-- super_admin, so you cannot lock yourself out by revoking your own role.
-- ============================================================================
