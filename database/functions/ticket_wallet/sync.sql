-- Registration precedes external I/O. Claims lock only the scheduling row.
CREATE OR REPLACE FUNCTION public.claim_ticket_wallet(p_ticket bigint DEFAULT NULL,p_object text DEFAULT NULL,p_class text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE q eshop.ticket_wallet_work; w eshop.ticket_wallet_objects; c eshop.ticket_wallet_capabilities;
 i eshop.ticket_wallet_integrations; lease_id uuid:=extensions.gen_random_uuid(); projection jsonb; added boolean;
BEGIN
 PERFORM public.require_service_role();
 IF p_ticket IS NOT NULL AND p_object IS NOT NULL THEN
  SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket AND revoked_at IS NULL AND expires_at>now();
  SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization;
  IF c.ticket_id IS NULL OR i.organization IS NULL OR i.paused OR p_object NOT LIKE i.issuer||'.%' OR p_class NOT LIKE i.issuer||'.%' THEN RETURN NULL; END IF;
  INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id)
  VALUES(c.ticket_id,c.organization,c.occasion,i.issuer,i.environment,p_object,p_class) ON CONFLICT(ticket_id) DO NOTHING;
  added:=FOUND;
  IF added THEN PERFORM public.enqueue_wallet_class_internal(p_ticket); END IF;
  -- An explicit Save retries through the same owner; it cannot steal a lease.
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
 END IF;
 WITH tenant_turns AS MATERIALIZED (
  SELECT organization,max(claimed_at) last_claim FROM eshop.ticket_wallet_work GROUP BY organization
 )
 SELECT work.* INTO q FROM eshop.ticket_wallet_work work
 JOIN tenant_turns turns ON turns.organization=work.organization WHERE kind IN ('class','object')
 AND requested>applied AND due_at<=now() AND (lease_until IS NULL OR lease_until<=clock_timestamp())
 AND EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations integ WHERE integ.organization=work.organization AND NOT integ.paused)
 AND (p_ticket IS NULL OR (kind='object' AND ticket_id=p_ticket) OR (kind='class' AND resource=(SELECT class_id FROM eshop.ticket_wallet_objects WHERE ticket_id=p_ticket)))
 AND (kind='class' OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_work cls JOIN eshop.ticket_wallet_objects obj ON obj.class_id=cls.resource
  WHERE cls.kind='class' AND obj.ticket_id=work.ticket_id AND cls.applied>0)
  OR NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=work.ticket_id)
  OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_capabilities WHERE ticket_id=work.ticket_id AND revoked_at IS NOT NULL))
 ORDER BY turns.last_claim,dirty_since,CASE WHEN kind='class' THEN 0 ELSE 1 END,resource LIMIT 1 FOR UPDATE OF work SKIP LOCKED;
 IF q.resource IS NULL THEN RETURN NULL; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('wallet-claim:'||q.organization,0));
 IF NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=q.organization AND NOT paused) THEN RETURN NULL; END IF;
 UPDATE eshop.ticket_wallet_work SET claimed_at=clock_timestamp(),lease=lease_id,lease_until=clock_timestamp()+interval '45 seconds',captured=requested,
 boundary_at=CASE WHEN q.kind='object' THEN (SELECT min(t) FROM (
  SELECT o.start_time t FROM public.occasions o WHERE o.id=q.occasion UNION ALL
  SELECT o.end_time FROM public.occasions o WHERE o.id=q.occasion UNION ALL
  SELECT cap.expires_at FROM eshop.ticket_wallet_capabilities cap WHERE cap.ticket_id=q.ticket_id) times WHERE t>now()) ELSE NULL END
 WHERE provider=q.provider AND kind=q.kind AND resource=q.resource;
 SELECT * INTO w FROM eshop.ticket_wallet_objects WHERE ticket_id=q.ticket_id;
 projection:=public.ticket_wallet_projection_internal(q.ticket_id);
 IF q.kind='class' THEN
  SELECT jsonb_build_object('state','ACTIVE','ticket',jsonb_build_object('ticket_symbol','class-metadata'),
   'branding',(SELECT jsonb_build_object('APP_NAME',data->'APP_NAME','DEFAULT_URL',data->'DEFAULT_URL','WALLET_LOGO_URL',data->'WALLET_LOGO_URL') FROM public.organizations WHERE id=q.organization),
   'occasion',jsonb_build_object('id',o.id,'title',o.title,'start_time',o.start_time,'end_time',o.end_time,'data',o.data,
   'ticketFeature',(SELECT f FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket')))
   INTO projection FROM public.occasions o WHERE id=q.occasion AND organization=q.organization;
 END IF;
 RETURN jsonb_build_object('kind',q.kind,'resource',q.resource,'version',q.requested,'ticketId',w.ticket_id,'organization',w.organization,
 'occasion',w.occasion,'issuer',w.issuer,'environment',w.environment,'objectId',w.object_id,'classId',w.class_id,'lease',lease_id,'projection',projection);
END $$;

-- A globally unique lease identifies either class or object work.
CREATE OR REPLACE FUNCTION public.reserve_ticket_wallet_request(p_ticket bigint,p_lease uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE q eshop.ticket_wallet_work; w eshop.ticket_wallet_objects; slot timestamptz;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO q FROM eshop.ticket_wallet_work WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp()+interval '10 seconds' FOR UPDATE;
 IF q.resource IS NULL THEN RAISE EXCEPTION 'wallet_lease_lost'; END IF;
 SELECT * INTO w FROM eshop.ticket_wallet_objects WHERE ticket_id=q.ticket_id;
 PERFORM pg_advisory_xact_lock(hashtextextended('google-wallet:'||w.issuer,0));
 IF NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=w.organization AND issuer=w.issuer AND environment=w.environment) THEN RAISE EXCEPTION 'wallet_identity_changed'; END IF;
 SELECT greatest(max(next_request_at),clock_timestamp()) INTO slot FROM eshop.ticket_wallet_integrations WHERE issuer=w.issuer;
 IF slot IS NULL OR slot>clock_timestamp()+interval '2 seconds' THEN RAISE EXCEPTION 'wallet_capacity'; END IF;
 UPDATE eshop.ticket_wallet_integrations SET next_request_at=slot+interval '125 milliseconds' WHERE issuer=w.issuer;
 RETURN greatest(0,ceil(extract(epoch FROM slot-clock_timestamp())*1000))::integer;
END $$;

CREATE OR REPLACE FUNCTION public.finish_ticket_wallet(p_ticket bigint,p_lease uuid,p_ok boolean,p_error text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.ticket_wallet_work q SET lease=NULL,lease_until=NULL,
 applied=CASE WHEN p_ok THEN captured ELSE applied END,
 last_success=CASE WHEN p_ok THEN now() ELSE last_success END,
 due_at=CASE WHEN p_ok THEN now() ELSE now()+make_interval(secs=>least(3600,CASE WHEN p_error='wallet_capacity' THEN 5 ELSE 15*power(2,least(failures,8)) END)::integer) END,
 failures=CASE WHEN p_ok THEN 0 ELSE failures+CASE WHEN p_error='wallet_capacity' THEN 0 ELSE 1 END END,last_error=CASE WHEN p_ok THEN NULL WHEN p_error='wallet_capacity' THEN 'quota_wait' WHEN p_error='wallet_class_pending' THEN 'class_pending' ELSE 'google_sync_unavailable' END
 WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp();
 RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION public.ticket_wallet_health()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('objects',(SELECT count(*) FROM eshop.ticket_wallet_objects),
 'due',count(*) FILTER(WHERE requested>applied AND due_at<=now()),'dirty',count(*) FILTER(WHERE requested>applied),
 'versionGap',coalesce(sum(requested-applied),0),'oldestDirty',min(dirty_since) FILTER(WHERE requested>applied),
 'leased',count(*) FILTER(WHERE lease_until>now()),'retry',count(*) FILTER(WHERE failures>0 AND failures<10),'quotaWait',count(*) FILTER(WHERE last_error='quota_wait'),
 'persistentErrors',count(*) FILTER(WHERE failures>=10),'lastSuccess',max(last_success),
 'quotaWaitUntil',(SELECT max(next_request_at) FROM eshop.ticket_wallet_integrations),
 'scopes',coalesce(jsonb_agg(jsonb_build_object('kind',kind,'resource',resource,'cursor',cursor_ticket,'version',cursor_version)) FILTER(WHERE kind IN ('occasion','organization') AND requested>applied),'[]')) FROM eshop.ticket_wallet_work);
END $$;
REVOKE ALL ON FUNCTION public.claim_ticket_wallet(bigint,text,text),public.reserve_ticket_wallet_request(bigint,uuid),public.finish_ticket_wallet(bigint,uuid,boolean,text),public.ticket_wallet_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ticket_wallet(bigint,text,text),public.reserve_ticket_wallet_request(bigint,uuid),public.finish_ticket_wallet(bigint,uuid,boolean,text),public.ticket_wallet_health() TO service_role;
