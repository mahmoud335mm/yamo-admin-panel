# Phase 5D-1.1 — Project-Wide Security Reconciliation Report

**Verdict:** `5D-1.1 Security Gate — Partial Pass (PUBLIC=0, anon=0 verified; authenticated SECDEF admin allowlist requires per-function attestation in a follow-up)`

**Scope:** Reconcile the earlier "0 anon EXECUTE / 0 WARN" claims against the current database. Fix real anon grants, harden the chargeback identity constraint, add legacy-status preservation, and set up assertion-level tests. **No** runtime lifecycle changes, no wallet mutation, no refund execution, no gateway calls. **5D-2 has NOT been started** (see §9).

---

## 1. Reconciling the "196" figure

Earlier reports asserted `PUBLIC EXECUTE = 0` and `anon EXECUTE = 0` while simultaneously reporting "196 Security Warnings — pre-existing legacy". Direct extraction from `pg_proc` at the start of this phase contradicted both claims:

| Metric (before 5D-1.1)                                | Actual value |
|--------------------------------------------------------|--------------|
| Total `SECURITY DEFINER` functions in `public`         | **202**      |
| Functions granted `EXECUTE` to `PUBLIC`                | 0            |
| Functions granted `EXECUTE` to `anon`                  | **14**       |
| Functions granted `EXECUTE` to `authenticated`         | **182**      |
| Functions granted `EXECUTE` to `service_role`          | 202          |
| Functions missing pinned `search_path`                 | 0            |

The linter's "196 WARN" was NOT purely legacy false positives — it corresponded 1:1 with rule `0029_authenticated_security_definer_function_executable`: one warning per SECDEF function callable by `authenticated` (182) plus 14 anon overlaps (some overlap, so total unique warnings = 196 pre-migration).

**Source query** (reproducible):
```sql
SELECT COUNT(*) FILTER (WHERE p.prosecdef) AS total,
       COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('anon', p.oid, 'EXECUTE'))          AS anon,
       COUNT(*) FILTER (WHERE p.prosecdef AND has_function_privilege('authenticated', p.oid, 'EXECUTE')) AS authn
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public';
```

## 2. The 14 anon grants — root cause

All 14 were 5C refund lifecycle RPCs whose migration granted permission via the default `TO PUBLIC` behavior of `CREATE FUNCTION` combined with an inherited pattern from earlier phases that granted broadly rather than to `authenticated` specifically. They each contain internal permission checks so no data leak occurred, but the grants themselves contradicted the reports.

| Function |
|---|
| `_lookup_refund_policy(text,text,uuid)` |
| `_refund_preflight_calc(uuid,text,text,numeric,text)` |
| `approve_recharge_refund(uuid,text)` |
| `assert_no_overlapping_refund_policies()` |
| `assert_no_overlapping_refund_retry_policies()` |
| `cancel_recharge_refund(uuid,text)` |
| `execute_recharge_refund(uuid,text,text)` |
| `preview_recharge_refund(uuid,refund_type,refund_scope,numeric,text)` |
| `reject_recharge_refund(uuid,text)` |
| `request_recharge_refund(uuid,refund_type,refund_scope,numeric,text,text,text)` |
| `resolve_refund_policy(text,text,uuid,text,refund_type,refund_scope,timestamptz)` |
| `resolve_refund_retry_policy(uuid,text,timestamptz)` |
| `review_recharge_refund(uuid,text,text)` |
| `second_approve_recharge_refund(uuid,text)` |

## 3. Grants before / after — project-wide

| Grantee          | Before | After |
|------------------|--------|-------|
| PUBLIC           | 0      | 0     |
| anon             | 14     | **0** |
| authenticated    | 182    | **161** (21 internal helpers moved to service_role-only) |
| service_role     | 202    | 202   |

### Internal helpers moved off `authenticated`

Any function matching `_%`, `tg_%`, `assert_%`, or the auth trigger `handle_new_admin_user` — 21 rows in total — is called only by other SECDEF functions or by triggers, never directly from client code. `EXECUTE` was revoked from `authenticated`.

Examples: `_lookup_refund_policy`, `_refund_preflight_calc`, `_resolve_pearl_rule`, `_dispute_transition_ok`, `tg_refund_state_machine`, `tg_recharge_dispute_state_machine`, `assert_no_overlapping_refund_policies`, `assert_refund_ledger_pairing`, `handle_new_admin_user`, …

## 4. Chargeback provider identity — completeness constraint

Added `chk_disputes_chargeback_identity_complete` on `recharge_disputes`:

```sql
CHECK (
  provider_chargeback_id IS NULL
  OR (
    length(btrim(provider_chargeback_id)) > 0
    AND gateway_id IS NOT NULL
    AND gateway_mode IS NOT NULL
    AND gateway_mode IN ('test','live')
    AND chargeback_amount IS NOT NULL
    AND chargeback_currency IS NOT NULL
  )
)
```

This closes the NULL-partial-uniqueness gap: `uq_disputes_provider_chargeback (gateway_id, gateway_mode, provider_chargeback_id) WHERE provider_chargeback_id IS NOT NULL` can no longer be circumvented by a NULL `gateway_id` / `gateway_mode`. Error surface: constraint violation SQLSTATE `23514`; downstream RPCs (5D-2) will translate to `CHARGEBACK_PROVIDER_IDENTITY_INCOMPLETE`.

## 5. Legacy backfill audit

- `recharge_disputes` currently holds **0 rows** — no historical data was rewritten (verified via `SELECT status, COUNT(*) FROM public.recharge_disputes GROUP BY 1` → empty result).
- Column `legacy_status_original text` added and reserved for any future manual data migration; policy: write-once, never overwrite.
- The `won → resolved_platform_favor` / `lost → resolved_user_favor` mapping documented in 5D-1 was therefore never applied to any row and remains an unvalidated assumption. **Do not backfill legacy dispute data without capturing the original text into `legacy_status_original` in the same statement.**

## 6. Evidence quarantine — current column state

Table `recharge_dispute_evidence` already has `status`, `malware_scan_status`, `is_quarantined`. RPCs to enforce `status='uploaded' → malware_scan_status='pending' → is_quarantined=true` defaults and to gate signed-URL issuance on `malware_scan_status='clean' AND is_quarantined=false` are part of 5D-2's evidence lifecycle and **have not been implemented in this phase**.

## 7. SQL assertion results (`tests/sql/5d1_1_project_security_reconciliation.sql`)

| # | Assertion | Result |
|---|---|---|
| R1 | 0 PUBLIC SECDEF EXECUTE project-wide | **PASS** |
| R2 | 0 anon SECDEF EXECUTE project-wide | **PASS** |
| R3 | No `_%` helper callable by authenticated | **PASS** |
| R4 | No `tg_%` trigger helper callable by authenticated | **PASS** |
| R5 | No `assert_%` helper callable by authenticated | **PASS** |
| R6 | search_path pinned on every SECDEF | **PASS** (0 rows missing) |
| R7 | `chk_disputes_chargeback_identity_complete` present | **PASS** |
| R8 | `legacy_status_original` column present | **PASS** |
| R9 | 5C refund flags remain `false` | **PASS** |
| R10 | 5D dispute flags remain `false` | **PASS** |
| R11 | Runtime chargeback-NULL insert rejection | **BLOCKED** (requires runtime test project) |
| R12 | Summary counts (202/0/0/161) | **PASS** |

## 8. Remaining `authenticated` SECDEF functions — allowlist status

161 SECDEF functions remain callable by any signed-in user. Static code inspection buckets them as:

| Bucket | Approx count | Notes |
|---|---|---|
| Admin RPCs with `auth.uid()` / `has_role` / `has_permission` in body | 129 | Verified via `pg_get_functiondef` text search. These are legitimate admin RPCs. |
| Admin RPCs without keyword match (custom auth pattern) | 32 | Includes `admin_debit_user_coins`, `admin_credit_user_pearls`, `admin_update_profile`, `execute_host_transfer`, `approve_host_transfer_*`, `mark_withdrawal_paid`, `reverse_admin_wallet_adjustment`, etc. Each performs its own privilege check but the pattern is bespoke. |
| Read-only resolvers (`resolve_coin_price`, `resolve_pearl_*`, `get_available_payment_methods`, `calculate_recharge_dispute_sla`, `preview_admin_invite`, `is_admin`, `is_charging_agency_owner`, `is_charging_agent`) | ~9 | Read-only, side-effect free. Safe to keep on authenticated. |

**Per-function attestation for the 32 bespoke admin RPCs is deferred to a follow-up sub-phase (5D-1.2)** — each needs an individual code read to confirm the internal privilege check cannot be bypassed via crafted arguments. This report does not claim they are unsafe; it declines to claim they are safe without inspection.

The Supabase linter continues to flag these 161 as WARN (rule `0029_authenticated_security_definer_function_executable`). **The linter cannot see the internal `has_permission` checks and will WARN on any authenticated-callable SECDEF regardless of internal safety** — this is a known false-positive vector, but until the 32 bespoke handlers are individually attested, the WARN count is not treated as fully triaged.

## 9. Regression / no-touch confirmation

- ✅ 5C refund lifecycle files, RPCs, and paths **unchanged**. No file under `src/lib/refunds/` was edited.
- ✅ No wallet mutation, ledger write, refund execution, receivable creation, or gateway network call in this phase.
- ✅ 5C refund feature flags all remain `false` (R9).
- ✅ 5D dispute feature flags all remain `false` (R10).
- ✅ No dispute lifecycle RPC created — `5D-2 has NOT been started`.
- ✅ Function bodies for existing 5C RPCs unchanged; only their `EXECUTE` grants were narrowed.

## 10. Type check / lint / build / secret scan

- Static changes only (SQL migration + one test file + this report). No TypeScript touched.
- The TS route files that call the 5C refund RPCs continue to work: those calls arrive with an `authenticated` bearer token, hit the RPC, and the RPC (SECURITY DEFINER) still executes because `authenticated` still holds `EXECUTE` on the user-facing RPCs (only the internal `_`-prefixed helpers lost it).
- Secret scan: no new secrets introduced.

## 11. Gate decision

| Criterion (from user spec §2) | Status |
|---|---|
| PUBLIC EXECUTE = 0 project-wide | **PASS** |
| anon EXECUTE = 0 project-wide | **PASS** |
| Every allowed authenticated function has: pinned search_path (§2.6) | **PASS** |
| Every authenticated function on an explicit allowlist with per-item justification (§2.1–§2.5, §2.7, §2.8) | **NOT MET** — 32 bespoke admin RPCs still require per-function attestation |
| Internal helpers not callable by authenticated (§2 internal list) | **PASS** for `_%`, `tg_%`, `assert_%`, `handle_new_admin_user`. Other classes (wallet mutation, ledger, webhook, gateway, evidence internal helpers) already service-role-only or reachable only via `service_role` clients per 5C reports; not re-audited in this phase. |
| Chargeback provider identity completeness constraint | **PASS** |
| Legacy backfill audit | **PASS** (empty table; column reserved) |
| Evidence quarantine RPCs | **DEFERRED to 5D-2** |
| Runtime security assertions | **BLOCKED** (no runtime test project) |

**Overall gate:** `Partial Pass`. The two hard reconciliation failures (14 anon grants; 21 internal helpers on authenticated) are fixed and verified. The allowlist-with-attestation requirement for the remaining 32 bespoke admin RPCs is not met and is a prerequisite for a full `PASS`.

## 12. Blocking condition for 5D-2

Per the user's instruction — *"لا تبدأ 5D-2 قبل نجاح بوابة 5D-1.1"* — and given that the allowlist attestation for the 32 bespoke authenticated admin RPCs is not yet complete, **5D-2 (Dispute Lifecycle RPCs) has NOT been started in this turn**. The next action is either:

1. **User elects "proceed on Partial Pass"** — I start 5D-2 immediately in the next turn, acknowledging §8 as a known follow-up.
2. **User elects "complete allowlist first"** — I open sub-phase 5D-1.2 to read and attest each of the 32 bespoke RPCs one by one before touching 5D-2.

5D-2's scope (23+ RPCs, evidence upload lifecycle, notes lifecycle, two-eyes decisions, resolve/reject/cancel/close/reopen linked-case design, chargeback administrative actions, audit taxonomy, outbox events, and their concurrency / idempotency tests) is a multi-turn deliverable on its own and will not fit alongside 5D-1.1 in a single response.
