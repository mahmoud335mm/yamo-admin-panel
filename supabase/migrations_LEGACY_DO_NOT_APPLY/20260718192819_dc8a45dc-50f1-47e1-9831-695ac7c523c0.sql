
-- Phase 5B.5 — reconcile_legacy_wallet_opening_balances
-- Idempotent: safe to re-run. Never mutates balances or existing ledger rows.

DO $$
DECLARE
  v_batch_id text := 'legacy_seed_reconciliation_2026_07_18';
  v_wallet   record;
  v_ref      text;
  v_direction ledger_direction;
  v_amount   bigint;
  v_created  int := 0;
  v_skipped  int := 0;
  v_scanned  int := 0;
  v_before_mismatch int;
  v_after_mismatch  int;
BEGIN
  -- Snapshot before
  SELECT count(*) INTO v_before_mismatch
  FROM (
    SELECT w.id
    FROM public.wallets w
    LEFT JOIN public.wallet_ledger l ON l.wallet_id = w.id
    GROUP BY w.id, w.balance
    HAVING w.balance <> COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0)
  ) s;

  FOR v_wallet IN
    SELECT w.id AS wallet_id, w.user_id, w.account, w.balance,
           COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0) AS ledger_sum
    FROM public.wallets w
    LEFT JOIN public.wallet_ledger l ON l.wallet_id = w.id
    GROUP BY w.id, w.user_id, w.account, w.balance
    HAVING w.balance <> COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0)
  LOOP
    v_scanned := v_scanned + 1;
    v_ref := v_batch_id || ':' || v_wallet.wallet_id::text;

    -- Idempotency: skip if a reconciliation entry for this wallet already exists.
    IF EXISTS (SELECT 1 FROM public.wallet_ledger WHERE reference = v_ref) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    IF (v_wallet.balance - v_wallet.ledger_sum) > 0 THEN
      v_direction := 'credit'::ledger_direction;
      v_amount := v_wallet.balance - v_wallet.ledger_sum;
    ELSE
      v_direction := 'debit'::ledger_direction;
      v_amount := v_wallet.ledger_sum - v_wallet.balance;
    END IF;

    -- Insert opening-balance ledger entry. balance_after = current wallet balance (unchanged).
    INSERT INTO public.wallet_ledger (
      wallet_id, user_id, account, direction, reason, amount, balance_after,
      reference, metadata, created_by
    ) VALUES (
      v_wallet.wallet_id, v_wallet.user_id, v_wallet.account, v_direction,
      'adjustment'::ledger_reason, v_amount, v_wallet.balance,
      v_ref,
      jsonb_build_object(
        'source', 'opening_balance_reconciliation',
        'batch_id', v_batch_id,
        'note', 'Pre-5B seed opening balance; wallet balance was NOT altered.',
        'previous_ledger_sum', v_wallet.ledger_sum
      ),
      NULL
    );
    v_created := v_created + 1;
  END LOOP;

  -- Verify post-state
  SELECT count(*) INTO v_after_mismatch
  FROM (
    SELECT w.id
    FROM public.wallets w
    LEFT JOIN public.wallet_ledger l ON l.wallet_id = w.id
    GROUP BY w.id, w.balance
    HAVING w.balance <> COALESCE(SUM(CASE WHEN l.direction='credit' THEN l.amount ELSE -l.amount END),0)
  ) s;

  -- Record the batch in audit_logs
  INSERT INTO public.audit_logs (actor_id, actor_email, action, entity_type, entity_id, metadata)
  VALUES (
    NULL, 'system@migration', 'wallet_reconciliation_batch', 'wallet_ledger', NULL,
    jsonb_build_object(
      'batch_id', v_batch_id,
      'wallets_scanned_mismatched', v_scanned,
      'entries_created', v_created,
      'entries_skipped_idempotent', v_skipped,
      'mismatches_before', v_before_mismatch,
      'mismatches_after', v_after_mismatch
    )
  );

  IF v_after_mismatch <> 0 THEN
    RAISE EXCEPTION 'Reconciliation failed: % wallets remain unbalanced', v_after_mismatch;
  END IF;
END $$;
