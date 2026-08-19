# Phase 5D-1 Final Test Report — Disputes & Chargebacks (Schema)

**Verdict:** `5D-1 Schema Complete — Runtime and Financial Actions Not Started`

**Scope:** Schema, enums, state machines, RLS, policies, evidence storage, permissions, feature flags, TypeScript contracts. **No** RPC execution, wallet mutation, refund, chargeback processing, or gateway integration.

---

## 1. Existing tables reviewed (no duplicates created)

| Table | Action |
| --- | --- |
| `recharge_disputes` | Extended (60+ new columns), enum-converted `status`/`dispute_type`/`priority` with data-preserving USING mapping |
| `recharge_dispute_notes` | Extended (typed `note_type`, `visibility`, redaction, supersession, generated `body`) |
| `recharge_refunds`, `recharge_requests`, `payment_webhooks`, `payment_gateways`, `payment_methods` | Referenced only |
| `wallet_ledger`, `system_ledger`, `audit_logs`, `transaction_message_outbox` | **Not touched** |
| `permissions`, `role_permissions`, `system_settings` | Extended with new dispute permissions + flags |

Newly created (no `_v2`, no duplicates):

- `recharge_dispute_policies` (SLA/threshold/version resolver rules)
- `recharge_dispute_evidence` (append-only)

## 2. Legacy backfill mapping (data-preserving)

| Legacy `status` | New enum |
| --- | --- |
| `open` / `opened` | `opened` |
| `evidence_required` | `awaiting_user_evidence` |
| `under_review` | `under_review` |
| `awaiting_gateway` | `awaiting_gateway_evidence` |
| `won` | `resolved_platform_favor` |
| `lost` / `refunded` | `resolved_user_favor` |
| `chargeback` | `chargeback_received` |
| `closed` | `closed` |

Legacy `dispute_type='user_reported'` → `other`. Legacy `priority` normalised (`low`/`normal`/`high`/`urgent`).

## 3. Enums installed

10 enums: `recharge_dispute_type_enum`, `_source_enum`, `_status_enum` (23 values incl. 7-state chargeback lane), `_priority_enum`, `_severity_enum`, `_provisional_action_enum`, `_note_type_enum`, `_note_visibility_enum`, `_evidence_type_enum`, `_evidence_status_enum`.

## 4. State machine

- `_dispute_transition_ok(from,to)` — pure immutable whitelist (36 legal edges).
- `tg_recharge_dispute_state_machine` BEFORE UPDATE trigger raises `DISPUTE_ILLEGAL_TRANSITION` (SQLSTATE `check_violation`) on any illegal edge.
- Terminal states (`closed`, `resolved_*`, `rejected`, `chargeback_won/lost/accepted`) cannot return to review.
- Chargeback lane wired: `chargeback_received → acknowledged → evidence_due → contested → won|lost | accepted → closed`.

## 5. Policies & resolver

- `resolve_recharge_dispute_policy(country, currency, gateway_id, gateway_mode, dispute_type, source)` — deterministic ORDER: specificity score DESC, priority ASC, created_at ASC. Returns one row.
- `assert_no_overlapping_recharge_dispute_policies()` returns 0 rows on empty catalog. Same-priority + same-scope pairs are flagged `POLICY_CONFLICT`.

## 6. Financial exposure preview (read-only)

`preview_recharge_dispute_exposure(request_id, dispute_id?)` returns paid, refunded, charged_back, remaining exposure, base/bonus coin totals plus `blocking_reasons[]` (e.g. `OVER_REFUND_OR_CHARGEBACK`). Requires `recharge_disputes.read` or `.manage`. **No mutation.**

## 7. SLA calculation

`calculate_recharge_dispute_sla(dispute_id)` returns first-response, evidence, resolution, and chargeback due timestamps + overdue booleans. **No auto status change.**

## 8. Evidence bucket & RLS

- Private bucket `recharge-dispute-evidence` created.
- Storage RLS: read/insert gated by `recharge_disputes.evidence.read` / `.create` (or `.manage`); UPDATE and DELETE **RESTRICTIVE** blocked for authenticated.
- MIME allowlist enforced at row level: `image/jpeg`, `image/png`, `image/webp`, `application/pdf`, `text/plain`, `message/rfc822`. SVG / HTML / JS / archives rejected.
- Signed URLs never persisted in DB; only `storage_bucket` + `storage_object_path`.

## 9. Notes RLS

- Append-only preserved (`rdn_no_update`, `rdn_no_delete` RESTRICTIVE).
- Typed `visibility` backfilled from legacy `is_internal`.
- Redaction fields added; text is superseded via new note, never edited in place.

## 10. Permissions (19 new)

`recharge_disputes.{triage, review, first_decide, second_decide, close, reopen, escalate, read_sensitive, evidence.create, evidence.read, evidence.read_sensitive, evidence.review, notes.create_internal, notes.create_user_visible, chargeback.read, chargeback.manage, provisional_action, export, policies.manage}` — all granted to `super_admin`.

## 11. Feature flags (all OFF)

`feature_flags.enable_disputes_admin_ui`, `enable_user_dispute_submission`, `enable_chargeback_processing`, `enable_dispute_financial_resolution`, `enable_dispute_provisional_actions` = `false`. `system_settings` remains RESTRICTIVE no-write to authenticated.

## 12. Two-eyes at rest

`chk_disputes_two_eyes_distinct` CHECK: `first_decision_by <> second_decision_by` (when both set). Enforcement of requester/reviewer separation and threshold-driven second_decide requirement is deferred to 5D-2 RPCs. Error codes reserved: `DISPUTE_SELF_DECISION_NOT_ALLOWED`, `DISPUTE_SECOND_DECISION_REQUIRED`, `DISPUTE_SECOND_REVIEWER_MUST_DIFFER`, `DISPUTE_DECISION_THRESHOLD_CHANGED`.

## 13. Uniqueness / idempotency

- `uq_disputes_provider_chargeback` UNIQUE `(gateway_id, gateway_mode, provider_chargeback_id) WHERE provider_chargeback_id IS NOT NULL`. Prevents duplicate chargeback records from replayed webhooks.
- `uq_disputes_idempotency` UNIQUE `(idempotency_key)`.

## 14. TypeScript contracts

`src/types/disputes.ts` — Zod schemas for enums, `RechargeDisputePolicy`, `RechargeDisputeExposurePreview`, `RechargeDisputeSla`, `ChargebackProviderSummary`. No React components, no server functions yet.

## 15. SQL assertions

`tests/sql/5d1_security_assertions.sql` — 19 assertion blocks (A1–A19).

| # | Assertion | Result |
| --- | --- | --- |
| A1 | 0 PUBLIC EXECUTE on 5D-1 SECDEF fns | **PASS** |
| A2 | 0 anon EXECUTE on 5D-1 SECDEF fns | **PASS** |
| A3 | search_path pinned | **PASS** |
| A4 | RLS enabled on 4 dispute tables | **PASS** |
| A5 | notes append-only | **PASS** |
| A6 | evidence append-only | **PASS** |
| A7 | policies has RESTRICTIVE no-write | **PASS** |
| A8 | two-eyes CHECK | **PASS** |
| A9 | provider chargeback composite unique | **PASS** |
| A10 | state-machine trigger installed | **PASS** |
| A11 | illegal transitions rejected | **PASS** (all four return false) |
| A12 | canonical transitions accepted | **PASS** |
| A13 | overlap assertion returns 0 rows | **PASS** |
| A14 | 5 feature flags exist and = false | **PASS** |
| A15 | system_settings RESTRICTIVE no-write | **PASS** |
| A16 | evidence bucket exists, private | **PASS** |
| A17 | storage RLS restricts update/delete on evidence bucket | **PASS** |
| A18 | no new wallet-deduct / execute-refund fns in 5D-1 | **PASS** |
| A19 | 5C refund flags untouched | **PASS** (all remain `false`) |

## 16. Skipped / blocked

| # | Test | Status | Reason |
| --- | --- | --- | --- |
| S-1 | Runtime RLS (User A / User B / Admin / Support / Auditor) | **BLOCKED** | Requires Test Project runtime; not executed in build sandbox |
| S-2 | State-machine end-to-end via UPDATE | **BLOCKED** | Requires seeded dispute rows in a Test Project |
| S-3 | Provider chargeback webhook duplicate replay | **BLOCKED** | Deferred to 5D-2 webhook integration |
| S-4 | Playwright admin UI check | **BLOCKED** | UI not built in 5D-1; `enable_disputes_admin_ui = false` |
| S-5 | Two-eyes threshold enforcement runtime | **BLOCKED** | Enforcement lives in 5D-2 RPCs |

## 17. Security linter

- Total WARNs in project: **196** (all pre-existing legacy `SECURITY DEFINER + anon EXECUTE` items from prior phases, already documented in the 5B report).
- **New 5D-1 functions add 0 warnings** — REVOKE FROM PUBLIC + explicit REVOKE FROM anon applied to all five (`resolve_recharge_dispute_policy`, `assert_no_overlapping_recharge_dispute_policies`, `preview_recharge_dispute_exposure`, `calculate_recharge_dispute_sla`, `_dispute_transition_ok`).
- 0 FAIL, 0 ERROR.

## 18. Confirmation checklist

- ✅ No Refund production paths modified.
- ✅ No wallet deduction, no ledger writes, no receivable creation.
- ✅ No chargeback processing enabled — flag remains `false`.
- ✅ No gateway network calls.
- ✅ Refund feature flags (5C) unchanged and remain `false`.
- ✅ G-17…G-31 release gates unchanged (`blocked` / `pending`).
- ✅ Data-preserving migration only — no `DROP COLUMN`, no `DELETE`, no history rewrite.
- ✅ 5C runtime verification status: unchanged (still `Runtime Verification Pending`).

## 19. Next step

**5D-2** will add:

- Create / Assign / Triage RPCs.
- Notes + Evidence lifecycle RPCs (with redaction).
- Review + Two-Eyes decision RPCs (threshold-gated).
- Resolve / Reject / Close / Reopen RPCs (`reopen_recharge_dispute`).
- **No** chargeback financial execution.
- **No** automatic wallet reversal.
