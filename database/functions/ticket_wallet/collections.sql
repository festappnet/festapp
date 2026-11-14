-- A collection grants only the delivered set, never future tickets in its order.
CREATE OR REPLACE FUNCTION public.prepare_ticket_wallet_collection(p_message uuid,p_tickets bigint[],p_hash text DEFAULT NULL,p_sealed jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; i eshop.ticket_wallet_integrations; o public.occasions;
 c eshop.ticket_wallet_capabilities; b eshop.ticket_wallet_collections; ids bigint[]; members jsonb:='[]'; v_fingerprint text;
BEGIN
 PERFORM public.require_service_role();
 IF p_tickets IS NULL OR cardinality(p_tickets) NOT BETWEEN 2 AND 1000 THEN RETURN NULL; END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO ids FROM unnest(p_tickets) x WHERE x>0;
 IF cardinality(ids) IS DISTINCT FROM cardinality(p_tickets) THEN RAISE invalid_parameter_value; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR NOT public.email_intent_valid(m) THEN RAISE insufficient_privilege; END IF;
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=m.organization AND collection_enabled AND NOT paused AND (publishing_ready OR apple_publishing_ready);
 SELECT * INTO o FROM public.occasions WHERE id=m.occasion AND organization=m.organization;
 IF i.organization IS NULL OR o.end_time IS NULL OR o.end_time+interval '7 days'<=now() THEN RETURN NULL; END IF;
 FOR c IN SELECT * FROM eshop.ticket_wallet_capabilities WHERE ticket_id=ANY(ids) ORDER BY ticket_id FOR UPDATE LOOP
  PERFORM public.refresh_ticket_wallet_term_internal(c.ticket_id);
  IF c.organization IS DISTINCT FROM m.organization OR c.occasion IS DISTINCT FROM m.occasion OR c.order_id IS DISTINCT FROM m.order_id
   OR c.recipient IS DISTINCT FROM m.recipient OR c.revoked_at IS NOT NULL OR c.reissue_after IS NOT NULL
   OR public.ticket_wallet_state_internal(c.ticket_id) NOT IN ('ACTIVE','COMPLETED') THEN RAISE insufficient_privilege; END IF;
  members:=members||jsonb_build_array(jsonb_build_object('ticketId',c.ticket_id,'tokenHash',c.token_hash,'generation',c.generation));
 END LOOP;
 IF jsonb_array_length(members)<>cardinality(ids) THEN RAISE insufficient_privilege; END IF;
 v_fingerprint:=encode(extensions.digest(members::text,'sha256'),'hex');
 SELECT * INTO b FROM eshop.ticket_wallet_collections WHERE organization=m.organization AND occasion=m.occasion AND order_id=m.order_id AND recipient=m.recipient AND ticket_wallet_collections.fingerprint=v_fingerprint;
 IF b.id IS NULL AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  IF p_hash !~ '^[a-f0-9]{64}$' OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash)
   OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_audit WHERE token_hash=p_hash) THEN RAISE invalid_parameter_value; END IF;
  INSERT INTO eshop.ticket_wallet_collections(organization,occasion,order_id,recipient,message_id,members,fingerprint,token_hash,sealed,event_end_at,expires_at)
  VALUES(m.organization,m.occasion,m.order_id,m.recipient,m.message_id,members,v_fingerprint,p_hash,p_sealed,o.end_time,o.end_time+interval '7 days')
  ON CONFLICT(organization,occasion,order_id,recipient,fingerprint) DO UPDATE SET event_end_at=excluded.event_end_at,expires_at=excluded.expires_at RETURNING * INTO b;
 END IF;
 IF b.revoked_at IS NOT NULL THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('organization',m.organization,'occasion',m.occasion,'orderId',m.order_id,'ticketIds',to_jsonb(ids),'fingerprint',v_fingerprint,
  'webOrigin',i.web_origin,'badgeUrls',i.badge_urls,'providers',jsonb_build_object('google',i.publishing_ready,'apple',i.apple_publishing_ready),
  'source',CASE WHEN b.id IS NOT NULL THEN jsonb_build_object('sealed',b.sealed,'tokenHash',b.token_hash) END);
END $$;

-- Shared authorization owner. It does not expose QR data for an entire large order.
CREATE OR REPLACE FUNCTION public.ticket_wallet_scope_internal(p_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; b eshop.ticket_wallet_collections; i eshop.ticket_wallet_integrations;
 member jsonb; tickets jsonb:='[]'; common jsonb; item jsonb; result jsonb; v_state text;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash !~ '^[a-f0-9]{64}$' THEN RETURN NULL; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal((SELECT ticket_id FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash));
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash AND revoked_at IS NULL AND expires_at>now() AND reissue_after IS NULL;
 IF c.ticket_id IS NOT NULL THEN
  SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization AND NOT paused;
 ELSE
  UPDATE eshop.ticket_wallet_collections x SET event_end_at=o.end_time,expires_at=o.end_time+interval '7 days'
   FROM public.occasions o WHERE x.token_hash=p_hash AND x.revoked_at IS NULL AND x.occasion=o.id AND x.organization=o.organization
    AND o.end_time IS NOT NULL AND x.event_end_at IS DISTINCT FROM o.end_time;
  SELECT * INTO b FROM eshop.ticket_wallet_collections WHERE token_hash=p_hash AND revoked_at IS NULL AND expires_at>now();
  IF b.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=b.organization AND collection_enabled AND NOT paused;
 END IF;
 IF i.organization IS NULL THEN RETURN NULL; END IF;
 common:=jsonb_build_object('organization',i.organization,'occasion',coalesce(c.occasion,b.occasion),'issuer',i.issuer,'environment',i.environment,
  'webOrigin',i.web_origin,'providers',jsonb_build_object('google',i.publishing_ready,'apple',i.apple_publishing_ready),
  'applePassTypeIdentifier',i.apple_pass_type_identifier,'appleTeamIdentifier',i.apple_team_identifier);
 IF c.ticket_id IS NOT NULL THEN
  item:=common||jsonb_build_object('ticketId',c.ticket_id,'capabilityHash',c.token_hash,'projection',public.ticket_wallet_projection_internal(c.ticket_id));
  result:=item||jsonb_build_object('kind','ticket','tickets',jsonb_build_array(item),'ticketCount',1,'originalCount',1,'state',item#>>'{projection,state}');
 ELSE
  FOR member IN SELECT value FROM jsonb_array_elements(b.members) LOOP
   PERFORM public.refresh_ticket_wallet_term_internal((member->>'ticketId')::bigint);
   SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=(member->>'ticketId')::bigint AND token_hash=member->>'tokenHash'
    AND generation=(member->>'generation')::integer AND organization=b.organization AND occasion=b.occasion AND order_id=b.order_id
    AND recipient=b.recipient AND revoked_at IS NULL AND reissue_after IS NULL AND expires_at>now();
   IF c.ticket_id IS NULL THEN CONTINUE; END IF;
   v_state:=public.ticket_wallet_state_internal(c.ticket_id);
   IF v_state<>'ACTIVE' THEN CONTINUE; END IF;
   tickets:=tickets||jsonb_build_array(common||jsonb_build_object('ticketId',c.ticket_id,'capabilityHash',c.token_hash,'projection',jsonb_build_object('state',v_state)));
  END LOOP;
  IF jsonb_array_length(tickets)=0 THEN RETURN NULL; END IF;
  result:=common||jsonb_build_object('kind','collection','tickets',tickets,'ticketCount',jsonb_array_length(tickets),'originalCount',jsonb_array_length(b.members),'state','ACTIVE');
 END IF;
 RETURN result||jsonb_build_object('revision',encode(extensions.digest(result::text,'sha256'),'hex'));
END $$;

-- The service may load only the already-authorized portion selected by its provider planner.
CREATE OR REPLACE FUNCTION public.get_ticket_wallet_projections(p_hash text,p_tickets bigint[],p_revision text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE scope jsonb; item jsonb; result jsonb:='[]'; ids bigint[];
BEGIN
 PERFORM public.require_service_role();
 IF p_tickets IS NULL OR cardinality(p_tickets) NOT BETWEEN 1 AND 10 THEN RETURN NULL; END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO ids FROM unnest(p_tickets) x;
 IF cardinality(ids) IS DISTINCT FROM cardinality(p_tickets) THEN RETURN NULL; END IF;
 scope:=public.ticket_wallet_scope_internal(p_hash);
 IF scope IS NULL OR scope->>'revision' IS DISTINCT FROM p_revision THEN RETURN NULL; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(scope->'tickets') WHERE (value->>'ticketId')::bigint=ANY(ids) ORDER BY (value->>'ticketId')::bigint LOOP
  result:=result||jsonb_build_array(item||jsonb_build_object('projection',public.ticket_wallet_projection_internal((item->>'ticketId')::bigint)));
 END LOOP;
 IF jsonb_array_length(result)<>cardinality(ids) THEN RETURN NULL; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.prepare_ticket_wallet_collection(uuid,bigint[],text,jsonb),public.ticket_wallet_scope_internal(text),public.get_ticket_wallet_projections(text,bigint[],text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ticket_wallet_collection(uuid,bigint[],text,jsonb),public.ticket_wallet_scope_internal(text),public.get_ticket_wallet_projections(text,bigint[],text) TO service_role;
