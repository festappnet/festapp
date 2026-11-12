-- Runtime policy functions only. One-time schema/backfill belongs to frozen 20261112160000.
CREATE OR REPLACE FUNCTION public.resolve_payment_method_policy_internal(p_organization bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization) OR
  (p_unit IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_organization)) THEN
  RAISE EXCEPTION 'PAYMENT_POLICY_SCOPE_MISMATCH'; END IF;
 SELECT jsonb_build_object('organizationId',p_organization,'unitId',p_unit,'revision',coalesce(s.revision,0),
  'preferredMethod',coalesce(up.preferred_method,s.preferred_method),'methods',(
  SELECT jsonb_object_agg(p.provider_key,jsonb_build_object('id',p.provider_key,'supported',true,
   'policyEnabled',coalesce(op.enabled,p.provider_key='cash') AND coalesce(u.mode,'inherit')<>'disabled',
   'revision',coalesce(op.revision,0)::text||':'||coalesce(u.revision,0)::text,
   'organizationEnabled',coalesce(op.enabled,p.provider_key='cash'),'mode',coalesce(u.mode,'inherit'),
   'inheritedFrom',CASE WHEN coalesce(u.mode,'inherit')='inherit' THEN 'organization' ELSE 'unit' END,
   'reason',CASE WHEN NOT coalesce(op.enabled,p.provider_key='cash') THEN 'organization_disabled' WHEN u.mode='disabled' THEN 'unit_disabled' END))
  FROM eshop.payment_providers p LEFT JOIN eshop.organization_payment_method_policies op ON op.organization_id=p_organization AND op.method=p.provider_key
  LEFT JOIN eshop.unit_payment_method_policies u ON u.unit_id=p_unit AND u.method=p.provider_key)) INTO result
 FROM (SELECT 1) seed LEFT JOIN eshop.payment_method_policy_scopes s ON s.organization_id=p_organization
 LEFT JOIN eshop.payment_method_policy_unit_preferences up ON up.unit_id=p_unit;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.payment_method_policy_enabled_internal(p_unit bigint,p_method text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((public.resolve_payment_method_policy_internal(u.organization,u.id)#>>ARRAY['methods',p_method,'policyEnabled'])::boolean,false)
 FROM public.units u WHERE u.id=p_unit;
$$;
CREATE OR REPLACE FUNCTION public.payment_policy_fence_internal(p_organization bigint)
RETURNS void LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT pg_advisory_xact_lock_shared(hashtextextended('payment-policy:'||p_organization,0));
$$;
CREATE OR REPLACE FUNCTION public.can_manage_payment_method_policy(p_organization bigint,p_unit bigint DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND CASE WHEN p_unit IS NULL THEN public.can_manage_organization_settings(p_organization)
 ELSE EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_organization) AND public.get_is_manager_on_unit(p_unit)
 AND NOT public.is_demo_unit(p_unit) END;
$$;
CREATE OR REPLACE FUNCTION public.get_payment_method_policy(p_organization bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE policy jsonb; row record; method jsonb; configured boolean; ready boolean; reason text;
BEGIN
 IF NOT public.can_manage_payment_method_policy(p_organization,p_unit) THEN RAISE insufficient_privilege; END IF;
 policy:=public.resolve_payment_method_policy_internal(p_organization,p_unit);
 FOR row IN SELECT * FROM eshop.payment_providers ORDER BY provider_key LOOP
  method:=policy#>ARRAY['methods',row.provider_key]; configured:=false; ready:=false; reason:=method->>'reason';
  IF p_unit IS NOT NULL AND method->'policyEnabled'='true'::jsonb THEN
   IF row.provider_key='bank' THEN configured:=EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN eshop.bank_accounts b ON b.id=l.bank_account WHERE l.unit=p_unit AND b.type<>'CASH'); ready:=configured;
   ELSIF row.provider_key='cash' THEN configured:=true; ready:=true;
   ELSIF row.hosted_checkout THEN
    BEGIN configured:=jsonb_array_length(public.payment_provider_call_internal(row.provider_key,'setup_recipients',jsonb_build_object('unitId',p_unit)))>0;
     -- A configured recipient is not a claim about currency/surface/runtime sales readiness.
     ready:=false; reason:=CASE WHEN configured THEN 'sale_readiness_required' ELSE 'not_configured' END;
    EXCEPTION WHEN OTHERS THEN reason:='connector_unavailable'; END;
   END IF;
  END IF;
  policy:=jsonb_set(policy,ARRAY['methods',row.provider_key],method||jsonb_build_object('configured',configured,'ready',ready,
   'canConfigure',p_unit IS NOT NULL AND method->'policyEnabled'='true'::jsonb AND public.get_is_manager_on_unit(p_unit),
   'readinessReason',coalesce(reason,CASE WHEN NOT configured THEN 'not_configured' END)));
 END LOOP;
 RETURN policy;
END $$;
CREATE OR REPLACE FUNCTION public.preview_payment_method_policy(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE org bigint:=(input_data->>'organizationId')::bigint; un bigint:=(input_data->>'unitId')::bigint; impact jsonb; policy jsonb;
BEGIN
 IF NOT public.can_manage_payment_method_policy(org,un) THEN RAISE insufficient_privilege; END IF;
 policy:=public.resolve_payment_method_policy_internal(org,un);
 IF NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=input_data->>'method') THEN RAISE EXCEPTION 'PAYMENT_METHOD_UNKNOWN'; END IF;
 SELECT jsonb_build_object('openCollections',count(*) FILTER(WHERE o.state IN ('created','ordered') AND pi.amount>coalesce(pi.paid,0)),
 'issuedReferences',count(*) FILTER(WHERE pi.variable_symbol IS NOT NULL OR pi.creditor_reference IS NOT NULL),
 'obligations',count(*) FILTER(WHERE coalesce(pi.paid,0)>coalesce(pi.returned,0) OR pi.amount>coalesce(pi.paid,0)),
 'pendingBankInstructions',(SELECT count(*) FROM eshop.refund_requests r JOIN eshop.orders ro ON ro.id=r.order_id JOIN public.occasions rc ON rc.id=ro.occasion
 WHERE rc.organization=org AND (un IS NULL OR rc.unit=un) AND r.method=input_data->>'method' AND r.method='bank' AND r.status IN ('pending','processing','unknown')),
 'providerIntents',(SELECT jsonb_build_object('undispatched',count(*) FILTER(WHERE r.dispatched_at IS NULL AND r.status='pending'),
 'dispatched',count(*) FILTER(WHERE r.dispatched_at IS NOT NULL AND r.status='processing'),'unknown',count(*) FILTER(WHERE r.status='unknown'))
 FROM eshop.refund_requests r JOIN eshop.orders ro ON ro.id=r.order_id JOIN public.occasions rc ON rc.id=ro.occasion
 WHERE rc.organization=org AND (un IS NULL OR rc.unit=un) AND r.method=input_data->>'method' AND public.payment_method_is_online_internal(r.method)),
 'pendingRequests',(SELECT count(*) FROM eshop.refund_requests r JOIN eshop.orders ro ON ro.id=r.order_id JOIN public.occasions rc ON rc.id=ro.occasion
 WHERE rc.organization=org AND (un IS NULL OR rc.unit=un) AND r.method=input_data->>'method' AND r.status IN ('pending','processing','unknown')))
 INTO impact FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=o.payment_info
 WHERE oc.organization=org AND (un IS NULL OR oc.unit=un) AND pi.payment_method=input_data->>'method';
 RETURN jsonb_build_object('revision',policy->'revision','impact',impact,'confirmation',encode(extensions.digest(
  jsonb_build_object('input',input_data,'revision',policy->'revision','impact',impact)::text,'sha256'),'hex'));
END $$;
CREATE OR REPLACE FUNCTION public.command_payment_method_policy(input_data jsonb,p_command_id uuid,p_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE org bigint:=(input_data->>'organizationId')::bigint; un bigint:=(input_data->>'unitId')::bigint; prior eshop.payment_method_policy_commands;
 preview jsonb; response jsonb; v_method text:=input_data->>'method'; v_mode text:=input_data->>'mode';
BEGIN
 -- Authority is checked even for a previously successful command.
 IF NOT public.can_manage_payment_method_policy(org,un) THEN RAISE insufficient_privilege; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('payment-policy:'||org,0));
 SELECT * INTO prior FROM eshop.payment_method_policy_commands WHERE id=p_command_id;
 IF FOUND THEN
  IF prior.actor IS DISTINCT FROM auth.uid() OR prior.input IS DISTINCT FROM input_data THEN RAISE EXCEPTION 'PAYMENT_POLICY_COMMAND_CONFLICT'; END IF;
  RETURN prior.response;
 END IF;
 preview:=public.preview_payment_method_policy(input_data);
 IF p_confirmation IS DISTINCT FROM preview->>'confirmation' THEN RAISE EXCEPTION 'PAYMENT_POLICY_PREVIEW_STALE'; END IF;
 IF v_mode IS NULL OR v_mode NOT IN ('enabled','disabled','inherit') OR (un IS NULL AND v_mode='inherit') THEN RAISE EXCEPTION 'PAYMENT_POLICY_MODE_INVALID'; END IF;
 IF un IS NULL THEN
  INSERT INTO eshop.organization_payment_method_policies(organization_id,method,enabled) VALUES(org,v_method,v_mode='enabled') ON CONFLICT(organization_id,method) DO UPDATE SET enabled=excluded.enabled,revision=eshop.organization_payment_method_policies.revision+1;
 ELSE
  INSERT INTO eshop.unit_payment_method_policies(unit_id,method,mode) VALUES(un,v_method,v_mode) ON CONFLICT(unit_id,method) DO UPDATE SET mode=excluded.mode,revision=eshop.unit_payment_method_policies.revision+1;
 END IF;
 INSERT INTO eshop.payment_method_policy_scopes(organization_id,revision) VALUES(org,1)
 ON CONFLICT(organization_id) DO UPDATE SET revision=eshop.payment_method_policy_scopes.revision+1;
 IF input_data ? 'preferredMethod' THEN
  IF NOT coalesce((public.resolve_payment_method_policy_internal(org,un)#>>ARRAY['methods',input_data->>'preferredMethod','policyEnabled'])::boolean,false) THEN
   RAISE EXCEPTION 'PAYMENT_POLICY_PREFERENCE_DISABLED'; END IF;
  IF un IS NULL THEN UPDATE eshop.payment_method_policy_scopes SET preferred_method=input_data->>'preferredMethod' WHERE organization_id=org;
  ELSE INSERT INTO eshop.payment_method_policy_unit_preferences VALUES(un,input_data->>'preferredMethod') ON CONFLICT(unit_id) DO UPDATE SET preferred_method=excluded.preferred_method; END IF;
 END IF;
 response:=public.resolve_payment_method_policy_internal(org,un);
 INSERT INTO eshop.payment_method_policy_commands(id,organization_id,actor,input,response) VALUES(p_command_id,org,auth.uid(),input_data,response);
 RETURN response;
END $$;
REVOKE ALL ON FUNCTION public.resolve_payment_method_policy_internal(bigint,bigint),public.payment_method_policy_enabled_internal(bigint,text),
 public.payment_policy_fence_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.can_manage_payment_method_policy(bigint,bigint),public.get_payment_method_policy(bigint,bigint),
 public.preview_payment_method_policy(jsonb),public.command_payment_method_policy(jsonb,uuid,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_payment_method_policy(bigint,bigint),public.get_payment_method_policy(bigint,bigint),
 public.preview_payment_method_policy(jsonb),public.command_payment_method_policy(jsonb,uuid,text) TO authenticated;

-- Bank authoring never borrows a disabled scope or an unrelated account role.
CREATE OR REPLACE FUNCTION public.require_bank_authoring_scope_internal(p_account bigint,p_unit bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE scope_unit bigint; scope_org bigint;
BEGIN
 SELECT u.id,u.organization INTO scope_unit,scope_org FROM public.units u
 WHERE (p_unit IS NULL OR u.id=p_unit) AND public.get_is_manager_on_unit(u.id)
 AND public.payment_method_policy_enabled_internal(u.id,'bank')
 AND (p_account IS NULL OR EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=u.id AND l.bank_account=p_account))
 ORDER BY u.id LIMIT 1;
 IF scope_unit IS NULL THEN RAISE insufficient_privilege USING MESSAGE='PAYMENT_BANK_SCOPE_UNAVAILABLE'; END IF;
 PERFORM public.payment_policy_fence_internal(scope_org);
 IF NOT public.payment_method_policy_enabled_internal(scope_unit,'bank') THEN RAISE insufficient_privilege USING MESSAGE='PAYMENT_METHOD_POLICY_DISABLED'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.require_bank_authoring_scope_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
