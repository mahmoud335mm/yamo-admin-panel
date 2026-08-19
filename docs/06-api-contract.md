# 06 — API Contract for Android / عقد API لتطبيق Android

Base URL (published):
```
https://project--505c1a6c-bb0e-4c6a-bc96-1c936d82771c.lovable.app/api/v1
```
Stable across renames. All endpoints require `Authorization: Bearer <supabase_access_token>` unless marked **PUBLIC**.

## Conventions

- JSON only, UTF-8.
- Errors:
  ```json
  { "error": { "code": "string", "message": "string", "details": {} } }
  ```
- Pagination: `?cursor=...&limit=50` → response `{ "items": [...], "next_cursor": "..." }`
- Sorting: `?sort=created_at.desc`
- Filtering: `?filter[status]=active`
- Idempotency: `Idempotency-Key: <uuid>` on POST/PUT for money endpoints.
- Versioning: additive-only within `v1`. Breaking = `v2` mount.

## Auth & Profile

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/session` | exchange refresh, returns claims |
| GET  | `/me` | current profile + wallet snapshot |
| PATCH| `/me` | edit name, avatar, cover, bio (not gender) |
| POST | `/me/devices` | register device (push token, model, os) |
| DELETE| `/me/devices/$id` | logout that device |

## Home / Config (SDUI)

| Method | Path | Purpose |
|---|---|---|
| GET | `/config/app` | **PUBLIC** — Remote Config for anonymous first-launch |
| GET | `/config/home` | Server-Driven UI sections + components for the caller |
| GET | `/config/feature-flags` | Flags evaluated for the caller |
| GET | `/config/banners?placement=home` | ordered banners w/ deep links |
| GET | `/config/daily-login` | current campaign + user progress |

## Rooms

| Method | Path | Purpose |
|---|---|---|
| GET | `/rooms` | list w/ filters `country, category, mic_count` |
| GET | `/rooms/$id` | detail |
| POST | `/rooms` | create (host / eligible) |
| PATCH | `/rooms/$id` | edit meta |
| POST | `/rooms/$id/join` | join |
| POST | `/rooms/$id/leave` | leave |
| POST | `/rooms/$id/mics/$slot/request` | request mic |
| POST | `/rooms/$id/mics/$slot/take` | admin/owner action |
| POST | `/rooms/$id/mics/$slot/mute` | mute/unmute |
| POST | `/rooms/$id/kick` | kick user |
| POST | `/rooms/$id/ban` | ban user (temp/perm) |
| GET | `/rooms/$id/rankings` | winbar + daily/weekly/monthly |

## Messages & Calls

| Method | Path | Purpose |
|---|---|---|
| GET | `/conversations` | list |
| GET | `/conversations/$id/messages` | paginated |
| POST | `/conversations/$id/messages` | send (text/image/video/audio/gift) |
| DELETE | `/messages/$id` | delete for me / for all |
| POST | `/calls` | start (audio/video/room) |
| POST | `/calls/$id/end` | end + finalize cost |

## Posts

| Method | Path |
|---|---|
| GET | `/posts?feed=for-you|following|trending` |
| POST | `/posts` |
| GET | `/posts/$id` |
| DELETE | `/posts/$id` |
| POST | `/posts/$id/reactions` |
| POST | `/posts/$id/comments` |

## Uploads

| Method | Path | Purpose |
|---|---|---|
| POST | `/uploads/sign` | returns pre-signed URL for target bucket |

## Wallet & Economy

| Method | Path | Purpose |
|---|---|---|
| GET | `/wallet` | all currencies snapshot |
| GET | `/wallet/ledger` | user-visible entries |
| GET | `/recharge/packages` | packages available in caller country |
| POST | `/recharge/orders` | create order → returns provider payload |
| GET | `/withdraw/methods` | methods by country |
| POST | `/withdraw/requests` | new withdrawal request |
| GET | `/withdraw/requests` | user's requests |

## Gifts / Store / Inventory

| Method | Path |
|---|---|
| GET | `/gifts?placement=room` |
| POST | `/gifts/send` (Idempotency-Key required) |
| GET | `/store/items` |
| POST | `/store/purchase` |
| GET | `/inventory` |
| POST | `/inventory/$id/equip` |

## VIP / Levels

| Method | Path |
|---|---|
| GET | `/vip/plans` |
| POST | `/vip/subscribe` |
| GET | `/levels` |
| GET | `/levels/my` |

## Agencies / Hosts / BD

| Method | Path |
|---|---|
| GET | `/agencies/$id/public` | public card |
| POST | `/agencies/$id/join-requests` | invite-code or open |
| GET | `/hosts/my` | if caller is a host |
| GET | `/hosts/my/earnings` |
| GET | `/hosts/my/targets` |

## Events

| Method | Path |
|---|---|
| GET | `/events?status=live` |
| GET | `/events/$id` |
| GET | `/events/$id/leaderboard` |
| POST | `/events/$id/claims` |

## Notifications

| Method | Path |
|---|---|
| GET | `/notifications/inbox` |
| POST | `/notifications/$id/read` |
| POST | `/notifications/token` | register push token |

## Realtime Channels

- `public:rooms:$id` — mic changes, gifts, winbar tick
- `public:conversations:$id` — new messages
- `private:user:$uid` — inbox, wallet updates, moderation notices
- `public:events:$id` — leaderboard/tick

## Webhooks (inbound to server)

Under `/api/public/webhooks/*` — HMAC-signature verified inside handler:
- `/api/public/webhooks/stripe`
- `/api/public/webhooks/paypal`
- `/api/public/webhooks/paddle`
- `/api/public/webhooks/apple-iap`
- `/api/public/webhooks/google-play`

## Example — Send Gift

Request:
```
POST /api/v1/gifts/send
Authorization: Bearer <token>
Idempotency-Key: 6b2f...
Content-Type: application/json

{
  "gift_id": "5f3...",
  "receiver_id": "9ab...",
  "room_id": "c1d...",
  "quantity": 3,
  "combo_id": null
}
```
Response `200`:
```json
{
  "transaction_id": "tx_01H...",
  "ledger_entries": ["led_...","led_..."],
  "sender_balance_after": { "coin": 128400 },
  "receiver_reward": { "pearl": 900 },
  "animation": { "lottie_url": "...", "duration_ms": 3200 },
  "winbar_delta": { "amount": 900, "multiplier": 1.0 }
}
```

Full endpoint-by-endpoint OpenAPI ships alongside Phase 9 implementation.
