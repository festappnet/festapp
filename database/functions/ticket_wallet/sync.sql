-- Registration precedes external I/O. No FK cascade may erase a remote identity.
CREATE OR REPLACE FUNCTION public.claim_ticket_wallet(p_ticket bigint DEFAULT NULL,p_object text DEFAULT NULL,p_class text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE w eshop.ticket_wallet_objects; c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations; lease_id uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM public.require_service_role();
 IF p_ticket IS NOT NULL THEN PERFORM public.refresh_ticket_wallet_term_internal(p_ticket); END IF;
 IF p_ticket IS NOT NULL AND p_object IS NOT NULL THEN
  SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket AND revoked_at IS NULL AND expires_at>now();
  SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization;
  IF c.ticket_id IS NULL OR i.organization IS NULL OR p_object NOT LIKE i.issuer||'.%' OR p_class NOT LIKE i.issuer||'.%' THEN RETURN NULL; END IF;
  INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id)
  VALUES(c.ticket_id,c.organization,c.occasion,i.issuer,i.environment,p_object,p_class) ON CONFLICT(ticket_id) DO NOTHING;
 END IF;
 SELECT * INTO w FROM eshop.ticket_wallet_objects
 WHERE (p_ticket IS NULL OR ticket_id=p_ticket) AND (p_ticket IS NOT NULL OR next_attempt<=now())
 AND (lease_until IS NULL OR lease_until<=now()) ORDER BY next_attempt,ticket_id LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF w.ticket_id IS NULL THEN RETURN NULL; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal(w.ticket_id);
 UPDATE eshop.ticket_wallet_objects SET lease=lease_id,lease_until=clock_timestamp()+interval '45 seconds',next_attempt=now()+interval '1 minute' WHERE ticket_id=w.ticket_id;
 RETURN jsonb_build_object('ticketId',w.ticket_id,'organization',w.organization,'occasion',w.occasion,'issuer',w.issuer,'environment',w.environment,
 'objectId',w.object_id,'classId',w.class_id,'lease',lease_id,'projection',public.ticket_wallet_projection_internal(w.ticket_id));
END $$;

-- Every outbound request checks its lease and reserves a globally spaced issuer slot.
CREATE OR REPLACE FUNCTION public.reserve_ticket_wallet_request(p_ticket bigint,p_lease uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE w eshop.ticket_wallet_objects; slot timestamptz;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO w FROM eshop.ticket_wallet_objects WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp()+interval '5 seconds' FOR UPDATE;
 IF w.ticket_id IS NULL THEN RAISE EXCEPTION 'wallet_lease_lost'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('google-wallet:'||w.issuer,0));
 IF NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=w.organization AND issuer=w.issuer AND environment=w.environment) THEN RAISE EXCEPTION 'wallet_identity_changed'; END IF;
 SELECT greatest(max(next_request_at),clock_timestamp()) INTO slot FROM eshop.ticket_wallet_integrations WHERE issuer=w.issuer;
 UPDATE eshop.ticket_wallet_integrations SET next_request_at=slot+interval '125 milliseconds' WHERE issuer=w.issuer;
 IF slot IS NULL OR slot>clock_timestamp()+interval '2 seconds' THEN RAISE EXCEPTION 'wallet_capacity'; END IF;
 RETURN greatest(0,ceil(extract(epoch FROM slot-clock_timestamp())*1000))::integer;
END $$;

CREATE OR REPLACE FUNCTION public.finish_ticket_wallet(p_ticket bigint,p_lease uuid,p_ok boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.ticket_wallet_objects SET lease=NULL,lease_until=NULL,
 last_synced=CASE WHEN p_ok THEN now() ELSE last_synced END,
 next_attempt=now()+CASE WHEN p_ok THEN interval '3 minutes' ELSE make_interval(secs=>least(3600,15*power(2,least(failures,8)))::integer) END,
 failures=CASE WHEN p_ok THEN 0 ELSE failures+1 END,last_error=CASE WHEN p_ok THEN NULL ELSE 'google_sync_unavailable' END
 WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp();
 RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION public.ticket_wallet_health()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('objects',count(*),'due',count(*) FILTER(WHERE next_attempt<=now()),
 'neverSynced',count(*) FILTER(WHERE last_synced IS NULL),'oldestSync',min(coalesce(last_synced,created_at)),
 'failed',count(*) FILTER(WHERE failures>0)) FROM eshop.ticket_wallet_objects);
END $$;
REVOKE ALL ON FUNCTION public.claim_ticket_wallet(bigint,text,text),public.reserve_ticket_wallet_request(bigint,uuid),public.finish_ticket_wallet(bigint,uuid,boolean),public.ticket_wallet_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ticket_wallet(bigint,text,text),public.reserve_ticket_wallet_request(bigint,uuid),public.finish_ticket_wallet(bigint,uuid,boolean),public.ticket_wallet_health() TO service_role;
