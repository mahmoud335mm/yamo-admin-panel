
DO $$ BEGIN
  CREATE TYPE public.financial_resolution_status_enum AS ENUM
    ('not_required','pending','blocked','waived','completed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.recharge_disputes
  ADD COLUMN IF NOT EXISTS financial_resolution_status public.financial_resolution_status_enum NOT NULL DEFAULT 'not_required',
  ADD COLUMN IF NOT EXISTS recommended_resolution_amount numeric,
  ADD COLUMN IF NOT EXISTS approved_resolution_amount numeric,
  ADD COLUMN IF NOT EXISTS current_exposure_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS current_exposure_checked_at timestamptz,
  ADD COLUMN IF NOT EXISTS policy_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS threshold_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS parent_dispute_id uuid REFERENCES public.recharge_disputes(id),
  ADD COLUMN IF NOT EXISTS root_dispute_id uuid REFERENCES public.recharge_disputes(id),
  ADD COLUMN IF NOT EXISTS reopen_sequence integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reopened_from_status public.recharge_dispute_status_enum,
  ADD COLUMN IF NOT EXISTS reopen_reason text,
  ADD COLUMN IF NOT EXISTS triaged_by uuid,
  ADD COLUMN IF NOT EXISTS triaged_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejected_by uuid,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_by uuid,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS resolution_version integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_action_idempotency_key text;

ALTER TABLE public.recharge_dispute_evidence
  ADD COLUMN IF NOT EXISTS review_reason text,
  ADD COLUMN IF NOT EXISTS object_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS idempotency_key text;

ALTER TABLE public.recharge_dispute_notes
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS content_hash text,
  ADD COLUMN IF NOT EXISTS redaction_hash text,
  ADD COLUMN IF NOT EXISTS user_delivery_status text;

ALTER TABLE public.recharge_dispute_evidence
  ALTER COLUMN is_quarantined SET DEFAULT true,
  ALTER COLUMN malware_scan_status SET DEFAULT 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS ux_recharge_disputes_reopen_chain
  ON public.recharge_disputes(root_dispute_id, reopen_sequence)
  WHERE root_dispute_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.dispute_action_idempotency (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dispute_id uuid,
  action_type text NOT NULL,
  idempotency_key text NOT NULL,
  actor_id uuid NOT NULL,
  input_hash text NOT NULL,
  result_reference jsonb,
  source_cycle text,
  decision_version integer,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.dispute_action_idempotency TO authenticated;
GRANT ALL ON public.dispute_action_idempotency TO service_role;
ALTER TABLE public.dispute_action_idempotency ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dispute_idem_actor_action_key
  ON public.dispute_action_idempotency(actor_id, action_type, idempotency_key);
CREATE UNIQUE INDEX IF NOT EXISTS ux_dispute_idem_dispute_action_version
  ON public.dispute_action_idempotency(dispute_id, action_type, decision_version)
  WHERE decision_version IS NOT NULL;
DROP POLICY IF EXISTS "idem service role" ON public.dispute_action_idempotency;
CREATE POLICY "idem service role" ON public.dispute_action_idempotency FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "idem read own" ON public.dispute_action_idempotency;
CREATE POLICY "idem read own" ON public.dispute_action_idempotency FOR SELECT TO authenticated USING (actor_id = auth.uid());

INSERT INTO public.permissions (key, module, label_ar, label_en, description) VALUES
  ('recharge_disputes.notes.redact','disputes','إخفاء ملاحظة نزاع','Redact dispute note','Redact but preserve dispute note record'),
  ('recharge_disputes.set_critical_severity','disputes','تعيين خطورة حرجة','Set critical severity','Elevate dispute severity to critical')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.system_settings(key, value) VALUES
  ('feature_flags.enable_disputes_admin_ui','false'),
  ('feature_flags.enable_user_dispute_submission','false'),
  ('feature_flags.enable_chargeback_processing','false'),
  ('feature_flags.enable_dispute_financial_resolution','false'),
  ('feature_flags.enable_dispute_provisional_actions','false')
ON CONFLICT (key) DO NOTHING;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['recharge_disputes','recharge_dispute_notes','recharge_dispute_evidence']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t||'_deny_ins_authn', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t||'_deny_upd_authn', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t||'_deny_del_authn', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false)', t||'_deny_ins_authn', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false)', t||'_deny_upd_authn', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING (false)', t||'_deny_del_authn', t);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public._dispute_assert_actor(_perm text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='42501'; END IF;
  IF NOT public.has_permission(_uid, _perm) THEN
    RAISE EXCEPTION 'FORBIDDEN: missing %', _perm USING ERRCODE='42501';
  END IF;
  RETURN _uid;
END $$;

CREATE OR REPLACE FUNCTION public._dispute_lock(_dispute_id uuid)
RETURNS public.recharge_disputes LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.recharge_disputes;
BEGIN
  SELECT * INTO r FROM public.recharge_disputes WHERE id=_dispute_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DISPUTE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public._dispute_idem_lookup(
  _actor uuid, _action text, _key text, _input_hash text,
  _dispute uuid DEFAULT NULL, _decision_version integer DEFAULT NULL, _source_cycle text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE existing public.dispute_action_idempotency;
BEGIN
  IF _key IS NULL OR length(_key) < 8 THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED' USING ERRCODE='22023'; END IF;
  SELECT * INTO existing FROM public.dispute_action_idempotency
    WHERE actor_id=_actor AND action_type=_action AND idempotency_key=_key FOR UPDATE;
  IF FOUND THEN
    IF existing.input_hash <> _input_hash THEN
      RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_INPUT' USING ERRCODE='22023';
    END IF;
    RETURN existing.result_reference;
  END IF;
  INSERT INTO public.dispute_action_idempotency(
    dispute_id, action_type, idempotency_key, actor_id, input_hash,
    result_reference, decision_version, source_cycle)
  VALUES(_dispute, _action, _key, _actor, _input_hash, NULL, _decision_version, _source_cycle);
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public._dispute_idem_finalize(
  _actor uuid, _action text, _key text, _result jsonb
) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
  UPDATE public.dispute_action_idempotency SET result_reference=_result
    WHERE actor_id=_actor AND action_type=_action AND idempotency_key=_key;
$$;

CREATE OR REPLACE FUNCTION public._dispute_write_audit(
  _actor uuid, _action text, _dispute uuid, _old_status text, _new_status text,
  _reason text, _meta jsonb
) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES(_actor, _action, 'recharge_dispute', _dispute,
    jsonb_strip_nulls(coalesce(_meta,'{}'::jsonb)
      || jsonb_build_object('old_status',_old_status,'new_status',_new_status,'reason',_reason)));
$$;

CREATE OR REPLACE FUNCTION public._dispute_write_outbox(
  _event text, _dispute uuid, _recipient uuid, _key text, _payload jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  INSERT INTO public.transaction_message_outbox(
    event_type, transaction_type, transaction_id, recipient_user_id,
    safe_payload, status, idempotency_key)
  VALUES(_event,'recharge_dispute',_dispute,_recipient, coalesce(_payload,'{}'::jsonb),'pending',_key)
  ON CONFLICT (idempotency_key) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public._dispute_snapshot_exposure(_dispute uuid, _request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE j jsonb;
BEGIN
  SELECT to_jsonb(x) INTO j FROM public.preview_recharge_dispute_exposure(_request,_dispute) x;
  UPDATE public.recharge_disputes SET current_exposure_snapshot=j, current_exposure_checked_at=now() WHERE id=_dispute;
  RETURN j;
END $$;

CREATE OR REPLACE FUNCTION public.record_dispute_evidence_scan_result(
  _evidence_id uuid, _scan_status text, _scanner_reference text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF _scan_status NOT IN ('clean','infected','failed','unavailable') THEN
    RAISE EXCEPTION 'INVALID_SCAN_STATUS' USING ERRCODE='22023';
  END IF;
  UPDATE public.recharge_dispute_evidence
    SET malware_scan_status=_scan_status,
        is_quarantined = CASE WHEN _scan_status='clean' THEN false ELSE true END,
        status = CASE WHEN _scan_status='infected' THEN 'quarantined'::recharge_dispute_evidence_status_enum ELSE status END,
        metadata_safe = coalesce(metadata_safe,'{}'::jsonb) || jsonb_build_object('scanner_reference',_scanner_reference)
    WHERE id=_evidence_id;
END $$;

REVOKE ALL ON FUNCTION
  public._dispute_assert_actor(text),
  public._dispute_lock(uuid),
  public._dispute_idem_lookup(uuid,text,text,text,uuid,integer,text),
  public._dispute_idem_finalize(uuid,text,text,jsonb),
  public._dispute_write_audit(uuid,text,uuid,text,text,text,jsonb),
  public._dispute_write_outbox(text,uuid,uuid,text,jsonb),
  public._dispute_snapshot_exposure(uuid,uuid),
  public.record_dispute_evidence_scan_result(uuid,text,text)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._dispute_assert_transition(
  _current public.recharge_dispute_status_enum, _next public.recharge_dispute_status_enum
) RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,pg_temp AS $$
DECLARE allowed boolean := false;
BEGIN
  allowed := CASE
    WHEN _current=_next THEN true
    WHEN _current='opened' AND _next IN ('triage','awaiting_user_evidence','awaiting_internal_evidence','awaiting_gateway_evidence','under_review','cancelled','rejected') THEN true
    WHEN _current='triage' AND _next IN ('awaiting_user_evidence','awaiting_internal_evidence','awaiting_gateway_evidence','under_review','escalated','cancelled','rejected') THEN true
    WHEN _current IN ('awaiting_user_evidence','awaiting_internal_evidence','awaiting_gateway_evidence')
         AND _next IN ('under_review','triage','escalated','rejected') THEN true
    WHEN _current='under_review' AND _next IN ('awaiting_user_evidence','awaiting_internal_evidence','awaiting_gateway_evidence','escalated','pending_first_decision','rejected') THEN true
    WHEN _current='escalated' AND _next IN ('under_review','pending_first_decision','rejected') THEN true
    WHEN _current='pending_first_decision' AND _next IN ('pending_second_decision','resolved_user_favor','resolved_platform_favor','resolved_partial','rejected') THEN true
    WHEN _current='pending_second_decision' AND _next IN ('resolved_user_favor','resolved_platform_favor','resolved_partial','rejected') THEN true
    WHEN _current IN ('resolved_user_favor','resolved_platform_favor','resolved_partial','rejected','cancelled') AND _next='closed' THEN true
    ELSE false END;
  IF NOT allowed THEN RAISE EXCEPTION 'DISPUTE_ILLEGAL_TRANSITION: % -> %', _current, _next USING ERRCODE='22023'; END IF;
END $$;
REVOKE ALL ON FUNCTION public._dispute_assert_transition(public.recharge_dispute_status_enum, public.recharge_dispute_status_enum) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_recharge_dispute(
  _recharge_request_id uuid, _dispute_type public.recharge_dispute_type_enum,
  _source public.recharge_dispute_source_enum, _title text, _summary text,
  _user_claim text, _reason text, _idempotency_key text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  _actor uuid; _rr public.recharge_requests; _existing jsonb; _dispute_id uuid; _ref text;
  _policy public.recharge_dispute_policies; _input_hash text;
  _active_states public.recharge_dispute_status_enum[] := ARRAY[
    'opened','triage','awaiting_user_evidence','awaiting_internal_evidence',
    'awaiting_gateway_evidence','under_review','escalated','pending_first_decision',
    'pending_second_decision','provisional_action','chargeback_received',
    'chargeback_acknowledged','chargeback_evidence_due','chargeback_contested']::public.recharge_dispute_status_enum[];
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.create');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT' USING ERRCODE='22023'; END IF;
  IF _title IS NULL OR length(_title) < 3 OR length(_title) > 200 THEN RAISE EXCEPTION 'TITLE_INVALID' USING ERRCODE='22023'; END IF;
  IF _summary IS NULL OR length(_summary) > 4000 THEN RAISE EXCEPTION 'SUMMARY_INVALID' USING ERRCODE='22023'; END IF;
  _input_hash := encode(digest(coalesce(_recharge_request_id::text,'')||'|'||_dispute_type||'|'||_source||'|'||_title||'|'||coalesce(_summary,'')||'|'||coalesce(_user_claim,''), 'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'create_recharge_dispute',_idempotency_key,_input_hash);
  IF _existing IS NOT NULL THEN RETURN (_existing->>'dispute_id')::uuid; END IF;
  SELECT * INTO _rr FROM public.recharge_requests WHERE id=_recharge_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECHARGE_REQUEST_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF EXISTS (SELECT 1 FROM public.recharge_disputes
             WHERE request_id=_recharge_request_id AND user_id=_rr.user_id
               AND dispute_type=_dispute_type AND dispute_source=_source
               AND status = ANY(_active_states)) THEN
    RAISE EXCEPTION 'ACTIVE_DISPUTE_ALREADY_EXISTS' USING ERRCODE='23505';
  END IF;
  SELECT * INTO _policy FROM public.recharge_dispute_policies
   WHERE active=true AND (dispute_type IS NULL OR dispute_type=_dispute_type) AND (source IS NULL OR source=_source)
   ORDER BY priority DESC NULLS LAST, version DESC LIMIT 1;
  _dispute_id := gen_random_uuid();
  _ref := 'D-'||to_char(now(),'YYYYMMDD')||'-'||substr(replace(_dispute_id::text,'-',''),1,8);
  INSERT INTO public.recharge_disputes(
    id, request_id, user_id, gateway_id, dispute_type, dispute_source, priority, severity,
    status, title, summary, user_claim, reason, opened_by, requested_by, opened_at,
    dispute_reference, dispute_policy_id, dispute_policy_version, policy_snapshot,
    requires_second_decision, financial_resolution_status,
    root_dispute_id, reopen_sequence, last_action_idempotency_key
  ) VALUES (
    _dispute_id, _recharge_request_id, _rr.user_id, _rr.gateway_id, _dispute_type, _source,
    'normal','medium','opened', _title, _summary, _user_claim, _reason, _actor, _actor, now(),
    _ref, _policy.id, _policy.version,
    CASE WHEN _policy.id IS NOT NULL THEN to_jsonb(_policy) ELSE NULL END,
    coalesce(_policy.require_second_decision,false), 'not_required',
    _dispute_id, 0, _idempotency_key);
  PERFORM public._dispute_snapshot_exposure(_dispute_id, _recharge_request_id);
  INSERT INTO public.recharge_dispute_notes(dispute_id, author_id, note_type, visibility, body, idempotency_key)
  VALUES(_dispute_id, _actor, 'system_event','internal',
         format('Dispute opened. Source=%s type=%s',_source::text,_dispute_type::text), _idempotency_key||':opened');
  PERFORM public._dispute_write_audit(_actor,'dispute_created',_dispute_id,NULL,'opened',_reason,
    jsonb_build_object('recharge_request_id',_recharge_request_id,'dispute_reference',_ref));
  PERFORM public._dispute_write_outbox('dispute_opened',_dispute_id,_rr.user_id,
    'dispute:'||_dispute_id||':opened', jsonb_build_object('dispute_reference',_ref));
  PERFORM public._dispute_idem_finalize(_actor,'create_recharge_dispute',_idempotency_key,
    jsonb_build_object('dispute_id',_dispute_id,'dispute_reference',_ref));
  RETURN _dispute_id;
END $$;

CREATE OR REPLACE FUNCTION public.assign_recharge_dispute(
  _dispute_id uuid, _assigned_to uuid, _assigned_team text, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.assign');
  _hash := encode(digest(_dispute_id::text||'|'||coalesce(_assigned_to::text,'')||'|'||coalesce(_assigned_team,''),'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'assign_recharge_dispute',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  IF _assigned_to IS NULL OR NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=_assigned_to AND is_active=true) THEN
    RAISE EXCEPTION 'ASSIGNEE_INVALID' USING ERRCODE='22023';
  END IF;
  UPDATE public.recharge_disputes SET assigned_to=_assigned_to, assigned_team=_assigned_team,
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_assigned',_dispute_id,_d.status::text,_d.status::text,_reason,
    jsonb_build_object('old_assignee',_d.assigned_to,'new_assignee',_assigned_to,'assigned_team',_assigned_team));
  PERFORM public._dispute_idem_finalize(_actor,'assign_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.triage_recharge_dispute(
  _dispute_id uuid, _priority public.recharge_dispute_priority_enum,
  _severity public.recharge_dispute_severity_enum, _assigned_team text, _next_action text,
  _request_user_evidence boolean, _request_internal_evidence boolean, _request_gateway_evidence boolean,
  _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text; _next public.recharge_dispute_status_enum;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.triage');
  IF _next_action NOT IN ('awaiting_user_evidence','awaiting_internal_evidence','awaiting_gateway_evidence','under_review') THEN
    RAISE EXCEPTION 'INVALID_NEXT_ACTION' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|'||_priority::text||'|'||_severity::text||'|'||_next_action,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'triage_recharge_dispute',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  IF _severity='critical' AND NOT public.has_permission(_actor,'recharge_disputes.set_critical_severity') THEN
    RAISE EXCEPTION 'FORBIDDEN: set_critical_severity' USING ERRCODE='42501';
  END IF;
  _next := _next_action::public.recharge_dispute_status_enum;
  PERFORM public._dispute_assert_transition(_d.status,_next);
  UPDATE public.recharge_disputes SET priority=_priority, severity=_severity,
    assigned_team=coalesce(_assigned_team,assigned_team), status=_next,
    triaged_by=_actor, triaged_at=now(), last_action_idempotency_key=_idempotency_key
    WHERE id=_dispute_id;
  IF _request_user_evidence OR _request_internal_evidence OR _request_gateway_evidence THEN
    INSERT INTO public.recharge_dispute_notes(dispute_id, author_id, note_type, visibility, body, idempotency_key)
    VALUES(_dispute_id,_actor,'evidence_request','internal',
      format('Evidence requested user=%s internal=%s gateway=%s',_request_user_evidence,_request_internal_evidence,_request_gateway_evidence),
      _idempotency_key||':evreq');
    PERFORM public._dispute_write_outbox('dispute_evidence_requested',_dispute_id,_d.user_id,
      'dispute:'||_dispute_id||':evidence-requested:'||_idempotency_key,
      jsonb_build_object('from_user',_request_user_evidence));
  END IF;
  PERFORM public._dispute_write_audit(_actor,'dispute_triaged',_dispute_id,_d.status::text,_next::text,_reason,
    jsonb_build_object('priority',_priority,'severity',_severity,'next_action',_next_action));
  PERFORM public._dispute_idem_finalize(_actor,'triage_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.request_dispute_evidence(
  _dispute_id uuid, _evidence_types public.recharge_dispute_evidence_type_enum[],
  _requested_from text, _due_at timestamptz, _user_message text, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.review');
  IF _requested_from NOT IN ('user','internal','gateway') THEN
    RAISE EXCEPTION 'INVALID_REQUESTED_FROM' USING ERRCODE='22023';
  END IF;
  IF _evidence_types IS NULL OR array_length(_evidence_types,1) IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_TYPES_REQUIRED' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|'||_requested_from||'|'||_evidence_types::text,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'request_dispute_evidence',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  INSERT INTO public.recharge_dispute_notes(dispute_id, author_id, note_type, visibility, body, idempotency_key)
  VALUES(_dispute_id,_actor,'evidence_request',
    CASE WHEN _requested_from='user' THEN 'user_visible' ELSE 'internal' END::public.recharge_dispute_note_visibility_enum,
    coalesce(_user_message, 'Evidence requested from '||_requested_from), _idempotency_key||':evreq');
  IF _requested_from='user' THEN
    PERFORM public._dispute_write_outbox('dispute_evidence_requested',_dispute_id,_d.user_id,
      'dispute:'||_dispute_id||':evidence-requested:'||_idempotency_key,
      jsonb_build_object('due_at',_due_at,'types',_evidence_types));
  END IF;
  PERFORM public._dispute_write_audit(_actor,'dispute_evidence_requested',_dispute_id,_d.status::text,_d.status::text,_reason,
    jsonb_build_object('requested_from',_requested_from,'types',_evidence_types,'due_at',_due_at));
  PERFORM public._dispute_idem_finalize(_actor,'request_dispute_evidence',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.add_dispute_internal_note(
  _dispute_id uuid, _body text, _visibility text, _reason text, _idempotency_key text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text; _nid uuid;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.notes.create_internal');
  IF _visibility NOT IN ('internal','finance_only','auditor_only') THEN
    RAISE EXCEPTION 'INVALID_NOTE_VISIBILITY' USING ERRCODE='22023';
  END IF;
  IF _body IS NULL OR length(trim(_body))=0 OR length(_body) > 8000 THEN
    RAISE EXCEPTION 'NOTE_BODY_INVALID' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|'||_visibility||'|'||_body,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'add_dispute_internal_note',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN (_existing->>'note_id')::uuid; END IF;
  _d := public._dispute_lock(_dispute_id);
  _nid := gen_random_uuid();
  INSERT INTO public.recharge_dispute_notes(id, dispute_id, author_id, note_type,
    visibility, body, content_hash, idempotency_key)
  VALUES(_nid, _dispute_id, _actor, 'internal_note',
    _visibility::public.recharge_dispute_note_visibility_enum, _body, _hash, _idempotency_key);
  PERFORM public._dispute_write_audit(_actor,'dispute_note_added',_dispute_id,_d.status::text,_d.status::text,_reason,
    jsonb_build_object('note_id',_nid,'visibility',_visibility,'is_user_visible',false));
  PERFORM public._dispute_idem_finalize(_actor,'add_dispute_internal_note',_idempotency_key,jsonb_build_object('note_id',_nid));
  RETURN _nid;
END $$;

CREATE OR REPLACE FUNCTION public.add_dispute_user_visible_note(
  _dispute_id uuid, _body text, _reason text, _idempotency_key text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text; _nid uuid;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.notes.create_user_visible');
  IF _body IS NULL OR length(trim(_body))=0 OR length(_body) > 4000 THEN
    RAISE EXCEPTION 'NOTE_BODY_INVALID' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|user|'||_body,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'add_dispute_user_visible_note',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN (_existing->>'note_id')::uuid; END IF;
  _d := public._dispute_lock(_dispute_id);
  _nid := gen_random_uuid();
  INSERT INTO public.recharge_dispute_notes(id, dispute_id, author_id, note_type,
    visibility, body, content_hash, idempotency_key, user_delivery_status)
  VALUES(_nid,_dispute_id,_actor,'user_message','user_visible',_body,_hash,_idempotency_key,'pending');
  PERFORM public._dispute_write_outbox('dispute_user_message',_dispute_id,_d.user_id,
    'dispute:'||_dispute_id||':note:'||_nid, jsonb_build_object('note_id',_nid));
  PERFORM public._dispute_write_audit(_actor,'dispute_note_added',_dispute_id,_d.status::text,_d.status::text,_reason,
    jsonb_build_object('note_id',_nid,'visibility','user_visible','is_user_visible',true));
  PERFORM public._dispute_idem_finalize(_actor,'add_dispute_user_visible_note',_idempotency_key,jsonb_build_object('note_id',_nid));
  RETURN _nid;
END $$;

CREATE OR REPLACE FUNCTION public.redact_dispute_note(
  _note_id uuid, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _existing jsonb; _hash text; _n public.recharge_dispute_notes;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.notes.redact');
  IF _reason IS NULL OR length(_reason) < 10 THEN RAISE EXCEPTION 'REASON_TOO_SHORT' USING ERRCODE='22023'; END IF;
  _hash := encode(digest(_note_id::text||'|'||_reason,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'redact_dispute_note',_idempotency_key,_hash);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  SELECT * INTO _n FROM public.recharge_dispute_notes WHERE id=_note_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOTE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  UPDATE public.recharge_dispute_notes SET
    is_redacted=true, redacted_by=_actor, redacted_at=now(), redaction_reason=_reason,
    redaction_hash=encode(digest(coalesce(body,''),'sha256'),'hex'),
    body='[REDACTED]' WHERE id=_note_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_note_redacted',_n.dispute_id,NULL,NULL,_reason,
    jsonb_build_object('note_id',_note_id));
  PERFORM public._dispute_idem_finalize(_actor,'redact_dispute_note',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.submit_dispute_evidence(
  _evidence_id uuid, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _e public.recharge_dispute_evidence; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.evidence.create');
  _hash := encode(digest(_evidence_id::text||'|submit','sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'submit_dispute_evidence',_idempotency_key,_hash);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  SELECT * INTO _e FROM public.recharge_dispute_evidence WHERE id=_evidence_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF _e.status NOT IN ('uploaded'::public.recharge_dispute_evidence_status_enum) THEN
    RAISE EXCEPTION 'EVIDENCE_ILLEGAL_TRANSITION' USING ERRCODE='22023';
  END IF;
  UPDATE public.recharge_dispute_evidence SET status='submitted', submitted_at=now(), idempotency_key=_idempotency_key
    WHERE id=_evidence_id;
  INSERT INTO public.recharge_dispute_notes(dispute_id, author_id, note_type, visibility, body, idempotency_key)
  VALUES(_e.dispute_id,_actor,'evidence_received','internal',
    format('Evidence submitted id=%s',_evidence_id), _idempotency_key||':evsub');
  PERFORM public._dispute_write_audit(_actor,'dispute_evidence_submitted',_e.dispute_id,NULL,NULL,_reason,
    jsonb_build_object('evidence_id',_evidence_id));
  PERFORM public._dispute_idem_finalize(_actor,'submit_dispute_evidence',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.review_dispute_evidence(
  _evidence_id uuid, _review_action text, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _e public.recharge_dispute_evidence; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.evidence.review');
  IF _review_action NOT IN ('accept','reject','request_replacement','keep_quarantined') THEN
    RAISE EXCEPTION 'INVALID_REVIEW_ACTION' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_evidence_id::text||'|'||_review_action,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'review_dispute_evidence',_idempotency_key,_hash);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  SELECT * INTO _e FROM public.recharge_dispute_evidence WHERE id=_evidence_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF _review_action='accept' AND (_e.malware_scan_status <> 'clean' OR _e.is_quarantined) THEN
    RAISE EXCEPTION 'EVIDENCE_SCAN_NOT_CLEAN' USING ERRCODE='22023';
  END IF;
  UPDATE public.recharge_dispute_evidence
    SET review_status = CASE _review_action WHEN 'accept' THEN 'accepted' WHEN 'reject' THEN 'rejected'
        WHEN 'request_replacement' THEN 'superseded' ELSE 'quarantined' END,
        status = CASE _review_action
          WHEN 'accept' THEN 'accepted'::public.recharge_dispute_evidence_status_enum
          WHEN 'reject' THEN 'rejected'::public.recharge_dispute_evidence_status_enum
          WHEN 'keep_quarantined' THEN 'quarantined'::public.recharge_dispute_evidence_status_enum
          ELSE status END,
        reviewed_by=_actor, reviewed_at=now(), review_reason=_reason
    WHERE id=_evidence_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_evidence_reviewed',_e.dispute_id,NULL,NULL,_reason,
    jsonb_build_object('evidence_id',_evidence_id,'review_action',_review_action));
  PERFORM public._dispute_idem_finalize(_actor,'review_dispute_evidence',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.review_recharge_dispute(
  _dispute_id uuid, _review_action text, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text; _next public.recharge_dispute_status_enum;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.review');
  IF _review_action NOT IN ('continue_review','request_user_evidence','request_internal_evidence','request_gateway_evidence','escalate','ready_for_decision','reject') THEN
    RAISE EXCEPTION 'INVALID_REVIEW_ACTION' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|'||_review_action,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'review_recharge_dispute',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  PERFORM public._dispute_snapshot_exposure(_dispute_id,_d.request_id);
  _next := CASE _review_action
    WHEN 'continue_review' THEN 'under_review'
    WHEN 'request_user_evidence' THEN 'awaiting_user_evidence'
    WHEN 'request_internal_evidence' THEN 'awaiting_internal_evidence'
    WHEN 'request_gateway_evidence' THEN 'awaiting_gateway_evidence'
    WHEN 'escalate' THEN 'escalated'
    WHEN 'ready_for_decision' THEN 'pending_first_decision'
    WHEN 'reject' THEN 'rejected' END::public.recharge_dispute_status_enum;
  PERFORM public._dispute_assert_transition(_d.status,_next);
  UPDATE public.recharge_disputes SET status=_next, reviewed_by=_actor, reviewed_at=now(),
    rejected_by=CASE WHEN _next='rejected' THEN _actor ELSE rejected_by END,
    rejected_at=CASE WHEN _next='rejected' THEN now() ELSE rejected_at END,
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_reviewed',_dispute_id,_d.status::text,_next::text,_reason,
    jsonb_build_object('review_action',_review_action));
  PERFORM public._dispute_idem_finalize(_actor,'review_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.escalate_recharge_dispute(
  _dispute_id uuid, _target_team text, _escalation_level text, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.escalate');
  IF _target_team NOT IN ('finance','compliance','fraud','engineering','gateway_ops') THEN
    RAISE EXCEPTION 'INVALID_TARGET_TEAM' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|'||_target_team||'|'||coalesce(_escalation_level,''),'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'escalate_recharge_dispute',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  PERFORM public._dispute_assert_transition(_d.status,'escalated');
  UPDATE public.recharge_disputes SET status='escalated', assigned_team=_target_team,
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_escalated',_dispute_id,_d.status::text,'escalated',_reason,
    jsonb_build_object('target_team',_target_team,'level',_escalation_level));
  PERFORM public._dispute_idem_finalize(_actor,'escalate_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.first_decide_recharge_dispute(
  _dispute_id uuid, _decision_type text, _resolution_code text, _resolution_reason text,
  _recommended_amount numeric, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text; _exp jsonb; _remain numeric;
  _next public.recharge_dispute_status_enum;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.first_decide');
  IF _decision_type NOT IN ('platform_favor','user_favor','partial_user_favor','reject_claim','request_more_evidence','escalate','recommend_refund','recommend_manual_compensation','accept_chargeback_recommendation','contest_chargeback_recommendation','no_financial_action') THEN
    RAISE EXCEPTION 'INVALID_DECISION_TYPE' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|'||_decision_type||'|'||coalesce(_recommended_amount::text,''),'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'first_decide_recharge_dispute',_idempotency_key,_hash,_dispute_id,1);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  PERFORM public._dispute_assert_transition(_d.status,'pending_first_decision');
  _exp := public._dispute_snapshot_exposure(_dispute_id,_d.request_id);
  _remain := coalesce((_exp->>'remaining_financial_exposure')::numeric,0);
  IF _recommended_amount IS NOT NULL AND (_recommended_amount < 0 OR _recommended_amount > _remain) THEN
    RAISE EXCEPTION 'DISPUTE_AMOUNT_EXCEEDS_EXPOSURE' USING ERRCODE='22023';
  END IF;
  _next := CASE WHEN _d.requires_second_decision THEN 'pending_second_decision'::public.recharge_dispute_status_enum
                ELSE 'pending_first_decision'::public.recharge_dispute_status_enum END;
  UPDATE public.recharge_disputes SET status=_next, decision_type=_decision_type,
    resolution_code=_resolution_code, resolution_reason=_resolution_reason,
    recommended_resolution_amount=_recommended_amount, first_decision_by=_actor, first_decision_at=now(),
    threshold_snapshot=jsonb_build_object('remaining_exposure',_remain,'at',now()),
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  INSERT INTO public.recharge_dispute_notes(dispute_id, author_id, note_type, visibility, body, idempotency_key)
  VALUES(_dispute_id,_actor,'decision_note','internal',
    format('First decision: %s code=%s',_decision_type,coalesce(_resolution_code,'')), _idempotency_key||':fd');
  PERFORM public._dispute_write_audit(_actor,'dispute_first_decision',_dispute_id,_d.status::text,_next::text,_reason,
    jsonb_build_object('decision_type',_decision_type,'recommended_amount',_recommended_amount));
  PERFORM public._dispute_idem_finalize(_actor,'first_decide_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.second_decide_recharge_dispute(
  _dispute_id uuid, _decision text, _approved_amount numeric, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text; _exp jsonb; _remain numeric;
  _next public.recharge_dispute_status_enum; _fin public.financial_resolution_status_enum;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.second_decide');
  IF _decision NOT IN ('confirm_user_favor','confirm_platform_favor','confirm_partial','reject','send_back_for_review') THEN
    RAISE EXCEPTION 'INVALID_DECISION_TYPE' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|'||_decision||'|'||coalesce(_approved_amount::text,''),'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'second_decide_recharge_dispute',_idempotency_key,_hash,_dispute_id,2);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  IF _d.first_decision_by IS NULL THEN RAISE EXCEPTION 'DISPUTE_SECOND_DECISION_REQUIRED' USING ERRCODE='22023'; END IF;
  IF _d.first_decision_by = _actor OR _d.opened_by = _actor THEN
    RAISE EXCEPTION 'DISPUTE_SECOND_REVIEWER_MUST_DIFFER' USING ERRCODE='22023';
  END IF;
  IF _d.status <> 'pending_second_decision' THEN
    RAISE EXCEPTION 'DISPUTE_ILLEGAL_TRANSITION: %', _d.status USING ERRCODE='22023';
  END IF;
  _exp := public._dispute_snapshot_exposure(_dispute_id,_d.request_id);
  _remain := coalesce((_exp->>'remaining_financial_exposure')::numeric,0);
  IF _approved_amount IS NOT NULL AND (_approved_amount < 0 OR _approved_amount > _remain) THEN
    RAISE EXCEPTION 'DISPUTE_AMOUNT_EXCEEDS_EXPOSURE' USING ERRCODE='22023';
  END IF;
  _next := CASE _decision
    WHEN 'confirm_user_favor' THEN 'resolved_user_favor'
    WHEN 'confirm_platform_favor' THEN 'resolved_platform_favor'
    WHEN 'confirm_partial' THEN 'resolved_partial'
    WHEN 'reject' THEN 'rejected'
    WHEN 'send_back_for_review' THEN 'under_review' END::public.recharge_dispute_status_enum;
  _fin := CASE _decision
    WHEN 'confirm_user_favor' THEN 'pending'
    WHEN 'confirm_partial' THEN 'pending'
    ELSE 'not_required' END::public.financial_resolution_status_enum;
  UPDATE public.recharge_disputes SET status=_next, second_decision_by=_actor, second_decision_at=now(),
    approved_resolution_amount=_approved_amount, financial_resolution_status=_fin,
    resolution_version=resolution_version+1, last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_second_decision',_dispute_id,_d.status::text,_next::text,_reason,
    jsonb_build_object('decision',_decision,'approved_amount',_approved_amount,'financial_status',_fin));
  PERFORM public._dispute_write_outbox('dispute_second_decision_internal',_dispute_id,_d.user_id,
    'dispute:'||_dispute_id||':second-decision:'||_d.resolution_version::text, jsonb_build_object('decision',_decision));
  PERFORM public._dispute_idem_finalize(_actor,'second_decide_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.resolve_recharge_dispute(
  _dispute_id uuid, _resolution_type text, _resolution_code text, _resolution_reason text,
  _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text; _next public.recharge_dispute_status_enum;
  _fin public.financial_resolution_status_enum;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.resolve');
  IF _resolution_type NOT IN ('user_favor','platform_favor','partial') THEN
    RAISE EXCEPTION 'INVALID_RESOLUTION_TYPE' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|'||_resolution_type||'|'||coalesce(_resolution_code,''),'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'resolve_recharge_dispute',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  _next := ('resolved_'||_resolution_type)::public.recharge_dispute_status_enum;
  PERFORM public._dispute_assert_transition(_d.status,_next);
  _fin := CASE WHEN _resolution_type IN ('user_favor','partial') THEN 'pending' ELSE 'not_required' END::public.financial_resolution_status_enum;
  UPDATE public.recharge_disputes SET status=_next, resolution=_resolution_type,
    resolution_code=coalesce(_resolution_code,resolution_code),
    resolution_reason=coalesce(_resolution_reason,resolution_reason),
    resolved_by=_actor, resolved_at=now(), financial_resolution_status=_fin,
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_resolved',_dispute_id,_d.status::text,_next::text,_reason,
    jsonb_build_object('resolution_type',_resolution_type,'financial_status',_fin));
  PERFORM public._dispute_write_outbox('dispute_'||_next::text,_dispute_id,_d.user_id,
    'dispute:'||_dispute_id||':resolved', jsonb_build_object('resolution_type',_resolution_type));
  PERFORM public._dispute_idem_finalize(_actor,'resolve_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.reject_recharge_dispute(
  _dispute_id uuid, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.review');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_TOO_SHORT' USING ERRCODE='22023'; END IF;
  _hash := encode(digest(_dispute_id::text||'|reject','sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'reject_recharge_dispute',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  PERFORM public._dispute_assert_transition(_d.status,'rejected');
  UPDATE public.recharge_disputes SET status='rejected', rejected_by=_actor, rejected_at=now(),
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_rejected',_dispute_id,_d.status::text,'rejected',_reason,'{}'::jsonb);
  PERFORM public._dispute_write_outbox('dispute_rejected',_dispute_id,_d.user_id,
    'dispute:'||_dispute_id||':rejected','{}'::jsonb);
  PERFORM public._dispute_idem_finalize(_actor,'reject_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.cancel_recharge_dispute(
  _dispute_id uuid, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.review');
  _hash := encode(digest(_dispute_id::text||'|cancel','sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'cancel_recharge_dispute',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  IF _d.status NOT IN ('opened','triage','awaiting_user_evidence') THEN
    RAISE EXCEPTION 'DISPUTE_CANNOT_CANCEL_IN_CURRENT_STATE: %', _d.status USING ERRCODE='22023';
  END IF;
  UPDATE public.recharge_disputes SET status='cancelled', cancelled_by=_actor, cancelled_at=now(),
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_cancelled',_dispute_id,_d.status::text,'cancelled',_reason,'{}'::jsonb);
  PERFORM public._dispute_idem_finalize(_actor,'cancel_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.close_recharge_dispute(
  _dispute_id uuid, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text; _pending_evidence int;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.close');
  _hash := encode(digest(_dispute_id::text||'|close','sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'close_recharge_dispute',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  IF _d.financial_resolution_status = 'pending' THEN
    RAISE EXCEPTION 'DISPUTE_CANNOT_CLOSE_PENDING_ACTIONS: financial resolution pending' USING ERRCODE='22023';
  END IF;
  SELECT count(*) INTO _pending_evidence FROM public.recharge_dispute_evidence
   WHERE dispute_id=_dispute_id AND (status IN ('submitted','under_review') OR malware_scan_status='pending');
  IF _pending_evidence > 0 THEN
    RAISE EXCEPTION 'DISPUTE_CANNOT_CLOSE_PENDING_ACTIONS: evidence pending' USING ERRCODE='22023';
  END IF;
  IF _d.status NOT IN ('resolved_user_favor','resolved_platform_favor','resolved_partial','rejected','cancelled') THEN
    RAISE EXCEPTION 'DISPUTE_CANNOT_CLOSE_PENDING_ACTIONS: status=%', _d.status USING ERRCODE='22023';
  END IF;
  UPDATE public.recharge_disputes SET status='closed', closed_by=_actor, closed_at=now(),
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'dispute_closed',_dispute_id,_d.status::text,'closed',_reason,'{}'::jsonb);
  PERFORM public._dispute_write_outbox('dispute_closed',_dispute_id,_d.user_id,
    'dispute:'||_dispute_id||':closed','{}'::jsonb);
  PERFORM public._dispute_idem_finalize(_actor,'close_recharge_dispute',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.reopen_recharge_dispute(
  _closed_dispute_id uuid, _reason text, _idempotency_key text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
  _new_id uuid; _seq integer; _root uuid;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.reopen');
  _hash := encode(digest(_closed_dispute_id::text||'|reopen','sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'reopen_recharge_dispute',_idempotency_key,_hash,_closed_dispute_id);
  IF _existing IS NOT NULL THEN RETURN (_existing->>'dispute_id')::uuid; END IF;
  _d := public._dispute_lock(_closed_dispute_id);
  IF _d.status NOT IN ('closed','resolved_user_favor','resolved_platform_favor','resolved_partial','rejected','cancelled') THEN
    RAISE EXCEPTION 'DISPUTE_ILLEGAL_TRANSITION: reopen requires closed/resolved/rejected/cancelled' USING ERRCODE='22023';
  END IF;
  _root := coalesce(_d.root_dispute_id,_d.id);
  SELECT coalesce(max(reopen_sequence),0)+1 INTO _seq FROM public.recharge_disputes WHERE root_dispute_id=_root;
  _new_id := gen_random_uuid();
  INSERT INTO public.recharge_disputes(
    id, request_id, user_id, gateway_id, dispute_type, dispute_source, priority, severity,
    status, title, summary, user_claim, reason, opened_by, requested_by, opened_at,
    dispute_reference, dispute_policy_id, dispute_policy_version, policy_snapshot,
    requires_second_decision, financial_resolution_status,
    parent_dispute_id, root_dispute_id, reopen_sequence, reopened_from_status, reopen_reason,
    last_action_idempotency_key
  ) VALUES (
    _new_id, _d.request_id, _d.user_id, _d.gateway_id, _d.dispute_type, _d.dispute_source,
    _d.priority, _d.severity, 'opened', _d.title, _d.summary, _d.user_claim, _reason,
    _actor, _actor, now(),
    'D-'||to_char(now(),'YYYYMMDD')||'-'||substr(replace(_new_id::text,'-',''),1,8),
    _d.dispute_policy_id, _d.dispute_policy_version, _d.policy_snapshot,
    _d.requires_second_decision, 'not_required',
    _closed_dispute_id, _root, _seq, _d.status, _reason, _idempotency_key);
  PERFORM public._dispute_snapshot_exposure(_new_id,_d.request_id);
  PERFORM public._dispute_write_audit(_actor,'dispute_reopened',_new_id,_d.status::text,'opened',_reason,
    jsonb_build_object('parent_dispute_id',_closed_dispute_id,'root_dispute_id',_root,'sequence',_seq));
  PERFORM public._dispute_write_outbox('dispute_reopened',_new_id,_d.user_id,
    'dispute:'||_new_id||':reopened', jsonb_build_object('parent_dispute_id',_closed_dispute_id));
  PERFORM public._dispute_idem_finalize(_actor,'reopen_recharge_dispute',_idempotency_key,jsonb_build_object('dispute_id',_new_id));
  RETURN _new_id;
END $$;

CREATE OR REPLACE FUNCTION public.acknowledge_chargeback(
  _dispute_id uuid, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.chargeback.manage');
  _hash := encode(digest(_dispute_id::text||'|ack','sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'acknowledge_chargeback',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  UPDATE public.recharge_disputes SET status='chargeback_acknowledged',
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'chargeback_acknowledged',_dispute_id,_d.status::text,'chargeback_acknowledged',_reason,'{}'::jsonb);
  PERFORM public._dispute_idem_finalize(_actor,'acknowledge_chargeback',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.mark_chargeback_evidence_due(
  _dispute_id uuid, _due_at timestamptz, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.chargeback.manage');
  _hash := encode(digest(_dispute_id::text||'|evdue|'||coalesce(_due_at::text,''),'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'mark_chargeback_evidence_due',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  UPDATE public.recharge_disputes SET status='chargeback_evidence_due', evidence_due_at=_due_at,
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'chargeback_evidence_due_recorded',_dispute_id,_d.status::text,'chargeback_evidence_due',_reason,
    jsonb_build_object('due_at',_due_at));
  PERFORM public._dispute_idem_finalize(_actor,'mark_chargeback_evidence_due',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.record_chargeback_recommendation(
  _dispute_id uuid, _recommendation text, _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.chargeback.manage');
  IF _recommendation NOT IN ('accept','contest','request_info') THEN
    RAISE EXCEPTION 'INVALID_RECOMMENDATION' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|rec|'||_recommendation,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'record_chargeback_recommendation',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  PERFORM public._dispute_write_audit(_actor,'chargeback_recommendation_recorded',_dispute_id,_d.status::text,_d.status::text,_reason,
    jsonb_build_object('recommendation',_recommendation));
  PERFORM public._dispute_idem_finalize(_actor,'record_chargeback_recommendation',_idempotency_key,jsonb_build_object('ok',true));
END $$;

CREATE OR REPLACE FUNCTION public.record_manual_chargeback_provider_status(
  _dispute_id uuid, _provider_status text, _provider_reference text, _source_reference text,
  _reason text, _idempotency_key text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE _actor uuid; _d public.recharge_disputes; _existing jsonb; _hash text;
BEGIN
  _actor := public._dispute_assert_actor('recharge_disputes.chargeback.manage');
  IF NOT public.has_permission(_actor,'recharge_disputes.read_sensitive') THEN
    RAISE EXCEPTION 'FORBIDDEN: read_sensitive' USING ERRCODE='42501';
  END IF;
  IF _provider_reference IS NULL OR length(_provider_reference) < 3 OR _source_reference IS NULL THEN
    RAISE EXCEPTION 'PROVIDER_IDENTITY_INCOMPLETE' USING ERRCODE='22023';
  END IF;
  _hash := encode(digest(_dispute_id::text||'|manprov|'||_provider_status||'|'||_provider_reference,'sha256'),'hex');
  _existing := public._dispute_idem_lookup(_actor,'record_manual_chargeback_provider_status',_idempotency_key,_hash,_dispute_id);
  IF _existing IS NOT NULL THEN RETURN; END IF;
  _d := public._dispute_lock(_dispute_id);
  UPDATE public.recharge_disputes SET provider_status=_provider_status,
    provider_case_reference=coalesce(provider_case_reference,_provider_reference),
    provider_mode='manual', provider_updated_at=now(),
    last_action_idempotency_key=_idempotency_key WHERE id=_dispute_id;
  PERFORM public._dispute_write_audit(_actor,'chargeback_manual_status_recorded',_dispute_id,_d.status::text,_d.status::text,_reason,
    jsonb_build_object('provider_status',_provider_status,'source_reference',_source_reference));
  PERFORM public._dispute_idem_finalize(_actor,'record_manual_chargeback_provider_status',_idempotency_key,jsonb_build_object('ok',true));
END $$;

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
    VALUES(r.proname, r.args, 'KEEP_AUTHENTICATED_ADMIN_RPC','medium','5D-2 dispute lifecycle wrapper: auth.uid() actor, permission-gated, idempotent, no financial exec')
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;
