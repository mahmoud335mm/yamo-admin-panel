# Yamo Chat Admin Console — لوحة تحكم يامو شات

## What's shipped (Phases 0–2)

### Phase 0 — Documentation
See `/docs`: architecture, ERD, roles/permissions, navigation map, feature flags, API contract, implementation phases.

### Phase 1 — Foundation
- **Auth**: email/password + Google OAuth via Lovable Cloud broker. First signup is auto-promoted to `super_admin` (bootstrap).
- **RBAC tables**: `admin_users`, `roles`, `permissions`, `role_permissions`, `admin_role_assignments`.
- **9 built-in roles** and ~46 permission keys seeded.
- **RLS**: every table locked, opened only via `has_permission(uid, key)` / `has_role(uid, role)`.
- **Audit**: `audit_logs` (append-only), `logAudit()` helper on every admin action.
- **Shell**: RTL layout, collapsible right-side Sidebar, TopBar (Global Search ⌘K, Notifications, Theme toggle, User menu), Breadcrumbs, Dark mode.

### Phase 2 — Users + Wallet Ledger
- **Tables**: `profiles`, `user_devices`, `user_sessions`, `wallets`, `wallet_ledger` (append-only), `transactions`, `user_penalties`.
- **RLS** scoped to `users.read`, `users.write`, `users.ban`, `users.verify`, `economy.read`, `economy.write`.
- **UI**: `/users` list with search by UID/username/phone + status filter; `/users/$id` full profile with tabs (overview · wallet · ledger · transactions · devices · penalties) and actions (ban/suspend/reactivate/verify) writing to audit log.
- **Demo seed**: 6 end-user profiles marked `is_demo = true` with wallets, ledger rows, and transactions. Delete anytime with:
  ```sql
  DELETE FROM public.profiles WHERE is_demo = true;
  ```

## Getting started
1. Visit `/auth`, create the first account (becomes Super Admin).
2. Land on `/dashboard`.
3. Manage admins in **مسؤولو اللوحة**, review actions in **سجل العمليات**.

## Environment
- `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY` — client (safe).
- `SUPABASE_SERVICE_ROLE_KEY` — server-only, never in frontend.

## Next phases
See `docs/07-implementation-phases.md`: Agencies/Hosts/BD (3) → Rooms/Comm (4) → Gifts/Store (5) → Recharge/Withdrawals (6) → Banners/Events/Notifs (7) → Reports/Moderation/Settings/RC (8) → Android API (9) → AI Operator (10) → QA (11).
