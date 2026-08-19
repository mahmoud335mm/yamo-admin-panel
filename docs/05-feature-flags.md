# 05 — Feature Flags & Remote Config Keys

> كل مفتاح مُخزَّن في `feature_flags` أو `app_config` مع version + history + rollback + targeting.

## Feature Flags (boolean toggles)

### Core
- `app.maintenance_mode`
- `app.force_update_min_version`
- `app.signup_enabled`
- `app.email_password_enabled`
- `app.google_signin_enabled`
- `app.face_verification_required`
- `app.one_account_per_device`

### Rooms
- `rooms.enabled`
- `rooms.mic_counts_allowed` → jsonb `[2,5,8,10,15,20,25,30]`
- `rooms.password_rooms_enabled`
- `rooms.winbar.enabled`
- `rooms.winbar.multiplier_max`
- `rooms.rankings.enabled`
- `rooms.trophy_widget_enabled`

### Gifts
- `gifts.enabled`
- `gifts.lucky.enabled`
- `gifts.combo.enabled`
- `gifts.group_send.enabled`
- `gifts.limited_editions.enabled`

### Games
- `games.enabled`
- `games.ludo.enabled`
- `games.pool.enabled`
- `games.luck.enabled`
- `games.pairs.enabled`

### Messaging & Calls
- `messenger.enabled`
- `messenger.attachments.video.enabled`
- `messenger.attachments.file.enabled`
- `calls.audio.enabled`
- `calls.video.enabled`
- `calls.paid.enabled`

### Posts
- `posts.enabled`
- `posts.video.enabled`
- `posts.poll.enabled`
- `posts.automod.enabled`

### Events / Daily Login / Banners
- `events.enabled`
- `daily_login.enabled`
- `banners.enabled`
- `banners.after_4th_room.enabled`

### Economy
- `wallet.recharge.enabled`
- `wallet.withdraw.enabled`
- `wallet.transfer.enabled`
- `agency.transfer.enabled`
- `bd.enabled`

### AI Operator (admin console)
- `ai.local_rules_mode` (default true)
- `ai.byok_enabled`

## Remote Config (typed values)

| Key | Type | Notes |
|---|---|---|
| `app.name` | string | localized |
| `app.support_email` | string | |
| `app.support_phone` | string | |
| `app.min_android_version` | string | e.g. `1.24.0` |
| `app.force_update_message` | jsonb | i18n |
| `rates.coin_per_usd` | number | |
| `rates.pearl_per_coin` | number | |
| `rates.gift.host_share` | number | 0..1 |
| `rates.gift.agency_share` | number | |
| `rates.gift.bd_share` | number | |
| `rates.gift.platform_share` | number | |
| `rates.call.audio_per_min_coins` | number | |
| `rates.call.video_per_min_coins` | number | |
| `limits.upload.image_mb` | number | |
| `limits.upload.video_mb` | number | |
| `limits.upload.video_seconds` | number | |
| `limits.messages.per_minute` | number | |
| `withdraw.min_amount` | number | |
| `withdraw.dual_approval_threshold` | number | |
| `withdraw.cooldown_days` | number | |
| `agency.transfer.cooldown_days` | number | |
| `daily_login.timezone` | string | IANA |
| `signup.invite_required` | boolean | |
| `home.sections_order` | jsonb | SDUI |
| `payments.methods_by_country` | jsonb | |
| `wordlists.banned` | jsonb | per-lang |

## Targeting Dimensions

Every flag/config value can be scoped by:
`country`, `gender`, `age_range`, `level_range`, `vip_tier`, `account_type` (user/host/agency/bd), `agency_id`, `app_version_range`, `platform` (android only for now), `percentage_rollout`.

## Publish Lifecycle

`draft → preview (sandbox) → scheduled → published → paused → rolled_back`, each transition writes a new row into `app_config_versions` with `published_by`, `reason`, and `diff`.
