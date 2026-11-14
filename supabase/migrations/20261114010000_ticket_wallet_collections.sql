-- Scoped Wallet collections: frozen delivered membership, canonical eligibility and per-provider bounded delivery.

-- SOURCE: ticket_wallet/collections_schema.sql
-- Explicit rollout readiness; shared backend deployment does not activate other tenants.
ALTER TABLE eshop.ticket_wallet_integrations ADD COLUMN IF NOT EXISTS collection_enabled boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_collections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization bigint NOT NULL, occasion bigint NOT NULL, order_id bigint NOT NULL,
 recipient text NOT NULL, message_id uuid NOT NULL,
 members jsonb NOT NULL CHECK(jsonb_typeof(members)='array' AND jsonb_array_length(members) BETWEEN 2 AND 1000),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 token_hash text UNIQUE NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 sealed jsonb NOT NULL, event_end_at timestamptz NOT NULL, expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz,
 UNIQUE(organization,occasion,order_id,recipient,fingerprint)
);
ALTER TABLE eshop.ticket_wallet_collections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_collections FROM PUBLIC,anon,authenticated;

-- SOURCE: ticket_wallet/projection.sql
-- The current paid-delivery boundary, never scanner configuration overrides.
CREATE OR REPLACE FUNCTION public.ticket_wallet_state_internal(p_ticket bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE t eshop.tickets; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; state text;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO t FROM eshop.tickets WHERE id=p_ticket;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 SELECT * INTO o FROM public.occasions WHERE id=t.occasion;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 state:='INACTIVE';
 IF t.id IS NOT NULL AND t.occasion=c.occasion AND o.organization=c.organization
 AND coalesce((f->>'is_enabled')::boolean,false) AND c.revoked_at IS NULL
 AND o.start_time IS NOT NULL AND o.end_time IS NOT NULL AND nullif(btrim(o.title),'') IS NOT NULL
 AND t.ticket_symbol IS NOT NULL AND t.state IN ('paid','sent','used')
 AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders ord ON ord.id=x."order"
  WHERE x.ticket=t.id AND ord.id=c.order_id AND ord.occasion=t.occasion AND ord.state IN ('paid','sent'))
 AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders ord ON ord.id=x."order"
  WHERE x.ticket=t.id AND (ord.occasion IS DISTINCT FROM t.occasion OR ord.state NOT IN ('paid','sent')))
 AND public.provider_ticket_admission_allowed_internal(t.id) THEN
  state:=CASE WHEN o.end_time<=now() OR c.expires_at<=now() THEN 'EXPIRED' WHEN t.state='used' THEN 'COMPLETED' ELSE 'ACTIVE' END;
 END IF;
 RETURN state;
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_state_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_state_internal(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_projection_internal(p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE t eshop.tickets; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; state text; details jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO t FROM eshop.tickets WHERE id=p_ticket;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 SELECT * INTO o FROM public.occasions WHERE id=t.occasion;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 state:=public.ticket_wallet_state_internal(p_ticket);
 IF t.id IS NOT NULL THEN
  SELECT x INTO details FROM jsonb_array_elements(public.get_tickets_with_details(c.order_id)) x WHERE (x->>'id')::bigint=t.id;
 END IF;
 RETURN jsonb_build_object('state',state,
 'branding',(SELECT jsonb_build_object('APP_NAME',data->'APP_NAME','DEFAULT_URL',data->'DEFAULT_URL','WALLET_LOGO_URL',data->'WALLET_LOGO_URL') FROM public.organizations WHERE id=o.organization),
 'ticket',jsonb_build_object('id',t.id,'ticket_symbol',t.ticket_symbol,
 'order_product_ticket',(SELECT coalesce(jsonb_agg(x||jsonb_build_object('product',jsonb_build_object('title',p.title))),'[]') FROM jsonb_array_elements(details->'order_product_ticket') x LEFT JOIN eshop.products p ON p.id=(x->>'product')::bigint)),
 'occasion',jsonb_build_object('id',o.id,'organization',o.organization,'title',o.title,'start_time',o.start_time,'end_time',o.end_time,
 'ticketFeature',jsonb_build_object('ticket_type',f->'ticket_type','background',f->'background','lightColor',f->'lightColor','layout',f->'layout','wallet_appearance',f->'wallet_appearance'),
 'data',jsonb_build_object('place_name',o.data->'place_name','timezone',o.data->'timezone','logo',o.data->'logo')));
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_projection_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_projection_internal(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.refresh_ticket_wallet_term_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.ticket_wallet_capabilities c SET event_end_at=o.end_time,expires_at=o.end_time+interval '7 days'
 FROM public.occasions o JOIN eshop.tickets t ON t.occasion=o.id
 WHERE c.ticket_id=p_ticket AND t.id=c.ticket_id AND o.id=c.occasion AND o.organization=c.organization
 AND c.revoked_at IS NULL AND c.reissue_after IS NULL AND o.end_time IS NOT NULL AND c.event_end_at IS DISTINCT FROM o.end_time;
END $$;
REVOKE ALL ON FUNCTION public.refresh_ticket_wallet_term_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_ticket_wallet_term_internal(bigint) TO service_role;

-- SOURCE: ticket_wallet/collections.sql
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

-- SOURCE: ticket_wallet/capabilities.sql
CREATE OR REPLACE FUNCTION public.prepare_ticket_wallet(p_message uuid,p_ticket bigint,p_hash text DEFAULT NULL,p_sealed jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash IS NOT NULL AND (EXISTS(SELECT 1 FROM eshop.ticket_wallet_audit WHERE token_hash=p_hash) OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_collections WHERE token_hash=p_hash)) THEN RETURN NULL; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR NOT public.email_intent_valid(m)
 OR NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket AND "order"=m.order_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Wallet unavailable'; END IF;
 SELECT * INTO o FROM public.occasions WHERE id=m.occasion;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=m.organization AND (publishing_ready OR apple_publishing_ready);
 IF NOT coalesce((f->>'is_enabled')::boolean,false) OR NOT public.ticket_wallet_enabled(f) OR i.organization IS NULL
 OR nullif(btrim(o.title),'') IS NULL OR (o.data->>'timezone' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=o.data->>'timezone'))
 OR o.end_time IS NULL OR o.start_time IS NULL OR o.end_time+interval '7 days'<=now() THEN RETURN NULL; END IF;
 -- Serialize issuance/reissue on the existing ticket; revoked rows never disappear.
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket AND occasion=m.occasion AND state IN ('paid','sent','used') AND ticket_symbol IS NOT NULL AND public.provider_ticket_admission_allowed_internal(id) FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal(p_ticket);
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 IF c.reissue_after IS NOT NULL AND m.created_at>c.reissue_after AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  UPDATE eshop.ticket_wallet_capabilities SET token_hash=p_hash,sealed=p_sealed,recipient=m.recipient,message_id=m.message_id,
   revoked_at=NULL,reissue_after=NULL,event_end_at=o.end_time,expires_at=o.end_time+interval '7 days' WHERE ticket_id=p_ticket RETURNING * INTO c;
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
 END IF;
 IF c.ticket_id IS NULL AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  INSERT INTO eshop.ticket_wallet_capabilities(ticket_id,organization,occasion,order_id,token_hash,sealed,recipient,message_id,expires_at,event_end_at)
  VALUES(p_ticket,m.organization,m.occasion,m.order_id,p_hash,p_sealed,m.recipient,m.message_id,o.end_time+interval '7 days',o.end_time) RETURNING * INTO c;
 END IF;
 IF c.reissue_after IS NOT NULL AND m.created_at>c.reissue_after AND p_hash IS NULL THEN c.ticket_id:=NULL; END IF;
 IF c.ticket_id IS NOT NULL AND (c.revoked_at IS NOT NULL OR c.expires_at<=now() OR c.recipient IS DISTINCT FROM m.recipient
 OR c.organization<>m.organization OR c.occasion<>m.occasion OR c.order_id<>m.order_id) THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('organization',m.organization,'occasion',m.occasion,'ticketId',p_ticket,'issuer',i.issuer,
 'environment',i.environment,'webOrigin',i.web_origin,'badgeUrls',i.badge_urls,
 'providers',jsonb_build_object('google',i.publishing_ready,'apple',i.apple_publishing_ready),
 'collectionEnabled',i.collection_enabled,'source',CASE WHEN c.ticket_id IS NOT NULL THEN jsonb_build_object('sealed',c.sealed,'tokenHash',c.token_hash,'generation',c.generation) END);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_ticket_wallet(p_hash text,p_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n integer; k text;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash !~ '^[a-f0-9]{64}$' OR p_source !~ '^[a-f0-9]{64}$' THEN RETURN NULL; END IF;
 DELETE FROM eshop.ticket_wallet_limits WHERE window_at<now()-interval '10 minutes';
 FOREACH k IN ARRAY ARRAY['token:'||p_hash,'source:'||p_source] LOOP
  INSERT INTO eshop.ticket_wallet_limits(key,window_at,attempts) VALUES(k,now(),1)
  ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN 1 ELSE ticket_wallet_limits.attempts+1 END,
  window_at=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN now() ELSE ticket_wallet_limits.window_at END RETURNING attempts INTO n;
  IF n>20 THEN RETURN NULL; END IF;
 END LOOP;
 RETURN public.ticket_wallet_scope_internal(p_hash);
END $$;

-- Explicit support operation. A new generation always requires a fresh valid email intent.
CREATE OR REPLACE FUNCTION public.manage_ticket_wallet(p_ticket bigint,p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; scope bigint;
BEGIN
 SELECT occasion INTO scope FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 IF auth.uid() IS NULL OR public.can_write_orders(scope) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 IF p_action NOT IN ('revoke','reissue') THEN RAISE invalid_parameter_value; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket FOR UPDATE;
 UPDATE eshop.ticket_wallet_capabilities SET revoked_at=coalesce(revoked_at,now()) WHERE ticket_id=p_ticket;
 -- Reissue retains the tombstone and audit while removing access to the previous source.
 IF p_action='reissue' THEN
  UPDATE eshop.ticket_wallet_capabilities SET generation=generation+1,reissue_after=clock_timestamp(),sealed='{}',token_hash=encode(extensions.gen_random_bytes(32),'hex'),
   recipient='',message_id='00000000-0000-0000-0000-000000000000',expires_at=now() WHERE ticket_id=p_ticket;
 END IF;
 INSERT INTO eshop.ticket_wallet_audit(ticket_id,generation,token_hash,actor,action) VALUES(p_ticket,c.generation,c.token_hash,auth.uid(),p_action);
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
END $$;
REVOKE ALL ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) TO service_role;
REVOKE ALL ON FUNCTION public.manage_ticket_wallet(bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_ticket_wallet(bigint,text) TO authenticated;

-- SOURCE: ticket_wallet/settings.sql
CREATE OR REPLACE FUNCTION public.ticket_wallet_enabled(p_feature jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
 IF NOT coalesce(p_feature ? 'wallet_enabled',false) THEN RETURN true; END IF;
 IF jsonb_typeof(p_feature->'wallet_enabled') IS DISTINCT FROM 'boolean' THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid ticket wallet preference'; END IF;
 RETURN (p_feature->>'wallet_enabled')::boolean;
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_enabled(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_enabled(jsonb) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_ready(p_organization bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.is_service_role() AND NOT EXISTS(SELECT 1 FROM public.units u WHERE u.organization=p_organization AND public.can_create_occasion(u.id)) THEN RETURN false; END IF;
 RETURN EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=p_organization AND (publishing_ready OR apple_publishing_ready));
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_ready(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_ready(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_fingerprint(p_occasion bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT coalesce((f->>'is_enabled')::boolean,false)::text||'/'||public.ticket_wallet_enabled(f)::text||'/'||public.ticket_wallet_ready(o.organization)::text||'/'||coalesce((SELECT publishing_ready::text||'/'||apple_publishing_ready::text||'/'||collection_enabled::text FROM eshop.ticket_wallet_integrations WHERE organization=o.organization),'false/false/false')
 FROM public.occasions o LEFT JOIN LATERAL (SELECT x f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket') x ON true WHERE o.id=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_fingerprint(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_fingerprint(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.validate_ticket_wallet_appearance(p_feature jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE appearance jsonb:=p_feature->'wallet_appearance'; k text; value text;
BEGIN
 IF appearance IS NULL THEN RETURN; END IF;
 IF jsonb_typeof(appearance) IS DISTINCT FROM 'object' OR octet_length(appearance::text)>8192
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(appearance) key WHERE key NOT IN ('background_color','logo','hero_image')) THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid Google Wallet appearance'; END IF;
 FOR k,value IN SELECT key,appearance->>key FROM jsonb_object_keys(appearance) key LOOP
  IF value IS NULL THEN CONTINUE; END IF;
  IF jsonb_typeof(appearance->k) IS DISTINCT FROM 'string' OR
   (k='background_color' AND value !~ '^#?[a-fA-F0-9]{6}$') OR
   (k IN ('logo','hero_image') AND (length(value)>2048 OR value !~ '^https://(img\.festapp\.net/(images|assets)/|a\.img\.festapp\.net/images/)[^?#[:space:]]+$')) THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid Google Wallet appearance'; END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.validate_ticket_wallet_appearance(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_ticket_wallet_appearance(jsonb) TO authenticated,service_role;

-- SOURCE: occasion_setup/email_preview.sql
-- Draft-scoped read projection. No caller-provided hierarchy or template ID is accepted.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(
 p_id uuid,p_expected_revision bigint,p_message_type text,p_occasion bigint,p_delivery_mode text,p_wallet_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; unit_data jsonb; resolved jsonb; copied jsonb;
 email_banner text; inherited_banner text; source_id bigint; tone text; reply_to text;
 payment_metadata jsonb; payment_policy jsonb; payment_method text; payment_info jsonb; payment_duration bigint;
 o public.occasions; selected_code text; feature jsonb; ticket_catalog jsonb; template_code text; templates jsonb:='[]'; overrides jsonb; effective jsonb;
BEGIN
 IF p_message_type IS NULL OR p_message_type NOT IN ('order_confirmation','order_tickets') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid preview message type'; END IF;
 selected_code:=CASE p_message_type WHEN 'order_tickets' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE 'TICKET_ORDER_CONFIRMATION' END;
 IF p_occasion IS NOT NULL THEN
  IF p_id IS NOT NULL OR auth.uid() IS NULL OR public.can_read_ticket_layout(p_occasion) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='Occasion preview denied'; END IF;
  SELECT * INTO o FROM public.occasions WHERE id=p_occasion;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Occasion preview denied'; END IF;
  d.unit:=o.unit;d.organization:=o.organization;
  SELECT f INTO feature FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket';
  d.data:=jsonb_build_object('title',o.title,'ticketDraft',feature,'communicationTone','inherit',
    'replyToMode',CASE WHEN nullif(o.data->>'reply_to','') IS NULL THEN 'inherit' ELSE 'custom' END,'replyToEmail',o.data->>'reply_to');
  ticket_catalog:=public.get_products_and_types(p_occasion)::jsonb;
 ELSE
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR
   public.can_create_occasion(d.unit) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN
  RAISE SQLSTATE 'PT409' USING MESSAGE='Draft revision conflict'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft is finalized'; END IF;
 END IF;
 SELECT data INTO unit_data FROM public.units WHERE id=d.unit AND organization=d.organization;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Draft hierarchy denied'; END IF;
 email_banner:=CASE WHEN p_occasion IS NULL THEN d.data->>'emailBanner' END;
 IF nullif(email_banner,'') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=email_banner AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft email banner access denied'; END IF;
 SELECT coalesce(unit_data->>'email_banner',data->>'email_banner') INTO inherited_banner FROM public.organizations WHERE id=d.organization;
 IF nullif(nullif(d.data->>'communicationTone',''),'inherit') IS NOT NULL
  AND public.parse_communication_tone(d.data->>'communicationTone') IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid tone'; END IF;
 tone:=public.resolve_communication_tone(d.data->>'communicationTone',unit_data->>'communication_tone');
 IF coalesce(d.data->>'replyToMode','inherit') NOT IN ('inherit','custom') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply mode'; END IF;
 reply_to:=CASE WHEN d.data->>'replyToMode'='custom' THEN btrim(d.data->>'replyToEmail') ELSE unit_data->>'reply_to' END;
 IF d.data->>'replyToMode'='custom' AND nullif(reply_to,'') IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 IF reply_to IS NOT NULL AND (length(reply_to)>254 OR reply_to !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 -- Finalization copies occasion templates only. An inherited source template or
 -- source wrapper must not replace the destination hierarchy in this preview.
 IF coalesce((d.data->>'copyEmails')::boolean,false) AND nullif(d.data->>'sourceId','') IS NOT NULL THEN
  source_id:=(d.data->>'sourceId')::bigint;
  IF NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(
   SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization) THEN
   RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 END IF;
 overrides:=public.validate_setup_email_templates_internal(d.data->'emailTemplateOverrides');
 FOREACH template_code IN ARRAY ARRAY['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_STORNO','TICKET_ORDER_UPDATE'] LOOP
  effective:=public.get_email_template_and_wrapper(template_code,jsonb_build_object('unit',d.unit,'organization',d.organization,'occasion',p_occasion));
  IF source_id IS NOT NULL THEN
   SELECT to_jsonb(t) INTO copied FROM public.email_templates t
   WHERE t.occasion=source_id AND t.code=template_code ORDER BY t.id DESC LIMIT 1;
   IF copied IS NOT NULL THEN effective:=jsonb_set(effective,'{template}',copied); END IF;
  END IF;
  IF overrides ? template_code THEN
   effective:=jsonb_set(effective,'{template}',coalesce(effective->'template','{}')||(overrides->template_code));
  END IF;
  templates:=templates||jsonb_build_array(jsonb_build_object('code',template_code,
   'template',effective->'template','customized',overrides ? template_code));
  IF template_code=selected_code THEN resolved:=effective; END IF;
 END LOOP;
 IF email_banner IS NOT NULL THEN
  resolved:=jsonb_set(resolved,'{wrapper}',jsonb_build_object('html',
    public.email_banner_wrapper_internal(email_banner,d.data->>'title')));
 END IF;
 feature:=coalesce(feature,d.data->'ticketDraft');
 IF p_delivery_mode IS NOT NULL THEN PERFORM public.ticket_delivery_mode(jsonb_build_object('delivery_mode',p_delivery_mode)); END IF;
 IF ticket_catalog IS NULL THEN
  SELECT jsonb_build_object('product_types',coalesce(jsonb_agg(t||jsonb_build_object('occasion',0)),'[]'::jsonb),
    'products',coalesce((SELECT jsonb_agg(p||jsonb_build_object('product_type',(pt->>'id')::bigint))
       FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) fld
       CROSS JOIN LATERAL (SELECT fld->'product_type_data' pt) x
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(pt->'products','[]')) p),'[]'::jsonb)) INTO ticket_catalog
  FROM (SELECT fld->'product_type_data' t FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) fld WHERE jsonb_typeof(fld->'product_type_data')='object') x;
 END IF;
 -- Preview facts use the same SQL policy owner as real checkout. No draft
 -- preview creates an order, reference or payment attempt.
 payment_metadata:=public.normalize_form_metadata_internal(d.data#>'{formDraft,data}');
 payment_metadata:=payment_metadata||jsonb_build_object('payments',public.normalize_setup_payments_internal(d.data)->'payments');
 payment_method:=CASE WHEN payment_metadata#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' WHEN payment_metadata#>'{payments,bankEnabled}'='true'::jsonb THEN 'bank' ELSE coalesce((SELECT k FROM jsonb_object_keys(coalesce(payment_metadata#>'{payments,providerConnections}','{}')) k ORDER BY k LIMIT 1),public.resolve_payment_method_policy_internal(d.organization,d.unit)->>'preferredMethod') END;
 payment_duration:=coalesce(nullif(d.data#>>'{formDraft,deadline_duration_seconds}','')::numeric,
   nullif(d.data->>'deadline','')::numeric*86400)::bigint;
 payment_policy:=public.resolve_payment_policy_internal(payment_metadata,payment_duration,
   (SELECT elem FROM jsonb_array_elements(coalesce(o.features,'[]')) elem WHERE elem->>'code'='form'),payment_method);
 SELECT jsonb_build_object('account_number',b.account_number,'account_number_human_readable',coalesce(nullif(b.account_number_human_readable,''),b.account_number))
 INTO payment_info FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
 WHERE u.unit=d.unit AND b.id::text=d.data->>'bankAccountId' AND b.type<>'CASH' AND payment_method='bank' AND public.payment_method_policy_enabled_internal(d.unit,'bank');
 payment_info:=coalesce(payment_info,'{}')||jsonb_build_object('payment_method',payment_method,
   'collectionAction',jsonb_build_object('method',payment_method,'purpose','collect_payment','allowed',payment_method='bank' AND payment_metadata#>'{payments,bankEnabled}'='true'::jsonb AND payment_info IS NOT NULL AND public.payment_method_policy_enabled_internal(d.unit,'bank')),
   'data',jsonb_build_object('payment_policy',payment_policy-'durationSeconds'),
   'deadline',CASE WHEN payment_policy->>'mode'='custom' THEN statement_timestamp()+make_interval(secs=>(payment_policy->>'durationSeconds')::bigint) END);
 RETURN jsonb_build_object('messageType',p_message_type,'deliveryMode',coalesce(p_delivery_mode,public.ticket_delivery_mode(feature)),
  'ticketFeature',feature,'ticketCatalog',ticket_catalog,'occasion',CASE WHEN p_occasion IS NOT NULL THEN to_jsonb(o) ELSE jsonb_build_object('id',0,'title',d.data->>'title','start_time',d.data->>'start','end_time',d.data->>'end','data',jsonb_build_object('place_name',d.data->>'placeName')) END,
  'revision' ,d.revision,'title',coalesce(nullif(d.data->>'title',''),'Ukázková událost'),
  'tone',tone,'replyTo',reply_to,'resolved',resolved,
  'emailBanner',email_banner,'inheritedEmailBanner',inherited_banner,
  'emailTemplates',templates,'emailScope',jsonb_build_object(
   'unit',jsonb_build_object('id',d.unit,'title',(SELECT title FROM public.units WHERE id=d.unit)),
   'organization',jsonb_build_object('id',d.organization,'title',(SELECT title FROM public.organizations WHERE id=d.organization))),
  'deadlineDurationSeconds',payment_policy->'durationSeconds',
  'paymentInfo',payment_info,
  'ticketsEnabled',coalesce((feature->>'is_enabled')::boolean,p_occasion IS NULL) AND (p_occasion IS NOT NULL OR coalesce((d.data->>'formEnabled')::boolean,true) AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false))),
  'walletEnabled',coalesce(p_wallet_enabled,public.ticket_wallet_enabled(feature)),
  'walletReady',public.ticket_wallet_ready(d.organization),
  'walletProviders',coalesce((SELECT jsonb_build_object('google',publishing_ready,'apple',apple_publishing_ready) FROM eshop.ticket_wallet_integrations WHERE organization=d.organization AND NOT paused),'{}'::jsonb),
  'walletCollectionEnabled',coalesce((SELECT collection_enabled FROM eshop.ticket_wallet_integrations WHERE organization=d.organization),false),
  'lang',(SELECT coalesce(data->>'DEFAULT_LANGUAGE','cs') FROM public.organizations WHERE id=d.organization),
  'sampleProducts',coalesce((SELECT jsonb_agg(p) FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f CROSS JOIN LATERAL (SELECT p FROM jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p WHERE NOT coalesce((p->>'is_hidden')::boolean,false) LIMIT 1) products(p) WHERE NOT coalesce((f->>'is_hidden')::boolean,false)),'[]'::jsonb),
  'has_custom_template',coalesce((overrides ? selected_code) OR (resolved->'template'->>'occasion') IS NOT NULL
    OR (resolved->'template'->>'unit') IS NOT NULL OR (resolved->'template'->>'organization') IS NOT NULL,false));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(p_id uuid,p_expected_revision bigint,p_message_type text,p_occasion bigint,p_delivery_mode text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.get_occasion_setup_email_preview(p_id,p_expected_revision,p_message_type,p_occasion,p_delivery_mode,NULL);
$$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text) TO authenticated;

-- Keep the supported confirmation/catalog preview contract unchanged.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(p_id uuid,p_expected_revision bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.get_occasion_setup_email_preview(p_id,p_expected_revision,'order_confirmation',NULL,NULL);
$$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint) TO authenticated;
