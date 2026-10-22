CREATE OR REPLACE FUNCTION public.claim_stripe_connection_status_internal(p_account text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; lease uuid;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM eshop.stripe_connections WHERE account_id=p_account AND livemode=p_livemode FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('disposition','unrelated'); END IF;
 IF c.status_lease_expires_at>clock_timestamp() THEN RETURN jsonb_build_object('disposition','busy'); END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_connections SET status_lease=lease,status_lease_expires_at=clock_timestamp()+interval '120 seconds' WHERE id=c.id;
 RETURN jsonb_build_object('disposition','dispatch','connectionId',c.id,'lease',lease);
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_connection_status_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_connection_status_internal(text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.commit_stripe_connection_status_internal(p_connection uuid,p_lease uuid,p_status jsonb,p_event jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; prior eshop.stripe_event_inbox; next_state text; unavailable boolean; result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=p_connection FOR UPDATE;
 IF p_event IS NOT NULL THEN
  IF p_event->>'id' IS NULL OR p_event->>'id' !~ '^evt_[A-Za-z0-9]+$' OR p_event->>'bodyHash' IS NULL OR p_event->>'bodyHash' !~ '^[a-f0-9]{64}$'
   OR p_event->>'accountId' IS DISTINCT FROM c.account_id OR (p_event->>'livemode')::boolean IS DISTINCT FROM c.livemode
   OR p_event->>'type' IS NULL OR p_event->>'type' NOT IN ('account.updated','account.application.deauthorized','account.application.authorized') THEN RAISE EXCEPTION 'STRIPE_EVENT_IDENTITY_INVALID'; END IF;
  SELECT * INTO prior FROM eshop.stripe_event_inbox WHERE connection_id=c.id AND event_id=p_event->>'id';
  IF FOUND THEN
   IF prior.body_sha256<>p_event->>'bodyHash' OR prior.receipt IS NULL THEN RAISE EXCEPTION 'STRIPE_EVENT_RECEIPT_INVALID'; END IF;
   -- The duplicate may have claimed a fresh read lease; release only that lease.
   UPDATE eshop.stripe_connections SET status_lease=NULL,status_lease_expires_at=NULL WHERE id=c.id AND status_lease=p_lease;
   RETURN prior.receipt;
  END IF;
 END IF;
 IF p_lease IS NULL OR c.status_lease IS DISTINCT FROM p_lease OR c.status_lease_expires_at IS NULL OR c.status_lease_expires_at<=clock_timestamp()
  OR p_status->>'accountId' IS DISTINCT FROM c.account_id THEN RAISE EXCEPTION 'STRIPE_CONNECTION_STATUS_INVALID'; END IF;
 unavailable:=coalesce(p_status->'accessUnavailable'='true'::jsonb,false);
 IF NOT unavailable AND EXISTS(SELECT 1 FROM unnest(ARRAY['modelVerified','chargesEnabled','payoutsEnabled','cardPaymentsActive']) name
  WHERE jsonb_typeof(p_status->name) IS DISTINCT FROM 'boolean') THEN RAISE EXCEPTION 'STRIPE_CONNECTION_STATUS_INVALID'; END IF;
 next_state:=CASE WHEN c.state='retired' THEN 'retired' WHEN c.state='revoked' OR unavailable THEN 'revoked'
  WHEN p_status->'modelVerified'='true'::jsonb AND p_status->'chargesEnabled'='true'::jsonb AND p_status->'cardPaymentsActive'='true'::jsonb THEN 'connected' ELSE 'restricted' END;
 UPDATE eshop.stripe_connections SET state=next_state,
  business_name=CASE WHEN unavailable THEN business_name ELSE nullif(left(p_status->>'businessName',200),'') END,
  country=CASE WHEN unavailable THEN country ELSE p_status->>'country' END,
  model_verified=CASE WHEN unavailable THEN model_verified ELSE (p_status->>'modelVerified')::boolean END,
  charges_enabled=NOT unavailable AND coalesce((p_status->>'chargesEnabled')::boolean,false),
  payouts_enabled=NOT unavailable AND coalesce((p_status->>'payoutsEnabled')::boolean,false),
  card_payments_active=NOT unavailable AND coalesce((p_status->>'cardPaymentsActive')::boolean,false),
  paused=paused OR next_state IN ('revoked','retired') OR p_status->'modelVerified'='false'::jsonb,
  checked_at=clock_timestamp(),next_check_at=clock_timestamp()+CASE WHEN next_state IN ('retired','revoked') THEN interval '1 day' ELSE interval '15 minutes' END,
  status_failures=0,status_lease=NULL,status_lease_expires_at=NULL WHERE id=c.id;
 IF next_state<>c.state OR unavailable OR c.charges_enabled IS DISTINCT FROM (p_status->>'chargesEnabled')::boolean
  OR c.payouts_enabled IS DISTINCT FROM (p_status->>'payoutsEnabled')::boolean OR c.model_verified IS DISTINCT FROM (p_status->>'modelVerified')::boolean THEN
  INSERT INTO eshop.stripe_connection_audit(connection_id,action) VALUES(c.id,CASE WHEN next_state='revoked' AND c.state<>'revoked' THEN 'revoked' ELSE 'status_changed' END);
 END IF;
 result:=jsonb_build_object('committed',true,'connectionId',c.id);
 IF unavailable THEN
  UPDATE eshop.stripe_disconnect_intents SET state='completed',result=jsonb_build_object('disconnected',true),completed_at=clock_timestamp()
   WHERE connection_id=c.id AND state<>'completed';
 END IF;
 IF p_event IS NOT NULL THEN
  INSERT INTO eshop.stripe_event_inbox(connection_id,event_id,body_sha256,event_type,provider_created_at,committed_at,receipt)
   VALUES(c.id,p_event->>'id',p_event->>'bodyHash',p_event->>'type',to_timestamp((p_event->>'created')::bigint),clock_timestamp(),result);
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.commit_stripe_connection_status_internal(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.commit_stripe_connection_status_internal(uuid,uuid,jsonb,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_stripe_connection_status_internal(p_connection uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.stripe_connections SET status_failures=least(status_failures+1,1000),status_lease=NULL,status_lease_expires_at=NULL,
  next_check_at=clock_timestamp()+make_interval(secs=>least(3600,30*power(2,least(status_failures,7)))::integer)
 WHERE id=p_connection AND status_lease=p_lease AND p_lease IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION public.fail_stripe_connection_status_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fail_stripe_connection_status_internal(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_recoverable_stripe_connections_internal(p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT coalesce(jsonb_agg(jsonb_build_object('accountId',x.account_id,'connectionId',x.id)),'[]'::jsonb) INTO result FROM (
  SELECT id,account_id FROM eshop.stripe_connections WHERE livemode=p_livemode AND next_check_at<=statement_timestamp()
   AND coalesce(status_lease_expires_at<=statement_timestamp(),true) ORDER BY next_check_at,id LIMIT 2
 ) x;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_recoverable_stripe_connections_internal(boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_recoverable_stripe_connections_internal(boolean) TO service_role;
