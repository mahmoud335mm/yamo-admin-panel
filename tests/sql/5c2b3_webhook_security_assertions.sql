-- 5C-2b.3 · Refund Webhook Processor static assertions.

-- 1. Composite unique on (gateway_id, gateway_mode, provider_event_id) exists.
SELECT 'composite_unique_present' AS check, (COUNT(*) > 0) AS pass
FROM pg_indexes
WHERE schemaname='public' AND tablename='payment_webhooks' AND indexname='uq_webhook_provider_event';

-- 2. New refund-domain columns are all present.
SELECT column_name
FROM information_schema.columns
WHERE table_schema='public' AND table_name='payment_webhooks'
  AND column_name IN ('event_domain','refund_id','refund_reference','provider_refund_id',
    'original_provider_payment_id','normalized_event_type','signature_verified',
    'timestamp_verified','replay_check_passed','validation_status','payload_redacted',
    'payload_hash','failure_code','safe_error','marked_as_duplicate','event_amount',
    'event_currency','occurred_at')
ORDER BY column_name;

-- 3. All new webhook RPCs exist.
SELECT proname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND proname IN (
  'register_refund_webhook_event','claim_refund_webhook_for_processing',
  'reclaim_stale_refund_webhooks','mark_refund_webhook_terminal',
  'apply_refund_webhook_event','process_confirmed_recharge_refund',
  'log_refund_webhook_audit'
) ORDER BY proname;

-- 4. Zero PUBLIC / anon / authenticated EXECUTE grants on the new RPCs.
SELECT p.proname AS function, r.rolname AS role
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN LATERAL aclexplode(p.proacl) a ON true
JOIN pg_roles r ON r.oid = a.grantee
WHERE n.nspname='public'
  AND p.proname IN ('register_refund_webhook_event','claim_refund_webhook_for_processing',
    'reclaim_stale_refund_webhooks','mark_refund_webhook_terminal',
    'apply_refund_webhook_event','process_confirmed_recharge_refund',
    'log_refund_webhook_audit')
  AND a.privilege_type='EXECUTE'
  AND r.rolname IN ('PUBLIC','anon','authenticated');  -- expected: 0 rows

-- 5. payment_webhooks write access is denied to authenticated (restrictive).
SELECT policyname, permissive, cmd
FROM pg_policies WHERE schemaname='public' AND tablename='payment_webhooks'
  AND policyname='pw_no_write_auth';

-- 6. Wallet reversal helper remains service-only.
SELECT COUNT(*) AS authenticated_leak_must_be_zero
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN LATERAL aclexplode(p.proacl) a ON true
JOIN pg_roles r ON r.oid = a.grantee
WHERE n.nspname='public' AND p.proname='_apply_recharge_refund_wallet_reversal'
  AND a.privilege_type='EXECUTE' AND r.rolname IN ('PUBLIC','anon','authenticated');

-- 7. event_domain / validation_status check constraints exist.
SELECT conname FROM pg_constraint WHERE conname IN
  ('payment_webhooks_event_domain_chk','payment_webhooks_validation_status_chk')
ORDER BY conname;

-- 8. Refund status enum still contains the required states.
SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
WHERE t.typname='refund_status' AND enumlabel IN
  ('gateway_confirmed','reversing_wallet','completed','partially_completed','manual_review','failed')
ORDER BY enumlabel;
