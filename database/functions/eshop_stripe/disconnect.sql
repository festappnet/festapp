CREATE OR REPLACE FUNCTION public.get_stripe_disconnect_impact(p_unit bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; result jsonb;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 SELECT * INTO c FROM eshop.stripe_connections WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted','revoked')
  ORDER BY (state<>'revoked') DESC,created_at DESC LIMIT 1;
 IF c.id IS NULL THEN RAISE EXCEPTION 'STRIPE_CONNECTION_UNAVAILABLE'; END IF;
 SELECT jsonb_build_object('connectionId',c.id,'businessName',c.business_name,
  'openAttempts',count(*) FILTER(WHERE state IN ('preparing','open','uncertain') OR lease_expires_at>statement_timestamp() OR refund_cursor IS NOT NULL OR session_lookup_cursor IS NOT NULL),
  'historyCount',count(*),'lastSyncedAt',CASE WHEN bool_or(last_synced_at IS NULL) THEN NULL ELSE min(last_synced_at) END,
  'disconnectState',(SELECT state FROM eshop.stripe_disconnect_intents WHERE connection_id=c.id AND state<>'completed')) INTO result
 FROM eshop.stripe_checkout_attempts WHERE connection_id=c.id;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_disconnect_impact(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_stripe_disconnect_impact(bigint,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.begin_stripe_disconnect(p_unit bigint,p_livemode boolean,p_expected_connection uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; intent eshop.stripe_disconnect_intents;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 PERFORM 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE o.unit=p_unit ORDER BY f.id FOR UPDATE OF f;
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 SELECT * INTO c FROM eshop.stripe_connections WHERE id=p_expected_connection AND unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_RECIPIENT_CHANGED'; END IF;
 SELECT * INTO intent FROM eshop.stripe_disconnect_intents WHERE connection_id=c.id AND state<>'completed';
 IF FOUND THEN
  IF intent.actor<>auth.uid() THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_PENDING'; END IF;
  RETURN jsonb_build_object('intentId',intent.id);
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.stripe_connection_flows WHERE unit_id=p_unit AND livemode=p_livemode AND expires_at>clock_timestamp() AND state IN ('pending','claimed','uncertain')) THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_PENDING'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE connection_id=c.id AND
  (state IN ('preparing','open','uncertain') OR lease_expires_at>clock_timestamp() OR refund_cursor IS NOT NULL OR session_lookup_cursor IS NOT NULL)) THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_OPEN_ATTEMPTS'; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.connect',p_unit,c.organization_id),jsonb_build_object('actor',auth.uid(),'unit',p_unit,'organization',c.organization_id));
 INSERT INTO eshop.stripe_disconnect_intents(connection_id,actor) VALUES(c.id,auth.uid()) RETURNING * INTO intent;
 UPDATE eshop.stripe_connections SET paused=true,next_check_at=clock_timestamp() WHERE id=c.id;
 INSERT INTO eshop.stripe_connection_audit(connection_id,actor,action) VALUES(c.id,auth.uid(),'paused');
 RETURN jsonb_build_object('intentId',intent.id);
END $$;
REVOKE ALL ON FUNCTION public.begin_stripe_disconnect(bigint,boolean,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.begin_stripe_disconnect(bigint,boolean,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_stripe_disconnect_internal(p_intent uuid,p_actor uuid,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE intent eshop.stripe_disconnect_intents; c eshop.stripe_connections;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT intent FROM eshop.stripe_disconnect_intents WHERE id=p_intent AND actor=p_actor FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=intent.connection_id AND livemode=p_livemode;
 PERFORM public.check_stripe_unit_manager_internal(c.unit_id,p_actor);
 IF intent.state='completed' THEN RETURN jsonb_build_object('disposition','replay','result',intent.result); END IF;
 IF intent.state<>'pending' THEN RETURN jsonb_build_object('disposition','uncertain'); END IF;
 UPDATE eshop.stripe_disconnect_intents SET state='claimed',claimed_at=clock_timestamp() WHERE id=intent.id;
 RETURN jsonb_build_object('disposition','dispatch','accountId',c.account_id);
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_disconnect_internal(uuid,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_disconnect_internal(uuid,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.finish_stripe_disconnect_internal(p_intent uuid,p_success boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE intent eshop.stripe_disconnect_intents; v_result jsonb;
BEGIN
 PERFORM public.require_service_role();
 -- Lock connection before intent, matching lifecycle completion.
 PERFORM 1 FROM eshop.stripe_connections WHERE id=(SELECT connection_id FROM eshop.stripe_disconnect_intents WHERE id=p_intent) FOR UPDATE;
 SELECT * INTO STRICT intent FROM eshop.stripe_disconnect_intents WHERE id=p_intent FOR UPDATE;
 IF intent.state='completed' THEN RETURN intent.result; END IF;
 IF intent.state<>'claimed' OR p_success IS NULL THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_INVALID'; END IF;
 IF NOT p_success THEN
  UPDATE eshop.stripe_disconnect_intents SET state='uncertain' WHERE id=intent.id;
  UPDATE eshop.stripe_connections SET next_check_at=clock_timestamp() WHERE id=intent.connection_id;
  RETURN jsonb_build_object('disconnected',false,'uncertain',true);
 END IF;
 v_result:=jsonb_build_object('disconnected',true);
 UPDATE eshop.stripe_connections SET state='revoked',paused=true,charges_enabled=false,card_payments_active=false,payouts_enabled=false,
  status_lease=NULL,status_lease_expires_at=NULL,checked_at=clock_timestamp(),next_check_at=clock_timestamp()+interval '1 day' WHERE id=intent.connection_id;
 UPDATE eshop.stripe_disconnect_intents SET state='completed',result=v_result,completed_at=clock_timestamp() WHERE id=intent.id;
 INSERT INTO eshop.stripe_connection_audit(connection_id,actor,action) VALUES(intent.connection_id,intent.actor,'revoked');
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.finish_stripe_disconnect_internal(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_stripe_disconnect_internal(uuid,boolean) TO service_role;
