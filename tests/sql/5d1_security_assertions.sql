-- Phase 5D-1 SQL Security Assertions
-- Run with: psql -f tests/sql/5d1_security_assertions.sql
-- Every SELECT should return zero rows unless labelled otherwise.

\echo '== A1: no PUBLIC EXECUTE on 5D-1 SECURITY DEFINER functions =='
SELECT p.proname
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.prosecdef
  AND has_function_privilege('public', p.oid, 'EXECUTE')
  AND p.proname IN (
    'resolve_recharge_dispute_policy',
    'assert_no_overlapping_recharge_dispute_policies',
    'preview_recharge_dispute_exposure',
    'calculate_recharge_dispute_sla',
    '_dispute_transition_ok'
  );

\echo '== A2: no anon EXECUTE on 5D-1 SECURITY DEFINER functions =='
SELECT p.proname
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
  AND p.proname IN (
    'resolve_recharge_dispute_policy',
    'assert_no_overlapping_recharge_dispute_policies',
    'preview_recharge_dispute_exposure',
    'calculate_recharge_dispute_sla',
    '_dispute_transition_ok'
  );

\echo '== A3: search_path pinned for all 5D-1 functions =='
SELECT p.proname
FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace
  AND p.proname IN (
    'resolve_recharge_dispute_policy','assert_no_overlapping_recharge_dispute_policies',
    'preview_recharge_dispute_exposure','calculate_recharge_dispute_sla',
    '_dispute_transition_ok','tg_recharge_dispute_state_machine')
  AND NOT EXISTS (
    SELECT 1 FROM unnest(coalesce(p.proconfig,'{}'::text[])) x WHERE x LIKE 'search_path=%');

\echo '== A4: RLS enabled on core dispute tables =='
SELECT c.relname FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN ('recharge_disputes','recharge_dispute_notes','recharge_dispute_evidence','recharge_dispute_policies')
  AND NOT c.relrowsecurity;

\echo '== A5: recharge_dispute_notes append-only (no UPDATE/DELETE permissive) =='
SELECT policyname FROM pg_policies
WHERE tablename='recharge_dispute_notes'
  AND cmd IN ('UPDATE','DELETE')
  AND permissive='PERMISSIVE';

\echo '== A6: recharge_dispute_evidence append-only =='
SELECT policyname FROM pg_policies
WHERE tablename='recharge_dispute_evidence'
  AND cmd IN ('UPDATE','DELETE')
  AND permissive='PERMISSIVE';

\echo '== A7: recharge_dispute_policies has restrictive no-write =='
SELECT count(*) AS restrictive_no_write_count
FROM pg_policies
WHERE tablename='recharge_dispute_policies' AND permissive='RESTRICTIVE';
-- expect >= 1

\echo '== A8: two-eyes CHECK exists =='
SELECT conname FROM pg_constraint
WHERE conrelid='public.recharge_disputes'::regclass
  AND conname='chk_disputes_two_eyes_distinct';
-- expect exactly one row

\echo '== A9: provider chargeback composite unique exists =='
SELECT indexname FROM pg_indexes
WHERE tablename='recharge_disputes' AND indexname='uq_disputes_provider_chargeback';
-- expect exactly one row

\echo '== A10: state machine trigger installed =='
SELECT tgname FROM pg_trigger
WHERE tgrelid='public.recharge_disputes'::regclass
  AND tgname='tg_recharge_dispute_state_machine';
-- expect exactly one row

\echo '== A11: transition function rejects known illegal transitions =='
SELECT public._dispute_transition_ok('closed','under_review') AS closed_to_review_should_be_false,
       public._dispute_transition_ok('rejected','resolved_user_favor') AS rejected_to_resolved_should_be_false,
       public._dispute_transition_ok('chargeback_lost','chargeback_contested') AS lost_to_contested_should_be_false,
       public._dispute_transition_ok('resolved_platform_favor','pending_first_decision') AS resolved_to_pending_should_be_false;

\echo '== A12: transition function accepts canonical happy paths =='
SELECT public._dispute_transition_ok('opened','triage') AS ok1,
       public._dispute_transition_ok('under_review','pending_first_decision') AS ok2,
       public._dispute_transition_ok('chargeback_received','chargeback_acknowledged') AS ok3;

\echo '== A13: policy overlap assertion returns 0 rows on empty catalog =='
SELECT * FROM public.assert_no_overlapping_recharge_dispute_policies();

\echo '== A14: feature flags exist and default to false =='
SELECT key, value FROM public.system_settings
WHERE key IN (
  'feature_flags.enable_disputes_admin_ui',
  'feature_flags.enable_user_dispute_submission',
  'feature_flags.enable_chargeback_processing',
  'feature_flags.enable_dispute_financial_resolution',
  'feature_flags.enable_dispute_provisional_actions')
ORDER BY key;
-- all values must be 'false'

\echo '== A15: system_settings is RESTRICTIVE no-write to authenticated =='
SELECT policyname FROM pg_policies
WHERE tablename='system_settings' AND permissive='RESTRICTIVE';
-- expect at least one restrictive policy

\echo '== A16: evidence bucket exists and is private =='
SELECT id, public FROM storage.buckets WHERE id='recharge-dispute-evidence';
-- expect public=false

\echo '== A17: storage RLS restricts evidence bucket update/delete =='
SELECT policyname FROM pg_policies
WHERE schemaname='storage' AND tablename='objects'
  AND policyname IN ('rde_bucket_no_update','rde_bucket_no_delete');
-- expect 2 rows

\echo '== A18: no new refund execution / wallet deduction functions in 5D-1 =='
SELECT p.proname FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace
  AND (p.proname ILIKE '%wallet_reverse%' OR p.proname ILIKE '%execute_refund%')
  AND p.oid > (
    SELECT max(oid) FROM pg_proc
    WHERE proname IN ('resolve_recharge_dispute_policy','preview_recharge_dispute_exposure')
  );
-- expect 0 rows

\echo '== A19: 5C refund feature flags untouched =='
SELECT key, value FROM public.system_settings
WHERE key LIKE 'feature_flags.%refund%' ORDER BY key;
