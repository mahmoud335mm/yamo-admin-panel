# 07 — Implementation Phases / مراحل التنفيذ

> يُنفَّذ على دفعات متتالية، كل دفعة = رسالة أو أكثر تحتوي migrations + RLS + server functions + صفحات + اختبار. لا حذف لأي بند من متطلبات المستخدم.

## Phase 1 — Foundation (base shell + Auth + RBAC + Audit)
- Enums: `admin_role`, `app_permission`.
- Tables: `admin_users`, `roles`, `permissions`, `role_permissions`, `admin_2fa`, `audit_logs`.
- SECURITY DEFINER: `has_role(uid, role)`, `has_permission(uid, perm)`.
- RLS: locked by default, opened by `has_permission`.
- Trigger: `audit_writer()` attached to every sensitive table added later.
- Frontend: TanStack Start shell, RTL/LTR, dark mode, Yamo palette, Sidebar (14 groups), TopBar, CommandPalette, GlobalSearch skeleton, i18n (ar/en).
- `/auth` page (email/password + Google via `lovable.auth.signInWithOAuth`).
- `/_authenticated/*` gate uses managed layout.
- First super_admin bootstrap flow.

## Phase 2 — Users + Wallet Ledger
- `profiles`, `user_devices`, `user_sessions`.
- `wallets`, `wallet_accounts`, `wallet_ledger` (append-only).
- Server functions: `credit_wallet`, `debit_wallet`, `transfer_wallet`, `reserve_balance`, `release_reserved_balance`, `refund_transaction`, `grant_reward`, `revoke_reward` — all `requireSupabaseAuth` + `has_permission` + idempotency + audit.
- Pages: `/users`, `/users/$id`, `/users/$id/edit`, `/users/verifications`, `/users/deleted`.

## Phase 3 — Agencies + Hosts + BD
- All 12 tables.
- Transfer request state machine (source → target → BD/Admin → cooldown → execute).
- Automatic level promotion/demotion via `pg_cron` calling `/api/public/cron/agency-levels`.
- Pages under `/agencies/*`, `/hosts/*`, `/bd/*` with BD-scoped RLS.

## Phase 4 — Rooms + Messages + Calls + Posts
- All content tables + Realtime publications.
- Moderation queue + "open content after report" server function w/ audit.
- Winbar design + multipliers + logs.
- Rankings daily/weekly/monthly (materialized view refreshed by cron).

## Phase 5 — Gifts / Store / Inventory / VIP / Levels
- Gift categories, effects, Lottie storage.
- `lucky_gift_rules` RNG server-side only.
- Inventory grants (single + mass) with audit.
- VIP subscription lifecycle.

## Phase 6 — Recharge / Withdrawals / Payments
- Packages + payment methods by country.
- Withdrawal state machine + dual approval.
- Payment webhook routes with HMAC verification.

## Phase 7 — Banners + Daily Login + Events + Notifications
- Banner CRUD + placements + targeting + versioning + rollback + preview + stats.
- Daily login 7/14/30 with Grace + mass compensation.
- Event Builder: rules engine, tasks, scoring sources, leaderboards, auto/manual distribution, sandbox, clone, templates.
- Notifications multi-channel + approval + rate limits.

## Phase 8 — Reports + Moderation + Settings + Remote Config + SDUI
- Report builder + CSV/Excel/PDF + scheduled reports.
- Moderation cases, penalties, appeals, wordlists, automod.
- Settings pages with per-key version/history/rollback.
- `app_config`, `app_config_versions`, `feature_flags`, `ui_sections`, `ui_components` full CRUD + targeting + preview → publish → rollback.

## Phase 9 — Android API `/api/v1/*` + Realtime + Webhooks
- All server routes per `docs/06-api-contract.md`.
- Realtime channel layout matches Android SDK expectations.
- Public webhooks with signature verify + Ledger writes.

## Phase 10 — AI Operator (Local Rules Mode)
- Templates + rules engine for event/banner/notification drafts.
- Provider Adapter interface (BYOK) — no default paid provider.
- Full audit of prompt/result/approval/execution.
- Whitelisted safe actions only — no free SQL.

## Phase 11 — QA + Seed + Docs
- Seed data for dev only (guarded by `app.env = 'development'`).
- README (AR/EN), `env.example`, Android integration guide, GitHub export instructions.
- Test matrix: every role × RLS, transfer flows, dual-approval withdrawal, event lifecycle, AI draft/execute, remote-config rollback, realtime, uploads.

## Delivery Contract

- ✅ لا صفحات فارغة ولا أزرار بلا وظيفة.
- ✅ لا أسرار في الواجهة.
- ✅ لا عمليات مالية من Client.
- ✅ كل عملية حساسة في Audit Logs.
- ✅ قابل للتصدير إلى GitHub والاستضافة خارج Lovable.
