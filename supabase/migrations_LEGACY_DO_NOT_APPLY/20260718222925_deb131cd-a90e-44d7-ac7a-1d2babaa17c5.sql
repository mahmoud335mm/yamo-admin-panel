
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef AND p.proname IN (
      'create_recharge_dispute','assign_recharge_dispute','triage_recharge_dispute',
      'request_dispute_evidence','add_dispute_internal_note','add_dispute_user_visible_note',
      'redact_dispute_note','submit_dispute_evidence','review_dispute_evidence',
      'review_recharge_dispute','escalate_recharge_dispute',
      'first_decide_recharge_dispute','second_decide_recharge_dispute',
      'resolve_recharge_dispute','reject_recharge_dispute','cancel_recharge_dispute',
      'close_recharge_dispute','reopen_recharge_dispute',
      'acknowledge_chargeback','mark_chargeback_evidence_due',
      'record_chargeback_recommendation','record_manual_chargeback_provider_status'
    )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon', r.proname, r.args);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated', r.proname, r.args);
    INSERT INTO public.security_definer_public_allowlist(function_name, function_args, decision, risk, reason)
    VALUES(r.proname, r.args, 'KEEP','medium','5D-2 dispute lifecycle wrapper: auth.uid() actor, permission-gated, idempotent, no financial exec')
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;
