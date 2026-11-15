-- Customer order self-service. Additive schema; feature/operations remain disabled until explicitly configured.

-- SOURCE: customer_order_changes/policy_schema.sql
-- Additive: no existing form receives permission or a write credential.
ALTER TABLE public.occasions ADD COLUMN customer_self_service_epoch bigint NOT NULL DEFAULT 0;
CREATE TABLE eshop.customer_order_change_policies (
 form_id bigint PRIMARY KEY REFERENCES public.forms(id) ON DELETE CASCADE,
 revision bigint NOT NULL CHECK(revision>0),
 policy jsonb NOT NULL CHECK(jsonb_typeof(policy)='object'),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE eshop.customer_order_change_policies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.customer_order_change_policies FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: customer_order_changes/runtime_schema.sql
-- Explicit term semantics. Sales windows retain their existing meaning.
ALTER TABLE public.forms ADD COLUMN term_start_at timestamptz, ADD COLUMN term_end_at timestamptz;
ALTER TABLE public.forms ADD CONSTRAINT forms_term_interval CHECK(term_end_at IS NULL OR (term_start_at IS NOT NULL AND term_end_at>term_start_at));
CREATE TABLE eshop.customer_order_change_capabilities (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), token_hash text UNIQUE NOT NULL CHECK(token_hash~'^[a-f0-9]{64}$'),
 parent_hash text NOT NULL REFERENCES eshop.waitlist_capabilities(token_hash) ON DELETE CASCADE,
 organization_id bigint NOT NULL REFERENCES public.organizations(id), form_id bigint NOT NULL REFERENCES public.forms(id) ON DELETE CASCADE,
 order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE, operation text NOT NULL CHECK(operation IN ('edit','cancel','move','withdraw')),
 proposal_hash text NOT NULL, policy_revision bigint NOT NULL, feature_epoch bigint NOT NULL,
 expires_at timestamptz NOT NULL, revoked_at timestamptz, consumed_by uuid, consumed_form_id bigint REFERENCES public.forms(id),
 preview_hash text, preview_expires_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE eshop.customer_order_change_sources (
 capability_id uuid PRIMARY KEY REFERENCES eshop.customer_order_change_capabilities(id) ON DELETE CASCADE,
 sealed jsonb NOT NULL, content_hash text NOT NULL
);
CREATE TABLE eshop.customer_order_change_attempts (
 order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE, ip_hash text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX customer_order_change_attempts_order_time ON eshop.customer_order_change_attempts(order_id,created_at);
CREATE INDEX customer_order_change_attempts_ip_time ON eshop.customer_order_change_attempts(ip_hash,created_at);
CREATE TABLE eshop.customer_order_change_limits (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), minimum_seconds integer NOT NULL CHECK(minimum_seconds>=60),
 hourly_limit integer NOT NULL CHECK(hourly_limit BETWEEN 1 AND 3)
);
INSERT INTO eshop.customer_order_change_limits VALUES(true,60,3);
-- Working evidence only. The existing refund_requests/settlements remain the
-- sole refund intent/fact owners. No amount is copied into this request table.
CREATE TABLE eshop.customer_order_change_requests (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE,
 organization_id bigint NOT NULL REFERENCES public.organizations(id), operation text NOT NULL CHECK(operation IN ('cancel','move')),
 status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','approved','rejected','withdrawn','resolved')),
 ticket_ids bigint[],
 reason text CHECK(length(reason)<=2000), target_form_id bigint REFERENCES public.forms(id) ON DELETE SET NULL,
 customer_command uuid UNIQUE NOT NULL REFERENCES public.client_mutation_receipts(command_id),
 decision_command uuid REFERENCES public.client_mutation_receipts(command_id), response text CHECK(length(response)<=2000),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 decided_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX customer_order_change_one_open_request ON eshop.customer_order_change_requests(order_id,operation) WHERE status='open';
CREATE TABLE eshop.customer_order_change_events (
 command_id uuid PRIMARY KEY REFERENCES public.client_mutation_receipts(command_id), order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE,
 operation text NOT NULL, outcome text NOT NULL, request_id uuid REFERENCES eshop.customer_order_change_requests(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE eshop.customer_order_change_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.customer_order_change_capabilities,eshop.customer_order_change_sources,
 eshop.customer_order_change_attempts,eshop.customer_order_change_limits,eshop.customer_order_change_requests,
 eshop.customer_order_change_events FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: user_permissions/customer_order_changes.sql
-- Typed organizer operation. Service credentials are not a customer entitlement.
CREATE OR REPLACE FUNCTION public.can_manage_customer_order_policy(p_form bigint,p_automatic_refund boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT auth.uid() IS NOT NULL AND public.can_author_forms(f.occasion)
  AND (NOT p_automatic_refund OR (public.get_is_manager_on_unit(o.unit) AND NOT public.is_demo_occasion(o.id)))
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form),false);
$$;
REVOKE ALL ON FUNCTION public.can_manage_customer_order_policy(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_customer_order_policy(bigint,boolean) TO authenticated;

-- Scoped customer write authorization, independent of every staff role.
CREATE OR REPLACE FUNCTION public.authorize_customer_change_internal(p_token text,p_command uuid DEFAULT NULL)
RETURNS eshop.customer_order_change_capabilities LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE c eshop.customer_order_change_capabilities;
BEGIN
 IF p_token IS NULL OR p_token!~'^[a-f0-9]{64}$' THEN RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 SELECT cap.* INTO c FROM eshop.customer_order_change_capabilities cap
 JOIN eshop.waitlist_capabilities parent ON parent.token_hash=cap.parent_hash AND parent.order_id=cap.order_id
 JOIN eshop.orders o ON o.id=cap.order_id JOIN public.occasions oc ON oc.id=o.occasion
 JOIN eshop.customer_order_change_policies policy ON policy.form_id=cap.form_id
 WHERE cap.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp()
 AND parent.revoked_at IS NULL AND parent.expires_at>statement_timestamp() AND parent.kind='order_view'
 AND parent.organization_id=cap.organization_id AND parent.form_id=o.form AND oc.organization=cap.organization_id
 AND (o.form=cap.form_id OR (cap.consumed_by=p_command AND o.form=cap.consumed_form_id))
 AND policy.revision=cap.policy_revision AND oc.customer_self_service_epoch=cap.feature_epoch
 AND (CASE WHEN cap.operation='withdraw' THEN public.customer_order_feature_enabled_internal(cap.form_id) ELSE public.customer_order_operation_enabled_internal(cap.form_id,cap.operation) END)
 AND (cap.consumed_by IS NULL OR cap.consumed_by=p_command);
 IF c.id IS NULL THEN RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 RETURN c;
END $$;
REVOKE ALL ON FUNCTION public.authorize_customer_change_internal(text,uuid) FROM PUBLIC,anon,authenticated,service_role;

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
 SELECT term.* INTO o FROM public.order_term_occasion_internal(m.order_id) term WHERE term.id=m.occasion AND term.organization=m.organization;
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
    AND o.end_time IS NOT NULL AND x.event_end_at IS DISTINCT FROM o.end_time AND NOT EXISTS(SELECT 1 FROM public.forms f JOIN eshop.orders ord ON ord.form=f.id WHERE ord.id=x.order_id AND f.term_start_at IS NOT NULL);
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
 SELECT term.* INTO o FROM public.order_term_occasion_internal(m.order_id) term WHERE term.id=m.occasion AND term.organization=m.organization;
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

-- SOURCE: eshop_forms/order_term.sql
-- One actual-term projection for PDFs, Wallet and order changes. Sales-window
-- metadata is deliberately absent from this owner.
CREATE OR REPLACE FUNCTION public.order_term_occasion_internal(p_order bigint)
RETURNS public.occasions LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occ public.occasions; form public.forms;
BEGIN
 SELECT oc.* INTO occ FROM public.occasions oc JOIN eshop.orders o ON o.occasion=oc.id WHERE o.id=p_order;
 SELECT f.* INTO form FROM public.forms f JOIN eshop.orders o ON o.form=f.id WHERE o.id=p_order AND f.occasion=occ.id;
 occ.start_time:=coalesce(form.term_start_at,occ.start_time);
 -- An unknown term end must not become a fabricated expiry at its start.
 occ.end_time:=CASE WHEN form.term_start_at IS NOT NULL THEN form.term_end_at ELSE occ.end_time END;
 RETURN occ;
END $$;
REVOKE ALL ON FUNCTION public.order_term_occasion_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.refresh_order_wallet_term_domain_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE term public.occasions;
BEGIN
 term:=public.order_term_occasion_internal(p_order);
 IF term.end_time IS NULL THEN RETURN; END IF;
 UPDATE eshop.ticket_wallet_capabilities SET event_end_at=term.end_time,expires_at=term.end_time+interval '7 days'
 WHERE order_id=p_order AND occasion=term.id AND organization=term.organization AND revoked_at IS NULL AND reissue_after IS NULL AND event_end_at IS DISTINCT FROM term.end_time;
 UPDATE eshop.ticket_wallet_collections SET event_end_at=term.end_time,expires_at=term.end_time+interval '7 days'
 WHERE order_id=p_order AND occasion=term.id AND organization=term.organization AND revoked_at IS NULL AND event_end_at IS DISTINCT FROM term.end_time;
END $$;
REVOKE ALL ON FUNCTION public.refresh_order_wallet_term_domain_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: abuse/orders.sql
-- Caller owns authorization and its existing receipt. This helper does not
-- cancel, refund, reprice or delete anything and has no external execution grant.
CREATE OR REPLACE FUNCTION public.admit_order_mutation_scope_internal(p_occasion bigint,p_items bigint,p_actor text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint;
BEGIN
 IF nullif(p_actor,'') IS NULL THEN RAISE insufficient_privilege USING MESSAGE='order actor required'; END IF;
 SELECT unit,organization INTO STRICT un,org FROM public.occasions WHERE id=p_occasion;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('order.mutation',un,org),
  jsonb_build_object('actor',p_actor,'unit',un,'organization',org),jsonb_build_object('order.mutation.items',p_items));
END $$;
REVOKE ALL ON FUNCTION public.admit_order_mutation_scope_internal(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_order_mutation_v1(p_occasion bigint,p_items bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint;
BEGIN
 IF auth.uid() IS NULL THEN RAISE insufficient_privilege USING MESSAGE='order actor required'; END IF;
 PERFORM public.admit_order_mutation_scope_internal(p_occasion,p_items,auth.uid()::text);
END $$;
REVOKE ALL ON FUNCTION public.admit_order_mutation_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: customer_order_changes/policy.sql
-- Private policy owner. The existing receipted form save is the only writer.
-- Lock hierarchy: blueprint scope fence -> capacity/forms in ascending ID ->
-- products in ascending ID -> order -> payment -> provider attempt -> tickets.
-- Payment operations additionally take their organization policy fence first.
-- Feature and form policy writes share the blueprint fence with customer commands.

CREATE OR REPLACE FUNCTION public.normalize_customer_order_policy_internal(p_policy jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE op record; rule jsonb; field jsonb; result jsonb:='{}';
BEGIN
 IF p_policy IS NULL OR jsonb_typeof(p_policy)<>'object' OR octet_length(p_policy::text)>16384
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_policy) k WHERE k NOT IN ('edit','cancel','move')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid customer change policy'; END IF;
 FOR op IN SELECT * FROM jsonb_each(p_policy) LOOP
  rule:=op.value;
  IF jsonb_typeof(rule)<>'object' OR jsonb_typeof(rule->'enabled') IS DISTINCT FROM 'boolean'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(rule) k WHERE k NOT IN ('enabled','allowed_until',
     'fields','mode','reason_required','refund_mode','targets')) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid customer operation policy'; END IF;
  IF rule->'enabled'='true'::jsonb OR rule ? 'allowed_until' THEN
   IF jsonb_typeof(rule->'allowed_until') IS DISTINCT FROM 'string'
    OR rule->>'allowed_until' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' THEN
    RAISE invalid_parameter_value USING MESSAGE='customer operation deadline required'; END IF;
   PERFORM (rule->>'allowed_until')::timestamptz;
  END IF;
  IF op.key='cancel' THEN
   IF rule->>'mode' IS NULL OR rule->>'mode' NOT IN ('automatic','approval_required')
    OR jsonb_typeof(rule->'reason_required') IS DISTINCT FROM 'boolean'
    OR rule->>'refund_mode' IS NULL OR rule->>'refund_mode' NOT IN ('none','automatic','manual') THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid cancellation mode'; END IF;
   IF rule ?| ARRAY['fields','targets'] THEN RAISE invalid_parameter_value USING MESSAGE='invalid cancellation keys'; END IF;
  ELSIF op.key='edit' THEN
   IF rule ?| ARRAY['mode','reason_required','refund_mode','targets'] OR jsonb_typeof(rule->'fields') IS DISTINCT FROM 'array'
    OR jsonb_array_length(rule->'fields')>100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid customer editable fields'; END IF;
   FOR field IN SELECT value FROM jsonb_array_elements(rule->'fields') LOOP
    IF jsonb_typeof(field)<>'object' OR NOT field ?& ARRAY['id','type'] OR field-ARRAY['id','type']<>'{}'::jsonb
     OR jsonb_typeof(field->'id') IS DISTINCT FROM 'number' OR field->>'id' !~ '^[0-9]+$'
     OR field->>'type' IS NULL OR field->>'type' NOT IN ('name','surname','phone','text','city','address','select_one') THEN
     RAISE invalid_parameter_value USING MESSAGE='customer field not editable'; END IF;
   END LOOP;
   IF (SELECT count(*) FROM jsonb_array_elements(rule->'fields'))<>(SELECT count(DISTINCT value->>'id') FROM jsonb_array_elements(rule->'fields')) THEN
    RAISE invalid_parameter_value USING MESSAGE='duplicate customer field'; END IF;
  ELSE
   IF rule ?| ARRAY['fields','mode','reason_required','refund_mode'] OR jsonb_typeof(rule->'targets') IS DISTINCT FROM 'array'
    OR jsonb_array_length(rule->'targets')>25 THEN RAISE invalid_parameter_value USING MESSAGE='invalid customer move targets'; END IF;
   FOR field IN SELECT value FROM jsonb_array_elements(rule->'targets') LOOP
    IF jsonb_typeof(field)<>'object' OR field-ARRAY['formId','products','fields']<>'{}'::jsonb
     OR jsonb_typeof(field->'formId') IS DISTINCT FROM 'number' OR field->>'formId' !~ '^[1-9][0-9]*$'
     OR jsonb_typeof(field->'products') IS DISTINCT FROM 'object'
     OR (field ? 'fields' AND jsonb_typeof(field->'fields')<>'object') THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid customer target mapping'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_each(field->'products') x WHERE x.key!~'^[1-9][0-9]*$' OR x.value::text!~'^[1-9][0-9]*$')
     OR EXISTS(SELECT 1 FROM jsonb_each(coalesce(field->'fields','{}')) x WHERE x.key!~'^[1-9][0-9]*$' OR x.value::text!~'^[1-9][0-9]*$') THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid customer target identifiers'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_each_text(coalesce(field->'fields','{}')) m GROUP BY m.value HAVING count(*)>1) THEN
     RAISE invalid_parameter_value USING MESSAGE='customer answer mapping must be one-to-one'; END IF;
   END LOOP;
  END IF;
  result:=result||jsonb_build_object(op.key,rule);
 END LOOP;
 IF (SELECT count(*) FROM jsonb_array_elements(coalesce(result#>'{move,targets}','[]')))<>(SELECT count(DISTINCT v->>'formId') FROM jsonb_array_elements(coalesce(result#>'{move,targets}','[]')) v) THEN
  RAISE invalid_parameter_value USING MESSAGE='duplicate customer target'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.normalize_customer_order_policy_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.save_customer_order_policy_internal(p_form bigint,p_policy jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE normalized jsonb; previous jsonb; fid bigint; rule jsonb; field jsonb; automatic_refund boolean;
BEGIN
 normalized:=public.normalize_customer_order_policy_internal(p_policy);
 automatic_refund:=normalized#>'{cancel,enabled}'='true'::jsonb AND normalized#>>'{cancel,refund_mode}'='automatic';
 IF public.can_manage_customer_order_policy(p_form,coalesce(automatic_refund,false)) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='customer policy editor required'; END IF;
 SELECT occasion INTO STRICT fid FROM public.forms WHERE id=p_form;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[fid]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 FOR field IN SELECT value FROM jsonb_array_elements(coalesce(normalized#>'{edit,fields}','[]')) LOOP
  IF NOT EXISTS(SELECT 1 FROM public.form_fields f WHERE f.form=p_form AND f.id=(field->>'id')::bigint
    AND f.type=field->>'type' AND NOT coalesce(f.is_hidden,false) AND f.product_type IS NULL) THEN
   RAISE invalid_parameter_value USING MESSAGE='customer field scope or type invalid'; END IF;
 END LOOP;
 FOR field IN SELECT value FROM jsonb_array_elements(coalesce(normalized#>'{move,targets}','[]')) LOOP
  IF NOT EXISTS(SELECT 1 FROM public.forms dst JOIN public.occasions target ON target.id=dst.occasion
    JOIN public.occasions source ON source.id=fid WHERE dst.id=(field->>'formId')::bigint AND dst.id<>p_form
    AND target.organization=source.organization AND public.can_read_form_catalog(target.id)) THEN
   RAISE invalid_parameter_value USING MESSAGE='customer target scope invalid'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_each_text(field->'products') mapping
    WHERE NOT EXISTS(SELECT 1 FROM eshop.products src JOIN eshop.products dst ON dst.id=mapping.value::bigint
      JOIN public.forms target ON target.id=(field->>'formId')::bigint WHERE src.id=mapping.key::bigint
      AND src.occasion=fid AND dst.occasion=target.occasion)) THEN
    RAISE invalid_parameter_value USING MESSAGE='customer product mapping scope invalid'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_each_text(coalesce(field->'fields','{}')) mapping
    WHERE NOT EXISTS(SELECT 1 FROM public.form_fields src JOIN public.form_fields dst ON dst.id=mapping.value::bigint
      WHERE src.id=mapping.key::bigint AND src.form=p_form AND dst.form=(field->>'formId')::bigint
      AND src.type=dst.type AND src.is_ticket_field IS NOT DISTINCT FROM dst.is_ticket_field
      AND NOT coalesce(src.is_hidden,false) AND NOT coalesce(dst.is_hidden,false))) THEN
    RAISE invalid_parameter_value USING MESSAGE='customer answer mapping scope invalid'; END IF;
 END LOOP;
 SELECT policy INTO previous FROM eshop.customer_order_change_policies WHERE form_id=p_form FOR UPDATE;
 IF previous IS NOT DISTINCT FROM normalized THEN RETURN; END IF;
 INSERT INTO eshop.customer_order_change_policies(form_id,revision,policy,updated_by)
 VALUES(p_form,1,normalized,auth.uid()) ON CONFLICT(form_id) DO UPDATE
 SET revision=eshop.customer_order_change_policies.revision+1,policy=excluded.policy,
  updated_at=clock_timestamp(),updated_by=auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.save_customer_order_policy_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_order_policy_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT jsonb_build_object('revision',revision,'policy',policy)
 FROM eshop.customer_order_change_policies WHERE form_id=p_form),'{"revision":0,"policy":{}}'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.customer_order_policy_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- This predicate is only a policy gate, never proof of customer ownership.
CREATE OR REPLACE FUNCTION public.customer_order_operation_enabled_internal(p_form bigint,p_operation text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.policy#>ARRAY[p_operation,'enabled']='true'::jsonb
  AND nullif(p.policy#>>ARRAY[p_operation,'allowed_until'],'')::timestamptz>statement_timestamp()
  AND jsonb_path_exists(coalesce(o.features,'[]'),'$[*] ? (@.code == "customer_self_service" && @.is_enabled == true)')
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN eshop.customer_order_change_policies p ON p.form_id=f.id
  WHERE f.id=p_form AND p_operation IN ('edit','cancel','move')),false);
$$;
REVOKE ALL ON FUNCTION public.customer_order_operation_enabled_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

-- A reason belongs only in the scoped request, never in technical audit payloads.
CREATE OR REPLACE FUNCTION public.validate_customer_cancellation_reason_internal(p_rule jsonb,p_reason text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE reason text:=nullif(btrim(p_reason),'');
BEGIN
 IF jsonb_typeof(p_rule->'reason_required') IS DISTINCT FROM 'boolean' THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid cancellation reason policy'; END IF;
 IF length(reason)>2000 OR (p_rule->'reason_required'='true'::jsonb AND reason IS NULL) THEN
  RAISE invalid_parameter_value USING MESSAGE='cancellation reason required or too long'; END IF;
 RETURN reason;
END $$;
REVOKE ALL ON FUNCTION public.validate_customer_cancellation_reason_internal(jsonb,text)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_order_feature_enabled_internal(p_form bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT jsonb_path_exists(coalesce(o.features,'[]'),'$[*] ? (@.code == "customer_self_service" && @.is_enabled == true)')
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form),false);
$$;
REVOKE ALL ON FUNCTION public.customer_order_feature_enabled_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_orders/update_order_responses.sql
CREATE OR REPLACE FUNCTION public.update_order_responses_domain_internal(
    p_order_id BIGINT,
    responses JSONB
)
RETURNS void
SECURITY INVOKER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_order_form_id BIGINT;
    v_current_state text;
    v_current_data JSONB;
    v_new_data JSONB;
    v_field_definitions JSONB;
    v_current_fields_map JSONB;
    v_merged_fields_map JSONB;
    v_new_fields_array JSONB;

    v_field_id_text TEXT;
    v_field_type TEXT;
    v_new_value JSONB;

    v_updated_order_state TEXT;
    v_updated_order_price NUMERIC(10, 2);
    v_updated_order_data JSONB;
BEGIN
    -- Fetch the order's current data, occasion, and form ID
    SELECT
        o.data,
        o.occasion,
        o.form,
        o.state
    INTO
        v_current_data,
        v_occasion_id,
        v_order_form_id,
        v_current_state
    FROM eshop.orders o
    WHERE o.id = p_order_id;

    -- Raise an exception if the SELECT INTO returned no row
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id;
    END IF;

    -- Reject the terminal state before form validation, without reversing
    -- the form -> order lock order used by form-field removal.
    IF v_current_state='storno' THEN
        RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
    END IF;

    -- Raise an exception if the order is not linked to a form
    IF v_order_form_id IS NULL THEN
        RAISE EXCEPTION 'Order % has no associated form.', p_order_id;
    END IF;

    -- Coordinate response validation/writes with form saves and field removal.
    PERFORM 1 FROM public.forms WHERE id = v_order_form_id FOR SHARE;
    PERFORM public.check_order_is_mutable(p_order_id);
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=p_order_id));
    SELECT data INTO v_current_data FROM eshop.orders WHERE id=p_order_id;

    -- Fetch all field definitions for this form into a JSONB map { "field_id": "field_type" }
    SELECT jsonb_object_agg(ff.id::text, ff.type)
    INTO v_field_definitions
    FROM public.form_fields ff
    WHERE ff.form = v_order_form_id;

    -- Raise an exception if the form has no fields
    IF v_field_definitions IS NULL THEN
        RAISE EXCEPTION 'No form fields found for form %', v_order_form_id;
    END IF;

    -- FIX: Use a LATERAL join to explicitly reference the columns from jsonb_each,
    -- resolving the "ambiguous column 'value'" error.
    SELECT jsonb_object_agg(je.key, je.value)
    INTO v_current_fields_map
    FROM jsonb_array_elements(v_current_data -> 'fields') AS jae(field_object),
         LATERAL jsonb_each(jae.field_object) AS je(key, value);

    -- Start with the current order data
    v_new_data := v_current_data;

    -- Merge the existing fields map with the new responses. New responses overwrite old ones.
    v_merged_fields_map := COALESCE(v_current_fields_map, '{}'::jsonb) || responses;

    -- Iterate through only the *incoming* responses to handle updates and nulls
    FOR v_field_id_text, v_new_value IN SELECT * FROM jsonb_each(responses)
    LOOP
        -- Get the type of the field being updated
        v_field_type := v_field_definitions ->> v_field_id_text;

        -- Validate that the field ID exists on this order's form
        IF v_field_type IS NULL THEN
            RAISE EXCEPTION 'Field ID % not found on form %', v_field_id_text, v_order_form_id;
        END IF;

        -- Handle null values: remove the key from the top level and from the merged map
        IF v_new_value IS NULL OR v_new_value = 'null'::jsonb THEN

            -- Remove from the map that will build the 'fields' array
            v_merged_fields_map := v_merged_fields_map - v_field_id_text;

            -- Remove top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data - 'name';
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data - 'surname';
            ELSIF v_field_type = 'email' THEN
                v_new_data := v_new_data - 'email';
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data - 'phone';
            END IF;

        -- Handle non-null values: update the top-level keys
        ELSE

            -- Update top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data || jsonb_build_object('name', v_new_value);
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data || jsonb_build_object('surname', v_new_value);
            ELSIF v_field_type = 'email' THEN
                IF NOT public.email_address_is_valid(v_new_value #>> '{}') THEN
                    RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact';
                END IF;
                v_new_data := v_new_data || jsonb_build_object('email', v_new_value);
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data || jsonb_build_object('phone', v_new_value);
            END IF;

        END IF;
    END LOOP;

    -- Rebuild the 'fields' array from the (now null-stripped) merged map
    -- It converts { "id": "val" } back to [ {"id": "val"} ]
    SELECT jsonb_agg(jsonb_build_object(key, value))
    INTO v_new_fields_array
    FROM jsonb_each(v_merged_fields_map);

    -- Set the new 'fields' array in the main data object
    v_new_data := jsonb_set(
        v_new_data,
        '{fields}',
        COALESCE(v_new_fields_array, '[]'::jsonb)
    );

    PERFORM public.notification_center_prepared_invalidate_order(p_order_id);
    -- Update the order in the database
    UPDATE eshop.orders
    SET
        data = v_new_data,
        updated_at = NOW()
    WHERE
        id = p_order_id
    RETURNING
        state, price, data
    INTO
        v_updated_order_state, v_updated_order_price, v_updated_order_data;

    -- Save the change to the orders_history table
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        p_order_id,
        v_updated_order_state,
        v_updated_order_price,
        v_updated_order_data,
        NOW()
    );

END;
$$;
REVOKE ALL ON FUNCTION public.update_order_responses_domain_internal(bigint,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.update_order_responses(p_order_id bigint,responses jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_occasion bigint;
BEGIN
 SELECT occasion INTO v_occasion FROM eshop.orders WHERE id=p_order_id;
 IF v_occasion IS NULL OR public.can_write_orders(v_occasion) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.update_order_responses_domain_internal(p_order_id,responses);
END $$;
REVOKE ALL ON FUNCTION public.update_order_responses(bigint,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.update_order_responses(bigint,jsonb) TO authenticated;

-- SOURCE: eshop_orders/update_order_detail_responses.sql
-- Scoped order-form answers retain their existing domain owner.
-- Ticket products and notes use their own existing owners.
DROP FUNCTION IF EXISTS public.update_order_detail_responses(bigint,bigint,bigint,jsonb,jsonb);
CREATE OR REPLACE FUNCTION public.update_order_detail_responses_domain_internal(
 p_order bigint,p_form bigint,p_expected_fields jsonb,p_responses jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; current_fields jsonb; entry record; ff public.form_fields;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL OR o.form IS DISTINCT FROM p_form
   OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=o.occasion) THEN
   RETURN jsonb_build_object('code',404,'message','Responses unavailable'); END IF;
 IF p_responses IS NULL OR jsonb_typeof(p_responses)<>'object' OR octet_length(p_responses::text)>65536 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid responses'; END IF;
 -- Use the same form -> order -> ticket lock order as response/grid owners.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR SHARE;
 PERFORM public.check_order_is_mutable(p_order);
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=p_order));
 SELECT * INTO o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF o.id IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
 IF o.form IS DISTINCT FROM p_form OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=o.occasion) THEN RETURN jsonb_build_object('code',409); END IF;
 current_fields:=coalesce(o.data->'fields','[]');
 IF current_fields IS DISTINCT FROM coalesce(p_expected_fields,'[]') THEN RETURN jsonb_build_object('code',409); END IF;
 FOR entry IN SELECT * FROM jsonb_each(p_responses) LOOP
   SELECT * INTO ff FROM public.form_fields WHERE form=p_form AND id::text=entry.key
     AND coalesce(is_ticket_field,false)=false;
   IF ff.id IS NULL OR ff.type IS NULL OR ff.type IN('sex','birth_year','birth_date','id_document','select_many','note','spot','product_type','ticket','email')
     OR (entry.value<>'null'::jsonb AND jsonb_typeof(entry.value)<>'string') THEN
     RAISE invalid_parameter_value USING MESSAGE='response field not editable'; END IF;
   IF ff.type='select_one' AND entry.value NOT IN('null'::jsonb,'""'::jsonb)
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(ff.data->'options','[]')) opt WHERE opt->'value'=entry.value) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid response option'; END IF;
 END LOOP;
 IF p_responses='{}' THEN RETURN jsonb_build_object('code',200); END IF;
 PERFORM public.update_order_responses_domain_internal(p_order,p_responses);
 RETURN jsonb_build_object('code',200);
END $$;
REVOKE ALL ON FUNCTION public.update_order_detail_responses_domain_internal(bigint,bigint,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.update_order_detail_responses(
 p_order bigint,p_form bigint,p_expected_fields jsonb,p_responses jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_occasion bigint;
BEGIN
 SELECT occasion INTO v_occasion FROM eshop.orders WHERE id=p_order AND form=p_form;
 IF v_occasion IS NULL OR public.can_write_orders(v_occasion) IS NOT TRUE THEN
  RETURN jsonb_build_object('code',404,'message','Responses unavailable'); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR SHARE;
 PERFORM 1 FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF public.can_write_orders(v_occasion) IS NOT TRUE THEN RETURN jsonb_build_object('code',404); END IF;
 RETURN public.update_order_detail_responses_domain_internal(p_order,p_form,p_expected_fields,p_responses);
END $$;
REVOKE ALL ON FUNCTION public.update_order_detail_responses(bigint,bigint,jsonb,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.update_order_detail_responses(bigint,bigint,jsonb,jsonb) TO authenticated;

-- SOURCE: payment_providers/effects.sql
-- Shared admission effect. Callers own authorization and financial interpretation.
-- This owner never manufactures a provider observation or changes original prices.
-- Lock hierarchy: payment policy fence -> capacity/forms -> order -> payment ->
-- provider attempt -> tickets. Callers that hold later locks must own the parents.
CREATE OR REPLACE FUNCTION public.cancel_online_order_admission_internal(p_order bigint,p_state text)
RETURNS bigint[] LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; cancelled bigint[];
BEGIN
 IF p_state IS NULL OR p_state NOT IN ('storno','expired') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid admission cancellation state'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info
  AND public.payment_method_is_online_internal(pi.payment_method)) THEN
  RAISE EXCEPTION 'ONLINE_ADMISSION_SOURCE_REQUIRED'; END IF;
 IF o.state=p_state THEN RETURN '{}'::bigint[]; END IF;
 SELECT array_agg(t.id ORDER BY t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t
 WHERE coalesce(t.state,'') NOT IN ('used','storno');
 PERFORM public.internal_storno_tickets_221(cancelled);
 UPDATE eshop.orders SET state=p_state,email_payment_version=email_payment_version+1,
  updated_at=clock_timestamp() WHERE id=o.id;
 PERFORM public.cancel_order_email_intents(o.id);
 RETURN coalesce(cancelled,'{}');
END $$;
REVOKE ALL ON FUNCTION public.cancel_online_order_admission_internal(bigint,text)
 FROM PUBLIC,anon,authenticated,service_role;

-- Lock order: capacity/form scope -> order -> payment -> provider attempt -> tickets.
-- All facts are read back from connector storage. No caller-supplied markPaid/amount.
CREATE OR REPLACE FUNCTION public.apply_provider_payment_effects_internal(
 p_provider text,p_attempt uuid,p_revision text,p_before jsonb,p_expired boolean DEFAULT false,
 p_unresolved boolean DEFAULT false,p_action text DEFAULT 'observe',p_tickets bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE context jsonb; prior jsonb; o eshop.orders; pi eshop.payment_info; totals record; projection jsonb; transition jsonb;
 received numeric; refunded numeric; payment_time timestamptz; deadline timestamptz; cancelled bigint[];
 conflict boolean; action_required boolean; changed boolean:=false; args jsonb:=jsonb_build_object('attemptId',p_attempt); decision jsonb; fact jsonb;
BEGIN
 IF p_provider IS NULL OR p_provider='bank' OR p_attempt IS NULL OR nullif(p_revision,'') IS NULL
  OR p_action IS NULL OR p_action NOT IN ('observe','keep','cancel_selected') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_INPUT_INVALID'; END IF;
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS NULL OR jsonb_typeof(context)<>'object' OR NOT context ?& ARRAY['attemptId','orderId','paymentId','connectionId','organizationId','unitId','accountId','livemode','amountMinor','currency','reservationExpiresAt','state','incomplete','receivedMinor','refundedMinor','paymentTime','decisions']
  OR context->>'attemptId' IS DISTINCT FROM p_attempt::text OR nullif(context->>'accountId','') IS NULL
  OR nullif(context->>'connectionId','') IS NULL OR (context->>'connectionId')::uuid IS NULL
  OR context->>'state' IS NULL OR context->>'state' NOT IN ('preparing','open','uncertain','paid','expired','action_required')
  OR jsonb_typeof(context->'livemode') IS DISTINCT FROM 'boolean' OR jsonb_typeof(context->'incomplete') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(context->'decisions') IS DISTINCT FROM 'array'
  OR jsonb_typeof(context->'amountMinor') IS DISTINCT FROM 'number' OR jsonb_typeof(context->'receivedMinor') IS DISTINCT FROM 'number'
  OR jsonb_typeof(context->'refundedMinor') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'PAYMENT_EFFECT_CONTEXT_INVALID'; END IF;
 prior:=context;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[(context->>'orderId')::bigint]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(context->>'orderId')::bigint FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 PERFORM public.payment_provider_call_internal(p_provider,'effect_lock',args);
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS DISTINCT FROM prior OR pi.id IS DISTINCT FROM (context->>'paymentId')::bigint
  OR pi.payment_method IS DISTINCT FROM p_provider OR pi.amount*100 IS DISTINCT FROM (context->>'amountMinor')::numeric
  OR pi.currency_code::text IS DISTINCT FROM context->>'currency'
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=(context->>'organizationId')::bigint AND unit=(context->>'unitId')::bigint)
  OR (p_before IS NOT NULL AND p_before->>'method' IS DISTINCT FROM p_provider) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_SCOPE_INVALID'; END IF;
 IF (context->>'amountMinor')::numeric<=0 OR (context->>'amountMinor')::numeric<>trunc((context->>'amountMinor')::numeric) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 received:=(context->>'receivedMinor')::numeric/100;refunded:=(context->>'refundedMinor')::numeric/100;
 deadline:=(context->>'reservationExpiresAt')::timestamptz;payment_time:=(context->>'paymentTime')::timestamptz;
 IF received<0 OR refunded<0 OR received>pi.amount OR refunded>received OR deadline IS NULL
  OR received*100<>trunc(received*100) OR refunded*100<>trunc(refunded*100)
  OR (received>0 AND payment_time IS NULL) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 conflict:=totals.gross_received>pi.amount OR totals.external_received<>0;
 action_required:=context->>'state'='action_required';
 IF p_action<>'observe' THEN
  IF auth.uid() IS NULL OR NOT public.can_write_orders(o.occasion) OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=(context->>'organizationId')::bigint)
   THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF refunded<=0 OR refunded>=pi.amount OR context->>'state'<>'paid' OR o.state NOT IN ('paid','sent') OR totals.invalid_identity
   OR context->'incomplete'='true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_PARTIAL_REFUND_REQUIRED'; END IF;
  IF (p_action='keep' AND cardinality(p_tickets)<>0) OR (p_action='cancel_selected' AND cardinality(p_tickets) NOT BETWEEN 1 AND 1000)
   OR EXISTS(SELECT 1 FROM unnest(p_tickets) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) t WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'PAYMENT_REFUND_TICKET_UNAVAILABLE'; END IF;
  PERFORM 1 FROM eshop.tickets WHERE id=ANY(p_tickets) ORDER BY id FOR UPDATE;
  IF p_action='cancel_selected' THEN
   PERFORM public.internal_storno_tickets_221(p_tickets);
   UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state<>'storno') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  END IF;
  decision:=public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason',CASE WHEN p_action='keep' THEN 'partial_refund_keep' ELSE 'partial_refund_cancel' END,'revision',p_revision,'tickets',to_jsonb(p_tickets)));
  PERFORM public.enqueue_order_wallet_internal(o.id);
  RETURN jsonb_build_object('changed',true,'decisionId',decision,'payment',public.provider_order_payment_projection_internal(o.id));
 END IF;
 IF conflict AND NOT context->'decisions' ? 'financial_conflict' THEN
  action_required:=true;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','financial_conflict','revision',p_revision));
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 IF received>=pi.amount AND refunded<pi.amount AND NOT conflict AND context->'incomplete'='false'::jsonb THEN
  IF o.state IN ('ordered','created') AND payment_time<=deadline THEN
   transition:=public.update_order_and_tickets_to_paid(o.id);
   IF transition->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'PAYMENT_PAID_TRANSITION_FAILED'; END IF;
   changed:=true;
  ELSIF o.state NOT IN ('paid','sent') THEN
   action_required:=true;
   PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
   IF NOT context->'decisions' ? 'late_payment' THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','late_payment','revision',p_revision)); END IF;
  END IF;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||jsonb_build_object('state',CASE WHEN action_required THEN 'action_required' ELSE 'paid' END));
 END IF;
 IF refunded>=pi.amount AND received>0 THEN
  IF NOT context->'decisions' ? 'full_refund' THEN
   cancelled:=public.cancel_online_order_admission_internal(o.id,'storno');
   PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','full_refund','revision',p_revision,'tickets',to_jsonb(coalesce(cancelled,'{}'))));
   changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND (p_expired OR (p_unresolved AND deadline<=clock_timestamp())) AND o.state='ordered' THEN
  cancelled:=public.cancel_online_order_admission_internal(o.id,'expired');
  -- Releasing inventory does not prove financial absence. Keep uncertain recovery alive.
  IF NOT p_unresolved THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"expired"}'); END IF;
  changed:=true;
 END IF;
 projection:=public.provider_order_payment_projection_internal(o.id);
 IF projection->>'admissionState' IS DISTINCT FROM p_before->>'admissionState' AND
  (projection->>'status'='disputed' OR p_before->>'status'='disputed' OR projection->'reconciliationPending'='true'::jsonb OR p_before->'reconciliationPending'='true'::jsonb) THEN
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('revision',p_revision,'reason',
   CASE WHEN projection->>'status'='disputed' THEN 'dispute_hold' WHEN p_before->>'status'='disputed' THEN 'dispute_release'
   WHEN projection->'reconciliationPending'='true'::jsonb THEN 'reconciliation_hold' ELSE 'reconciliation_release' END));
  IF projection->>'admissionState'='valid' THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  changed:=true;
 END IF;

 FOR fact IN SELECT value FROM jsonb_array_elements(public.payment_provider_call_internal(p_provider,'notification_facts',args)) LOOP
  PERFORM public.notification_center_payment_fact_internal(o.id,p_provider,fact->>'identity',(fact->>'amount')::numeric,fact->>'currency',(fact->>'occurredAt')::timestamptz);
 END LOOP;
 PERFORM public.notification_center_payment_problem_internal(o.id,action_required OR conflict,
  CASE WHEN conflict THEN 'financial_conflict' ELSE 'action_required' END);
 PERFORM public.enqueue_order_wallet_internal(o.id);
 RETURN jsonb_build_object('changed',changed,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.apply_provider_payment_effects_internal(text,uuid,text,jsonb,boolean,boolean,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: payment_providers/operations.sql
-- Shared preparation effect; administrative/customer boundaries own distinct
-- authorization. Only the original connector can determine write support.
-- Call after policy fence -> capacity -> order -> payment locks. No dispatch.
CREATE OR REPLACE FUNCTION public.prepare_order_refund_internal(
 p_order bigint,p_method text,p_amount numeric,p_command uuid,p_input jsonb,p_existing_debits bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; c jsonb; cap jsonb; req eshop.refund_requests;
 result jsonb; observed jsonb; debit_id bigint; v_method text:=p_method; amount numeric:=p_amount;
 existing_debits bigint[]:=p_existing_debits; p_command_id uuid:=p_command; input_data jsonb:=p_input;
 op text:='prepare_refund';
BEGIN
 IF jsonb_typeof(input_data) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PAYMENT_INPUT_INVALID'; END IF;
 input_data:=input_data||jsonb_build_object('operation',op,'orderId',p_order,'method',p_method,'amount',p_amount::text);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 IF p_command IS NULL OR amount IS NULL OR amount<=0 OR amount*100<>trunc(amount*100)
  OR amount>99999999.99 THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
 IF public.payment_method_is_online_internal(pi.payment_method) AND v_method IS DISTINCT FROM pi.payment_method THEN
  RAISE EXCEPTION 'PAYMENT_SOURCE_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=o.id) THEN RAISE EXCEPTION 'ORDER_DELETION_IN_PROGRESS'; END IF;
 c:=public.payment_method_context_internal(o.id);
 -- No synthetic manager permission is passed to a connector. Online connector
 -- capability is independent of the caller; bank/cash retain their own checks.
 cap:=public.payment_provider_call_internal(v_method,'operation_capabilities',jsonb_build_object('orderId',o.id));
 IF cap->'refund' IS DISTINCT FROM 'true'::jsonb OR NOT EXISTS(
   SELECT 1 FROM eshop.payment_providers WHERE provider_key=v_method AND refund_write_supported AND refund_write_enabled)
  OR c->'invalidIdentity' IS DISTINCT FROM 'false'::jsonb
  OR EXISTS(SELECT 1 FROM eshop.refund_requests rr WHERE rr.payment_info=pi.id AND rr.result->'deviation'='true'::jsonb) THEN
  RAISE EXCEPTION 'PAYMENT_REFUND_UNAVAILABLE'; END IF;
   IF EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=v_method AND NOT partial_refund_supported) AND amount IS DISTINCT FROM (c->>'net')::numeric THEN RAISE EXCEPTION 'PAYMENT_PARTIAL_REFUND_UNSUPPORTED'; END IF;
   IF amount>(c->>'available')::numeric THEN RAISE EXCEPTION 'REFUND_AVAILABLE_EXCEEDED'; END IF;
   IF public.payment_method_verification_internal(v_method)='bank_event' THEN
    PERFORM 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
     WHERE oc.id=o.occasion AND link.bank_account=pi.bank_account FOR SHARE OF link;
    IF NOT FOUND THEN RAISE EXCEPTION 'BANK_REFUND_SOURCE_UNLINKED'; END IF;
    -- An already imported debit with the same owned reference is evidence that
    -- must be reconciled before another instruction can be issued. No reverse locks.
    IF EXISTS(SELECT 1 FROM eshop.transactions t WHERE t.amount<0 AND t.payment_info IS NULL AND NOT t.id=ANY(coalesce(existing_debits,'{}'::bigint[]))
     AND (t.bank_account_id=pi.bank_account OR public.bank_sync_accounts_match(t.id,pi.bank_account))
     AND (trim(t.vs)=pi.variable_symbol::text OR (pi.currency_code='EUR' AND public.normalize_creditor_reference(t.payer_reference)=pi.creditor_reference))) THEN
      RAISE EXCEPTION 'REFUND_RETRY_NEW_BANK_FACT' USING ERRCODE='40001'; END IF;
   END IF;
   INSERT INTO eshop.refund_requests(id,order_id,payment_info,method,amount,currency,status,payload,created_by)
    VALUES(p_command_id,o.id,pi.id,v_method,amount,trim(pi.currency_code),'pending',input_data||jsonb_build_object('existingDebits',coalesce(to_jsonb(existing_debits),'[]')),auth.uid()) RETURNING * INTO req;
   IF public.payment_method_verification_internal(v_method)='verified_provider_observation' THEN
    UPDATE eshop.refund_requests SET payload=payload||jsonb_build_object('binding',public.payment_provider_call_internal(v_method,'refund_binding',jsonb_build_object('orderId',o.id))) WHERE id=req.id;
    result:=jsonb_build_object('nextAction','processing');
   ELSE
    result:=public.payment_provider_call_internal(v_method,op,input_data||jsonb_build_object('requestId',req.id));
    IF public.payment_method_verification_internal(v_method)='bank_event' AND cardinality(existing_debits)>0 THEN
     FOREACH debit_id IN ARRAY existing_debits LOOP
      observed:=public.observe_bank_refund_internal(debit_id);
      IF observed->'matched' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'REFUND_EXISTING_DEBIT_REQUIRES_RECONCILIATION'; END IF;
     END LOOP;
     result:=jsonb_build_object('nextAction','recorded');
    END IF;
   END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.prepare_order_refund_internal(bigint,text,numeric,uuid,jsonb,bigint[])
 FROM PUBLIC,anon,authenticated,service_role;

-- Private context is only embedded in authorized admin readers.
CREATE OR REPLACE FUNCTION public.payment_method_context_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 SELECT c.context INTO result FROM public.payment_method_contexts_internal(ARRAY[p_order]) c;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.payment_method_context_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_payment_operation_context(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occasion_id bigint;
BEGIN
 SELECT occasion INTO occasion_id FROM eshop.orders WHERE id=p_order_id;
 IF occasion_id IS NULL OR NOT public.can_read_orders(occasion_id) THEN RAISE insufficient_privilege; END IF;
 RETURN jsonb_build_object('code',200,'orderId',p_order_id,'context',public.payment_method_context_internal(p_order_id));
END $$;
REVOKE ALL ON FUNCTION public.get_payment_operation_context(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_payment_operation_context(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.command_payment_operation(input_data jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; op text:=input_data->>'operation'; v_method text:=input_data->>'method';
 c jsonb; cap jsonb; start_result jsonb; result jsonb; req eshop.refund_requests; users uuid[]; tx eshop.transactions; amount numeric; existing_debits bigint[]; debit_id bigint; observed jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(input_data->>'orderId')::bigint;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=o.occasion;
 IF public.payment_method_is_online_internal(pi.payment_method) AND v_method IS DISTINCT FROM pi.payment_method THEN RAISE EXCEPTION 'PAYMENT_SOURCE_MISMATCH'; END IF;
 IF input_data ? 'currency' AND input_data->>'currency' IS DISTINCT FROM trim(pi.currency_code) THEN RAISE EXCEPTION 'PAYMENT_CURRENCY_MISMATCH'; END IF;
 IF jsonb_typeof(input_data)<>'object' OR octet_length(input_data::text)>8192 THEN RAISE EXCEPTION 'PAYMENT_INPUT_INVALID'; END IF;
 IF op NOT IN ('record_payment','prepare_refund','cancel_pending','correct_record') OR op IS NULL THEN RAISE EXCEPTION 'PAYMENT_OPERATION_INVALID'; END IF;
 IF op IN ('cancel_pending','correct_record') AND input_data ? 'requestId' THEN
  SELECT * INTO STRICT req FROM eshop.refund_requests WHERE id=(input_data->>'requestId')::uuid AND order_id=o.id;
  v_method:=req.method;
 END IF;
 -- Re-authorize before receipt replay. Actual account and unit are stored facts.
 IF NOT coalesce((CASE WHEN public.payment_method_verification_internal(v_method)='local_commit' THEN public.can_record_order_cash(o.id)
  WHEN public.payment_method_verification_internal(v_method)='bank_event' THEN public.can_prepare_order_bank_refund(o.id)
  ELSE public.payment_method_verification_internal(v_method)='verified_provider_observation' AND v_method=pi.payment_method AND public.can_prepare_order_provider_refund(o.id) END),false)
 THEN RAISE insufficient_privilege USING MESSAGE='PAYMENT_OPERATION_FORBIDDEN'; END IF;
 IF public.payment_method_is_online_internal(pi.payment_method) AND v_method IS DISTINCT FROM pi.payment_method THEN RAISE EXCEPTION 'PAYMENT_SOURCE_MISMATCH'; END IF;
 IF op='correct_record' AND req.id IS NULL THEN
  SELECT t.* INTO tx FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
  WHERE t.id=(input_data->>'transactionId')::bigint AND t.payment_info=pi.id AND upper(b.type)='CASH' AND t.ingest_source='manual'
   AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id) FOR UPDATE OF t;
  IF tx.id IS NULL OR (input_data->>'amount')::numeric IS DISTINCT FROM -tx.amount THEN RAISE EXCEPTION 'PAYMENT_CORRECTION_INVALID'; END IF;
 END IF;
 -- Existing imported debits are locked before capacity/order/payment, matching
 -- ingest/pairing. A later unseen debit causes a retry instead of a reverse lock.
 IF op='prepare_refund' AND public.payment_method_verification_internal(v_method)='bank_event' THEN
  SELECT array_agg(candidate.id ORDER BY candidate.id) INTO existing_debits FROM (
   SELECT t.id FROM eshop.transactions t WHERE t.amount<0 AND t.payment_info IS NULL
    AND t.ingest_source IN ('banksync_api','fio_api')
    AND (t.bank_account_id=pi.bank_account OR public.bank_sync_accounts_match(t.id,pi.bank_account))
    AND (trim(t.vs)=pi.variable_symbol::text OR (pi.currency_code='EUR' AND public.normalize_creditor_reference(t.payer_reference)=pi.creditor_reference))
   ORDER BY t.id FOR UPDATE OF t) candidate;
 END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[o.id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=o.id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 IF op='correct_record' AND req.id IS NULL AND EXISTS(SELECT 1 FROM eshop.transaction_pairing_events e WHERE e.transaction_snapshot_id=tx.id AND e.method='exact_cash_correction') THEN RAISE EXCEPTION 'PAYMENT_CORRECTION_ALREADY_APPLIED'; END IF;
 start_result:=public.begin_client_mutation_v1(p_command_id,'orders.payment.operation',o.occasion,auth.uid(),encode(extensions.digest(input_data::text,'sha256'),'hex'));
 IF start_result->>'disposition'='replay' THEN
  result:=start_result->'response'; c:=public.payment_method_context_internal(o.id);
  SELECT value INTO cap FROM jsonb_array_elements(c->'requests') WHERE value->>'id'=p_command_id::text;
  result:=(result-'request'-'instructions')||jsonb_build_object('context',c,'request',cap);
  IF result ? 'data' THEN result:=jsonb_set(result,'{data}',((result->'data')-'request'-'instructions')||jsonb_build_object('context',c,'request',cap)); END IF;
  RETURN jsonb_set(result,'{mutation,replayed}','true');
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=o.id) THEN RAISE EXCEPTION 'ORDER_DELETION_IN_PROGRESS'; END IF;
 c:=public.payment_method_context_internal(o.id);
 IF op='cancel_pending' THEN
  SELECT * INTO STRICT req FROM eshop.refund_requests WHERE id=req.id FOR UPDATE;
  IF public.payment_method_verification_internal(req.method) IS DISTINCT FROM 'bank_event' OR input_data->'transferNotSubmitted' IS DISTINCT FROM 'true'::jsonb OR req.status<>'pending' THEN
   RAISE EXCEPTION 'REFUND_CANCELLATION_UNSAFE'; END IF;
  UPDATE eshop.refund_requests SET status='cancelled',updated_at=now() WHERE id=req.id;
  result:=jsonb_build_object('nextAction','recorded');
 ELSIF op='correct_record' AND req.id IS NOT NULL THEN
  IF public.payment_method_verification_internal(req.method) IS DISTINCT FROM 'local_commit' OR nullif(trim(input_data->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'REFUND_CORRECTION_INVALID'; END IF;
  -- This path only voids the immutable CASH fact; never bank/provider facts.
  UPDATE eshop.refund_settlements s SET voided_at=now(),void_reason=input_data->>'reason'
   FROM eshop.transactions t JOIN eshop.bank_accounts ba ON ba.id=t.bank_account_id
   WHERE s.transaction_id=t.id AND s.request_id=req.id AND s.voided_at IS NULL AND ba.type='CASH' AND t.ingest_source='manual';
  IF NOT FOUND THEN RAISE EXCEPTION 'REFUND_CORRECTION_INVALID'; END IF;
  UPDATE eshop.refund_requests SET status='cancelled',updated_at=now() WHERE id=req.id;
  PERFORM public.refresh_payment_info_totals_internal(pi.id);
  PERFORM public.reconcile_order_payment_internal_v1(o.id,'refund_fact');
  result:=jsonb_build_object('nextAction','recorded');
 ELSE
  SELECT value INTO cap FROM jsonb_array_elements(c->'methods') WHERE value->>'id'=v_method;
  IF op='prepare_refund' THEN
   IF cap->'refund' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_REFUND_UNAVAILABLE'; END IF;
  ELSIF op='record_payment' THEN
   IF cap->'record' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_RECORD_UNAVAILABLE'; END IF;
  ELSIF op='correct_record' AND (public.payment_method_verification_internal(v_method) IS DISTINCT FROM 'local_commit' OR nullif(trim(input_data->>'reason'),'') IS NULL) THEN
   RAISE EXCEPTION 'PAYMENT_CORRECTION_INVALID';
  END IF;
  IF jsonb_typeof(input_data->'amount') IS DISTINCT FROM 'string' OR input_data->>'amount' !~ '^-?[0-9]{1,8}(\.[0-9]{1,2})?$' THEN
   RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
  amount:=(input_data->>'amount')::numeric;
  IF amount=0 OR (op<>'correct_record' AND amount<0) THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
  IF op='prepare_refund' THEN
   result:=public.prepare_order_refund_internal(o.id,v_method,amount,p_command_id,input_data,existing_debits);
   SELECT * INTO STRICT req FROM eshop.refund_requests WHERE id=p_command_id;
  ELSE
   result:=public.payment_provider_call_internal(v_method,op,input_data);
   IF op='correct_record' THEN
    INSERT INTO eshop.transaction_pairing_events(transaction_snapshot_id,transaction_id,old_payment_info_id,new_payment_info_id,action,method,actor_kind,actor_id,details)
    VALUES(tx.id,tx.id,pi.id,pi.id,'paired','exact_cash_correction','user',auth.uid(),jsonb_build_object('reason',input_data->>'reason','correctionTransactionId',result->'transactionId'));
   END IF;
  END IF;
 END IF;
 IF req.id IS NOT NULL THEN
  INSERT INTO eshop.payment_operation_events(request_id,operation,actor,details) VALUES(req.id,op,auth.uid(),input_data);
  SELECT * INTO req FROM eshop.refund_requests WHERE id=req.id;
  SELECT value INTO cap FROM jsonb_array_elements(public.payment_method_context_internal(o.id)->'requests') WHERE value->>'id'=req.id::text;
  result:=result||jsonb_build_object('request',cap);
 END IF;
 SELECT coalesce(array_agg(DISTINCT "user"),'{}') INTO users FROM public.occasion_users WHERE occasion=o.occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,'orders.payment.operation',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','changedFields',jsonb_build_array('payment'))),users,
  jsonb_build_object('code',200,'orderId',o.id,'context',public.payment_method_context_internal(o.id))||result);
END $$;
REVOKE ALL ON FUNCTION public.command_payment_operation(jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.command_payment_operation(jsonb,uuid) TO authenticated;

-- Read-only impact preview. Final command repeats these checks under order locks.
CREATE OR REPLACE FUNCTION public.preview_payment_operation(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; c jsonb; cap jsonb; amount numeric; threshold numeric;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(input_data->>'orderId')::bigint;
 IF NOT public.can_read_orders(o.occasion) THEN RAISE insufficient_privilege; END IF;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 c:=public.payment_method_context_internal(o.id);
 SELECT value INTO cap FROM jsonb_array_elements(c->'methods') WHERE value->>'id'=input_data->>'method';
 IF cap->'refund' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_REFUND_UNAVAILABLE'; END IF;
 IF jsonb_typeof(input_data->'amount') IS DISTINCT FROM 'string' OR input_data->>'amount' !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
 amount:=(input_data->>'amount')::numeric;
 IF EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=input_data->>'method' AND NOT partial_refund_supported) AND amount IS DISTINCT FROM (c->>'net')::numeric THEN RAISE EXCEPTION 'PAYMENT_PARTIAL_REFUND_UNSUPPORTED'; END IF;
 IF amount<=0 OR amount>(c->>'available')::numeric THEN RAISE EXCEPTION 'REFUND_AVAILABLE_EXCEEDED'; END IF;
 threshold:=least(coalesce(pi.deposit_amount,o.price),o.price);
 RETURN jsonb_build_object('code',200,'preview',jsonb_build_object('netAfter',((c->>'net')::numeric-amount)::text,
  'availableAfter',((c->>'available')::numeric-amount)::text,'paidThreshold',threshold::text,
  'eligibleAfter',(c->>'net')::numeric-amount>=threshold,'lifecyclePreserved',o.state IN ('storno','expired') OR public.payment_method_is_online_internal(pi.payment_method),
  'currency',trim(pi.currency_code)));
END $$;
REVOKE ALL ON FUNCTION public.preview_payment_operation(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_payment_operation(jsonb) TO authenticated;

-- Rendering payment instructions is a read, not a refund reservation or ledger write.
CREATE OR REPLACE FUNCTION public.get_bank_refund_instructions(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; c jsonb; cap jsonb; amount numeric; iban text; name text;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(input_data->>'orderId')::bigint;
 IF NOT public.can_read_orders(o.occasion) THEN RAISE insufficient_privilege; END IF;
 PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=o.occasion;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 c:=public.payment_method_context_internal(o.id);
 SELECT value INTO cap FROM jsonb_array_elements(c->'methods') WHERE value->>'id'='bank';
 IF cap->'instructions' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_REFUND_UNAVAILABLE'; END IF;
 IF input_data->>'currency' IS DISTINCT FROM trim(pi.currency_code) THEN RAISE EXCEPTION 'PAYMENT_CURRENCY_MISMATCH'; END IF;
 IF jsonb_typeof(input_data->'amount') IS DISTINCT FROM 'string' OR input_data->>'amount' !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
 amount:=(input_data->>'amount')::numeric;
 IF amount<=0 OR amount>(c->>'available')::numeric THEN RAISE EXCEPTION 'REFUND_AVAILABLE_EXCEEDED'; END IF;
 iban:=public.canonical_payment_reference_account_internal(input_data->>'recipientIban');
 name:=trim(input_data->>'recipientName');
 IF name IS NULL OR length(name) NOT BETWEEN 1 AND 70 OR name ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'REFUND_RECIPIENT_INVALID'; END IF;
 IF trim(pi.currency_code)='CZK' AND iban NOT LIKE 'CZ%' THEN RAISE EXCEPTION 'SPD_DOMESTIC_ACCOUNT_REQUIRED'; END IF;
 RETURN jsonb_build_object('code',200,'sourceOrderId',o.id,'instructions',jsonb_build_object('purpose','bank_refund_instruction','method','bank','verification','bank_event','allowed',true,'sourceOrderId',o.id,'sourcePaymentId',pi.id,'sourceMethod',pi.payment_method,'recipientIban',iban,'recipientName',name,
  'amount',amount::text,'currency',trim(pi.currency_code),'variableSymbol',pi.variable_symbol::text,
  'creditorReference',pi.creditor_reference,'reference',CASE WHEN trim(pi.currency_code)='EUR' THEN pi.creditor_reference ELSE pi.variable_symbol::text END));
END $$;
REVOKE ALL ON FUNCTION public.get_bank_refund_instructions(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_refund_instructions(jsonb) TO authenticated;

-- SOURCE: eshop_forms/update_form_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.update_form_client_sync_v1(p_form jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_form bigint;
  v_begin jsonb; v_hash text; v_version bigint; v_expected bigint; v_users uuid[]; v_result jsonb; v_check record; v_current bigint;
BEGIN
  IF p_form IS NULL OR jsonb_typeof(p_form)<>'object'
    OR octet_length(p_form::text)>4194304 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid form aggregate'; END IF;
  v_occasion:=NULLIF(p_form->>'occasion','')::bigint;
  v_form:=NULLIF(p_form->>'id','')::bigint;
  IF v_actor IS NULL OR v_occasion IS NULL OR v_form IS NULL
    OR NOT public.can_author_forms(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  -- Financial policy entitlement is current even for an existing command receipt.
  IF p_form ? 'customer_self_service' THEN
    IF NOT p_form ? 'expected_aggregate_version' THEN
      RAISE invalid_parameter_value USING MESSAGE='customer policy requires original form revision'; END IF;
    IF public.can_manage_customer_order_policy(v_form,coalesce(
      p_form#>'{customer_self_service,cancel,enabled}'='true'::jsonb AND
      p_form#>>'{customer_self_service,cancel,refund_mode}'='automatic',false)) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='customer policy editor required'; END IF;
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'form',p_form)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=v_occasion));
  -- Parent order matches checkout: form, product, blueprint, then seats.
  PERFORM 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion FOR UPDATE;
  PERFORM 1 FROM eshop.product_types WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM eshop.products WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  IF v_form IS NOT NULL THEN
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_form::text FOR UPDATE;
  ELSE v_version:=0; END IF;
  IF (p_form#>'{settings,payments}' ? 'providerConnections' OR p_form#>'{data,payments}' ? 'providerConnections')
    AND NOT p_form ? 'expected_aggregate_version' THEN
    RAISE invalid_parameter_value USING MESSAGE='modern payment snapshot requires original form revision'; END IF;
  -- Missing baseline remains an installed-client adapter, explicitly not MCP-ready.
  v_expected:=CASE WHEN p_form ? 'expected_aggregate_version' THEN (p_form->>'expected_aggregate_version')::bigint ELSE v_version END;
  IF v_expected IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('aggregate_version',v_version)); END IF;
  -- These maps were frozen when the editor loaded. No read-before-write rebasing.
  -- Missing maps are the bounded released-client facade, not MCP-ready authoring.
  IF p_form ? 'expected_product_versions' OR p_form ? 'expected_product_type_versions' THEN
    IF jsonb_typeof(p_form->'expected_product_versions') IS DISTINCT FROM 'object'
      OR jsonb_typeof(p_form->'expected_product_type_versions') IS DISTINCT FROM 'object' THEN
      RAISE invalid_parameter_value USING MESSAGE='original product versions required'; END IF;
    FOR v_check IN
      SELECT DISTINCT 'product'::text kind, (p->>'id')::bigint id FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(nullif(f#>'{product_type,products}','null'),'[]')) p WHERE p->>'id' IS NOT NULL
      UNION SELECT 'product',value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_product_ids','[]'))
      UNION SELECT DISTINCT 'product',p.id FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
        WHERE ff.form=v_form AND ff.id IN (SELECT value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_field_ids','[]')))
      UNION SELECT DISTINCT 'product_type',(f#>>'{product_type,id}')::bigint FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        WHERE f#>>'{product_type,id}' IS NOT NULL
      ORDER BY 1,2
    LOOP
      IF NOT (CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions'
        ELSE p_form->'expected_product_type_versions' END) ? v_check.id::text THEN
        RAISE invalid_parameter_value USING MESSAGE='missing original product baseline'; END IF;
      IF (v_check.kind='product' AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=v_check.id AND occasion=v_occasion))
        OR (v_check.kind='product_type' AND NOT EXISTS(SELECT 1 FROM eshop.product_types WHERE id=v_check.id AND occasion=v_occasion)) THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('entity_type',v_check.kind,'entity_id',v_check.id,'deleted',true)); END IF;
      SELECT coalesce(v.version,0) INTO v_current FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
        ON v.aggregate_type=v_check.kind AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=v_check.id::text;
      IF ((CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions' ELSE p_form->'expected_product_type_versions' END)->>v_check.id::text)::bigint IS DISTINCT FROM v_current THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
          jsonb_build_object('aggregate_version',v_version,'entity_type',v_check.kind,'entity_id',v_check.id,'entity_version',v_current));
      END IF;
    END LOOP;
  END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.products p ON p.id=opt.product
  WHERE ou.occasion=v_occasion AND p.occasion=v_occasion;
  BEGIN
    v_result:=public.update_form_internal_v1(p_form-'expected_product_versions'-'expected_product_type_versions');
    IF coalesce((v_result->>'code')::integer,500)<>200 THEN
      RAISE SQLSTATE 'P0F01' USING MESSAGE='authoring domain rejected'; END IF;
  EXCEPTION WHEN SQLSTATE 'P0F01' THEN NULL;
  END;
  IF coalesce((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer BETWEEN 100 AND 599 THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  v_form:=(v_result->>'form_id')::bigint;
  IF p_form ? 'term_start_at' OR p_form ? 'term_end_at' THEN
    IF NOT p_form ? 'expected_aggregate_version' THEN RAISE invalid_parameter_value USING MESSAGE='term revision required'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_each(p_form) setting WHERE setting.key IN ('term_start_at','term_end_at')
      AND setting.value<>'null'::jsonb AND (jsonb_typeof(setting.value)<>'string' OR
      setting.value#>>'{}' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$')) THEN
      RAISE invalid_parameter_value USING MESSAGE='term requires explicit ISO instant'; END IF;
    UPDATE public.forms SET term_start_at=CASE WHEN p_form ? 'term_start_at' THEN (p_form->>'term_start_at')::timestamptz ELSE term_start_at END,
      term_end_at=CASE WHEN p_form ? 'term_end_at' THEN (p_form->>'term_end_at')::timestamptz ELSE term_end_at END WHERE id=v_form;
  END IF;
  IF p_form ? 'customer_self_service' THEN
    PERFORM public.save_customer_order_policy_internal(v_form,p_form->'customer_self_service');
  END IF;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,1)
    ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
    RETURNING version INTO v_version;
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version,
    'product_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product'),
    'product_type_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product_type'),
    'authoring',public.get_form_authoring_snapshot_internal(v_form));
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.save',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','update',
      'safeLabel',left(p_form->>'title',240),'changedFields',jsonb_build_array(
        'configuration','products'))),v_users,v_result);
END; $function$;

REVOKE ALL ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_form(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.update_form_client_sync_v1(input_data,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code')||result->'data';
END $$;
REVOKE ALL ON FUNCTION public.update_form(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form(jsonb) TO authenticated;

-- SOURCE: eshop_forms/get_form_for_edit.sql
-- Canonical editor projection shared by the checked UI and MCP boundaries.
CREATE OR REPLACE FUNCTION public.get_form_editor_bundle_internal(p_form_id bigint,p_related_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE
 SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_form_id BIGINT;
    v_occasion_id BIGINT;
    v_unit_id BIGINT;
    formData JSONB;
    formFieldsData JSONB;
    productTypesData JSONB;
    productsData JSONB;
    availableBankAccountsData JSONB;
    canDelete BOOLEAN;
BEGIN
    SELECT
        f.id,
        f.occasion,
        o.unit
    INTO
        v_form_id,
        v_occasion_id,
        v_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    IF v_form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found for the provided link.');
    END IF;

    -- Private projection; the checked public reader/command owns authorization.

    -- Use the same reference guard as deletion, including retained history.
    canDelete := (public.get_form_usage_internal(v_form_id)->>'blocking_orders')::bigint=0;

    SELECT jsonb_build_object(
        'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=f.occasion AND aggregate_id=f.id::text),0),
        'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'organizationIdentity',(SELECT CASE WHEN o.organization=u.organization THEN public.get_verified_unit_identity_internal(u.id) END FROM public.occasions o JOIN public.units u ON u.id=o.unit WHERE o.id=f.occasion),
        'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
        'key', f.key,
        'is_open', f.is_open,
        'created_at', f.created_at,
        'data', public.normalize_form_metadata_internal(f.data),
        'measurement_status', public.form_measurement_status_internal(f.id),
        'customer_self_service',public.customer_order_policy_internal(f.id)||jsonb_build_object('canEnableAutomaticRefund',public.can_manage_customer_order_policy(f.id,true)),
        'term_start_at',f.term_start_at,'term_end_at',f.term_end_at,
        'type', f.type,
        'title', f.title,
        'header', f.header,
        'header_off', f.header_off,
        'occasion', f.occasion,
        'blueprint', f.blueprint,
        'link', f.link,
        'bank_account', f.bank_account,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'can_delete', canDelete -- Added field
    )
    INTO formData
    FROM public.forms f
    WHERE f.id = v_form_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', pt.id,
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product_type' AND scope_type='occasion' AND scope_id=pt.occasion AND aggregate_id=pt.id::text),0),
            'title', pt.title,
            'description', pt.description,
            'type', pt.type,
            'data', pt.data,
            'occasion', pt.occasion
        ) ORDER BY pt.title
    ), '[]'::jsonb)
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id
      AND (NOT p_related_only OR pt.id IN (SELECT product_type FROM public.form_fields WHERE form=v_form_id));

    -- Materialize occasion history once rather than scanning it for every
    -- product and every field. Only current orders and current references determine eligibility.
    WITH occasion_orders AS MATERIALIZED (
      SELECT id, data FROM eshop.orders WHERE occasion = v_occasion_id
    ), snapshots AS MATERIALIZED (
      SELECT data FROM occasion_orders
    ), used_products AS MATERIALIZED (
      SELECT opt.product::text AS product FROM eshop.order_product_ticket opt
      JOIN eshop.products p ON p.id = opt.product WHERE p.occasion = v_occasion_id
      UNION
      SELECT value #>> '{}' FROM snapshots s
      CROSS JOIN LATERAL jsonb_path_query(s.data, '$.tickets[*].products[*].id') ids(value)
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=p.occasion AND aggregate_id=p.id::text),0),
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
            'occasion', p.occasion,
            'title', p.title,
            'description', p.description,
            'price', p.price,
            'currency_code', p.currency_code,
            'is_hidden', p.is_hidden,
            'order', p."order",
            'product_type', p.product_type,
            'ordered_count', (
                SELECT count(*)
                FROM eshop.order_product_ticket opt
                JOIN eshop.orders o ON opt."order" = o.id
                WHERE opt.product = p.id AND o.state <> 'storno'
            ),
            'maximum', p.maximum,
            'data', p.data
        ) ORDER BY COALESCE(p."order", 0)
    ), '[]'::jsonb)
    INTO productsData
    FROM eshop.products p
    CROSS JOIN LATERAL (SELECT CASE
      WHEN public.primary_product_delete_blocked_internal(p.id) THEN 'primary_product'
      WHEN EXISTS (SELECT 1 FROM used_products u WHERE u.product = p.id::text) THEN 'orders'
      WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
      WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
      WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
    END AS reason) usage
    WHERE p.occasion=v_occasion_id AND p.product_type IN (SELECT id FROM eshop.product_types WHERE occasion = v_occasion_id)
      AND (NOT p_related_only OR p.product_type IN (SELECT product_type FROM public.form_fields WHERE form=v_form_id));

    WITH form_orders AS MATERIALIZED (
      SELECT id, data FROM eshop.orders WHERE form = v_form_id
    ), form_snapshots AS MATERIALIZED (
      SELECT data FROM form_orders
    ), form_tickets AS MATERIALIZED (
      SELECT t.note FROM eshop.order_product_ticket opt
      JOIN form_orders o ON o.id = opt."order"
      JOIN eshop.tickets t ON t.id = opt.ticket
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ff.id,
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
            'form', ff.form,
            'title', ff.title,
            'description', ff.description,
            'data', ff.data,
            'type', ff.type,
            'is_required', ff.is_required,
            'is_hidden', ff.is_hidden,
            'is_ticket_field', ff.is_ticket_field,
            'order', ff."order",
            'product_type', ff.product_type
        ) ORDER BY COALESCE(ff."order", 0)
    ), '[]'::jsonb)
    INTO formFieldsData
    FROM public.form_fields ff
    CROSS JOIN LATERAL (SELECT CASE
      WHEN EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=ff.product_type AND pt.type='spot')
        OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM public.form_fields child
          JOIN eshop.product_types pt ON pt.id=child.product_type
          WHERE child.form=ff.form AND child.is_ticket_field AND pt.type='spot')) THEN 'primary_product'
      WHEN EXISTS (
      SELECT 1 FROM form_snapshots s WHERE
        EXISTS (SELECT 1 FROM jsonb_array_elements(
          CASE WHEN jsonb_typeof(s.data->'fields') = 'array' THEN s.data->'fields' ELSE '[]'::jsonb END) answer
          WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
        OR (ff.type = 'ticket' AND jsonb_path_exists(s.data, '$.tickets[*]'))
        OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(s.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
    ) OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM form_tickets))
      OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (SELECT 1 FROM form_tickets WHERE NULLIF(note, '') IS NOT NULL))
      OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
        WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
      OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form))
    THEN 'responses' ELSE (
      SELECT p->>'delete_blocked_reason' FROM public.form_fields member
      JOIN jsonb_array_elements(productsData) p ON (p->>'product_type')::bigint = member.product_type
      WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
        AND p->>'delete_blocked_reason' IS NOT NULL
      ORDER BY (p->>'id')::bigint LIMIT 1
    ) END AS reason) usage
    WHERE ff.form = v_form_id;

    availableBankAccountsData:=CASE WHEN p_related_only THEN '[]'::jsonb
        ELSE public.get_form_bank_accounts_internal(v_unit_id) END;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'form', formData,
            'form_fields', formFieldsData,
            'product_types', productTypesData,
            'products', productsData,
            'payment_method_policy',public.resolve_payment_method_policy_internal((SELECT organization FROM public.units WHERE id=v_unit_id),v_unit_id),
            'available_bank_accounts', availableBankAccountsData
        )
    );
END;
$$;
REVOKE ALL ON FUNCTION public.get_form_editor_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Released link-based entry remains a checked boundary on the same projection.
CREATE OR REPLACE FUNCTION public.get_form_for_edit(form_link text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE form_id bigint;
BEGIN
 form_id:=public.resolve_form_link_internal(form_link);
 IF form_id IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form not found for the provided link.'); END IF;
 IF public.can_read_form_catalog((SELECT occasion FROM public.forms WHERE id=form_id)) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='form catalog reader required'; END IF;
 RETURN public.get_form_editor_bundle_internal(form_id);
END $$;
REVOKE ALL ON FUNCTION public.get_form_for_edit(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_for_edit(text) TO anon,authenticated,service_role;

-- SOURCE: others/update_occasion.sql
CREATE OR REPLACE FUNCTION public.update_occasion_internal_v1(input_data JSONB)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 AS $$
 DECLARE
     updated_occ public.occasions;
     occ_id BIGINT;
     now TIMESTAMPTZ := NOW();
     final_unit BIGINT;

     -- Variable for the determined support flag
     is_app_supported BOOLEAN;

     -- Variable to help find the organization to check settings
     v_org_id BIGINT;

     -- Variables for feature handling
     new_blueprint_id BIGINT;
     v_form_id BIGINT;
     v_form_blueprint BIGINT;
     v_form_settings JSONB;
     v_form_link TEXT;
     v_reminder_interval_seconds BIGINT;
     v_email_order record;

     input_features JSONB;
     old_features JSONB;
     old_sync_enabled boolean := false;
     processed_features JSONB;
     feature JSONB;
     form_feature_found BOOLEAN;
 BEGIN
     -- Validate input data. Raise an exception if it's missing or empty.
     IF input_data IS NULL OR input_data = '{}'::jsonb THEN
         RAISE EXCEPTION 'Input data is missing or empty';
     END IF;

     -- 1. Identify the Organization ID
     IF (input_data->>'id') IS NOT NULL THEN
         -- Case A: UPDATE - Get organization from the existing occasion
         SELECT organization INTO v_org_id
         FROM public.occasions
         WHERE id = (input_data->>'id')::BIGINT;
     ELSE
         -- Case B: INSERT - Try to get organization from input
         v_org_id := (input_data->>'organization')::BIGINT;

         -- Case C: INSERT fallback - If org is missing, try to get it via the Unit
         IF v_org_id IS NULL AND (input_data->>'unit') IS NOT NULL THEN
            SELECT organization INTO v_org_id
            FROM public.units
            WHERE id = (input_data->>'unit')::BIGINT;
         END IF;
     END IF;

     -- 2. Fetch the setting from public.organizations.data
     -- Defaults to TRUE if the organization or the key is not found to ensure backward compatibility
     IF v_org_id IS NOT NULL THEN
         SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
         INTO is_app_supported
         FROM public.organizations
         WHERE id = v_org_id;
     ELSE
         is_app_supported := false;
     END IF;

     -- Ensure is_app_supported is not null (redundant safety check)
     is_app_supported := COALESCE(is_app_supported, false);

     --
     -- Prepare features based on is_app_supported flag
     --
     input_features := COALESCE(input_data->'features', '[]'::jsonb);
     processed_features := '[]'::jsonb;

     IF NOT is_app_supported THEN
         -- If the app is not supported, we must enable the 'form' feature.
         form_feature_found := false;
         -- Loop through existing features to find and enable the form feature
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             IF feature->>'code' = 'form' THEN
                 -- If form feature exists, ensure it is enabled
                 feature := feature || '{"is_enabled": true}';
                 form_feature_found := true;
             END IF;
             processed_features := processed_features || feature;
         END LOOP;

         -- If the form feature was not found in the original array, add it.
         IF NOT form_feature_found THEN
             processed_features := processed_features || '{"code": "form", "is_enabled": true}';
         END IF;
     ELSE
         -- If app is supported, use features as they were provided.
         processed_features := input_features;
     END IF;

     -- Determine if this is an UPDATE or INSERT based on the presence of an 'id'
     occ_id := (input_data->>'id')::BIGINT;

     IF occ_id IS NOT NULL THEN
         PERFORM public.lock_blueprint_scope_internal(ARRAY[occ_id]);
         PERFORM public.check_occasion_writable(occ_id);
         -- This is an UPDATE operation

         -- Check for the existence of the occasion and get its current unit
         SELECT unit, features, is_order_synchronization_enabled INTO final_unit, old_features, old_sync_enabled FROM public.occasions WHERE id = occ_id FOR UPDATE;
         IF NOT FOUND THEN
             RAISE EXCEPTION 'Occasion with ID % not found', occ_id;
         END IF;

         processed_features := public.merge_ticket_layout_features(old_features, processed_features, input_data->'ticket_layout_change');
         PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';

         -- Determine the final unit, allowing it to be updated.
         final_unit := COALESCE((input_data->>'unit')::BIGINT, final_unit);

         -- Security check: ensure the current user has editor rights on the target unit.
         IF NOT public.can_edit_occasion(occ_id,final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         IF (input_data ? 'organization' AND (input_data->>'organization')::bigint IS DISTINCT FROM v_org_id)
           OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=final_unit AND organization=v_org_id) THEN
           RAISE insufficient_privilege USING MESSAGE='Occasion tenant cannot change'; END IF;

         IF jsonb_path_exists(coalesce(old_features,'[]'), '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
           AND NOT jsonb_path_exists(processed_features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
           IF EXISTS(SELECT 1 FROM public.forms WHERE occasion=occ_id AND blueprint IS NOT NULL)
             OR EXISTS(SELECT 1 FROM eshop.spots WHERE occasion=occ_id AND blueprint IS NOT NULL AND
               (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()))) THEN
             RAISE EXCEPTION 'ASSIGNMENTS_EXIST'; END IF;
         END IF;

         UPDATE public.occasions
            SET customer_self_service_epoch=customer_self_service_epoch+CASE
                  WHEN (SELECT coalesce(jsonb_agg(f ORDER BY f::text),'[]'::jsonb) FROM jsonb_array_elements(coalesce(old_features,'[]')) f WHERE f->>'code'='customer_self_service')
                    IS DISTINCT FROM
                    (SELECT coalesce(jsonb_agg(f ORDER BY f::text),'[]'::jsonb) FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='customer_self_service')
                  THEN 1 ELSE 0 END,
                updated_at  = now,
                title       = COALESCE(input_data->>'title', title),
                description = COALESCE(input_data->>'description', description),
                link        = public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',false),
                data        = COALESCE(input_data->'data', data),
                is_hidden   = COALESCE((input_data->>'is_hidden')::BOOLEAN, is_hidden),
                is_open     = COALESCE((input_data->>'is_open')::BOOLEAN, is_open),
                is_promoted = COALESCE((input_data->>'is_promoted')::BOOLEAN, is_promoted),
                start_time  = COALESCE((input_data->>'start_time')::TIMESTAMPTZ, start_time),
                end_time    = COALESCE((input_data->>'end_time')::TIMESTAMPTZ, end_time),
                organization = COALESCE((input_data->>'organization')::BIGINT, organization),
                services    = COALESCE(input_data->'services', services),
                unit        = final_unit,
                is_order_synchronization_enabled=COALESCE((input_data->>'is_order_synchronization_enabled')::boolean,is_order_synchronization_enabled),
                features    = processed_features -- Use the processed features
          WHERE id = occ_id
          RETURNING * INTO updated_occ;

     ELSE
         -- This is an INSERT operation

         -- For new occasions, the 'unit' field is mandatory.
         final_unit := (input_data->>'unit')::BIGINT;
         IF final_unit IS NULL THEN
             RAISE EXCEPTION 'The "unit" field is required for new occasions';
         END IF;

         -- Security check for the new occasion's unit.
         IF NOT public.can_create_occasion(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         -- We still need to default 'reminder_is_enabled' for the 'form' feature if not specified.
         -- We do this on the already processed_features array.
         input_features := processed_features; -- Use the result from the is_app_supported logic
         processed_features := '[]'::jsonb;
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             -- If the current feature is the 'form' feature
             IF feature->>'code' = 'form' THEN
                 -- And if 'reminder_is_enabled' is NOT specified, default it to true.
                 IF NOT (feature ? 'reminder_is_enabled') THEN
                     feature := feature || '{"reminder_is_enabled": true}';
                 END IF;
             END IF;
             processed_features := processed_features || feature::jsonb;
         END LOOP;

         processed_features := public.merge_ticket_layout_features('[]', processed_features, input_data->'ticket_layout_change', true);

         INSERT INTO public.occasions(
             created_at, updated_at, title, description, link, data,
             is_hidden, is_open, is_promoted, start_time, end_time, organization,
             services, unit, features
         )
         VALUES(
             now, now,
             COALESCE(input_data->>'title', ''),
             COALESCE(input_data->>'description', ''),
             '',
             COALESCE(input_data->'data', '{}'::jsonb),
             COALESCE((input_data->>'is_hidden')::BOOLEAN, false),
             COALESCE((input_data->>'is_open')::BOOLEAN, true),
             COALESCE((input_data->>'is_promoted')::BOOLEAN, false),
             (input_data->>'start_time')::TIMESTAMPTZ,
             (input_data->>'end_time')::TIMESTAMPTZ,
             (input_data->>'organization')::BIGINT,
             COALESCE(input_data->'services', '{}'::jsonb),
             final_unit,
             processed_features
         )
         RETURNING * INTO updated_occ;

         -- Set the occ_id from the newly created record for subsequent logic
         occ_id := updated_occ.id;
         UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',true) WHERE id=occ_id RETURNING * INTO updated_occ;
     END IF;

     PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
     --
     -- Post-update/insert feature handling
     --

     -- Check if form feature is enabled and handle related logic.
     -- This will now be triggered if is_app_supported was false (based on organization settings).
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "form" && @.is_enabled == true)') THEN
         -- Extract the settings for the 'form' feature from the newly saved data
         SELECT elem INTO v_form_settings
         FROM jsonb_array_elements(updated_occ.features) AS elem
         WHERE elem->>'code' = 'form';

         -- Create a default form if one doesn't exist for the occasion
         IF NOT EXISTS (SELECT 1 FROM public.forms WHERE occasion = occ_id) THEN
             v_form_link := NULLIF(btrim(input_data->>'form_link'), '');
             IF input_data->>'id' IS NULL THEN
               PERFORM public.create_initial_occasion_form_internal_v1(occ_id,v_form_link,'Registration');
             ELSE
               PERFORM public.create_form(occ_id,v_form_link,'Registration');
             END IF;
         END IF;

         -- Check if reminders are enabled within the form feature
         IF (v_form_settings->>'reminder_is_enabled')::boolean IS TRUE THEN
             -- Get the reminder interval, defaulting to 1 day (86400 seconds) if not specified
             v_reminder_interval_seconds := COALESCE(
                 (v_form_settings->>'reminder_interval_seconds')::bigint,
                 86400
             );
             -- Call the function to queue payment reminders for all relevant orders

         END IF;
     END IF;

     -- Revalidate in-flight reminders after every relevant occasion update.
     PERFORM public.queue_payment_reminders(occ_id,coalesce(v_reminder_interval_seconds,86400));
     IF updated_occ.is_order_synchronization_enabled AND (
       NOT coalesce(old_sync_enabled,false) OR (
        NOT jsonb_path_exists(coalesce(old_features,'[]'), '$[*] ? (@.code == "ticket" && @.is_enabled == true)')
        AND jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "ticket" && @.is_enabled == true)'))) THEN
       FOR v_email_order IN SELECT id FROM eshop.orders WHERE occasion=occ_id AND state='paid' LOOP
         PERFORM public.enqueue_paid_order_tickets(v_email_order.id);
       END LOOP;
     END IF;
     PERFORM public.enqueue_wallet_scope_internal(occ_id);
     -- Check if the blueprint feature is enabled in the final, saved state
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
         -- Prepare a plan even when all forms use capacity/waitlisting.
         SELECT id INTO new_blueprint_id FROM eshop.blueprints
          WHERE occasion=occ_id AND (SELECT count(*) FROM eshop.blueprints WHERE occasion=occ_id)=1;
         IF new_blueprint_id IS NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion=occ_id) THEN
             INSERT INTO eshop.blueprints(occasion, organization, created_at, updated_at,layout)
             VALUES (occ_id, COALESCE(updated_occ.organization, 1), now, now,
              '{"schemaVersion":2,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1120,"height":2080,"fill":"#ffffffff"},"styles":{},"seatingDefaults":{},"textPolicy":{"language":"und","direction":"auto"},"nodes":[],"selectionUnits":[],"attachments":[],"sections":[],"presets":[]}'::jsonb)
             RETURNING id INTO new_blueprint_id;
         END IF;

         -- Saved seat selectors use the plan immediately. Ordinary forms keep
         -- their product choices, capacity and waitlist until that selector is enabled.
         PERFORM public.sync_form_blueprint_internal(id) FROM public.forms WHERE occasion=occ_id ORDER BY id;
     END IF;
 END;
 $$;

-- SOURCE: eshop/product_selection_contract.sql
-- Shared admission/required-product validation for checkout and term moves.
CREATE OR REPLACE FUNCTION public.assert_ticket_required_products_internal(p_form bigint,p_products bigint[])
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE missing_field bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE p.id=ANY(p_products) AND pt.type='spot') AND NOT coalesce((SELECT bool_and(is_hidden IS TRUE)
   FROM public.form_fields WHERE form=p_form AND type='ticket'),false) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',1015,'message','Spot product is missing in ticket fields')::text;
 END IF;
 SELECT ff.id INTO missing_field FROM public.form_fields ff WHERE ff.form=p_form AND ff.type='product_type'
  AND ff.is_ticket_field AND ff.is_required AND NOT ff.is_hidden AND NOT EXISTS(
   SELECT 1 FROM eshop.products p WHERE p.id=ANY(p_products) AND p.product_type=ff.product_type)
 ORDER BY ff.id LIMIT 1;
 IF FOUND THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',missing_field,'message','Required product selection missing')::text;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_ticket_required_products_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: customer_order_changes/move.sql
-- Selection validation is shared with the ordinary product materializer.

CREATE OR REPLACE FUNCTION public.remap_customer_move_answers_internal(p_data jsonb,p_source bigint,p_target bigint,p_map jsonb,p_ticket boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb:='[]'; field public.form_fields; source_field public.form_fields; source_id text; val jsonb;
BEGIN
 FOR field IN SELECT * FROM public.form_fields WHERE form=p_target AND coalesce(is_ticket_field,false)=p_ticket
  AND NOT coalesce(is_hidden,false) AND type NOT IN ('ticket','product_type') LOOP
  SELECT key INTO source_id FROM jsonb_each_text(coalesce(p_map,'{}')) WHERE value=field.id::text;
  SELECT * INTO source_field FROM public.form_fields WHERE form=p_source AND id::text=source_id AND type=field.type
   AND coalesce(is_ticket_field,false)=p_ticket AND NOT coalesce(is_hidden,false);
  SELECT v->source_id INTO val FROM jsonb_array_elements(coalesce(p_data->'fields','[]')) v WHERE v ? source_id LIMIT 1;
  IF source_field.id IS NULL OR field.type NOT IN ('name','surname','phone','email','text','city','address','select_one') THEN val:=NULL; END IF;
  IF field.is_required AND (val IS NULL OR jsonb_typeof(val)<>'string' OR nullif(btrim(val#>>'{}'),'') IS NULL) THEN
   RAISE EXCEPTION 'TARGET_ANSWERS_REQUIRED'; END IF;
  IF val IS NOT NULL THEN
   IF field.type='select_one' AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(field.data->'options','[]')) option WHERE option->'value'=val) THEN
    RAISE EXCEPTION 'TARGET_ANSWERS_INVALID'; END IF;
   result:=result||jsonb_build_array(jsonb_build_object(field.id::text,val));
  END IF;
 END LOOP;
 RETURN jsonb_set(coalesce(p_data,'{}'),'{fields}',result);
END $$;
REVOKE ALL ON FUNCTION public.remap_customer_move_answers_internal(jsonb,bigint,bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_move_preview_internal(p_order bigint,p_target bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; src public.forms; dst public.forms; cfg jsonb; mapping jsonb; field_map jsonb; capacity jsonb;
 item record; product eshop.products; ticket eshop.tickets; ids bigint[]; n bigint; reason text; order_data jsonb;
 items jsonb:='[]'; tickets jsonb:='[]'; td jsonb; snapshot jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT src FROM public.forms WHERE id=o.form;
 SELECT * INTO dst FROM public.forms WHERE id=p_target;
 SELECT v INTO cfg FROM jsonb_array_elements(coalesce(public.customer_order_policy_internal(src.id)#>'{policy,move,targets}','[]')) v
 WHERE v->>'formId'=p_target::text;
 IF dst.id IS NULL OR dst.id=src.id OR cfg IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_MOVE_TARGET_UNAVAILABLE'; END IF;
 mapping:=coalesce(cfg->'products','{}');field_map:=coalesce(cfg->'fields','{}');
 capacity:=public.get_form_capacity_snapshot_internal(dst.id);
 SELECT count(*) INTO n FROM public.get_order_tickets_internal(o.id);
 reason:=CASE WHEN dst.occasion<>src.occasion THEN 'different_occasion'
  WHEN dst.term_start_at IS NULL OR src.term_start_at IS NULL OR dst.term_end_at IS NULL OR src.term_end_at IS NULL THEN 'term_unavailable'
  WHEN NOT public.customer_order_operation_enabled_internal(dst.id,'move') THEN 'target_policy_unavailable'
  WHEN NOT coalesce((public.get_form_availability_snapshot_internal(dst.id)->>'isWindowOpen')::boolean,false) THEN 'target_closed'
  WHEN src.blueprint IS NOT NULL OR dst.blueprint IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE x."order"=o.id) THEN 'seating_requires_review'
  WHEN (capacity->>'remainingPublic')::bigint<n THEN 'target_full' END;
 BEGIN
  PERFORM public.assert_order_discount_unchanged_internal(o.id);
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='DISCOUNTED_ORDER_PRICE_IMMUTABLE' THEN reason:='discount_requires_review'; ELSE RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info AND
   (pi.deposit_amount IS NOT NULL OR (pi.payment_method='bank' AND dst.bank_account IS DISTINCT FROM pi.bank_account))) THEN reason:='payment_scope_requires_review'; END IF;
 IF public.payment_method_context_internal(o.id)->'invalidIdentity' IS DISTINCT FROM 'false'::jsonb
  OR coalesce((public.payment_method_context_internal(o.id)->>'pending')::numeric,0)>0
  OR public.provider_order_payment_projection_internal(o.id)->'reconciliationPending'='true'::jsonb
  OR public.provider_order_payment_projection_internal(o.id)->>'status' IN ('disputed','unknown','action_required') THEN reason:='finance_requires_review'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info AND public.payment_method_is_online_internal(pi.payment_method)
   AND (o.state NOT IN ('paid','sent') OR (public.get_effective_form_data(dst.id)#>ARRAY['payments','providerConnections',pi.payment_method]) IS DISTINCT FROM (to_jsonb(pi)->(pi.payment_method||'_connection_id')))) THEN reason:='payment_scope_requires_review'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.product_inventory_contexts c ON c.product=x.product WHERE x."order"=o.id) THEN reason:='inventory_requires_review'; END IF;
 BEGIN
  order_data:=public.remap_customer_move_answers_internal(o.data,src.id,dst.id,field_map,false);
  FOR ticket IN SELECT * FROM public.get_order_tickets_internal(o.id) LOOP
   ids:='{}'; items:='[]';
   FOR item IN SELECT * FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=ticket.id LOOP
    SELECT * INTO product FROM eshop.products WHERE id::text=mapping->>item.product::text;
    IF product.id IS NULL OR product.occasion<>src.occasion OR product.is_hidden
     OR product.currency_code<>o.currency_code OR product.price IS DISTINCT FROM item.net_price
     OR NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=dst.id AND product_type=product.product_type AND NOT is_hidden)
     OR EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product=product.id) THEN
      RAISE EXCEPTION 'PRODUCT_MAPPING_UNAVAILABLE'; END IF;
    IF product.maximum>0 AND (SELECT count(*) FROM eshop.order_product_ticket existing WHERE existing.product=product.id AND existing."order"<>o.id)
      +(SELECT count(*) FROM eshop.order_product_ticket x WHERE x."order"=o.id AND mapping->>x.product::text=product.id::text)>product.maximum THEN
      RAISE EXCEPTION 'TARGET_PRODUCT_FULL'; END IF;
    ids:=array_append(ids,product.id);
    items:=items||jsonb_build_array(jsonb_build_object('id',product.id,'title',product.title,'price',product.price,'currency_code',product.currency_code));
   END LOOP;
   IF cardinality(ids)<>(SELECT count(DISTINCT id) FROM unnest(ids) id) THEN RAISE EXCEPTION 'PRODUCT_MAPPING_AMBIGUOUS'; END IF;
   PERFORM public.assert_ticket_required_products_internal(dst.id,ids);
   td:=public.remap_customer_move_answers_internal(ticket.data,src.id,dst.id,field_map,true);
   tickets:=tickets||jsonb_build_array(jsonb_build_object('id',ticket.id,'fields',td->'fields','products',items));
  END LOOP;
 EXCEPTION WHEN raise_exception THEN reason:=coalesce(reason,'target_configuration_requires_review'); END;
 RETURN jsonb_build_object('formId',dst.id,'title',dst.title,'startsAt',dst.term_start_at,'endsAt',dst.term_end_at,
  'automatic',reason IS NULL,'reason',reason,'capacity',capacity-'serverTime','priceDifference',0,'tickets',tickets,
  'orderFields',order_data->'fields','products',mapping,'fieldMap',field_map);
END $$;
REVOKE ALL ON FUNCTION public.customer_move_preview_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_move_targets_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(public.customer_move_preview_internal(o.id,(t->>'formId')::bigint)),'[]')
 FROM eshop.orders o CROSS JOIN LATERAL jsonb_array_elements(coalesce(public.customer_order_policy_internal(o.form)#>'{policy,move,targets}','[]')) t
 WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.customer_move_targets_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.move_customer_order_domain_internal(p_order bigint,p_target bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; preview jsonb; ticket jsonb; symbol text; ticket_snapshots jsonb; source bigint; org bigint;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;source:=o.form;
 PERFORM public.assert_order_discount_unchanged_internal(o.id);
 preview:=public.customer_move_preview_internal(o.id,p_target);
 IF preview->'automatic' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=o.occasion;
 -- Retain an explicit original snapshot; no price/payment mutation is allowed.
 INSERT INTO eshop.orders_history("order",state,price,data,currency_code) VALUES(o.id,o.state,o.price,o.data||jsonb_build_object('formId',source),o.currency_code);
 UPDATE eshop.order_product_ticket x SET product=(preview#>>ARRAY['products',x.product::text])::bigint
 WHERE x."order"=o.id;
 FOR ticket IN SELECT value FROM jsonb_array_elements(preview->'tickets') LOOP
  symbol:=public.generate_ticket_symbol(org,o.occasion);
  UPDATE eshop.tickets t SET ticket_symbol=symbol,data=jsonb_set(coalesce(t.data,'{}'),'{fields}',ticket->'fields') WHERE id=(ticket->>'id')::bigint;
  ticket:=ticket||jsonb_build_object('ticket_symbol',symbol);
  ticket_snapshots:=coalesce(ticket_snapshots,'[]')||jsonb_build_array(ticket);
 END LOOP;
 UPDATE eshop.orders SET form=p_target,data=jsonb_set(jsonb_set(o.data,'{fields}',preview->'orderFields'),'{tickets}',coalesce(ticket_snapshots,'[]')),
  email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
 -- The established overview URL and token continue to follow this same order.
 UPDATE eshop.waitlist_capabilities SET form_id=p_target WHERE order_id=o.id AND kind='order_view' AND revoked_at IS NULL;
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(source,p_target);
 PERFORM public.cancel_order_email_intents(o.id);
 PERFORM public.refresh_order_wallet_term_domain_internal(o.id);
 PERFORM public.enqueue_order_wallet_internal(o.id);
 IF o.state IN ('paid','sent') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
 INSERT INTO eshop.orders_history("order",state,price,data,currency_code)
 SELECT ord.id,ord.state,ord.price,ord.data||jsonb_build_object('formId',ord.form),ord.currency_code FROM eshop.orders ord WHERE ord.id=o.id;
END $$;
REVOKE ALL ON FUNCTION public.move_customer_order_domain_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: customer_order_changes/preview.sql
-- One domain projection serves customer UI, confirmation and email context.
CREATE OR REPLACE FUNCTION public.customer_change_read_scope_internal(p_token text,p_order bigint)
RETURNS eshop.waitlist_capabilities LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE c eshop.waitlist_capabilities;
BEGIN
 IF p_token IS NULL OR p_token!~'^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY' USING ERRCODE='42501'; END IF;
 SELECT cap.* INTO c FROM eshop.waitlist_capabilities cap JOIN eshop.orders o ON o.id=cap.order_id
 JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion JOIN public.occasions oc ON oc.id=o.occasion
 WHERE cap.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND cap.kind='order_view'
 AND cap.order_id=p_order AND cap.form_id=f.id AND cap.organization_id=oc.organization
 AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp();
 IF c.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY' USING ERRCODE='42501'; END IF;
 RETURN c;
END $$;
REVOKE ALL ON FUNCTION public.customer_change_read_scope_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_order_change_requests_internal(p_order bigint,p_staff boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'operation',operation,'status',status,
 'reason',reason,'response',response,'ticketIds',to_jsonb(ticket_ids),'targetFormId',target_form_id,'createdAt',created_at,'updatedAt',updated_at,
 'canWithdraw',status='open' AND public.customer_order_feature_enabled_internal((SELECT form FROM eshop.orders WHERE id=p_order)),'canDecide',p_staff AND status='open') ORDER BY created_at DESC),'[]')
 FROM eshop.customer_order_change_requests WHERE order_id=p_order;
$$;
REVOKE ALL ON FUNCTION public.customer_order_change_requests_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_order_actions_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; policy jsonb; op text; rule jsonb; actions jsonb:='[]'; enabled boolean; reason text;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 policy:=public.customer_order_policy_internal(o.form)->'policy';
 FOREACH op IN ARRAY ARRAY['edit','cancel','move'] LOOP
  rule:=policy->op;
  enabled:=public.customer_order_operation_enabled_internal(o.form,op);
  reason:=CASE WHEN NOT enabled THEN 'policy_unavailable'
   WHEN o.state NOT IN ('ordered','created','paid','sent') THEN 'order_unavailable'
   WHEN EXISTS(SELECT 1 FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=op AND status='open') THEN 'request_pending'
   WHEN o.source_waitlist_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.orders WHERE source_waitlist_order_id=o.id)
    OR EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state='waitlisted') THEN 'waitlist_family'
   ELSE NULL END;
  actions:=actions||jsonb_build_array(jsonb_build_object('operation',op,'enabled',reason IS NULL,'reason',reason,
   'allowedUntil',rule->'allowed_until','mode',rule->'mode','reasonRequired',rule->'reason_required',
   'refundMode',rule->'refund_mode','tickets',CASE WHEN op='cancel' AND reason IS NULL THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,o.form)) ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t WHERE t.state NOT IN ('used','storno','expired','stock','waitlisted','preparing_payment')) ELSE '[]'::jsonb END,'fields',CASE WHEN op='edit' AND reason IS NULL THEN (
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'type',f.type,'title',f.title,'required',f.is_required,
     'ticket',f.is_ticket_field,'options',f.data->'options',
     'value',(SELECT answer->f.id::text FROM jsonb_array_elements(coalesce(o.data->'fields','[]')) answer WHERE answer ? f.id::text LIMIT 1),
     'values',(SELECT jsonb_agg(jsonb_build_object('ticketId',t.id,'value',(SELECT answer->f.id::text FROM jsonb_array_elements(coalesce(t.data->'fields','[]')) answer WHERE answer ? f.id::text LIMIT 1)) ORDER BY t.id) FROM public.get_order_tickets_internal(o.id) t))),'[]') FROM public.form_fields f
    JOIN jsonb_array_elements(rule->'fields') allow ON (allow->>'id')::bigint=f.id AND allow->>'type'=f.type
    WHERE f.form=o.form AND NOT coalesce(f.is_hidden,false) AND f.product_type IS NULL) END,
   'targets',CASE WHEN op='move' AND reason IS NULL THEN public.customer_move_targets_internal(o.id) ELSE '[]'::jsonb END));
 END LOOP;
 RETURN actions;
END $$;
REVOKE ALL ON FUNCTION public.customer_order_actions_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_customer_order_change_internal(p_order bigint,p_operation text,p_payload jsonb,p_staff boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; rule jsonb; rev bigint; effect text; blocked text; reason text;
 f public.form_fields; ticket_id bigint; patch record; finance jsonb; amount numeric:=0; target jsonb;
 selected bigint[]; partial boolean:=false; selected_price numeric;
 snapshot jsonb; fields jsonb; current_value jsonb; all_payload jsonb;
BEGIN
 IF p_operation IS NULL OR p_operation NOT IN ('edit','cancel','move','withdraw') OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object'
  OR octet_length(p_payload::text)>32768 THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_CHANGE_INPUT_INVALID'; END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 SELECT revision,policy->p_operation INTO rev,rule FROM eshop.customer_order_change_policies WHERE form_id=o.form;
 IF NOT p_staff AND NOT (CASE WHEN p_operation='withdraw' THEN public.customer_order_feature_enabled_internal(o.form) ELSE public.customer_order_operation_enabled_internal(o.form,p_operation) END) THEN
  RAISE insufficient_privilege USING MESSAGE='CUSTOMER_CHANGE_UNAVAILABLE'; END IF;
 IF p_operation='withdraw' THEN
  IF p_payload-ARRAY['requestId']<>'{}'::jsonb OR NOT EXISTS(SELECT 1 FROM eshop.customer_order_change_requests
   WHERE id=(p_payload->>'requestId')::uuid AND order_id=o.id AND status='open') THEN
   RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
  effect:='withdraw';
 ELSE
  IF NOT p_staff AND p_operation IN ('cancel','move') AND EXISTS(SELECT 1 FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=p_operation AND status='open') THEN RAISE EXCEPTION 'CUSTOMER_REQUEST_ALREADY_OPEN' USING ERRCODE='40001'; END IF;
  IF o.state NOT IN ('created','ordered','paid','sent') OR o.source_waitlist_order_id IS NOT NULL
   OR EXISTS(SELECT 1 FROM eshop.orders WHERE source_waitlist_order_id=o.id)
   OR EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state IN ('waitlisted','stock','preparing_payment')) THEN
   RAISE EXCEPTION 'CUSTOMER_ORDER_UNAVAILABLE' USING ERRCODE='40001'; END IF;
  IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=o.id) THEN RAISE EXCEPTION 'CUSTOMER_ORDER_UNAVAILABLE' USING ERRCODE='40001'; END IF;
  IF p_operation='cancel' AND p_payload ? 'ticketIds' THEN
   IF jsonb_typeof(p_payload->'ticketIds') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'ticketIds') NOT BETWEEN 1 AND 1000
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'ticketIds') id WHERE jsonb_typeof(id)<>'number' OR id::text!~'^[1-9][0-9]*$') THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_TICKET_SELECTION_INVALID'; END IF;
   SELECT array_agg(value::bigint ORDER BY value::bigint) INTO selected FROM jsonb_array_elements_text(p_payload->'ticketIds');
   IF cardinality(selected)<>(SELECT count(DISTINCT id) FROM unnest(selected) id) OR EXISTS(SELECT 1 FROM unnest(selected) chosen(id) WHERE NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) t WHERE t.id=chosen.id AND t.state NOT IN ('storno','expired','stock','waitlisted','preparing_payment'))) THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_TICKET_SELECTION_INVALID'; END IF;
   partial:=cardinality(selected)<(SELECT count(*) FROM public.get_order_tickets_internal(o.id) WHERE state NOT IN ('storno','expired'));
  ELSE SELECT array_agg(id ORDER BY id) INTO selected FROM public.get_order_tickets_internal(o.id); END IF;
  -- Mutability/print guards below are translated into a request only for a
  -- supported request operation. No exception can commit a partial mutation.
  IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state='used' AND id=ANY(selected)) THEN blocked:='used_ticket'; END IF;
  BEGIN
   PERFORM public.check_batch_ticket_print_immutable_internal(selected);
  EXCEPTION WHEN SQLSTATE '55000' THEN blocked:='immutable_print'; END;
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=o.id AND (data ? 'fakturoid_invoice_id' OR data ? 'invoice_id'))
   OR EXISTS(SELECT 1 FROM eshop.external_services WHERE unit=oc.unit AND type='FAKTUROID')
   OR EXISTS(SELECT 1 FROM eshop.replacement_invoice_preparations WHERE order_id=o.id AND state NOT IN ('failed','cancelled')) THEN blocked:='invoice_review'; END IF;
  -- All provider/bank/cash facts and reservations come from the existing engine.
  finance:=public.payment_method_context_internal(o.id);
  amount:=coalesce((finance->>'net')::numeric,0);
  IF p_operation='edit' THEN
   IF blocked IS NOT NULL THEN RAISE EXCEPTION 'CUSTOMER_ORDER_UNAVAILABLE' USING ERRCODE='40001'; END IF;
   IF (coalesce(p_payload->'order','{}')='{}'::jsonb AND coalesce(p_payload->'tickets','{}')='{}'::jsonb) OR p_payload-ARRAY['order','tickets']<>'{}'::jsonb OR (NOT p_payload ? 'order' AND NOT p_payload ? 'tickets')
    OR (p_payload ? 'order' AND jsonb_typeof(p_payload->'order')<>'object')
    OR (p_payload ? 'tickets' AND jsonb_typeof(p_payload->'tickets')<>'object') THEN
    RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_FIELDS_INVALID'; END IF;
   FOR ticket_id,fields IN
    SELECT NULL::bigint,coalesce(p_payload->'order','{}') UNION ALL
    SELECT key::bigint,value FROM jsonb_each(coalesce(p_payload->'tickets','{}'))
   LOOP
    IF jsonb_typeof(fields)<>'object' OR (ticket_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE id=ticket_id)) THEN
     RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_FIELDS_INVALID'; END IF;
    FOR patch IN SELECT * FROM jsonb_each(fields) LOOP
     SELECT * INTO f FROM public.form_fields WHERE form=o.form AND id::text=patch.key
      AND coalesce(is_ticket_field,false)=(ticket_id IS NOT NULL) AND NOT coalesce(is_hidden,false) AND product_type IS NULL;
     IF f.id IS NULL OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(rule->'fields','[]')) a WHERE a->>'id'=f.id::text AND a->>'type'=f.type)
      OR f.type NOT IN ('name','surname','phone','text','city','address','select_one')
      OR jsonb_typeof(patch.value) IS DISTINCT FROM 'string' OR length(patch.value#>>'{}')>4000
      OR (f.is_required AND nullif(btrim(patch.value#>>'{}'),'') IS NULL)
      OR (f.type='select_one' AND patch.value NOT IN ('""'::jsonb,'null'::jsonb) AND NOT EXISTS(
        SELECT 1 FROM jsonb_array_elements(coalesce(f.data->'options','[]')) option WHERE option->'value'=patch.value)) THEN
      RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_FIELDS_INVALID'; END IF;
    END LOOP;
   END LOOP;
   effect:='edit';
  ELSIF p_operation='cancel' THEN
   IF p_payload-ARRAY['reason','ticketIds']<>'{}'::jsonb OR (p_payload ? 'reason' AND jsonb_typeof(p_payload->'reason')<>'string') THEN
    RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_CHANGE_INPUT_INVALID'; END IF;
   reason:=public.validate_customer_cancellation_reason_internal(rule,p_payload->>'reason');
   effect:=CASE WHEN NOT p_staff AND rule->>'mode'='approval_required' THEN 'request_cancel'
    WHEN blocked IS NOT NULL THEN 'request_cancel' ELSE 'cancel' END;
   IF amount>0 THEN
    IF rule->>'refund_mode'='none' THEN effect:='request_cancel';blocked:='paid_order_requires_review';
    ELSIF rule->>'refund_mode'='manual' THEN effect:=CASE WHEN effect='cancel' THEN 'cancel_manual_refund' ELSE effect END;
    ELSIF effect='cancel' THEN
     IF finance->'invalidIdentity' IS DISTINCT FROM 'false'::jsonb OR (finance->>'pending')::numeric<>0
      OR (finance->>'available')::numeric IS DISTINCT FROM amount
      OR public.provider_order_payment_projection_internal(o.id)->>'status' IN ('disputed','unknown','action_required')
      OR public.provider_order_payment_projection_internal(o.id)->'reconciliationPending'='true'::jsonb
      OR NOT EXISTS(SELECT 1 FROM eshop.payment_info pi JOIN eshop.payment_providers pp ON pp.provider_key=pi.payment_method
        WHERE pi.id=o.payment_info AND pp.hosted_checkout AND pp.refund_write_supported AND pp.refund_write_enabled
        AND public.payment_provider_call_internal(pi.payment_method,'refund_binding',jsonb_build_object('orderId',o.id)) IS NOT NULL) THEN
       effect:='request_cancel';blocked:='refund_requires_review';
     ELSE effect:='cancel_refund'; END IF;
    END IF;
   ELSIF amount<0 OR finance->'invalidIdentity'='true'::jsonb OR coalesce((finance->>'pending')::numeric,0)>0
    OR EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info AND public.payment_method_is_online_internal(pi.payment_method)) THEN
    -- No-money online checkout may still collect. Customer cannot manufacture
    -- provider expiry or free a reservation while collection is uncertain.
    effect:='request_cancel';blocked:='collection_unresolved';
   END IF;
   IF partial THEN
    -- The existing bank/cash partial-cancellation owner reduces only selected
    -- sale lines. Online admission/refund selection stays with its provider owner.
    SELECT coalesce(sum((product->>'price')::numeric),0) INTO selected_price FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) ticket CROSS JOIN LATERAL jsonb_array_elements(coalesce(ticket->'products','[]')) product WHERE (ticket->>'id')::bigint=ANY(selected);
    IF EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info AND (public.payment_method_is_online_internal(pi.payment_method) OR pi.deposit_amount IS NOT NULL)) OR (amount>0 AND amount<o.price) OR o.data ? 'discount' OR selected_price<0 OR selected_price>o.price THEN effect:='request_cancel';blocked:='partial_finance_requires_review'; END IF;
    BEGIN PERFORM public.assert_order_discount_unchanged_internal(o.id);
    EXCEPTION WHEN raise_exception THEN IF SQLERRM='DISCOUNTED_ORDER_PRICE_IMMUTABLE' THEN effect:='request_cancel';blocked:='discount_requires_review'; ELSE RAISE;END IF;END;
    amount:=least(greatest(amount,0),selected_price);
   END IF;
   BEGIN PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE x.ticket=ANY(selected)));
   EXCEPTION WHEN invalid_parameter_value OR check_violation THEN effect:='request_cancel';blocked:='seat_selection_requires_review'; END;
   IF finance->'invalidIdentity'='true'::jsonb OR coalesce((finance->>'pending')::numeric,0)>0
    OR public.provider_order_payment_projection_internal(o.id)->>'status' IN ('disputed','unknown','action_required')
    OR public.provider_order_payment_projection_internal(o.id)->'reconciliationPending'='true'::jsonb THEN
    effect:='request_cancel';blocked:='finance_requires_review'; END IF;
  ELSE
   IF p_payload-ARRAY['targetFormId','reason']<>'{}'::jsonb OR jsonb_typeof(p_payload->'targetFormId') IS DISTINCT FROM 'number'
    OR length(coalesce(p_payload->>'reason',''))>2000 THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_MOVE_INVALID'; END IF;
   target:=public.customer_move_preview_internal(o.id,(p_payload->>'targetFormId')::bigint);
   effect:=CASE WHEN blocked IS NULL AND target->'automatic'='true'::jsonb THEN 'move' ELSE 'request_move' END;
   blocked:=coalesce(blocked,target->>'reason');
  END IF;
 END IF;
 snapshot:=jsonb_build_object('form',o.form,'state',o.state,'data',o.data,'price',o.price,'payment',o.payment_info,
  'policyRevision',rev,'epoch',oc.customer_self_service_epoch,'effect',effect,'payload',p_payload,'finance',finance-ARRAY['methods','requests'],
  'refunds',(SELECT jsonb_agg(jsonb_build_object('id',rr.id,'status',rr.status,'amount',rr.amount) ORDER BY rr.id) FROM eshop.refund_requests rr WHERE rr.order_id=o.id),
  'requests',public.customer_order_change_requests_internal(o.id),
  'definitions',(SELECT jsonb_agg(to_jsonb(definition) ORDER BY definition.id) FROM public.form_fields definition WHERE definition.form=o.form),
  'allocations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM eshop.order_product_ticket x WHERE x."order"=o.id),
  'tickets',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.get_order_tickets_internal(o.id) t),'target',target);
 RETURN jsonb_build_object('code',200,'operation',p_operation,'effect',effect,'reason',blocked,'refundAmount',CASE WHEN effect='cancel_refund' THEN amount ELSE 0 END,
  'partial',partial,'ticketIds',to_jsonb(selected),'currency',o.currency_code,'target',target,'policyRevision',rev,'expiresAt',statement_timestamp()+interval '5 minutes',
  'fingerprint',encode(extensions.digest(snapshot::text,'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.preview_customer_order_change_internal(bigint,text,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_orders/storno_tickets_bulk.sql
CREATE OR REPLACE FUNCTION public.cancel_ticket_selection_domain_internal(p_ticket_ids BIGINT[], p_send_email BOOLEAN DEFAULT TRUE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    v_order_id BIGINT;
    v_occasion_id BIGINT;
    v_tickets_in_order BIGINT[];
    v_tickets_to_cancel_in_order BIGINT[];
    v_remaining_count INT;
    v_ticket_id_to_remove BIGINT;
    v_original_data JSONB;
    v_updated_tickets_json JSONB;
    v_ticket_elem JSONB;
    v_product_elem JSONB;
    v_removed_price NUMERIC(10, 2);
    v_current_price NUMERIC(10, 2);
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(p_ticket_ids)));
    PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(p_ticket_ids)));
    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_ticket_ids)));
    -- 1. Identify all unique orders involved in this batch AND their occasion
    -- We need the occasion ID to perform the security check
    FOR v_order_id, v_occasion_id IN
        SELECT DISTINCT o.id, o.occasion
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE t.id = ANY(p_ticket_ids)
        ORDER BY o.id
    LOOP
        -- Repeated selected tickets in an otherwise active order are a no-op.
        IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
          WHERE opt."order"=v_order_id AND t.id=ANY(p_ticket_ids) AND t.state IS DISTINCT FROM 'storno') THEN
          CONTINUE;
        END IF;
        PERFORM public.check_order_is_mutable(v_order_id);
        IF EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=v_order_id AND public.payment_method_is_online_internal(pi.payment_method)) THEN
            RAISE EXCEPTION 'STRIPE_USE_REFUND_ADMISSION_DECISION'; END IF;

        -- Serialize cancellations on the same order before counting survivors.
        PERFORM 1 FROM eshop.orders WHERE id = v_order_id FOR UPDATE;

        -- 3. Get all active tickets currently in this order
        SELECT ARRAY_AGG(t.id)
        INTO v_tickets_in_order
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        WHERE opt."order" = v_order_id
        AND (t.state IS NULL OR t.state != 'storno');

        -- 4. Get intersection: Tickets in this order that we want to cancel
        SELECT ARRAY_AGG(id)
        INTO v_tickets_to_cancel_in_order
        FROM UNNEST(v_tickets_in_order) AS id
        WHERE id = ANY(p_ticket_ids);

        -- A replay or a selection containing only cancelled tickets has no effect.
        IF coalesce(cardinality(v_tickets_to_cancel_in_order), 0) = 0 THEN
            CONTINUE;
        END IF;

        -- 5. Calculate how many would remain
        v_remaining_count := array_length(v_tickets_in_order, 1) - array_length(v_tickets_to_cancel_in_order, 1);

        -- -----------------------------------------------------
        -- SCENARIO A: Full Order Cancellation
        -- -----------------------------------------------------
        IF v_remaining_count <= 0 THEN
            -- Helper function to cancel the entire order
            PERFORM public.cancel_order_domain_internal_v1(v_order_id,p_send_email);

        -- -----------------------------------------------------
        -- SCENARIO B: Partial Cancellation (Modify Order)
        -- -----------------------------------------------------
        ELSE
            -- 1. Mark specific tickets as storno in DB
            PERFORM internal_storno_tickets_221(v_tickets_to_cancel_in_order);

            -- 2. Fetch Order Data
            SELECT data, price INTO v_original_data, v_current_price
            FROM eshop.orders WHERE id = v_order_id;

            v_updated_tickets_json := '[]'::JSONB;
            v_removed_price := 0;

            -- 3. Rebuild JSON data, filtering out cancelled tickets and summing price to remove
            FOR v_ticket_elem IN SELECT * FROM jsonb_array_elements(v_original_data->'tickets')
            LOOP
                v_ticket_id_to_remove := (v_ticket_elem->>'id')::BIGINT;

                -- If this ticket is one of the ones being cancelled
                IF v_ticket_id_to_remove = ANY(v_tickets_to_cancel_in_order) THEN
                    -- Sum up price to deduct
                    FOR v_product_elem IN SELECT * FROM jsonb_array_elements(v_ticket_elem->'products')
                    LOOP
                        v_removed_price := v_removed_price + COALESCE((v_product_elem->>'price')::NUMERIC, 0);
                    END LOOP;
                ELSE
                    -- Keep this ticket in the new JSON
                    v_updated_tickets_json := v_updated_tickets_json || v_ticket_elem;
                END IF;
            END LOOP;

            -- Fence unsent snapshots of the previous ticket set, and keep the
            -- payment amount aligned with the new order total.
            PERFORM public.cancel_order_email_intents(v_order_id);
            UPDATE eshop.payment_info SET amount=GREATEST(0, COALESCE(v_current_price,0)-v_removed_price)
            WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=v_order_id);

            -- 4. Update Order (Data & Price)
            UPDATE eshop.orders
            SET
                data = v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                price = GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                email_payment_version = email_payment_version + 1,
                updated_at = NOW()
            WHERE id = v_order_id;

            -- Refresh only this order's existing reminder schedule for its new amount.
            PERFORM public.set_payment_deadline(pi.id,pi.deadline)
            FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
            WHERE o.id=v_order_id AND o.state='ordered' AND pi.deadline IS NOT NULL;

            -- Existing delivery policy prepares the surviving tickets if their
            -- paid order has not finished sending yet; sent orders stay untouched.
            PERFORM public.enqueue_paid_order_tickets(v_order_id);

            -- 5. Insert ONE history record for this modification
            INSERT INTO eshop.orders_history (
                "order",
                data,
                state,
                price,
                created_at
            )
            VALUES (
                v_order_id,
                v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                (SELECT state FROM eshop.orders WHERE id=v_order_id),
                GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                NOW()
            );
        END IF;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_ticket_selection_domain_internal(bigint[],boolean) FROM PUBLIC, anon, authenticated,service_role;

CREATE OR REPLACE FUNCTION public.storno_tickets_bulk_internal_v1(p_ticket_ids bigint[],p_send_email boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(p_ticket_ids)));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_ticket_ids)));
 IF EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
   WHERE x.ticket=ANY(p_ticket_ids) AND public.can_write_orders(o.occasion) IS NOT TRUE) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.cancel_ticket_selection_domain_internal(p_ticket_ids,p_send_email);
END $$;
REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[],boolean) FROM PUBLIC,anon,authenticated;

-- SOURCE: customer_order_changes/commands.sql
CREATE OR REPLACE FUNCTION public.lock_customer_order_change_internal(p_order bigint,p_target bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; fid bigint;
BEGIN
 SELECT occasion,form INTO oc.id,fid FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=oc.id;
 PERFORM public.payment_policy_fence_internal(oc.organization);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[oc.id]);
 PERFORM 1 FROM public.forms WHERE id IN(fid,p_target) AND occasion=oc.id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.orders WHERE id=p_order FOR UPDATE;
 -- Form saves take this same occasion fence before their product locks.
 PERFORM 1 FROM eshop.products WHERE occasion=oc.id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=p_order) FOR UPDATE;
 PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT id FROM public.get_order_tickets_internal(p_order)) ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_customer_order_change_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.publish_customer_order_request_internal(p_request uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r eshop.customer_order_change_requests; oc public.occasions;
BEGIN
 SELECT * INTO STRICT r FROM eshop.customer_order_change_requests WHERE id=p_request;
 SELECT occ.* INTO STRICT oc FROM public.occasions occ JOIN eshop.orders o ON o.occasion=occ.id WHERE o.id=r.order_id;
 -- Request reasons/answers never enter notification payloads or technical audit.
 PERFORM public.notification_center_order_internal(r.order_id,'customer_order_request','customer-request:'||r.id||':'||r.status,
  NULL,jsonb_build_object('customerRequestId',r.id,'customerRequestOperation',r.operation,'customerRequestStatus',r.status));
END $$;
REVOKE ALL ON FUNCTION public.publish_customer_order_request_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.apply_customer_order_change_internal(p_order bigint,p_operation text,p_payload jsonb,p_preview jsonb,p_command uuid,p_existing_request uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; effect text:=p_preview->>'effect'; request_id uuid:=p_existing_request;
 item record; t eshop.tickets; merged jsonb; fields jsonb; result jsonb; request_status text:='open';
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 IF effect='edit' THEN
  IF coalesce(p_payload->'order','{}')<>'{}'::jsonb THEN PERFORM public.update_order_responses_domain_internal(o.id,p_payload->'order'); END IF;
  FOR item IN SELECT * FROM jsonb_each(coalesce(p_payload->'tickets','{}')) LOOP
   SELECT * INTO STRICT t FROM eshop.tickets WHERE id=item.key::bigint FOR UPDATE;
   SELECT coalesce(jsonb_object_agg(a.key,a.value),'{}') INTO merged FROM jsonb_array_elements(coalesce(t.data->'fields','[]')) f CROSS JOIN LATERAL jsonb_each(f) a;
   SELECT coalesce(jsonb_agg(jsonb_build_object(key,value) ORDER BY key),'[]') INTO fields FROM jsonb_each(merged||item.value);
   UPDATE eshop.tickets SET data=jsonb_set(coalesce(t.data,'{}'),'{fields}',fields) WHERE id=t.id;
  END LOOP;
  IF coalesce(p_payload->'tickets','{}')<>'{}'::jsonb THEN
   UPDATE eshop.orders ord SET data=jsonb_set(ord.data,'{tickets}',(SELECT coalesce(jsonb_agg(
    CASE WHEN p_payload->'tickets' ? (snapshot->>'id') THEN jsonb_set(snapshot,'{fields}',(SELECT data->'fields' FROM eshop.tickets WHERE id=(snapshot->>'id')::bigint)) ELSE snapshot END),'[]')
    FROM jsonb_array_elements(coalesce(ord.data->'tickets','[]')) snapshot)),updated_at=clock_timestamp() WHERE ord.id=o.id;
   INSERT INTO eshop.orders_history("order",state,price,data,currency_code) SELECT id,state,price,data,currency_code FROM eshop.orders WHERE id=o.id;
  END IF;
  -- Materialized ticket documents and Wallet share the existing delivery owner.
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);
  PERFORM public.enqueue_order_wallet_internal(o.id);
  IF o.state IN ('paid','sent') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
 ELSIF effect IN ('request_cancel','request_move','cancel_manual_refund') OR (p_operation IN ('cancel','move') AND nullif(btrim(p_payload->>'reason'),'') IS NOT NULL) THEN
  IF effect IN ('cancel_manual_refund','cancel_refund') THEN request_status:='approved'; ELSIF effect IN ('cancel','move') THEN request_status:='resolved'; END IF;
  IF p_existing_request IS NULL THEN
  INSERT INTO eshop.customer_order_change_requests(order_id,organization_id,operation,reason,target_form_id,customer_command,status,ticket_ids)
  VALUES(o.id,oc.organization,p_operation,nullif(btrim(p_payload->>'reason'),''),nullif(p_payload->>'targetFormId','')::bigint,p_command,request_status,CASE WHEN p_payload ? 'ticketIds' THEN ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_payload->'ticketIds')) END)
  ON CONFLICT(order_id,operation) WHERE status='open' DO NOTHING RETURNING id INTO request_id;
  IF request_id IS NULL THEN SELECT id INTO request_id FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=p_operation AND status='open'; END IF;
  PERFORM public.publish_customer_order_request_internal(request_id);
  END IF;
 END IF;
 IF effect IN ('cancel','cancel_refund','cancel_manual_refund') THEN
  IF effect='cancel_refund' THEN
   PERFORM public.prepare_order_refund_internal(o.id,(SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info),
    (p_preview->>'refundAmount')::numeric,p_command,'{}');
   INSERT INTO eshop.payment_operation_events(request_id,operation,actor,details) VALUES(p_command,'prepare_refund',auth.uid(),jsonb_build_object('source','customer_order_change','commandId',p_command));
  END IF;
  IF p_preview->'partial'='true'::jsonb THEN
   PERFORM public.cancel_ticket_selection_domain_internal(ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_preview->'ticketIds')),true);
  ELSIF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=o.payment_info AND public.payment_method_is_online_internal(payment_method)) THEN
   PERFORM public.cancel_online_order_admission_internal(o.id,'storno');
   INSERT INTO eshop.orders_history("order",state,price,data,currency_code) SELECT id,state,price,data,currency_code FROM eshop.orders WHERE id=o.id;
   PERFORM public.notification_center_order_state_internal(o.id);
   PERFORM public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit);
  ELSE PERFORM public.cancel_order_domain_internal_v1(o.id,true); END IF;
  PERFORM public.enqueue_order_wallet_internal(o.id);
 ELSIF effect='move' THEN
  PERFORM public.move_customer_order_domain_internal(o.id,(p_payload->>'targetFormId')::bigint);
 ELSIF effect='withdraw' THEN
  UPDATE eshop.customer_order_change_requests SET status='withdrawn',updated_at=clock_timestamp()
   WHERE id=(p_payload->>'requestId')::uuid AND order_id=o.id AND status='open' RETURNING id INTO request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 END IF;
 IF (effect IN ('edit','move','request_cancel','request_move','withdraw') OR p_preview->'partial'='true'::jsonb) AND (SELECT state FROM eshop.orders WHERE id=o.id)<>'storno' THEN
  PERFORM public.enqueue_order_email('TICKET_ORDER_UPDATE',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit,now(),'customer-change:'||p_command);
 END IF;
 INSERT INTO eshop.customer_order_change_events(command_id,order_id,operation,outcome,request_id)
 VALUES(p_command,o.id,p_operation,effect,request_id);
 RETURN jsonb_build_object('code',200,'effect',effect,'requestId',request_id,'orderId',o.id);
END $$;
REVOKE ALL ON FUNCTION public.apply_customer_order_change_internal(bigint,text,jsonb,jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;


CREATE OR REPLACE FUNCTION public.customer_order_change_gateway(p_action text,p_token text,p_order bigint DEFAULT NULL,
 p_operation text DEFAULT NULL,p_payload jsonb DEFAULT '{}',p_command uuid DEFAULT NULL,p_fingerprint text DEFAULT NULL,
 p_delivery jsonb DEFAULT NULL,p_ip_hash text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE parent eshop.waitlist_capabilities; cap eshop.customer_order_change_capabilities;
 o eshop.orders; oc public.occasions; preview jsonb; limits eshop.customer_order_change_limits; receipt jsonb; result jsonb; users uuid[];
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_action IS NULL OR p_action NOT IN ('challenge_context','challenge','resolve','preview','command') THEN RAISE invalid_parameter_value; END IF;
 IF p_action IN ('challenge_context','challenge') THEN
  parent:=public.customer_change_read_scope_internal(p_token,p_order);
  PERFORM public.lock_customer_order_change_internal(parent.order_id,nullif(p_payload->>'targetFormId','')::bigint);
  parent:=public.customer_change_read_scope_internal(p_token,p_order);
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=parent.order_id;
  SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
  preview:=public.preview_customer_order_change_internal(o.id,p_operation,p_payload);
  IF p_action='challenge' THEN
   IF p_ip_hash IS NULL OR p_ip_hash!~'^[a-f0-9]{64}$' OR p_delivery->>'tokenHash' IS NULL OR p_delivery->>'tokenHash'!~'^[a-f0-9]{64}$'
    OR jsonb_typeof(p_delivery->'source') IS DISTINCT FROM 'object' OR jsonb_typeof(p_delivery->'email') IS DISTINCT FROM 'object'
    OR p_delivery->>'contentHash' IS NULL OR p_delivery->>'contentHash'!~'^[a-f0-9]{64}$' THEN RAISE invalid_parameter_value; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('customer-change-order:'||o.id,0));
   PERFORM pg_advisory_xact_lock(hashtextextended('customer-change-ip:'||p_ip_hash,0));
   SELECT * INTO STRICT limits FROM eshop.customer_order_change_limits WHERE singleton;
   IF EXISTS(SELECT 1 FROM eshop.customer_order_change_attempts WHERE (order_id=o.id OR ip_hash=p_ip_hash)
     AND created_at>clock_timestamp()-make_interval(secs=>limits.minimum_seconds))
    OR (SELECT count(*) FROM eshop.customer_order_change_attempts WHERE order_id=o.id AND created_at>clock_timestamp()-interval '1 hour')>=limits.hourly_limit
    OR (SELECT count(*) FROM eshop.customer_order_change_attempts WHERE ip_hash=p_ip_hash AND created_at>clock_timestamp()-interval '1 hour')>=limits.hourly_limit THEN
     RETURN jsonb_build_object('code',202); END IF;
   INSERT INTO eshop.customer_order_change_attempts(order_id,ip_hash) VALUES(o.id,p_ip_hash);
   INSERT INTO eshop.customer_order_change_capabilities(token_hash,parent_hash,organization_id,form_id,order_id,operation,proposal_hash,
    policy_revision,feature_epoch,expires_at)
   VALUES(p_delivery->>'tokenHash',parent.token_hash,oc.organization,o.form,o.id,p_operation,
    encode(extensions.digest(p_payload::text,'sha256'),'hex'),(preview->>'policyRevision')::bigint,oc.customer_self_service_epoch,clock_timestamp()+interval '10 minutes') RETURNING * INTO cap;
   INSERT INTO eshop.customer_order_change_sources VALUES(cap.id,p_delivery->'source',p_delivery->>'contentHash');
   PERFORM public.enqueue_prepared_email('custom',jsonb_build_object('organization',oc.organization,'occasion',oc.id,'unit',oc.unit,'tracking_policy','none'),
    o.data->>'email',p_delivery->'email','customer-change:'||cap.id,p_delivery->>'contentHash','CUSTOMER_ORDER_CHANGE',cap.expires_at);
   RETURN jsonb_build_object('code',202);
  END IF;
  RETURN jsonb_build_object('code',200,'orderId',o.id,'recipient',o.data->>'email','organization',oc.organization,'occasion',oc.id,'unit',oc.unit,
   'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=oc.organization),
   'locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=oc.organization),'cs'),'preview',preview);
 END IF;
 -- A customer scope is always recovered from the stored credential, never orderId.
 cap:=public.authorize_customer_change_internal(p_token,p_command);
 IF p_order IS NOT NULL AND p_order<>cap.order_id THEN RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 IF p_action='resolve' THEN
  RETURN jsonb_build_object('code',200,'orderId',cap.order_id,'operation',cap.operation,
    'source',(SELECT sealed FROM eshop.customer_order_change_sources WHERE capability_id=cap.id));
 END IF;
 PERFORM public.lock_customer_order_change_internal(cap.order_id,nullif(p_payload->>'targetFormId','')::bigint);
 cap:=public.authorize_customer_change_internal(p_token,p_command);
 IF p_operation IS DISTINCT FROM cap.operation OR encode(extensions.digest(p_payload::text,'sha256'),'hex') IS DISTINCT FROM cap.proposal_hash THEN
  RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 IF p_action='preview' THEN
  preview:=public.preview_customer_order_change_internal(cap.order_id,cap.operation,p_payload);
  UPDATE eshop.customer_order_change_capabilities SET preview_hash=preview->>'fingerprint',preview_expires_at=(preview->>'expiresAt')::timestamptz WHERE id=cap.id;
  RETURN preview;
 END IF;
 IF p_command IS NULL THEN RAISE invalid_parameter_value; END IF;
 receipt:=public.begin_anonymous_client_mutation_v1(p_command,'orders.customer.'||cap.operation,
  (SELECT occasion FROM eshop.orders WHERE id=cap.order_id),cap.id,encode(extensions.digest(jsonb_build_object('capability',cap.id,'operation',cap.operation,'payload',p_payload,'fingerprint',p_fingerprint)::text,'sha256'),'hex'));
 IF receipt->>'disposition'='replay' THEN RETURN receipt->'response'; END IF;
 preview:=public.preview_customer_order_change_internal(cap.order_id,cap.operation,p_payload);
 IF p_fingerprint IS NULL OR cap.preview_expires_at IS NULL OR cap.preview_expires_at<=clock_timestamp() OR cap.preview_hash IS DISTINCT FROM p_fingerprint OR preview->>'fingerprint' IS DISTINCT FROM p_fingerprint THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 PERFORM public.admit_order_mutation_scope_internal((SELECT occasion FROM eshop.orders WHERE id=cap.order_id),(SELECT count(*) FROM public.get_order_tickets_internal(cap.order_id)),'customer-order:'||cap.order_id);
 SELECT coalesce(array_agg("user"),'{}') INTO users FROM public.occasion_users WHERE occasion=(SELECT occasion FROM eshop.orders WHERE id=cap.order_id);
 result:=public.apply_customer_order_change_internal(cap.order_id,cap.operation,p_payload,preview,p_command);
 UPDATE eshop.customer_order_change_capabilities SET consumed_by=p_command,consumed_form_id=(SELECT form FROM eshop.orders WHERE id=cap.order_id) WHERE id=cap.id;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command,(SELECT occasion FROM eshop.orders WHERE id=cap.order_id),
  'orders.customer.'||cap.operation,jsonb_build_array(jsonb_build_object('entityType','order','entityId',cap.order_id,'operation','update',
  'changedFields',jsonb_build_array(cap.operation))),users,result,'unknown');
END $$;
REVOKE ALL ON FUNCTION public.customer_order_change_gateway(text,text,bigint,text,jsonb,uuid,text,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.customer_order_change_gateway(text,text,bigint,text,jsonb,uuid,text,jsonb,text) TO service_role;

-- SOURCE: customer_order_changes/staff.sql
CREATE OR REPLACE FUNCTION public.command_customer_order_request(p_request uuid,p_action text,p_command uuid,p_expected_at timestamptz,p_response text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r eshop.customer_order_change_requests; o eshop.orders; oc public.occasions; actor uuid:=auth.uid();
 hash text; receipt jsonb; preview jsonb; payload jsonb; result jsonb; users uuid[];
BEGIN
 SELECT * INTO r FROM eshop.customer_order_change_requests WHERE id=p_request;
 SELECT * INTO o FROM eshop.orders WHERE id=r.order_id;
 IF actor IS NULL OR o.id IS NULL OR public.can_write_orders(o.occasion) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='customer request unavailable'; END IF;
 IF p_action IS NULL OR p_action NOT IN ('approve','reject','resolve') OR length(p_response)>2000 THEN RAISE invalid_parameter_value; END IF;
 PERFORM public.lock_customer_order_change_internal(o.id,r.target_form_id);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=o.id;
 SELECT * INTO STRICT r FROM eshop.customer_order_change_requests WHERE id=p_request FOR UPDATE;
 IF public.can_write_orders(o.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 -- Replaying an accepted financial effect also needs today's financial role.
 IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE id=p_command AND order_id=o.id)
  AND public.can_prepare_order_provider_refund(o.id) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('request',p_request,'action',p_action,'expectedAt',p_expected_at,'response',p_response)::text,'sha256'),'hex');
 receipt:=public.begin_client_mutation_v1(p_command,'orders.customer.request.decide',o.occasion,actor,hash);
 IF receipt->>'disposition'='replay' THEN RETURN receipt->'response'; END IF;
 IF r.updated_at IS DISTINCT FROM p_expected_at OR r.status NOT IN ('open','approved') THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 SELECT coalesce(array_agg("user"),'{}') INTO users FROM public.occasion_users WHERE occasion=o.occasion;
 IF p_action='approve' THEN
  IF r.status<>'open' THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
  payload:=CASE WHEN r.operation='move' THEN jsonb_build_object('targetFormId',r.target_form_id,'reason',coalesce(r.reason,'')) ELSE jsonb_build_object('reason',coalesce(r.reason,'')) END;
  IF r.ticket_ids IS NOT NULL THEN payload:=payload||jsonb_build_object('ticketIds',to_jsonb(r.ticket_ids)); END IF;
  preview:=public.preview_customer_order_change_internal(o.id,r.operation,payload,true);
  IF preview->>'effect' IN ('request_cancel','request_move') THEN
   RAISE EXCEPTION 'CUSTOMER_REQUEST_REQUIRES_MANUAL_ACTION' USING ERRCODE='40001'; END IF;
  IF preview->>'effect'='cancel_refund' AND public.can_prepare_order_provider_refund(o.id) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='financial permission required'; END IF;
  result:=public.apply_customer_order_change_internal(o.id,r.operation,payload,preview,p_command,r.id);
  UPDATE eshop.customer_order_change_requests SET status='approved',response=nullif(btrim(p_response),''),
   decided_by=actor,decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 ELSIF p_action='reject' THEN
  IF r.status<>'open' THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
  UPDATE eshop.customer_order_change_requests SET status='rejected',response=nullif(btrim(p_response),''),
   decided_by=actor,decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 ELSE
  IF nullif(btrim(p_response),'') IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='resolution response required'; END IF;
  -- A manual refund obligation cannot be marked paid by a staff click.
  IF r.operation='cancel' AND r.status='approved' AND (coalesce((public.payment_method_context_internal(o.id)->>'net')::numeric,0)>CASE WHEN r.ticket_ids IS NULL THEN 0 ELSE o.price END OR public.payment_method_context_internal(o.id)->'invalidIdentity' IS DISTINCT FROM 'false'::jsonb OR coalesce((public.payment_method_context_internal(o.id)->>'pending')::numeric,0)>0) THEN
   RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRED' USING ERRCODE='40001'; END IF;
  UPDATE eshop.customer_order_change_requests SET status='resolved',response=btrim(p_response),decided_by=actor,
   decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 END IF;
 PERFORM public.publish_customer_order_request_internal(r.id);
 -- Storno owns its confirmation; support decisions use the same existing queue.
 IF (SELECT state FROM eshop.orders WHERE id=o.id)<>'storno' THEN
  PERFORM public.enqueue_order_email('TICKET_ORDER_UPDATE',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit,now(),'customer-request:'||p_command);
 END IF;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command,o.occasion,'orders.customer.request.decide',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','changedFields',jsonb_build_array('customerRequests'))),
  users,jsonb_build_object('code',200,'requestId',r.id));
END $$;
REVOKE ALL ON FUNCTION public.command_customer_order_request(uuid,text,uuid,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.command_customer_order_request(uuid,text,uuid,timestamptz,text) TO authenticated;

-- SOURCE: eshop/materialize_ticket_products_internal_v1.sql
-- Private product materializer. Callers normalize selection, lock capacity/products,
-- and determine ticket identity first. It never creates an order or a ticket.
CREATE OR REPLACE FUNCTION public.materialize_ticket_products_internal_v1(
 order_id bigint,form_id bigint,ticket_id bigint,ticket_data jsonb,spot_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE
 is_editor boolean; occasion_id bigint; spot_data record; spot_product record; spot_id bigint;
 spot_product_id bigint;
 missing_required_product_field bigint;
 ticket_note text; product_id bigint; ordered_count bigint; field_item jsonb;
 products_array bigint[] := '{}'; product_data record; ticket_products jsonb;
 order_product_ticket_id bigint; first_currency_code text; calculated_price numeric := 0;
 v_product_deposit numeric; v_total_deposit numeric := 0; now timestamptz := clock_timestamp();
BEGIN
 SELECT occasion INTO STRICT occasion_id FROM public.forms WHERE id=form_id;
 is_editor:=coalesce(public.can_write_orders(occasion_id),false);
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=order_id AND form=form_id AND occasion=occasion_id)
 OR NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=ticket_id AND occasion=occasion_id AND state='ordered') THEN
  RAISE EXCEPTION 'TICKET_MATERIALIZATION_SCOPE_MISMATCH'; END IF;
            spot_data := NULL;
            spot_product_id := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT s.* INTO spot_data
                FROM eshop.spots s
                JOIN public.forms f ON f.id=form_id AND f.blueprint=s.blueprint AND f.occasion=s.occasion
                JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=f.blueprint
                WHERE s.id = (ticket_data->>'spot')::BIGINT
                  AND s.occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings b WHERE b.spot=spot_data.id AND b.blocked) OR spot_data.product IS NULL THEN
                    RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (spot_secret::text)::UUID;
                IF (NOT coalesce(is_editor,false) AND
                     (spot_secret IS NULL OR spot_data.secret IS NULL
                      OR spot_data.secret IS DISTINCT FROM spot_secret
                      OR spot_data.secret_expiration_time IS NULL
                      OR spot_data.secret_expiration_time <= clock_timestamp()))
                   OR (coalesce(is_editor,false) AND spot_data.secret IS NOT NULL
                       AND spot_data.secret_expiration_time > clock_timestamp()
                       AND spot_data.secret IS DISTINCT FROM spot_secret) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
                spot_product_id := spot_product.id;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product_id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden)
                  AND NOT EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(form_id) offered
                    WHERE offered.product=product_data.id AND offered.has_capacity) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                PERFORM public.assert_admission_seating_internal(form_id,product_id,spot_id);

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product_id IS NULL THEN
                    spot_product := product_data;
                    spot_product_id := product_data.id;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                INSERT INTO eshop.order_product_ticket ("order", product, ticket,base_price,net_price)
                VALUES (order_id, product_id, ticket_id,product_data.price,product_data.price)
                RETURNING id INTO order_product_ticket_id;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product_id IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product_id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'order_product_ticket_id',order_product_ticket_id,
                        'base_price',product_data.price,'discount_amount',0,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product_id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, secret = NULL, secret_expiration_time = NULL, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- Active seat sales still require an actual admission entitlement.
            -- Hiding ticket issuance cannot turn an auxiliary fee into a
            -- seatless admission behind the published/legacy seating plan.
            IF spot_product_id IS NULL AND EXISTS(
                SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
                WHERE f.id=form_id AND f.blueprint IS NOT NULL
                  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
            ) THEN
                RAISE EXCEPTION '%',jsonb_build_object('code',409,
                  'errorCode','ADMISSION_SOURCE_REQUIRES_SEATING')::text;
            END IF;

            PERFORM public.assert_ticket_required_products_internal(form_id,products_array);

 RETURN jsonb_build_object('products',ticket_products,'price',calculated_price,
  'deposit',v_total_deposit,'currency_code',first_currency_code,'spot',spot_id,'note',ticket_note);
END $$;
REVOKE ALL ON FUNCTION public.materialize_ticket_products_internal_v1(bigint,bigint,bigint,jsonb,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_waitlist/order_overview.sql
-- Private pure projection. No matcher, paid transition or payment side effect.
CREATE OR REPLACE FUNCTION public.customer_order_payment_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH facts AS (
 SELECT o.*,public.payment_collection_action_internal(o.id) collection_action,p.payment_method,p.amount,coalesce(p.paid,0) received,coalesce(p.returned,0) returned,
 coalesce(p.paid,0)-coalesce(p.returned,0) net,
 (SELECT coalesce(sum(r.amount),0) FROM eshop.refund_requests r WHERE r.payment_info=p.id AND r.status IN ('pending','processing','unknown')) pending,
 p.data->'payment_policy' payment_policy,p.deposit_amount,p.deposit_deadline,p.deadline,p.variable_symbol,p.creditor_reference,
 b.account_number,b.account_number_human_readable,
 coalesce(nullif(trim(b.creditor_name),''),(SELECT left(trim(regexp_replace(org.title,'[[:space:][:cntrl:]]+',' ','g')),70) FROM public.occasions occ JOIN public.organizations org ON org.id=occ.organization WHERE occ.id=o.occasion)) creditor_name,
 CASE WHEN o.state='preparing_payment' THEN 'preparing'
 WHEN o.state='storno' THEN 'cancelled'
 WHEN o.state='expired' THEN 'expired'
 WHEN o.state='waitlisted' AND p.id IS NULL THEN 'not_required_yet'
 WHEN o.price=0 THEN 'free'
 WHEN p.id IS NULL OR p.currency_code IS DISTINCT FROM o.currency_code OR p.amount IS NULL OR p.amount<0 OR coalesce(p.paid,0)<0 OR coalesce(p.paid_externally,0)<>0
  OR (o.state IN ('paid','sent') AND o.price>0 AND coalesce(p.paid,0)=0) THEN 'unknown'
 WHEN coalesce(p.paid,0)-coalesce(p.returned,0)>=p.amount THEN 'fully_paid'
 WHEN coalesce(p.paid,0)-coalesce(p.returned,0)<=0 THEN 'unpaid'
 WHEN p.deposit_amount>0 AND coalesce(p.paid,0)-coalesce(p.returned,0)>=p.deposit_amount THEN 'deposit_paid'
 ELSE 'partially_paid' END status
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info
 LEFT JOIN eshop.bank_accounts b ON b.id=p.bank_account WHERE o.id=p_order),
 due AS (SELECT *,greatest(amount-net,0) outstanding,
 CASE WHEN deposit_amount>net THEN greatest(deposit_amount-net,0) ELSE greatest(amount-net,0) END due_now,
 CASE WHEN deposit_amount>net THEN deposit_deadline ELSE deadline END due_at FROM facts)
 SELECT CASE WHEN public.payment_method_is_online_internal(payment_method) THEN public.provider_order_payment_projection_internal(p_order)||jsonb_build_object('allowedActions',CASE WHEN collection_action->'allowed'='true'::jsonb THEN public.provider_order_payment_projection_internal(p_order)->'allowedActions' ELSE '["refresh"]'::jsonb END,'net',net,'pending',pending,'totalOutstanding',outstanding,'overpaid',greatest(net-amount,0)) ELSE jsonb_build_object('method',payment_method,'deadlinePolicy',payment_policy->>'mode','instructions',jsonb_build_object('cashInstructions',payment_policy->>'cashInstructions'),'currency',trim(currency_code),'paid',received,'remaining',outstanding,'status',status,'amount',amount,'received',received,'returned',returned,'net',net,'pending',pending,
 'totalOutstanding',outstanding,'overpaid',greatest(net-amount,0),'depositAmount',deposit_amount,
 'depositDeadline',deposit_deadline,'finalDeadline',deadline,
 'dueNow',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN due_now ELSE 0 END,
 'dueAt',due_at,'overdue',coalesce(due_at<statement_timestamp() AND due_now>0,false),
 'instructionsAvailable',collection_action->'allowed'='true'::jsonb AND status IN ('unpaid','partially_paid','deposit_paid') AND (payment_method='cash' OR account_number IS NOT NULL)
  AND (payment_method='cash' OR CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END),
 'reference',CASE WHEN collection_action->'allowed'='true'::jsonb AND status IN ('unpaid','partially_paid','deposit_paid') THEN
  CASE WHEN currency_code='EUR' THEN creditor_reference ELSE variable_symbol::text END END,
 'qrPayment',CASE WHEN collection_action->'allowed'='true'::jsonb AND payment_method='bank' AND status IN ('unpaid','partially_paid','deposit_paid') AND due_now>0 AND account_number IS NOT NULL
  AND CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END
 THEN jsonb_build_object('amount',due_now,'currency_code',trim(currency_code),'account_number',account_number,
  'account_number_human_readable',account_number_human_readable,'creditor_name',creditor_name,
  'variable_symbol',variable_symbol,'creditor_reference',creditor_reference) END,
 'referenceKind',CASE WHEN currency_code='EUR' THEN 'RF' ELSE 'VS' END,
 'transactions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
  'date',t.date::date,'recordedAt',t.created_at,'amount',t.amount,'currency',trim(t.currency),
  'kind',CASE WHEN m.voided THEN 'payment_adjustment_voided' WHEN m.is_refund THEN 'refund' WHEN t.amount>0 THEN 'payment_received' ELSE 'payment_adjustment' END)
  ORDER BY t.created_at NULLS LAST,t.id),'[]') FROM eshop.transactions t JOIN LATERAL public.payment_transaction_movements_internal(due.payment_info) m ON m.transaction_id=t.id WHERE t.payment_info=due.payment_info),
 'publicAccount',CASE WHEN collection_action->'allowed'='true'::jsonb AND payment_method='bank' AND status IN ('unpaid','partially_paid','deposit_paid') THEN coalesce(account_number_human_readable,account_number) END)
 END FROM due;
$$;
REVOKE ALL ON FUNCTION public.customer_order_payment_internal(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.customer_ticket_label_internal(p_ticket bigint,p_form bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT nullif(string_agg(a.value#>>'{}',' ' ORDER BY CASE f.type WHEN 'name' THEN 0 ELSE 1 END,f.id),'')
 FROM eshop.tickets t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t.data->'fields','[]')) field
 CROSS JOIN LATERAL jsonb_each(field) a JOIN public.form_fields f ON f.id::text=a.key
 WHERE t.id=p_ticket AND f.form=p_form AND f.is_ticket_field AND NOT f.is_hidden AND f.type IN ('name','surname');
$$;
REVOKE ALL ON FUNCTION public.customer_ticket_label_internal(bigint,bigint) FROM PUBLIC,anon,authenticated;

-- Customer-visible answers only; field definitions own scope and visibility.
CREATE OR REPLACE FUNCTION public.customer_order_answers_internal(p_form bigint,p_data jsonb,p_ticket boolean)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('title',f.title,'type',f.type,'value',CASE WHEN f.type='id_document' AND jsonb_typeof(answer.value)='object'
  THEN jsonb_strip_nulls(jsonb_build_object('id_document_number',answer.value->'id_document_number',
   'id_document_expiry_date',answer.value->'id_document_expiry_date')) ELSE answer.value END) ORDER BY f."order",f.id),'[]')
 FROM public.form_fields f CROSS JOIN LATERAL (
  SELECT coalesce(a->(f.id::text),a->f.type) value
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'fields')='array' THEN p_data->'fields' ELSE '[]' END) a
  WHERE a ? f.id::text OR (a->>'_subFieldId'=f.id::text AND a ? f.type)
   OR (NOT a ? '_subFieldId' AND a ? f.type
    AND NOT EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k ~ '^[0-9]+$')
    AND 1=(SELECT count(*) FROM public.form_fields other WHERE other.form=p_form AND other.type=f.type AND other.is_ticket_field=p_ticket AND NOT other.is_hidden))
  LIMIT 1
 ) answer
 WHERE f.form=p_form AND f.is_ticket_field=p_ticket AND NOT f.is_hidden
 AND f.type IN ('name','surname','email','phone','city','sex','birth_year','birth_date','address','nationality','id_document','text','note','select_one','select_many')
 AND ((f.type='id_document' AND jsonb_typeof(answer.value)='object'
  AND jsonb_typeof(answer.value->'id_document_number')='string'
  AND (answer.value->'id_document_expiry_date' IS NULL OR jsonb_typeof(answer.value->'id_document_expiry_date') IN ('string','null')))
  OR jsonb_typeof(answer.value) IN ('string','number','boolean') OR (jsonb_typeof(answer.value)='array'
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(answer.value)='array' THEN answer.value ELSE '[]' END) v WHERE jsonb_typeof(v) NOT IN ('string','number','boolean'))));
$$;
REVOKE ALL ON FUNCTION public.customer_order_answers_internal(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_customer_order_overview_internal(p_token text,p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE root eshop.orders; cap eshop.waitlist_capabilities; occ public.occasions; f public.forms;
 ids bigint[]; result jsonb;
BEGIN
 PERFORM set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 SELECT * INTO root FROM eshop.orders WHERE id=p_order_id AND source_waitlist_order_id IS NULL;
 SELECT * INTO occ FROM public.occasions WHERE id=root.occasion;
 SELECT * INTO f FROM public.forms WHERE id=root.form AND occasion=occ.id;
 SELECT * INTO cap FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 AND kind='order_view' AND order_id=root.id AND form_id=f.id AND organization_id=occ.organization
 AND revoked_at IS NULL AND expires_at>statement_timestamp();
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' OR cap.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT array_agg(id) INTO ids FROM eshop.orders WHERE id=root.id OR (source_waitlist_order_id=root.id AND NOT (
  NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=eshop.orders.id)
  AND EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE target_order_id=eshop.orders.id AND source_order_id=root.id AND state='aborted')));
 -- Reject malformed provenance rather than expanding an apparently related scope.
 IF EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(ids) AND (o.form IS DISTINCT FROM f.id OR o.occasion IS DISTINCT FROM occ.id))
 OR EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=ANY(ids)
  AND (t.occasion<>occ.id OR EXISTS(SELECT 1 FROM eshop.order_product_ticket y WHERE y.ticket=t.id AND y."order" IS DISTINCT FROM x."order")))
 OR EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(ids) AND o.source_waitlist_order_id=root.id AND NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  JOIN eshop.order_product_ticket x ON x.ticket=s.ticket_id AND x."order"=o.id
  WHERE w.order_id=root.id AND w.form_id=f.id AND s.form_id=f.id AND s.outcome='accepted' AND s.resulting_order_id=o.id))
 OR EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=ANY(ids) AND x."order"<>root.id AND NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.ticket_id=x.ticket AND s.resulting_order_id=x."order" AND s.outcome='accepted' AND w.order_id=root.id AND w.form_id=f.id))
 THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT jsonb_build_object('code',200,'root',jsonb_build_object('id',root.id,'symbol',root.order_symbol,'createdAt',root.created_at,'state',root.state,'title',occ.title,'formLink',f.link,'communicationTone',public.effective_form_metadata_internal(f.data,(SELECT data FROM public.units WHERE id=occ.unit))->>'communication_tone','hasTickets',public.uses_ticket_terminology_internal(occ.features)),
 'timeline',(SELECT coalesce(jsonb_agg(event ORDER BY happened,sort_key),'[]') FROM (
  SELECT root.created_at happened,'0' sort_key,jsonb_build_object('kind',CASE WHEN root.state='waitlisted' THEN 'waitlist_entered' ELSE 'order_ordered' END,'at',root.created_at,'symbol',root.order_symbol) event
  WHERE root.state='waitlisted' OR NOT EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=root.id AND state='ordered')
  UNION ALL
  SELECT w.created_at,'1'||w.id::text,jsonb_build_object('kind','places_offered','at',w.created_at)
  FROM eshop.waitlist_offers w WHERE w.order_id=root.id AND w.form_id=f.id
  UNION ALL
  SELECT s.updated_at,'2'||s.id::text,jsonb_build_object('kind','offer_'||s.outcome,'at',s.updated_at)
  FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE w.order_id=root.id AND w.form_id=f.id AND s.form_id=f.id AND s.outcome IN ('accepted','declined','cancelled','expired')
  UNION ALL
  SELECT t.created_at,'4'||t.id::text,jsonb_build_object('kind',CASE WHEN m.voided THEN 'payment_adjustment_voided' WHEN m.is_refund THEN 'refund' WHEN t.amount>0 THEN 'payment_received' ELSE 'payment_adjustment' END,
   'at',t.created_at,'timeKind','recorded','amount',t.amount,'currency',trim(t.currency),'symbol',o.order_symbol,
   'paymentMethod',CASE WHEN b.type='CASH' THEN 'cash' WHEN nullif(trim(b.account_number),'') IS NOT NULL THEN 'bank' END,
   'recipientAccount',CASE WHEN b.type<>'CASH' THEN coalesce(nullif(trim(b.account_number_human_readable),''),nullif(trim(b.account_number),'')) END)
  FROM eshop.orders o JOIN eshop.transactions t ON t.payment_info=o.payment_info JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id LEFT JOIN eshop.bank_accounts b ON b.id=t.bank_account_id WHERE o.id=ANY(ids) AND t.created_at IS NOT NULL
  UNION ALL
  SELECT h.created_at,'3'||h.id::text,jsonb_build_object(
   'kind',CASE WHEN h.state IS DISTINCT FROM h.previous_state THEN 'order_'||h.state ELSE 'order_changed' END,
   'at',h.created_at,'symbol',h.order_symbol,'previousState',h.previous_state,'state',h.state,
   'previousTotal',CASE WHEN h.price IS DISTINCT FROM h.previous_price AND h.previous_state IS NOT NULL THEN h.previous_price END,
   'total',h.price,'currency',h.currency_code,
   'itemsChanged',h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items,
   'itemsBefore',CASE WHEN h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items THEN h.previous_items END,
   'itemsAfter',CASE WHEN h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items THEN h.items END,
   'detailsChanged',h.previous_state IS NOT NULL AND h.details IS DISTINCT FROM h.previous_details)
  FROM (SELECT snapshots.*,lag(state) OVER w previous_state,lag(price) OVER w previous_price,
   lag(items) OVER w previous_items,lag(details) OVER w previous_details FROM (
    SELECT h.id,h.created_at,h."order",h.state,h.price,coalesce(h.currency_code,o.currency_code) currency_code,o.order_symbol,
     (SELECT coalesce(jsonb_agg(jsonb_build_object('id',p->'id','ticketId',t->'id','ticketSymbol',t->>'ticket_symbol','title',p->>'title','price',p->'price') ORDER BY t->>'id',p->>'id'),'[]')
      FROM jsonb_array_elements(coalesce(h.data->'tickets','[]')) t
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p) items,
     jsonb_build_object('fields',coalesce(h.data->'fields',h.data#>'{input_data,fields}'),'tickets',
      (SELECT jsonb_agg(jsonb_build_object('id',t->'id','fields',t->'fields') ORDER BY t->>'id') FROM jsonb_array_elements(coalesce(h.data->'tickets','[]')) t)) details
    FROM eshop.orders_history h JOIN eshop.orders o ON o.id=h."order" WHERE h."order"=ANY(ids)
      AND h.state IN ('ordered','paid','sent','storno') AND (h.price IS NOT NULL OR h.data ? 'tickets')
   ) snapshots WINDOW w AS (PARTITION BY "order" ORDER BY created_at,id)) h
  WHERE h.state IS DISTINCT FROM h.previous_state OR h.price IS DISTINCT FROM h.previous_price
   OR h.items IS DISTINCT FROM h.previous_items OR h.details IS DISTINCT FROM h.previous_details
 ) events),
 'organizationIdentity',CASE WHEN occ.organization=(SELECT organization FROM public.units WHERE id=occ.unit) THEN public.get_verified_unit_identity_internal(occ.unit) END,
 'allowedActions',public.customer_order_actions_internal(root.id),'changeRequests',public.customer_order_change_requests_internal(root.id),
 'serverTime',statement_timestamp(),'accessExpiresAt',cap.expires_at,'actions',jsonb_build_array('refresh'),
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),'symbol',t.ticket_symbol,
  'answers',public.customer_order_answers_internal(f.id,t.data,true),'effectiveLifecycle',CASE WHEN (SELECT state FROM eshop.orders WHERE id=x."order")='preparing_payment' THEN 'preparing' ELSE public.get_effective_waitlist_ticket_lifecycle_internal(t.id) END,'currentOrderId',x."order") ORDER BY t.id),'[]')
  FROM (SELECT DISTINCT "order",ticket FROM eshop.order_product_ticket WHERE "order"=ANY(ids)) x JOIN eshop.tickets t ON t.id=x.ticket),
 'offers',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'expiresAt',w.expires_at,
  'pendingPlaces',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending' AND w.expires_at>statement_timestamp()),
  'effectiveStatus',CASE WHEN w.expires_at<=statement_timestamp() THEN 'expired'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending') THEN 'pending'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome IN ('declined','cancelled')) THEN 'cancelled' ELSE 'accepted' END)
  ORDER BY w.created_at,w.id),'[]') FROM eshop.waitlist_offers w WHERE w.order_id=root.id AND w.form_id=f.id),
 'orders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'symbol',o.order_symbol,'state',o.state,'total',o.price,'currency',o.currency_code,
  'discount',o.data->'discount',
  'payment',public.customer_order_payment_internal(o.id),
  'answers',public.customer_order_answers_internal(f.id,o.data,false),
  'ticketIds',(SELECT coalesce(jsonb_agg(t.id ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t),
  'items',CASE WHEN o.state='preparing_payment' THEN '[]'::jsonb ELSE (SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ticketId',t->'id','id',p->'id','title',p->>'title','spotTitle',p->>'spot_title','spotGroupTitle',p->>'spot_group_title','isStanding',coalesce((p->>'is_standing')::boolean,false),'standingAreaTitle',p->>'standing_area_title','price',p->'price','basePrice',p->'base_price','discountAmount',p->'discount_amount','currency',p->>'currency_code') ORDER BY (t->>'id')::bigint,
    (SELECT min(coalesce(ff."order",0)) FROM public.form_fields ff WHERE ff.form=f.id AND ff.product_type=product.product_type) NULLS LAST,
    coalesce(product."order",0),product.id),'[]')
   FROM jsonb_array_elements(public.order_tickets_with_seating_internal(o.id,o.data->'tickets')) t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p
   JOIN eshop.products product ON product.id=(p->>'id')::bigint
   WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint)) END,
  'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),'rawState',t.state,
   'displayStatus',CASE t.state WHEN 'ordered' THEN 'awaiting_payment' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END,
   'usageStatus',CASE t.state WHEN 'ordered' THEN 'unused' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END) ORDER BY t.id),'[]')
   FROM public.get_order_tickets_internal(o.id) t)) ORDER BY o.id),'[]')
  FROM eshop.orders o WHERE o.id=ANY(ids) AND o.state IS DISTINCT FROM 'waitlisted')) INTO result;
 RETURN result;
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;
REVOKE ALL ON FUNCTION public.get_customer_order_overview_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_customer_order_overview(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; p record;
BEGIN
 result:=public.get_customer_order_overview_internal(input_data->>'token',(input_data->>'order_id')::bigint);
 IF result->>'code'='200' THEN
  FOR p IN SELECT pi.data->'payment_policy' policy,pi.payment_method method FROM eshop.orders o
   JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id IN(SELECT (x->>'id')::bigint FROM jsonb_array_elements(result->'orders') x) LOOP
   PERFORM public.check_payment_client_capabilities_internal(p.policy,p.method,input_data->'client_capabilities');
  END LOOP;
 END IF;
 RETURN result;
EXCEPTION WHEN raise_exception THEN
 IF left(SQLERRM,1)='{' THEN RETURN SQLERRM::jsonb; END IF; RAISE;
END $$;
CREATE OR REPLACE FUNCTION public.get_customer_order_overview(p_token text,p_order_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_customer_order_overview(jsonb_build_object('token',p_token,'order_id',p_order_id));
$$;
REVOKE ALL ON FUNCTION public.get_customer_order_overview(jsonb),public.get_customer_order_overview(text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_customer_order_overview(jsonb),public.get_customer_order_overview(text,bigint) TO anon,authenticated,service_role;

-- SOURCE: eshop_orders/get_order_admin_detail.sql
-- Exact-order read projection. This fingerprint is a read consistency token,
-- never authorization or a command fence. No registry, trigger, locks or writes.
CREATE OR REPLACE FUNCTION public.order_admin_places_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH own AS (
  SELECT x.id item_id,x.ticket,x.product,o.occasion,o.form,o.state order_state,t.state ticket_state,
   count(*) FILTER (WHERE pt.type='spot') OVER(PARTITION BY x.ticket) primary_count,
   pt.type product_type
  FROM eshop.orders o JOIN eshop.order_product_ticket x ON x."order"=o.id
  JOIN eshop.tickets t ON t.id=x.ticket AND t.occasion=o.occasion
  JOIN eshop.products p ON p.id=x.product AND p.occasion=o.occasion
  JOIN eshop.product_types pt ON pt.id=p.product_type WHERE o.id=p_order
 ), places AS (
 SELECT x.*,s.id spot_id,coalesce(s.blueprint,ab.blueprint) blueprint_id,
 coalesce(sb.node_id,ab.node_id) node_id,sb.group_node,sb.selection_unit,
 s.title,coalesce(sb.blocked,false) blocked,ab.node_id IS NOT NULL standing,
 (SELECT count(*) FROM eshop.spots sp WHERE sp.order_product_ticket=x.item_id AND sp.blueprint IS NOT NULL) addressed_count,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket other WHERE other.ticket=x.ticket AND other."order"<>p_order) foreign_order,
 b.layout,
 EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=coalesce(sb.node_id,ab.node_id)::text) has_node,
 (SELECT n->>'label' FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=sb.group_node::text) group_title,
 (SELECT n->>'label' FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=coalesce(sb.node_id,ab.node_id)::text) node_title
 FROM own x JOIN eshop.spots s ON s.order_product_ticket=x.item_id AND s.occasion=x.occasion
 LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=s.blueprint
 LEFT JOIN public.forms f ON f.id=x.form AND f.occasion=x.occasion
 LEFT JOIN eshop.blueprint_area_bindings ab ON s.blueprint IS NULL AND ab.inventory_context=s.inventory_context AND ab.product=x.product
   AND ab.blueprint=coalesce(f.blueprint,(SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
     JOIN eshop.blueprints target ON target.id=candidate.blueprint WHERE candidate.inventory_context=s.inventory_context
       AND candidate.product=x.product AND target.occasion=x.occasion HAVING count(DISTINCT candidate.blueprint)=1))
 LEFT JOIN eshop.blueprints b ON b.id=coalesce(s.blueprint,ab.blueprint) AND b.occasion=x.occasion
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'spotId',spot_id,'ticketId',ticket,'admissionItemId',item_id,'productId',product,
  'blueprintId',blueprint_id,'nodeId',node_id,'groupNodeId',group_node,'selectionUnitId',selection_unit,
  'title',coalesce(node_title,title),'groupTitle',group_title,'standing',standing,
  'active',ticket_state NOT IN ('storno','waitlisted') AND order_state NOT IN ('storno','stock','waitlisted')
    AND primary_count=1 AND NOT foreign_order AND NOT blocked AND (standing OR addressed_count=1) AND has_node,
  'problem',CASE WHEN primary_count<>1 OR foreign_order OR addressed_count>1 THEN 'ADMISSION_DATA_AMBIGUOUS'
    WHEN ticket_state='storno' OR order_state='storno' THEN 'HISTORICAL'
    WHEN NOT has_node THEN 'PLACE_NOT_IN_CURRENT_PLAN' WHEN blocked THEN 'BLOCKED' END
 ) ORDER BY item_id,spot_id,node_id),'[]') FROM places;
$$;
REVOKE ALL ON FUNCTION public.order_admin_places_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One canonical placement snapshot/fingerprint. The plan reader must not rebuild
-- payment, form, or email projections just to validate its read consistency token.
CREATE OR REPLACE FUNCTION public.order_admin_placement_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; places jsonb; tickets jsonb; plans jsonb; tr bigint;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL THEN RETURN NULL; END IF;
 places:=public.order_admin_places_internal(o.id);
 SELECT min(b.id) INTO tr FROM eshop.blueprints b CROSS JOIN LATERAL public.blueprint_seating_sources_internal(b.id) source WHERE b.occasion=o.occasion AND source.form_id=o.form HAVING count(*)=1;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'ticket_symbol',t.ticket_symbol,'state',t.state,
  'note',t.note,'note_hidden',t.note_hidden,'data',t.data,
  'snapshot',coalesce((SELECT v FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) v WHERE v->>'id'=t.id::text),
    (SELECT v FROM eshop.orders_history h CROSS JOIN LATERAL jsonb_array_elements(coalesce(h.data->'tickets','[]')) v
     WHERE h."order"=o.id AND v->>'id'=t.id::text ORDER BY h.created_at DESC,h.id DESC LIMIT 1)),
  'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'productId',x.product) ORDER BY x.id),'[]') FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=t.id),
  'admission',CASE WHEN tr IS NOT NULL THEN (SELECT jsonb_build_object('category',a.category,'reason',a.reason) FROM public.seating_admissions_internal(tr) a WHERE a.order_id=o.id AND a.ticket_id=t.id) END,
  'batch',(SELECT jsonb_build_object('id',i.batch_id,'title',b.title,'ordinal',i.ordinal) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=t.id)
 ) ORDER BY t.id),'[]') INTO tickets FROM eshop.tickets t
 WHERE t.occasion=o.occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=o.id);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,'layoutRevision',b.layout_revision) ORDER BY b.id),'[]') INTO plans
 FROM eshop.blueprints b WHERE b.occasion=o.occasion AND EXISTS(SELECT 1 FROM jsonb_array_elements(places) v WHERE v->>'blueprintId'=b.id::text);
 RETURN jsonb_build_object('places',places,'tickets',tickets,'plans',plans,'placementFingerprint',md5(jsonb_build_object('order',o.id,'state',o.state,'form',o.form,'transition',tr,'places',places,'tickets',tickets)::text));
END $$;
REVOKE ALL ON FUNCTION public.order_admin_placement_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_order_admin_detail(p_order bigint,p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; places jsonb; tickets jsonb; plans jsonb; actions jsonb; placement jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL OR o.occasion IS DISTINCT FROM p_occasion OR public.can_read_orders(o.occasion) IS NOT TRUE THEN
  RETURN jsonb_build_object('code',404,'message','Order unavailable'); END IF;
 placement:=public.order_admin_placement_internal(o.id);
 places:=placement->'places';tickets:=placement->'tickets';plans:=placement->'plans';
 actions:=public.get_order_allowed_actions_internal_v1(o.id);
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
  'order',jsonb_build_object('id',o.id,'occasion',o.occasion,'form_id',o.form,'order_symbol',o.order_symbol,'order_sequence',o.order_sequence,
   'created_at',o.created_at,'updated_at',o.updated_at,'state',o.state,'price',o.price,'currency_code',o.currency_code,
   'data',o.data,'note_hidden',o.note_hidden,'allowedActions',actions,'email_payment_version',o.email_payment_version,
   'email_payment_fingerprint',public.order_email_payment_fingerprint(o.id),
   'payment_method',(SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info)),
  'capabilities',jsonb_build_object('write',coalesce(public.can_write_orders(o.occasion),false),'allowedActions',actions),
  'payment',public.customer_order_payment_internal(o.id)-'transactions',
  'paymentOperations',public.payment_method_context_internal(o.id),
  'customerRequests',public.customer_order_change_requests_internal(o.id,public.can_write_orders(o.occasion)),
  -- Authorized admin metadata stays readable after payment. Never issue or
  -- regenerate instructions as a side effect of viewing an order.
  'bankPaymentDetails',(SELECT jsonb_build_object(
    'account',coalesce(b.account_number_human_readable,b.account_number),
    'iban',b.account_number,'creditorName',b.creditor_name,
    'referenceKind',CASE WHEN o.currency_code='EUR' THEN 'RF' ELSE 'VS' END,
    'reference',CASE WHEN o.currency_code='EUR' THEN pi.creditor_reference ELSE pi.variable_symbol::text END)
    FROM eshop.payment_info pi JOIN eshop.bank_accounts b ON b.id=pi.bank_account
    WHERE pi.id=o.payment_info AND pi.payment_method='bank'
      AND pi.currency_code=o.currency_code),
  'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL THEN public.get_waitlist_summary_internal(o.id) END,
  'tickets',tickets,'places',places,'placesComplete',true,'plans',plans,
  'placementFingerprint',placement->>'placementFingerprint',
  'form',(SELECT jsonb_build_object('id',f.id,'title',f.title) FROM public.forms f WHERE f.id=o.form AND f.occasion=o.occasion),
  'fields',(SELECT coalesce(jsonb_agg(to_jsonb(ff)||jsonb_build_object('product_type_data',
    CASE WHEN pt.id IS NOT NULL THEN jsonb_build_object('id',pt.id,'title',pt.title,'description',pt.description,'type',pt.type) END)
    ORDER BY ff."order",ff.id),'[]') FROM public.form_fields ff
    LEFT JOIN eshop.product_types pt ON pt.id=ff.product_type AND pt.occasion=o.occasion WHERE ff.form=o.form),
  'productCategories',(SELECT coalesce(jsonb_object_agg(p.id::text,p.product_type),'{}') FROM eshop.products p
    WHERE p.occasion=o.occasion AND EXISTS(SELECT 1 FROM jsonb_array_elements(tickets) t
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(t#>'{snapshot,products}','[]')) pr WHERE pr->>'id'=p.id::text)),
  'answers',coalesce(o.data->'fields','[]'),
  'emailSummary',public.get_order_email_summary(o.id)
 ));
END $$;
REVOKE ALL ON FUNCTION public.get_order_admin_detail(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_admin_detail(bigint,bigint) TO authenticated;

-- SOURCE: notification_center/shared.sql
-- Shared notification classification, DTO and receipt grouping.
-- Serving adapters own scopes; these owners retain domain policy and history.
CREATE OR REPLACE FUNCTION public.notification_center_order_activity_internal(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_kind IN ('customer_order_request','order_created','order_cancelled','order_payment_received','payment_problem','waitlist_registered','offer_accepted','offer_declined','offer_expired');
$$;

CREATE OR REPLACE FUNCTION public.notification_center_batch_internal(
 e public.notification_center_events,d public.notification_center_deliveries)
RETURNS TABLE(batch_id text,is_read boolean,after_sequence bigint,through_sequence bigint,group_key text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH state AS (
  SELECT coalesce((SELECT read_through_sequence FROM public.notification_center_user_state
   WHERE organization=d.organization AND recipient=d.recipient),0) baseline,
   CASE WHEN e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem','payment_problem','provider_problem')
    THEN 'occasion-kind:'||e.occasion||':'||e.kind ELSE 'event:'||e.id END key),
 receipt AS (
  SELECT b.* FROM public.notification_center_read_batches b,state s
  WHERE b.organization=d.organization AND b.recipient=d.recipient AND b.group_key=s.key
   AND d.sequence>b.after_sequence AND d.sequence<=b.through_sequence
  ORDER BY b.through_sequence,b.read_at,b.id LIMIT 1),
 bounds AS (
  SELECT s.*,greatest(s.baseline,coalesce((SELECT max(b.through_sequence)
   FROM public.notification_center_read_batches b WHERE b.organization=d.organization
    AND b.recipient=d.recipient AND b.group_key=s.key),0)) last_read,
   e.actor=d.recipient AND e.kind IN ('order_created','order_cancelled') own_action FROM state s)
 SELECT CASE WHEN coalesce(s.own_action,false) THEN s.key||':self'
   WHEN d.sequence<=s.baseline THEN s.key||':legacy'
   WHEN r.id IS NOT NULL THEN s.key||':batch:'||r.after_sequence
   ELSE s.key||':batch:'||s.last_read END,
  coalesce(s.own_action,false) OR d.sequence<=s.baseline OR r.id IS NOT NULL,
  CASE WHEN coalesce(s.own_action,false) OR d.sequence<=s.baseline THEN 0
   WHEN r.id IS NOT NULL THEN r.after_sequence ELSE s.last_read END,
  CASE WHEN coalesce(s.own_action,false) THEN d.sequence WHEN d.sequence<=s.baseline THEN s.baseline
   WHEN r.id IS NOT NULL THEN r.through_sequence ELSE d.sequence END,s.key
 FROM bounds s LEFT JOIN receipt r ON true;
$$;
REVOKE ALL ON FUNCTION public.notification_center_batch_internal(public.notification_center_events,public.notification_center_deliveries) FROM PUBLIC,anon,authenticated,service_role;


-- Immutable source contributions are shared by serving and delivery adapters.
-- Only historical events missing a field consult the original domain owner.
CREATE OR REPLACE FUNCTION public.notification_center_event_facts_internal(e public.notification_center_events)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE places bigint; context jsonb; legacy_form bigint;
BEGIN
 places:=CASE WHEN e.data->>'count' ~ '^[0-9]{1,9}$' THEN nullif((e.data->>'count')::bigint,0) END;
 context:=nullif(e.data->'formContext','null'::jsonb);
 IF public.notification_center_order_activity_internal(e.kind) AND e.kind NOT IN ('order_payment_received','payment_problem') AND (e.data->>'count' IS NULL OR context IS NULL) THEN
  SELECT o.form INTO legacy_form FROM eshop.orders o
   JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
   WHERE o.occasion=e.occasion AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END;
  IF FOUND THEN
   IF e.data->>'count' IS NULL THEN
    SELECT nullif(count(DISTINCT x.ticket),0) INTO places FROM eshop.order_product_ticket x
     WHERE x."order"=(e.data->>'orderId')::bigint;
   END IF;
   IF context IS NULL THEN context:=public.notification_center_order_form_context_internal(legacy_form); END IF;
  END IF;
 END IF;
 RETURN jsonb_build_object('count',CASE WHEN e.data->>'count' ~ '^[0-9]{1,9}$' THEN (e.data->>'count')::bigint ELSE places END,'formContext',context,
  'allowsMultiple',coalesce(places>1 OR context->'allowsMultiple'='true'::jsonb,false))||
  jsonb_strip_nulls(jsonb_build_object('amount',e.data->'amount','currency',e.data->'currency','receivedAt',e.data->'receivedAt','reason',e.data->'reason','reassigned',e.data->'reassigned'));
END $$;
REVOKE ALL ON FUNCTION public.notification_center_event_facts_internal(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

-- Safe shared metadata, intentionally excluding customer contacts and bank IDs.
CREATE OR REPLACE FUNCTION public.notification_center_event_display_internal(e public.notification_center_events)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('organizationId',e.organization,'organizationTitle',org.title,
  'occasionId',e.occasion,'occasionLink',oc.link,'occasionTitle',oc.title,'webLink',org.data->>'DEFAULT_URL')
 FROM public.organizations org LEFT JOIN public.occasions oc ON oc.id=e.occasion AND oc.organization=org.id WHERE org.id=e.organization;
$$;
REVOKE ALL ON FUNCTION public.notification_center_event_display_internal(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.notification_center_bank_display_internal(e public.notification_center_events,p_recipient uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE payload jsonb:='{}'; account bigint; un bigint; impacts jsonb;
BEGIN
 IF e.kind<>'bank_problem' THEN RETURN payload; END IF;
  SELECT bu.bank_account,u.id INTO account,un FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu
   ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   WHERE c.id=(e.data->>'bankConnectionId')::bigint AND bu."user"=p_recipient AND public.notification_center_bank_admin(bu.bank_account,p_recipient) AND u.organization=e.organization AND EXISTS(SELECT 1 FROM public.unit_users um WHERE um.unit=u.id AND um."user"=p_recipient AND um.is_manager) ORDER BY u.id LIMIT 1;
  IF account IS NOT NULL THEN payload:=payload||jsonb_build_object('bankAccountId',account,'unitId',un); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'link',oc.link)),'[]') INTO impacts
   FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=p_recipient AND ou.is_editor_order_view
   WHERE oc.organization=e.organization AND oc.id=ANY(e.affected_occasions);
  payload:=payload||jsonb_build_object('affectedOccasions',impacts);
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_bank_display_internal(public.notification_center_events,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.notification_center_dto(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=e.data-'bankConnectionId'; customer text; actual_state text; contact jsonb;
BEGIN
 IF NOT public.notification_center_allowed(e,auth.uid()) THEN RETURN NULL; END IF;
 IF e.kind='email_problem' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT payload||jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'recipient',m.recipient,'customerName',coalesce(
    nullif(trim(concat_ws(' ',o.data->>'name',o.data->>'surname')),''),
    nullif(trim(concat_ws(' ',u.name,u.surname)),''))) INTO payload
  FROM public.email_messages m
  LEFT JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
    AND coalesce(public.can_read_orders(o.occasion),false)
    AND EXISTS(SELECT 1 FROM public.occasions oc WHERE oc.id=o.occasion AND oc.organization=m.organization)
  LEFT JOIN public.user_info u ON u.id=m.recipient_user AND u.organization=m.organization
  WHERE m.message_id=(e.data->>'messageId')::uuid AND m.organization=e.organization
    AND m.occasion IS NOT DISTINCT FROM e.occasion;
  payload:=coalesce(payload,e.data-'bankConnectionId');
 END IF;
 IF e.kind='occasion_joined' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT nullif(trim(concat_ws(' ',u.name,u.surname)),'') INTO customer
  FROM public.user_info u JOIN public.occasion_users m ON m."user"=u.id
  WHERE m.occasion=e.occasion AND u.organization=e.organization AND u.id=(e.data->>'userId')::uuid;
  payload:=payload||jsonb_build_object('customerName',customer,'state',CASE WHEN EXISTS(
   SELECT 1 FROM public.occasion_users m WHERE m.occasion=e.occasion AND m."user"=(e.data->>'userId')::uuid) THEN 'membership_active' ELSE 'membership_left' END);
 END IF;
 IF e.data ? 'orderId' AND e.occasion IS NOT NULL AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),o.state
   INTO contact,actual_state
   FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
   WHERE o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion;
  payload:=payload||jsonb_build_object('contact',coalesce(contact,'{}'),'customerName',nullif(trim(concat_ws(' ',contact->>'name',contact->>'surname')),''),'state',coalesce(actual_state,e.data->>'state'));
  IF public.notification_center_order_activity_internal(e.kind) THEN
   payload:=payload||(public.notification_center_event_facts_internal(e)-'allowsMultiple');
  END IF;
 END IF;
 IF e.kind='bank_problem' THEN payload:=payload||public.notification_center_bank_display_internal(e,auth.uid()); END IF;
 RETURN public.notification_center_event_display_internal(e)||jsonb_build_object('id',e.id,'sequence',d.sequence,
  'kind',e.kind,'occurredAt',e.occurred_at,'status',e.status,'data',payload);
END $$;

REVOKE ALL ON FUNCTION public.notification_center_order_activity_internal(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.notification_center_dto(public.notification_center_events,public.notification_center_deliveries) FROM PUBLIC,anon,authenticated;

-- SOURCE: notification_center/email_preferences.sql
CREATE OR REPLACE FUNCTION public.notification_center_email_category_internal(p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_kind IN ('email_problem','bank_problem','payment_problem','provider_problem') THEN 'problems'
 WHEN p_kind='occasion_joined' THEN 'participants'
 WHEN p_kind IN ('customer_order_request','waitlist_registered','offer_accepted','offer_declined','offer_expired','order_created','order_cancelled') THEN 'orders'
 WHEN p_kind='order_payment_received' THEN 'payments' END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_email_enabled_internal(e public.notification_center_events,p_user uuid,p_scopes text[])
RETURNS timestamptz LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT min(policy.enabled) FROM (
 SELECT a.email_collection_started_at FROM public.notification_center_organizations a
 WHERE a.organization=e.organization AND a.email_collection_started_at IS NOT NULL
  AND public.notification_center_email_required_kind_internal(e.kind)
  AND CASE WHEN e.kind='bank_problem' THEN ('bank:'||(e.data->>'bankConnectionId'))=ANY(p_scopes)
   WHEN e.kind='provider_problem' THEN ('provider-unit:'||(e.data->>'unitId'))=ANY(p_scopes) ELSE false END
  AND e.occurred_at>=a.email_collection_started_at
 UNION ALL
 SELECT min(greatest(s.enabled_from,(s.kinds->e.kind->>'enabledFrom')::timestamptz,a.email_collection_started_at))
 FROM public.notification_center_email_subscriptions s
 JOIN public.notification_center_email_profiles p ON p.recipient=s.recipient AND NOT p.stopped
 JOIN public.notification_center_organizations a ON a.organization=s.organization
 WHERE s.recipient=p_user AND s.organization=e.organization AND a.email_collection_started_at IS NOT NULL
  AND public.notification_center_email_category_internal(e.kind) IS NOT NULL
  AND s.kinds->e.kind->>'enabled'='true'
  AND e.occurred_at>=greatest(s.enabled_from,(s.kinds->e.kind->>'enabledFrom')::timestamptz,a.email_collection_started_at)
  AND public.notification_center_unmuted(e,p_user)
  AND NOT public.notification_center_email_required_kind_internal(e.kind)) policy(enabled)
$$;
-- All runtime profile creation uses this owner. Try-lock keeps enrollment from
-- blocking a second collector behind an uncommitted first-profile insertion.
CREATE OR REPLACE FUNCTION public.notification_center_email_ensure_profile_internal(p_recipient uuid,p_try boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.notification_center_email_profiles WHERE recipient=p_recipient) THEN RETURN true; END IF;
 IF p_try THEN
  IF NOT pg_try_advisory_xact_lock(hashtextextended('notification-email-profile:'||p_recipient,0)) THEN RETURN false; END IF;
 ELSE PERFORM pg_advisory_xact_lock(hashtextextended('notification-email-profile:'||p_recipient,0));
 END IF;
 INSERT INTO public.notification_center_email_profiles(recipient,locale)
 SELECT ui.id,CASE WHEN ui.data->>'locale' IN ('cs','en','de','pl','sk','uk') THEN ui.data->>'locale' ELSE 'cs' END
 FROM public.user_info ui WHERE ui.id=p_recipient ON CONFLICT DO NOTHING;
 RETURN EXISTS(SELECT 1 FROM public.notification_center_email_profiles WHERE recipient=p_recipient);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_email_ensure_profile_internal(uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.save_notification_center_email_settings(
 p_organization bigint,p_revision bigint,p_stopped boolean,p_locale text,p_kinds jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE profile public.notification_center_email_profiles; previous jsonb; kinds jsonb; item record; at timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 IF jsonb_typeof(p_kinds) IS DISTINCT FROM 'object' OR p_stopped IS NULL OR p_locale NOT IN ('cs','en','de','pl','sk','uk') THEN RAISE EXCEPTION 'notification_email_settings_invalid'; END IF;
 PERFORM public.notification_center_email_ensure_profile_internal(auth.uid());
 SELECT * INTO STRICT profile FROM public.notification_center_email_profiles WHERE recipient=auth.uid() FOR UPDATE;
 IF p_revision IS DISTINCT FROM profile.revision THEN RAISE serialization_failure USING MESSAGE='notification_email_revision_conflict'; END IF;
 SELECT s.kinds INTO previous FROM public.notification_center_email_subscriptions s
 WHERE s.recipient=auth.uid() AND s.organization=p_organization;
 kinds:='{}';
 FOR item IN SELECT key,value FROM jsonb_each(p_kinds) LOOP
  IF public.notification_center_email_required_kind_internal(item.key) THEN RAISE EXCEPTION 'notification_email_kind_required'; END IF;
  IF public.notification_center_email_category_internal(item.key) IS NULL OR jsonb_typeof(item.value)<>'boolean' THEN RAISE EXCEPTION 'notification_email_kind_invalid'; END IF;
  kinds:=kinds||jsonb_build_object(item.key,jsonb_build_object('enabled',item.value,
   'enabledFrom',CASE WHEN previous->item.key->>'enabled'='true' AND NOT profile.stopped THEN previous->item.key->>'enabledFrom' ELSE at::text END));
 END LOOP;
 INSERT INTO public.notification_center_email_subscriptions(recipient,organization,kinds,enabled_from)
 VALUES(auth.uid(),p_organization,kinds,at)
 ON CONFLICT(recipient,organization) DO UPDATE SET kinds=excluded.kinds,revision=notification_center_email_subscriptions.revision+1;
 IF profile.stopped AND NOT p_stopped THEN
  UPDATE public.notification_center_email_subscriptions SET enabled_from=at WHERE recipient=auth.uid();
 END IF;
 UPDATE public.notification_center_email_profiles SET stopped=p_stopped,locale=p_locale,revision=revision+1 WHERE recipient=auth.uid() RETURNING revision INTO p_revision;
 RETURN p_revision;
END $$;
REVOKE ALL ON FUNCTION public.save_notification_center_email_settings(bigint,bigint,boolean,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.save_notification_center_email_settings(bigint,bigint,boolean,text,jsonb) TO authenticated;

-- Released web 0.20.597+1113 still sends p_occasion. Keep only its null-scope
-- wire adapter until that cached web release is retired. No occasion writer or
-- preference inheritance survives; old non-null requests fail without writing.
CREATE OR REPLACE FUNCTION public.save_notification_center_email_settings(
 p_organization bigint,p_occasion bigint,p_revision bigint,p_stopped boolean,p_locale text,p_kinds jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_occasion IS NOT NULL THEN RAISE EXCEPTION 'notification_email_occasion_settings_removed'; END IF;
 RETURN public.save_notification_center_email_settings(p_organization,p_revision,p_stopped,p_locale,p_kinds);
END $$;
REVOKE ALL ON FUNCTION public.save_notification_center_email_settings(bigint,bigint,bigint,boolean,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.save_notification_center_email_settings(bigint,bigint,bigint,boolean,text,jsonb) TO authenticated;

-- Separate activation of selected tenant scope, never implicit in a delivery.
CREATE OR REPLACE FUNCTION public.activate_notification_center_emails(p_organization bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 PERFORM 1 FROM public.notification_center_organizations WHERE organization=p_organization FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'notification_email_organization_inactive'; END IF;
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization AND email_collection_started_at IS NOT NULL) THEN RETURN; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.email_capacity c CROSS JOIN public.abuse_policy_rules r
  WHERE r.rule_key='email.send.notification.global.day' AND c.quota_at>now()-interval '15 minutes'
   AND r.base_limit<=floor(least(c.daily_quota,CASE WHEN c.shared_account THEN c.allocated_daily ELSE c.daily_quota END)*0.1)) THEN
  RAISE EXCEPTION 'notification_capacity_policy_unverified';
 END IF;
 UPDATE public.notification_center_user_state SET email_scanned_sequence=last_delivery_sequence WHERE organization=p_organization;
 UPDATE public.notification_center_organizations SET email_collection_started_at=clock_timestamp() WHERE organization=p_organization;
END $$;
REVOKE ALL ON FUNCTION public.activate_notification_center_emails(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_notification_center_emails(bigint) TO service_role;
REVOKE ALL ON FUNCTION public.notification_center_email_category_internal(text),public.notification_center_email_enabled_internal(public.notification_center_events,uuid,text[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_email_catalog_internal(p_scopes text[],p_occasion bigint)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH kinds AS(SELECT kind,public.notification_center_email_category_internal(kind) category FROM unnest(ARRAY['customer_order_request','occasion_joined','waitlist_registered','order_created','order_cancelled','offer_accepted','offer_declined','offer_expired','order_payment_received','payment_problem','bank_problem','email_problem','provider_problem']) kind)
 SELECT coalesce(jsonb_object_agg(kind,category),'{}') FROM kinds k WHERE EXISTS(SELECT 1 FROM unnest(p_scopes) x
  WHERE CASE WHEN k.kind='occasion_joined' THEN CASE WHEN p_occasion IS NULL THEN x LIKE 'app:%' ELSE x='app:'||p_occasion END
   WHEN k.kind='provider_problem' THEN x LIKE 'provider-unit:%'
   WHEN k.kind='bank_problem' THEN x LIKE 'bank:%'
   WHEN k.kind='email_problem' THEN x='email-admin:shared' OR CASE WHEN p_occasion IS NULL THEN x LIKE 'email-admin:%' ELSE x='email-admin:'||p_occasion END
   ELSE CASE WHEN p_occasion IS NULL THEN x LIKE 'orders:%' ELSE x='orders:'||p_occasion END END);
$$;
REVOKE ALL ON FUNCTION public.notification_center_email_catalog_internal(text[],bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Self-only status: no message payload, address or provider diagnostics.
CREATE OR REPLACE FUNCTION public.notification_center_email_settings_internal(p_organization bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH capability AS MATERIALIZED(SELECT public.notification_center_app_supported_internal(p_organization) app_supported),
 scopes AS MATERIALIZED(SELECT array_agg(a.scope) FILTER(WHERE a.scope NOT LIKE 'app:%' OR c.app_supported) allowed
  FROM public.notification_center_prepared_allowed_scopes(p_organization,NULL,auth.uid()) a CROSS JOIN capability c),
 catalog AS MATERIALIZED(SELECT public.notification_center_email_catalog_internal((SELECT allowed FROM scopes),NULL) kinds)
 SELECT jsonb_build_object('windowSeconds',extract(epoch FROM public.notification_center_email_window_internal())::integer,'revision',coalesce(p.revision,0),'stopped',coalesce(p.stopped,true),'locale',coalesce(p.locale,'cs'),
 'catalog',(SELECT kinds FROM catalog),
 'requiredKinds',coalesce((SELECT jsonb_agg(key ORDER BY key) FROM catalog,jsonb_object_keys(kinds) key WHERE public.notification_center_email_required_kind_internal(key)),'[]'::jsonb),
 'kinds',coalesce((SELECT s.kinds FROM public.notification_center_email_subscriptions s WHERE s.recipient=auth.uid() AND s.organization=p_organization),'{}'),
 'subscriptions',coalesce((SELECT jsonb_agg(jsonb_build_object('occasion',NULL,'kinds',s.kinds)) FROM public.notification_center_email_subscriptions s WHERE s.recipient=auth.uid() AND s.organization=p_organization),'[]'),
 'state',CASE WHEN EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d WHERE d.recipient=auth.uid() AND d.state='collecting') AND public.get_user_delivery_email(auth.uid()) IS NULL THEN 'no_address'
  ELSE (SELECT m.workflow_state FROM public.email_messages m WHERE m.recipient_user=auth.uid() AND m.message_kind='admin_notification_digest' ORDER BY m.id DESC LIMIT 1) END)
 FROM (SELECT 1) seed LEFT JOIN public.notification_center_email_profiles p ON p.recipient=auth.uid();
$$;
REVOKE ALL ON FUNCTION public.notification_center_email_settings_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/admin_form_commands.sql
-- Delegation adapter only: existing UI commands retain the single transaction,
-- receipt, validation, allocation, notification and sync ownership.
CREATE OR REPLACE FUNCTION public.manage_form(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_action text,p_payload jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; link text; form_id bigint; source_id bigint; allowed text[]; state jsonb;
BEGIN
 IF p_action IS NULL OR p_action NOT IN ('create','save','duplicate','delete','public_link') OR p_payload IS NULL
  OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>1048576 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid form command'; END IF;
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,CASE WHEN p_action='public_link' THEN 'save' ELSE p_action END);
 SELECT o.link INTO link FROM public.occasions o WHERE o.id=p_occasion;
 IF p_action IN ('save','delete','public_link') THEN
  form_id:=(p_payload->>'id')::bigint;
  IF form_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=form_id AND occasion=p_occasion)
   AND NOT (p_action='delete' AND EXISTS(SELECT 1 FROM public.client_mutation_receipts
    WHERE command_id=p_command_id AND actor_id=auth.uid() AND occasion=p_occasion AND command_name='inventory.form.delete')) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
  IF NOT p_payload ? 'expected_aggregate_version' OR jsonb_typeof(p_payload->'expected_aggregate_version')<>'number'
    OR (p_payload->>'expected_aggregate_version')::bigint<0 THEN
   RAISE invalid_parameter_value USING MESSAGE='original form version required'; END IF;
 END IF;
 allowed:=CASE p_action
  WHEN 'public_link' THEN ARRAY['id','expected_aggregate_version','link']
  WHEN 'create' THEN ARRAY['title']
  WHEN 'save' THEN ARRAY['payment_selection_intent','id','expected_aggregate_version','expected_product_versions','expected_product_type_versions',
   'title','header','header_off','is_open','blueprint','bank_account','deadline_duration_seconds',
   'participant_capacity','waitlist_enabled','show_remaining_capacity','waitlist_offer_duration_seconds',
   'form_fields','deleted_field_ids','deleted_product_ids','settings','customer_self_service','term_start_at','term_end_at']
  WHEN 'duplicate' THEN ARRAY['source_form_id','source_occasion_id','source_unit_id','locale']
  WHEN 'delete' THEN ARRAY['id','expected_aggregate_version']
 END;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE NOT k=ANY(allowed)) THEN
  RAISE invalid_parameter_value USING MESSAGE='unsupported form fields'; END IF;
 CASE p_action
 WHEN 'public_link' THEN
  IF jsonb_typeof(p_payload->'link') IS DISTINCT FROM 'string' THEN RAISE invalid_parameter_value USING MESSAGE='public slug required'; END IF;
  result:=public.update_form_client_sync_v1(p_payload||jsonb_build_object('occasion',p_occasion,'expected_product_versions','{}'::jsonb,'expected_product_type_versions','{}'::jsonb),p_command_id);
 WHEN 'create' THEN
  IF NOT p_payload ? 'title' OR jsonb_typeof(p_payload->'title')<>'string' OR length(p_payload->>'title')>500 THEN
   RAISE invalid_parameter_value USING MESSAGE='form title required'; END IF;
  result:=public.create_form_client_sync_v1(link,'',p_payload->>'title',p_command_id);
 WHEN 'save' THEN
  IF jsonb_typeof(p_payload->'expected_product_versions') IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_payload->'expected_product_type_versions') IS DISTINCT FROM 'object' THEN
   RAISE invalid_parameter_value USING MESSAGE='original product versions required'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(p_payload->'deleted_product_ids','[]')) id
    WHERE NOT (p_payload->'expected_product_versions') ? id) THEN
   RAISE invalid_parameter_value USING MESSAGE='deleted product baseline required'; END IF;
  -- The field transport can edit common definitions and reference a catalog
  -- type; inline product mutation remains in the existing aggregate UI owner.
  IF p_payload ? 'form_fields' AND (jsonb_typeof(p_payload->'form_fields')<>'array' OR
    EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'form_fields') f WHERE
      jsonb_typeof(f)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(f) k WHERE k NOT IN
       ('id','title','description','type','is_required','is_hidden','is_ticket_field','order','data','product_type_id','product_type')))) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid form fields'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_payload->'form_fields','[]')) f
    WHERE f ? 'data' AND f->'data'<>'null'::jsonb AND
     (jsonb_typeof(f->'data')<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(f->'data') k
       WHERE k NOT IN ('options','max_tickets','selection_type','default_value','label','is_group_feature','min_year','max_year','is_hard','message','show_expiry_date','expiry_date_label','show_surcharge_description')))) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported field settings'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_payload->'form_fields','[]')) f
    WHERE f ? 'product_type' AND f ? 'product_type_id') THEN RAISE invalid_parameter_value USING MESSAGE='choose product reference or aggregate'; END IF;
  result:=public.update_form_client_sync_v1(p_payload||jsonb_build_object('occasion',p_occasion),p_command_id);
 WHEN 'duplicate' THEN
  source_id:=(p_payload->>'source_occasion_id')::bigint;
  PERFORM public.check_form_authoring_scope_internal(source_id,p_organization,(p_payload->>'source_unit_id')::bigint,'source');
  IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=(p_payload->>'source_form_id')::bigint AND occasion=source_id) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign source form'; END IF;
  IF p_payload->>'locale' IS NULL OR p_payload->>'locale' NOT IN ('cs','en','sk','de','pl','uk') THEN
   RAISE invalid_parameter_value USING MESSAGE='copy locale required'; END IF;
  result:=public.duplicate_form_to_occasion_client_sync_v1((p_payload->>'source_form_id')::bigint,link,p_command_id,p_payload->>'locale');
  PERFORM public.check_form_authoring_scope_internal(source_id,p_organization,(p_payload->>'source_unit_id')::bigint,'source',true);
 WHEN 'delete' THEN
  result:=public.delete_form_client_sync_v1(form_id,p_command_id,(p_payload->>'expected_aggregate_version')::bigint);
 END CASE;
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,CASE WHEN p_action='public_link' THEN 'save' ELSE p_action END,true);
 IF (result->>'code')::int=200 THEN
  state:=result->'data'->'authoring';
  IF octet_length(state::text)>1048576 OR jsonb_array_length(state->'fields')>500 THEN
   RAISE program_limit_exceeded USING MESSAGE='form snapshot too large'; END IF;
  form_id:=coalesce((state->'form'->>'id')::bigint,form_id);
  RETURN result||jsonb_build_object('data',jsonb_build_object('occasionId',p_occasion,'formId',form_id,'authoring',state),
   'sync',jsonb_build_object('replacements','[]'::jsonb))
   ||CASE WHEN p_action='public_link' THEN jsonb_build_object('publicLink',jsonb_build_object('occasionId',p_occasion,'formId',form_id,'slug',result#>>'{data,link}')) ELSE '{}'::jsonb END;
 END IF;
 RETURN result||jsonb_build_object('data',jsonb_build_object('reason','FORM_COMMAND_REJECTED'),
   'sync',jsonb_build_object('replacements','[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.manage_form(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_form(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated;

-- SOURCE: eshop_waitlist/order_overview_email.sql
-- The overview link belongs in existing order emails, never a separate message.
-- Keep historical template and delivery rows; exclude this code from the catalog.
DROP FUNCTION IF EXISTS public.enqueue_order_overview_reissue_v1(bigint,uuid,uuid,jsonb,text);

-- Private renderer boundary. The first ordinary order email creates the source;
-- every later message and split child reuses the root's encrypted source.
CREATE OR REPLACE FUNCTION public.get_order_email_overview_source_v1(
 p_order_id bigint,p_recipient text,p_command_id uuid,p_delivery jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE requested eshop.orders; root eshop.orders; occ public.occasions; f public.forms;
 s eshop.order_overview_sources;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO STRICT requested FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO STRICT root FROM eshop.orders WHERE id=coalesce(requested.source_waitlist_order_id,requested.id) FOR UPDATE;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=root.occasion;
 SELECT * INTO f FROM public.forms WHERE id=root.form AND occasion=occ.id;
 IF requested.occasion IS DISTINCT FROM root.occasion OR requested.form IS DISTINCT FROM root.form
 OR requested.data->>'email' IS DISTINCT FROM p_recipient THEN
  RAISE EXCEPTION 'INVALID_OVERVIEW_RECIPIENT';
 END IF;
 -- A repaired split child must not receive the root capability covering other
 -- orders at its former contact. Omit that optional link; preserve the root
 -- source and every other order/contact unchanged.
 IF root.data->>'email' IS DISTINCT FROM p_recipient THEN RETURN NULL; END IF;
 -- Orders without a public form have no public overview route.
 IF f.id IS NULL THEN RETURN NULL; END IF;
 SELECT src.* INTO s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities cap USING(token_hash)
 WHERE cap.order_id=root.id AND cap.form_id=f.id AND cap.organization_id=occ.organization
 AND cap.kind='order_view' AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp()
 AND src.expires_at=cap.expires_at ORDER BY src.created_at DESC LIMIT 1;
 IF s.token_hash IS NULL THEN
  -- Never silently replace an expired/revoked capability with a different link.
  IF EXISTS(SELECT 1 FROM eshop.waitlist_capabilities WHERE order_id=root.id AND kind='order_view') THEN RETURN NULL; END IF;
  IF p_delivery IS NOT NULL THEN
   PERFORM public.issue_order_overview_internal(root.id,p_delivery,p_command_id);
   SELECT * INTO STRICT s FROM eshop.order_overview_sources WHERE command_id=p_command_id;
  END IF;
 END IF;
 RETURN jsonb_build_object('orderId',root.id,'organization',occ.organization,'occasion',occ.id,'unit',occ.unit,
 'allowedActions',public.customer_order_actions_internal(root.id),'recipient',p_recipient,'occasionTitle',occ.title,'orderSymbol',root.order_symbol,
 'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(root.id)),
 'formLink',f.link,'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=occ.organization),
 'source',CASE WHEN s.token_hash IS NOT NULL THEN jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,'expiresAt',s.expires_at) END);
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_overview_source_v1(bigint,text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_email_overview_source_v1(bigint,text,uuid,jsonb) TO service_role;

-- SOURCE: eshop_waitlist/email_render_context.sql
-- Shared presentation metadata; no lifecycle or capability decisions.
CREATE OR REPLACE FUNCTION public.get_waitlist_form_timezone_internal(p_form bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH config AS MATERIALIZED (
  SELECT array_remove(ARRAY[nullif(occ.data->>'timezone',''),nullif(u.data->>'timezone',''),
   nullif(org.data->>'timezone','')],NULL) zones
  FROM public.forms f JOIN public.occasions occ ON occ.id=f.occasion
  LEFT JOIN public.units u ON u.id=occ.unit
  LEFT JOIN public.organizations org ON org.id=occ.organization
  WHERE f.id=p_form
 )
 -- Enumerating pg_timezone_names reads the whole catalog. Validate all three
 -- preferences in one pass, and avoid that work when no preference is set.
 SELECT CASE WHEN cardinality(zones)=0 THEN 'Europe/Prague' ELSE coalesce((
  SELECT name FROM pg_timezone_names WHERE name=ANY(config.zones)
  ORDER BY array_position(config.zones,name) LIMIT 1
 ),'Europe/Prague') END FROM config;
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_form_timezone_internal(bigint) FROM PUBLIC,anon,authenticated;

-- Private queue renderer boundary. Personal capabilities remain encrypted in
-- existing queue sources; the renderer receives only their hashes and envelopes.
CREATE OR REPLACE FUNCTION public.get_waitlist_email_render_context_v1(
 p_order_id bigint,p_offer_id uuid DEFAULT NULL,p_recipient text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE o eshop.orders; f public.forms; occ public.occasions; org public.organizations;
 manage_message public.email_messages; manage_cap eshop.waitlist_capabilities;
 source_cap eshop.waitlist_capabilities; v_recipient text; v_timezone text;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO f FROM public.forms WHERE id=o.form;
 SELECT * INTO occ FROM public.occasions WHERE id=o.occasion;
 SELECT * INTO org FROM public.organizations WHERE id=occ.organization;
 IF o.id IS NULL OR f.id IS NULL OR f.occasion<>occ.id OR o.state<>'waitlisted'
 OR (p_offer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers
  WHERE id=p_offer_id AND order_id=o.id AND form_id=f.id AND expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id AND outcome='pending'))) THEN
  RAISE EXCEPTION 'waitlist_email_source_invalid';
 END IF;
 v_timezone:=public.get_waitlist_form_timezone_internal(f.id);
 v_recipient:=coalesce(p_recipient,o.data->>'email');
 SELECT * INTO manage_message FROM public.email_messages m
 WHERE m.order_id=o.id AND m.message_kind='waitlist_confirmation'
 AND m.recipient=v_recipient
 AND m.data ? 'waitlistEnvelope' ORDER BY m.id LIMIT 1;
 SELECT * INTO manage_cap FROM eshop.waitlist_capabilities
 WHERE order_id=o.id AND form_id=f.id AND organization_id=org.id
 AND kind='manage' AND revoked_at IS NULL;
 SELECT * INTO source_cap FROM eshop.waitlist_capabilities
 WHERE order_id=o.id AND form_id=f.id AND organization_id=org.id AND revoked_at IS NULL
 AND CASE WHEN p_offer_id IS NULL THEN kind='manage'
  ELSE kind='offer' AND offer_id=p_offer_id AND expires_at>clock_timestamp() END;
 IF manage_message.id IS NULL OR manage_cap.token_hash IS NULL OR source_cap.token_hash IS NULL THEN
  RAISE EXCEPTION 'waitlist_email_source_invalid';
 END IF;
 RETURN jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,
  'allowedActions',public.customer_order_actions_internal(o.id),'organization',org.id,'occasion',occ.id,'unit',occ.unit,'formLink',f.link,
  'webLink',org.data->>'DEFAULT_URL','replyTo',public.get_reply_to_email_for_order(o.id),
  'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(o.id)),
  'offeredCount',(SELECT count(*) FROM eshop.waitlist_offer_slots
    WHERE offer_id=p_offer_id AND outcome='pending'),
  'timeZone',v_timezone,
  'communicationTone',public.get_effective_form_data(f.id)->>'communication_tone',
  'toneSubstitutions',public.get_waitlist_email_tone_substitutions_internal(f.id),
  'expiresAt',(SELECT expires_at FROM eshop.waitlist_offers WHERE id=p_offer_id),
  'tokenHash',source_cap.token_hash,'manageTokenHash',manage_cap.token_hash,
  'manageEnvelope',manage_message.data->'waitlistEnvelope',
  'overviewSource',(SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash) WHERE c.order_id=o.id AND c.kind='order_view' AND c.revoked_at IS NULL AND c.expires_at>statement_timestamp() ORDER BY s.created_at DESC LIMIT 1),
  'manageContentHash',manage_message.data->>'content_hash');
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 TO service_role;

-- SOURCE: eshop/get_order_details_for_email.sql
CREATE OR REPLACE FUNCTION public.get_order_details_for_email(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
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
        'occasion', to_jsonb(public.order_term_occasion_internal(o.id))||jsonb_build_object('locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=occ.organization),'cs')),
        -- Same statement snapshot as the ticket feature used by delivery.
        'wallet', jsonb_build_object(
          'feature',(SELECT f FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'),
          'fingerprint',public.ticket_wallet_fingerprint(occ.id)),
        'payment_info', to_jsonb(pi.*)||jsonb_build_object('collectionAction',public.payment_collection_action_internal(o.id),'providerPayment',CASE WHEN public.payment_method_is_online_internal(pi.payment_method) THEN public.provider_order_payment_projection_internal(o.id) END),
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
$$;
-- The worker is the external consumer. Already-authorized definer commands
-- (contact repair) share this read owner without granting it to clients.
REVOKE ALL ON FUNCTION public.get_order_details_for_email(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_details_for_email(bigint) TO service_role;

-- SOURCE: ticket_wallet/projection.sql
-- The current paid-delivery boundary, never scanner configuration overrides.
CREATE OR REPLACE FUNCTION public.ticket_wallet_state_internal(p_ticket bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE t eshop.tickets; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; state text;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO t FROM eshop.tickets WHERE id=p_ticket;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 SELECT * INTO o FROM public.order_term_occasion_internal(c.order_id);
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
 SELECT * INTO o FROM public.order_term_occasion_internal(c.order_id);
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
 PERFORM public.refresh_order_wallet_term_domain_internal((SELECT order_id FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket));
END $$;
REVOKE ALL ON FUNCTION public.refresh_ticket_wallet_term_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_ticket_wallet_term_internal(bigint) TO service_role;
