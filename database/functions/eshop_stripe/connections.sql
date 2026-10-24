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
