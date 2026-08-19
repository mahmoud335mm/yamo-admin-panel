
CREATE OR REPLACE FUNCTION public._wallet_apply(
  _user_id uuid, _account wallet_account, _delta bigint,
  _reason ledger_reason, _reference text, _metadata jsonb
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE w_id uuid; new_bal bigint; cur_bal bigint;
BEGIN
  SELECT id, balance INTO w_id, cur_bal FROM public.wallets
    WHERE user_id = _user_id AND account = _account FOR UPDATE;
  IF w_id IS NULL THEN
    INSERT INTO public.wallets(user_id, account, balance, reserved) VALUES (_user_id, _account, 0, 0)
      RETURNING id, balance INTO w_id, cur_bal;
    PERFORM 1 FROM public.wallets WHERE id = w_id FOR UPDATE;
  END IF;
  new_bal := cur_bal + _delta;
  IF new_bal < 0 THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE: have %, need %', cur_bal, ABS(_delta) USING ERRCODE='P0001'; END IF;
  UPDATE public.wallets SET balance = new_bal, updated_at = now() WHERE id = w_id;
  INSERT INTO public.wallet_ledger(wallet_id, user_id, account, direction, reason, amount, balance_after, reference, metadata, created_by)
    VALUES (w_id, _user_id, _account,
      CASE WHEN _delta >= 0 THEN 'credit'::ledger_direction ELSE 'debit'::ledger_direction END,
      _reason, ABS(_delta), new_bal, _reference, COALESCE(_metadata,'{}'::jsonb), auth.uid());
  RETURN new_bal;
END $$;
REVOKE EXECUTE ON FUNCTION public._wallet_apply(uuid,wallet_account,bigint,ledger_reason,text,jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._charge_audit(_action text, _entity_type text, _entity_id text, _meta jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), _action, _entity_type, _entity_id, COALESCE(_meta,'{}'::jsonb));
END $$;
REVOKE EXECUTE ON FUNCTION public._charge_audit(text,text,text,jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_charging_agency(
  _name text, _country text, _city text, _default_currency text,
  _owner_user_id uuid, _deputy_user_id uuid, _phone text, _email text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE new_id uuid;
BEGIN
  PERFORM public._require_perm('charging_agencies.create');
  IF _name IS NULL OR length(_name) < 2 THEN RAISE EXCEPTION 'INVALID_NAME'; END IF;
  INSERT INTO public.charging_agencies(name,country,city,default_currency,owner_user_id,deputy_user_id,phone,email,status,created_by,updated_by)
  VALUES (_name,_country,_city,COALESCE(_default_currency,'USD'),_owner_user_id,_deputy_user_id,_phone,_email,'active',auth.uid(),auth.uid())
  RETURNING id INTO new_id;
  IF _owner_user_id IS NOT NULL THEN
    INSERT INTO public.charging_agency_members(agency_id,user_id,member_role,assigned_by)
      VALUES (new_id,_owner_user_id,'charging_agency_owner',auth.uid()) ON CONFLICT DO NOTHING;
    INSERT INTO public.charging_agent_settings(user_id, agency_id, activated_by)
      VALUES (_owner_user_id, new_id, auth.uid())
      ON CONFLICT (user_id) DO UPDATE SET agency_id=EXCLUDED.agency_id, status='active';
  END IF;
  IF _deputy_user_id IS NOT NULL AND _deputy_user_id <> COALESCE(_owner_user_id,'00000000-0000-0000-0000-000000000000'::uuid) THEN
    INSERT INTO public.charging_agency_members(agency_id,user_id,member_role,assigned_by)
      VALUES (new_id,_deputy_user_id,'charging_agency_deputy',auth.uid()) ON CONFLICT DO NOTHING;
    INSERT INTO public.charging_agent_settings(user_id, agency_id, activated_by)
      VALUES (_deputy_user_id, new_id, auth.uid())
      ON CONFLICT (user_id) DO UPDATE SET agency_id=EXCLUDED.agency_id, status='active';
  END IF;
  PERFORM public._charge_audit('charging.agency.create','charging_agencies',new_id::text, jsonb_build_object('name',_name));
  RETURN new_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.create_charging_agency(text,text,text,text,uuid,uuid,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_charging_agency(text,text,text,text,uuid,uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_charging_agency(
  _agency_id uuid, _name text, _country text, _city text, _default_currency text,
  _phone text, _email text, _logo_url text, _cover_url text, _admin_notes text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agencies.update');
  UPDATE public.charging_agencies SET
    name=COALESCE(_name,name), country=COALESCE(_country,country), city=COALESCE(_city,city),
    default_currency=COALESCE(_default_currency,default_currency),
    phone=COALESCE(_phone,phone), email=COALESCE(_email,email),
    logo_url=COALESCE(_logo_url,logo_url), cover_url=COALESCE(_cover_url,cover_url),
    admin_notes=COALESCE(_admin_notes,admin_notes), updated_by=auth.uid()
  WHERE id=_agency_id;
  PERFORM public._charge_audit('charging.agency.update','charging_agencies',_agency_id::text,'{}'::jsonb);
END $$;
REVOKE EXECUTE ON FUNCTION public.update_charging_agency(uuid,text,text,text,text,text,text,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_charging_agency(uuid,text,text,text,text,text,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.suspend_charging_agency(_agency_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agencies.suspend');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE public.charging_agencies SET status='suspended', updated_by=auth.uid() WHERE id=_agency_id AND status <> 'closed';
  PERFORM public._charge_audit('charging.agency.suspend','charging_agencies',_agency_id::text, jsonb_build_object('reason',_reason));
END $$;
REVOKE EXECUTE ON FUNCTION public.suspend_charging_agency(uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.suspend_charging_agency(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reactivate_charging_agency(_agency_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agencies.suspend');
  UPDATE public.charging_agencies SET status='active', updated_by=auth.uid() WHERE id=_agency_id AND status='suspended';
  PERFORM public._charge_audit('charging.agency.reactivate','charging_agencies',_agency_id::text,'{}'::jsonb);
END $$;
REVOKE EXECUTE ON FUNCTION public.reactivate_charging_agency(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reactivate_charging_agency(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.close_charging_agency(_agency_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agencies.close');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE public.charging_agencies SET status='closed', updated_by=auth.uid() WHERE id=_agency_id;
  UPDATE public.charging_agent_settings SET status='inactive', deactivated_at=now(), deactivated_by=auth.uid() WHERE agency_id=_agency_id;
  PERFORM public._charge_audit('charging.agency.close','charging_agencies',_agency_id::text, jsonb_build_object('reason',_reason));
END $$;
REVOKE EXECUTE ON FUNCTION public.close_charging_agency(uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.close_charging_agency(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.activate_charging_agent(
  _user_id uuid, _agency_id uuid, _role charging_agent_role,
  _daily_coin_limit bigint, _monthly_coin_limit bigint,
  _daily_pearl_limit bigint, _monthly_pearl_limit bigint
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE ag_status public.charging_agency_status;
BEGIN
  PERFORM public._require_perm('charging_agents.activate');
  IF _user_id IS NULL THEN RAISE EXCEPTION 'USER_REQUIRED'; END IF;
  IF _agency_id IS NULL THEN RAISE EXCEPTION 'AGENCY_REQUIRED'; END IF;
  SELECT status INTO ag_status FROM public.charging_agencies WHERE id=_agency_id;
  IF ag_status IS NULL THEN RAISE EXCEPTION 'AGENCY_NOT_FOUND'; END IF;
  IF ag_status <> 'active' THEN RAISE EXCEPTION 'AGENCY_NOT_ACTIVE: %', ag_status; END IF;
  INSERT INTO public.charging_agency_members(agency_id,user_id,member_role,assigned_by)
    VALUES (_agency_id,_user_id, COALESCE(_role,'charging_agent'::charging_agent_role), auth.uid())
    ON CONFLICT (agency_id, user_id) DO UPDATE SET member_role=EXCLUDED.member_role, status='active', removed_at=NULL;
  INSERT INTO public.charging_agent_settings(user_id, agency_id, activated_by, daily_coin_limit, monthly_coin_limit, daily_pearl_limit, monthly_pearl_limit)
  VALUES (_user_id, _agency_id, auth.uid(),
    COALESCE(_daily_coin_limit,50000000), COALESCE(_monthly_coin_limit,1500000000),
    COALESCE(_daily_pearl_limit,5000000), COALESCE(_monthly_pearl_limit,150000000))
  ON CONFLICT (user_id) DO UPDATE SET
    agency_id=EXCLUDED.agency_id, status='active',
    daily_coin_limit=EXCLUDED.daily_coin_limit, monthly_coin_limit=EXCLUDED.monthly_coin_limit,
    daily_pearl_limit=EXCLUDED.daily_pearl_limit, monthly_pearl_limit=EXCLUDED.monthly_pearl_limit,
    activated_at=now(), activated_by=auth.uid(),
    deactivated_at=NULL, deactivated_by=NULL,
    suspended_at=NULL, suspended_by=NULL, suspend_reason=NULL;
  PERFORM public._charge_audit('charging.agent.activate','charging_agent_settings',_user_id::text, jsonb_build_object('agency_id',_agency_id,'role',_role));
END $$;
REVOKE EXECUTE ON FUNCTION public.activate_charging_agent(uuid,uuid,charging_agent_role,bigint,bigint,bigint,bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.activate_charging_agent(uuid,uuid,charging_agent_role,bigint,bigint,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.deactivate_charging_agent(_user_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agents.suspend');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE public.charging_agent_settings SET status='inactive', deactivated_at=now(), deactivated_by=auth.uid() WHERE user_id=_user_id;
  UPDATE public.charging_agency_members SET status='inactive', removed_at=now() WHERE user_id=_user_id AND status='active';
  PERFORM public._charge_audit('charging.agent.deactivate','charging_agent_settings',_user_id::text, jsonb_build_object('reason',_reason));
END $$;
REVOKE EXECUTE ON FUNCTION public.deactivate_charging_agent(uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.deactivate_charging_agent(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.suspend_charging_agent(_user_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agents.suspend');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE public.charging_agent_settings SET status='suspended', suspended_at=now(), suspended_by=auth.uid(), suspend_reason=_reason WHERE user_id=_user_id;
  PERFORM public._charge_audit('charging.agent.suspend','charging_agent_settings',_user_id::text, jsonb_build_object('reason',_reason));
END $$;
REVOKE EXECUTE ON FUNCTION public.suspend_charging_agent(uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.suspend_charging_agent(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reactivate_charging_agent(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agents.suspend');
  UPDATE public.charging_agent_settings SET status='active', suspended_at=NULL, suspended_by=NULL, suspend_reason=NULL WHERE user_id=_user_id AND status='suspended';
  PERFORM public._charge_audit('charging.agent.reactivate','charging_agent_settings',_user_id::text,'{}'::jsonb);
END $$;
REVOKE EXECUTE ON FUNCTION public.reactivate_charging_agent(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reactivate_charging_agent(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_charging_agent_limits(
  _user_id uuid, _daily_coin_limit bigint, _monthly_coin_limit bigint,
  _daily_pearl_limit bigint, _monthly_pearl_limit bigint,
  _min_coin_transfer bigint, _max_coin_transfer bigint,
  _min_pearl_transfer bigint, _max_pearl_transfer bigint
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agents.update_limits');
  UPDATE public.charging_agent_settings SET
    daily_coin_limit=COALESCE(_daily_coin_limit,daily_coin_limit),
    monthly_coin_limit=COALESCE(_monthly_coin_limit,monthly_coin_limit),
    daily_pearl_limit=COALESCE(_daily_pearl_limit,daily_pearl_limit),
    monthly_pearl_limit=COALESCE(_monthly_pearl_limit,monthly_pearl_limit),
    min_coin_transfer=COALESCE(_min_coin_transfer,min_coin_transfer),
    max_coin_transfer=COALESCE(_max_coin_transfer,max_coin_transfer),
    min_pearl_transfer=COALESCE(_min_pearl_transfer,min_pearl_transfer),
    max_pearl_transfer=COALESCE(_max_pearl_transfer,max_pearl_transfer)
  WHERE user_id=_user_id;
  PERFORM public._charge_audit('charging.agent.update_limits','charging_agent_settings',_user_id::text,'{}'::jsonb);
END $$;
REVOKE EXECUTE ON FUNCTION public.update_charging_agent_limits(uuid,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_charging_agent_limits(uuid,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_charging_agent_permissions(
  _user_id uuid, _can_sell_coins boolean, _can_buy_pearls boolean,
  _can_transfer_to_agents boolean, _can_exchange_pearls_to_coins boolean
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agents.update_limits');
  UPDATE public.charging_agent_settings SET
    can_sell_coins=COALESCE(_can_sell_coins,can_sell_coins),
    can_buy_pearls=COALESCE(_can_buy_pearls,can_buy_pearls),
    can_transfer_to_agents=COALESCE(_can_transfer_to_agents,can_transfer_to_agents),
    can_exchange_pearls_to_coins=COALESCE(_can_exchange_pearls_to_coins,can_exchange_pearls_to_coins)
  WHERE user_id=_user_id;
  PERFORM public._charge_audit('charging.agent.update_permissions','charging_agent_settings',_user_id::text,'{}'::jsonb);
END $$;
REVOKE EXECUTE ON FUNCTION public.update_charging_agent_permissions(uuid,boolean,boolean,boolean,boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_charging_agent_permissions(uuid,boolean,boolean,boolean,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_agent_to_charging_agency(_user_id uuid, _agency_id uuid, _role charging_agent_role)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agents.activate');
  INSERT INTO public.charging_agency_members(agency_id,user_id,member_role,assigned_by)
    VALUES (_agency_id,_user_id, COALESCE(_role,'charging_agent'::charging_agent_role), auth.uid())
    ON CONFLICT (agency_id, user_id) DO UPDATE SET member_role=EXCLUDED.member_role, status='active', removed_at=NULL;
  UPDATE public.charging_agent_settings SET agency_id=_agency_id WHERE user_id=_user_id;
  PERFORM public._charge_audit('charging.agent.assign','charging_agency_members',_user_id::text, jsonb_build_object('agency_id',_agency_id));
END $$;
REVOKE EXECUTE ON FUNCTION public.assign_agent_to_charging_agency(uuid,uuid,charging_agent_role) FROM anon;
GRANT EXECUTE ON FUNCTION public.assign_agent_to_charging_agency(uuid,uuid,charging_agent_role) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_agent_from_charging_agency(_user_id uuid, _agency_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_perm('charging_agents.suspend');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE public.charging_agency_members SET status='inactive', removed_at=now() WHERE agency_id=_agency_id AND user_id=_user_id;
  UPDATE public.charging_agent_settings SET agency_id=NULL WHERE user_id=_user_id AND agency_id=_agency_id;
  PERFORM public._charge_audit('charging.agent.remove','charging_agency_members',_user_id::text, jsonb_build_object('agency_id',_agency_id,'reason',_reason));
END $$;
REVOKE EXECUTE ON FUNCTION public.remove_agent_from_charging_agency(uuid,uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.remove_agent_from_charging_agency(uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.charging_agent_transfer_coins(
  _recipient_user_id uuid, _amount bigint,
  _sale_price numeric, _currency text, _payment_reference text, _receipt_url text, _note text,
  _idempotency_key text
) RETURNS TABLE(transfer_id uuid, reference text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  agent_uid uuid := auth.uid();
  a_settings public.charging_agent_settings%ROWTYPE;
  agency public.charging_agencies%ROWTYPE;
  recip_status public.user_status;
  is_recip_agent boolean; existing uuid;
  new_transfer_id uuid; new_ref text;
  day_used bigint; month_used bigint;
BEGIN
  IF agent_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _recipient_user_id IS NULL THEN RAISE EXCEPTION 'RECIPIENT_REQUIRED'; END IF;
  IF _recipient_user_id = agent_uid THEN RAISE EXCEPTION 'CANNOT_TRANSFER_TO_SELF'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  IF _idempotency_key IS NOT NULL THEN
    SELECT id INTO existing FROM public.charging_coin_transfers WHERE idempotency_key = _idempotency_key;
    IF existing IS NOT NULL THEN RETURN QUERY SELECT id, reference FROM public.charging_coin_transfers WHERE id=existing; RETURN; END IF;
  END IF;

  SELECT * INTO a_settings FROM public.charging_agent_settings WHERE user_id = agent_uid FOR UPDATE;
  IF a_settings.user_id IS NULL THEN RAISE EXCEPTION 'NOT_A_CHARGING_AGENT'; END IF;
  IF a_settings.status <> 'active' THEN RAISE EXCEPTION 'AGENT_NOT_ACTIVE: %', a_settings.status; END IF;
  IF NOT a_settings.can_sell_coins THEN RAISE EXCEPTION 'AGENT_CANNOT_SELL_COINS'; END IF;

  IF a_settings.agency_id IS NOT NULL THEN
    SELECT * INTO agency FROM public.charging_agencies WHERE id = a_settings.agency_id;
    IF agency.status <> 'active' THEN RAISE EXCEPTION 'AGENCY_NOT_ACTIVE: %', agency.status; END IF;
  END IF;

  IF _amount < COALESCE(a_settings.min_coin_transfer,1) THEN RAISE EXCEPTION 'BELOW_MIN_TRANSFER: min=%', a_settings.min_coin_transfer; END IF;
  IF a_settings.max_coin_transfer IS NOT NULL AND _amount > a_settings.max_coin_transfer THEN RAISE EXCEPTION 'ABOVE_MAX_TRANSFER: max=%', a_settings.max_coin_transfer; END IF;

  SELECT COALESCE(SUM(amount),0) INTO day_used FROM public.charging_coin_transfers
    WHERE agent_user_id=agent_uid AND status='completed' AND created_at >= date_trunc('day', now());
  SELECT COALESCE(SUM(amount),0) INTO month_used FROM public.charging_coin_transfers
    WHERE agent_user_id=agent_uid AND status='completed' AND created_at >= date_trunc('month', now());
  IF day_used + _amount > COALESCE(a_settings.daily_coin_limit,9223372036854775807) THEN RAISE EXCEPTION 'DAILY_LIMIT_EXCEEDED: used=%, limit=%', day_used, a_settings.daily_coin_limit; END IF;
  IF month_used + _amount > COALESCE(a_settings.monthly_coin_limit,9223372036854775807) THEN RAISE EXCEPTION 'MONTHLY_LIMIT_EXCEEDED: used=%, limit=%', month_used, a_settings.monthly_coin_limit; END IF;

  SELECT status INTO recip_status FROM public.profiles WHERE id = _recipient_user_id;
  IF recip_status IS NULL THEN RAISE EXCEPTION 'RECIPIENT_NOT_FOUND'; END IF;
  IF recip_status = 'banned' THEN RAISE EXCEPTION 'RECIPIENT_BANNED'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.charging_agent_settings WHERE user_id=_recipient_user_id AND status='active') INTO is_recip_agent;

  new_ref := 'YC-COIN-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8);
  INSERT INTO public.charging_coin_transfers(reference, agent_user_id, agency_id, recipient_user_id, recipient_is_agent, amount, sale_price, currency, payment_reference, receipt_url, note, status, idempotency_key)
  VALUES (new_ref, agent_uid, a_settings.agency_id, _recipient_user_id, is_recip_agent, _amount, _sale_price, _currency, _payment_reference, _receipt_url, _note, 'pending', _idempotency_key)
  RETURNING id INTO new_transfer_id;

  PERFORM public._wallet_apply(agent_uid, 'coins'::wallet_account, -_amount, 'charging_coin_transfer'::ledger_reason, new_ref, jsonb_build_object('recipient_user_id',_recipient_user_id,'transfer_id',new_transfer_id));
  PERFORM public._wallet_apply(_recipient_user_id, 'coins'::wallet_account, _amount, 'charging_coin_transfer'::ledger_reason, new_ref, jsonb_build_object('agent_user_id',agent_uid,'transfer_id',new_transfer_id));

  UPDATE public.charging_coin_transfers SET status='completed', completed_at=now() WHERE id=new_transfer_id;

  INSERT INTO public.message_transaction_metadata(txn_type, txn_reference, from_user_id, to_user_id, amount, currency_code, metadata)
  VALUES ('coin_transfer', new_ref, agent_uid, _recipient_user_id, _amount, 'coins', jsonb_build_object('transfer_id',new_transfer_id,'sale_price',_sale_price,'currency',_currency,'note',_note));

  INSERT INTO public.charging_customers(user_id, agency_id, preferred_agent_id, coin_purchase_count, total_coins_purchased, total_coin_amount_paid, last_transaction_at)
  VALUES (_recipient_user_id, a_settings.agency_id, agent_uid, 1, _amount, COALESCE(_sale_price,0), now())
  ON CONFLICT (agency_id, user_id) DO UPDATE SET
    coin_purchase_count = public.charging_customers.coin_purchase_count + 1,
    total_coins_purchased = public.charging_customers.total_coins_purchased + _amount,
    total_coin_amount_paid = public.charging_customers.total_coin_amount_paid + COALESCE(_sale_price,0),
    last_transaction_at = now(),
    preferred_agent_id = COALESCE(public.charging_customers.preferred_agent_id, agent_uid);

  INSERT INTO public.charging_notifications(user_id, event_type, title, body, entity_type, entity_id) VALUES
    (_recipient_user_id, 'coin_received', 'استلمت كوينز', 'تم استلام ' || _amount::text || ' كوينز', 'charging_coin_transfer', new_transfer_id::text),
    (agent_uid, 'coin_sent', 'تم إرسال الكوينز', 'تم إرسال ' || _amount::text || ' كوينز', 'charging_coin_transfer', new_transfer_id::text);

  PERFORM public._charge_audit('charging.coin_transfer','charging_coin_transfers', new_transfer_id::text, jsonb_build_object('amount',_amount,'recipient',_recipient_user_id,'reference',new_ref));
  RETURN QUERY SELECT new_transfer_id, new_ref;
END $$;
REVOKE EXECUTE ON FUNCTION public.charging_agent_transfer_coins(uuid,bigint,numeric,text,text,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.charging_agent_transfer_coins(uuid,bigint,numeric,text,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.charging_agent_transfer_pearls(_recipient_user_id uuid, _amount bigint, _note text, _idempotency_key text)
RETURNS TABLE(transfer_id uuid, reference text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  agent_uid uuid := auth.uid();
  a_settings public.charging_agent_settings%ROWTYPE;
  r_settings public.charging_agent_settings%ROWTYPE;
  existing uuid; new_id uuid; new_ref text;
  day_used bigint; month_used bigint;
BEGIN
  IF agent_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _recipient_user_id IS NULL THEN RAISE EXCEPTION 'RECIPIENT_REQUIRED'; END IF;
  IF _recipient_user_id = agent_uid THEN RAISE EXCEPTION 'CANNOT_TRANSFER_TO_SELF'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF _idempotency_key IS NOT NULL THEN
    SELECT id INTO existing FROM public.charging_pearl_transfers WHERE idempotency_key=_idempotency_key;
    IF existing IS NOT NULL THEN RETURN QUERY SELECT id, reference FROM public.charging_pearl_transfers WHERE id=existing; RETURN; END IF;
  END IF;
  SELECT * INTO a_settings FROM public.charging_agent_settings WHERE user_id=agent_uid FOR UPDATE;
  IF a_settings.user_id IS NULL OR a_settings.status <> 'active' THEN RAISE EXCEPTION 'AGENT_NOT_ACTIVE'; END IF;
  IF NOT a_settings.can_transfer_to_agents THEN RAISE EXCEPTION 'AGENT_CANNOT_TRANSFER_PEARLS'; END IF;
  SELECT * INTO r_settings FROM public.charging_agent_settings WHERE user_id=_recipient_user_id;
  IF r_settings.user_id IS NULL OR r_settings.status <> 'active' THEN RAISE EXCEPTION 'RECIPIENT_NOT_AGENT'; END IF;
  IF _amount < COALESCE(a_settings.min_pearl_transfer,1) THEN RAISE EXCEPTION 'BELOW_MIN'; END IF;
  IF a_settings.max_pearl_transfer IS NOT NULL AND _amount > a_settings.max_pearl_transfer THEN RAISE EXCEPTION 'ABOVE_MAX'; END IF;
  SELECT COALESCE(SUM(amount),0) INTO day_used FROM public.charging_pearl_transfers WHERE from_user_id=agent_uid AND status='completed' AND created_at >= date_trunc('day', now());
  SELECT COALESCE(SUM(amount),0) INTO month_used FROM public.charging_pearl_transfers WHERE from_user_id=agent_uid AND status='completed' AND created_at >= date_trunc('month', now());
  IF day_used + _amount > COALESCE(a_settings.daily_pearl_limit,9223372036854775807) THEN RAISE EXCEPTION 'DAILY_LIMIT_EXCEEDED'; END IF;
  IF month_used + _amount > COALESCE(a_settings.monthly_pearl_limit,9223372036854775807) THEN RAISE EXCEPTION 'MONTHLY_LIMIT_EXCEEDED'; END IF;

  new_ref := 'YC-PEARL-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8);
  INSERT INTO public.charging_pearl_transfers(reference, from_user_id, to_user_id, amount, note, status, idempotency_key)
  VALUES (new_ref, agent_uid, _recipient_user_id, _amount, _note, 'pending', _idempotency_key) RETURNING id INTO new_id;

  PERFORM public._wallet_apply(agent_uid, 'diamonds'::wallet_account, -_amount, 'charging_pearl_transfer'::ledger_reason, new_ref, jsonb_build_object('to_user_id',_recipient_user_id,'transfer_id',new_id));
  PERFORM public._wallet_apply(_recipient_user_id, 'diamonds'::wallet_account, _amount, 'charging_pearl_transfer'::ledger_reason, new_ref, jsonb_build_object('from_user_id',agent_uid,'transfer_id',new_id));

  UPDATE public.charging_pearl_transfers SET status='completed', completed_at=now() WHERE id=new_id;

  INSERT INTO public.message_transaction_metadata(txn_type, txn_reference, from_user_id, to_user_id, amount, currency_code, metadata)
  VALUES ('pearl_transfer', new_ref, agent_uid, _recipient_user_id, _amount, 'pearls', jsonb_build_object('transfer_id',new_id,'note',_note));
  INSERT INTO public.charging_notifications(user_id, event_type, title, body, entity_type, entity_id) VALUES
    (_recipient_user_id, 'pearl_received', 'استلمت لؤلؤًا', 'تم استلام ' || _amount::text || ' لؤلؤة', 'charging_pearl_transfer', new_id::text),
    (agent_uid, 'pearl_sent', 'تم إرسال اللؤلؤ', 'تم إرسال ' || _amount::text || ' لؤلؤة', 'charging_pearl_transfer', new_id::text);
  PERFORM public._charge_audit('charging.pearl_transfer','charging_pearl_transfers', new_id::text, jsonb_build_object('amount',_amount,'recipient',_recipient_user_id,'reference',new_ref));
  RETURN QUERY SELECT new_id, new_ref;
END $$;
REVOKE EXECUTE ON FUNCTION public.charging_agent_transfer_pearls(uuid,bigint,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.charging_agent_transfer_pearls(uuid,bigint,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public._admin_wallet_adjust(_target_user_id uuid, _kind wallet_adjustment_kind, _amount bigint, _reason text, _idempotency_key text)
RETURNS TABLE(adjustment_id uuid, reference text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE acct wallet_account; delta bigint; ledger_r ledger_reason; need_perm text; new_ref text; new_id uuid; existing uuid; bal_before bigint; bal_after bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  CASE _kind
    WHEN 'coin_credit'  THEN acct:='coins'::wallet_account;    delta:= _amount; ledger_r:='admin_coin_credit'::ledger_reason;  need_perm:='wallets.coins.credit';
    WHEN 'coin_debit'   THEN acct:='coins'::wallet_account;    delta:=-_amount; ledger_r:='admin_coin_debit'::ledger_reason;   need_perm:='wallets.coins.debit';
    WHEN 'pearl_credit' THEN acct:='diamonds'::wallet_account; delta:= _amount; ledger_r:='admin_pearl_credit'::ledger_reason; need_perm:='wallets.pearls.credit';
    WHEN 'pearl_debit'  THEN acct:='diamonds'::wallet_account; delta:=-_amount; ledger_r:='admin_pearl_debit'::ledger_reason;  need_perm:='wallets.pearls.debit';
  END CASE;
  PERFORM public._require_perm(need_perm);
  IF _idempotency_key IS NOT NULL THEN
    SELECT id INTO existing FROM public.wallet_adjustment_requests WHERE idempotency_key=_idempotency_key;
    IF existing IS NOT NULL THEN RETURN QUERY SELECT id, reference FROM public.wallet_adjustment_requests WHERE id=existing; RETURN; END IF;
  END IF;
  new_ref := 'YC-ADJ-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8);
  SELECT balance INTO bal_before FROM public.wallets WHERE user_id=_target_user_id AND account=acct;
  bal_before := COALESCE(bal_before,0);
  INSERT INTO public.wallet_adjustment_requests(reference, target_user_id, kind, amount, reason, status, idempotency_key, created_by, balance_before)
  VALUES (new_ref, _target_user_id, _kind, _amount, _reason, 'applied', _idempotency_key, auth.uid(), bal_before) RETURNING id INTO new_id;
  bal_after := public._wallet_apply(_target_user_id, acct, delta, ledger_r, new_ref, jsonb_build_object('adjustment_id',new_id,'reason',_reason));
  UPDATE public.wallet_adjustment_requests SET applied_at=now(), balance_after=bal_after WHERE id=new_id;
  INSERT INTO public.message_transaction_metadata(txn_type, txn_reference, from_user_id, to_user_id, amount, currency_code, metadata)
  VALUES ('admin_adjustment', new_ref, auth.uid(), _target_user_id, _amount, CASE WHEN acct='coins'::wallet_account THEN 'coins' ELSE 'pearls' END, jsonb_build_object('kind',_kind,'reason',_reason));
  INSERT INTO public.charging_notifications(user_id, event_type, title, body, entity_type, entity_id)
  VALUES (_target_user_id, 'admin_adjustment', 'تعديل إداري على رصيدك', _kind::text || ' ' || _amount::text, 'wallet_adjustment_requests', new_id::text);
  PERFORM public._charge_audit('charging.admin_adjust','wallet_adjustment_requests', new_id::text, jsonb_build_object('kind',_kind,'amount',_amount,'target',_target_user_id,'reason',_reason,'balance_before',bal_before,'balance_after',bal_after));
  RETURN QUERY SELECT new_id, new_ref;
END $$;
REVOKE EXECUTE ON FUNCTION public._admin_wallet_adjust(uuid,wallet_adjustment_kind,bigint,text,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_credit_user_coins(_target_user_id uuid, _amount bigint, _reason text, _idempotency_key text)
RETURNS TABLE(adjustment_id uuid, reference text) LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT * FROM public._admin_wallet_adjust(_target_user_id,'coin_credit'::wallet_adjustment_kind,_amount,_reason,_idempotency_key);
$$;
REVOKE EXECUTE ON FUNCTION public.admin_credit_user_coins(uuid,bigint,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_credit_user_coins(uuid,bigint,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_debit_user_coins(_target_user_id uuid, _amount bigint, _reason text, _idempotency_key text)
RETURNS TABLE(adjustment_id uuid, reference text) LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT * FROM public._admin_wallet_adjust(_target_user_id,'coin_debit'::wallet_adjustment_kind,_amount,_reason,_idempotency_key);
$$;
REVOKE EXECUTE ON FUNCTION public.admin_debit_user_coins(uuid,bigint,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_debit_user_coins(uuid,bigint,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_credit_user_pearls(_target_user_id uuid, _amount bigint, _reason text, _idempotency_key text)
RETURNS TABLE(adjustment_id uuid, reference text) LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT * FROM public._admin_wallet_adjust(_target_user_id,'pearl_credit'::wallet_adjustment_kind,_amount,_reason,_idempotency_key);
$$;
REVOKE EXECUTE ON FUNCTION public.admin_credit_user_pearls(uuid,bigint,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_credit_user_pearls(uuid,bigint,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_debit_user_pearls(_target_user_id uuid, _amount bigint, _reason text, _idempotency_key text)
RETURNS TABLE(adjustment_id uuid, reference text) LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT * FROM public._admin_wallet_adjust(_target_user_id,'pearl_debit'::wallet_adjustment_kind,_amount,_reason,_idempotency_key);
$$;
REVOKE EXECUTE ON FUNCTION public.admin_debit_user_pearls(uuid,bigint,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_debit_user_pearls(uuid,bigint,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reverse_coin_transfer(_transfer_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE t public.charging_coin_transfers%ROWTYPE;
BEGIN
  PERFORM public._require_perm('charging_coin_transfers.reverse');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT * INTO t FROM public.charging_coin_transfers WHERE id=_transfer_id FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF t.status <> 'completed' THEN RAISE EXCEPTION 'CANNOT_REVERSE_STATUS: %', t.status; END IF;
  IF EXISTS (SELECT 1 FROM public.charging_coin_transfer_reversals WHERE original_transfer_id=_transfer_id) THEN RAISE EXCEPTION 'ALREADY_REVERSED'; END IF;
  PERFORM public._wallet_apply(t.recipient_user_id, 'coins'::wallet_account, -t.amount, 'charging_coin_transfer_reverse'::ledger_reason, t.reference || '-REV', jsonb_build_object('original_reference',t.reference,'reason',_reason));
  PERFORM public._wallet_apply(t.agent_user_id, 'coins'::wallet_account, t.amount, 'charging_coin_transfer_reverse'::ledger_reason, t.reference || '-REV', jsonb_build_object('original_reference',t.reference,'reason',_reason));
  INSERT INTO public.charging_coin_transfer_reversals(original_transfer_id, reason, reversed_by) VALUES (_transfer_id, _reason, auth.uid());
  UPDATE public.charging_coin_transfers SET status='reversed' WHERE id=_transfer_id;
  INSERT INTO public.message_transaction_metadata(txn_type, txn_reference, from_user_id, to_user_id, amount, currency_code, metadata)
  VALUES ('coin_transfer_reverse', t.reference || '-REV', t.recipient_user_id, t.agent_user_id, t.amount, 'coins', jsonb_build_object('original_transfer_id',_transfer_id,'reason',_reason));
  PERFORM public._charge_audit('charging.coin_transfer.reverse','charging_coin_transfers',_transfer_id::text, jsonb_build_object('reason',_reason));
END $$;
REVOKE EXECUTE ON FUNCTION public.reverse_coin_transfer(uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reverse_coin_transfer(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reverse_pearl_transfer(_transfer_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE t public.charging_pearl_transfers%ROWTYPE;
BEGIN
  PERFORM public._require_perm('charging_pearl_transfers.reverse');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT * INTO t FROM public.charging_pearl_transfers WHERE id=_transfer_id FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF t.status <> 'completed' THEN RAISE EXCEPTION 'CANNOT_REVERSE_STATUS: %', t.status; END IF;
  IF EXISTS (SELECT 1 FROM public.charging_pearl_transfer_reversals WHERE original_transfer_id=_transfer_id) THEN RAISE EXCEPTION 'ALREADY_REVERSED'; END IF;
  PERFORM public._wallet_apply(t.to_user_id, 'diamonds'::wallet_account, -t.amount, 'charging_pearl_transfer_reverse'::ledger_reason, t.reference || '-REV', jsonb_build_object('original_reference',t.reference,'reason',_reason));
  PERFORM public._wallet_apply(t.from_user_id, 'diamonds'::wallet_account, t.amount, 'charging_pearl_transfer_reverse'::ledger_reason, t.reference || '-REV', jsonb_build_object('original_reference',t.reference,'reason',_reason));
  INSERT INTO public.charging_pearl_transfer_reversals(original_transfer_id, reason, reversed_by) VALUES (_transfer_id, _reason, auth.uid());
  UPDATE public.charging_pearl_transfers SET status='reversed' WHERE id=_transfer_id;
  INSERT INTO public.message_transaction_metadata(txn_type, txn_reference, from_user_id, to_user_id, amount, currency_code, metadata)
  VALUES ('pearl_transfer_reverse', t.reference || '-REV', t.to_user_id, t.from_user_id, t.amount, 'pearls', jsonb_build_object('original_transfer_id',_transfer_id,'reason',_reason));
  PERFORM public._charge_audit('charging.pearl_transfer.reverse','charging_pearl_transfers',_transfer_id::text, jsonb_build_object('reason',_reason));
END $$;
REVOKE EXECUTE ON FUNCTION public.reverse_pearl_transfer(uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reverse_pearl_transfer(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reverse_admin_wallet_adjustment(_adjustment_id uuid, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE r public.wallet_adjustment_requests%ROWTYPE; acct wallet_account; delta bigint; ledger_r ledger_reason;
BEGIN
  PERFORM public._require_perm('wallets.adjustments.review');
  IF _reason IS NULL OR length(_reason) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT * INTO r FROM public.wallet_adjustment_requests WHERE id=_adjustment_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF r.status <> 'applied' THEN RAISE EXCEPTION 'CANNOT_REVERSE_STATUS: %', r.status; END IF;
  CASE r.kind
    WHEN 'coin_credit'  THEN acct:='coins'::wallet_account;    delta:=-r.amount; ledger_r:='admin_coin_debit'::ledger_reason;
    WHEN 'coin_debit'   THEN acct:='coins'::wallet_account;    delta:= r.amount; ledger_r:='admin_coin_credit'::ledger_reason;
    WHEN 'pearl_credit' THEN acct:='diamonds'::wallet_account; delta:=-r.amount; ledger_r:='admin_pearl_debit'::ledger_reason;
    WHEN 'pearl_debit'  THEN acct:='diamonds'::wallet_account; delta:= r.amount; ledger_r:='admin_pearl_credit'::ledger_reason;
  END CASE;
  PERFORM public._wallet_apply(r.target_user_id, acct, delta, ledger_r, r.reference || '-REV', jsonb_build_object('original_adjustment_id',r.id,'reverse_reason',_reason));
  UPDATE public.wallet_adjustment_requests SET status='reversed', reversed_at=now() WHERE id=_adjustment_id;
  PERFORM public._charge_audit('charging.admin_adjust.reverse','wallet_adjustment_requests',_adjustment_id::text, jsonb_build_object('reason',_reason));
END $$;
REVOKE EXECUTE ON FUNCTION public.reverse_admin_wallet_adjustment(uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reverse_admin_wallet_adjustment(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.exchange_pearls_to_coins(_pearl_amount bigint, _rate_id uuid, _idempotency_key text)
RETURNS TABLE(exchange_id uuid, reference text, coins_amount bigint) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  agent_uid uuid := auth.uid();
  a_settings public.charging_agent_settings%ROWTYPE;
  rate public.pearl_coin_exchange_rates%ROWTYPE;
  new_id uuid; new_ref text; existing uuid;
  fee bigint; net_pearls bigint; c_amount bigint;
BEGIN
  IF agent_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _pearl_amount IS NULL OR _pearl_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF _idempotency_key IS NOT NULL THEN
    SELECT id INTO existing FROM public.pearl_coin_exchanges WHERE idempotency_key=_idempotency_key;
    IF existing IS NOT NULL THEN RETURN QUERY SELECT id, reference, coins_amount FROM public.pearl_coin_exchanges WHERE id=existing; RETURN; END IF;
  END IF;
  SELECT * INTO a_settings FROM public.charging_agent_settings WHERE user_id=agent_uid FOR UPDATE;
  IF a_settings.user_id IS NULL OR a_settings.status <> 'active' THEN RAISE EXCEPTION 'AGENT_NOT_ACTIVE'; END IF;
  IF NOT a_settings.can_exchange_pearls_to_coins THEN RAISE EXCEPTION 'AGENT_CANNOT_EXCHANGE'; END IF;
  SELECT * INTO rate FROM public.pearl_coin_exchange_rates WHERE id=_rate_id;
  IF rate.id IS NULL THEN RAISE EXCEPTION 'RATE_NOT_FOUND'; END IF;
  IF rate.status <> 'active' THEN RAISE EXCEPTION 'RATE_NOT_ACTIVE'; END IF;
  IF rate.starts_at IS NOT NULL AND rate.starts_at > now() THEN RAISE EXCEPTION 'RATE_NOT_STARTED'; END IF;
  IF rate.ends_at IS NOT NULL AND rate.ends_at < now() THEN RAISE EXCEPTION 'RATE_ENDED'; END IF;
  IF _pearl_amount < COALESCE(rate.min_exchange,0) THEN RAISE EXCEPTION 'BELOW_MIN'; END IF;
  IF rate.max_exchange IS NOT NULL AND _pearl_amount > rate.max_exchange THEN RAISE EXCEPTION 'ABOVE_MAX'; END IF;
  fee := FLOOR(_pearl_amount * COALESCE(rate.fee_percentage,0));
  net_pearls := _pearl_amount - fee;
  c_amount := FLOOR(net_pearls * rate.coins_per_pearl);
  IF c_amount <= 0 THEN RAISE EXCEPTION 'ZERO_COINS_RESULT'; END IF;
  new_ref := 'YC-EXC-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8);
  INSERT INTO public.pearl_coin_exchanges(reference, agent_user_id, agency_id, rate_id, pearl_amount, coins_amount, fee_amount, applied_rate, status, idempotency_key)
  VALUES (new_ref, agent_uid, a_settings.agency_id, _rate_id, _pearl_amount, c_amount, fee, rate.coins_per_pearl, 'pending', _idempotency_key) RETURNING id INTO new_id;
  PERFORM public._wallet_apply(agent_uid, 'diamonds'::wallet_account, -_pearl_amount, 'pearl_to_coin_exchange'::ledger_reason, new_ref, jsonb_build_object('exchange_id',new_id,'rate',rate.coins_per_pearl,'fee',fee));
  PERFORM public._wallet_apply(agent_uid, 'coins'::wallet_account, c_amount, 'pearl_to_coin_exchange'::ledger_reason, new_ref, jsonb_build_object('exchange_id',new_id,'pearls',_pearl_amount));
  UPDATE public.pearl_coin_exchanges SET status='completed', completed_at=now() WHERE id=new_id;
  INSERT INTO public.message_transaction_metadata(txn_type, txn_reference, from_user_id, to_user_id, amount, currency_code, metadata)
  VALUES ('pearl_to_coin_exchange', new_ref, agent_uid, agent_uid, c_amount, 'coins', jsonb_build_object('exchange_id',new_id,'pearls',_pearl_amount,'rate',rate.coins_per_pearl,'fee',fee));
  PERFORM public._charge_audit('charging.exchange','pearl_coin_exchanges',new_id::text, jsonb_build_object('pearls',_pearl_amount,'coins',c_amount,'rate',rate.coins_per_pearl));
  RETURN QUERY SELECT new_id, new_ref, c_amount;
END $$;
REVOKE EXECUTE ON FUNCTION public.exchange_pearls_to_coins(bigint,uuid,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.exchange_pearls_to_coins(bigint,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_pearl_exchange_rate(
  _country text, _agency_id uuid, _coins_per_pearl numeric,
  _fee_percentage numeric, _min_exchange bigint, _max_exchange bigint,
  _daily_limit bigint, _monthly_limit bigint, _status text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE new_id uuid;
BEGIN
  PERFORM public._require_perm('pearl_exchanges.manage_rates');
  INSERT INTO public.pearl_coin_exchange_rates(country, agency_id, coins_per_pearl, fee_percentage, min_exchange, max_exchange, daily_limit, monthly_limit, status, created_by, starts_at)
  VALUES (_country, _agency_id, _coins_per_pearl, COALESCE(_fee_percentage,0), COALESCE(_min_exchange,100), COALESCE(_max_exchange,10000000), COALESCE(_daily_limit,100000000), COALESCE(_monthly_limit,3000000000), COALESCE(_status,'active'), auth.uid(), now()) RETURNING id INTO new_id;
  PERFORM public._charge_audit('charging.rate.create','pearl_coin_exchange_rates', new_id::text, jsonb_build_object('coins_per_pearl',_coins_per_pearl));
  RETURN new_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.create_pearl_exchange_rate(text,uuid,numeric,numeric,bigint,bigint,bigint,bigint,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pearl_exchange_rate(text,uuid,numeric,numeric,bigint,bigint,bigint,bigint,text) TO authenticated;
