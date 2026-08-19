# 01 — Architecture Plan / خطة المعمارية

> Yamo Chat Admin Console — لوحة تحكم يامو شات
> يتحكم في تطبيق Android `com.blacksky.app` عبر Backend مشترك دون تعديل كود التطبيق لكل تغيير.

---

## 1. Stack

| Layer | Tech |
|---|---|
| Frontend | React 19 + TypeScript + TanStack Start v1 + Vite 7 |
| Styling | Tailwind CSS v4 + shadcn/ui + RTL |
| State/Data | TanStack Query + Supabase Realtime |
| Backend Runtime | TanStack `createServerFn` (app-internal) + Server Routes `src/routes/api/*` (public/webhooks) |
| Database | Lovable Cloud PostgreSQL (Supabase) |
| Auth | Supabase Auth (Email/Password + Google OAuth) |
| Storage | Supabase Storage (buckets: `avatars`, `covers`, `gifts`, `banners`, `events`, `posts`, `rooms`, `lottie`, `audio`, `admin-uploads`) |
| Realtime | Supabase Realtime channels |
| Scheduling | `pg_cron` + `pg_net` → server routes at `/api/public/cron/*` |
| Payments Webhooks | `/api/public/webhooks/{stripe,paypal,paddle,...}` — HMAC verified |
| RTC | Agora/Zego (mobile-only; keys in Backend Secrets, لا تُسرَّب للمتصفح) |

## 2. Layered Model

```
┌─────────────────────────────────────────────────────────┐
│ Admin Console (React + TanStack Start)                   │
│   Sidebar · TopBar · CommandPalette · GlobalSearch · RTL │
└────────────┬─────────────────────────┬──────────────────┘
             │ TanStack Query          │ Realtime
┌────────────▼─────────────┐  ┌────────▼──────────────────┐
│ createServerFn (RPC)     │  │ Supabase Realtime          │
│  ↳ requireSupabaseAuth   │  │  (dashboards, moderation)  │
│  ↳ RBAC has_permission() │  └────────────────────────────┘
└────────────┬─────────────┘
             │
┌────────────▼─────────────────────────────────────────────┐
│ Server Routes /api/*                                      │
│   /api/v1/*          → Android app contract               │
│   /api/public/*      → webhooks, cron, public reads       │
└────────────┬─────────────────────────────────────────────┘
             │
┌────────────▼─────────────────────────────────────────────┐
│ PostgreSQL (RLS everywhere) · Storage · Audit Log         │
│  Ledger (append-only) · Remote Config · Feature Flags     │
└──────────────────────────────────────────────────────────┘
             ▲
             │ same DB, same API
┌────────────┴─────────────────────────────────────────────┐
│ Android App  com.blacksky.app  (existing)                 │
│  Reads: /api/v1/*  ·  Realtime channels                   │
│  Renders: Server-Driven UI (ui_sections/ui_components)    │
└──────────────────────────────────────────────────────────┘
```

## 3. Environments

- **Development** — preview branch, seed data allowed.
- **Production** — published, seed disabled, dual-approval enforced.
- Secrets: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (managed), plus payment/RTC secrets added via Backend Secrets — **لا شيء منها في bundle المتصفح**.

## 4. Security Principles

1. **RLS on every table.** No table ships without policies.
2. **Roles in `admin_users` + `roles` + `permissions` + `role_permissions`.** Never role on profile.
3. **`has_permission(uid, perm)` SECURITY DEFINER** used by all admin RLS policies (no recursion).
4. **Audit log** = append-only trigger on every sensitive table.
5. **Ledger** = append-only; reversal = new row, never delete.
6. **Idempotency key** required on every money mutation.
7. **Dual approval** on: withdrawals > threshold, permanent ban, mass rewards, mass transfers.
8. **Rate limiting** per admin + per IP for sensitive endpoints.
9. **Soft delete** with `deleted_at` + restore window; hard-delete only via retention job.
10. **Session timeout**, device log, IP log, optional 2FA (TOTP).
11. **Content privacy**: private messages/calls invisible to admins by default; unlock only after report + reason + audit entry.

## 5. Server-Driven UI

Android app reads `GET /api/v1/config/home` → returns:
- `sections[]` — ordered, targeted (country/gender/level/vip/agency)
- `components[]` — banner / carousel / gift_bar / room_list / event_card / cta
- `feature_flags{}` — toggle native features that already ship in the APK
- New native capability = flag scaffolded now + one Android release later to activate.

## 6. Financial Flow

```
Client action ──► ServerFn (auth+perm)
                       │
                       ▼
                credit_wallet / debit_wallet / transfer_wallet
                       │  idempotency_key + row-level lock
                       ▼
                INSERT wallet_ledger (append-only)
                       │
                       ▼
                Update wallet_accounts.balance (trigger-derived from ledger)
                       │
                       ▼
                INSERT audit_logs
```

Withdrawals: `pending → reviewed → approved(2nd admin) → paid → settled` or `rejected/refunded`.

## 7. AI Operator (Local Rules Mode)

Default = **no external provider**. Templates + rules engine generate drafts for events, banners, notifications. BYOK provider adapter defined for later. Every AI output = Draft → Dry Run → Approve → Execute + full audit. No free-form SQL.

## 8. Delivery

GitHub sync (from Lovable UI) · README (AR/EN) · `env.example` · SQL migrations under `supabase/migrations/` · seed under `supabase/seed/` (dev only).
