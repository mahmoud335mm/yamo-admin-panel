-- ============================================================================
-- Phase 5C-4 — Final SQL Security Assertions
-- Run inside a Test Project (never against production). Each block is designed
-- to raise an exception (or return non-zero rows) when an invariant is broken,
-- so the whole file can be piped through `psql -v ON_ERROR_STOP=1`.
-- ============================================================================

-- 1. No PUBLIC EXECUTE on SECURITY DEFINER functions in public schema.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND has_function_privilege('public', p.oid, 'EXECUTE');
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-01: % SECURITY DEFINER functions grant EXECUTE to PUBLIC', bad; END IF;
END $$;

-- 2. No anon EXECUTE on SECURITY DEFINER functions (except explicit allowlist).
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND NOT EXISTS (
      SELECT 1 FROM public.security_definer_public_allowlist a WHERE a.function_name = p.proname
    );
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-02: % SECURITY DEFINER functions grant EXECUTE to anon outside allowlist', bad; END IF;
END $$;

-- 3. All 5C refund functions have search_path pinned.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (p.proname LIKE '%refund%' OR p.proname LIKE '%recharge_refund%')
    AND p.prosecdef = true
    AND NOT EXISTS (
      SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg WHERE cfg LIKE 'search_path=%'
    );
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-03: % refund functions missing pinned search_path', bad; END IF;
END $$;

-- 4. Wallet-reversal internal RPC not callable by any user-facing role.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = '_apply_recharge_refund_wallet_reversal'
    AND (
      has_function_privilege('public',        p.oid, 'EXECUTE') OR
      has_function_privilege('anon',          p.oid, 'EXECUTE') OR
      has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-04: wallet-reversal RPC exposed beyond service_role'; END IF;
END $$;

-- 5. Gateway prepare/finalize/fail RPCs are internal only.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = ANY (ARRAY[
      'prepare_refund_gateway_execution',
      'finalize_refund_gateway_execution',
      'fail_refund_gateway_execution',
      'prepare_refund_status_refresh',
      'finalize_refund_status_refresh',
      'fail_refund_status_refresh',
      'claim_refund_gateway_execution_lease',
      'claim_refund_status_refresh_lease'
    ])
    AND (
      has_function_privilege('anon',          p.oid, 'EXECUTE') OR
      has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-05: % gateway-internal RPCs exposed to anon/authenticated', bad; END IF;
END $$;

-- 6. Webhook register/claim/finalize RPCs are internal only.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'register_refund_webhook',
      'claim_refund_webhook_processing',
      'finalize_refund_webhook_processing',
      'fail_refund_webhook_processing'
    )
    AND (
      has_function_privilege('anon',          p.oid, 'EXECUTE') OR
      has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-06: % webhook-internal RPCs exposed', bad; END IF;
END $$;

-- 7. Append-only tables: authenticated must have no UPDATE/DELETE.
DO $$
DECLARE bad int;
DECLARE t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'wallet_ledger','system_ledger','audit_logs',
    'recharge_refund_attempts','payment_webhooks',
    'transaction_message_outbox'
  ]) LOOP
    IF has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
       OR has_table_privilege('authenticated', 'public.' || t, 'DELETE')
       OR has_table_privilege('anon', 'public.' || t, 'UPDATE')
       OR has_table_privilege('anon', 'public.' || t, 'DELETE') THEN
      RAISE EXCEPTION 'SEC-07: append-only table % is mutable by anon/authenticated', t;
    END IF;
  END LOOP;
END $$;

-- 8. Feature flags cannot be updated by non-admin roles.
DO $$
BEGIN
  IF has_table_privilege('authenticated', 'public.system_settings', 'UPDATE')
     OR has_table_privilege('anon', 'public.system_settings', 'UPDATE') THEN
    RAISE EXCEPTION 'SEC-08: system_settings mutable outside admin role';
  END IF;
END $$;

-- 9. Refund policy resolver returns at most 1 row per input tuple (integrity check).
DO $$
DECLARE overlap int;
BEGIN
  SELECT public.assert_no_overlapping_refund_policies() INTO overlap;
  IF overlap <> 0 THEN RAISE EXCEPTION 'SEC-09: overlapping refund policies detected (%)', overlap; END IF;
END $$;

-- 10. Retry policy resolver has no overlaps.
DO $$
DECLARE overlap int;
BEGIN
  SELECT public.assert_no_overlapping_refund_retry_policies() INTO overlap;
  IF overlap <> 0 THEN RAISE EXCEPTION 'SEC-10: overlapping refund retry policies detected (%)', overlap; END IF;
END $$;

-- 11. State machine: no completed → processing_gateway transitions historically.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM public.audit_logs
  WHERE resource = 'recharge_refunds'
    AND (metadata->>'old_status') = 'completed'
    AND (metadata->>'new_status') = 'processing_gateway';
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-11: illegal completed→processing_gateway transitions: %', bad; END IF;
END $$;

-- 12. rejected → approved and cancelled → completed have never occurred.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM public.audit_logs
  WHERE resource = 'recharge_refunds'
    AND (
      ((metadata->>'old_status') = 'rejected'  AND (metadata->>'new_status') = 'approved') OR
      ((metadata->>'old_status') = 'cancelled' AND (metadata->>'new_status') = 'completed')
    );
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-12: illegal refund transitions: %', bad; END IF;
END $$;

-- 13. Two-eyes: no completed refund has first_reviewer = second_reviewer.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM public.recharge_refunds
  WHERE status IN ('completed','partially_completed','gateway_confirmed')
    AND first_reviewer_id IS NOT NULL
    AND second_reviewer_id IS NOT NULL
    AND first_reviewer_id = second_reviewer_id;
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-13: two-eyes violation: %', bad; END IF;
END $$;

-- 14. Two-eyes: requester never approves own refund at either level.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM public.recharge_refunds
  WHERE requested_by IS NOT NULL
    AND (requested_by = first_reviewer_id OR requested_by = second_reviewer_id);
  IF bad > 0 THEN RAISE EXCEPTION 'SEC-14: requester approved own refund: %', bad; END IF;
END $$;

-- 15. Ledger pairing invariant: every wallet debit for a completed refund has a matching system credit.
DO $$
DECLARE mismatched int;
BEGIN
  SELECT count(*) INTO mismatched
  FROM public.wallet_ledger wl
  WHERE wl.transaction_reference LIKE 'refund:%'
    AND wl.entry_type = 'debit'
    AND NOT EXISTS (
      SELECT 1 FROM public.system_ledger sl
      WHERE sl.transaction_group_id = wl.transaction_group_id
        AND sl.entry_type = 'credit'
        AND sl.amount = wl.amount
    );
  IF mismatched > 0 THEN RAISE EXCEPTION 'LDG-01: % refund debits missing system-side credit', mismatched; END IF;
END $$;

-- 16. No wallet reversal exists for refunds that never reached gateway_confirmed / completed.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM public.wallet_ledger wl
  JOIN public.recharge_refunds r ON r.id::text = split_part(wl.transaction_reference, ':', 2)
  WHERE wl.transaction_reference LIKE 'refund:%'
    AND r.status NOT IN ('completed','partially_completed','gateway_confirmed');
  IF bad > 0 THEN RAISE EXCEPTION 'LDG-02: wallet reversal for non-completed refund: %', bad; END IF;
END $$;

-- 17. No wallet balance is negative.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad FROM public.wallets WHERE coins_balance < 0 OR pearls_balance < 0;
  IF bad > 0 THEN RAISE EXCEPTION 'LDG-03: negative wallet balances: %', bad; END IF;
END $$;

-- 18. Ledger append-only: no rows with updated_at > created_at.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad FROM public.wallet_ledger
  WHERE updated_at IS NOT NULL AND updated_at <> created_at;
  IF bad > 0 THEN RAISE EXCEPTION 'LDG-04: wallet_ledger rows mutated after insert: %', bad; END IF;
END $$;

SELECT '5C-4 SQL assertions: PASSED' AS result;
