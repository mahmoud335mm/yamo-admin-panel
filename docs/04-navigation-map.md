# 04 — Navigation Map / خريطة التنقل

## Top-Level (Sidebar Groups)

```
📊 Overview
   └─ / (Dashboard)
   └─ /realtime         (Live activity)
   └─ /health           (DB · Realtime · Storage · Notifications · RTC · Payments)

👥 Users
   └─ /users
   └─ /users/$id        (Profile, Wallet, Devices, Sessions, Penalties, Notes)
   └─ /users/$id/edit
   └─ /users/verifications
   └─ /users/deleted    (soft-deleted, restore)

🏢 Agencies
   └─ /agencies
   └─ /agencies/$id     (Overview · Hosts · Earnings · Tasks · Violations · Transfers · Withdrawals · Reports)
   └─ /agencies/levels
   └─ /agencies/join-requests
   └─ /agencies/transfers        (Agency-to-Agency host transfer queue)
   └─ /agencies/bd-transfers     (Agency-to-BD reassignment)

🎤 Hosts
   └─ /hosts
   └─ /hosts/$id                 (Earnings · Shifts · Targets · Violations)
   └─ /hosts/levels
   └─ /hosts/unassigned

📣 BD
   └─ /bd
   └─ /bd/$id                    (Agencies · Hosts · Commissions · Targets)
   └─ /bd/levels

🪙 Economy
   └─ /economy/wallets
   └─ /economy/ledger            (append-only browser + filters + export)
   └─ /economy/withdrawals       (queue with dual-approval)
   └─ /economy/recharge          (packages + payment methods per country)
   └─ /economy/payments          (transactions · refunds)
   └─ /economy/disputes

🎧 Rooms
   └─ /rooms
   └─ /rooms/$id                 (Members · Mics · Moderators · Bans · Winbar · Rankings)
   └─ /rooms/rankings            (daily/weekly/monthly · users/rooms/agencies)
   └─ /rooms/winbar              (design + multipliers + logs)

💬 Communication
   └─ /messages                  (metadata + open-after-report)
   └─ /calls                     (log · cost · duration · terminate)
   └─ /posts                     (moderation queue)

🎁 Gifts & Store
   └─ /gifts
   └─ /gifts/categories
   └─ /gifts/lucky               (Server-side RNG rules)
   └─ /store/items
   └─ /store/inventory           (grant/revoke)
   └─ /vip/plans
   └─ /vip/memberships
   └─ /levels
   └─ /levels/rewards

🎮 Games
   └─ /games                    (enable/order · payout ratios · anti-cheat · rounds)

🗓 Events
   └─ /events
   └─ /events/$id               (Rules · Tasks · Participants · Scores · Leaderboards · Rewards)
   └─ /events/new               (Event Builder)
   └─ /events/templates
   └─ /events/sandbox

🎯 Daily Login
   └─ /daily-login/campaigns
   └─ /daily-login/claims
   └─ /daily-login/compensate

🖼 Content
   └─ /banners
   └─ /banners/$id
   └─ /banners/placements
   └─ /notifications
   └─ /notifications/campaigns

🛡 Moderation
   └─ /reports
   └─ /moderation/queue
   └─ /moderation/penalties
   └─ /moderation/appeals
   └─ /moderation/wordlists

📈 Reports
   └─ /reports/users
   └─ /reports/economy
   └─ /reports/agencies
   └─ /reports/hosts
   └─ /reports/rooms
   └─ /reports/events
   └─ /reports/scheduled

🎛 Remote Config
   └─ /remote-config/keys
   └─ /remote-config/versions
   └─ /remote-config/feature-flags
   └─ /remote-config/ui-sections
   └─ /remote-config/ui-components

🤖 AI Operator
   └─ /ai/prompts
   └─ /ai/drafts
   └─ /ai/actions
   └─ /ai/audit
   └─ /ai/templates

⚙️ Settings
   └─ /settings/general
   └─ /settings/localization
   └─ /settings/security
   └─ /settings/rates            (call/gift/recharge rates)
   └─ /settings/limits           (rate limits · file sizes)
   └─ /settings/policies
   └─ /settings/history          (every setting versioned)

🔐 Admin
   └─ /admin/users               (admin accounts + 2FA)
   └─ /admin/roles
   └─ /admin/permissions
   └─ /admin/audit
   └─ /admin/secrets             (super_admin only – names only)

🎧 Support
   └─ /support/tickets
   └─ /support/knowledge

🔎 Global Search  (Cmd/Ctrl+K) — user id, room id, agency id, bd id, transaction id
```

## Auth Routes

- `/auth` — public (email/password + Google)
- `/auth/reset-password`
- `/auth/2fa`
- Everything else under `/_authenticated/*` gate.

## Breadcrumbs

Every leaf page shows: `Group › Section › Entity › Sub-tab` derived from route + loader data.
