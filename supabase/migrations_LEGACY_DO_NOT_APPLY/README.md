# ⚠️ LEGACY MIGRATIONS — DO NOT APPLY TO THE YAMO DATABASE

These 55 migrations built the admin panel's ORIGINAL standalone database
(`omgrldatyncodeabecia`). They are kept for reference only.

## Why they must never run against Yamo (btsjuwbjfyikoyqzmwwp)

1. **`public.wallets` conflict — critical.**
   The Yamo wallet is one row per user with `coins`/`pearls` columns and
   ALL writes revoked from `authenticated`. The version here is one row per
   (user, currency) with `balance`/`reserved`, references `public.profiles`
   instead of `auth.users`, and runs:

       GRANT SELECT, INSERT, UPDATE ON public.wallets TO authenticated;

   Applying that would let any signed-in user edit their own balance
   directly, destroying every safeguard built in the Wallet phase.

2. **Parallel economy.** These migrations create `transactions`,
   `wallet_ledger`, `system_ledger`, `recharge_requests`,
   `withdrawal_requests`, `payment_methods`, `agencies`, `hosts` and 25
   `charging_*` tables. Yamo already implements all of these. Running both
   would mean two competing sources of truth for real money.

3. **`profiles` conflict.** The admin version has a different shape from
   Yamo's `profiles`, which the whole app depends on.

## What is used instead

`RUN_THIS_SQL_V120.sql` in the Yamo project creates only the admin
infrastructure that has no Yamo equivalent, all prefixed `yamo_admin_*`
or `yamo_event*` so collision is impossible:

- `yamo_admin_users`, `yamo_admin_roles`, `yamo_admin_permissions`,
  `yamo_admin_role_permissions`, `yamo_admin_role_assignments`,
  `yamo_admin_invites`, `yamo_admin_audit_logs`
- `yamo_events`, `yamo_event_rewards`, `yamo_event_tasks`,
  `yamo_event_participants`

Every admin action goes through a permission-gated, audited
`SECURITY DEFINER` RPC on the Yamo database.
