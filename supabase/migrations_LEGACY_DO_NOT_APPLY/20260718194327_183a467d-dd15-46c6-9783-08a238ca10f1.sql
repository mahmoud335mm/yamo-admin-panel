
-- =========================================================================
-- PART A: Double-entry system accounts + backfill of legacy reconciliation
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.system_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  account_type text NOT NULL, -- 'liability' | 'asset' | 'equity' | 'revenue' | 'expense'
  currency text,              -- NULL = multi-currency / coin-side
  is_system boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.system_accounts TO authenticated;
GRANT ALL ON public.system_accounts TO service_role;
ALTER TABLE public.system_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "system_accounts_read_admin" ON public.system_accounts FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'audit_logs.read') OR public.has_permission(auth.uid(), 'recharge_refunds.read'));

CREATE TABLE IF NOT EXISTS public.system_ledger (
  id bigserial PRIMARY KEY,
  system_account_id uuid NOT NULL REFERENCES public.system_accounts(id),
  direction text NOT NULL CHECK (direction IN ('debit','credit')),
  amount numeric(30,6) NOT NULL CHECK (amount > 0),
  currency text,                          -- NULL for coin/diamond/bonus accounts
  asset_class text NOT NULL,              -- 'coins' | 'bonus' | 'diamonds' | 'cash'
  reference text,                         -- pairs with wallet_ledger.reference or refund_reference
  batch_reference text,                   -- pairs to a batch (reconciliation batch, refund id, etc.)
  paired_user_ledger_id bigint,           -- optional FK to wallet_ledger.id
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (system_account_id, reference, direction, asset_class)
);
CREATE INDEX IF NOT EXISTS system_ledger_batch_idx ON public.system_ledger(batch_reference);
CREATE INDEX IF NOT EXISTS system_ledger_reference_idx ON public.system_ledger(reference);
CREATE INDEX IF NOT EXISTS system_ledger_paired_idx ON public.system_ledger(paired_user_ledger_id);

GRANT SELECT ON public.system_ledger TO authenticated;
GRANT ALL ON public.system_ledger TO service_role;
ALTER TABLE public.system_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "system_ledger_read_admin" ON public.system_ledger FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'audit_logs.read') OR public.has_permission(auth.uid(), 'recharge_refunds.read'));
-- Append-only, no user UPDATE/DELETE
CREATE POLICY "system_ledger_deny_update" ON public.system_ledger AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY "system_ledger_deny_delete" ON public.system_ledger AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

-- Seed standing accounts
INSERT INTO public.system_accounts (code, name, account_type, currency) VALUES
  ('legacy_opening_balance', 'Legacy Opening Balance (pre-5B seed)', 'equity', NULL),
  ('treasury_coins',         'Treasury — Coins Issued to Users',    'liability', NULL),
  ('treasury_bonus',         'Treasury — Bonus Coins Issued',       'liability', NULL),
  ('treasury_diamonds',      'Treasury — Diamonds Issued',          'liability', NULL),
  ('refund_clearing',        'Refund Clearing (in-flight refunds)', 'liability', NULL),
  ('refund_unrecovered',     'Refund Unrecovered (write-off / receivable)', 'asset', NULL)
ON CONFLICT (code) DO NOTHING;

-- Backfill counter-entries for the legacy reconciliation batch.
-- For each existing user-side CREDIT with reference 'legacy_seed_reconciliation_%',
-- insert a matching DEBIT on 'legacy_opening_balance'.
INSERT INTO public.system_ledger (system_account_id, direction, amount, currency, asset_class, reference, batch_reference, paired_user_ledger_id, metadata)
SELECT
  (SELECT id FROM public.system_accounts WHERE code = 'legacy_opening_balance'),
  'debit',
  wl.amount::numeric,
  NULL,
  wl.account::text,
  wl.reference,
  'legacy_seed_reconciliation_2026_07_18',
  wl.id,
  jsonb_build_object(
    'source','opening_balance_double_entry_fix',
    'paired_wallet_ledger_id', wl.id,
    'note','Counter-entry to make legacy opening-balance reconciliation double-entry compliant. No wallet balances were altered.'
  )
FROM public.wallet_ledger wl
WHERE wl.reference LIKE 'legacy_seed_reconciliation_2026_07_18:%'
  AND wl.metadata->>'source' = 'opening_balance_reconciliation'
ON CONFLICT DO NOTHING;

-- =========================================================================
-- PART B: refund_policies
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.refund_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  country_code text,
  currency_code text,
  gateway_id uuid REFERENCES public.payment_gateways(id) ON DELETE SET NULL,
  refund_type_scope text[] NOT NULL DEFAULT ARRAY['full','partial'],
  refund_window_days integer NOT NULL DEFAULT 30 CHECK (refund_window_days > 0),
  single_approval_threshold numeric(30,6) NOT NULL DEFAULT 100 CHECK (single_approval_threshold >= 0),
  second_approval_threshold numeric(30,6) NOT NULL DEFAULT 500 CHECK (second_approval_threshold > 0),
  allow_partial_refund boolean NOT NULL DEFAULT true,
  partial_bonus_policy text NOT NULL DEFAULT 'proportional'
    CHECK (partial_bonus_policy IN ('proportional','reverse_bonus_first','keep_bonus','full_bonus_reversal')),
  insufficient_balance_policy text NOT NULL DEFAULT 'manual_review_before_gateway_refund'
    CHECK (insufficient_balance_policy IN (
      'block_before_gateway_refund',
      'manual_review_before_gateway_refund',
      'recover_available_and_create_receivable',
      'money_only_with_override'
    )),
  require_wallet_reversal_before_gateway_refund boolean NOT NULL DEFAULT false,
  allow_money_only_refund boolean NOT NULL DEFAULT true,
  rounding_mode text NOT NULL DEFAULT 'half_even' CHECK (rounding_mode IN ('half_even','half_up','floor','ceil')),
  decimal_scale integer NOT NULL DEFAULT 2 CHECK (decimal_scale BETWEEN 0 AND 8),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived','draft')),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  version integer NOT NULL DEFAULT 1,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS refund_policies_lookup_idx
  ON public.refund_policies(country_code, currency_code, gateway_id, status);

GRANT SELECT ON public.refund_policies TO authenticated;
GRANT ALL ON public.refund_policies TO service_role;
ALTER TABLE public.refund_policies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "refund_policies_read_admin" ON public.refund_policies FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'recharge_refunds.read'));
CREATE POLICY "refund_policies_write_admin" ON public.refund_policies FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(), 'system_settings.write'))
  WITH CHECK (public.has_permission(auth.uid(), 'system_settings.write'));

INSERT INTO public.refund_policies (name, country_code, currency_code, gateway_id, single_approval_threshold, second_approval_threshold, insufficient_balance_policy)
VALUES ('Default global refund policy', NULL, NULL, NULL, 100, 500, 'manual_review_before_gateway_refund')
ON CONFLICT DO NOTHING;

-- =========================================================================
-- PART C: Internal helpers
-- =========================================================================

-- Policy lookup: most specific match wins (gateway > currency > country > global)
CREATE OR REPLACE FUNCTION public._lookup_refund_policy(
  _country text, _currency text, _gateway_id uuid
) RETURNS public.refund_policies LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.refund_policies
  WHERE status = 'active'
    AND (starts_at IS NULL OR starts_at <= now())
    AND (ends_at   IS NULL OR ends_at   >  now())
    AND (gateway_id IS NULL OR gateway_id = _gateway_id)
    AND (currency_code IS NULL OR currency_code = _currency)
    AND (country_code  IS NULL OR country_code  = _country)
  ORDER BY
    (gateway_id IS NOT NULL)::int DESC,
    (currency_code IS NOT NULL)::int DESC,
    (country_code  IS NOT NULL)::int DESC,
    version DESC,
    created_at DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._lookup_refund_policy(text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._lookup_refund_policy(text, text, uuid) TO authenticated, service_role;

-- Preflight calculator (used by preview + all lifecycle RPCs)
CREATE OR REPLACE FUNCTION public._refund_preflight_calc(
  _recharge_request_id uuid,
  _refund_type text,
  _refund_scope text,
  _requested_amount numeric,
  _bonus_policy_override text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rr public.recharge_requests;
  pol public.refund_policies;
  bonus_policy text;
  already_refunded numeric := 0;
  remaining_refundable numeric;
  ratio numeric;
  base_coins bigint := 0;
  bonus_coins bigint := 0;
  base_reverse bigint := 0;
  bonus_reverse bigint := 0;
  avail_coins bigint := 0;
  avail_bonus bigint := 0;
  recover_base bigint := 0;
  recover_bonus bigint := 0;
  unrec_base bigint := 0;
  unrec_bonus bigint := 0;
  requires_second boolean;
  applicable_threshold numeric;
  blocking text[] := ARRAY[]::text[];
  warnings text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO rr FROM public.recharge_requests WHERE id = _recharge_request_id;
  IF rr.id IS NULL THEN RAISE EXCEPTION 'RECHARGE_NOT_FOUND'; END IF;

  SELECT * INTO pol FROM public._lookup_refund_policy(rr.country_code, rr.currency_code, rr.payment_gateway_id);
  IF pol.id IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_REFUND_POLICY'; END IF;

  bonus_policy := COALESCE(_bonus_policy_override, pol.partial_bonus_policy);

  -- Sum of previous refunds not in terminal-failed states
  SELECT COALESCE(SUM(rf.approved_amount),0) INTO already_refunded
  FROM public.recharge_refunds rf
  WHERE rf.request_id = _recharge_request_id
    AND rf.status IN ('approved','processing_gateway','gateway_confirmed','reversing_wallet','completed','partially_completed','manual_review');

  remaining_refundable := rr.final_amount - already_refunded;

  -- Cap request
  IF _refund_type = 'full' THEN
    _requested_amount := remaining_refundable;
  ELSIF _requested_amount IS NULL OR _requested_amount <= 0 THEN
    blocking := blocking || 'INVALID_AMOUNT';
  ELSIF _requested_amount > remaining_refundable THEN
    blocking := blocking || 'AMOUNT_EXCEEDS_REMAINING';
  END IF;

  -- Refund window
  IF rr.completed_at IS NULL THEN
    blocking := blocking || 'RECHARGE_NOT_COMPLETED';
  ELSIF rr.completed_at + (pol.refund_window_days || ' days')::interval < now() THEN
    warnings := warnings || 'OUTSIDE_REFUND_WINDOW';
  END IF;

  ratio := CASE WHEN rr.final_amount > 0 THEN _requested_amount / rr.final_amount ELSE 0 END;
  base_coins  := COALESCE(rr.coin_amount, 0);
  bonus_coins := COALESCE(rr.bonus_amount, 0);

  IF _refund_scope IN ('money_only','administrative_compensation','technical_failure') THEN
    base_reverse := 0;
    bonus_reverse := 0;
  ELSIF _refund_scope = 'money_and_base_coins' THEN
    base_reverse := floor(base_coins * ratio)::bigint;
    IF bonus_policy = 'full_bonus_reversal' THEN
      bonus_reverse := bonus_coins;
    ELSIF bonus_policy = 'keep_bonus' THEN
      bonus_reverse := 0;
    ELSE
      bonus_reverse := 0;
    END IF;
  ELSE -- money_and_all_coins
    base_reverse := floor(base_coins * ratio)::bigint;
    bonus_reverse := CASE
      WHEN bonus_policy = 'proportional'         THEN floor(bonus_coins * ratio)::bigint
      WHEN bonus_policy = 'reverse_bonus_first'  THEN LEAST(bonus_coins, ceil(bonus_coins * ratio)::bigint)
      WHEN bonus_policy = 'keep_bonus'           THEN 0
      WHEN bonus_policy = 'full_bonus_reversal'  THEN bonus_coins
      ELSE floor(bonus_coins * ratio)::bigint
    END;
  END IF;

  -- User current balances
  SELECT COALESCE(balance,0) INTO avail_coins  FROM public.wallets WHERE user_id = rr.user_id AND account = 'coins';
  SELECT COALESCE(balance,0) INTO avail_bonus  FROM public.wallets WHERE user_id = rr.user_id AND account = 'bonus';

  recover_base  := LEAST(avail_coins, base_reverse);
  recover_bonus := LEAST(avail_bonus, bonus_reverse);
  unrec_base    := base_reverse - recover_base;
  unrec_bonus   := bonus_reverse - recover_bonus;

  IF unrec_base > 0 OR unrec_bonus > 0 THEN
    IF pol.insufficient_balance_policy = 'block_before_gateway_refund' THEN
      blocking := blocking || 'INSUFFICIENT_COIN_BALANCE';
    ELSIF pol.insufficient_balance_policy = 'manual_review_before_gateway_refund' THEN
      warnings := warnings || 'INSUFFICIENT_COIN_BALANCE_MANUAL_REVIEW';
    END IF;
  END IF;

  applicable_threshold := pol.second_approval_threshold;
  requires_second := (_requested_amount >= pol.second_approval_threshold);

  RETURN jsonb_build_object(
    'recharge_request_id', rr.id,
    'user_id', rr.user_id,
    'original_paid_amount', rr.final_amount,
    'already_refunded_amount', already_refunded,
    'remaining_refundable_amount', remaining_refundable,
    'requested_amount', _requested_amount,
    'currency', rr.currency_code,
    'refund_ratio', ratio,
    'original_base_coins', base_coins,
    'original_bonus_coins', bonus_coins,
    'base_coins_to_reverse', base_reverse,
    'bonus_coins_to_reverse', bonus_reverse,
    'user_available_coins', avail_coins,
    'user_available_bonus', avail_bonus,
    'recoverable_base_coins', recover_base,
    'recoverable_bonus_coins', recover_bonus,
    'unrecovered_base_coins', unrec_base,
    'unrecovered_bonus_coins', unrec_bonus,
    'requires_second_approval', requires_second,
    'applicable_threshold', applicable_threshold,
    'applicable_policy_id', pol.id,
    'bonus_policy', bonus_policy,
    'insufficient_balance_policy', pol.insufficient_balance_policy,
    'can_execute_automatically', (cardinality(blocking) = 0 AND unrec_base = 0 AND unrec_bonus = 0),
    'blocking_reasons', to_jsonb(blocking),
    'warnings', to_jsonb(warnings),
    'rounding_details', jsonb_build_object('mode', pol.rounding_mode, 'scale', pol.decimal_scale)
  );
END $$;
REVOKE ALL ON FUNCTION public._refund_preflight_calc(uuid, text, text, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._refund_preflight_calc(uuid, text, text, numeric, text) TO authenticated, service_role;

-- =========================================================================
-- PART D: Public preview RPC
-- =========================================================================

CREATE OR REPLACE FUNCTION public.preview_recharge_refund(
  _recharge_request_id uuid,
  _refund_type refund_type,
  _refund_scope refund_scope,
  _requested_amount numeric DEFAULT NULL,
  _bonus_policy text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.has_permission(auth.uid(), 'recharge_refunds.read') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN public._refund_preflight_calc(_recharge_request_id, _refund_type::text, _refund_scope::text, _requested_amount, _bonus_policy);
END $$;
REVOKE ALL ON FUNCTION public.preview_recharge_refund(uuid, refund_type, refund_scope, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.preview_recharge_refund(uuid, refund_type, refund_scope, numeric, text) TO authenticated;

-- =========================================================================
-- PART E: Refund lifecycle RPCs
-- =========================================================================

-- REQUEST
CREATE OR REPLACE FUNCTION public.request_recharge_refund(
  _recharge_request_id uuid,
  _refund_type refund_type,
  _refund_scope refund_scope,
  _requested_amount numeric,
  _bonus_policy text,
  _reason text,
  _idempotency_key text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  actor uuid := auth.uid();
  rr public.recharge_requests;
  pre jsonb;
  new_id uuid;
  ref text;
  existing uuid;
BEGIN
  IF NOT public.has_permission(actor, 'recharge_refunds.request') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT'; END IF;
  IF _idempotency_key IS NULL OR length(_idempotency_key) < 8 THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_TOO_SHORT'; END IF;

  -- Idempotency
  SELECT id INTO existing FROM public.recharge_refunds
    WHERE request_id = _recharge_request_id AND idempotency_key = _idempotency_key LIMIT 1;
  IF existing IS NOT NULL THEN RETURN existing; END IF;

  SELECT * INTO rr FROM public.recharge_requests WHERE id = _recharge_request_id FOR UPDATE;
  IF rr.id IS NULL THEN RAISE EXCEPTION 'RECHARGE_NOT_FOUND'; END IF;
  IF rr.status <> 'completed' THEN RAISE EXCEPTION 'RECHARGE_NOT_COMPLETED'; END IF;

  pre := public._refund_preflight_calc(_recharge_request_id, _refund_type::text, _refund_scope::text, _requested_amount, _bonus_policy);
  IF jsonb_array_length(pre->'blocking_reasons') > 0 THEN
    RAISE EXCEPTION 'PREFLIGHT_BLOCKED: %', pre->'blocking_reasons';
  END IF;

  ref := 'RF-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,10);

  INSERT INTO public.recharge_refunds(
    request_id, user_id, refund_type, refund_scope,
    requested_amount, approved_amount, amount,
    base_coins_to_reverse, bonus_coins_to_reverse,
    requires_second_approval, threshold_rule_id,
    bonus_policy_snapshot, refund_reference,
    reason, decision_reason, idempotency_key,
    requested_by, status, currency_code,
    gateway_id, payment_method_id, original_payment_reference,
    metadata
  ) VALUES (
    _recharge_request_id, rr.user_id, _refund_type, _refund_scope,
    (pre->>'requested_amount')::numeric,
    (pre->>'requested_amount')::numeric,
    (pre->>'requested_amount')::numeric,
    (pre->>'base_coins_to_reverse')::bigint,
    (pre->>'bonus_coins_to_reverse')::bigint,
    (pre->>'requires_second_approval')::boolean,
    (pre->>'applicable_policy_id')::uuid,
    pre->>'bonus_policy',
    ref,
    _reason, _reason, _idempotency_key,
    actor, 'pending_review', rr.currency_code,
    rr.payment_gateway_id, rr.payment_method_id, rr.provider_payment_id,
    jsonb_build_object('preflight_snapshot', pre)
  ) RETURNING id INTO new_id;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, 'refund_requested', 'recharge_refund', new_id,
            jsonb_build_object('refund_reference', ref, 'preflight', pre, 'reason', _reason));

  RETURN new_id;
END $$;
REVOKE ALL ON FUNCTION public.request_recharge_refund(uuid, refund_type, refund_scope, numeric, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_recharge_refund(uuid, refund_type, refund_scope, numeric, text, text, text) TO authenticated;

-- REVIEW (approve/reject/request_changes/move_to_manual_review)
CREATE OR REPLACE FUNCTION public.review_recharge_refund(
  _refund_id uuid, _decision text, _reason text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  actor uuid := auth.uid();
  rf public.recharge_refunds;
  pre jsonb;
BEGIN
  IF NOT public.has_permission(actor, 'recharge_refunds.review') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT'; END IF;
  SELECT * INTO rf FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF rf.id IS NULL THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;

  pre := public._refund_preflight_calc(rf.request_id, rf.refund_type::text, rf.refund_scope::text, rf.approved_amount, rf.bonus_policy_snapshot);

  IF _decision = 'approve' THEN
    PERFORM public.approve_recharge_refund(_refund_id, _reason);
  ELSIF _decision = 'reject' THEN
    PERFORM public.reject_recharge_refund(_refund_id, _reason);
  ELSIF _decision = 'move_to_manual_review' THEN
    UPDATE public.recharge_refunds SET status='manual_review', updated_at=now(),
      metadata = metadata || jsonb_build_object('manual_review_by', actor, 'manual_review_reason', _reason, 'preflight_at_review', pre)
      WHERE id = _refund_id;
  ELSIF _decision = 'request_changes' THEN
    UPDATE public.recharge_refunds SET status='requested', updated_at=now(),
      metadata = metadata || jsonb_build_object('changes_requested_by', actor, 'changes_reason', _reason)
      WHERE id = _refund_id;
  ELSE
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, 'refund_reviewed', 'recharge_refund', _refund_id,
            jsonb_build_object('decision', _decision, 'reason', _reason, 'preflight_at_review', pre));
END $$;
REVOKE ALL ON FUNCTION public.review_recharge_refund(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_recharge_refund(uuid, text, text) TO authenticated;

-- APPROVE (first approval)
CREATE OR REPLACE FUNCTION public.approve_recharge_refund(
  _refund_id uuid, _reason text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  actor uuid := auth.uid();
  rf public.recharge_refunds;
  next_status refund_status;
BEGIN
  IF NOT public.has_permission(actor, 'recharge_refunds.approve') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT'; END IF;
  SELECT * INTO rf FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF rf.id IS NULL THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;
  IF rf.requested_by = actor THEN RAISE EXCEPTION 'SELF_APPROVAL_NOT_ALLOWED'; END IF;
  IF rf.status <> 'pending_review' THEN RAISE EXCEPTION 'INVALID_STATE %', rf.status; END IF;

  next_status := CASE WHEN rf.requires_second_approval THEN 'pending_second_review'::refund_status ELSE 'approved'::refund_status END;

  UPDATE public.recharge_refunds
     SET status = next_status,
         first_reviewed_by = actor,
         first_reviewed_at = now(),
         approved_by = CASE WHEN NOT rf.requires_second_approval THEN actor ELSE approved_by END,
         approved_at = CASE WHEN NOT rf.requires_second_approval THEN now()  ELSE approved_at END,
         decision_reason = _reason,
         updated_at = now()
   WHERE id = _refund_id;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, 'refund_first_approved', 'recharge_refund', _refund_id,
            jsonb_build_object('reason', _reason, 'next_status', next_status));
END $$;
REVOKE ALL ON FUNCTION public.approve_recharge_refund(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_recharge_refund(uuid, text) TO authenticated;

-- SECOND APPROVE
CREATE OR REPLACE FUNCTION public.second_approve_recharge_refund(
  _refund_id uuid, _reason text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  actor uuid := auth.uid();
  rf public.recharge_refunds;
  pre jsonb;
BEGIN
  IF NOT public.has_permission(actor, 'recharge_refunds.second_approve') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT'; END IF;
  SELECT * INTO rf FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF rf.id IS NULL THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;
  IF rf.status <> 'pending_second_review' THEN RAISE EXCEPTION 'INVALID_STATE %', rf.status; END IF;
  IF actor = rf.requested_by THEN RAISE EXCEPTION 'SELF_APPROVAL_NOT_ALLOWED'; END IF;
  IF actor = rf.first_reviewed_by THEN RAISE EXCEPTION 'SECOND_REVIEWER_MUST_DIFFER'; END IF;

  pre := public._refund_preflight_calc(rf.request_id, rf.refund_type::text, rf.refund_scope::text, rf.approved_amount, rf.bonus_policy_snapshot);

  UPDATE public.recharge_refunds
     SET status = 'approved',
         second_reviewed_by = actor,
         second_reviewed_at = now(),
         approved_by = actor,
         approved_at = now(),
         updated_at  = now(),
         metadata = metadata || jsonb_build_object('preflight_at_second_approval', pre)
   WHERE id = _refund_id;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, 'refund_second_approved', 'recharge_refund', _refund_id,
            jsonb_build_object('reason', _reason, 'preflight', pre));
END $$;
REVOKE ALL ON FUNCTION public.second_approve_recharge_refund(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.second_approve_recharge_refund(uuid, text) TO authenticated;

-- REJECT
CREATE OR REPLACE FUNCTION public.reject_recharge_refund(
  _refund_id uuid, _reason text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  actor uuid := auth.uid();
  rf public.recharge_refunds;
BEGIN
  IF NOT public.has_permission(actor, 'recharge_refunds.reject') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT'; END IF;
  SELECT * INTO rf FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF rf.id IS NULL THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;
  IF rf.status NOT IN ('requested','pending_review','pending_second_review','manual_review') THEN
    RAISE EXCEPTION 'INVALID_STATE %', rf.status;
  END IF;

  UPDATE public.recharge_refunds
     SET status = 'rejected', rejected_by = actor, rejected_at = now(),
         decision_reason = _reason, updated_at = now()
   WHERE id = _refund_id;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, 'refund_rejected', 'recharge_refund', _refund_id, jsonb_build_object('reason', _reason));
END $$;
REVOKE ALL ON FUNCTION public.reject_recharge_refund(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_recharge_refund(uuid, text) TO authenticated;

-- CANCEL
CREATE OR REPLACE FUNCTION public.cancel_recharge_refund(
  _refund_id uuid, _reason text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  actor uuid := auth.uid();
  rf public.recharge_refunds;
BEGIN
  IF NOT public.has_permission(actor, 'recharge_refunds.cancel') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT'; END IF;
  SELECT * INTO rf FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF rf.id IS NULL THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;
  IF rf.status NOT IN ('requested','pending_review','pending_second_review','approved') THEN
    RAISE EXCEPTION 'CANNOT_CANCEL_AFTER_EXECUTION %', rf.status;
  END IF;

  UPDATE public.recharge_refunds
     SET status = 'cancelled', decision_reason = _reason, updated_at = now()
   WHERE id = _refund_id;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, 'refund_cancelled', 'recharge_refund', _refund_id, jsonb_build_object('reason', _reason));
END $$;
REVOKE ALL ON FUNCTION public.cancel_recharge_refund(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_recharge_refund(uuid, text) TO authenticated;

-- =========================================================================
-- PART F: Wallet reversal internal helper
-- =========================================================================

CREATE OR REPLACE FUNCTION public._apply_recharge_refund_wallet_reversal(
  _refund_id uuid,
  _execution_reference text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rf public.recharge_refunds;
  w_coins public.wallets;
  w_bonus public.wallets;
  base_reverse bigint;
  bonus_reverse bigint;
  actual_base bigint := 0;
  actual_bonus bigint := 0;
  unrec_base bigint := 0;
  unrec_bonus bigint := 0;
  new_ledger_id bigint;
BEGIN
  SELECT * INTO rf FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF rf.id IS NULL THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;

  base_reverse := COALESCE(rf.base_coins_to_reverse, 0);
  bonus_reverse := COALESCE(rf.bonus_coins_to_reverse, 0);

  -- Idempotency: if already applied, no-op
  IF EXISTS (SELECT 1 FROM public.wallet_ledger
             WHERE reference = _execution_reference AND reason = 'recharge_refund') THEN
    RETURN jsonb_build_object('idempotent', true);
  END IF;

  -- Lock wallets
  IF base_reverse > 0 THEN
    SELECT * INTO w_coins FROM public.wallets WHERE user_id = rf.user_id AND account='coins' FOR UPDATE;
    IF w_coins.id IS NULL THEN RAISE EXCEPTION 'WALLET_MISSING_COINS'; END IF;
    actual_base := LEAST(w_coins.balance, base_reverse);
    unrec_base := base_reverse - actual_base;

    IF actual_base > 0 THEN
      UPDATE public.wallets SET balance = balance - actual_base, updated_at = now() WHERE id = w_coins.id;
      INSERT INTO public.wallet_ledger(wallet_id, user_id, account, direction, reason, amount, balance_after, reference, metadata)
      VALUES (w_coins.id, rf.user_id, 'coins', 'debit', 'recharge_refund', actual_base, w_coins.balance - actual_base, _execution_reference,
              jsonb_build_object('refund_id', rf.id, 'refund_reference', rf.refund_reference, 'kind', 'base_reversal'))
      RETURNING id INTO new_ledger_id;

      INSERT INTO public.system_ledger(system_account_id, direction, amount, asset_class, reference, batch_reference, paired_user_ledger_id, metadata)
      VALUES ((SELECT id FROM public.system_accounts WHERE code='treasury_coins'),
              'credit', actual_base, 'coins', _execution_reference, rf.refund_reference::text, new_ledger_id,
              jsonb_build_object('refund_id', rf.id, 'kind', 'base_reversal_counter'));
    END IF;
  END IF;

  IF bonus_reverse > 0 THEN
    SELECT * INTO w_bonus FROM public.wallets WHERE user_id = rf.user_id AND account='bonus' FOR UPDATE;
    IF w_bonus.id IS NOT NULL THEN
      actual_bonus := LEAST(w_bonus.balance, bonus_reverse);
      unrec_bonus := bonus_reverse - actual_bonus;
      IF actual_bonus > 0 THEN
        UPDATE public.wallets SET balance = balance - actual_bonus, updated_at = now() WHERE id = w_bonus.id;
        INSERT INTO public.wallet_ledger(wallet_id, user_id, account, direction, reason, amount, balance_after, reference, metadata)
        VALUES (w_bonus.id, rf.user_id, 'bonus', 'debit', 'recharge_refund', actual_bonus, w_bonus.balance - actual_bonus, _execution_reference,
                jsonb_build_object('refund_id', rf.id, 'refund_reference', rf.refund_reference, 'kind', 'bonus_reversal'))
        RETURNING id INTO new_ledger_id;

        INSERT INTO public.system_ledger(system_account_id, direction, amount, asset_class, reference, batch_reference, paired_user_ledger_id, metadata)
        VALUES ((SELECT id FROM public.system_accounts WHERE code='treasury_bonus'),
                'credit', actual_bonus, 'bonus', _execution_reference, rf.refund_reference::text, new_ledger_id,
                jsonb_build_object('refund_id', rf.id, 'kind', 'bonus_reversal_counter'));
      END IF;
    ELSE
      unrec_bonus := bonus_reverse;
    END IF;
  END IF;

  UPDATE public.recharge_refunds
     SET coins_actually_reversed = actual_base,
         bonus_actually_reversed = actual_bonus,
         unrecovered_coin_amount = unrec_base,
         unrecovered_bonus_amount = unrec_bonus,
         updated_at = now()
   WHERE id = _refund_id;

  RETURN jsonb_build_object(
    'base_reversed', actual_base, 'bonus_reversed', actual_bonus,
    'unrecovered_base', unrec_base, 'unrecovered_bonus', unrec_bonus
  );
END $$;
REVOKE ALL ON FUNCTION public._apply_recharge_refund_wallet_reversal(uuid, text) FROM PUBLIC;
-- Only service_role and internal callers may execute; NOT granted to authenticated.
GRANT EXECUTE ON FUNCTION public._apply_recharge_refund_wallet_reversal(uuid, text) TO service_role;

-- =========================================================================
-- PART G: EXECUTE RPC (orchestrates gateway + wallet reversal)
-- =========================================================================

CREATE OR REPLACE FUNCTION public.execute_recharge_refund(
  _refund_id uuid,
  _reason text,
  _idempotency_key text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  actor uuid := auth.uid();
  rf public.recharge_refunds;
  pre jsonb;
  pol public.refund_policies;
  reversal_result jsonb;
  exec_ref text;
  final_status refund_status;
BEGIN
  IF NOT public.has_permission(actor, 'recharge_refunds.execute') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF _reason IS NULL OR length(btrim(_reason)) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT'; END IF;
  IF _idempotency_key IS NULL OR length(_idempotency_key) < 8 THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_TOO_SHORT'; END IF;

  SELECT * INTO rf FROM public.recharge_refunds WHERE id = _refund_id FOR UPDATE;
  IF rf.id IS NULL THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;
  IF rf.status = 'completed' OR rf.status = 'partially_completed' THEN
    RETURN jsonb_build_object('idempotent', true, 'status', rf.status);
  END IF;
  IF rf.status <> 'approved' THEN RAISE EXCEPTION 'INVALID_STATE %', rf.status; END IF;
  IF actor = rf.requested_by THEN RAISE EXCEPTION 'EXECUTOR_SEPARATION_REQUIRED'; END IF;

  -- Re-run preflight
  pre := public._refund_preflight_calc(rf.request_id, rf.refund_type::text, rf.refund_scope::text, rf.approved_amount, rf.bonus_policy_snapshot);
  SELECT * INTO pol FROM public.refund_policies WHERE id = (pre->>'applicable_policy_id')::uuid;

  IF jsonb_array_length(pre->'blocking_reasons') > 0 THEN
    UPDATE public.recharge_refunds SET status='manual_review', updated_at=now(),
      metadata = metadata || jsonb_build_object('execute_blocked_preflight', pre) WHERE id = _refund_id;
    INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
      VALUES (actor, 'refund_manual_review', 'recharge_refund', _refund_id, jsonb_build_object('reason','preflight_blocked','preflight',pre));
    RETURN jsonb_build_object('status','manual_review','preflight',pre);
  END IF;

  -- Insufficient balance manual-review gate
  IF ((pre->>'unrecovered_base_coins')::bigint > 0 OR (pre->>'unrecovered_bonus_coins')::bigint > 0)
     AND pol.insufficient_balance_policy IN ('block_before_gateway_refund','manual_review_before_gateway_refund') THEN
    UPDATE public.recharge_refunds SET status='manual_review', updated_at=now(),
      unrecovered_coin_amount = (pre->>'unrecovered_base_coins')::bigint,
      unrecovered_bonus_amount = (pre->>'unrecovered_bonus_coins')::bigint,
      metadata = metadata || jsonb_build_object('insufficient_balance_at_execute', pre) WHERE id = _refund_id;
    INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
      VALUES (actor, 'refund_manual_review', 'recharge_refund', _refund_id, jsonb_build_object('reason','insufficient_balance','preflight',pre));
    RETURN jsonb_build_object('status','manual_review','preflight',pre);
  END IF;

  exec_ref := 'rfx:' || rf.refund_reference || ':' || _idempotency_key;

  -- Gateway step (mock: synchronous success; a real gateway would set processing_gateway then wait for webhook)
  UPDATE public.recharge_refunds
     SET status='processing_gateway', executed_by = actor, executed_at = now(),
         provider_refund_id = COALESCE(provider_refund_id, 'MOCK-' || rf.refund_reference),
         updated_at = now()
   WHERE id = _refund_id;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, 'refund_gateway_started', 'recharge_refund', _refund_id,
            jsonb_build_object('provider_refund_id', 'MOCK-' || rf.refund_reference, 'reason', _reason));

  -- Confirm (mock synchronous path)
  UPDATE public.recharge_refunds SET status='gateway_confirmed', updated_at=now() WHERE id = _refund_id;
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, 'refund_gateway_confirmed', 'recharge_refund', _refund_id, jsonb_build_object());

  -- Wallet reversal
  UPDATE public.recharge_refunds SET status='reversing_wallet', updated_at=now() WHERE id = _refund_id;
  reversal_result := public._apply_recharge_refund_wallet_reversal(_refund_id, exec_ref);

  final_status := CASE
    WHEN ((reversal_result->>'unrecovered_base')::bigint > 0 OR (reversal_result->>'unrecovered_bonus')::bigint > 0)
      THEN 'partially_completed'::refund_status
    ELSE 'completed'::refund_status
  END;

  UPDATE public.recharge_refunds SET status = final_status, updated_at = now() WHERE id = _refund_id;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    VALUES (actor, CASE WHEN final_status='completed' THEN 'refund_completed' ELSE 'refund_partial' END,
            'recharge_refund', _refund_id, jsonb_build_object('reversal', reversal_result, 'preflight', pre));

  RETURN jsonb_build_object('status', final_status, 'reversal', reversal_result, 'preflight', pre);
END $$;
REVOKE ALL ON FUNCTION public.execute_recharge_refund(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.execute_recharge_refund(uuid, text, text) TO authenticated;

-- =========================================================================
-- PART H: recharge_refunds read policy (owner + admin)
-- =========================================================================

DROP POLICY IF EXISTS "recharge_refunds_owner_read" ON public.recharge_refunds;
CREATE POLICY "recharge_refunds_owner_read" ON public.recharge_refunds
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_permission(auth.uid(), 'recharge_refunds.read'));
