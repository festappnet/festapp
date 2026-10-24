-- Stripe unit authorization and durable OAuth intent boundary. Requires Stripe foundation.

-- SOURCE: eshop_stripe/connections_schema.sql
CREATE TABLE eshop.stripe_connection_flows (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 state_hash text NOT NULL UNIQUE CHECK(state_hash ~ '^[a-f0-9]{64}$'),
 actor uuid NOT NULL REFERENCES public.user_info(id),
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 unit_id bigint NOT NULL REFERENCES public.units(id), livemode boolean NOT NULL,
 previous_connection_id uuid REFERENCES eshop.stripe_connections(id),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','claimed','uncertain','completed','denied')),
 lease_token uuid, result jsonb,
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 CHECK(expires_at>created_at)
);
CREATE TABLE eshop.stripe_connection_audit (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), connection_id uuid REFERENCES eshop.stripe_connections(id),
 flow_id uuid REFERENCES eshop.stripe_connection_flows(id), actor uuid REFERENCES public.user_info(id),
 action text NOT NULL CHECK(action IN ('connected','reconnected','replaced','paused','resumed','revoked')),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE eshop.stripe_connection_flows ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_connection_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.stripe_connection_flows,eshop.stripe_connection_audit FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_stripe/connection_status_schema.sql
ALTER TABLE eshop.stripe_connections ADD COLUMN status_lease uuid;
ALTER TABLE eshop.stripe_connections ADD COLUMN status_lease_expires_at timestamptz;
ALTER TABLE eshop.stripe_connections ADD COLUMN next_check_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE eshop.stripe_connections ADD COLUMN status_failures integer NOT NULL DEFAULT 0 CHECK(status_failures>=0);
ALTER TABLE eshop.stripe_connections ADD CONSTRAINT stripe_connection_status_lease CHECK((status_lease IS NULL)=(status_lease_expires_at IS NULL));
ALTER TABLE eshop.stripe_connection_audit DROP CONSTRAINT stripe_connection_audit_action_check;
ALTER TABLE eshop.stripe_connection_audit ADD CONSTRAINT stripe_connection_audit_action_check
 CHECK(action IN ('connected','reconnected','replaced','paused','resumed','revoked','status_changed'));

-- SOURCE: eshop_stripe/disconnect_schema.sql
CREATE TABLE eshop.stripe_disconnect_intents (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 connection_id uuid NOT NULL REFERENCES eshop.stripe_connections(id),
 actor uuid NOT NULL REFERENCES public.user_info(id),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','claimed','uncertain','completed')),
 result jsonb,created_at timestamptz NOT NULL DEFAULT now(),claimed_at timestamptz,completed_at timestamptz
);
CREATE UNIQUE INDEX stripe_one_disconnect_intent ON eshop.stripe_disconnect_intents(connection_id) WHERE state<>'completed';
ALTER TABLE eshop.stripe_disconnect_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.stripe_disconnect_intents FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_stripe/abuse.sql
-- Connect uses the existing admission/budget engine; no parallel rate limiter.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('stripe.connect.actor.day','stripe.connect','actor','rolling',86400,3600,30,100),
 ('stripe.connect.unit.burst','stripe.connect','unit','rolling',60,60,5,20),
 ('stripe.connect.organization.day','stripe.connect','organization','rolling',86400,3600,100,1000);

-- SOURCE: abuse/policy.sql
-- One statement snapshot per domain admission. Scoped overrides cannot alter an actor rule.
CREATE OR REPLACE FUNCTION public.abuse_effective_rules_v1(p_budget text,p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('revision',v.revision,'rules',coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object(
 'base_limit',coalesce(u.base_limit,o.base_limit,r.base_limit)) ORDER BY r.rule_key),'[]'::jsonb))
 FROM public.abuse_policy_revision v CROSS JOIN public.abuse_policy_rules r
 LEFT JOIN public.abuse_policy_overrides o ON o.rule_key=r.rule_key AND o.target_kind='organization'
  AND o.target_id=p_org AND r.scope_kind IN ('unit','organization') AND o.expires_at>statement_timestamp()
 LEFT JOIN public.abuse_policy_overrides u ON u.rule_key=r.rule_key AND u.target_kind='unit'
  AND u.target_id=p_unit AND r.scope_kind='unit' AND u.expires_at>statement_timestamp()
 WHERE r.budget_key=p_budget GROUP BY v.revision
 HAVING count(*)=CASE p_budget WHEN 'occasion.creation' THEN 8 WHEN 'occasion.copy' THEN 2 WHEN 'occasion.draft' THEN 7
  WHEN 'unit.creation' THEN 3 WHEN 'email.ordinary' THEN 4 WHEN 'email.auth' THEN 4
  WHEN 'email.backlog' THEN 4 WHEN 'email.auth.backlog' THEN 1 WHEN 'email.payload' THEN 1
  WHEN 'email.prepare' THEN 2 WHEN 'email.actor' THEN 1 WHEN 'email.dispatch' THEN 1 WHEN 'ticket.document' THEN 4 WHEN 'ticket.preview' THEN 4 WHEN 'bank.operation' THEN 3 WHEN 'stripe.connect' THEN 3 WHEN 'stripe.checkout' THEN 3 WHEN 'order.creation' THEN 4 WHEN 'qr.global' THEN 1 WHEN 'qr.proof' THEN 1 WHEN 'qr.payload' THEN 1 WHEN 'spot.hold' THEN 3 WHEN 'image.upload' THEN 5 WHEN 'image.fetch' THEN 5 WHEN 'sync.snapshot' THEN 2 WHEN 'sync.work' THEN 1 WHEN 'hold.duration' THEN 1 WHEN 'auth.reset.source' THEN 2 WHEN 'organization.creation' THEN 1 WHEN 'auth.reset.account' THEN 1
  WHEN 'auth.google.source' THEN 1 WHEN 'auth.google.client' THEN 1 WHEN 'auth.google.global' THEN 1 WHEN 'auth.google.attempt' THEN 1 WHEN 'auth.google.proof' THEN 1
  WHEN 'scan.operation' THEN 2 WHEN 'scan.invalid.global' THEN 1 WHEN 'scan.invalid.source' THEN 1 WHEN 'scan.password' THEN 2 WHEN 'scan.export' THEN 2
  WHEN 'reception.create' THEN 1 WHEN 'reception.issue' THEN 1 WHEN 'reception.revoke' THEN 1 WHEN 'reception.cancel' THEN 1
  WHEN 'order.mutation' THEN 4
  WHEN 'push.delivery' THEN 10
  WHEN 'cleaning.report' THEN 3
  WHEN 'push.dispatch' THEN 2
  WHEN 'image.records' THEN 9 WHEN 'auth.password' THEN 2 WHEN 'document.output' THEN 4 WHEN 'image.storage' THEN 3 WHEN 'monitor.thresholds' THEN 6 WHEN 'auth.password.change' THEN 3
  WHEN 'email.send.ordinary' THEN 2 WHEN 'email.send.auth' THEN 2 WHEN 'email.send.commitment' THEN 2
  ELSE -1 END;
$$;

-- All families in one admission phase share a PostgreSQL STABLE statement
-- snapshot, including overrides and revision; no config lock or HTTP hop.
CREATE OR REPLACE FUNCTION public.abuse_policy_bundle_v1(p_budgets text[],p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_object_agg(b,public.abuse_effective_rules_v1(b,p_unit,p_org)) FROM unnest(p_budgets) b;
$$;
REVOKE ALL ON FUNCTION public.abuse_policy_bundle_v1(text[],bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Only numeric limits may be changed here. Algorithm/window/identity changes need a migration.
-- A batch is one audited optimistic revision; no writes to usage.
CREATE OR REPLACE FUNCTION public.set_abuse_policy_v1(p_expected_revision bigint,p_reason text,p_changes jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_revision bigint; c jsonb; r public.abuse_policy_rules; v_old jsonb; v_author text;
BEGIN
 PERFORM public.require_service_role();
 IF length(btrim(p_reason)) NOT BETWEEN 8 AND 1000 OR p_reason IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_changes) NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy batch'; END IF;
 SELECT revision INTO v_revision FROM public.abuse_policy_revision FOR UPDATE;
 IF p_expected_revision IS DISTINCT FROM v_revision THEN RAISE serialization_failure USING MESSAGE='abuse policy revision conflict'; END IF;
 v_author:=coalesce(auth.uid()::text,session_user::text);
 SELECT jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
 'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x)) INTO v_old;
 FOR c IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN ('rule_key','base_limit','target_kind','target_id','expires_at')) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported abuse policy parameter'; END IF;
  SELECT * INTO r FROM public.abuse_policy_rules WHERE rule_key=c->>'rule_key';
  IF NOT FOUND OR (c->>'base_limit')::bigint IS NULL OR (c->>'base_limit')::bigint NOT BETWEEN 1 AND r.hard_cap THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy limit'; END IF;
  IF c ? 'target_kind' THEN
   IF (c->>'target_kind'='unit' AND r.scope_kind<>'unit') OR
    (c->>'target_kind'='organization' AND r.scope_kind NOT IN ('unit','organization')) OR
    c->>'target_kind' NOT IN ('unit','organization') OR (c->>'target_id')::bigint IS NULL OR
    (c->>'expires_at')::timestamptz IS NULL OR (c->>'expires_at')::timestamptz<=statement_timestamp() OR
    (c->>'expires_at')::timestamptz>statement_timestamp()+interval '90 days' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid abuse override scope or expiry'; END IF;
   IF NOT (CASE WHEN c->>'target_kind'='unit' THEN EXISTS(SELECT 1 FROM public.units WHERE id=(c->>'target_id')::bigint)
    ELSE EXISTS(SELECT 1 FROM public.organizations WHERE id=(c->>'target_id')::bigint) END) THEN
    RAISE invalid_parameter_value USING MESSAGE='unknown abuse override target'; END IF;
   INSERT INTO public.abuse_policy_overrides VALUES(r.rule_key,c->>'target_kind',(c->>'target_id')::bigint,
    (c->>'base_limit')::bigint,(c->>'expires_at')::timestamptz,p_reason,v_author)
   ON CONFLICT(rule_key,target_kind,target_id) DO UPDATE SET base_limit=excluded.base_limit,expires_at=excluded.expires_at,reason=excluded.reason,author=excluded.author;
  ELSE
   IF c ? 'target_id' OR c ? 'expires_at' THEN RAISE invalid_parameter_value USING MESSAGE='override target required'; END IF;
   UPDATE public.abuse_policy_rules SET base_limit=(c->>'base_limit')::bigint WHERE rule_key=r.rule_key;
  END IF;
 END LOOP;
 UPDATE public.abuse_policy_revision SET revision=revision+1 RETURNING revision INTO v_revision;
 INSERT INTO public.abuse_policy_audit SELECT v_revision,clock_timestamp(),v_author,p_reason,v_old,
  jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
   'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x));
 RETURN v_revision;
END $$;
REVOKE ALL ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.abuse_effective_rules_v1(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_abuse_policy_v1(p_unit bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_manager_on_unit(p_unit) OR public.get_is_editor_on_unit(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 SELECT organization INTO v_org FROM public.units WHERE id=p_unit;
 RETURN jsonb_build_object('creation',public.abuse_effective_rules_v1('occasion.creation',p_unit,v_org),
 'draft',public.abuse_effective_rules_v1('occasion.draft',p_unit,v_org),
 'usage',coalesce((SELECT jsonb_agg(jsonb_build_object('rule',u.rule_key,'amount',u.amount,'bucketAt',u.bucket_at,'expiresAt',u.expires_at))
 FROM public.abuse_budget_usage u JOIN public.abuse_policy_rules r USING(rule_key)
 WHERE u.expires_at>statement_timestamp() AND ((r.scope_kind='unit' AND u.scope_id=p_unit::text)
 OR (r.scope_kind='actor' AND u.scope_id=auth.uid()::text))),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_unit_abuse_policy_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_abuse_policy_v1(bigint) TO authenticated;

-- SOURCE: eshop_stripe/connections.sql
CREATE OR REPLACE FUNCTION public.check_stripe_unit_manager_internal(p_unit bigint,p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.units u JOIN public.unit_users uu ON uu.unit=u.id
  JOIN public.user_info i ON i.id=uu."user" AND i.organization=u.organization
  WHERE u.id=p_unit AND uu."user"=p_actor AND uu.is_manager) THEN
  RAISE insufficient_privilege USING MESSAGE='STRIPE_UNIT_MANAGER_REQUIRED'; END IF;
 IF public.is_demo_unit(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='DEMO_UNIT_READ_ONLY'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_stripe_unit_manager_internal(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.begin_stripe_connection_flow(p_unit bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE nonce text; flow uuid; org bigint; previous uuid; deadline timestamptz;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 SELECT organization INTO org FROM public.units WHERE id=p_unit FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eshop.stripe_disconnect_intents intent JOIN eshop.stripe_connections c ON c.id=intent.connection_id
  WHERE c.unit_id=p_unit AND c.livemode=p_livemode AND intent.state<>'completed') THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_PENDING'; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.connect',p_unit,org),
  jsonb_build_object('actor',auth.uid(),'unit',p_unit,'organization',org));
 SELECT id INTO previous FROM eshop.stripe_connections WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted');
 nonce:=encode(extensions.gen_random_bytes(32),'hex');
 deadline:=clock_timestamp()+interval '10 minutes';
 INSERT INTO eshop.stripe_connection_flows(state_hash,actor,organization_id,unit_id,livemode,previous_connection_id,expires_at)
 VALUES(encode(extensions.digest(nonce,'sha256'),'hex'),auth.uid(),org,p_unit,p_livemode,previous,deadline) RETURNING id INTO flow;
 RETURN jsonb_build_object('flowId',flow,'state',nonce,'expiresAt',deadline);
END $$;
REVOKE ALL ON FUNCTION public.begin_stripe_connection_flow(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.begin_stripe_connection_flow(bigint,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_stripe_connection_flow_internal(p_state text,p_actor uuid,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f eshop.stripe_connection_flows; lease uuid;
BEGIN
 PERFORM public.require_service_role();
 IF p_state IS NULL OR p_state !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 SELECT * INTO f FROM eshop.stripe_connection_flows WHERE state_hash=encode(extensions.digest(p_state,'sha256'),'hex')
  AND actor=p_actor AND livemode=p_livemode AND expires_at>clock_timestamp() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 PERFORM public.check_stripe_unit_manager_internal(f.unit_id,p_actor);
 IF NOT EXISTS(SELECT 1 FROM public.units WHERE id=f.unit_id AND organization=f.organization_id) THEN
  RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 IF f.state='completed' THEN RETURN jsonb_build_object('disposition','replay','result',f.result); END IF;
 IF f.state<>'pending' THEN RETURN jsonb_build_object('disposition','uncertain'); END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_connection_flows SET state='claimed',lease_token=lease WHERE id=f.id;
 RETURN jsonb_build_object('disposition','claimed','flowId',f.id,'lease',lease,'unitId',f.unit_id,'organizationId',f.organization_id);
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_connection_flow_internal(text,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_connection_flow_internal(text,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_stripe_connection_flow_internal(p_flow uuid,p_lease uuid,p_account jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f eshop.stripe_connection_flows; c eshop.stripe_connections; current_connection uuid; v_result jsonb;
 occasion_scope bigint; mutation uuid; members uuid[]; changed_forms jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO f FROM eshop.stripe_connection_flows WHERE id=p_flow AND state='claimed' AND lease_token=p_lease FOR UPDATE;
 IF NOT FOUND OR f.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 PERFORM public.check_stripe_unit_manager_internal(f.unit_id,f.actor);
 -- Checkout and form saves take form before unit. Keep that order while
 -- replacing future recipients; immutable attempts never participate here.
 IF f.previous_connection_id IS NOT NULL THEN
  PERFORM 1 FROM public.forms form JOIN public.occasions occasion ON occasion.id=form.occasion
   WHERE occasion.unit=f.unit_id AND occasion.organization=f.organization_id ORDER BY form.id FOR UPDATE OF form;
 END IF;
 PERFORM 1 FROM public.units WHERE id=f.unit_id AND organization=f.organization_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 IF p_account->>'accountId' IS NULL OR p_account->>'accountId' !~ '^acct_[A-Za-z0-9]+$'
  OR p_account->'modelVerified' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'STRIPE_ACCOUNT_MODEL_UNVERIFIED'; END IF;
 -- Serialize the global identity before checking ownership, without exposing another organizer.
 PERFORM pg_advisory_xact_lock(hashtextextended((p_account->>'accountId')||':'||f.livemode::text,7351));
 SELECT * INTO c FROM eshop.stripe_connections WHERE account_id=p_account->>'accountId' AND livemode=f.livemode FOR UPDATE;
 IF FOUND AND (c.unit_id<>f.unit_id OR c.organization_id<>f.organization_id) THEN RAISE EXCEPTION 'STRIPE_ACCOUNT_UNAVAILABLE'; END IF;
 SELECT id INTO current_connection FROM eshop.stripe_connections WHERE unit_id=f.unit_id AND livemode=f.livemode AND state IN ('connected','restricted') FOR UPDATE;
 IF current_connection IS DISTINCT FROM f.previous_connection_id AND current_connection IS DISTINCT FROM c.id THEN
  RAISE EXCEPTION 'STRIPE_CONNECTION_CHANGED'; END IF;
 IF current_connection IS NOT NULL AND current_connection IS DISTINCT FROM c.id THEN
  UPDATE eshop.stripe_connections SET state='retired',paused=true WHERE id=current_connection;
 END IF;
 IF c.id IS NULL THEN
  INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused)
  VALUES(f.organization_id,f.unit_id,p_account->>'accountId',f.livemode,'candidate',true) RETURNING * INTO c;
 END IF;
 UPDATE eshop.stripe_connections SET business_name=nullif(left(p_account->>'businessName',200),''),country=p_account->>'country',
  charges_enabled=coalesce((p_account->>'chargesEnabled')::boolean,false),payouts_enabled=coalesce((p_account->>'payoutsEnabled')::boolean,false),
  card_payments_active=coalesce((p_account->>'cardPaymentsActive')::boolean,false),model_verified=true,
  state=CASE WHEN p_account->'ready'='true'::jsonb THEN 'connected' ELSE 'restricted' END,
  checked_at=clock_timestamp(),next_check_at=clock_timestamp()+interval '15 minutes',status_failures=0,status_lease=NULL,status_lease_expires_at=NULL WHERE id=c.id;
 IF current_connection IS NOT NULL AND current_connection IS DISTINCT FROM c.id THEN
  FOR occasion_scope IN SELECT DISTINCT form.occasion FROM public.forms form JOIN public.occasions occasion ON occasion.id=form.occasion
   WHERE occasion.unit=f.unit_id AND occasion.organization=f.organization_id
    AND form.data#>>'{payments,stripeConnectionId}'=current_connection::text ORDER BY form.occasion LOOP
   mutation:=substr(encode(extensions.digest(f.id::text||':forms:'||occasion_scope::text,'sha256'),'hex'),1,32)::uuid;
   PERFORM public.begin_anonymous_client_mutation_v1(mutation,'inventory.form.stripe_recipient',occasion_scope,mutation,
    encode(extensions.digest(f.id::text||':'||c.id::text||':'||occasion_scope::text,'sha256'),'hex'));
   SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO members FROM public.occasion_users ou WHERE ou.occasion=occasion_scope;
   WITH updated AS (
    UPDATE public.forms SET data=jsonb_set(data,'{payments,stripeConnectionId}',to_jsonb(c.id::text)),updated_at=clock_timestamp()
     WHERE occasion=occasion_scope AND data#>>'{payments,stripeConnectionId}'=current_connection::text RETURNING id
   ), versions AS (
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
     SELECT 'form','occasion',occasion_scope,id::text,1 FROM updated
     ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
      SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp() RETURNING aggregate_id
   ) SELECT coalesce(jsonb_agg(jsonb_build_object('entityType','form','entityId',aggregate_id::bigint,'operation','update',
     'safeLabel','Card payment recipient','changedFields',jsonb_build_array('configuration'))),'[]'::jsonb) INTO changed_forms FROM versions;
   PERFORM public.complete_profile_inventory_membership_mutation_v1(mutation,occasion_scope,'inventory.form.stripe_recipient',
    changed_forms,members,jsonb_build_object('connectionId',c.id),'service');
  END LOOP;
 END IF;
 -- Existing card forms follow a verified replacement; bank-only forms and
 -- the tenant's payment switch are unchanged. New recipients remain paused.
 v_result:=jsonb_build_object('connectionId',c.id,'unitId',f.unit_id,'connected',true);
 UPDATE eshop.stripe_connection_flows SET state='completed',result=v_result WHERE id=f.id;
 INSERT INTO eshop.stripe_connection_audit(connection_id,flow_id,actor,action)
 VALUES(c.id,f.id,f.actor,CASE WHEN current_connection=c.id THEN 'reconnected' WHEN current_connection IS NOT NULL THEN 'replaced' ELSE 'connected' END);
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.complete_stripe_connection_flow_internal(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_stripe_connection_flow_internal(uuid,uuid,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.finish_stripe_connection_flow_error_internal(p_flow uuid,p_lease uuid,p_denied boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.stripe_connection_flows SET state=CASE WHEN p_denied THEN 'denied' ELSE 'uncertain' END
 WHERE id=p_flow AND lease_token=p_lease AND state='claimed';
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.finish_stripe_connection_flow_error_internal(uuid,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_stripe_connection_flow_error_internal(uuid,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.get_stripe_unit_connection(p_unit bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 SELECT jsonb_build_object('connectionId',id,'businessName',business_name,'country',country,'state',state,
  'paused',paused,'chargesEnabled',charges_enabled,'payoutsEnabled',payouts_enabled,'cardPaymentsActive',card_payments_active,
  'modelVerified',model_verified,'checkedAt',checked_at,'statusFailures',status_failures,
  'disconnectState',(SELECT state FROM eshop.stripe_disconnect_intents WHERE connection_id=eshop.stripe_connections.id AND state<>'completed'),
  'dashboardUrl','https://dashboard.stripe.com/'||account_id||CASE WHEN livemode THEN '' ELSE '/test' END||'/dashboard') INTO result FROM eshop.stripe_connections
 WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted','revoked')
 ORDER BY (state IN ('connected','restricted')) DESC,coalesce(checked_at,created_at) DESC LIMIT 1;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_unit_connection(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_stripe_unit_connection(bigint,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_stripe_unit_paused(p_unit bigint,p_livemode boolean,p_paused boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE conn uuid; prior_pause boolean; org bigint;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 IF p_paused IS NULL THEN RAISE EXCEPTION 'STRIPE_PAUSE_INVALID'; END IF;
 SELECT id,paused,organization_id INTO conn,prior_pause,org FROM eshop.stripe_connections WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CONNECTION_UNAVAILABLE'; END IF;
 IF NOT p_paused AND EXISTS(SELECT 1 FROM eshop.stripe_disconnect_intents WHERE connection_id=conn AND state<>'completed') THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_PENDING'; END IF;
 IF prior_pause=p_paused THEN RETURN; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.connect',p_unit,org),jsonb_build_object('actor',auth.uid(),'unit',p_unit,'organization',org));
 UPDATE eshop.stripe_connections SET paused=p_paused WHERE id=conn;
 INSERT INTO eshop.stripe_connection_audit(connection_id,actor,action) VALUES(conn,auth.uid(),CASE WHEN p_paused THEN 'paused' ELSE 'resumed' END);
END $$;
REVOKE ALL ON FUNCTION public.set_stripe_unit_paused(bigint,boolean,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.set_stripe_unit_paused(bigint,boolean,boolean) TO authenticated;

-- SOURCE: eshop_stripe/connection_status.sql
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

-- SOURCE: eshop_stripe/disconnect.sql
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
