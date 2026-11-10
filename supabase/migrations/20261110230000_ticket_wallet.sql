-- Google Wallet: additive capability and provider metadata; no tenant activation.

-- Source: database/functions/ticket_wallet/schema.sql
-- Provider metadata only. Deliberately retain identities when a ticket is deleted.
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_integrations (
 organization bigint PRIMARY KEY REFERENCES public.organizations(id),
 issuer text NOT NULL CHECK(issuer ~ '^[0-9]+$'),
 environment text NOT NULL CHECK(environment ~ '^[a-zA-Z0-9_-]{1,40}$'),
 publishing_ready boolean NOT NULL DEFAULT false,
 web_origin text NOT NULL CHECK(web_origin ~ '^https://[^/#?]+$'),
 badge_urls jsonb NOT NULL DEFAULT '{}',
 next_request_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_capabilities (
 ticket_id bigint PRIMARY KEY, organization bigint NOT NULL, occasion bigint NOT NULL,
 order_id bigint NOT NULL, generation integer NOT NULL DEFAULT 1,
 token_hash text UNIQUE NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 sealed jsonb NOT NULL, recipient text NOT NULL, message_id uuid NOT NULL,
 expires_at timestamptz NOT NULL, event_end_at timestamptz, revoked_at timestamptz, reissue_after timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_objects (
 ticket_id bigint PRIMARY KEY, organization bigint NOT NULL, occasion bigint NOT NULL,
 issuer text NOT NULL, environment text NOT NULL, object_id text UNIQUE NOT NULL,
 class_id text NOT NULL, lease uuid, lease_until timestamptz,
 next_attempt timestamptz NOT NULL DEFAULT now(), last_synced timestamptz,
 failures integer NOT NULL DEFAULT 0, last_error text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ticket_wallet_due ON eshop.ticket_wallet_objects(next_attempt,ticket_id);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ticket_id bigint NOT NULL,
 generation integer NOT NULL, token_hash text NOT NULL, actor uuid NOT NULL, action text NOT NULL CHECK(action IN ('revoke','reissue')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ticket_wallet_revoked_hash ON eshop.ticket_wallet_audit(token_hash);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_limits (
 key text PRIMARY KEY, window_at timestamptz NOT NULL, attempts integer NOT NULL
);
ALTER TABLE eshop.ticket_wallet_integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_integrations,eshop.ticket_wallet_capabilities,eshop.ticket_wallet_objects,eshop.ticket_wallet_audit,eshop.ticket_wallet_limits FROM PUBLIC,anon,authenticated;

-- Source: database/functions/ticket_wallet/settings.sql
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
 RETURN EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=p_organization AND publishing_ready);
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_ready(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_ready(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_fingerprint(p_occasion bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT coalesce((f->>'is_enabled')::boolean,false)::text||'/'||public.ticket_wallet_enabled(f)::text||'/'||public.ticket_wallet_ready(o.organization)::text
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

-- Source: database/functions/ticket_wallet/projection.sql
-- The current paid-delivery boundary, never scanner configuration overrides.
CREATE OR REPLACE FUNCTION public.ticket_wallet_projection_internal(p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE t eshop.tickets; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; state text; details jsonb;
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
 IF t.id IS NOT NULL THEN
  SELECT x INTO details FROM jsonb_array_elements(public.get_tickets_with_details(c.order_id)) x WHERE (x->>'id')::bigint=t.id;
 END IF;
 RETURN jsonb_build_object('state',state,'ticket',jsonb_build_object('id',t.id,'ticket_symbol',t.ticket_symbol,
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

-- Source: database/functions/ticket_wallet/capabilities.sql
CREATE OR REPLACE FUNCTION public.prepare_ticket_wallet(p_message uuid,p_ticket bigint,p_hash text DEFAULT NULL,p_sealed jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.ticket_wallet_audit WHERE token_hash=p_hash) THEN RETURN NULL; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR NOT public.email_intent_valid(m)
 OR NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket AND "order"=m.order_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Wallet unavailable'; END IF;
 SELECT * INTO o FROM public.occasions WHERE id=m.occasion;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=m.organization AND publishing_ready;
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
 'source',CASE WHEN c.ticket_id IS NOT NULL THEN jsonb_build_object('sealed',c.sealed,'tokenHash',c.token_hash,'generation',c.generation) END);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_ticket_wallet(p_hash text,p_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations; n integer; k text;
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
 PERFORM public.refresh_ticket_wallet_term_internal((SELECT ticket_id FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash));
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash AND revoked_at IS NULL AND expires_at>now();
 IF c.ticket_id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization;
 IF i.organization IS NULL THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('ticketId',c.ticket_id,'organization',c.organization,'occasion',c.occasion,'issuer',i.issuer,'environment',i.environment,
 'webOrigin',i.web_origin,'projection',public.ticket_wallet_projection_internal(c.ticket_id));
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
 -- Periodic reconciliation observes the new capability state without reversing object/capability lock order.
END $$;
REVOKE ALL ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) TO service_role;
REVOKE ALL ON FUNCTION public.manage_ticket_wallet(bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_ticket_wallet(bigint,text) TO authenticated;

-- Source: database/functions/ticket_wallet/sync.sql
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

-- Source: database/functions/ticket_wallet/worker.sql
-- Disabled until operations supplies the canonical endpoint; no network activity on migration.
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_worker (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 worker_url text CHECK(worker_url ~ '^https://[^ ]+/functions/v1/sync-ticket-wallet$')
);
ALTER TABLE eshop.ticket_wallet_worker ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_worker FROM PUBLIC,anon,authenticated;
INSERT INTO eshop.ticket_wallet_worker(singleton) VALUES(true) ON CONFLICT DO NOTHING;
CREATE OR REPLACE FUNCTION public.wake_ticket_wallet_worker()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target text;
BEGIN
 PERFORM public.require_service_role();
 SELECT worker_url INTO target FROM eshop.ticket_wallet_worker WHERE singleton;
 IF target IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_objects WHERE next_attempt<=now() AND (lease_until IS NULL OR lease_until<=now())) THEN RETURN; END IF;
 PERFORM net.http_post(url:=target,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
END $$;
REVOKE ALL ON FUNCTION public.wake_ticket_wallet_worker() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_ticket_wallet_worker() TO service_role;
-- Deployment schedules this service-only owner using the existing trusted cron owner.
-- No trigger, paid dispatch or tenant activation is performed by the migration.

-- Install dormant, matching the existing notification workers. Activation is
-- a separate authorized release step after the trusted scheduler/worker probe.
DO $$ DECLARE job bigint; BEGIN
 IF EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  SELECT jobid INTO job FROM cron.job WHERE jobname='festapp_google_ticket_wallet';
  IF job IS NULL THEN
   job:=cron.schedule('festapp_google_ticket_wallet','* * * * *','SELECT public.wake_ticket_wallet_worker()');
   PERFORM cron.alter_job(job,active:=false);
  END IF;
 END IF;
END $$;

-- Source: database/functions/others/ticket_layout.sql
CREATE OR REPLACE FUNCTION public.merge_ticket_layout_features(p_old jsonb,p_next jsonb,p_change jsonb DEFAULT NULL,p_create boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE
SET search_path = public, extensions AS $$
DECLARE old_ticket jsonb; old_layout jsonb; next_layout jsonb; f jsonb; result jsonb:='[]'; found_ticket boolean:=false;
BEGIN
  IF jsonb_typeof(p_next) IS DISTINCT FROM 'array' OR (SELECT count(*) FROM jsonb_array_elements(p_next) e WHERE e->>'code'='ticket')>1
  THEN RAISE EXCEPTION 'Invalid features'; END IF;
  SELECT value->'layout' INTO old_layout FROM jsonb_array_elements(COALESCE(p_old,'[]')) WHERE value->>'code'='ticket';
  SELECT value INTO old_ticket FROM jsonb_array_elements(COALESCE(p_old,'[]')) WHERE value->>'code'='ticket';
  next_layout:=old_layout;
  IF p_change IS NOT NULL THEN
    IF jsonb_typeof(p_change)<>'object' OR NOT (p_change ? 'expected' AND p_change ? 'next')
      OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_change) k WHERE k NOT IN ('expected','next','appearance')) THEN RAISE EXCEPTION 'Invalid ticket layout change'; END IF;
    IF COALESCE(old_layout,'null') IS DISTINCT FROM p_change->'expected' THEN
      RAISE EXCEPTION 'ticket_layout_conflict' USING ERRCODE='40001';
    END IF;
    -- A client must not downgrade a schema it does not understand.
    IF old_layout IS NOT NULL AND old_layout->'schemaVersion' IS DISTINCT FROM '3'::jsonb THEN RAISE EXCEPTION 'Unsupported ticket layout'; END IF;
    next_layout:=p_change->'next';
    IF next_layout IS NULL OR next_layout='null'::jsonb THEN RAISE EXCEPTION 'Ticket layout reset rejected'; END IF;
    PERFORM public.validate_ticket_layout(next_layout);
  END IF;
  FOR f IN SELECT * FROM jsonb_array_elements(p_next) LOOP
    IF f->>'code'='ticket' THEN
      found_ticket:=true;
      -- Older clients omitting the attribute cannot reset an explicit choice.
      IF NOT p_create AND NOT (f ? 'delivery_mode') AND old_ticket ? 'delivery_mode' THEN
        f:=f||jsonb_build_object('delivery_mode',old_ticket->'delivery_mode'); END IF;
      IF NOT p_create AND NOT (f ? 'wallet_enabled') AND old_ticket ? 'wallet_enabled' THEN
        f:=f||jsonb_build_object('wallet_enabled',old_ticket->'wallet_enabled'); END IF;
      IF NOT p_create AND NOT (f ? 'wallet_appearance') AND old_ticket ? 'wallet_appearance' THEN
        f:=f||jsonb_build_object('wallet_appearance',old_ticket->'wallet_appearance'); END IF;
      PERFORM public.validate_ticket_wallet_appearance(f);
      PERFORM public.ticket_wallet_enabled(f);
      PERFORM public.ticket_delivery_mode(f);
      IF p_create AND p_change IS NULL THEN next_layout:=f->'layout'; IF next_layout IS NOT NULL THEN PERFORM public.validate_ticket_layout(next_layout); END IF; END IF;
      f:=f-'layout'; IF next_layout IS NOT NULL THEN f:=f||jsonb_build_object('layout',next_layout); END IF;
    END IF;
    result:=result||jsonb_build_array(f);
  END LOOP;
  IF NOT found_ticket AND (next_layout IS NOT NULL OR old_ticket ? 'delivery_mode' OR old_ticket ? 'wallet_enabled' OR old_ticket ? 'wallet_appearance') THEN result:=result||jsonb_build_array((coalesce(old_ticket,'{}'::jsonb) || jsonb_build_object('code','ticket','is_enabled',false) || CASE WHEN next_layout IS NOT NULL THEN jsonb_build_object('layout',next_layout) ELSE '{}'::jsonb END)); END IF;
  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.merge_ticket_appearance_internal_v1(p_occasion bigint,p_features jsonb,p_appearance jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:='[]'; feature jsonb; background text; old_background text;
BEGIN
 IF p_appearance IS NULL THEN RETURN p_features; END IF;
 IF jsonb_typeof(p_appearance) IS DISTINCT FROM 'object'
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_appearance) k WHERE k NOT IN ('background','ticket_type','wallet_appearance'))
  OR (p_appearance ? 'ticket_type' AND p_appearance->>'ticket_type' IS NOT NULL
    AND p_appearance->>'ticket_type' NOT IN ('wide','named')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid ticket appearance'; END IF;
 PERFORM public.validate_ticket_wallet_appearance(p_appearance);
 SELECT f->>'background' INTO old_background FROM jsonb_array_elements(p_features) f WHERE f->>'code'='ticket';
 background:=p_appearance->>'background';
 IF background IS NOT NULL AND background IS DISTINCT FROM old_background AND NOT EXISTS(
  SELECT 1 FROM public.images i JOIN public.occasions o ON o.id=p_occasion
  WHERE i.link=background AND (i.occasion=o.id OR i.unit=o.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='ticket background must belong to this occasion or unit'; END IF;
 FOR feature IN SELECT value FROM jsonb_array_elements(p_features) LOOP
  IF feature->>'code'='ticket' THEN feature:=feature||p_appearance; END IF;
  result:=result||jsonb_build_array(feature);
 END LOOP;
 RETURN result;
END $$;

-- Source: database/functions/occasion_setup/drafts.sql
CREATE OR REPLACE FUNCTION public.save_occasion_setup_draft(p_id uuid, p_expected_revision bigint, p_data jsonb, p_step integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
  p_data := public.normalize_setup_payments_internal(p_data - 'finalizedOccasion' - 'finalizeResponse');
  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' OR octet_length(p_data::text) > 262144 OR p_step IS NULL OR p_step NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Invalid draft' USING ERRCODE = '22023'; END IF;
  IF jsonb_typeof(p_data->'ticketDraft')='object' AND NOT ((p_data->'ticketDraft') ? 'delivery_mode')
    AND (d.data->'ticketDraft') ? 'delivery_mode' AND p_data->>'sourceId' IS NOT DISTINCT FROM d.data->>'sourceId' THEN
    p_data:=jsonb_set(p_data,'{ticketDraft,delivery_mode}',d.data#>'{ticketDraft,delivery_mode}'); END IF;
  IF jsonb_typeof(p_data->'ticketDraft')='object' AND NOT ((p_data->'ticketDraft') ? 'wallet_enabled')
    AND (d.data->'ticketDraft') ? 'wallet_enabled' AND p_data->>'sourceId' IS NOT DISTINCT FROM d.data->>'sourceId' THEN
    p_data:=jsonb_set(p_data,'{ticketDraft,wallet_enabled}',d.data#>'{ticketDraft,wallet_enabled}'); END IF;
  IF jsonb_typeof(p_data->'ticketDraft')='object' AND NOT ((p_data->'ticketDraft') ? 'wallet_appearance')
    AND (d.data->'ticketDraft') ? 'wallet_appearance' AND p_data->>'sourceId' IS NOT DISTINCT FROM d.data->>'sourceId' THEN
    p_data:=jsonb_set(p_data,'{ticketDraft,wallet_appearance}',d.data#>'{ticketDraft,wallet_appearance}'); END IF;
  PERFORM public.validate_ticket_wallet_appearance(p_data->'ticketDraft');
  PERFORM public.ticket_wallet_enabled(p_data->'ticketDraft');
  PERFORM public.ticket_delivery_mode(p_data->'ticketDraft');
  IF d.data ? 'copy_locale' THEN p_data := jsonb_set(p_data,'{copy_locale}',d.data->'copy_locale'); END IF;
  IF p_data ? 'copy_locale' AND p_data->>'sourceId' IS NOT NULL
     AND coalesce((p_data->>'copy_title_edited')::boolean,false)=false AND coalesce(p_data->>'title','')='' THEN
    IF NOT public.can_copy_occasion_source((p_data->>'sourceId')::bigint) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint AND organization=d.organization) THEN
      RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
    IF d.revision=p_expected_revision+1 AND d.data->>'sourceId'=p_data->>'sourceId' THEN
      p_data := jsonb_set(p_data,'{title}',d.data->'title');
    ELSE
      p_data := jsonb_set(p_data,'{title}',to_jsonb(public.copy_occasion_title_internal(
        (SELECT title FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint),p_data->>'copy_locale')));
    END IF;
  END IF;
  IF d.revision = p_expected_revision + 1 AND d.data = p_data AND d.current_step = p_step THEN RETURN jsonb_set(to_jsonb(d),'{data}',public.normalize_setup_payments_internal(d.data)); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = 'PT409'; END IF;
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,octet_length(p_data::text),false,false);
  UPDATE public.occasion_setup_drafts SET data = p_data, current_step = p_step,
    revision = revision + 1, updated_at = now() WHERE id = p_id RETURNING * INTO d;
  RETURN jsonb_set(to_jsonb(d),'{data}',public.normalize_setup_payments_internal(d.data));
END $$;

-- Source: database/functions/occasion_setup/appearance.sql
-- Deterministic projection on the existing finalizer's authorized draft.
CREATE OR REPLACE FUNCTION public.normalize_occasion_setup_appearance_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE payload jsonb:=p_data-'eventKind'-'eventKindNeedsConfirmation'; appearance jsonb; shared_font text; has_tickets boolean;
BEGIN
 has_tickets:=coalesce((payload->>'formEnabled')::boolean,true) AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false));
 PERFORM public.validate_ticket_wallet_appearance(payload->'ticketDraft');
 PERFORM public.ticket_wallet_enabled(payload->'ticketDraft');
 PERFORM public.ticket_delivery_mode(payload->'ticketDraft');
 appearance:=payload->'appearance';
 IF appearance IS NOT NULL THEN
  IF jsonb_typeof(appearance)<>'object' OR coalesce(appearance->>'primary','') !~ '^[A-Fa-f0-9]{6}$' OR coalesce(appearance->>'secondary','') !~ '^[A-Fa-f0-9]{6}$'
    OR jsonb_typeof(appearance->'gradient') IS DISTINCT FROM 'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='Invalid shared appearance'; END IF;
  shared_font:=public.occasion_setup_font_id_internal(appearance->>'fontFamily');
  IF shared_font IS NULL AND coalesce((appearance->>'preserveSource')::boolean,false)=false THEN RAISE invalid_parameter_value USING MESSAGE='Unsupported shared font'; END IF;
  IF coalesce((appearance->>'preserveSource')::boolean,false)=false THEN
   IF replace(payload#>>'{formDraft,data,design,primary_color}','#','') IS DISTINCT FROM appearance->>'primary'
    OR replace(payload#>>'{formDraft,data,design,secondary_color}','#','') IS DISTINCT FROM appearance->>'secondary'
    OR payload#>>'{formDraft,data,design,font_family}' IS DISTINCT FROM appearance->>'fontFamily'
    OR payload#>>'{formDraft,data,design,background_mode}' IS DISTINCT FROM (CASE WHEN (appearance->>'gradient')::boolean THEN 'gradient' ELSE 'solid' END)
    THEN RAISE invalid_parameter_value USING MESSAGE='Shared form style mismatch'; END IF;
   IF has_tickets AND public.ticket_delivery_mode(payload->'ticketDraft')<>'inline_qr' AND (payload#>'{ticketDraft,layout,templates}' IS NULL OR EXISTS(
    SELECT 1 FROM jsonb_each(payload#>'{ticketDraft,layout,templates}') t
    WHERE t.value->>'fontId' IS DISTINCT FROM shared_font OR t.value->>'canvasColor' IS DISTINCT FROM appearance->>'primary'
     OR (CASE WHEN (appearance->>'gradient')::boolean THEN t.value->'canvasGradient' IS DISTINCT FROM jsonb_build_array(appearance->>'primary',appearance->>'secondary') ELSE t.value ? 'canvasGradient' END)))
    THEN RAISE invalid_parameter_value USING MESSAGE='Shared ticket style mismatch'; END IF;
  END IF;
  -- A custom copied layout retains its detailed style until the user chooses
  -- a shared style. New shared styles are materialized by the one draft mapper.
  IF appearance->>'id'<>'custom' AND payload#>>'{formDraft,data,design,font_family}' IS DISTINCT FROM appearance->>'fontFamily' THEN
    RAISE invalid_parameter_value USING MESSAGE='Form appearance mismatch'; END IF;
 END IF;


 IF jsonb_typeof(payload->'formDraft')='object' THEN payload:=jsonb_set(payload,'{formDraft,title}',coalesce(payload->'title','""'::jsonb)); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.normalize_occasion_setup_appearance_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/occasion_setup/email_preview.sql
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
 payment_method:=CASE WHEN payment_metadata#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' ELSE 'bank' END;
 payment_duration:=coalesce(nullif(d.data#>>'{formDraft,deadline_duration_seconds}','')::numeric,
   nullif(d.data->>'deadline','')::numeric*86400)::bigint;
 payment_policy:=public.resolve_payment_policy_internal(payment_metadata,payment_duration,
   (SELECT elem FROM jsonb_array_elements(coalesce(o.features,'[]')) elem WHERE elem->>'code'='form'),payment_method);
 SELECT jsonb_build_object('account_number',b.account_number,'account_number_human_readable',coalesce(nullif(b.account_number_human_readable,''),b.account_number))
 INTO payment_info FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
 WHERE u.unit=d.unit AND b.id::text=d.data->>'bankAccountId' AND b.type<>'CASH' AND payment_method='bank';
 payment_info:=coalesce(payment_info,'{}')||jsonb_build_object('payment_method',payment_method,
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

-- Source: database/functions/occasion_setup/communication.sql
CREATE OR REPLACE FUNCTION public.get_occasion_setup_communication(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; u public.units; manager boolean; version bigint; snapshot record;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 SELECT row_u,coalesce(v.version,0) AS aggregate_version INTO snapshot FROM public.units row_u
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='unit' AND v.scope_type='unit'
   AND v.scope_id=row_u.id AND v.aggregate_id=row_u.id::text WHERE row_u.id=d.unit;
 u:=snapshot.row_u; version:=snapshot.aggregate_version;
 manager:=public.get_is_manager_on_unit(d.unit);
 RETURN jsonb_build_object('canManage',manager,
  'firstEvent',NOT EXISTS(SELECT 1 FROM public.occasions WHERE unit=d.unit),
  'defaults',jsonb_build_object('walletReady',public.ticket_wallet_ready(u.organization),'replyTo',nullif(btrim(u.data->>'reply_to'),''),
    'tone',public.resolve_communication_tone(u.data->>'communication_tone'),
    'remindersEnabled',coalesce((u.data->>'is_reminder_enabled')::boolean,true),
    'leadSeconds',coalesce((u.data->>'reminder_interval_seconds')::bigint,86400)),
  'unit',CASE WHEN manager THEN jsonb_build_object('id',u.id,'title',u.title,'data',u.data,'aggregate_version',coalesce(version,0)) ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_communication(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_communication(uuid) TO authenticated;

-- Source: database/functions/emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric; v_detail text; v_retry integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.forms f JOIN public.sale_opening_campaigns c ON c.form_id=f.id
  JOIN public.email_messages m ON m.data->>'campaign_id'=c.id::text
  JOIN public.email_attempts a ON a.message_id=m.message_id
  WHERE a.attempt_id=p_attempt AND m.message_kind IN ('sale_opening_opened') FOR UPDATE OF f;
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id;
 IF v_row.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=v_row.order_id FOR UPDATE; END IF;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id FOR UPDATE;
 IF v_attempt.lease_token IS DISTINCT FROM p_token OR v_row.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF v_attempt.state<>'preparing' THEN RETURN jsonb_build_object('disposition','replay','state',v_attempt.state); END IF;
 IF v_row.workflow_state<>'preparing' OR v_row.lease_until<=now() OR v_row.prepared IS NULL THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF NOT public.email_intent_valid(v_row) OR EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN
  UPDATE public.email_messages SET last_error=CASE WHEN v_row.message_kind='sale_opening_opened' THEN 'intent_invalid' ELSE last_error END,workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
  PERFORM public.notification_center_email_internal(v_row.message_id);
  RETURN jsonb_build_object('disposition','cancelled');
 END IF;
 -- A partial acceptance can change a queued offer after its rendered snapshot
 -- was cached. Re-render within this same queue before granting a send permit.
 IF v_row.message_kind='waitlist_offer' AND
  (v_row.post_action->>'waitlist_pending_count')::bigint IS DISTINCT FROM
  (SELECT count(*) FROM eshop.waitlist_offer_slots
   WHERE offer_id=(v_row.data->>'offer_id')::uuid AND outcome='pending') THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),
   prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'waitlist_pending_count',lease_token=NULL,lease_until=NULL,
   last_error='offer_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),
   error_code='offer_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Only unstarted provider attempts can discard a stale Wallet snapshot.
 IF v_row.message_kind='order_tickets' AND v_row.post_action->>'wallet_fingerprint'
  IS DISTINCT FROM public.ticket_wallet_fingerprint(v_row.occasion) THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'wallet_fingerprint',lease_token=NULL,lease_until=NULL,last_error='wallet_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='wallet_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 v_rate:=CASE WHEN v_cap.shared_account THEN least(v_cap.max_rate*0.8,v_cap.allocated_rate) ELSE v_cap.max_rate*0.8 END*v_cap.rate_factor;
 v_daily:=CASE WHEN v_cap.shared_account THEN least(v_cap.daily_quota,v_cap.allocated_daily) ELSE v_cap.daily_quota END*0.9;
 -- Count all local starts since snapshot plus provider's rolling usage; conservative during drift.
 SELECT count(*) INTO v_used FROM public.email_attempts WHERE began_at>now()-interval '24 hours' AND (began_at>v_cap.quota_at OR state IN ('sending','unknown')) AND state IN ('sending','accepted','unknown');
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_rate IS NULL OR v_rate<=0 OR v_daily IS NULL
 OR (v_cap.shared_account AND (v_cap.allocated_rate IS NULL OR v_cap.allocated_daily IS NULL)) OR v_cap.provider_sent_24h+v_used>=v_daily
 OR v_cap.next_send_at>now() OR v_cap.circuit_until>now()
 OR (v_cap.provider_outage_streak>0 AND v_cap.probe_until>now())
 OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='sending' AND lease_until>now())>=v_cap.max_sending THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=greatest(now()+interval '1 second',coalesce(v_cap.next_send_at,now()),coalesce(v_cap.circuit_until,now()),coalesce(v_cap.probe_until,now())),lease_token=NULL,lease_until=NULL,last_error='capacity_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='capacity_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Recipient admission at enqueue does not protect against many future intents
 -- converging on one date. Meter the actual fenced send, with separate essential
 -- classes so ordinary bulk cannot consume Auth or accepted-order capacity.
 BEGIN
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.'||v_row.admission_class,v_row.unit,v_row.organization),
   jsonb_build_object('recipient',public.abuse_recipient_key_v1(v_row.recipient)));
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
  v_retry:=greatest(coalesce((v_detail::jsonb->>'retryAfterSeconds')::integer,60),1);
  UPDATE public.email_messages SET workflow_state='pending',target_time=now()+make_interval(secs=>v_retry),lease_token=NULL,lease_until=NULL,last_error='recipient_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='recipient_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END;
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END WHERE singleton;
 UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
 UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
END $$;

-- Source: database/functions/others/get_ticket_layout_write_contract_v1.sql
-- Generated by automation/generate_ticket_layout_write_contract.py.
-- A readiness probe, not a write dispatcher or a grant to any new executor.
CREATE OR REPLACE FUNCTION public.get_ticket_layout_write_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ready boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid()) THEN
  RAISE insufficient_privilege USING MESSAGE='authenticated user required'; END IF;
 SELECT coalesce(bool_and(p.oid IS NOT NULL AND md5(btrim(p.prosrc,E' \n\r\t'))=expected.body_md5
  AND p.prosecdef=expected.definer AND (EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
   WHERE regexp_replace(setting,'[[:space:]]','','g')='search_path=public,extensions')=expected.needs_path)),false)
 INTO ready FROM (VALUES
  ('public.active_membership(boolean,boolean)','2dd31a8b531c745b2ed16af90e0260ea',false,false),
  ('public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean)','7a9559975e19ae53e8b15a23a4b8b68a',false,false),
  ('public.blueprint_write_rule(boolean,boolean)','0c68680b6879b48966f2bf3bc0210d37',false,false),
  ('public.can_create_occasion(bigint)','f13b39c68d18a53dbb79125c23d7dc23',true,true),
  ('public.can_delete_orders(bigint)','8db8081db5e65a6948f4cefe1b109f93',true,true),
  ('public.can_edit_occasion(bigint,bigint)','af8850fc3a3bed9a06274880669c340d',true,true),
  ('public.can_edit_ticket_layout(bigint)','bb45fdb1e72cd16860e9719c8f9ab84f',true,true),
  ('public.can_edit_ticket_layout_as_actor_internal_v1(uuid,bigint)','f6ee7e318387522f6146e13b3c4854f7',true,true),
  ('public.can_manage_occasion_participants(bigint)','8cb3dd4327ae5c9302da134994dd5d07',true,true),
  ('public.can_manage_unit_users(bigint)','700c32f30396d2bc5bb21553c2f42ca8',true,true),
  ('public.can_preview_ticket_readonly(bigint)','48efb47c1529b5106cbab4edf641fd0a',true,true),
  ('public.can_read_information_editor_bundle(bigint)','ba203be730cbf9acca46c0b3e63363ad',true,true),
  ('public.can_read_map_editor_bundle(bigint)','02c9fbcfcd61c8598e88407a9f3070fa',true,true),
  ('public.can_read_orders(bigint)','6b8f1152158aa8ab01bd13cec9dbbdf3',true,true),
  ('public.can_read_ticket_layout(bigint)','50105a20a0ff5d89389f80e5dd9f891c',true,true),
  ('public.can_read_unit_users(bigint)','76b08038f169406ba1ba56652e44608e',true,true),
  ('public.can_write_orders(bigint)','680cbd3862cc0f6abc89d7d2497c7fb1',true,true),
  ('public.can_write_orders_as_actor_internal(uuid,bigint)','064d9d9fe95cfbb62ccbe39efa120a62',false,false),
  ('public.cleaning_crew_navigation_rule(boolean)','30e845096d248f7112e1d570bb489e6a',false,false),
  ('public.client_activity_read_rule(boolean,boolean,boolean)','002ce7bce477126bcdab9e94db022734',false,false),
  ('public.client_commit_read_rule(boolean,boolean,boolean)','229306cbca2f8a160f4d66b2598fc127',false,false),
  ('public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean)','9f7f53c36711c06eb5a130dc339b325b',false,false),
  ('public.companion_assignment_rule(boolean,boolean)','7d53e2d7e2196b118c29f85cc90d0ab2',false,false),
  ('public.context_private_access_rule(boolean,boolean,boolean)','a187283398f1802a1b79b46963ff98b6',false,false),
  ('public.demo_own_work_rule(boolean,boolean,boolean,boolean)','3dd99e356714a2005743f678f09f7ae9',false,false),
  ('public.email_template_read_rule(boolean,boolean)','6501d868e3a245da411c8685a6c39406',false,false),
  ('public.email_template_write_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.event_attendance_read_rule(boolean,boolean)','e85f194d54fb7db63b079e5d689de085',false,false),
  ('public.form_authoring_rule(boolean,boolean)','378d42348079d8d5df8ed0d914f5d007',false,false),
  ('public.form_catalog_read_rule(boolean,boolean,boolean)','7a7263f988a28c0272c14f0234b12563',false,false),
  ('public.form_copy_source_rule(boolean,boolean)','0fff049746a86488382290a67c8c9838',false,false),
  ('public.group_assignments_write_rule(boolean,boolean,boolean,boolean)','0221c1b7823f38a4d5afa4abe5e0912f',false,false),
  ('public.group_data_read_rule(boolean,boolean)','a5a4e0f5924790a0c9e68e79bc606a1e',false,false),
  ('public.group_editor_read_rule(boolean,boolean,boolean)','c1fd67eb4de0001ed5aaffb65d36b437',false,false),
  ('public.group_members_read_rule(boolean,boolean,boolean)','c8e7fdf47b08fac95a18ed026d4d07bc',false,false),
  ('public.group_members_write_rule(boolean,boolean)','46f6cef5344290b2caf0182185c3ce4e',false,false),
  ('public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','937805bab351b685970512e7f5e6f285',false,false),
  ('public.group_write_rule(boolean,boolean,boolean)','3dd26a325ee3dd2e391136570cbc5f60',false,false),
  ('public.inventory_copy_target_rule(boolean,boolean)','604bd24712dc418a35616de6d38e0578',false,false),
  ('public.map_editor_read_rule(boolean,boolean)','3f4dc9022d50562b6a48d6e46b0c5928',false,false),
  ('public.merge_ticket_appearance_internal_v1(bigint,jsonb,jsonb)','337628341725ae78a7c14a130a0fe7a4',false,true),
  ('public.merge_ticket_layout_features(jsonb,jsonb,jsonb,boolean)','d8c6d2e6a64880af2fa1e5553dbf85f5',false,true),
  ('public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','f68f00938a5a8efee47af7edc0062f94',false,false),
  ('public.occasion_commit_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.occasion_context_read_rule(boolean,boolean,boolean)','b54f8cf02bc1580acba23e2497d1cc9f',false,false),
  ('public.occasion_create_rule(boolean,boolean)','faa2f799767b4c9edb52c58944b4a66b',false,false),
  ('public.occasion_directory_read_rule(boolean,boolean)','d4937332739a00292987baae5b876b2b',false,false),
  ('public.occasion_edit_rule(boolean,boolean)','1d4987935db34cc6011f633ef3f6f291',false,false),
  ('public.occasion_editor_read_rule(boolean,boolean,boolean)','1702aa0f9d1003c29f02ef70a017dee6',false,false),
  ('public.occasion_list_read_rule(boolean,boolean)','7ecb040f0c43bb540a15e2ab868ac31e',false,false),
  ('public.occasion_media_upload_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean)','6c7cfeabfb173e0283543f575272d4d8',false,false),
  ('public.occasion_users_write_rule(boolean,boolean,boolean)','2a1ee1bc8a910030a6010ff778df7bc4',false,false),
  ('public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean)','939699b1b32832f4e2ad0c3af5f22210',false,false),
  ('public.order_delete_rule(boolean,boolean,boolean)','6fdbd70c92f774e10d2be6e0e30eb219',false,false),
  ('public.order_editor_membership_as_actor_internal(uuid,bigint)','aa05414eef3f73d8792cdaaa22023c39',false,false),
  ('public.order_read_rule(boolean,boolean,boolean)','d8acd43d69e2797bbd63063512eb4e69',false,false),
  ('public.order_write_rule(boolean,boolean)','4dd2fa01cd16e5c36983aa7aeb280d3f',false,false),
  ('public.participant_contacts_read_rule(boolean,boolean,boolean)','c371f5c035213b1fd9c8a5f15ba3c6e3',false,false),
  ('public.participant_manage_rule(boolean,boolean)','2ddebfa1df2bdd7becf910d5b619a3c0',false,false),
  ('public.place_move_rule(boolean,boolean,boolean,boolean)','73f870eaea9c56088435b4d80cbf5315',false,false),
  ('public.public_publication_actor_rule(boolean,boolean,boolean)','47ad63e39013d34b5a4105a18f04457d',false,false),
  ('public.readable_membership(boolean,boolean,boolean)','057c3a891e1c41c9b77dc8af67983e20',false,false),
  ('public.reception_enabled(jsonb)','0844ea35e4e7bfad821b8f09f81e8fbb',false,false),
  ('public.reception_use_rule(boolean,boolean,boolean,boolean)','99350a72fb204f5160cb72714b85882c',false,false),
  ('public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean)','53eb537fe636ad48274e61bafb683e4a',false,false),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)','56bf52d069b80a2ffa254509afdaa5a1',true,true),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)','00af445f9e641905e395adaca48ce248',true,true),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)','eda19f32835616334b3adc0f4d2cd2f6',true,true),
  ('public.scanner_settings_rule(boolean,boolean,boolean)','2b1717b65933cede78c39b44f5d6230d',false,false),
  ('public.schedule_entry_navigation_rule(boolean)','f0258b7a3cc8e3a024dee1a96d34d407',false,false),
  ('public.schedule_feedback_read_rule(boolean,boolean)','a546bbfc24dce06e231e832a11ddb4b4',false,false),
  ('public.schedule_participants_read_rule(boolean,boolean,boolean)','7f6977ddb21f0e2044e154b4428275d1',false,false),
  ('public.ticket_delivery_mode(jsonb)','c2590b2701840fc3cba0df9e8d0359cd',false,true),
  ('public.ticket_layout_rule(boolean,boolean)','8bc8e0cd6a5a45d10d57f79cec655768',false,false),
  ('public.ticket_layout_uses_product_type(bigint,bigint)','dddc7962230734dd5835601b455d8bb4',false,true),
  ('public.ticket_wallet_enabled(jsonb)','ccbb73fd52b030315763e2be50b8e7a7',false,true),
  ('public.ticket_wallet_fingerprint(bigint)','b925aa31ec85daa749b9be964813dfbd',true,true),
  ('public.ticket_wallet_ready(bigint)','d1827ba2afea0b03bf617631d00c9515',true,true),
  ('public.unit_abuse_policy_read_rule(boolean,boolean)','42fc89183ec978eccce36173bc6c3a50',false,false),
  ('public.unit_discovery_rule(boolean,boolean,boolean)','d49526989a25babf6f7ca9ba34b3061c',false,false),
  ('public.unit_landing_read_rule(boolean,boolean,boolean,boolean)','14e7808464b1206a6842240b8db567ff',false,false),
  ('public.unit_legal_profile_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.unit_template_read_rule(boolean,boolean,boolean)','a22a3f456bfac47bcc58b72c2ec5f75f',false,false),
  ('public.unit_users_read_rule(boolean,boolean,boolean)','a7131760aa20a35fa57d63f718037a34',false,false),
  ('public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean)','5ba3417d0406073b8ce9421770304558',false,false),
  ('public.update_occasion(jsonb)','0425e6f46c20d2c30a2ffd054619b2b0',true,true),
  ('public.update_occasion_182(jsonb)','bdcda71506ac0abb50a466bb18eb1cc7',true,true),
  ('public.update_occasion_203(jsonb)','916b23b47758d87e478b3b7d84a50ee2',true,true),
  ('public.update_occasion_internal_v1(jsonb)','2446d470f7e49092199946b0cc8fa6bd',true,true),
  ('public.validate_ticket_layout(jsonb)','53d7703a06dbde87349a0ac04e50cd54',false,true),
  ('public.validate_ticket_layout_references(bigint,jsonb)','aad01d93c9f0a7035efa243caa3d5a20',false,true),
  ('public.validate_ticket_wallet_appearance(jsonb)','bdcc55cb2a986056fbae005acee1990c',false,true)
 ) expected(signature,body_md5,definer,needs_path)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(expected.signature);
 ready:=ready AND NOT EXISTS(
  SELECT 1 FROM (VALUES('authenticated'),('anon')) actor(role_name)
  WHERE has_table_privilege(actor.role_name,'public.occasions','INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_any_column_privilege(actor.role_name,'public.occasions','INSERT,UPDATE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion_internal_v1(jsonb)'),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)')
 ) private(signature) WHERE has_function_privilege('authenticated',to_regprocedure(private.signature),'EXECUTE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion(jsonb)'),('public.update_occasion_203(jsonb)'),('public.update_occasion_182(jsonb)'),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)')
 ) boundary(signature) WHERE NOT has_function_privilege('authenticated',to_regprocedure(boundary.signature),'EXECUTE')
 OR has_function_privilege('anon',to_regprocedure(boundary.signature),'EXECUTE'));
 RETURN jsonb_build_object('family','ticket_layouts','contractVersion',1,'ready',coalesce(ready,false));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_layout_write_contract_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_layout_write_contract_v1() TO authenticated;

-- Source: database/functions/eshop/get_order_details_for_email.sql
CREATE OR REPLACE FUNCTION public.get_order_details_for_email(p_order_id bigint)
RETURNS jsonb
STABLE
SET search_path = public, extensions AS $$
DECLARE
    result_data jsonb;
    v_changes jsonb;
    form_fields_data jsonb;
    form_data jsonb;
    form_key uuid;
    latest_history_id bigint;
    v_reply_to_email TEXT;
BEGIN
    -- Retrieve the order, occasion, payment info, and bank account as separate objects
    SELECT jsonb_build_object(
        'order', to_jsonb(o.*) || jsonb_build_object('data', o.data || jsonb_build_object(
          'tickets', public.order_tickets_with_seating_internal(o.id,o.data->'tickets'))),
        'occasion', to_jsonb(occ.*)||jsonb_build_object('locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=occ.organization),'cs')),
        -- Same statement snapshot as the ticket feature used by delivery.
        'wallet', jsonb_build_object(
          'feature',(SELECT f FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'),
          'fingerprint',coalesce(((SELECT f->>'is_enabled' FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'))::boolean,false)::text
            ||'/'||public.ticket_wallet_enabled((SELECT f FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'))::text
            ||'/'||public.ticket_wallet_ready(occ.organization)::text),
        'payment_info', to_jsonb(pi.*),
        'bank_account', CASE
            WHEN upper(o.currency_code) = 'EUR'
              AND ba.id IS NOT NULL
              AND nullif(trim(ba.creditor_name), '') IS NULL
            THEN jsonb_set(
              to_jsonb(ba.*),
              '{creditor_name}',
              to_jsonb(left(trim(regexp_replace(org.title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70))
            )
            ELSE to_jsonb(ba.*)
        END
    )
    INTO result_data
    FROM eshop.orders AS o
    LEFT JOIN public.occasions AS occ ON o.occasion = occ.id
    LEFT JOIN public.organizations AS org ON occ.organization = org.id
    LEFT JOIN eshop.payment_info AS pi ON o.payment_info = pi.id
    LEFT JOIN eshop.bank_accounts AS ba ON pi.bank_account = ba.id
    WHERE o.id = p_order_id;

    -- Check if the order was found
    IF result_data IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found.');
    END IF;

    -- Call the function you provided to get the email
    SELECT get_reply_to_email_for_order(p_order_id) INTO v_reply_to_email;

    -- Add the email to the result data. jsonb_build_object handles NULLs gracefully.
    result_data := result_data || jsonb_build_object('reply_to', v_reply_to_email);


    v_changes := public.get_order_change_summary_v1(p_order_id);
    latest_history_id := (v_changes->>'latestHistoryId')::bigint;
    result_data := result_data || jsonb_build_object(
      'latest_history_id', latest_history_id,
      'reference_history', v_changes#>'{referenceOrder,data}',
      'order_changes', v_changes);

    -- Extract the form's unique key from the order's data
    form_key := (result_data->'order'->'data'->>'form')::uuid;

    -- If a form key exists, fetch all associated form fields
    IF form_key IS NOT NULL THEN
        -- 2. Modified query to fetch both form_fields and form_data at the same time
        SELECT
            jsonb_object_agg(ff.id, to_jsonb(ff.*)), -- All fields
            public.effective_form_metadata_internal(f.data, u.data) -- Communication metadata without analytics policy
        INTO
            form_fields_data,
            form_data
        FROM
            public.form_fields AS ff
        JOIN
            public.forms AS f ON ff.form = f.id
        JOIN public.occasions form_occasion ON form_occasion.id = f.occasion
        JOIN public.units u ON u.id = form_occasion.unit
        WHERE
            f.key = form_key
        GROUP BY
            f.id, u.data; -- Group by the form used for effective data

        -- If form fields were found, add them to the result data
        IF form_fields_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_fields', form_fields_data);
        END IF;

        -- 3. Added this block to merge the form_data
        IF form_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_data', form_data);
        END IF;
    END IF;

    -- Return a success response with the collected data
    RETURN jsonb_build_object('code', 200, 'data', result_data);

END;
$$ LANGUAGE plpgsql;
