-- Payment policy integrated with current canonical main; no money rewrite or connector activation.

-- SOURCE: payment_providers/operation_support.sql
-- Installed implementation support is separate from the runtime write switch.
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS refund_write_supported boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS partial_refund_supported boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS refund_observation_supported boolean NOT NULL DEFAULT false;
UPDATE eshop.payment_providers SET refund_write_supported=true,partial_refund_supported=true,refund_observation_supported=true
 WHERE provider_key IN ('bank','cash','stripe');
UPDATE eshop.payment_providers SET refund_observation_supported=true WHERE provider_key='barion';

-- SOURCE: payment_providers/method_policy.sql
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
   'policyEnabled',coalesce(op.enabled,false) AND coalesce(u.mode,'inherit')<>'disabled',
   'revision',coalesce(op.revision,0)::text||':'||coalesce(u.revision,0)::text,
   'organizationEnabled',coalesce(op.enabled,false),'mode',coalesce(u.mode,'inherit'),
   'inheritedFrom',CASE WHEN coalesce(u.mode,'inherit')='inherit' THEN 'organization' ELSE 'unit' END,
   'reason',CASE WHEN NOT coalesce(op.enabled,false) THEN 'organization_disabled' WHEN u.mode='disabled' THEN 'unit_disabled' END))
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

-- SOURCE: payment_providers/registry.sql
-- One typed SQL entrypoint for connector-owned persistence and financial facts.
-- The handler identifier is read from a migration-owned table and quoted from
-- pg_catalog; all business inputs are passed as bound parameters.
CREATE OR REPLACE FUNCTION public.payment_provider_call_internal(p_provider text,p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE handler_name name; result jsonb; policy_unit bigint; policy_org bigint;
BEGIN
 IF p_operation IN ('form_availability','initialize_payment','validate_form','setup_recipients','form_editor_fields','unit_fields','unit_feature') THEN
  IF p_args ? 'formId' THEN SELECT oc.unit,oc.organization INTO policy_unit,policy_org FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=(p_args->>'formId')::bigint;
  ELSIF p_args ? 'unitId' THEN SELECT id,organization INTO policy_unit,policy_org FROM public.units WHERE id=(p_args->>'unitId')::bigint;
  END IF;
  IF policy_unit IS NOT NULL AND NOT coalesce(public.payment_method_policy_enabled_internal(policy_unit,p_provider),false) THEN
   IF p_operation='form_availability' THEN RETURN jsonb_build_object('providerId',p_provider,'configured',false,'available',false,'recipient',NULL,'supportedSurfaces','[]'::jsonb,
    'reason',jsonb_build_object('code',public.resolve_payment_method_policy_internal(policy_org,policy_unit)#>>ARRAY['methods',p_provider,'reason']));
   ELSIF p_operation='setup_recipients' THEN RETURN '[]'::jsonb;
   ELSIF p_operation='unit_feature' THEN RETURN 'false'::jsonb;
   ELSIF p_operation IN ('form_editor_fields','unit_fields') THEN RETURN '{}'::jsonb;
   ELSE RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
  END IF;
 END IF;
 SELECT f.proname INTO handler_name FROM eshop.payment_providers r
 JOIN pg_catalog.pg_proc f ON f.oid=r.handler
 JOIN pg_catalog.pg_namespace n ON n.oid=f.pronamespace
 WHERE r.provider_key=p_provider AND n.nspname='public'
  AND f.proargtypes='25 3802'::oidvector AND f.prorettype='jsonb'::regtype;
 IF handler_name IS NULL THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_UNAVAILABLE'; END IF;
 EXECUTE format('SELECT public.%I($1,$2)',handler_name) INTO result USING p_operation,p_args;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.payment_method_registered_internal(p_method text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=p_method);
$$;
CREATE OR REPLACE FUNCTION public.payment_method_is_online_internal(p_method text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT hosted_checkout FROM eshop.payment_providers WHERE provider_key=p_method),false);
$$;
REVOKE ALL ON FUNCTION public.payment_method_is_online_internal(text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.strip_payment_sources_internal(p_input jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_input-coalesce((SELECT array_agg(source_field) FROM eshop.payment_providers WHERE source_field IS NOT NULL),'{}'::text[]);
$$;
CREATE OR REPLACE FUNCTION public.provider_order_payment_projection_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE method text; result jsonb;
BEGIN
 SELECT p.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
 IF NOT public.payment_method_is_online_internal(method) THEN RETURN NULL; END IF;
 result:=public.payment_provider_call_internal(method,'projection',jsonb_build_object('orderId',p_order));
 IF result->>'method' IS DISTINCT FROM method THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_IDENTITY_MISMATCH'; END IF;
 IF public.payment_collection_action_internal(p_order)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN result:=result||jsonb_build_object('allowedActions','["refresh"]'::jsonb); END IF;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.attach_provider_order_source_internal(p_order bigint,p_command uuid,p_input jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE method text; field text;
BEGIN
 SELECT p.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
 IF NOT public.payment_method_is_online_internal(method) THEN RETURN; END IF;
 SELECT source_field INTO STRICT field FROM eshop.payment_providers WHERE provider_key=method;
 PERFORM public.payment_provider_call_internal(method,'attach_source',jsonb_build_object('orderId',p_order,'commandId',p_command,'source',p_input->field));
END $$;
CREATE OR REPLACE FUNCTION public.provider_ticket_requires_online_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
 JOIN eshop.payment_info p ON p.id=o.payment_info WHERE x.ticket=p_ticket AND public.payment_method_is_online_internal(p.payment_method));
$$;
CREATE OR REPLACE FUNCTION public.provider_ticket_admission_allowed_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
 JOIN eshop.payment_info p ON p.id=o.payment_info WHERE x.ticket=p_ticket AND public.payment_method_is_online_internal(p.payment_method)
 AND public.provider_order_payment_projection_internal(o.id)->>'admissionState' IS DISTINCT FROM 'valid');
$$;
CREATE OR REPLACE FUNCTION public.provider_paid_guard_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE method text;
BEGIN
 SELECT p.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
 IF NOT public.payment_method_is_online_internal(method) THEN RETURN NULL; END IF;
 RETURN public.payment_provider_call_internal(method,'paid_guard',jsonb_build_object('orderId',p_order));
END $$;
CREATE OR REPLACE FUNCTION public.provider_payment_movements_internal(p_payment bigint)
RETURNS TABLE(kind text,amount_minor bigint,currency text,occurred_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE method text; rows jsonb;
BEGIN
 SELECT p.payment_method INTO method FROM eshop.payment_info p WHERE p.id=p_payment;
 IF NOT public.payment_method_is_online_internal(method) THEN RETURN; END IF;
 rows:=public.payment_provider_call_internal(method,'movements',jsonb_build_object('paymentId',p_payment));
 RETURN QUERY SELECT * FROM jsonb_to_recordset(rows) AS x(kind text,amount_minor bigint,currency text,occurred_at timestamptz);
END $$;
CREATE OR REPLACE FUNCTION public.payment_provider_connection_internal(p_config jsonb,p_provider text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE field text; legacy text; modern text;
BEGIN
 SELECT legacy_connection_field INTO field FROM eshop.payment_providers WHERE provider_key=p_provider;
 legacy:=nullif(p_config->>field,'');modern:=nullif(p_config#>>ARRAY['providerConnections',p_provider],'');
 IF legacy IS NOT NULL AND modern IS NOT NULL AND legacy<>modern THEN RAISE EXCEPTION 'PAYMENT_RECIPIENT_CONFLICT'; END IF;
 RETURN coalesce(modern,legacy)::uuid;
END $$;
CREATE OR REPLACE FUNCTION public.strip_form_payment_connections_internal(p_metadata jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_metadata ? 'payments' THEN jsonb_set(p_metadata,'{payments}',
  (p_metadata->'payments')-'providerConnections'-coalesce((SELECT array_agg(legacy_connection_field) FROM eshop.payment_providers WHERE legacy_connection_field IS NOT NULL),'{}'::text[])) ELSE p_metadata END;
$$;
CREATE OR REPLACE FUNCTION public.provider_unit_features_internal(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; result jsonb:='{}'; current jsonb;
BEGIN
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE hosted_checkout ORDER BY provider_key LOOP
  BEGIN
   current:=public.payment_provider_call_internal(r.provider_key,'unit_feature',jsonb_build_object('unitId',p_unit));
   IF jsonb_typeof(current) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_PROJECTION_INVALID'; END IF;
  EXCEPTION WHEN OTHERS THEN current:='false'; END;
  result:=result||jsonb_build_object(r.provider_key,current);
 END LOOP;
 RETURN result;
END $$;
-- Provider fields cannot overwrite common or another provider's namespace.
CREATE OR REPLACE FUNCTION public.provider_unit_public_fields_internal(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; fields jsonb:='{}'; current jsonb; features jsonb;
BEGIN
 features:=public.provider_unit_features_internal(p_unit);
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE hosted_checkout ORDER BY provider_key LOOP
  BEGIN
   current:=public.payment_provider_call_internal(r.provider_key,'unit_fields',jsonb_build_object('unitId',p_unit));
   IF jsonb_typeof(current) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_PROJECTION_INVALID'; END IF;
  EXCEPTION WHEN OTHERS THEN current:='{"available":false,"reason":{"code":"provider_unavailable"}}'; END;
  fields:=fields||jsonb_build_object(r.provider_key,current);
 END LOOP;
 RETURN jsonb_build_object('payment_method_policy',(SELECT public.resolve_payment_method_policy_internal(organization,id) FROM public.units WHERE id=p_unit),'payment_providers',features,'providerFields',fields)
  ||CASE WHEN fields ? 'stripe' THEN jsonb_build_object('stripe_preview_enabled',fields#>'{stripe,stripe_preview_enabled}') ELSE '{}'::jsonb END;
END $$;
CREATE OR REPLACE FUNCTION public.payment_sale_policy_internal()
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT '{"reservationSeconds":1860,"fullPaymentOnly":true,"depositsSupported":false,"surchargesSupported":false}'::jsonb;
$$;
CREATE OR REPLACE FUNCTION public.form_payment_availability_internal(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; current jsonb; providers jsonb:='{}'; available jsonb:='[]'; config jsonb; bank boolean; cash boolean; configured boolean; enabled boolean; collection_ready boolean; template_audit jsonb; form_unit bigint; form_occasion bigint;
BEGIN
 SELECT f.data->'payments',oc.unit,oc.id INTO config,form_unit,form_occasion FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=p_form;
 IF form_occasion IS NOT NULL THEN template_audit:=public.payment_template_audit_internal(form_occasion); END IF;
 current:=public.payment_provider_call_internal('bank','form_availability',jsonb_build_object('formId',p_form));
 bank:=coalesce((current->>'available')::boolean,false);
 current:=public.payment_provider_call_internal('cash','form_availability',jsonb_build_object('formId',p_form));
 cash:=coalesce((current->>'available')::boolean,false);
 IF bank THEN available:=available||jsonb_build_array('bank'); END IF;
 IF cash THEN available:=available||jsonb_build_array('cash'); END IF;
 FOR r IN SELECT provider_key,legacy_connection_field FROM eshop.payment_providers WHERE hosted_checkout ORDER BY provider_key LOOP
  configured:=nullif(config#>>ARRAY['providerConnections',r.provider_key],'') IS NOT NULL OR nullif(config->>r.legacy_connection_field,'') IS NOT NULL;
  BEGIN
   PERFORM public.payment_provider_connection_internal(config,r.provider_key);
   current:=public.payment_provider_call_internal(r.provider_key,'form_availability',jsonb_build_object('formId',p_form));
   IF jsonb_typeof(current) IS DISTINCT FROM 'object' OR current->>'providerId' IS DISTINCT FROM r.provider_key
    OR jsonb_typeof(current->'available') IS DISTINCT FROM 'boolean' OR jsonb_typeof(current->'configured') IS DISTINCT FROM 'boolean'
    OR jsonb_typeof(current->'supportedSurfaces') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_PROJECTION_INVALID'; END IF;
   enabled:=configured AND current->'available'='true'::jsonb AND current->'configured'='true'::jsonb;
   -- Public sale discovery may intentionally be closed for an operator-only
   -- sandbox. Its connector must explicitly attest its private collection gate.
   collection_ready:=configured AND current->'configured'='true'::jsonb AND coalesce(current->'collectionAvailable',current->'available')='true'::jsonb;
   IF template_audit->'compatible' IS DISTINCT FROM 'true'::jsonb OR
    (NOT coalesce(public.payment_method_policy_enabled_internal(form_unit,'bank'),false) AND template_audit->'reviewed' IS DISTINCT FROM 'true'::jsonb) THEN
    enabled:=false; collection_ready:=false; current:=current||jsonb_build_object('reason',jsonb_build_object('code','payment_template_review_required'));
   END IF;
   current:=current||jsonb_build_object('available',enabled,'collectionAvailable',coalesce(collection_ready,false),'configured',configured,'policy',public.payment_sale_policy_internal());
  EXCEPTION WHEN OTHERS THEN
   current:=jsonb_build_object('providerId',r.provider_key,'configured',configured,'available',false,
    'reason',jsonb_build_object('code',CASE WHEN configured THEN 'provider_unavailable' ELSE 'not_configured' END),
    'supportedSurfaces','[]'::jsonb,'recipient',NULL,'policy',public.payment_sale_policy_internal());
   enabled:=false; collection_ready:=false;
   current:=current||jsonb_build_object('collectionAvailable',false);
  END;
  providers:=providers||jsonb_build_object(r.provider_key,current);
  IF enabled THEN available:=available||jsonb_build_array(r.provider_key); END IF;
 END LOOP;
 -- Only this Stripe compatibility boundary projects released mobile root fields.
 RETURN jsonb_build_object('cash',jsonb_build_object('configured',coalesce(cash,false),'available',coalesce(cash,false),'instructions',config->>'cashInstructions'), 'deadlinePolicy',public.resolve_form_payment_policy_internal(p_form,CASE WHEN cash THEN 'cash' ELSE 'bank' END), 'bank',jsonb_build_object('configured',bank,'available',bank),'available',available,'providers',providers,
  'policy',public.payment_sale_policy_internal(),'reservationSeconds',public.payment_sale_policy_internal()->'reservationSeconds',
  'configured',jsonb_build_object('bank',bank,'stripe',coalesce(providers#>'{stripe,configured}','false')),
  'stripeUnavailableReason',providers#>'{stripe,reason,code}','recipient',providers#>'{stripe,recipient}',
  'supportedSurfaces',coalesce(providers#>'{stripe,supportedSurfaces}','[]'));
END $$;
CREATE OR REPLACE FUNCTION public.validate_form_payment_configuration_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; config jsonb; connections jsonb; entry record;
BEGIN
 SELECT data->'payments' INTO config FROM public.forms WHERE id=p_form;
 IF config IS NULL THEN RETURN; END IF;
 IF jsonb_typeof(config)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(config) k
  WHERE k NOT IN ('bankEnabled','providerConnections','cashEnabled','cashInstructions') AND NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE legacy_connection_field=k))
  OR (config ? 'bankEnabled' AND jsonb_typeof(config->'bankEnabled')<>'boolean') THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 config:=public.merge_form_payments_internal(config,NULL);
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=p_form AND (
  (config->'bankEnabled'='true'::jsonb AND NOT public.payment_method_policy_enabled_internal(oc.unit,'bank')) OR
  (config->'cashEnabled'='true'::jsonb AND NOT public.payment_method_policy_enabled_internal(oc.unit,'cash')))) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
 IF config->'cashEnabled'='true'::jsonb AND EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
   JOIN eshop.external_services e ON e.unit=o.unit AND e.type='FAKTUROID' WHERE f.id=p_form) THEN
  RAISE EXCEPTION 'CASH_FAKTUROID_UNSUPPORTED: Cash reservations cannot use mandatory Fakturoid invoicing'; END IF;
 PERFORM public.resolve_form_payment_policy_internal(p_form,CASE WHEN config->'cashEnabled'='true'::jsonb THEN 'cash' ELSE 'bank' END);
 connections:=coalesce(config->'providerConnections','{}'::jsonb);
 IF jsonb_typeof(connections)<>'object' THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 FOR entry IN SELECT * FROM jsonb_each(connections) LOOP
  IF jsonb_typeof(entry.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=entry.key AND hosted_checkout) THEN
   RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  PERFORM (entry.value#>>'{}')::uuid;
 END LOOP;
 IF config->'bankEnabled'='false'::jsonb AND config->'cashEnabled'<>'true'::jsonb
  AND NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE hosted_checkout AND public.payment_provider_connection_internal(config,provider_key) IS NOT NULL)
  AND EXISTS(SELECT 1 FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id JOIN eshop.products p ON p.product_type=ff.product_type
   WHERE f.id=p_form AND f.is_open AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false) AND p.price>0) THEN
  RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INCOMPLETE'; END IF;
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id JOIN eshop.products p ON p.product_type=ff.product_type
  WHERE f.id=p_form AND f.is_open AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false) AND p.price>0)
  AND jsonb_array_length(public.form_payment_availability_internal(p_form)->'available')=0 THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INCOMPLETE'; END IF;
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE hosted_checkout LOOP
  IF public.payment_provider_connection_internal(config,r.provider_key) IS NOT NULL THEN
   PERFORM public.payment_provider_call_internal(r.provider_key,'validate_form',jsonb_build_object('formId',p_form));
  END IF;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.provider_form_editor_fields_internal(p_unit bigint,p_occasion bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; fields jsonb:='{}'; current jsonb;
BEGIN
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE hosted_checkout ORDER BY provider_key LOOP
  BEGIN
   current:=public.payment_provider_call_internal(r.provider_key,'form_editor_fields',jsonb_build_object('unitId',p_unit,'occasionId',p_occasion,'livemode',p_livemode));
   IF jsonb_typeof(current) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_PROJECTION_INVALID'; END IF;
  EXCEPTION WHEN OTHERS THEN current:='{"available":false,"reason":{"code":"provider_unavailable"}}'; END;
  fields:=fields||jsonb_build_object(r.provider_key,current);
 END LOOP;
 RETURN jsonb_build_object('providerEditorFields',fields,'policy',public.payment_sale_policy_internal())
  ||CASE WHEN fields ? 'stripe' THEN jsonb_build_object('stripeRecipient',fields#>'{stripe,stripeRecipient}') ELSE '{}'::jsonb END;
END $$;
REVOKE ALL ON FUNCTION public.payment_sale_policy_internal() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.payment_provider_call_internal(text,text,jsonb),public.payment_method_registered_internal(text),
 public.strip_payment_sources_internal(jsonb),public.provider_order_payment_projection_internal(bigint),
 public.attach_provider_order_source_internal(bigint,uuid,jsonb),public.provider_ticket_requires_online_internal(bigint),
 public.provider_ticket_admission_allowed_internal(bigint),public.provider_paid_guard_internal(bigint),
 public.provider_payment_movements_internal(bigint),public.form_payment_availability_internal(bigint),
 public.payment_provider_connection_internal(jsonb,text),public.strip_form_payment_connections_internal(jsonb),
 public.provider_unit_public_fields_internal(bigint),public.provider_unit_features_internal(bigint),public.validate_form_payment_configuration_internal(bigint),public.provider_form_editor_fields_internal(bigint,bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Verification semantics are installed capabilities, never provider-name tests.
CREATE OR REPLACE FUNCTION public.payment_method_verification_internal(p_method text)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT verification FROM eshop.payment_providers WHERE provider_key=p_method;
$$;
REVOKE ALL ON FUNCTION public.payment_method_verification_internal(text) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: payment_providers/configuration.sql
-- Canonical bank/provider snapshot, with a bounded released Stripe-only writer.
CREATE OR REPLACE FUNCTION public.merge_form_payments_internal(p_saved jsonb,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE saved jsonb:=coalesce(nullif(p_saved,'null'),'{}'); incoming jsonb; connections jsonb; r record; legacy text; modern text;
BEGIN
 IF jsonb_typeof(saved)<>'object' THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 connections:=coalesce(saved->'providerConnections','{}');
 FOR r IN SELECT provider_key,legacy_connection_field FROM eshop.payment_providers WHERE legacy_connection_field IS NOT NULL LOOP
  legacy:=nullif(saved->>r.legacy_connection_field,'');modern:=connections->>r.provider_key;
  IF legacy IS NOT NULL AND modern IS NOT NULL AND legacy<>modern THEN RAISE EXCEPTION 'PAYMENT_RECIPIENT_CONFLICT'; END IF;
  IF legacy IS NOT NULL THEN connections:=connections||jsonb_build_object(r.provider_key,legacy); END IF;
  saved:=saved-r.legacy_connection_field;
 END LOOP;
 saved:=saved||jsonb_build_object('bankEnabled',coalesce(saved->'bankEnabled','false'),'providerConnections',connections,'cashEnabled',coalesce(saved->'cashEnabled','false'),'cashInstructions',coalesce(saved->'cashInstructions','""'::jsonb));
 IF p_input IS NULL THEN p_input:=saved; END IF;
 -- SQL NULL normalizes saved data; explicit JSON null resets inheritance.
 incoming:=CASE WHEN p_input='null'::jsonb THEN '{"bankEnabled":false,"providerConnections":{},"cashEnabled":false,"cashInstructions":""}'::jsonb ELSE p_input END;
 IF incoming->'cashEnabled'='null'::jsonb THEN incoming:=jsonb_set(incoming,'{cashEnabled}','false'); END IF;
 IF incoming->'cashInstructions'='null'::jsonb THEN incoming:=jsonb_set(incoming,'{cashInstructions}','""'); END IF;
 IF incoming->'bankEnabled'='null'::jsonb THEN incoming:=jsonb_set(incoming,'{bankEnabled}','false'); END IF;
 IF jsonb_typeof(incoming)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(incoming) k WHERE k NOT IN ('bankEnabled','providerConnections','stripeConnectionId','cashEnabled','cashInstructions'))
  OR (incoming ? 'bankEnabled' AND jsonb_typeof(incoming->'bankEnabled')<>'boolean') THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 IF incoming ? 'providerConnections' THEN
  connections:=coalesce(nullif(incoming->'providerConnections','null'::jsonb),'{}'::jsonb);
  IF jsonb_typeof(connections) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  IF incoming ? 'stripeConnectionId' AND incoming->>'stripeConnectionId' IS DISTINCT FROM connections->>'stripe' THEN RAISE EXCEPTION 'PAYMENT_RECIPIENT_CONFLICT'; END IF;
 ELSE
  -- A present legacy object owns Stripe only. Removing it never unbinds another provider.
  connections:=connections-'stripe';
  IF incoming->>'stripeConnectionId' IS NOT NULL THEN connections:=connections||jsonb_build_object('stripe',incoming->>'stripeConnectionId'); END IF;
 END IF;
 FOR r IN SELECT * FROM jsonb_each(connections) LOOP
  IF jsonb_typeof(r.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=r.key AND hosted_checkout) THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  PERFORM (r.value#>>'{}')::uuid;
 END LOOP;
 saved:=jsonb_build_object('bankEnabled',coalesce(incoming->'bankEnabled',saved->'bankEnabled'),'providerConnections',connections,
  'cashEnabled',coalesce(incoming->'cashEnabled',saved->'cashEnabled','false'),
  'cashInstructions',coalesce(incoming->'cashInstructions',saved->'cashInstructions','""'::jsonb));
 IF jsonb_typeof(saved->'cashEnabled')<>'boolean' OR jsonb_typeof(saved->'cashInstructions')<>'string'
  OR length(saved->>'cashInstructions')>1000 THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 IF saved->'cashEnabled'='true'::jsonb AND (saved->'bankEnabled'<>'false'::jsonb OR connections<>'{}'::jsonb) THEN
  RAISE EXCEPTION 'CASH_PAYMENT_COMBINATION_UNSUPPORTED'; END IF;
 RETURN saved;
END $$;
-- Legacy draft translation uses saved recipient evidence, never a registry default.
CREATE OR REPLACE FUNCTION public.normalize_setup_payments_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE config jsonb; method text:=p_data->>'paymentMethod'; result jsonb:=p_data-'paymentMethod'; connections jsonb;
BEGIN
 config:=public.merge_form_payments_internal(coalesce(p_data->'payments',p_data#>'{formDraft,data,payments}'),NULL);
 IF method IS NOT NULL THEN
  IF method='cash' THEN config:='{"bankEnabled":false,"cashEnabled":true,"providerConnections":{}}';
  ELSIF method='bank' THEN config:='{"bankEnabled":true,"providerConnections":{}}';
  ELSE
   connections:=config->'providerConnections';
   IF method<>'both' THEN connections:=CASE WHEN connections ? method THEN jsonb_build_object(method,connections->method) ELSE '{}'::jsonb END; END IF;
   config:=jsonb_build_object('bankEnabled',method='both','providerConnections',connections);
   IF connections='{}'::jsonb THEN result:=result||'{"paymentRepairRequired":true}'::jsonb; END IF;
  END IF;
 END IF;
 RETURN result||jsonb_build_object('payments',config);
END $$;
REVOKE ALL ON FUNCTION public.merge_form_payments_internal(jsonb,jsonb),public.normalize_setup_payments_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Setup authors may read eligible recipients without receiving connection-management rights.
CREATE OR REPLACE FUNCTION public.get_setup_payment_options(p_draft uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; r record; recipients jsonb; result jsonb:='{}';
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_draft;
 IF d.id IS NULL OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit)
  OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=d.organization) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE hosted_checkout ORDER BY provider_key LOOP
  BEGIN
   recipients:=public.payment_provider_call_internal(r.provider_key,'setup_recipients',jsonb_build_object('unitId',d.unit));
   IF jsonb_typeof(recipients) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_PROJECTION_INVALID'; END IF;
  EXCEPTION WHEN OTHERS THEN recipients:='[]'; END;
  result:=result||jsonb_build_object(r.provider_key,recipients);
 END LOOP;
 RETURN jsonb_build_object('providerRecipients',result,'policy',public.payment_sale_policy_internal());
END $$;
REVOKE ALL ON FUNCTION public.get_setup_payment_options(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_setup_payment_options(uuid) TO authenticated;

-- SOURCE: payment_providers/operation_contexts.sql
-- Private read assembly. Prepared permissions never come from a client or live
-- beyond this invocation; mutation entrypoints re-authorize stored scopes.
CREATE OR REPLACE FUNCTION public.payment_method_contexts_internal(p_orders bigint[])
RETURNS TABLE(order_id bigint,context jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE selected_orders bigint[]; payments bigint[]; financials jsonb; permissions jsonb; refunds jsonb;
 providers eshop.payment_providers[]; online_methods text[]; fences bigint[]; entry record;
 o eshop.orders; pi eshop.payment_info; r eshop.payment_providers; fin jsonb; permission jsonb;
 refund_data jsonb; policy_data jsonb; policy jsonb; caps jsonb; methods jsonb; requests jsonb; pending numeric; is_online boolean;
BEGIN
 SELECT array_agg(ord.id),array_agg(DISTINCT pay.id) INTO selected_orders,payments
 FROM eshop.orders ord JOIN eshop.payment_info pay ON pay.id=ord.payment_info WHERE ord.id=ANY(p_orders);
 IF selected_orders IS NULL THEN RETURN; END IF;
 SELECT jsonb_object_agg(s.id,public.resolve_payment_method_policy_internal(s.organization,s.id)) INTO policy_data
 FROM (SELECT DISTINCT u.id,u.organization FROM public.units u JOIN public.occasions oc ON oc.unit=u.id JOIN eshop.orders ord ON ord.occasion=oc.id WHERE ord.id=ANY(selected_orders)) s;

 SELECT jsonb_object_agg(f.payment_id,to_jsonb(f)) INTO financials
 FROM public.payment_financial_totals_bulk_internal(payments) f;
 SELECT jsonb_object_agg(p.order_id,to_jsonb(p)) INTO permissions
 FROM public.payment_operation_permissions_internal(selected_orders) p;
 SELECT array_agg(p ORDER BY p.provider_key),array_agg(p.provider_key) FILTER(WHERE p.hosted_checkout)
 INTO providers,online_methods FROM eshop.payment_providers p;
 SELECT coalesce(array_agg(f.order_id),'{}') INTO fences FROM eshop.order_deletion_fences f WHERE f.order_id=ANY(selected_orders);

 -- Load requests and their settlement facts once, including reservations that
 -- have not changed the actual ledger. Instructions remain permission-filtered.
 SELECT jsonb_object_agg(summary.payment_info,summary.data) INTO refunds FROM (
  SELECT rr.payment_info,jsonb_build_object(
   'pending',coalesce(sum(rr.amount) FILTER(WHERE rr.status IN ('pending','processing','unknown')),0),
   'review',coalesce(bool_or(rr.result->'deviation'='true'::jsonb),false),
   'requests',jsonb_agg(to_jsonb(rr)||jsonb_build_object('verification',p.verification,
    'hasSettlement',EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.request_id=rr.id AND s.voided_at IS NULL),
    'transactionId',(SELECT s.transaction_id FROM eshop.refund_settlements s WHERE s.request_id=rr.id LIMIT 1)) ORDER BY rr.created_at)
  ) data
  FROM eshop.refund_requests rr JOIN eshop.payment_providers p ON p.provider_key=rr.method
  WHERE rr.payment_info=ANY(payments) GROUP BY rr.payment_info
 ) summary;

 FOR entry IN SELECT ord AS order_row,pay AS payment_row FROM eshop.orders ord
  JOIN eshop.payment_info pay ON pay.id=ord.payment_info WHERE ord.id=ANY(selected_orders)
 LOOP
  o:=entry.order_row; pi:=entry.payment_row;
  fin:=financials->pi.id::text;
  SELECT policy_data->oc.unit::text INTO policy FROM public.occasions oc WHERE oc.id=o.occasion;
  permission:=coalesce(permissions->o.id::text,
   '{"can_record_cash":false,"can_refund_bank":false,"can_refund_provider":false}'::jsonb);
  refund_data:=refunds->pi.id::text; pending:=coalesce((refund_data->>'pending')::numeric,0);
  methods:='[]'; is_online:=coalesce(pi.payment_method=ANY(online_methods),false);
  FOREACH r IN ARRAY providers LOOP
   IF NOT ((NOT is_online AND NOT r.hosted_checkout) OR r.provider_key=pi.payment_method) THEN CONTINUE; END IF;
   caps:=public.payment_provider_call_internal(r.provider_key,'operation_capabilities',
    jsonb_build_object('orderId',o.id,'permissions',permission));
   IF NOT r.refund_write_supported THEN caps:=caps||jsonb_build_object('refund',false,'reason','unsupported_operation');
   ELSIF NOT r.refund_write_enabled THEN caps:=caps||jsonb_build_object('refund',false,'reason','connector_write_disabled'); END IF;
   caps:=caps||jsonb_build_object('refundWriteSupported',r.refund_write_supported,'partialRefundSupported',r.partial_refund_supported,'refundObservationSupported',r.refund_observation_supported);
   IF NOT r.hosted_checkout AND policy#>ARRAY['methods',r.provider_key,'policyEnabled'] IS DISTINCT FROM 'true'::jsonb THEN
    caps:=caps||jsonb_build_object('refund',false,'record',false,'instructions',false,'visible',false,'reason',policy#>>ARRAY['methods',r.provider_key,'reason']);
   END IF;
   caps:=caps||jsonb_build_object('method',r.provider_key,'purpose',CASE WHEN r.verification='bank_event' THEN 'bank_refund_instruction' ELSE 'refund' END,
    'policyRevision',policy->'revision');
   IF NOT r.partial_refund_supported AND greatest((fin->>'available')::numeric-pending,0)<(fin->>'net_received')::numeric THEN caps:=caps||jsonb_build_object('refund',false,'reason','full_refund_amount_unavailable'); END IF;
   IF r.hosted_checkout AND NOT (permission->>'can_refund_provider')::boolean THEN caps:=caps||jsonb_build_object('refund',false); END IF;
   IF caps->>'id' IS DISTINCT FROM r.provider_key THEN RAISE EXCEPTION 'PAYMENT_CAPABILITY_IDENTITY_MISMATCH'; END IF;
   IF o.id=ANY(fences) THEN caps:=caps||jsonb_build_object('refund',false,'record',false,'instructions',false,'reason','order_deletion_in_progress'); END IF;
   IF refund_data->'review'='true'::jsonb THEN caps:=caps||jsonb_build_object('refund',false,'instructions',false,'reason','refund_requires_review'); END IF;
   IF o.state NOT IN ('created','ordered','paid','sent','storno','expired') OR (fin->>'invalid_identity')::boolean OR (fin->>'net_received')::numeric<0 THEN
    caps:=caps||jsonb_build_object('refund',false,'instructions',false,'reason','payment_identity_or_state_unavailable'); END IF;
   IF o.state IN ('storno','expired','waiting','preparing') THEN caps:=caps||jsonb_build_object('record',false); END IF;
   methods:=methods||jsonb_build_array(caps);
  END LOOP;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',req->'id','method',req->'method','verification',req->'verification',
   'amount',req->>'amount','currency',req->'currency','status',req->'status','createdAt',req->'created_at',
   'instructions',CASE WHEN req->>'verification'='bank_event' AND req->>'status'='pending' AND req->'hasSettlement'='false'::jsonb AND NOT is_online AND policy#>'{methods,bank,policyEnabled}'='true'::jsonb AND (permission->>'can_refund_bank')::boolean THEN req#>'{payload,instructions}' END,
   'purpose',CASE WHEN req->>'verification'='bank_event' THEN 'bank_refund_instruction' ELSE 'refund' END,
   'sourceOrderId',o.id,'sourcePaymentId',pi.id,'sourceMethod',pi.payment_method,
   'instructionAllowed',req->>'verification'='bank_event' AND req->>'status'='pending' AND req->'hasSettlement'='false'::jsonb AND NOT is_online AND policy#>'{methods,bank,policyEnabled}'='true'::jsonb AND (permission->>'can_refund_bank')::boolean,
   'canReopen',CASE WHEN req->>'verification'='bank_event' THEN req->>'status'='pending' AND req->'hasSettlement'='false'::jsonb AND NOT is_online AND policy#>'{methods,bank,policyEnabled}'='true'::jsonb AND (permission->>'can_refund_bank')::boolean ELSE (permission->>'can_refund_provider')::boolean END,
   'canCancel',req->>'verification'='bank_event' AND req->>'status'='pending' AND (permission->>'can_refund_bank')::boolean,
   'canCorrect',NOT is_online AND (permission->>'can_record_cash')::boolean AND req->>'verification'='local_commit' AND req->>'status'='succeeded' AND (req->>'hasSettlement')::boolean,
   'transactionId',req->'transactionId') ORDER BY ordinal),'[]') INTO requests
  FROM jsonb_array_elements(coalesce(refund_data->'requests','[]')) WITH ORDINALITY items(req,ordinal);
  order_id:=o.id;
  context:=jsonb_build_object('sourceOrderId',o.id,'sourcePaymentId',pi.id,'sourceMethod',pi.payment_method,'gross',fin->>'gross_received','refunded',fin->>'refunded','net',fin->>'net_received',
   'pending',pending::text,'available',greatest((fin->>'available')::numeric-pending,0)::text,'currency',trim(pi.currency_code),
   'methods',methods,'requests',requests,'invalidIdentity',(fin->>'invalid_identity')::boolean,
   'due',greatest(coalesce(o.price,0)-(fin->>'net_received')::numeric,0)::text,'deposit',pi.deposit_amount);
  RETURN NEXT;
 END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_method_contexts_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: payment_providers/operations.sql
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

-- SOURCE: eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
<<checkout>>
DECLARE
    result JSONB;
    selected_payment_options jsonb;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    assigned_order_sequence BIGINT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    v_ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    form_blueprint BIGINT;
    selected_spots BIGINT[];
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
    v_payment_method text;
    v_payment_instructions jsonb;
    v_provider_payment jsonb;
    v_payment_policy jsonb;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid)]);
    PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(coalesce(input_data->'ticket','[]')) t WHERE t->>'spot' IS NOT NULL));
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence']
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        IF jsonb_typeof(input_data->'ticket') = 'array' AND
            jsonb_array_length(input_data->'ticket') > public.ticket_order_limit() THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1023,
                'message', 'Maximum number of tickets per order exceeded',
                'limit', public.ticket_order_limit())::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.forms f
          JOIN public.occasions oc ON oc.id=f.occasion WHERE f.key=form_key;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open, blueprint
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val, form_blueprint
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.can_write_orders(occasion_id);

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF unit_id IS NULL THEN RAISE EXCEPTION 'PAYMENT_POLICY_SCOPE_MISMATCH'; END IF;
        PERFORM public.resolve_payment_method_policy_internal(organization_id,unit_id);

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        input_data:=jsonb_set(input_data,'{ticket}',public.normalize_form_ticket_answers_internal(form_id,input_data->'ticket'));

        SELECT id,order_symbol,order_sequence INTO order_id,assigned_order_symbol,assigned_order_sequence
        FROM eshop.orders WHERE id=p_target_order AND form=form_id FOR UPDATE;
        IF order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=order_id AND (NOT p_offer OR product IS NOT NULL)) THEN
          RAISE EXCEPTION 'Invalid finalization target'; END IF;
        IF NOT p_offer AND (SELECT participant_capacity IS NOT NULL FROM public.forms WHERE id=form_id)
           AND jsonb_array_length(input_data->'ticket') >
           (public.get_form_capacity_snapshot_internal(form_id)->>'remainingPublic')::bigint THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','FORM_CAPACITY_EXCEEDED',
            'capacity',public.get_form_capacity_snapshot_internal(form_id))::text; END IF;
        PERFORM public.lock_ticket_order_products_internal(order_id,input_data);
        SELECT coalesce(array_agg((t->>'spot')::bigint),'{}') INTO selected_spots
        FROM jsonb_array_elements(input_data->'ticket') t WHERE t->>'spot' IS NOT NULL;
        IF cardinality(selected_spots)<>(SELECT count(DISTINCT id) FROM unnest(selected_spots) id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',1007,'message','Duplicate spot')::text; END IF;
        -- Admission locks product/inventory parents before any seat row. The
        -- occasion scope is acquired by every caller before form/order parents.
        PERFORM 1 FROM eshop.spots WHERE id=ANY(selected_spots) ORDER BY id FOR UPDATE;
        now:=clock_timestamp();
        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS NOT TRUE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Identity is explicit: offers reuse the waiting ticket; checkout creates it.
        FOR ticket_data IN SELECT * FROM jsonb_array_elements(input_data->'ticket') LOOP
            SELECT value->>'note' INTO ticket_note FROM jsonb_array_elements(coalesce(ticket_data->'fields','[]'))
              WHERE value ? 'note' LIMIT 1;
            v_ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            IF p_offer THEN
              ticket_id:=(ticket_data->>'ticketId')::bigint;
              UPDATE eshop.tickets t SET state='ordered',ticket_symbol=v_ticket_symbol,
                note=ticket_note,data=public.extract_ticket_answers_internal(form_id,ticket_data),updated_at=now
              WHERE t.id=ticket_id AND t.state='waitlisted' AND t.ticket_symbol IS NULL
                AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=order_id AND x.product IS NULL)
                AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots x WHERE x.ticket_id=t.id AND x.outcome='accepted');
              IF NOT FOUND THEN RAISE EXCEPTION 'Invalid waiting ticket finalization'; END IF;
              DELETE FROM eshop.order_product_ticket WHERE "order"=order_id AND ticket=ticket_id AND product IS NULL;
            ELSE
              IF ticket_data ? 'ticketId' THEN RAISE EXCEPTION 'Ticket identity is server assigned'; END IF;
              INSERT INTO eshop.tickets (state,occasion,ticket_symbol,note,data,created_at,updated_at)
              VALUES('ordered',occasion_id,v_ticket_symbol,ticket_note,public.extract_ticket_answers_internal(form_id,ticket_data),now,now) RETURNING id INTO ticket_id;
            END IF;
            result:=public.materialize_ticket_products_internal_v1(order_id,form_id,ticket_id,ticket_data,(input_data->>'secret')::uuid);
            IF first_currency_code IS NULL THEN first_currency_code:=result->>'currency_code';
            ELSIF first_currency_code IS DISTINCT FROM result->>'currency_code' THEN
              RAISE EXCEPTION '%',jsonb_build_object('code',1014,'message','Products in the order must have the same currency',
                'expected_currency',first_currency_code,'actual_currency',result->>'currency_code')::text;
            END IF;
            calculated_price:=calculated_price+(result->>'price')::numeric;
            v_total_deposit:=v_total_deposit+(result->>'deposit')::numeric;
            IF result->>'spot' IS NOT NULL THEN used_spots:=used_spots||jsonb_build_array((result->>'spot')::bigint); END IF;
            ticket_details:=ticket_details||jsonb_build_object('id',ticket_id,'ticket_symbol',v_ticket_symbol,
              'note',ticket_note,'products',result->'products');
        END LOOP;

        order_data := public.strip_payment_sources_internal(input_data) - 'ticket' || JSONB_BUILD_OBJECT('tickets', public.order_tickets_with_seating_internal(order_id, ticket_details));

        v_payment_method:=input_data->>'payment_method';
        IF v_payment_method IS NULL THEN
          IF calculated_price=0 THEN
            -- Released no-money registration rows retain their bank-shaped storage
            -- identity only. No bank service, account, reference or action is issued.
            v_payment_method:=CASE WHEN form_data#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' ELSE 'bank' END;
          ELSE
            selected_payment_options:=public.form_payment_availability_internal(form_id)->'available';
            IF jsonb_array_length(selected_payment_options)<>1 THEN RAISE EXCEPTION 'PAYMENT_METHOD_REQUIRED'; END IF;
            v_payment_method:=selected_payment_options->>0;
          END IF;
        END IF;
        IF NOT public.payment_method_registered_internal(v_payment_method) THEN RAISE EXCEPTION 'PAYMENT_METHOD_INVALID'; END IF;
        -- Selection exclusivity applies to free orders too; repricing must retain
        -- a method that the form actually offered. Online readiness and recipient
        -- changes remain owned by the provider's locked initialization below.
        IF coalesce(form_data#>'{payments,cashEnabled}'='true'::jsonb,false)
             IS DISTINCT FROM (v_payment_method='cash') THEN
          RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
        v_payment_policy:=public.resolve_form_payment_policy_internal(form_id,v_payment_method);
        PERFORM public.check_payment_client_capabilities_internal(v_payment_policy,v_payment_method,input_data->'client_capabilities');
        IF calculated_price>0 AND NOT public.payment_method_is_online_internal(v_payment_method)
          AND NOT (public.form_payment_availability_internal(form_id)->'available' ? v_payment_method) THEN
          RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
        IF v_payment_method='cash' THEN v_total_deposit:=0; END IF;
        IF calculated_price=0 THEN
          IF public.payment_method_is_online_internal(v_payment_method) THEN
            IF public.payment_provider_connection_internal(form_data->'payments',v_payment_method) IS NULL THEN RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
            -- A selected hosted method still needs no provider identity for a
            -- no-money registration. Reuse the bounded released storage shape.
            v_payment_method:='bank';
          END IF;
          bank_account_id:=NULL;
          INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method) VALUES(0,first_currency_code,now,v_payment_method) RETURNING id INTO payment_info_id;
        ELSE
          v_provider_payment:=public.payment_provider_call_internal(v_payment_method,'initialize_payment',jsonb_build_object(
            'formId',form_id,'input',input_data,'amount',calculated_price,'currency',first_currency_code,'deposit',v_total_deposit,'createdAt',now));
          payment_info_id:=(v_provider_payment->>'paymentInfoId')::bigint;
          IF payment_info_id IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.payment_info provider_payment
            WHERE provider_payment.id=payment_info_id AND provider_payment.payment_method=v_payment_method
              AND provider_payment.amount=calculated_price AND provider_payment.currency_code=first_currency_code) THEN
            RAISE EXCEPTION 'PAYMENT_PROVIDER_PREPARATION_INVALID'; END IF;
          bank_account_id:=NULL;
        END IF;

        -- The locked connector first validates its original recipient identity,
        -- preserving the released stale-recipient rejection. Full configuration
        -- validation still runs before the order/attempt commits; failure rolls
        -- back the local preparation and never dispatches a remote request.
        PERFORM public.validate_form_payment_configuration_internal(form_id);

        UPDATE eshop.payment_info SET data=coalesce(data,'{}')||jsonb_build_object('no_money_registration',calculated_price=0,'payment_policy',v_payment_policy-'durationSeconds') WHERE id=payment_info_id;
        PERFORM public.notification_center_prepared_invalidate_order(order_id);
        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        v_payment_instructions:=public.ensure_order_payment_instructions_internal(order_id);
        bank_account_id:=(v_payment_instructions->>'bank_account')::bigint;
        generated_variable_symbol:=(v_payment_instructions->>'variable_symbol')::bigint;
        generated_creditor_reference:=v_payment_instructions->>'creditor_reference';
        account_number:=v_payment_instructions->>'account_number';
        account_number_human_readable:=v_payment_instructions->>'account_number_human_readable';
        creditor_name:=v_payment_instructions->>'creditor_name';

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          IF public.payment_method_is_online_internal(v_payment_method) THEN
              v_provider_payment:=public.payment_provider_call_internal(v_payment_method,'create_attempt',jsonb_build_object('orderId',order_id));
              deadline:=(v_provider_payment->>'expiresAt')::timestamptz;
              IF deadline IS NULL THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_DEADLINE_INVALID'; END IF;
          ELSIF v_payment_policy->>'mode'='custom' THEN
              deadline:=now+make_interval(secs=>(v_payment_policy->>'durationSeconds')::bigint);
              UPDATE eshop.payment_info SET deadline=checkout.deadline WHERE id=payment_info_id;
              PERFORM public.queue_payment_reminders_internal(occasion_id,payment_info_id);
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 AND v_payment_policy->>'mode'<>'none' THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- One queue boundary resolves form and occasion reminder settings.
                    PERFORM public.queue_payment_reminders_internal(occasion_id,payment_info_id);
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details,'payment_policy',v_payment_policy-'durationSeconds'),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=form_id;
        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'payment',public.customer_order_payment_internal(order_id),
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'payment_method',v_payment_method,
                    'data',jsonb_build_object('payment_policy',v_payment_policy-'durationSeconds'),
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN SQLERRM = 'STRIPE_RECIPIENT_CHANGED' THEN
                JSONB_BUILD_OBJECT('code',409,'errorCode','STRIPE_RECIPIENT_CHANGED',
                    'message','The payment recipient changed. Review the current form.')
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    PERFORM public.notification_center_order_capacity_internal(order_id);
    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop_orders/ensure_order_payment_instructions.sql
-- One owner for issuing payment instructions, at checkout and on repricing.
-- The authorized caller owns its transaction; no provider charge is dispatched.
CREATE OR REPLACE FUNCTION public.ensure_order_payment_instructions_internal(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE o eshop.orders; pi eshop.payment_info; f public.forms;
 account eshop.bank_accounts; receiving_account bigint; unit_id bigint; org_id bigint;
 form_data jsonb; symbol bigint; reference text; recipient text;
BEGIN
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 IF NOT public.payment_method_registered_internal(pi.payment_method) OR pi.payment_method IS NULL THEN
   RAISE EXCEPTION 'PAYMENT_METHOD_INVALID'; END IF;
 IF pi.amount IS DISTINCT FROM o.price OR pi.currency_code IS DISTINCT FROM o.currency_code THEN
   RAISE EXCEPTION 'PAYMENT_ORDER_AMOUNT_MISMATCH'; END IF;
 IF pi.payment_method<>'bank' AND (pi.bank_account IS NOT NULL
   OR pi.variable_symbol IS NOT NULL OR pi.creditor_reference IS NOT NULL) THEN
   RAISE EXCEPTION 'STRIPE_BANK_INSTRUCTIONS_FORBIDDEN'; END IF;
 -- Stripe creates references/attempts through its provider lifecycle. Bank
 -- instructions must never be fabricated for a card payment or a free order.
 IF pi.amount>0 AND pi.amount>coalesce(pi.paid,0)-coalesce(pi.returned,0) AND pi.payment_method='bank' THEN
   SELECT * INTO STRICT f FROM public.forms WHERE id=o.form;
   SELECT unit,organization INTO unit_id,org_id FROM public.occasions WHERE id=o.occasion;
   IF NOT coalesce(public.payment_method_policy_enabled_internal(unit_id,'bank'),false) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
   IF pi.bank_account IS NULL THEN
     IF pi.variable_symbol IS NOT NULL OR pi.creditor_reference IS NOT NULL THEN
       RAISE EXCEPTION 'PAYMENT_RECIPIENT_REQUIRED'; END IF;
     form_data:=public.get_effective_form_data(f.id);
     IF coalesce(form_data#>'{payments,bankEnabled}','false'::jsonb)<>'true'::jsonb THEN
       RAISE EXCEPTION 'BANK_PAYMENT_NOT_CONFIGURED'; END IF;
     SELECT b.id INTO receiving_account
     FROM eshop.unit_bank_accounts uba JOIN eshop.bank_accounts b ON b.id=uba.bank_account
     WHERE uba.unit=unit_id AND (f.bank_account IS NULL OR b.id=f.bank_account)
       AND b.supported_currencies @> ARRAY[trim(pi.currency_code)]
       AND b.type IS DISTINCT FROM 'CASH'
     ORDER BY uba.priority ASC,b.id ASC LIMIT 1;
     IF receiving_account IS NULL THEN
       RAISE EXCEPTION '%',jsonb_build_object('code',1018,
         'message','No available bank account supports the required currency',
         'required_currency',pi.currency_code)::text;
     END IF;
     UPDATE eshop.payment_info SET bank_account=receiving_account WHERE id=pi.id;
     pi.bank_account:=receiving_account;
   END IF;
   SELECT * INTO STRICT account FROM eshop.bank_accounts WHERE id=pi.bank_account FOR SHARE;
   -- Existing references retain their receiving account across price changes.
   IF pi.variable_symbol IS NULL THEN
     IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba
       WHERE uba.unit=unit_id AND uba.bank_account=account.id)
       OR NOT account.supported_currencies @> ARRAY[trim(pi.currency_code)]
       OR account.type='CASH' THEN
       RAISE EXCEPTION 'BANK_PAYMENT_NOT_CONFIGURED'; END IF;
     IF public.payment_reference_scope_enabled_internal(f.id) THEN
       symbol:=public.reserve_order_payment_reference_internal(pi.id,f.id);
     ELSE
       symbol:=public.generate_payment_variable_symbol(account.id,f.id);
     END IF;
     UPDATE eshop.payment_info SET variable_symbol=symbol WHERE id=pi.id;
     pi.variable_symbol:=symbol;
   END IF;
   recipient:=nullif(trim(account.creditor_name),'');
   IF trim(pi.currency_code)='EUR' THEN
     IF recipient IS NULL THEN
       SELECT left(trim(regexp_replace(title,'[[:space:][:cntrl:]]+',' ','g')),70)
       INTO recipient FROM public.organizations WHERE id=org_id;
     END IF;
     IF recipient IS NULL OR length(recipient) NOT BETWEEN 1 AND 70 THEN
       RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED'; END IF;
     IF account.account_number IS NULL OR NOT public.is_valid_iban(account.account_number) THEN
       RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED'; END IF;
     IF pi.creditor_reference IS NULL THEN
       reference:=public.generate_creditor_reference(pi.variable_symbol);
       UPDATE eshop.payment_info SET creditor_reference=reference WHERE id=pi.id;
       pi.creditor_reference:=reference;
     END IF;
   END IF;
 ELSIF pi.bank_account IS NOT NULL THEN
   SELECT * INTO account FROM eshop.bank_accounts WHERE id=pi.bank_account;
   recipient:=account.creditor_name;
 END IF;
 RETURN jsonb_build_object('bank_account',pi.bank_account,
   'account_number',account.account_number,'account_number_human_readable',account.account_number_human_readable,
   'creditor_name',recipient,'variable_symbol',pi.variable_symbol,'creditor_reference',pi.creditor_reference);
END;
$$;
REVOKE ALL ON FUNCTION public.ensure_order_payment_instructions_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_order_payment_instructions_internal(bigint) TO postgres,service_role;

-- SOURCE: eshop_transactions/add_transaction_to_payment_info_ws.sql
CREATE OR REPLACE FUNCTION public.add_transaction_to_payment_info_ws(
    p_transaction_id bigint,
    p_payment_info_id bigint
)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    bank_acc bigint;
    occasion_id bigint;
BEGIN
    -- Retrieve the associated order_id from payment_info
    SELECT pi.bank_account INTO bank_acc
    FROM eshop.payment_info pi
    WHERE pi.id = p_payment_info_id
    LIMIT 1;

    IF NOT public.can_manage_bank_account(bank_acc) THEN
    RAISE insufficient_privilege USING MESSAGE='Bank transaction write access denied'; END IF;

    IF NOT public.can_manage_bank_account((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id)) THEN
      RAISE insufficient_privilege USING MESSAGE='Source bank transaction write access denied'; END IF;

    SELECT o.occasion
    INTO occasion_id
    FROM eshop.orders o
    WHERE o.payment_info = p_payment_info_id
    LIMIT 1;

    PERFORM public.check_is_editor_order_on_occasion(occasion_id);
  PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=occasion_id;
  IF NOT coalesce((SELECT public.payment_method_policy_enabled_internal(oc.unit,'bank') FROM public.occasions oc WHERE oc.id=occasion_id),false) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;

    PERFORM public.apply_transaction_pairing(
      p_transaction_id, p_payment_info_id, 'manual_attach', 'user'
    );

    -- Return success message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Transaction added successfully.'
    );

END;
$$ LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION public.add_transaction_to_payment_info_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.add_transaction_to_payment_info_ws(bigint,bigint)
  TO authenticated;

-- SOURCE: eshop_transactions/remove_transaction_from_payment_info_ws.sql
CREATE OR REPLACE FUNCTION public.remove_transaction_from_payment_info_ws(
  p_transaction_id bigint,
  p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bank_account_id bigint;
  v_occasion_id bigint;
BEGIN
  SELECT pi.bank_account, o.occasion INTO v_bank_account_id, v_occasion_id
  FROM eshop.payment_info pi
  JOIN eshop.orders o ON o.payment_info = pi.id
  WHERE pi.id = p_payment_info_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_INFO_NOT_FOUND'; END IF;
  IF NOT public.can_manage_bank_account(v_bank_account_id) THEN
    RAISE insufficient_privilege USING MESSAGE='Bank transaction write access denied'; END IF;
  IF NOT public.can_manage_bank_account((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id)) THEN
    RAISE insufficient_privilege USING MESSAGE='Source bank transaction write access denied'; END IF;
  PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);
  PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=v_occasion_id;
  IF NOT coalesce((SELECT public.payment_method_policy_enabled_internal(oc.unit,'bank') FROM public.occasions oc WHERE oc.id=v_occasion_id),false) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM eshop.transactions t
    WHERE t.id = p_transaction_id AND t.payment_info = p_payment_info_id) THEN
    RAISE EXCEPTION 'TRANSACTION_PAIRING_MISMATCH';
  END IF;
  PERFORM public.apply_transaction_pairing(
    p_transaction_id, NULL, 'manual_unlink', 'user'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.remove_transaction_from_payment_info_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.remove_transaction_from_payment_info_ws(bigint,bigint)
  TO authenticated;

-- SOURCE: eshop_transactions/get_transactions_for_order.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id bigint; bank_allowed boolean; payment_context jsonb; provider_rows jsonb:='[]'; provider_complete boolean:=true; method text; movement jsonb;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT can_read_orders(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  SELECT pi.payment_method='bank' AND public.payment_method_policy_enabled_internal(oc.unit,'bank') INTO bank_allowed
  FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=order_id;
  payment_context:=public.payment_method_context_internal(order_id);
  SELECT pi.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=order_id;
  IF public.payment_method_is_online_internal(method) THEN
   BEGIN
    SELECT public.payment_provider_call_internal(method,'movements',jsonb_build_object('paymentId',o.payment_info)) INTO movement FROM eshop.orders o WHERE o.id=order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('source','provider','sourceId',m->>'sourceId','provider',method,
     'date',m->'occurred_at','amount',CASE WHEN m->>'kind'='dispute' THEN NULL ELSE CASE WHEN m->>'kind'='refund' THEN -1 ELSE 1 END*(m->>'amount_minor')::numeric/100 END,
     'heldAmount',CASE WHEN m->>'kind'='dispute' THEN (m->>'amount_minor')::numeric/100 END,'status',m->>'status',
     'currency',m->>'currency','transaction_type',m->>'kind','isRefund',m->>'kind'='refund','voided',false)), '[]')
    INTO provider_rows FROM jsonb_array_elements(movement) m;
    provider_complete:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(movement) m WHERE nullif(m->>'sourceId','') IS NULL);
   EXCEPTION WHEN OTHERS THEN provider_complete:=false; END;
  ELSIF method NOT IN ('bank','cash') OR method IS NULL THEN provider_complete:=false;
  END IF;
  RETURN (
    SELECT jsonb_build_object(
      'order_state', o.state,'ledgerComplete',provider_complete,
      'paymentOperations',payment_context,
      'actions', jsonb_build_object(
        'canAddCash', EXISTS(SELECT 1 FROM jsonb_array_elements(payment_context->'methods') m WHERE m->>'id'='cash' AND m->'record'='true'::jsonb),
        'canConfigureBank', bank_allowed AND public.can_manage_unit_bank_accounts(oc.unit),
        'showBankSetup',bank_allowed AND public.can_manage_unit_bank_accounts(oc.unit),
        'showBankAccess',bank_allowed AND NOT public.can_manage_unit_bank_accounts(oc.unit),
        'bankState', CASE WHEN NOT bank_allowed THEN 'disabled' WHEN NOT public.can_read_unit_bank_accounts(oc.unit) THEN 'restricted'
          WHEN EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN eshop.bank_accounts b ON b.id=l.bank_account
            WHERE l.unit=oc.unit AND upper(b.type)<>'CASH') THEN 'configured' ELSE 'absent' END,
        'pairingAccountId', CASE WHEN bank_allowed AND pi.payment_method='bank' AND public.can_manage_bank_account(pi.bank_account)
          AND public.can_write_orders(o.occasion) AND o.state IN ('created','ordered','paid','sent') THEN pi.bank_account END,
        'unitId', oc.unit,
        'removableTransactionIds', (SELECT coalesce(jsonb_agg(t.id),'[]')
          FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
          WHERE t.payment_info=o.payment_info AND o.state IN ('created','ordered','paid','sent')
          AND NOT public.payment_method_is_online_internal(pi.payment_method)
          AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id)
          AND NOT EXISTS(SELECT 1 FROM eshop.transaction_pairing_events e WHERE e.transaction_snapshot_id=t.id AND e.method='exact_cash_correction')
          AND CASE WHEN t.transaction_type='manual' THEN upper(b.type)='CASH'
            AND public.can_manage_unit_bank_accounts(oc.unit) AND EXISTS(
              SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=oc.unit AND l.bank_account=b.id)
            ELSE bank_allowed AND public.can_write_orders(o.occasion) AND public.can_manage_bank_account(b.id) END)
      ),
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', COALESCE((
        SELECT jsonb_agg(
            to_jsonb(t) || jsonb_build_object('source',CASE WHEN t.ingest_source='manual' THEN 'cash' ELSE 'bank' END,'sourceId','transaction:'||t.id,'isRefund',m.is_refund,'voided',m.voided,'createdByName',
                trim(both from COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, ''))
            )
        )
        FROM eshop.transactions t
        JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id
        LEFT JOIN public.user_info ui ON t.created_by = ui.id
        WHERE t.payment_info = o.payment_info
      ), '[]'::jsonb)||provider_rows
    )
    FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id = order_id
  );
END;
$$;

-- SOURCE: payment_providers/refund_dispatch.sql
-- Service-only leased dispatch. A response never manufactures financial facts.
CREATE OR REPLACE FUNCTION public.claim_payment_refund(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r eshop.refund_requests; binding jsonb; token uuid; was_dispatched boolean;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=p_request;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[r.order_id]);
 PERFORM 1 FROM eshop.payment_info WHERE id=r.payment_info FOR UPDATE;
 SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=p_request FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=r.method AND hosted_checkout AND (refund_write_supported AND refund_write_enabled OR r.dispatched_at IS NOT NULL)) OR r.status NOT IN ('pending','processing','unknown') THEN RETURN jsonb_build_object('disposition','read'); END IF;
 IF r.lease_until>clock_timestamp() THEN RETURN jsonb_build_object('disposition','busy'); END IF;
 binding:=public.payment_provider_call_internal(r.method,'refund_binding',jsonb_build_object('orderId',r.order_id));
 IF binding IS NULL OR binding IS DISTINCT FROM r.payload->'binding' THEN RAISE EXCEPTION 'REFUND_BINDING_CHANGED'; END IF;
 IF r.provider_refund_id IS NOT NULL AND public.payment_provider_call_internal(r.method,'refund_observed',
  jsonb_build_object('requestId',r.id,'orderId',r.order_id,'refundId',r.provider_refund_id))='true'::jsonb THEN
  UPDATE eshop.refund_requests SET status='succeeded',updated_at=now() WHERE id=r.id;
  PERFORM public.record_payment_fact_sync_internal(r.order_id);
  RETURN jsonb_build_object('disposition','read');
 END IF;
 token:=extensions.gen_random_uuid();was_dispatched:=r.dispatched_at IS NOT NULL;
 UPDATE eshop.refund_requests SET lease_token=token,lease_until=clock_timestamp()+interval '90 seconds',
  dispatched_at=coalesce(dispatched_at,clock_timestamp()),status='processing',updated_at=now() WHERE id=r.id;
 RETURN jsonb_build_object('requestId',r.id,'providerId',r.method,'lease',token,'priorDispatched',was_dispatched,
  'connectorState',coalesce(r.result->'connectorState','{}')||jsonb_strip_nulls(jsonb_build_object('refundId',r.provider_refund_id)),
  'snapshot',binding||jsonb_build_object('requestId',r.id,'providerId',r.method,'amountMinor',(r.amount*100)::bigint,
    'currency',r.currency,'createdAt',floor(extract(epoch FROM r.created_at))::bigint,'idempotencyKey','festapp-refund-'||r.id));
END $$;
CREATE OR REPLACE FUNCTION public.complete_payment_refund(p_request uuid,p_lease uuid,p_result jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r eshop.refund_requests; v_status text; observed boolean;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=p_request;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[r.order_id]);
 PERFORM 1 FROM eshop.payment_info WHERE id=r.payment_info FOR UPDATE;
 SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=p_request FOR UPDATE;
 IF p_lease IS NULL OR r.lease_token IS NULL OR r.lease_until IS NULL OR r.lease_token IS DISTINCT FROM p_lease OR r.lease_until<clock_timestamp() OR NOT public.payment_method_is_online_internal(r.method) THEN RAISE EXCEPTION 'REFUND_LEASE_LOST'; END IF;
 IF p_result->>'status' NOT IN ('pending','action_required','succeeded','failed','cancelled','unknown') OR p_result->>'status' IS NULL THEN RAISE EXCEPTION 'REFUND_RESULT_INVALID'; END IF;
 IF r.provider_refund_id IS NOT NULL AND p_result->>'refundId' IS NOT NULL AND r.provider_refund_id<>p_result->>'refundId' THEN RAISE EXCEPTION 'REFUND_IDENTITY_CONFLICT'; END IF;
 observed:=public.payment_provider_call_internal(r.method,'refund_observed',jsonb_build_object('requestId',r.id,'orderId',r.order_id,'refundId',coalesce(r.provider_refund_id,p_result->>'refundId')))='true'::jsonb;
 v_status:=CASE WHEN observed THEN 'succeeded' WHEN p_result->'dispatchUncertain'='true'::jsonb THEN 'unknown'
  WHEN p_result->>'status' IN ('failed','cancelled') THEN p_result->>'status' ELSE 'pending' END;
 UPDATE eshop.refund_requests SET status=v_status,provider_refund_id=coalesce(provider_refund_id,p_result->>'refundId'),result=p_result,
  lease_token=NULL,lease_until=NULL,updated_at=now() WHERE id=r.id;
 INSERT INTO eshop.payment_operation_events(request_id,operation,details) VALUES(r.id,'provider_dispatch',p_result);
 PERFORM public.record_payment_fact_sync_internal(r.order_id);
 RETURN jsonb_build_object('committed',true,'status',v_status);
END $$;
CREATE OR REPLACE FUNCTION public.get_recoverable_payment_refunds()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT coalesce(jsonb_agg(jsonb_build_object('requestId',id,'providerId',method)),'[]') INTO result FROM (
  SELECT r.id,r.method FROM eshop.refund_requests r JOIN eshop.payment_providers p ON p.provider_key=r.method
  WHERE p.hosted_checkout AND r.status IN ('pending','processing','unknown')
   AND (r.lease_until IS NULL OR r.lease_until<clock_timestamp()) ORDER BY r.updated_at LIMIT 10) q;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.claim_payment_refund(uuid),public.complete_payment_refund(uuid,uuid,jsonb),public.get_recoverable_payment_refunds() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_payment_refund(uuid),public.complete_payment_refund(uuid,uuid,jsonb),public.get_recoverable_payment_refunds() TO service_role;

-- SOURCE: payment_providers/builtin.sql
-- Real builtin implementations of the same installed-method dispatch contract.
CREATE OR REPLACE FUNCTION public.bank_refund_readiness_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; ns text; c eshop.bank_sync_connections; account text;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF pi.currency_code NOT IN ('CZK','EUR','USD') OR pi.variable_symbol IS NULL THEN RETURN NULL; END IF;
 SELECT a.namespace_id,n.canonical_account INTO ns,account FROM eshop.payment_reference_accounts a
 JOIN eshop.payment_reference_namespaces n ON n.id=a.namespace_id
 JOIN eshop.payment_reference_reservations r ON r.namespace_id=a.namespace_id AND r.variable_symbol=pi.variable_symbol
 JOIN public.occasions oc ON oc.id=o.occasion
 JOIN eshop.payment_reference_scopes s ON s.organization_id=oc.organization AND s.phase IN ('active','paused')
 WHERE a.bank_account_id=pi.bank_account AND r.payment_info_id=pi.id AND r.original_payment_info_id=pi.id
 AND n.allocation_enabled;
 IF ns IS NULL OR (pi.currency_code='EUR' AND NOT public.is_valid_creditor_reference(pi.creditor_reference)) THEN RETURN NULL; END IF;
 SELECT con.* INTO c FROM eshop.bank_sync_connections con
 WHERE (con.bank_account_id=pi.bank_account OR EXISTS(SELECT 1 FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=con.id AND a.bank_account_id=pi.bank_account))
 AND con.state IN ('connected','degraded') AND con.mode='api' AND con.provider='FIO' AND con.legacy_blocked_at IS NOT NULL;
 IF c.id IS NULL OR (pi.currency_code='EUR' AND NOT c.refund_rf_verified) OR EXISTS(SELECT 1 FROM eshop.bank_sync_operations op WHERE op.operation='suspend' AND op.state IN ('pending','running','uncertain')
 AND (op.bank_account_id=pi.bank_account OR op.bank_account_id=c.bank_account_id OR op.bank_account_id IN (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id))) THEN RETURN NULL; END IF;
 -- The source account cannot silently change after enrollment.
 IF account IS DISTINCT FROM public.try_payment_reference_account_internal((SELECT account_number FROM eshop.bank_accounts WHERE id=pi.bank_account)) THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('namespace',ns,'sourceAccount',account,'connectionId',c.id,'lastSyncedAt',c.bank_pull_at,
  'variableSymbol',pi.variable_symbol::text,'creditorReference',pi.creditor_reference,
  'reference',CASE WHEN pi.currency_code='EUR' THEN pi.creditor_reference ELSE pi.variable_symbol::text END);
END $$;
CREATE OR REPLACE FUNCTION public.cash_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; u bigint; tx bigint; r eshop.refund_requests; pi_id bigint; cfg jsonb; can_record boolean;
BEGIN
 IF p_operation='initialize_payment' THEN
  INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method)
   VALUES((p_args->>'amount')::numeric,p_args->>'currency',(p_args->>'createdAt')::timestamptz,'cash') RETURNING id INTO pi_id;
  RETURN jsonb_build_object('paymentInfoId',pi_id);
 ELSIF p_operation='form_availability' THEN
  SELECT data->'payments' INTO cfg FROM public.forms WHERE id=(p_args->>'formId')::bigint;
  RETURN jsonb_build_object('providerId','cash','configured',coalesce(cfg->'cashEnabled','false'),
   'available',coalesce(cfg->'cashEnabled','false'),'supportedSurfaces','[]'::jsonb);
 ELSIF p_operation='operation_capabilities' THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint;
  -- Only the private context reader supplies prepared, stored-scope permissions.
  can_record:=CASE WHEN p_args ? 'permissions' THEN coalesce((p_args#>>'{permissions,can_record_cash}')::boolean,false)
   ELSE public.can_record_order_cash(o.id) END;
  RETURN jsonb_build_object('id','cash','displayName','Cash','record',can_record,
   'refund',can_record AND trim(o.currency_code) IN ('CZK','EUR','PLN','USD','GBP'),
   'verification','local_commit');
 ELSIF p_operation IN ('record_payment','correct_record','prepare_refund') THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint;
  SELECT unit INTO u FROM public.occasions WHERE id=o.occasion;
  IF p_operation='prepare_refund' THEN
   SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=(p_args->>'requestId')::uuid;
   tx:=public.write_cash_movement_internal(-r.amount,r.currency,u,NULL,(p_args->>'receivedAt')::timestamptz,p_args->>'note',o.payment_info,'refund',r.id);
   UPDATE eshop.refund_requests SET status='succeeded',updated_at=now() WHERE id=r.id;
  ELSE
   tx:=public.write_cash_movement_internal((p_args->>'amount')::numeric,trim(o.currency_code),u,NULL,
    (p_args->>'receivedAt')::timestamptz,p_args->>'note',o.payment_info,CASE WHEN p_operation='correct_record' THEN 'correct_record' ELSE 'correction' END,NULL);
  END IF;
  RETURN jsonb_build_object('nextAction','recorded','transactionId',tx);
 END IF;
 RAISE EXCEPTION 'PAYMENT_OPERATION_UNAVAILABLE';
END $$;
CREATE OR REPLACE FUNCTION public.bank_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ready jsonb; r eshop.refund_requests; iban text; name text; pi_id bigint; cfg jsonb; bank boolean; p_form bigint;
BEGIN
 IF p_operation='observe_payment' THEN
  RETURN public.match_bank_transaction((p_args->>'transactionId')::bigint);
 ELSIF p_operation='observe_refund' THEN
  RETURN public.observe_bank_refund_internal((p_args->>'transactionId')::bigint);
 ELSIF p_operation='initialize_payment' THEN
  INSERT INTO eshop.payment_info(amount,deposit_amount,currency_code,created_at,payment_method)
   VALUES((p_args->>'amount')::numeric,CASE WHEN p_args#>>'{input,payment_type}'='full' THEN NULL ELSE nullif((p_args->>'deposit')::numeric,0) END,
    p_args->>'currency',(p_args->>'createdAt')::timestamptz,'bank') RETURNING id INTO pi_id;
  RETURN jsonb_build_object('paymentInfoId',pi_id);
 ELSIF p_operation='form_availability' THEN
  p_form:=(p_args->>'formId')::bigint;
  SELECT data->'payments' INTO cfg FROM public.forms WHERE id=p_form;
  bank:=FOUND AND coalesce(cfg->'bankEnabled','false')='true'::jsonb;
  bank:=bank AND EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion
   JOIN eshop.unit_bank_accounts link ON link.unit=oc.unit JOIN eshop.bank_accounts b ON b.id=link.bank_account
   WHERE f.id=p_form AND (f.bank_account IS NULL OR f.bank_account=b.id) AND b.type IS DISTINCT FROM 'CASH'
   AND NOT EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
    WHERE ff.form=f.id AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false)
    AND p.price>0 AND NOT coalesce(b.supported_currencies,'{}'::text[]) @> ARRAY[trim(p.currency_code)]));
  RETURN jsonb_build_object('providerId','bank','configured',bank,'available',bank,'supportedSurfaces','[]'::jsonb);
 ELSIF p_operation='operation_capabilities' THEN
  ready:=public.bank_refund_readiness_internal((p_args->>'orderId')::bigint);
  RETURN jsonb_build_object('id','bank','displayName','Bank transfer','record',false,
   'instructions',EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id=(p_args->>'orderId')::bigint AND pi.payment_method='bank' AND public.can_read_orders(o.occasion)
    AND ((trim(pi.currency_code)='CZK' AND pi.variable_symbol IS NOT NULL)
     OR (trim(pi.currency_code)='EUR' AND public.is_valid_creditor_reference(pi.creditor_reference)))),
   'refund',(CASE WHEN p_args ? 'permissions' THEN coalesce((p_args#>>'{permissions,can_refund_bank}')::boolean,false)
    ELSE public.can_prepare_order_bank_refund((p_args->>'orderId')::bigint) END) AND ready IS NOT NULL,
   'reason',CASE WHEN ready IS NULL THEN 'original_reference_or_bank_sync_unavailable' END,'verification','bank_event');
 ELSIF p_operation='prepare_refund' THEN
  SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=(p_args->>'requestId')::uuid;
  ready:=public.bank_refund_readiness_internal(r.order_id);
  IF ready IS NULL THEN RAISE EXCEPTION 'BANK_REFUND_NOT_READY'; END IF;
  iban:=public.canonical_payment_reference_account_internal(p_args->>'recipientIban');
  name:=trim(p_args->>'recipientName');
  IF name IS NULL OR length(name) NOT BETWEEN 1 AND 70 OR name ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'REFUND_RECIPIENT_INVALID'; END IF;
  IF r.currency='CZK' AND iban NOT LIKE 'CZ%' THEN RAISE EXCEPTION 'SPD_DOMESTIC_ACCOUNT_REQUIRED'; END IF;
  UPDATE eshop.refund_requests SET payload=payload||jsonb_build_object('instructions',ready||jsonb_build_object(
    'recipientIban',iban,'recipientName',name,'amount',r.amount::text,'currency',r.currency)),
   source_account=(SELECT bank_account FROM eshop.payment_info WHERE id=r.payment_info),reference_namespace=ready->>'namespace',
   variable_symbol=(ready->>'variableSymbol')::bigint,creditor_reference=ready->>'creditorReference'
   WHERE id=r.id;
  RETURN jsonb_build_object('nextAction','show_bank_instructions');
 END IF;
 RAISE EXCEPTION 'PAYMENT_OPERATION_UNAVAILABLE';
END $$;
INSERT INTO eshop.payment_providers(provider_key,handler,operation_mode,verification,refund_write_enabled)
 VALUES('cash','public.cash_payment_provider_internal(text,jsonb)'::regprocedure,'local','local_commit',true),
 ('bank','public.bank_payment_provider_internal(text,jsonb)'::regprocedure,'instructions','bank_event',true)
 ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,operation_mode=excluded.operation_mode,
 verification=excluded.verification,refund_write_enabled=excluded.refund_write_enabled;
ALTER TABLE eshop.payment_providers DROP CONSTRAINT IF EXISTS payment_providers_concrete_handler;
ALTER TABLE eshop.payment_providers ADD CONSTRAINT payment_providers_concrete_handler CHECK(handler IS NOT NULL);
REVOKE ALL ON FUNCTION public.bank_refund_readiness_internal(bigint),public.cash_payment_provider_internal(text,jsonb),public.bank_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_transactions/delete_manual_transaction_ws.sql
CREATE OR REPLACE FUNCTION public.delete_manual_transaction_ws(
  p_transaction_id bigint,
  p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE source eshop.transactions; oid bigint;
BEGIN
  SELECT * INTO source FROM eshop.transactions WHERE id=p_transaction_id AND payment_info=p_payment_info_id;
  SELECT id INTO oid FROM eshop.orders WHERE payment_info=p_payment_info_id;
  IF source.id IS NULL OR oid IS NULL THEN RAISE EXCEPTION 'MANUAL_TRANSACTION_PAIRING_MISMATCH'; END IF;
  PERFORM public.check_order_is_mutable(oid);
  -- Released void RPC delegates to the same exact-source command. Preserve the
  -- original cash fact and reverse it once, instead of deleting financial history.
  PERFORM public.command_payment_operation(jsonb_build_object('operation','correct_record','method','cash','orderId',oid,
    'transactionId',source.id,'amount',(-source.amount)::text,'currency',trim(source.currency),
    'receivedAt',source.date,'reason','Oprava původního hotovostního záznamu'),
    md5('legacy-manual-correction:'||source.id)::uuid);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_manual_transaction_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_manual_transaction_ws(bigint,bigint)
  TO authenticated;

-- SOURCE: eshop_transactions/insert_manual_transaction_internal_v1.sql
-- One owner for exact cash movements, account serialization and existing pairing.
CREATE OR REPLACE FUNCTION public.write_cash_movement_internal(
 p_amount numeric,p_currency text,p_unit_id bigint,p_variable_symbol text,p_date timestamptz,
 p_note text,p_payment_info_id bigint,p_purpose text,p_request uuid)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE
    v_account_id bigint;
    v_date timestamp with time zone;
    v_new_transaction_id bigint;
    v_payment_info_id bigint;
    v_candidate_ids bigint[];
    v_order eshop.orders;
    v_unit bigint;
BEGIN
    PERFORM public.payment_policy_fence_internal(u.organization) FROM public.units u WHERE u.id=p_unit_id;
    IF p_purpose<>'correct_record' AND NOT coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'cash'),false) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
    IF p_payment_info_id IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=p_payment_info_id AND public.payment_method_is_online_internal(pi.payment_method)) THEN RAISE EXCEPTION 'PAYMENT_SOURCE_MISMATCH'; END IF;
    -- Check permissions (must be Unit Manager)
    PERFORM public.check_is_manager_on_unit(p_unit_id);
    IF p_amount IS NULL OR p_amount=0 OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount*100<>trunc(p_amount*100)
       OR p_currency IS NULL OR p_currency NOT IN ('CZK','EUR','PLN','USD','GBP') OR p_date IS NULL THEN
      RAISE EXCEPTION 'CASH_AMOUNT_INVALID'; END IF;
    IF p_payment_info_id IS NULL AND p_variable_symbol ~ '^[0-9]{1,10}$' THEN
      SELECT array_agg(pi.id ORDER BY pi.id) INTO v_candidate_ids FROM eshop.payment_info pi
      JOIN eshop.orders o ON o.payment_info=pi.id JOIN public.occasions oc ON oc.id=o.occasion
      WHERE pi.variable_symbol=p_variable_symbol::bigint AND trim(pi.currency_code)=p_currency AND oc.unit=p_unit_id;
      IF cardinality(v_candidate_ids)=1 THEN
        RETURN public.write_cash_movement_internal(p_amount,p_currency,p_unit_id,p_variable_symbol,p_date,p_note,v_candidate_ids[1],p_purpose,p_request);
      END IF;
    END IF;
    IF p_payment_info_id IS NOT NULL THEN
      SELECT * INTO STRICT v_order FROM eshop.orders WHERE payment_info=p_payment_info_id;
      PERFORM public.lock_order_capacity_scope_internal(ARRAY[v_order.id]);
      SELECT unit INTO v_unit FROM public.occasions WHERE id=v_order.occasion;
      IF v_unit IS DISTINCT FROM p_unit_id OR trim(v_order.currency_code) IS DISTINCT FROM p_currency THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
      IF p_purpose<>'refund' THEN PERFORM public.check_order_is_mutable(v_order.id); END IF;
      PERFORM 1 FROM eshop.payment_info WHERE id=p_payment_info_id FOR UPDATE;
      IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=v_order.id) THEN RAISE EXCEPTION 'ORDER_DELETION_IN_PROGRESS'; END IF;
      IF p_amount<0 AND p_purpose<>'refund' THEN
        PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-p_amount);
      END IF;
    END IF;
    v_date := p_date;
    PERFORM pg_advisory_xact_lock(hashtextextended('cash-account:'||p_unit_id||':'||p_currency,79103));

    -- 1. Find or Create CASH account
    SELECT ba.id INTO v_account_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id
      AND ba.type = 'CASH'
      AND p_currency = ANY(ba.supported_currencies)
    ORDER BY ba.id LIMIT 1;

    IF v_account_id IS NULL THEN
        INSERT INTO eshop.bank_accounts (
            title, type, supported_currencies, account_number, account_number_human_readable
        ) VALUES (
            'Cash Account (' || p_currency || ')', 'CASH', ARRAY[p_currency], '', ''
        )
        RETURNING id INTO v_account_id;

        INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
        VALUES (p_unit_id, v_account_id, 0);
    END IF;

    -- 2. Insert Transaction
    INSERT INTO eshop.transactions (
        bank_account_id,
        amount,
        currency,
        date,
        vs,
        message_for_recipient,
        transaction_type,
        created_by,
        ingest_source
    ) VALUES (
        v_account_id,
        p_amount,
        p_currency,
        v_date,
        p_variable_symbol,
        p_note,
        CASE WHEN p_purpose='refund' THEN 'return' ELSE 'manual' END,
        auth.uid(),
        'manual'
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    IF p_payment_info_id IS NOT NULL THEN
         v_payment_info_id := p_payment_info_id;

    END IF;

    IF v_payment_info_id IS NOT NULL THEN
        IF p_purpose='refund' THEN
          IF p_amount>=0 OR p_request IS NULL THEN RAISE EXCEPTION 'REFUND_CASH_INVALID'; END IF;
          UPDATE eshop.transactions SET payment_info=v_payment_info_id WHERE id=v_new_transaction_id;
          INSERT INTO eshop.refund_settlements(transaction_id,request_id,actor) VALUES(v_new_transaction_id,p_request,auth.uid());
          PERFORM public.refresh_payment_info_totals_internal(v_payment_info_id);
          PERFORM public.reconcile_order_payment_internal_v1(v_order.id,'refund_fact');
        ELSE
          PERFORM public.apply_transaction_pairing(v_new_transaction_id,v_payment_info_id,'manual_insert','user');
        END IF;
    END IF;
    RETURN v_new_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.write_cash_movement_internal(numeric,text,bigint,text,timestamptz,text,bigint,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
-- Released cash APIs and prepaid cash sales retain one ledger writer.
CREATE OR REPLACE FUNCTION public.insert_manual_transaction_internal_v1(
 p_amount numeric,p_currency text,p_unit_id bigint,p_variable_symbol text,p_date timestamptz,
 p_note text DEFAULT NULL,p_payment_info_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.write_cash_movement_internal(p_amount,p_currency,p_unit_id,p_variable_symbol,p_date,p_note,p_payment_info_id,'correction',NULL);
$$;
REVOKE ALL ON FUNCTION public.insert_manual_transaction_internal_v1(numeric,text,bigint,text,timestamptz,text,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_transactions/get_transactions_for_order_all_available.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order_all_available(payment_info_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    bank_acc bigint;
BEGIN
    SELECT pi.bank_account INTO bank_acc
    FROM eshop.payment_info pi
    WHERE pi.id = payment_info_id
    AND pi.payment_method='bank'
    LIMIT 1;

    IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.payment_info=payment_info_id AND public.payment_method_policy_enabled_internal(oc.unit,'bank') AND public.can_read_orders(oc.id)) THEN RAISE insufficient_privilege; END IF;
    IF bank_acc IS NULL THEN RAISE insufficient_privilege USING MESSAGE='Bank payment account required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=bank_acc AND public.can_read_orders(demo_bank.occasion)) THEN
        PERFORM public.check_is_admin_for_bank_account(bank_acc);
    END IF;

    RETURN (
        SELECT jsonb_agg(t ORDER BY t.date DESC)
        FROM eshop.transactions t
        WHERE t.bank_account_id = (
            SELECT pi.bank_account
            FROM eshop.payment_info pi
            WHERE pi.id = payment_info_id
        )
        AND t.payment_info IS NULL AND t.amount>0
        AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id)
    );
END;
$$;

-- Explicit account context. Order access never grants statement authority.
CREATE OR REPLACE FUNCTION public.get_bank_transaction_history(p_bank_account_id bigint,p_unit_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_read_bank_transactions(p_bank_account_id) OR NOT public.get_is_manager_on_unit(p_unit_id)
  OR NOT coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'bank'),false)
  OR NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts WHERE unit=p_unit_id AND bank_account=p_bank_account_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Bank history access denied'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(t ORDER BY t.date DESC,t.id),'[]') FROM eshop.transactions t
  JOIN eshop.bank_accounts b ON b.id=t.bank_account_id WHERE b.id=p_bank_account_id AND upper(b.type)<>'CASH');
END $$;
REVOKE ALL ON FUNCTION public.get_bank_transaction_history(bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_transaction_history(bigint,bigint) TO authenticated;

-- SOURCE: eshop_bank_accounts/get_bank_accounts_for_unit_management.sql
DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);

CREATE FUNCTION public.get_bank_accounts_for_unit_management(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    creditor_name text,
    type text,
    is_admin boolean,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    last_fio_fetch_time timestamptz,
    bank_sync jsonb,
    bank_sync_warning jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_unit_manager boolean;
BEGIN
    IF NOT coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'bank'),false) THEN RAISE insufficient_privilege USING MESSAGE='PAYMENT_METHOD_POLICY_DISABLED'; END IF;
    v_unit_manager := public.can_manage_unit_bank_accounts(p_unit_id);
    IF NOT public.can_read_unit_bank_accounts(p_unit_id) THEN
      RAISE insufficient_privilege USING MESSAGE='User is not manager.';
    END IF;
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.title,
        ba.creditor_name,
        ba.type,
        coalesce(membership.is_admin,false) as is_admin,
        NULL::text as token_masked,
        NULL::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ba.last_fio_fetch_time,
        CASE WHEN public.bank_account_write_rule(membership.is_admin,v_unit_manager,protected.bank_account IS NOT NULL)
          THEN public.get_bank_sync_connection(ba.id)
          ELSE (
            SELECT jsonb_build_object('state',connection.state,'mode',connection.mode)
            FROM eshop.bank_sync_connections connection
            WHERE connection.bank_account_id = ba.id
          ) END AS bank_sync,
        public.bank_sync_warning(ba.id) AS bank_sync_warning
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    -- Historical memberships need not be unique. Preserve any active admin
    -- grant while returning one row for each linked bank account.
    LEFT JOIN (
      SELECT grants.bank_account,bool_or(grants.is_admin) AS is_admin
      FROM eshop.bank_account_users grants WHERE grants."user"=auth.uid()
      GROUP BY grants.bank_account
    ) membership ON membership.bank_account=ba.id
    LEFT JOIN (SELECT DISTINCT bank_account FROM public.demo_occasions) protected ON protected.bank_account=ba.id
    WHERE uba.unit = p_unit_id
    AND ba.type != 'CASH'
    -- The entry guard admits a manager or a listed demo reader. Managers are
    -- always outside demo units; demo readers retain the account-level fence.
    AND (v_unit_manager OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=ba.id AND public.can_read_orders(demo_bank.occasion)));
END;
$$;

REVOKE ALL ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) TO authenticated, service_role;

-- SOURCE: eshop_stripe/provider.sql
-- Stripe is one connector. All Stripe storage/identity and price restrictions
-- remain here; the order lifecycle dispatches through the common registry.
CREATE OR REPLACE FUNCTION public.stripe_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE input jsonb; connection uuid; payment_id bigint; attempt uuid; expires timestamptz;
 amount numeric; currency text; target bigint; result jsonb;
BEGIN
 target:=(p_args->>'orderId')::bigint;
 IF p_operation='operation_capabilities' THEN
  result:=public.stripe_payment_provider_internal('refund_binding',p_args);
  RETURN jsonb_build_object('id','stripe','displayName','Stripe','record',false,'refund',result IS NOT NULL,
   'verification','verified_provider_observation','reason',CASE WHEN result IS NULL THEN 'original_payment_unavailable' ELSE NULL END);
 ELSIF p_operation='refund_binding' THEN
  -- Refunds bind to one evidenced original payment, never a checkout URL or client identity.
  SELECT jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',a.livemode,
   'paymentId',a.payment_intent_id,'currency',a.currency,'amountMinor',a.amount_minor) INTO result
  FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_connections c ON c.id=a.connection_id
  JOIN eshop.orders o ON o.id=a.order_id AND o.payment_info=a.payment_info_id
  JOIN eshop.payment_info pi ON pi.id=a.payment_info_id AND pi.stripe_connection_id=c.id
  WHERE a.order_id=target AND a.payment_intent_id IS NOT NULL AND c.livemode=a.livemode
   AND c.organization_id=a.organization_id AND c.unit_id=a.unit_id AND pi.payment_method='stripe' AND pi.currency_code::text=a.currency AND pi.amount*100=a.amount_minor
   AND c.state IN ('connected','restricted') AND c.model_verified
   AND a.currency IN ('CZK','EUR','PLN','USD','GBP')
   AND EXISTS(SELECT 1 FROM eshop.stripe_payment_movements m WHERE m.attempt_id=a.id AND m.kind='payment' AND m.provider_id=a.payment_intent_id AND m.currency=a.currency AND m.amount_minor=a.amount_minor)
   AND 1=(SELECT count(*) FROM eshop.stripe_checkout_attempts x WHERE x.order_id=target AND EXISTS(
    SELECT 1 FROM eshop.stripe_payment_movements m WHERE m.attempt_id=x.id AND m.kind='payment'));
  RETURN result;
 ELSIF p_operation='refund_observed' THEN
  RETURN to_jsonb(EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts a
   JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id AND m.connection_id=a.connection_id
   WHERE a.order_id=target AND m.kind='refund' AND m.provider_id=p_args->>'refundId'
    AND EXISTS(SELECT 1 FROM eshop.refund_requests r WHERE r.id=(p_args->>'requestId')::uuid
      AND r.order_id=a.order_id AND r.payment_info=a.payment_info_id AND r.method='stripe'
      AND r.currency=m.currency AND r.amount*100=m.amount_minor)));
 ELSIF p_operation='projection' THEN RETURN public.stripe_order_payment_projection_internal(target);
 ELSIF p_operation='attach_source' THEN
  PERFORM public.attach_stripe_order_pay_source_internal(target,(p_args->>'commandId')::uuid,p_args->'source'); RETURN NULL;
 ELSIF p_operation='initialize_payment' THEN
  input:=p_args->'input';amount:=(p_args->>'amount')::numeric;currency:=p_args->>'currency';
  IF coalesce(input->>'payment_type','full')<>'full' OR (p_args->>'deposit')::numeric>0 THEN RAISE EXCEPTION 'STRIPE_DEPOSIT_UNSUPPORTED'; END IF;
  connection:=public.assert_stripe_form_payable_internal((p_args->>'formId')::bigint,(input->>'stripe_connection_id')::uuid,input->>'payment_surface');
  IF (input->>'expected_payment_amount_minor')::numeric IS DISTINCT FROM amount*100 OR input->>'expected_payment_currency' IS DISTINCT FROM currency THEN
   RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','STRIPE_PRICE_CHANGED','message','Order price changed. Review the order before paying.')::text; END IF;
  IF currency NOT IN ('CZK','EUR','PLN','USD','GBP') OR amount*100<>trunc(amount*100) THEN RAISE EXCEPTION 'STRIPE_AMOUNT_UNSUPPORTED'; END IF;
  INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method,stripe_connection_id)
   VALUES(amount,currency,(p_args->>'createdAt')::timestamptz,'stripe',connection) RETURNING id INTO payment_id;
  RETURN jsonb_build_object('paymentInfoId',payment_id);
 ELSIF p_operation='create_attempt' THEN
  attempt:=public.create_stripe_order_attempt_internal(target);
  SELECT reservation_expires_at INTO STRICT expires FROM eshop.stripe_checkout_attempts WHERE id=attempt;
  RETURN jsonb_build_object('expiresAt',expires);
 ELSIF p_operation='paid_guard' THEN
  IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
   JOIN eshop.stripe_checkout_attempts a ON a.order_id=o.id JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id
   WHERE o.id=target AND m.kind='payment' AND m.amount_minor=a.amount_minor
    AND m.connection_id=pi.stripe_connection_id AND m.occurred_at<=a.reservation_expires_at) THEN
   RETURN jsonb_build_object('code',409,'message','STRIPE_PROVIDER_PAYMENT_REQUIRED'); END IF;
  IF (SELECT state FROM eshop.orders WHERE id=target)='expired' THEN RETURN jsonb_build_object('code',409,'message','Stripe reservation was released'); END IF;
  RETURN NULL;
 ELSIF p_operation='totals' THEN
  payment_id:=(p_args->>'paymentId')::bigint;
  WITH p AS (SELECT * FROM eshop.payment_info WHERE id=payment_id), money AS (
   SELECT coalesce(sum(m.amount_minor) FILTER(WHERE m.kind='payment'),0)/100 received,
    coalesce(sum(m.amount_minor) FILTER(WHERE m.kind='refund'),0)/100 returned,
    coalesce(bool_or(m.connection_id IS DISTINCT FROM p.stripe_connection_id OR m.currency IS DISTINCT FROM p.currency_code::text
     OR a.order_id NOT IN(SELECT id FROM eshop.orders WHERE payment_info=p.id)),false) invalid
   FROM p JOIN eshop.stripe_checkout_attempts a ON a.payment_info_id=p.id JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id),
  holds AS (SELECT coalesce(sum(d.amount_minor) FILTER(WHERE d.status IN ('needs_response','under_review','lost')),0)/100 held
   FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_disputes d ON d.attempt_id=a.id WHERE a.payment_info_id=payment_id)
  SELECT jsonb_build_object('received',received,'returned',returned,'invalid',invalid,'held',held) INTO result FROM money CROSS JOIN holds;
  RETURN result;
 ELSIF p_operation='effect_context' THEN
  SELECT jsonb_build_object('attemptId',a.id,'orderId',a.order_id,'paymentId',a.payment_info_id,'connectionId',a.connection_id,
   'organizationId',a.organization_id,'unitId',a.unit_id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'reservationExpiresAt',a.reservation_expires_at,
   'state',a.state,'incomplete',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL,
   'receivedMinor',(SELECT coalesce(sum(amount_minor),0) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='payment'),
   'refundedMinor',(SELECT coalesce(sum(amount_minor),0) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund'),
   'paymentTime',(SELECT min(occurred_at) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='payment'),
   'decisions',coalesce((SELECT jsonb_agg(reason) FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id),'[]'))
  INTO result FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_connections c ON c.id=a.connection_id
   JOIN eshop.payment_info pi ON pi.id=a.payment_info_id AND pi.stripe_connection_id=c.id
   WHERE a.id=(p_args->>'attemptId')::uuid AND c.organization_id=a.organization_id AND c.unit_id=a.unit_id AND c.livemode=a.livemode;
  RETURN result;
 ELSIF p_operation='effect_lock' THEN
  PERFORM 1 FROM eshop.stripe_checkout_attempts WHERE id=(p_args->>'attemptId')::uuid FOR UPDATE; RETURN NULL;
 ELSIF p_operation='effect_state' THEN
  IF p_args->>'state' NOT IN ('paid','expired','action_required') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_STATE_INVALID'; END IF;
  UPDATE eshop.stripe_checkout_attempts SET state=p_args->>'state'
   WHERE id=(p_args->>'attemptId')::uuid; RETURN NULL;
 ELSIF p_operation='effect_decision' THEN
  INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision,ticket_ids,actor)
   VALUES((p_args->>'attemptId')::uuid,p_args->>'reason',p_args->>'revision',
    ARRAY(SELECT jsonb_array_elements_text(coalesce(p_args->'tickets','[]'))::bigint),auth.uid()) RETURNING id INTO attempt;
  RETURN to_jsonb(attempt);
 ELSIF p_operation='setup_recipients' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('connectionId',id,'name',business_name,'livemode',livemode) ORDER BY livemode,id),'[]') INTO result
   FROM eshop.stripe_connections WHERE unit_id=(p_args->>'unitId')::bigint AND model_verified AND state IN ('connected','restricted');
  RETURN result;
 ELSIF p_operation='unit_fields' THEN RETURN jsonb_build_object('stripe_preview_enabled',public.stripe_unit_feature_enabled_internal((p_args->>'unitId')::bigint));
 ELSIF p_operation='unit_feature' THEN RETURN to_jsonb(public.stripe_unit_feature_enabled_internal((p_args->>'unitId')::bigint));
 ELSIF p_operation='form_availability' THEN
  result:=public.stripe_form_payment_availability_internal((p_args->>'formId')::bigint);
  RETURN jsonb_build_object('providerId','stripe','configured',result#>'{configured,stripe}',
   'available',result->'available' ? 'stripe','recipient',result->'recipient','supportedSurfaces',result->'supportedSurfaces',
   'reason',jsonb_build_object('code',result->'stripeUnavailableReason'));
 ELSIF p_operation='validate_form' THEN
  PERFORM public.validate_stripe_form_payment_configuration_internal((p_args->>'formId')::bigint); RETURN NULL;
 ELSIF p_operation='form_editor_fields' THEN
  RETURN jsonb_build_object('stripeRecipient',public.get_form_stripe_recipient((p_args->>'unitId')::bigint,(p_args->>'occasionId')::bigint,(p_args->>'livemode')::boolean));
 ELSIF p_operation='movements' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('sourceId',m.source_id,'kind',m.kind,'amount_minor',m.amount_minor,'currency',m.currency,'occurred_at',m.occurred_at,'status',m.status)),'[]') INTO result
   FROM (
    SELECT m.connection_id::text||':'||m.provider_id source_id,m.kind,m.amount_minor,m.currency,m.occurred_at,NULL::text status
    FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id WHERE a.payment_info_id=(p_args->>'paymentId')::bigint
    UNION ALL
    SELECT d.connection_id::text||':dispute:'||d.provider_id,'dispute',d.amount_minor,a.currency,d.observed_at,d.status
    FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_disputes d ON d.attempt_id=a.id WHERE a.payment_info_id=(p_args->>'paymentId')::bigint
   ) m;
  RETURN result;
 END IF;
 RAISE EXCEPTION 'PAYMENT_PROVIDER_OPERATION_UNSUPPORTED';
END $$;
REVOKE ALL ON FUNCTION public.stripe_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.payment_info'::regclass AND conname='payment_info_stripe_connection_identity') THEN
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_stripe_connection_identity CHECK(
 (payment_method='stripe')=(stripe_connection_id IS NOT NULL)); END IF; END $$;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,legacy_connection_field,hosted_checkout,operation_mode,verification)
 VALUES('stripe','public.stripe_payment_provider_internal(text,jsonb)'::regprocedure,'stripePaymentSource','stripeConnectionId',true,'remote','verified_provider_observation') ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,source_field=excluded.source_field,legacy_connection_field=excluded.legacy_connection_field,hosted_checkout=excluded.hosted_checkout,operation_mode=excluded.operation_mode,verification=excluded.verification;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.payment_info'::regclass AND conname='payment_info_registered_method') THEN
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_registered_method
 FOREIGN KEY(payment_method) REFERENCES eshop.payment_providers(provider_key); END IF; END $$;

-- SOURCE: eshop_barion/provider.sql
-- Protocol persistence and projections only. Order/ticket/email decisions are
-- exclusively owned by apply_provider_payment_effects_internal.
CREATE OR REPLACE FUNCTION public.barion_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.barion_attempts; c eshop.barion_connections; o eshop.orders; pi eshop.payment_info;
 result jsonb; input jsonb; binding uuid; amount numeric; stamp timestamptz:=date_trunc('second',clock_timestamp());
 received bigint; refunded bigint; status text; admission text; expiry timestamptz;
BEGIN
 IF p_operation='operation_capabilities' THEN
  RETURN jsonb_build_object('id','barion','displayName','Barion sandbox','record',false,'refund',false,
   'verification','verified_provider_observation','reason','refund_write_unavailable');
 ELSIF p_operation='refund_binding' THEN RETURN NULL;
 ELSIF p_operation='refund_observed' THEN
  RETURN to_jsonb(EXISTS(SELECT 1 FROM eshop.barion_attempts a JOIN eshop.barion_movements m ON m.attempt_id=a.id
   WHERE a.order_id=(p_args->>'orderId')::bigint AND m.kind='refund' AND m.provider_id=p_args->>'refundId'
    AND EXISTS(SELECT 1 FROM eshop.refund_requests r WHERE r.id=(p_args->>'requestId')::uuid
      AND r.order_id=a.order_id AND r.payment_info=a.payment_info_id AND r.method='barion'
      AND r.currency=m.currency AND r.amount*100=m.amount_minor)));
 ELSIF p_operation IN ('unit_feature','unit_fields') THEN RETURN CASE WHEN p_operation='unit_feature' THEN 'false'::jsonb ELSE '{}'::jsonb END;
 ELSIF p_operation='setup_recipients' THEN RETURN '[]'::jsonb;
 ELSIF p_operation='form_editor_fields' THEN RETURN '{}'::jsonb;
 ELSIF p_operation IN ('form_availability','validate_form') THEN
  binding:=public.payment_provider_connection_internal((SELECT data->'payments' FROM public.forms WHERE id=(p_args->>'formId')::bigint),'barion');
  IF p_operation='validate_form' THEN
   IF binding IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.barion_connections b JOIN public.forms f ON f.id=(p_args->>'formId')::bigint JOIN public.occasions oc ON oc.id=f.occasion
    WHERE b.id=binding AND b.unit_id=oc.unit AND b.organization_id=oc.organization AND f.id=ANY(b.sandbox_form_ids)) THEN RAISE EXCEPTION 'BARION_SANDBOX_FORM_REQUIRED'; END IF;
   RETURN NULL;
  END IF;
  SELECT * INTO c FROM eshop.barion_connections WHERE id=binding;
  RETURN jsonb_build_object('providerId','barion','configured',binding IS NOT NULL,'available',false,'collectionAvailable',c.enabled AND EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=(p_args->>'formId')::bigint AND f.id=ANY(c.sandbox_form_ids) AND oc.unit=c.unit_id AND oc.organization=c.organization_id),
   'recipient',CASE WHEN c.id IS NOT NULL THEN jsonb_build_object('connectionId',c.id,'name',c.business_name,'livemode',false) ELSE NULL END,
   'supportedSurfaces','[]'::jsonb,'reason',jsonb_build_object('code','sandbox_only'));
 ELSIF p_operation='initialize_payment' THEN
  input:=p_args->'input';amount:=(p_args->>'amount')::numeric;
  binding:=public.payment_provider_connection_internal((SELECT data->'payments' FROM public.forms WHERE id=(p_args->>'formId')::bigint),'barion');
  SELECT b.* INTO c FROM eshop.barion_connections b JOIN public.forms f ON f.id=(p_args->>'formId')::bigint JOIN public.occasions oc ON oc.id=f.occasion
   WHERE b.id=binding AND b.enabled AND b.organization_id=oc.organization AND b.unit_id=oc.unit AND f.id=ANY(b.sandbox_form_ids);
  IF c.id IS NULL OR input->>'payment_connection_id' IS DISTINCT FROM binding::text THEN RAISE EXCEPTION 'BARION_SANDBOX_FORM_REQUIRED'; END IF;
  IF amount<=0 OR amount*100<>trunc(amount*100) OR amount*100>1000000000 OR p_args->>'currency' NOT IN ('CZK','EUR','USD')
   OR (input->>'expected_payment_amount_minor')::numeric IS DISTINCT FROM amount*100 OR input->>'expected_payment_currency' IS DISTINCT FROM p_args->>'currency'
   OR coalesce(input->>'payment_type','full')<>'full' OR coalesce((p_args->>'deposit')::numeric,0)<>0 THEN RAISE EXCEPTION 'BARION_PRICE_INVALID'; END IF;
  INSERT INTO eshop.payment_info(amount,currency_code,payment_method,created_at,barion_connection_id) VALUES(amount,p_args->>'currency','barion',stamp,binding) RETURNING id INTO amount;
  RETURN jsonb_build_object('paymentInfoId',amount);
 END IF;
 IF p_args ? 'attemptId' THEN SELECT * INTO a FROM eshop.barion_attempts WHERE id=(p_args->>'attemptId')::uuid;
 ELSIF p_args ? 'orderId' THEN SELECT * INTO a FROM eshop.barion_attempts WHERE order_id=(p_args->>'orderId')::bigint;
 ELSE SELECT * INTO a FROM eshop.barion_attempts WHERE payment_info_id=(p_args->>'paymentId')::bigint; END IF;
 IF p_operation='create_attempt' THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint FOR UPDATE;
  SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
  binding:=pi.barion_connection_id;
  SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=binding AND enabled AND o.form=ANY(sandbox_form_ids);
  IF pi.payment_method<>'barion' OR pi.amount<>o.price OR pi.currency_code<>o.currency_code OR o.state<>'ordered'
    OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND unit=c.unit_id AND organization=c.organization_id) THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
  expiry:=stamp+make_interval(secs=>(public.payment_sale_policy_internal()->>'reservationSeconds')::integer);
  INSERT INTO eshop.barion_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,amount_minor,currency,reservation_expires_at,return_base_url,locale)
   SELECT o.id,pi.id,c.organization_id,c.unit_id,c.id,(pi.amount*100)::bigint,pi.currency_code,expiry,
    rtrim(data->>'DEFAULT_URL','/')||'/payments/barion/return',CASE WHEN data->>'DEFAULT_LANGUAGE' IN ('cs','en','de','pl','sk') THEN data->>'DEFAULT_LANGUAGE' ELSE 'en' END
   FROM public.organizations WHERE id=c.organization_id RETURNING * INTO a;
  UPDATE eshop.payment_info SET deadline=expiry WHERE id=pi.id;
  RETURN jsonb_build_object('expiresAt',expiry);
 END IF;
 IF a.id IS NULL THEN
  IF p_operation='projection' THEN RETURN NULL; END IF;
  IF p_operation='paid_guard' THEN RETURN jsonb_build_object('code',409,'message','BARION_VERIFIED_PAYMENT_REQUIRED'); END IF;
  RAISE EXCEPTION 'BARION_ATTEMPT_REQUIRED';
 END IF;
 SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=a.connection_id;
 SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0),coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0) INTO received,refunded FROM eshop.barion_movements WHERE attempt_id=a.id;
 IF p_operation='totals' THEN RETURN jsonb_build_object('received',received/100.0,'returned',refunded/100.0,'held',CASE WHEN a.financial_hold THEN a.amount_minor/100.0 ELSE 0 END,'invalid',false);
 ELSIF p_operation='movements' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('sourceId',m.connection_id::text||':'||m.provider_id,'kind',m.kind,'amount_minor',m.amount_minor,'currency',m.currency,'occurred_at',m.occurred_at)),'[]') FROM eshop.barion_movements m WHERE attempt_id=a.id);
 ELSIF p_operation='effect_context' THEN
  RETURN jsonb_build_object('attemptId',a.id,'orderId',a.order_id,'paymentId',a.payment_info_id,'connectionId',c.id,'organizationId',a.organization_id,'unitId',a.unit_id,
   'accountId',c.account_id,'livemode',false,'amountMinor',a.amount_minor,'currency',a.currency,'reservationExpiresAt',a.reservation_expires_at,
   'state',a.state,'incomplete',a.financial_hold,'receivedMinor',received,'refundedMinor',refunded,
   'paymentTime',(SELECT min(occurred_at) FROM eshop.barion_movements WHERE attempt_id=a.id AND kind='payment'),'decisions',a.decisions);
 ELSIF p_operation='effect_lock' THEN PERFORM 1 FROM eshop.barion_attempts WHERE id=a.id FOR UPDATE;RETURN NULL;
 ELSIF p_operation='effect_state' THEN
  IF p_args->>'state' NOT IN ('paid','expired','action_required') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_STATE_INVALID'; END IF;
  UPDATE eshop.barion_attempts SET state=p_args->>'state' WHERE id=a.id;RETURN NULL;
 ELSIF p_operation='effect_decision' THEN
  UPDATE eshop.barion_attempts SET decisions=decisions||jsonb_build_array(p_args->>'reason') WHERE id=a.id;RETURN to_jsonb(extensions.gen_random_uuid());
 ELSIF p_operation IN ('projection','paid_guard') THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id;SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=a.payment_info_id;
  IF p_operation='paid_guard' THEN
   IF a.financial_hold OR received<>a.amount_minor OR refunded>=a.amount_minor OR o.state='expired' OR NOT EXISTS(
    SELECT 1 FROM eshop.barion_movements WHERE attempt_id=a.id AND kind='payment' AND occurred_at<=a.reservation_expires_at) THEN
    RETURN jsonb_build_object('code',409,'message','BARION_VERIFIED_PAYMENT_REQUIRED'); END IF; RETURN NULL;
  END IF;
  status:=CASE WHEN a.financial_hold THEN 'disputed' WHEN refunded>=a.amount_minor THEN 'refunded' WHEN a.state='action_required' THEN 'action_required'
   WHEN refunded>0 THEN 'partially_refunded' WHEN received>=a.amount_minor AND o.state IN ('paid','sent') THEN 'paid'
   WHEN a.state='uncertain' AND a.remote_id IS NULL THEN 'pending'
   WHEN a.state='expired' OR a.reservation_expires_at<=clock_timestamp() OR o.state IN ('expired','storno') THEN 'expired'
   WHEN a.state='preparing' THEN 'preparing' ELSE 'open' END;
  admission:=CASE WHEN status IN ('disputed','refunded','action_required') THEN 'hold' WHEN status IN ('paid','partially_refunded') AND o.state IN ('paid','sent') THEN 'valid' ELSE 'pending' END;
  RETURN jsonb_build_object('method','barion','status',status,'amount',pi.amount::text,'received',(received/100.0)::numeric(30,2)::text,'returned',(refunded/100.0)::numeric(30,2)::text,
   'currency',a.currency,'admissionState',admission,'orderState',o.state,'reservationExpiresAt',a.reservation_expires_at,'serverNow',clock_timestamp(),
   'reconciliationPending',a.financial_hold OR (a.state='uncertain' AND a.remote_id IS NULL),'reconciliationFailures',a.reconcile_failures,'lastSyncedAt',a.last_synced_at,
   'deliveryState',coalesce((SELECT CASE workflow_state WHEN 'accepted' THEN 'accepted' WHEN 'failed' THEN 'failed' ELSE 'pending' END FROM public.email_messages WHERE order_id=o.id AND message_kind='order_tickets' ORDER BY created_at DESC,id DESC LIMIT 1),'not_requested'),
   'allowedActions',CASE WHEN status IN ('preparing','open') THEN '["refresh","pay"]'::jsonb ELSE '["refresh"]'::jsonb END);
 ELSIF p_operation='attach_source' THEN
  input:=p_args->'source';
  IF input->>'tokenHash' IS NULL OR input->>'tokenHash' !~ '^[a-f0-9]{64}$' OR input->>'returnHash' IS NULL OR input->>'returnHash' !~ '^[a-f0-9]{64}$'
   OR input->>'tokenHash'=input->>'returnHash' OR input->>'contentHash' IS NULL OR input->>'contentHash' !~ '^[a-f0-9]{64}$'
   OR jsonb_typeof(input->'sealed') IS DISTINCT FROM 'object' OR input#>>'{sealed,v}' IS DISTINCT FROM '1'
   OR nullif(input#>>'{sealed,iv}','') IS NULL OR nullif(input#>>'{sealed,ciphertext}','') IS NULL THEN RAISE EXCEPTION 'BARION_SOURCE_INVALID'; END IF;
  INSERT INTO eshop.barion_capabilities(token_hash,attempt_id,scope,expires_at) VALUES(input->>'tokenHash',a.id,'order_pay',stamp+interval '30 days'),(input->>'returnHash',a.id,'return_read',a.reservation_expires_at+interval '1 day');
  INSERT INTO eshop.barion_sources VALUES(a.id,(p_args->>'commandId')::uuid,input->>'tokenHash',input->'sealed',input->>'contentHash');RETURN NULL;
 END IF;
 RAISE EXCEPTION 'BARION_OPERATION_UNSUPPORTED';
END $$;
REVOKE ALL ON FUNCTION public.barion_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,hosted_checkout,operation_mode,verification) VALUES('barion','public.barion_payment_provider_internal(text,jsonb)'::regprocedure,'barionPaymentSource',true,'remote','verified_provider_observation') ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,source_field=excluded.source_field,hosted_checkout=true,operation_mode=excluded.operation_mode,verification=excluded.verification;

-- SOURCE: eshop_bank_accounts/link_bank_account_to_unit.sql
CREATE OR REPLACE FUNCTION public.link_bank_account_to_unit(
    p_bank_account_id bigint,
    p_unit_id bigint,
    p_priority int,
    p_hard boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_conflict_data jsonb;
    v_is_reordering boolean;
BEGIN
    PERFORM public.require_bank_authoring_scope_internal(NULL,p_unit_id);
    PERFORM public.check_bank_account_writable(p_bank_account_id);
    v_is_reordering := EXISTS (
        SELECT 1 FROM eshop.unit_bank_accounts
        WHERE unit = p_unit_id AND bank_account = p_bank_account_id
    );
    IF p_priority IS NULL OR v_is_reordering THEN
        IF NOT public.can_manage_unit_bank_accounts(p_unit_id) THEN
            RAISE insufficient_privilege USING MESSAGE='User is not manager.';
        END IF;
    ELSIF NOT public.can_link_bank_account_to_unit(p_bank_account_id,p_unit_id) THEN
        RAISE EXCEPTION 'User is not an admin of this bank account or manager of the target unit.' USING ERRCODE='42501';
    END IF;

    IF p_priority IS NULL THEN
        -- Issued instructions outlive a dialog and may still arrive as debits.
        -- Account links needed by an open refund cannot be forcibly removed.
        PERFORM public.lock_order_capacity_scope_internal(ARRAY(
          SELECT o.id FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
          JOIN eshop.payment_info pi ON pi.id=o.payment_info
          WHERE oc.unit=p_unit_id AND pi.bank_account=p_bank_account_id ORDER BY o.id));
        IF EXISTS(SELECT 1 FROM eshop.refund_requests r JOIN eshop.orders o ON o.id=r.order_id
          JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=r.payment_info
          WHERE oc.unit=p_unit_id AND pi.bank_account=p_bank_account_id
            AND r.status IN ('pending','processing','unknown')) THEN
          RAISE EXCEPTION 'BANK_ACCOUNT_HAS_PENDING_REFUND';
        END IF;
        -- Unlink Logic

        -- Dependency Check (unless hard)
        IF NOT p_hard THEN
            WITH TargetAcc AS (
                SELECT unnest(supported_currencies) as curr FROM eshop.bank_accounts WHERE id = p_bank_account_id
            ),
            OtherAccs AS (
                SELECT unnest(ba.supported_currencies) as curr
                FROM eshop.unit_bank_accounts uba
                JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
                WHERE uba.unit = p_unit_id AND uba.bank_account != p_bank_account_id AND ba.type IS DISTINCT FROM 'CASH'
            ),
            LostCurrencies AS (
                SELECT curr FROM TargetAcc
                EXCEPT
                SELECT curr FROM OtherAccs
            ),
            ConflictingForms AS (
                SELECT DISTINCT f.title as form_title, f.link as form_link, p.currency_code, o.title as occasion_title
                FROM public.forms f
                JOIN public.occasions o ON f.occasion = o.id
                JOIN public.form_fields ff ON ff.form = f.id
                JOIN eshop.product_types pt ON ff.product_type = pt.id
                JOIN eshop.products p ON p.product_type = pt.id
                JOIN eshop.products p2 ON ff.product_type = p2.product_type
                WHERE o.unit = p_unit_id
                  AND f.is_open = true
                  AND coalesce(f.data#>'{payments,bankEnabled}','true'::jsonb)='true'::jsonb
                  -- AND p.is_hidden = false -- Removed is_hidden check? Original SQL had it. Let's keep it tight.
                  AND p.currency_code IN (SELECT curr FROM LostCurrencies)
            )
            SELECT jsonb_agg(jsonb_build_object('form', form_title, 'link', form_link, 'currency', currency_code, 'occasion', occasion_title))
            INTO v_conflict_data
            FROM ConflictingForms;

            IF v_conflict_data IS NOT NULL THEN
                 RAISE EXCEPTION '%', jsonb_build_object(
                    'code', 'LINK_DEPENDENCY_ERROR',
                    'message', 'Cannot unlink bank account because some active forms depend on its currency support.',
                    'conflicts', v_conflict_data
                 )::text;
            END IF;
        END IF;

        DELETE FROM eshop.unit_bank_accounts
        WHERE unit = p_unit_id AND bank_account = p_bank_account_id;
    ELSE
        -- Link or Update Priority
        IF v_is_reordering THEN
            UPDATE eshop.unit_bank_accounts
            SET priority = p_priority
            WHERE unit = p_unit_id AND bank_account = p_bank_account_id;
        ELSE
            INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
            VALUES (p_unit_id, p_bank_account_id, p_priority);

        END IF;
    END IF;
END;
$$;

-- SOURCE: eshop_bank_accounts/update_bank_account.sql
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[]);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint,text);

CREATE OR REPLACE FUNCTION public.update_bank_account(
    p_id bigint,
    p_account_number text,
    p_title text,
    p_type text DEFAULT 'FIO',
    p_supported_currencies text[] DEFAULT NULL,
    p_account_number_human_readable text DEFAULT NULL,
    p_unit_id bigint DEFAULT NULL,
    p_creditor_name text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_id bigint;
    v_account_number text;
    v_operation_id uuid;
    v_request jsonb;
BEGIN
    PERFORM public.require_bank_authoring_scope_internal(p_id,p_unit_id);
    PERFORM public.check_bank_account_writable(p_id);
    -- Prevent manual manipulation of CASH accounts
    IF p_type = 'CASH' THEN
        RAISE EXCEPTION 'CASH_ACCOUNT_MANUAL_UPDATE_FORBIDDEN';
    END IF;

    IF char_length(p_title)>120 THEN RAISE EXCEPTION 'BANK_ACCOUNT_TITLE_TOO_LONG'; END IF;

    -- Input normalization
    v_account_number := TRIM(p_account_number);

    IF p_id IS NULL THEN
        -- A new account has no account admin yet: a managed target unit is
        -- mandatory, and creation grants the second role atomically below.
        IF p_unit_id IS NULL THEN
            RAISE EXCEPTION 'A managed unit is required to create a bank account.' USING ERRCODE='42501';
        END IF;
        IF NOT public.can_manage_unit_bank_accounts(p_unit_id) THEN
            RAISE insufficient_privilege USING MESSAGE='User is not manager.';
        END IF;

        -- Check for duplicate account number on insert
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        INSERT INTO eshop.bank_accounts (account_number, title, type, supported_currencies, account_number_human_readable, creditor_name)
        VALUES (v_account_number, p_title, p_type, p_supported_currencies, p_account_number_human_readable, nullif(trim(p_creditor_name), ''))
        RETURNING id INTO v_id;

        -- Automatically make the creator an Admin
        INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin)
        VALUES (v_id, auth.uid(), true);

        -- Automatically link to unit if provided
        IF p_unit_id IS NOT NULL THEN
             INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
             VALUES (p_unit_id, v_id, 0);
        END IF;
    ELSE
        -- Check for duplicate account number on update (exclude current id)
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number AND id != p_id) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        -- Security Check: Caller must be an Admin of the bank account
        IF NOT public.can_manage_bank_account(p_id) THEN
            RAISE EXCEPTION 'Permission denied: Only bank account admins can update details.' USING ERRCODE='42501';
        END IF;

        PERFORM 1 FROM eshop.bank_accounts WHERE id=p_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM eshop.bank_sync_connections WHERE bank_account_id=p_id)
          AND EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE id=p_id
            AND (account_number IS DISTINCT FROM v_account_number OR type IS DISTINCT FROM p_type)) THEN
          RAISE EXCEPTION 'BANK_SYNC_ACCOUNT_IDENTITY_IMMUTABLE';
        END IF;
        IF EXISTS(SELECT 1 FROM eshop.payment_reference_accounts a JOIN eshop.payment_reference_namespaces n ON n.id=a.namespace_id
          WHERE a.bank_account_id=p_id AND (n.canonical_account IS DISTINCT FROM public.canonical_payment_reference_account_internal(v_account_number)
           OR p_type='CASH')) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_IDENTITY_IMMUTABLE'; END IF;
        UPDATE eshop.bank_accounts
        SET
            account_number = v_account_number,
            title = p_title,
            type = p_type,
            supported_currencies = p_supported_currencies,
            account_number_human_readable = p_account_number_human_readable,
            creditor_name = nullif(trim(p_creditor_name), ''),
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_id;
    END IF;
    -- Local details and the durable remote update intent commit together.
    IF p_id IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.bank_sync_connections WHERE bank_account_id=v_id) THEN
      v_operation_id := gen_random_uuid();
      v_request := jsonb_build_object('operation','update_details','operation_id',v_operation_id,'account_id',v_id);
      INSERT INTO eshop.bank_sync_operations(id,bank_account_id,actor,operation,payload_sha256,state,request)
        VALUES(v_operation_id,v_id,auth.uid(),'update_details',encode(extensions.digest(v_request::text,'sha256'),'hex'),'pending',v_request);
    END IF;
    RETURN v_id;
END;
$$;

-- SOURCE: eshop_stripe/feature_settings.sql
-- Released Stripe discovery boundary delegates to canonical scoped policy.
-- Consumer: published mobile versions reading stripe_preview_enabled and the old
-- feature endpoint. Remove after those supported clients retire. No second store.
CREATE OR REPLACE FUNCTION public.stripe_unit_feature_enabled_internal(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.payment_method_policy_enabled_internal(p_unit,'stripe'),false);
$$;
REVOKE ALL ON FUNCTION public.stripe_unit_feature_enabled_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.set_stripe_unit_feature(p_unit bigint,p_enabled boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE org bigint; input jsonb; preview jsonb;
BEGIN
 SELECT organization INTO org FROM public.units WHERE id=p_unit;
 IF NOT public.can_manage_organization_settings(org) OR NOT public.can_manage_payment_method_policy(org,p_unit) THEN RAISE insufficient_privilege; END IF;
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'PAYMENT_POLICY_MODE_INVALID'; END IF;
 input:=jsonb_build_object('organizationId',org,'unitId',p_unit,'method','stripe','mode',CASE WHEN p_enabled THEN 'enabled' ELSE 'disabled' END);
 preview:=public.preview_payment_method_policy(input);
 -- Legacy setter cannot acknowledge obligations: require the new preview UI.
 IF p_enabled=false AND ((preview#>>'{impact,openCollections}')::bigint>0 OR (preview#>>'{impact,pendingRequests}')::bigint>0) THEN RAISE EXCEPTION 'PAYMENT_POLICY_IMPACT_CONFIRMATION_REQUIRED'; END IF;
 PERFORM public.command_payment_method_policy(input,extensions.gen_random_uuid(),preview->>'confirmation');
 RETURN public.payment_method_policy_enabled_internal(p_unit,'stripe');
END $$;
REVOKE ALL ON FUNCTION public.set_stripe_unit_feature(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.set_stripe_unit_feature(bigint,boolean) TO authenticated;

-- SOURCE: eshop_forms/form_creation_domain.sql
-- Shared form construction. Invoker-only, private to explicit checked owners.
CREATE OR REPLACE FUNCTION public.insert_form_for_occasion_internal_v1(p_occasion_id bigint, p_link text, p_title text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    new_form_id BIGINT;
    new_form JSONB;
    new_product_type_id BIGINT;
    now TIMESTAMPTZ := NOW();
    payment_default text;
    initial_data jsonb := '{"is_reminder_enabled": true,"design":{"presale_header":"event_and_date"}}'::jsonb;
BEGIN
    SELECT public.resolve_payment_method_policy_internal(o.organization,o.unit)->>'preferredMethod' INTO payment_default
    FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
    WHERE o.id=p_occasion_id;
    IF payment_default='cash' THEN
      initial_data := initial_data || '{"payments":{"bankEnabled":false,"cashEnabled":true,"providerConnections":{}},"payment_deadline":{"mode":"none"}}'::jsonb;
    ELSIF public.payment_method_is_online_internal(payment_default) THEN
      -- A closed draft can await Connect without inventing a recipient or bank.
      initial_data := initial_data || '{"payments":{"bankEnabled":false}}'::jsonb;
    END IF;
    IF NOT (initial_data ? 'payments') THEN initial_data:=initial_data||jsonb_build_object('payments',jsonb_build_object('bankEnabled',payment_default='bank' AND public.payment_method_policy_enabled_internal((SELECT unit FROM public.occasions WHERE id=p_occasion_id),'bank'))); END IF;
    PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion_id));
    -- Create the new form
    INSERT INTO public.forms(
        title,
        is_open,
        link,
        occasion,
        created_at,
        updated_at,
        deadline_duration_seconds,
        data
    )
    VALUES (
        p_title,
        false,
        NULL,
        p_occasion_id,
        now,
        now,
        NULL, -- New forms inherit the occasion policy; legacy stored durations stay custom.
        initial_data
    )
    RETURNING to_jsonb(public.forms.*) INTO new_form;

    new_form_id := (new_form->>'id')::BIGINT;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,p_link,true) WHERE id=new_form_id;
    SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;

    -- Create default 'email' and 'ticket' fields
    INSERT INTO public.form_fields(title, type, is_required, form, "order")
    VALUES ('', 'email', true, new_form_id, 0),
           ('', 'ticket', true, new_form_id, 1);

    -- Ensure 'spot' product type exists for the occasion
    IF NOT EXISTS (SELECT 1 FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot') THEN
        INSERT INTO eshop.product_types(title, type, occasion)
        VALUES ('Spot', 'spot', p_occasion_id)
        RETURNING id INTO new_product_type_id;
    ELSE
        SELECT id INTO new_product_type_id FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot' LIMIT 1;
    END IF;

    -- Ensure the 'spot' product type has at least one product
    IF NOT EXISTS (SELECT 1 FROM eshop.products WHERE occasion = p_occasion_id AND product_type = new_product_type_id) THEN
        INSERT INTO eshop.products(title, price, product_type, occasion, currency_code, "order")
        VALUES ('Variant 1', 100, new_product_type_id, p_occasion_id, 'CZK', 0);
    END IF;

    -- Create the 'product_type' form field linked to 'spot'
    INSERT INTO public.form_fields(title, type, is_required, form, "order", product_type, is_ticket_field)
    VALUES ('Spot', 'product_type', false, new_form_id, 2, new_product_type_id, true);

    IF EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion_id AND
      jsonb_path_exists(features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN
      INSERT INTO public.form_fields(form,type,is_ticket_field,is_required,is_hidden,"order")
      VALUES(new_form_id,'spot',true,true,false,-1);
      PERFORM public.sync_form_blueprint_internal(new_form_id);
      SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;
    END IF;

    -- Return the raw data of the newly created form
    PERFORM public.notification_center_form_created_internal(new_form_id);
    RETURN new_form;
END;
$function$;
REVOKE ALL ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) TO postgres;

-- Only the explicit occasion-create owner calls this initial-form boundary.
-- Manager-only creation uses its own domain right, not a fabricated editor role.
CREATE OR REPLACE FUNCTION public.create_initial_occasion_form_internal_v1(p_occasion_id bigint,p_link text,p_title text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_unit bigint;
BEGIN
  SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(v_unit)
    OR EXISTS(SELECT 1 FROM public.forms WHERE occasion=p_occasion_id) THEN
    RAISE insufficient_privilege USING MESSAGE='initial occasion form creation unavailable';
  END IF;
  PERFORM public.check_occasion_writable(p_occasion_id);
  RETURN public.insert_form_for_occasion_internal_v1(p_occasion_id,p_link,p_title);
END $$;
REVOKE ALL ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) TO postgres;

-- SOURCE: occasion_setup/drafts.sql
-- Round in the event tenant's civil time; a single captured instant owns defaults.
CREATE OR REPLACE FUNCTION public.occasion_setup_default_start_internal(p_now timestamptz,p_timezone text DEFAULT 'Europe/Prague')
RETURNS timestamptz LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT (date_trunc('hour',local_now) + ceil(extract(epoch FROM (local_now-date_trunc('hour',local_now)))/1800)*interval '30 minutes') AT TIME ZONE p_timezone
 FROM (SELECT (p_now AT TIME ZONE p_timezone)+interval '30 days' local_now) x;
$$;
REVOKE ALL ON FUNCTION public.occasion_setup_default_start_internal(timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;

-- Drafts are private workspace objects, never public occasions.
CREATE TABLE IF NOT EXISTS public.occasion_setup_drafts (
  id uuid PRIMARY KEY,
  unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  author uuid NOT NULL REFERENCES auth.users(id),
  data jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(data) = 'object' AND octet_length(data::text) <= 262144),
  revision bigint NOT NULL DEFAULT 1,
  current_step integer NOT NULL DEFAULT 0 CHECK (current_step BETWEEN 0 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.occasion_setup_drafts DROP CONSTRAINT IF EXISTS occasion_setup_drafts_current_step_check;
ALTER TABLE public.occasion_setup_drafts ADD CONSTRAINT occasion_setup_drafts_current_step_check CHECK (current_step BETWEEN 0 AND 6);
CREATE INDEX IF NOT EXISTS occasion_setup_drafts_unit_idx ON public.occasion_setup_drafts(unit);
ALTER TABLE public.occasion_setup_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_setup_drafts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_drafts(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY updated_at DESC)
    FROM public.occasion_setup_drafts d WHERE unit = p_unit AND NOT (d.data ? 'finalizedOccasion')), '[]'::jsonb);
END $$;

-- Terminal receipts remain readable to an already-open wizard, independently
-- of the resumable list. Never infer completion from a missing list item.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_draft(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
  IF NOT FOUND OR auth.uid() IS NULL OR public.can_create_occasion(d.unit) IS NOT TRUE THEN
    RAISE insufficient_privilege USING MESSAGE='Draft access denied';
  END IF;
  RETURN jsonb_set(to_jsonb(d),'{data}',public.normalize_setup_payments_internal(d.data));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_draft(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_draft(uuid) TO authenticated;

-- Run the canonical creator inside a rollback-only subtransaction. Its
-- complete configuration survives in a PL/pgSQL variable, but no occasion,
-- form, product, reminders or other rows escape into the normal application.
-- PostgreSQL sequences may advance; those IDs are draft-local references.
CREATE OR REPLACE FUNCTION public.build_occasion_setup_configuration(p_unit bigint, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE configuration jsonb; organization_id bigint;
  default_start timestamptz; event_zone text;
  provisional_link text := 'draft-' || p_id::text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT organization,coalesce(data->>'timezone','Europe/Prague') INTO organization_id,event_zone FROM public.units WHERE id = p_unit;
  default_start:=public.occasion_setup_default_start_internal(now(),event_zone);
  BEGIN
    PERFORM public.update_occasion_internal_v1(jsonb_build_object(
      'unit',p_unit,'organization',organization_id,'title','',
      'link',provisional_link,'is_hidden',true,'is_open',false,
      'features','[{"code":"form","is_enabled":true}]'::jsonb,
      'start_time',default_start,'end_time',((default_start AT TIME ZONE event_zone)+interval '3 days') AT TIME ZONE event_zone));
    SELECT public.occasion_setup_source_internal(id) INTO configuration
      FROM public.occasions WHERE link=provisional_link AND unit=p_unit;
    IF configuration IS NULL THEN RAISE EXCEPTION 'Creation configuration missing'; END IF;
    RAISE EXCEPTION 'Rollback provisional creation' USING ERRCODE = 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN
    -- Variables retain their values while all writes in the block roll back.
    NULL;
  END;
  configuration := jsonb_set(configuration,'{occasion,link}','""'::jsonb);
  configuration := jsonb_set(configuration,'{forms}',coalesce((SELECT jsonb_agg(jsonb_set(f,'{link}','""'::jsonb))
    FROM jsonb_array_elements(configuration->'forms') f),'[]'::jsonb));
  RETURN configuration;
END $$;
REVOKE ALL ON FUNCTION public.build_occasion_setup_configuration(bigint,uuid) FROM PUBLIC,anon,authenticated;

-- Client-generated UUID makes canonical draft initialization safe to retry.
CREATE OR REPLACE FUNCTION public.create_occasion_setup_draft(p_id uuid, p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb; is_new boolean; policy jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  -- Serialize identical UUIDs before inspecting existence, without charging retries.
  PERFORM pg_advisory_xact_lock(hashtextextended('draft:'||p_id::text,0));
  is_new:=NOT EXISTS(SELECT 1 FROM public.occasion_setup_drafts WHERE id=p_id);
  IF is_new THEN
    policy:=public.abuse_effective_rules_v1('occasion.draft',p_unit,(SELECT organization FROM public.units WHERE id=p_unit));
    PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,
      (SELECT organization FROM public.units WHERE id=p_unit),0,true,true,policy);
  END IF;
  INSERT INTO public.occasion_setup_drafts(id,unit,organization,author)
    SELECT p_id,id,organization,auth.uid() FROM public.units WHERE id = p_unit
    ON CONFLICT (id) DO NOTHING;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF d.unit IS DISTINCT FROM p_unit OR d.author IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (d.data ? 'defaultConfiguration') THEN
    IF NOT is_new THEN
      policy:=public.abuse_effective_rules_v1('occasion.draft',p_unit,d.organization);
      PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,d.organization,0,false,true,policy);
    END IF;
    configuration := public.build_occasion_setup_configuration(p_unit,p_id);
    UPDATE public.occasion_setup_drafts SET data =
      public.normalize_setup_payments_internal(jsonb_build_object('defaultConfiguration',configuration,
        'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true,
        'paymentMethod',public.resolve_payment_method_policy_internal(d.organization,d.unit)->>'preferredMethod',
        'paymentChoicesEnabled',EXISTS(SELECT 1 FROM jsonb_each(public.provider_unit_features_internal(d.unit)) x WHERE x.value='true'::jsonb))
      || d.data) WHERE id = p_id RETURNING * INTO d;
    PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,d.organization,octet_length(d.data::text),false,false,policy);
  END IF;
  RETURN jsonb_set(to_jsonb(d),'{data}',public.normalize_setup_payments_internal(d.data));
END $$;

CREATE OR REPLACE FUNCTION public.initialize_occasion_setup_draft_defaults(p_id uuid, p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb; policy jsonb;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'finalizedOccasion' OR
     (jsonb_typeof(d.data#>'{defaultConfiguration,forms}')='array' AND
      jsonb_array_length(d.data#>'{defaultConfiguration,forms}')>0) THEN RETURN jsonb_set(to_jsonb(d),'{data}',public.normalize_setup_payments_internal(d.data)); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = 'PT409';
  END IF;
  policy:=public.abuse_effective_rules_v1('occasion.draft',d.unit,d.organization);
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,0,false,true,policy);
  configuration := public.build_occasion_setup_configuration(d.unit,p_id);
  UPDATE public.occasion_setup_drafts SET data =
    public.normalize_setup_payments_internal(jsonb_build_object('defaultConfiguration',configuration,
      'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true,
        'paymentMethod',public.resolve_payment_method_policy_internal(d.organization,d.unit)->>'preferredMethod',
        'paymentChoicesEnabled',EXISTS(SELECT 1 FROM jsonb_each(public.provider_unit_features_internal(d.unit)) x WHERE x.value='true'::jsonb))
    || (d.data-'defaultConfiguration')), revision = revision+1, updated_at=now()
    WHERE id=p_id RETURNING * INTO d;
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,octet_length(d.data::text),false,false,policy);
  RETURN jsonb_set(to_jsonb(d),'{data}',public.normalize_setup_payments_internal(d.data));
END $$;
REVOKE ALL ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) TO authenticated;

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

CREATE OR REPLACE FUNCTION public.delete_occasion_setup_draft(p_id uuid, p_unit bigint, p_expected_revision bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF d.unit <> p_unit THEN RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501'; END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = 'PT409';
  END IF;
  DELETE FROM public.occasion_setup_drafts WHERE id = p_id;
END $$;

REVOKE ALL ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) TO authenticated;

-- SOURCE: payment_providers/template_policy.sql
-- Review records attest exact effective templates, never editable payment tokens.
CREATE TABLE IF NOT EXISTS eshop.payment_template_reviews (
 occasion_id bigint PRIMARY KEY REFERENCES public.occasions(id) ON DELETE CASCADE,
 revision text NOT NULL,reviewed_by uuid NOT NULL,reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE eshop.payment_template_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.payment_template_reviews FROM PUBLIC,anon,authenticated,service_role;
-- Monotonic per-occasion epoch prevents A-B-A content changes from reviving a
-- prepared snapshot, without invalidating another organizer's templates.
CREATE TABLE IF NOT EXISTS eshop.payment_template_epochs (
 occasion_id bigint PRIMARY KEY REFERENCES public.occasions(id) ON DELETE CASCADE,
 revision bigint NOT NULL DEFAULT 0
);
ALTER TABLE eshop.payment_template_epochs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.payment_template_epochs FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.payment_template_audit_internal(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; code text; resolved jsonb; evidence jsonb:='[]'; blockers jsonb:='[]'; part text; content text; v_revision text;
BEGIN
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=p_occasion;
 FOREACH code IN ARRAY ARRAY['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_UPDATE','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_STORNO'] LOOP
  resolved:=public.get_email_template_and_wrapper(code,jsonb_build_object('occasion',oc.id,'unit',oc.unit,'organization',oc.organization));
  evidence:=evidence||jsonb_build_array(jsonb_build_object('code',code,'resolved',resolved));
  FOREACH part IN ARRAY ARRAY['template','wrapper'] LOOP
   content:=coalesce(resolved#>>ARRAY[part,'html'],'')||' '||coalesce(resolved#>>ARRAY[part,'subject'],'');
   -- A conservative aid, not a claim to understand arbitrary authored HTML.
   IF content ~* '(\{\{\s*(iban|accountNumber|variableSymbol)\s*\}\}|qr-payment|SPD\*|BCD[[:space:]]|[A-Z]{2}[0-9]{2}[[:space:]]?([A-Z0-9][[:space:]]?){11,30}|[0-9]{2,10}/[0-9]{4})' THEN
    blockers:=blockers||jsonb_build_array(jsonb_build_object('code',code,'location',part,'templateId',resolved#>ARRAY[part,'id'],'reason','authored_bank_instructions'));
   END IF;
  END LOOP;
 END LOOP;
 v_revision:=encode(extensions.digest(jsonb_build_object('templates',evidence,'epoch',coalesce((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=oc.id),0))::text,'sha256'),'hex');
 RETURN jsonb_build_object('revision',v_revision,'blockers',blockers,'compatible',jsonb_array_length(blockers)=0,
  'reviewed',EXISTS(SELECT 1 FROM eshop.payment_template_reviews WHERE occasion_id=oc.id AND payment_template_reviews.revision=v_revision));
END $$;
REVOKE ALL ON FUNCTION public.payment_template_audit_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_payment_template_audit(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint;
BEGIN
 SELECT occasion INTO oc FROM public.forms WHERE id=p_form;
 IF oc IS NULL OR NOT public.can_read_occasion_email_templates(oc) THEN RAISE insufficient_privilege; END IF;
 RETURN public.payment_template_audit_internal(oc)||jsonb_build_object('canReview',public.can_write_occasion_email_templates(oc));
END $$;
CREATE OR REPLACE FUNCTION public.review_payment_templates(p_form bigint,p_revision text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; audit jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.forms WHERE id=p_form;
 IF oc IS NULL OR NOT public.can_write_occasion_email_templates(oc) THEN RAISE insufficient_privilege; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('payment-template-review:'||oc,0));
 audit:=public.payment_template_audit_internal(oc);
 IF p_revision IS DISTINCT FROM audit->>'revision' THEN RAISE EXCEPTION 'PAYMENT_TEMPLATE_REVIEW_STALE'; END IF;
 IF audit->'compatible' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_TEMPLATE_BANK_CONTENT_REQUIRES_REPAIR'; END IF;
 INSERT INTO eshop.payment_template_reviews(occasion_id,revision,reviewed_by) VALUES(oc,p_revision,auth.uid())
 ON CONFLICT(occasion_id) DO UPDATE SET revision=excluded.revision,reviewed_by=excluded.reviewed_by,reviewed_at=clock_timestamp();
 RETURN public.payment_template_audit_internal(oc);
END $$;
REVOKE ALL ON FUNCTION public.get_payment_template_audit(bigint),public.review_payment_templates(bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_payment_template_audit(bigint),public.review_payment_templates(bigint,text) TO authenticated;

-- Explicit authoring boundary, called before hierarchy/row locks. No persistent
-- application trigger: command owners attest writes in the same transaction.
CREATE OR REPLACE FUNCTION public.payment_template_write_scope_internal(p_context jsonb,p_invalidate boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE org bigint;
BEGIN
 IF p_context IS NULL OR jsonb_typeof(p_context)<>'object' THEN
  RAISE invalid_parameter_value USING MESSAGE='Template write scope required'; END IF;
 FOR org IN SELECT o.id FROM public.organizations o WHERE
  CASE WHEN p_context->>'occasion' IS NOT NULL THEN EXISTS(SELECT 1 FROM public.occasions oc WHERE oc.id=(p_context->>'occasion')::bigint AND oc.organization=o.id)
   WHEN p_context->>'unit' IS NOT NULL THEN EXISTS(SELECT 1 FROM public.units u WHERE u.id=(p_context->>'unit')::bigint AND u.organization=o.id)
   WHEN p_context->>'organization' IS NOT NULL THEN o.id=(p_context->>'organization')::bigint
   ELSE true END ORDER BY o.id LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('payment-policy:'||org,0));
  IF p_invalidate THEN
   INSERT INTO eshop.payment_template_epochs(occasion_id,revision)
   SELECT oc.id,1 FROM public.occasions oc WHERE oc.organization=org AND
    CASE WHEN p_context->>'occasion' IS NOT NULL THEN oc.id=(p_context->>'occasion')::bigint
     WHEN p_context->>'unit' IS NOT NULL THEN oc.unit=(p_context->>'unit')::bigint
     ELSE true END
   ON CONFLICT(occasion_id) DO UPDATE SET revision=payment_template_epochs.revision+1;
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.payment_template_write_scope_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
-- Retire the earlier local candidate; no installed migration is rewritten.
DROP TRIGGER IF EXISTS payment_template_policy_fence ON public.email_templates;
DROP TRIGGER IF EXISTS payment_template_policy_fence ON public.email_wrappers;
DROP FUNCTION IF EXISTS public.payment_template_policy_fence_internal();
-- All supported runtime authors use the checked definer commands above.
-- Direct API table writes cannot bypass the explicit fence/epoch owner.
REVOKE INSERT,UPDATE,DELETE ON public.email_templates,public.email_wrappers FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: others/email_template_commands.sql
-- Shared content invariant for ordinary saves and setup-draft overrides.
CREATE OR REPLACE FUNCTION public.validate_email_template_content_internal(p_code text,p_html text)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
 IF p_code='TICKET_ORDER_PAYMENT_DONE' AND
  (length(coalesce(p_html,''))-length(replace(coalesce(p_html,''),'{{tickets}}','')))/length('{{tickets}}')>1 THEN
  RAISE invalid_parameter_value USING MESSAGE='Only one tickets block is allowed'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.validate_email_template_content_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.lock_email_template_hierarchy_internal(p_context jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.payment_template_write_scope_internal(p_context);
 PERFORM 1 FROM public.organizations WHERE id=(p_context->>'organization')::bigint FOR SHARE;
 IF p_context->>'occasion' IS NOT NULL THEN
  PERFORM 1 FROM public.units WHERE id=(p_context->>'unit')::bigint FOR SHARE;
  PERFORM 1 FROM public.occasions WHERE id=(p_context->>'occasion')::bigint FOR UPDATE;
 ELSIF p_context->>'unit' IS NOT NULL THEN
  PERFORM 1 FROM public.units WHERE id=(p_context->>'unit')::bigint FOR UPDATE;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_email_template_hierarchy_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Typed authoring boundary. Scope narrows live rights; template text is data.
CREATE OR REPLACE FUNCTION public.check_email_template_scope_internal(
 p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,p_write boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o bigint; u bigint; c bigint;
BEGIN
 IF auth.uid() IS NULL OR p_organization IS NULL OR p_entity_id IS NULL THEN
  RAISE insufficient_privilege USING MESSAGE='email template scope required'; END IF;
 IF p_entity_type='occasion' THEN
  SELECT organization,unit,id INTO o,u,c FROM public.occasions WHERE id=p_entity_id;
  IF NOT FOUND OR (CASE WHEN p_write THEN public.can_write_occasion_email_templates(c)
     ELSE public.can_read_occasion_email_templates(c) END) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='email template access denied'; END IF;
 ELSIF p_entity_type='unit' THEN
  SELECT organization,id INTO o,u FROM public.units WHERE id=p_entity_id;
  IF NOT FOUND OR (CASE WHEN p_write THEN public.can_write_unit_email_templates(u)
     ELSE public.can_read_unit_email_templates(u) END) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='email template access denied'; END IF;
 ELSE RAISE invalid_parameter_value USING MESSAGE='invalid email template entity'; END IF;
 IF o IS DISTINCT FROM p_organization OR (p_unit IS NOT NULL AND u IS DISTINCT FROM p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='email template hierarchy changed'; END IF;
 RETURN jsonb_build_object('occasion',c,'unit',u,'organization',o);
END $$;
REVOKE ALL ON FUNCTION public.check_email_template_scope_internal(text,bigint,bigint,bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- The effective row and target override together form the compare-and-set token.
-- A newly created/deleted override changes identity even if its text is identical.
CREATE OR REPLACE FUNCTION public.get_email_template_state_internal(p_context jsonb,p_code text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT effective || jsonb_build_object('source',jsonb_build_object(
  'type',CASE WHEN effective->>'occasion' IS NOT NULL THEN 'occasion'
    WHEN effective->>'unit' IS NOT NULL THEN 'unit'
    WHEN effective->>'organization' IS NOT NULL THEN 'organization' ELSE 'global' END,
  'id',to_jsonb(coalesce((effective->>'occasion')::bigint,(effective->>'unit')::bigint,(effective->>'organization')::bigint))),
  'revision',encode(extensions.digest(convert_to(jsonb_build_object('effective',effective,
    'override',(SELECT to_jsonb(t) FROM public.email_templates t WHERE t.code=p_code AND
      CASE WHEN p_context->>'occasion' IS NOT NULL THEN t.occasion=(p_context->>'occasion')::bigint
      ELSE t.occasion IS NULL AND t.unit=(p_context->>'unit')::bigint END
      ORDER BY t.id DESC LIMIT 1))::text,'UTF8'),'sha256'),'hex'))
 FROM (SELECT public.get_resolved_email_template(p_code,p_context) effective) s;
$$;
REVOKE ALL ON FUNCTION public.get_email_template_state_internal(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_template_catalog(
 p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,p_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; templates jsonb; result jsonb;
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 SELECT coalesce(jsonb_agg(CASE WHEN p_code IS NULL THEN t-'html' ELSE t END ORDER BY t->>'code'),'[]')
 INTO templates FROM jsonb_array_elements(public.get_all_email_templates(context)) t
 WHERE p_code IS NULL OR t->>'code'=p_code;
 IF p_code IS NOT NULL AND jsonb_array_length(templates)=0 THEN
  RAISE invalid_parameter_value USING MESSAGE='template unavailable in this scope'; END IF;
 result:=jsonb_build_object('entityType',p_entity_type,'entityId',p_entity_id,'templates',templates);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='email template result too large'; END IF;
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_template_catalog(text,bigint,bigint,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_email_template_catalog(text,bigint,bigint,bigint,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_email_template(
 p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,
 p_action text,p_code text,p_expected_revision text,p_payload jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; state jsonb; started jsonb; hash text; name text; result jsonb; audience uuid[];
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit,true);
 IF p_action IS NULL OR p_action NOT IN ('save','reset') OR p_code IS NULL
  OR p_expected_revision IS NULL OR p_expected_revision !~ '^[0-9a-f]{64}$'
  OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>524288
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('title','subject','html'))
  OR (p_action='save' AND (NOT p_payload ?& ARRAY['title','subject','html'] OR EXISTS(
    SELECT 1 FROM jsonb_each(p_payload) e WHERE jsonb_typeof(e.value) NOT IN ('string','null'))))
  OR (p_action='reset' AND p_payload<>'{}'::jsonb) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid email template command'; END IF;
 name:=p_entity_type||'.email_template.'||p_action;
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('context',context,'action',p_action,
  'code',p_code,'expectedRevision',p_expected_revision,'payload',p_payload)::text,'UTF8'),'sha256'),'hex');
 IF p_entity_type='occasion' THEN
  started:=public.begin_client_mutation_v1(p_command_id,name,p_entity_id,auth.uid(),hash);
 ELSE started:=public.begin_unit_client_mutation_v1(p_command_id,name,p_entity_id,auth.uid(),hash); END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 -- Receipt -> hierarchy -> target. Legacy writes use these same hierarchy locks.
 PERFORM public.lock_email_template_hierarchy_internal(context);
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit,true);
 SELECT t INTO state FROM jsonb_array_elements(public.get_all_email_templates(context)) t WHERE t->>'code'=p_code;
 IF state IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='template unavailable in this scope'; END IF;
 IF state->>'revision' IS DISTINCT FROM p_expected_revision THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','EMAIL_TEMPLATE_CHANGED'));
 END IF;
 IF p_action='save' THEN
  PERFORM public.update_email_template(p_payload||context||jsonb_build_object('code',p_code));
 ELSE PERFORM public.delete_entity_email_template(p_entity_type,p_entity_id,p_code); END IF;
 result:=public.get_email_template_catalog(p_entity_type,p_entity_id,p_organization,p_unit,p_code);
 IF p_entity_type='unit' THEN
  RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_entity_id,name,'email_template',p_entity_id,'update',result);
 END IF;
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_entity_id,name,'configuration',
  jsonb_build_array(jsonb_build_object('entityType','email_template','entityId',p_entity_id,'operation','update',
   'safeLabel','Email template','changedFields',jsonb_build_array('template'))),'{}'::text[],'[]','[]',result);
END $$;
REVOKE ALL ON FUNCTION public.manage_email_template(text,bigint,bigint,bigint,text,text,text,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_email_template(text,bigint,bigint,bigint,text,text,text,jsonb,uuid) TO authenticated;

-- Wrapper selection remains owned by the sending resolver, never a MCP copy.
CREATE OR REPLACE FUNCTION public.get_email_banner_state_internal(p_context jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('overrideUrl',own_url,'inheritedUrl',inherited_url,
  'effectiveUrl',coalesce(own_url,inherited_url),'wrapperHtml',resolved->'wrapper'->'html',
  'revision',encode(extensions.digest(convert_to(jsonb_build_object('ownUrl',own_url,
    'inheritedUrl',inherited_url,'wrapper',resolved->'wrapper')::text,'UTF8'),'sha256'),'hex'))
 FROM (SELECT public.get_email_template_and_wrapper('',p_context) resolved,
  CASE WHEN p_context->>'occasion' IS NOT NULL THEN o.data->>'email_banner'
    ELSE u.data->>'email_banner' END own_url,
  CASE WHEN p_context->>'occasion' IS NOT NULL THEN coalesce(u.data->>'email_banner',org.data->>'email_banner')
    ELSE org.data->>'email_banner' END inherited_url
  FROM public.organizations org
  JOIN public.units u ON u.id=(p_context->>'unit')::bigint AND u.organization=org.id
  LEFT JOIN public.occasions o ON o.id=(p_context->>'occasion')::bigint AND o.unit=u.id
  WHERE org.id=(p_context->>'organization')::bigint) s;
$$;
REVOKE ALL ON FUNCTION public.get_email_banner_state_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_banner(p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; result jsonb;
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 result:=public.get_email_banner_state_internal(context)||jsonb_build_object('entityType',p_entity_type,'entityId',p_entity_id);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='email banner too large'; END IF;
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_banner(text,bigint,bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_email_banner(text,bigint,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_email_banner(p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,
 p_expected_revision text,p_banner_url text,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; state jsonb; started jsonb; hash text; name text; result jsonb;
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit,true);
 IF p_expected_revision IS NULL OR p_expected_revision !~ '^[0-9a-f]{64}$'
  OR (p_banner_url IS NOT NULL AND (length(p_banner_url)>8192
    OR p_banner_url !~ '^https://(a\.)?img\.festapp\.net/(images|assets)/[A-Za-z0-9_./-]+$'
    OR p_banner_url LIKE '%/../%')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid email banner command'; END IF;
 name:=p_entity_type||'.email_banner.save';
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('context',context,
   'expectedRevision',p_expected_revision,'url',p_banner_url)::text,'UTF8'),'sha256'),'hex');
 IF p_entity_type='occasion' THEN
  started:=public.begin_client_mutation_v1(p_command_id,name,p_entity_id,auth.uid(),hash);
 ELSE started:=public.begin_unit_client_mutation_v1(p_command_id,name,p_entity_id,auth.uid(),hash); END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 PERFORM public.lock_email_template_hierarchy_internal(context);
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit,true);
 state:=public.get_email_banner_state_internal(context);
 IF state->>'revision' IS DISTINCT FROM p_expected_revision THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','EMAIL_BANNER_CHANGED'));
 END IF;
 PERFORM public.update_entity_email_banner(p_entity_type,p_entity_id,p_banner_url);
 result:=public.get_email_banner(p_entity_type,p_entity_id,p_organization,p_unit);
 IF p_entity_type='unit' THEN
  RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_entity_id,name,'unit',p_entity_id,'update',result);
 END IF;
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_entity_id,name,'configuration',
  jsonb_build_array(jsonb_build_object('entityType','occasion','entityId',p_entity_id,'operation','update',
   'safeLabel','Email banner','changedFields',jsonb_build_array('email_banner'))),ARRAY['occasion_config'],'[]','[]',result,
  '{}'::text[],'[]','user',NULL,'[]',ARRAY[(context->>'unit')::bigint]);
END $$;
REVOKE ALL ON FUNCTION public.manage_email_banner(text,bigint,bigint,bigint,text,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_email_banner(text,bigint,bigint,bigint,text,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_email_template_preview_context(
 p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; catalog jsonb; result jsonb;
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 catalog:=public.get_email_template_catalog(p_entity_type,p_entity_id,p_organization,p_unit,p_code);
 result:=public.get_email_template_and_wrapper(p_code,context)||jsonb_build_object('context',context);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='email preview too large'; END IF;
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_template_preview_context(text,bigint,bigint,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_email_template_preview_context(text,bigint,bigint,bigint,text) TO authenticated;

-- SOURCE: others/update_email_template.sql
CREATE OR REPLACE FUNCTION public.update_email_template(p_data jsonb)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  v_occ   bigint;
  v_unit  bigint;
  v_org   bigint;
  v_code  text;
  v_existing_id bigint;
  v_actual_unit bigint;
  v_actual_org bigint;
  v_changed bigint;
BEGIN
  -- Extract values from input JSON.
  v_occ  := CASE WHEN p_data ? 'occasion' THEN (p_data ->> 'occasion')::bigint ELSE NULL END;
  v_unit := CASE WHEN p_data ? 'unit' THEN (p_data ->> 'unit')::bigint ELSE NULL END;
  v_org := (p_data ->> 'organization')::bigint;
  v_code := p_data ->> 'code';

  -- Resolve the actual hierarchy before authorizing template writes.
  IF v_occ IS NOT NULL THEN
    SELECT unit, organization INTO v_actual_unit, v_actual_org FROM public.occasions WHERE id=v_occ;
    IF NOT FOUND OR (v_unit IS NOT NULL AND v_unit IS DISTINCT FROM v_actual_unit)
        OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE='Invalid email template hierarchy';
    END IF;
    v_unit := v_actual_unit;
    v_org := v_actual_org;
    IF NOT public.is_service_role() AND public.can_write_occasion_email_templates(v_occ) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Occasion template write denied';
    END IF;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_actual_org FROM public.units WHERE id=v_unit;
    IF NOT FOUND OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE='Invalid email template hierarchy';
    END IF;
    v_org := v_actual_org;
    IF NOT public.is_service_role() AND public.can_write_unit_email_templates(v_unit) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Unit template write denied';
    END IF;
  ELSIF NOT public.is_service_role() THEN
    IF v_org IS NULL OR public.can_manage_organization_email_templates(v_org) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Organization template write denied';
    END IF;
  END IF;

  PERFORM public.lock_email_template_hierarchy_internal(jsonb_build_object('occasion',v_occ,'unit',v_unit,'organization',v_org));

  PERFORM public.validate_email_template_content_internal(v_code,p_data->>'html');

  -- An occasion override is identified by occasion + code. Ancestors are
  -- metadata, not identity; the partial unique index also fences concurrent saves.
  IF v_occ IS NOT NULL THEN
    INSERT INTO public.email_templates (html, occasion, subject, organization, code, unit, title)
    VALUES (p_data->>'html', v_occ, p_data->>'subject', v_org, v_code, v_unit, p_data->>'title')
    ON CONFLICT (occasion, code) WHERE occasion IS NOT NULL
    DO UPDATE SET html=EXCLUDED.html, subject=EXCLUDED.subject, title=EXCLUDED.title,
                  unit=EXCLUDED.unit, organization=EXCLUDED.organization
    WHERE (email_templates.html,email_templates.subject,email_templates.title,email_templates.unit,email_templates.organization)
      IS DISTINCT FROM (EXCLUDED.html,EXCLUDED.subject,EXCLUDED.title,EXCLUDED.unit,EXCLUDED.organization);
    GET DIAGNOSTICS v_changed=ROW_COUNT;
    IF v_changed>0 THEN
      PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',v_occ,'unit',v_unit,'organization',v_org),true);
    END IF;
    RETURN;
  END IF;

  -- Try to find an existing email template matching the given context and code.
  SELECT id
    INTO v_existing_id
  FROM public.email_templates
  WHERE
    ((occasion = v_occ) OR (occasion IS NULL AND v_occ IS NULL))
    AND ((unit = v_unit) OR (unit IS NULL AND v_unit IS NULL))
    AND ((organization = v_org) OR (organization IS NULL AND v_org IS NULL))
    AND code = v_code
  LIMIT 1;

  IF FOUND THEN
    -- Update the existing record.
    UPDATE public.email_templates
    SET
      html    = p_data ->> 'html',
      subject = p_data ->> 'subject',
      title   = p_data ->> 'title'
    WHERE id = v_existing_id AND (html,subject,title) IS DISTINCT FROM (p_data->>'html',p_data->>'subject',p_data->>'title');
  ELSE
    -- Insert a new record.
    INSERT INTO public.email_templates (
      html,
      occasion,
      subject,
      organization,
      code,
      unit,
      title
    )
    VALUES (
      p_data ->> 'html',
      v_occ,
      p_data ->> 'subject',
      v_org,
      v_code,
      v_unit,
      p_data ->> 'title'
    );
  END IF;
  GET DIAGNOSTICS v_changed=ROW_COUNT;
  IF v_changed>0 THEN
    PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',v_occ,'unit',v_unit,'organization',v_org),true);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_email_template(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_email_template(jsonb) TO authenticated, service_role;

-- SOURCE: others/delete_entity_email_template.sql
create or replace function public.delete_entity_email_template(p_entity_type text, p_entity_id bigint, p_code text)
    returns void
    language plpgsql
    security definer
SET search_path = public, extensions
as
$$
declare
    v_changed bigint;
begin
    if p_entity_type = 'occasion' then
        if public.can_write_occasion_email_templates(p_entity_id) IS NOT TRUE then
            perform public.raise_error('permission_denied');
        end if;

        PERFORM public.lock_email_template_hierarchy_internal(CASE WHEN p_entity_type='occasion' THEN
          (SELECT jsonb_build_object('occasion',id,'unit',unit,'organization',organization) FROM public.occasions WHERE id=p_entity_id)
          ELSE (SELECT jsonb_build_object('unit',id,'organization',organization) FROM public.units WHERE id=p_entity_id) END);

        delete from public.email_templates
        where occasion = p_entity_id 
          and code = p_code;

    elsif p_entity_type = 'unit' then
        if (public.can_write_unit_email_templates(p_entity_id) IS NOT TRUE) then
            perform public.raise_error('permission_denied');
        end if;

        PERFORM public.lock_email_template_hierarchy_internal(CASE WHEN p_entity_type='occasion' THEN
          (SELECT jsonb_build_object('occasion',id,'unit',unit,'organization',organization) FROM public.occasions WHERE id=p_entity_id)
          ELSE (SELECT jsonb_build_object('unit',id,'organization',organization) FROM public.units WHERE id=p_entity_id) END);

        delete from public.email_templates
        where unit = p_entity_id
          and occasion is null
          and code = p_code;
    else
        raise exception 'Invalid entity type: %', p_entity_type;
    end if;
    GET DIAGNOSTICS v_changed=ROW_COUNT;
    IF v_changed>0 THEN
      PERFORM public.payment_template_write_scope_internal(jsonb_build_object(p_entity_type,p_entity_id),true);
    END IF;
end;
$$;

-- SOURCE: others/update_entity_email_banner.sql
-- null inherits the existing wrapper; empty text explicitly suppresses its image.
CREATE OR REPLACE FUNCTION public.email_banner_wrapper_internal(p_banner_url text,p_title text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_banner_url IS NULL THEN NULL ELSE
  '<div style="font-family: Arial, sans-serif; font-size: 16px; max-width: 680px; margin: 0 auto;">'
  ||CASE WHEN p_banner_url='' THEN '' ELSE '<div style="text-align: center;"><img src="'
    ||replace(replace(replace(replace(p_banner_url,'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;')
    ||'" alt="'||replace(replace(replace(replace(coalesce(p_title,'Banner'),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;')
    ||'" style="width: 100%; height: auto; display: block;"></div>' END
  ||'<div style="margin-top: 10px; margin-bottom: 10px; padding: 0 24px;">{{content}}</div></div>' END;
$$;
REVOKE ALL ON FUNCTION public.email_banner_wrapper_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;

create or replace function public.update_entity_email_banner(p_entity_type text, p_entity_id bigint, p_banner_url text)
    returns void
    language plpgsql
    security definer
SET search_path = public, extensions
as
$$
declare
    v_org_id bigint;
    v_entity_title text;
    v_new_html text;
    v_before jsonb;
    v_changed bigint;
begin
    -- Authorize before taking private policy or hierarchy locks.
    IF p_entity_type='occasion' THEN
      IF public.can_write_occasion_email_templates(p_entity_id) IS NOT TRUE THEN
        PERFORM public.raise_error('permission_denied'); END IF;
    ELSIF p_entity_type='unit' THEN
      IF public.can_write_unit_email_templates(p_entity_id) IS NOT TRUE THEN
        PERFORM public.raise_error('permission_denied'); END IF;
    ELSE RAISE EXCEPTION 'Invalid entity type: %',p_entity_type;
    END IF;
    PERFORM public.lock_email_template_hierarchy_internal(CASE WHEN p_entity_type='occasion' THEN
      (SELECT jsonb_build_object('occasion',id,'unit',unit,'organization',organization) FROM public.occasions WHERE id=p_entity_id)
      ELSE (SELECT jsonb_build_object('unit',id,'organization',organization) FROM public.units WHERE id=p_entity_id) END);

    if p_entity_type = 'occasion' then
        SELECT data INTO v_before FROM public.occasions WHERE id=p_entity_id FOR UPDATE;
        -- Update Occasion Data
        update public.occasions
        set data = jsonb_set(coalesce(data, '{}'), '{email_banner}', coalesce(to_jsonb(p_banner_url),'null'::jsonb))
        where id = p_entity_id
        returning organization, title into v_org_id, v_entity_title;

    elsif p_entity_type = 'unit' then
        SELECT data INTO v_before FROM public.units WHERE id=p_entity_id FOR UPDATE;
        -- Update Unit Data
        update public.units
        set data = jsonb_set(coalesce(data, '{}'), '{email_banner}', coalesce(to_jsonb(p_banner_url),'null'::jsonb))
        where id = p_entity_id
        returning organization, title into v_org_id, v_entity_title;

    else
        raise exception 'Invalid entity type: %', p_entity_type;
    end if;

    IF v_before IS DISTINCT FROM (CASE WHEN p_entity_type='occasion'
      THEN (SELECT data FROM public.occasions WHERE id=p_entity_id)
      ELSE (SELECT data FROM public.units WHERE id=p_entity_id) END) THEN
      INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES(p_entity_type,p_entity_type,p_entity_id,p_entity_id::text,1)
      ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
      SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
    END IF;

    -- 2. Handle HTML Wrapper Logic
    if p_banner_url is not null then
        v_new_html := public.email_banner_wrapper_internal(p_banner_url, v_entity_title);

        -- Upsert Wrapper
        if p_entity_type = 'occasion' then
             -- For occasion, check existing wrapper
            if exists (select 1 from public.email_wrappers where occasion = p_entity_id) then
                update public.email_wrappers set html = v_new_html where occasion = p_entity_id AND html IS DISTINCT FROM v_new_html;
            else
                insert into public.email_wrappers (occasion, organization, unit, title, html)
                values (p_entity_id, v_org_id, (select unit from occasions where id = p_entity_id), 'Occasion Banner Wrapper', v_new_html);
            end if;
        elsif p_entity_type = 'unit' then
             -- For unit (occasion is null)
            if exists (select 1 from public.email_wrappers where unit = p_entity_id and occasion is null) then
                update public.email_wrappers set html = v_new_html where unit = p_entity_id and occasion is null AND html IS DISTINCT FROM v_new_html;
            else
                insert into public.email_wrappers (occasion, organization, unit, title, html)
                values (null, v_org_id, p_entity_id, 'Unit Banner Wrapper', v_new_html);
            end if;
        end if;
    else
        -- 3. Banner Removed -> Delete Wrapper
        if p_entity_type = 'occasion' then
            delete from public.email_wrappers where occasion = p_entity_id;
        elsif p_entity_type = 'unit' then
            delete from public.email_wrappers where unit = p_entity_id and occasion is null;
        end if;
    end if;
    GET DIAGNOSTICS v_changed=ROW_COUNT;
    IF v_changed>0 THEN
      PERFORM public.payment_template_write_scope_internal(jsonb_build_object(p_entity_type,p_entity_id),true);
    END IF;
end;
$$;

REVOKE ALL ON FUNCTION public.update_entity_email_banner(text,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_entity_email_banner(text,bigint,text) TO authenticated;

-- SOURCE: payment_providers/collection_action.sql
-- Customer-facing collection eligibility is separate from financial history.
CREATE OR REPLACE FUNCTION public.payment_collection_action_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; oc public.occasions; policy jsonb; allowed boolean; reason text; fin record; template_audit jsonb; availability jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF pi.id IS NULL THEN RETURN jsonb_build_object('action','collect_payment','purpose','collect_payment','method',NULL,'sourceOrderId',o.id,'allowed',false,'policyRevision','0','reason','no_payment_identity'); END IF;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 IF NOT EXISTS(SELECT 1 FROM public.units WHERE id=oc.unit AND organization=oc.organization) THEN
  RETURN jsonb_build_object('action','collect_payment','purpose','collect_payment','method',pi.payment_method,'sourceOrderId',o.id,'allowed',false,'policyRevision','0','reason','payment_policy_scope_mismatch');
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=o.form AND occasion=o.occasion) THEN
  RETURN jsonb_build_object('action','collect_payment','purpose','collect_payment','method',pi.payment_method,'sourceOrderId',o.id,'allowed',false,'policyRevision','0','reason','collection_form_unavailable');
 END IF;
 policy:=public.resolve_payment_method_policy_internal(oc.organization,oc.unit);
 SELECT * INTO fin FROM public.payment_financial_totals_bulk_internal(ARRAY[pi.id]);
 availability:=public.form_payment_availability_internal(o.form);
 allowed:=coalesce(policy#>ARRAY['methods',pi.payment_method,'policyEnabled']='true'::jsonb,false)
  AND o.state IN ('ordered','created','paid','sent') AND pi.amount>coalesce(fin.net_received,0)
  AND NOT coalesce(fin.invalid_identity,true) AND coalesce(fin.disputed,0)=0
  AND (pi.deadline>now() OR (pi.payment_method IN ('bank','cash') AND (pi.data#>>'{payment_policy,mode}'='none' OR pi.deposit_amount IS NOT NULL)))
  AND CASE WHEN public.payment_method_is_online_internal(pi.payment_method) THEN availability#>ARRAY['providers',pi.payment_method,'collectionAvailable']='true'::jsonb ELSE availability->'available' ? pi.payment_method END;
 template_audit:=public.payment_template_audit_internal(o.occasion);
 IF public.payment_method_is_online_internal(pi.payment_method) THEN
  allowed:=allowed AND template_audit->'compatible'='true'::jsonb AND (
   public.payment_method_policy_enabled_internal(oc.unit,'bank') OR template_audit->'reviewed'='true'::jsonb);
 END IF;
 reason:=CASE WHEN policy#>ARRAY['methods',pi.payment_method,'policyEnabled'] IS DISTINCT FROM 'true'::jsonb THEN 'method_policy_disabled'
  WHEN NOT coalesce(allowed,false) THEN 'collection_unavailable' END;
 RETURN jsonb_build_object('action','collect_payment','purpose','collect_payment','method',pi.payment_method,'sourceOrderId',o.id,
  'allowed',coalesce(allowed,false),'policyRevision',coalesce(policy#>>ARRAY['methods',pi.payment_method,'revision'],'0')||':'||coalesce(template_audit->>'revision',''),'reason',reason);
END $$;
REVOKE ALL ON FUNCTION public.payment_collection_action_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

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
        'occasion', to_jsonb(occ.*)||jsonb_build_object('locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=occ.organization),'cs')),
        -- Same statement snapshot as the ticket feature used by delivery.
        'wallet', jsonb_build_object(
          'feature',(SELECT f FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'),
          'fingerprint',coalesce(((SELECT f->>'is_enabled' FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'))::boolean,false)::text
            ||'/'||public.ticket_wallet_enabled((SELECT f FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'))::text
            ||'/'||public.ticket_wallet_ready(occ.organization)::text),
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

-- SOURCE: emails/queue_payment_reminders.sql
CREATE OR REPLACE FUNCTION public.queue_payment_reminders_internal(p_occasion_id BIGINT, p_payment_info_id BIGINT)
RETURNS VOID
SET search_path = public, extensions AS $$
-- NULL payment scope is reserved for explicit occasion-wide settings changes.
-- Checkout and deadline changes only replace reminders for their own payment.
BEGIN
  IF public.is_demo_occasion(p_occasion_id) THEN RETURN; END IF;

  UPDATE public.email_messages SET workflow_state='cancelled',last_error='reminder_superseded',lease_token=NULL,lease_until=NULL
  WHERE ((p_payment_info_id IS NULL AND occasion=p_occasion_id) OR order_id IN (SELECT id FROM eshop.orders WHERE payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id AND (p_payment_info_id IS NULL OR payment_info=p_payment_info_id)))) AND message_kind='order_reminder' AND workflow_state IN ('pending','retry_wait','blocked','preparing');
  UPDATE eshop.payment_info pi SET email_reminder_version=email_reminder_version+1
  WHERE EXISTS(SELECT 1 FROM eshop.orders o WHERE o.payment_info=pi.id AND o.occasion=p_occasion_id AND (p_payment_info_id IS NULL OR pi.id=p_payment_info_id));

  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id
    ),occ.organization,o.occasion,occ.unit,pi.deadline - make_interval(secs=>coalesce((f.data->>'reminder_interval_seconds')::bigint,(form_settings.feature->>'reminder_interval_seconds')::bigint,86400))) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE

  LEFT JOIN public.forms f ON f.id = o.form
  WHERE
    o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id AND (p_payment_info_id IS NULL OR payment_info=p_payment_info_id))
    AND o.state = 'ordered'
    AND pi.payment_method='bank' AND public.payment_collection_action_internal(o.id)->'allowed'='true'::jsonb
    AND pi.data#>>'{payment_policy,mode}' IS DISTINCT FROM 'none'
    AND pi.deadline IS NOT NULL

    AND (pi.data->>'current_version_reminded')::boolean IS NOT TRUE

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE

    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, (form_settings.feature->>'reminder_is_enabled')::boolean, TRUE) IS TRUE;

  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id,
      'is_deposit_reminder', true
    ),occ.organization,o.occasion,occ.unit,(occ.start_time - make_interval(days => (deposit_settings.feature->>'deposit_deadline_days')::int)) - make_interval(secs=>coalesce((f.data->>'reminder_interval_seconds')::bigint,(form_settings.feature->>'reminder_interval_seconds')::bigint,86400))) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'deposit'
  ) deposit_settings ON TRUE

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE
  LEFT JOIN public.forms f ON f.id = o.form
  WHERE
    o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id AND (p_payment_info_id IS NULL OR payment_info=p_payment_info_id))
    -- Schedule the balance reminder before deposit payment, as order creation always did.
    AND o.state IN ('ordered','paid')
    AND pi.payment_method='bank' AND public.payment_collection_action_internal(o.id)->'allowed'='true'::jsonb
    AND pi.data#>>'{payment_policy,mode}' IS DISTINCT FROM 'none'
    AND pi.deposit_amount IS NOT NULL
    AND coalesce(pi.paid,0)-coalesce(pi.returned,0) < pi.amount

    AND (deposit_settings.feature->>'is_enabled')::boolean IS TRUE

    AND (deposit_settings.feature->>'deposit_deadline') IS DISTINCT FROM 'on_site'

    AND (deposit_settings.feature->>'deposit_deadline_days') IS NOT NULL

    AND occ.start_time IS NOT NULL

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE
    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, (form_settings.feature->>'reminder_is_enabled')::boolean, TRUE) IS TRUE;

END;
$$ LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION public.queue_payment_reminders_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the published occasion-wide scheduling boundary and interval argument.
CREATE OR REPLACE FUNCTION public.queue_payment_reminders(p_occasion_id BIGINT,p_seconds_before_deadline BIGINT)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.queue_payment_reminders_internal(p_occasion_id,NULL);
$$;

-- SOURCE: emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.wake_email_worker() RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF current_setting('festapp.email_wake',true)='scheduled' THEN RETURN; END IF;
 SELECT worker_url INTO v_url FROM public.email_capacity WHERE NOT paused;
 IF v_url IS NULL OR NOT (EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now())
  OR EXISTS(SELECT 1 FROM public.email_capacity WHERE quota_at IS NULL OR quota_at<now()-interval '5 minutes')) THEN RETURN; END IF;
 PERFORM set_config('festapp.email_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=v_url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  -- Do not invert producer order/message locks against gateway capacity/order locks.
  UPDATE public.email_capacity SET wake_error='wake_failed' WHERE ctid IN (SELECT ctid FROM public.email_capacity FOR UPDATE SKIP LOCKED);
 END;
END $$;

-- Internal service boundary. Domain functions are the only caller for public commands.
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 p_recipient:=public.normalize_order_email_contact(p_recipient);
 PERFORM public.check_occasion_writable(v_occ);
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF v_org IS NULL OR p_kind NOT IN ('order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer','sale_opening_opened')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 IF p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice') THEN
  p_data:=coalesce(p_data,'{}')||jsonb_build_object('collectionAction',public.payment_collection_action_internal(p_order));
 END IF;
 IF p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN
  p_data:=coalesce(p_data,'{}')||jsonb_build_object('paymentTemplateEpoch',coalesce((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=v_occ),0));
 END IF;
 -- Snapshot the tenant default only for new unlocalized domain intents. Existing
 -- messages, explicit locales and prepared/encrypted Auth content are untouched.
 IF NOT coalesce(p_data,'{}'::jsonb) ? 'lang' AND
    (p_kind LIKE 'order_%' OR p_kind IN ('waitlist_confirmation','waitlist_offer','sale_opening_opened')) AND
    (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=v_org)='en' THEN
   p_data:=coalesce(p_data,'{}'::jsonb)||'{"lang":"en"}'::jsonb;
 END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',CASE WHEN p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN p_data-'requested_by'-'collectionAction'-'paymentTemplateEpoch' ELSE p_data-'requested_by' END,'code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE organization=v_org AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 PERFORM public.admit_email_intent_v1(v_row.id);
 PERFORM public.notification_center_email_internal(v_row.message_id);
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb; v_template_epoch bigint; template_audit jsonb; bank_enabled boolean;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.access_invitations i WHERE i.message_id=p_message.message_id
   AND i.accepted_at IS NULL AND public.access_invitation_valid_internal_v1(i)
   AND i.email=p_message.recipient AND i.occasion IS NOT DISTINCT FROM p_message.occasion AND i.unit=p_message.unit AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_ACCESS_NOTICE' THEN
  RETURN public.can_manage_member_access_as_actor_internal_v1(p_message.producer_actor,
   CASE WHEN p_message.occasion IS NULL THEN 'unit' ELSE 'occasion' END,coalesce(p_message.occasion,p_message.unit))
   AND public.get_user_delivery_email(p_message.recipient_user)=p_message.recipient
   AND CASE WHEN p_message.occasion IS NULL THEN EXISTS(SELECT 1 FROM public.unit_users WHERE unit=p_message.unit AND "user"=p_message.recipient_user)
    ELSE EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_message.occasion AND "user"=p_message.recipient_user) END;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='MEASUREMENT_APPROVAL_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM analytics.unit_measurement_request q JOIN public.units u ON u.id=q.unit
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE q.unit=p_message.unit AND u.organization=p_message.organization AND NOT public.is_demo_unit(u.id)
    AND q.revision=coalesce((p_message.data->>'request_revision')::integer,1)
    AND (public.unit_measurement_approval_internal(u.id)->'approved'='false'::jsonb
     OR EXISTS(SELECT FROM jsonb_array_elements(q.requested_origins) x
      WHERE coalesce(u.data->'measurement_websites','[]'::jsonb) @> jsonb_build_array(x.value)
       AND NOT (public.unit_measurement_approval_internal(u.id)->'approved_origins' @> jsonb_build_array(x.value))))
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='BANK_SYNC_WARNING' THEN
  IF NOT EXISTS (SELECT 1 FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE h.connection_id=(p_message.data->>'connection_id')::bigint
      AND h.incident_id::text=p_message.data->>'incident_id'
      AND public.bank_sync_alert_ready(c.id)
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_confirmation' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_opened' THEN
  RETURN public.sale_opening_intent_valid_internal(p_message);
 END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.data->>'repair_payment_fingerprint' IS NOT NULL AND p_message.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(v_order.id) THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  v_template_epoch:=coalesce((SELECT e.revision FROM eshop.payment_template_epochs e WHERE e.occasion_id=v_order.occasion),0);
  bank_enabled:=coalesce(public.payment_method_policy_enabled_internal(v_occ.unit,'bank'),false);
  IF p_message.data ? 'paymentTemplateEpoch' THEN
   IF (p_message.data->>'paymentTemplateEpoch')::bigint IS DISTINCT FROM v_template_epoch THEN RETURN false; END IF;
  ELSIF p_message.prepared IS NOT NULL AND (NOT bank_enabled OR public.payment_method_is_online_internal(v_pi.payment_method)) THEN
   -- An encrypted legacy snapshot has no attestation for the current template.
   -- Preserve it as audit; a new authorized preparation must replace the intent.
   RETURN false;
  END IF;
  IF NOT bank_enabled OR public.payment_method_is_online_internal(v_pi.payment_method) THEN
   template_audit:=public.payment_template_audit_internal(v_order.occasion);
   IF template_audit->'compatible' IS DISTINCT FROM 'true'::jsonb THEN RETURN false; END IF;
  END IF;
 END IF;
 IF p_message.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice') THEN
  IF p_message.data#>>'{collectionAction,policyRevision}' IS NULL THEN RETURN false; END IF;
  IF public.payment_collection_action_internal(v_order.id)->'policyRevision' IS DISTINCT FROM p_message.data#>'{collectionAction,policyRevision}' THEN RETURN false; END IF;
 END IF;
 IF p_message.data#>'{collectionAction,allowed}'='true'::jsonb THEN
 IF (
  public.payment_collection_action_internal(v_order.id)->'allowed' IS DISTINCT FROM 'true'::jsonb OR
  public.payment_collection_action_internal(v_order.id)->'policyRevision' IS DISTINCT FROM p_message.data#>'{collectionAction,policyRevision}') THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND public.payment_method_is_online_internal(payment_method))
   AND public.provider_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_confirmation' THEN
  RETURN public.order_checkout_email_kind_internal(v_order.id)='order_confirmation'
   AND v_order.state IN ('ordered','paid') AND v_order.email_payment_version=p_message.source_version
   AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  IF public.payment_collection_action_internal(v_order.id)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN RETURN false; END IF;
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method<>'bank' OR v_pi.data#>>'{payment_policy,mode}'='none' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND coalesce(v_pi.paid,0)-coalesce(v_pi.returned,0)<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.recover_email_leases() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 -- Sending expiry is ambiguous, preparation expiry is safe to recover.
 UPDATE public.email_attempts a SET state='unknown',finished_at=now(),error_code='lease_expired'
 FROM public.email_messages m WHERE m.message_id=a.message_id AND m.workflow_state='sending' AND m.lease_until<now() AND a.state='sending';
 UPDATE public.email_messages SET workflow_state='unknown',last_error='lease_expired' WHERE workflow_state='sending' AND lease_until<now();
 UPDATE public.email_attempts a SET state='cancelled',finished_at=now() FROM public.email_messages m
 WHERE a.message_id=m.message_id AND a.lease_token=m.lease_token AND a.state='preparing' AND m.lease_until<now();
 UPDATE public.email_messages SET workflow_state='pending',lease_token=NULL,lease_until=NULL WHERE workflow_state='preparing' AND lease_until<now();

END $$;
REVOKE ALL ON FUNCTION public.recover_email_leases() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_leases() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_email() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_row public.email_messages; v_cap public.email_capacity; v_attempt uuid; v_token uuid:=extensions.gen_random_uuid(); v_wait integer;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_capacity SET heartbeat_at=now() WHERE singleton;
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_cap.circuit_until>now()
  OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='preparing' AND lease_until>now())>=v_cap.max_preparing THEN RETURN NULL; END IF;
 SELECT (x->>'base_limit')::integer INTO v_wait FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.dispatch',NULL,NULL)->'rules') x;
 IF v_wait IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 SELECT * INTO v_row FROM public.email_messages m
 WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()
 AND (m.prepared IS NOT NULL OR m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation')
  OR (SELECT count(*) FROM public.email_messages heavy WHERE heavy.workflow_state='preparing' AND heavy.lease_until>now() AND heavy.prepared IS NULL
   AND heavy.message_kind NOT IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation'))<greatest(1,v_cap.max_preparing-1))
 AND NOT EXISTS(SELECT 1 FROM public.email_messages prior WHERE prior.order_id=m.order_id AND prior.message_kind='order_confirmation'
  AND m.message_kind<>'order_confirmation' AND prior.workflow_state NOT IN ('accepted','cancelled','expired'))
 ORDER BY CASE WHEN m.created_at<=now()-make_interval(secs=>v_wait) THEN 0 ELSE priority END,
 (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.last_claimed_at IS NOT NULL) NULLS FIRST,
 CASE WHEN m.unit IS NULL THEN (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.unit IS NULL AND served.last_claimed_at IS NOT NULL)
 ELSE (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.unit=m.unit AND served.last_claimed_at IS NOT NULL) END NULLS FIRST,target_time,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF v_row.id IS NULL THEN RETURN NULL; END IF;
 IF NOT public.email_intent_valid(v_row) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN expires_at<=now() THEN 'expired' ELSE 'cancelled' END,last_error='intent_invalid' WHERE id=v_row.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 UPDATE public.email_messages SET workflow_state='preparing',last_claimed_at=now(),lease_token=v_token,lease_until=now()+interval '90 seconds' WHERE id=v_row.id RETURNING * INTO v_row;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(v_row.message_id,v_token,'preparing') RETURNING attempt_id INTO v_attempt;
 RETURN to_jsonb(v_row)||jsonb_build_object('attempt_id',v_attempt);
END $$;

-- Keep the global preparation permit while rendering still runs; expired workers cannot renew.
CREATE OR REPLACE FUNCTION public.renew_email_preparation(p_message uuid,p_token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET lease_until=now()+interval '90 seconds'
 WHERE message_id=p_message AND lease_token=p_token AND workflow_state='preparing' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.renew_email_preparation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.renew_email_preparation(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_email(p_message uuid,p_token uuid,p_prepared jsonb,p_post_action jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF octet_length(p_prepared::text)>(SELECT (x->>'base_limit')::bigint
  FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.payload',NULL,NULL)->'rules') x LIMIT 1) THEN
  RAISE configuration_limit_exceeded USING MESSAGE='email_payload_too_large'; END IF;
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now()),
 tracking_policy=CASE WHEN prepared IS NULL AND message_kind LIKE 'order_%' AND p_post_action->>'tracking_policy'='engagement' THEN 'engagement' ELSE tracking_policy END,
 post_action=CASE WHEN prepared IS NULL THEN post_action||p_post_action ELSE post_action END
 WHERE message_id=p_message AND lease_token=p_token AND lease_until>now() AND workflow_state='preparing'
 AND (prepared IS NULL OR prepared=p_prepared);
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=p_message),true);
END $$;

CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric; v_detail text; v_retry integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.payment_policy_fence_internal(m.organization) FROM public.email_messages m
 JOIN public.email_attempts a ON a.message_id=m.message_id WHERE a.attempt_id=p_attempt AND m.order_id IS NOT NULL;
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
  UPDATE public.email_messages SET last_error='intent_invalid',workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
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

CREATE OR REPLACE FUNCTION public.finish_email_attempt(p_attempt uuid,p_token uuid,p_outcome text,p_provider_id text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_a public.email_attempts; v_m public.email_messages; v_delay integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_a FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_m FROM public.email_messages WHERE message_id=v_a.message_id FOR UPDATE;
 IF v_a.lease_token IS DISTINCT FROM p_token OR v_m.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_completion'; END IF;
 IF v_a.state='accepted' THEN RETURN; END IF;
 IF p_outcome NOT IN ('accepted','retry','dead','unknown','preparation_failed') THEN RAISE EXCEPTION 'invalid_email_outcome'; END IF;
 IF p_outcome='accepted' AND (p_provider_id IS NULL OR v_a.state NOT IN ('sending','unknown')) THEN RAISE EXCEPTION 'invalid_email_acceptance'; END IF;
 IF p_outcome IN ('retry','dead','unknown') AND v_a.state<>'sending' THEN RAISE EXCEPTION 'invalid_email_failure'; END IF;
 IF p_outcome='preparation_failed' AND v_a.state<>'preparing' THEN RAISE EXCEPTION 'invalid_email_preparation_failure'; END IF;
 IF p_outcome='accepted' THEN
  UPDATE public.email_capacity SET provider_outage_streak=0,probe_until=NULL,probe_attempt=NULL,circuit_until=NULL WHERE probe_attempt=p_attempt;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=p_provider_id,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='accepted',provider_message_id=p_provider_id,accepted_at=coalesce(accepted_at,now()),last_error=NULL WHERE id=v_m.id;
 ELSE
  v_delay:=(ARRAY[15,60,300,1800,7200])[least(greatest(v_m.attempt_count,1),5)];
  UPDATE public.email_attempts SET state=CASE WHEN p_outcome='unknown' THEN 'unknown' ELSE 'not_accepted' END,error_code=p_error,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN p_outcome='unknown' THEN 'unknown' WHEN p_outcome='dead' OR attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END>=8 THEN 'dead' ELSE 'retry_wait' END,
   attempt_count=attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END,
   target_time=now()+make_interval(secs=>v_delay*(0.8+random()*0.4)),last_error=left(p_error,100),lease_until=NULL WHERE id=v_m.id;
  IF p_outcome='unknown' THEN UPDATE public.email_capacity SET provider_outage_streak=least(provider_outage_streak+1,10),
   probe_until=NULL,probe_attempt=NULL,circuit_until=now()+make_interval(secs=>least(300,30*power(2,least(provider_outage_streak,4)))::double precision) WHERE singleton; END IF;
  PERFORM public.notification_center_email_internal(v_m.message_id);
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds' WHERE singleton; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
 PERFORM public.notification_center_email_internal(v_m.message_id);
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_email_events() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_event record;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 WITH matched AS (UPDATE public.email_delivery_events e SET message_id=m.message_id FROM public.email_messages m
 WHERE e.message_id IS NULL AND lower(e.recipient)=lower(m.recipient)
 AND (m.provider_message_id=e.provider_message_id OR EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id AND a.attempt_id=e.attempt_id AND a.state IN ('sending','unknown','accepted'))) RETURNING e.message_id)
 UPDATE public.email_messages m SET feedback_pending=true WHERE m.message_id IN (SELECT message_id FROM matched);
 FOR v_event IN SELECT message_id,min(provider_time) FILTER(WHERE event_type='delivery') delivery,
 min(provider_time) FILTER(WHERE event_type='bounce') bounce,min(provider_time) FILTER(WHERE event_type='complaint') complaint,
 min(provider_time) FILTER(WHERE event_type='open') opened,min(provider_time) FILTER(WHERE event_type='click') clicked,
 min(provider_time) FILTER(WHERE event_type IN ('send','delivery','open','click','bounce','complaint','delay')) accepted,
 min(provider_message_id) provider_id,max(event_type) FILTER(WHERE event_type IN ('reject','rendering_failure','delay')) failure
 FROM public.email_delivery_events WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE workflow_state IN ('sending','unknown') OR feedback_pending) GROUP BY message_id LOOP
  UPDATE public.email_messages SET delivered_at=least(delivered_at,v_event.delivery),bounced_at=least(bounced_at,v_event.bounce),complained_at=least(complained_at,v_event.complaint),
   opened_at=CASE WHEN tracking_policy<>'disabled' THEN least(opened_at,v_event.opened) ELSE NULL END,
   clicked_at=CASE WHEN tracking_policy='engagement' THEN least(clicked_at,v_event.clicked) ELSE NULL END,provider_failure=v_event.failure,
   accepted_at=coalesce(accepted_at,v_event.accepted),provider_message_id=coalesce(provider_message_id,v_event.provider_id),
   workflow_state=CASE WHEN v_event.accepted IS NOT NULL AND workflow_state IN ('sending','unknown') THEN 'accepted' ELSE workflow_state END,feedback_pending=false
  WHERE message_id=v_event.message_id;
  PERFORM public.notification_center_email_internal(v_event.message_id);
  UPDATE public.email_attempts SET state='accepted',provider_message_id=v_event.provider_id,finished_at=coalesce(finished_at,now())
  WHERE message_id=v_event.message_id AND state IN ('sending','unknown') AND v_event.accepted IS NOT NULL;
 INSERT INTO public.email_suppressions(recipient,reason)
 SELECT lower(recipient),CASE WHEN bool_or(event_type='complaint') THEN 'complaint' ELSE 'hard_bounce' END
 FROM public.email_delivery_events WHERE message_id=v_event.message_id AND (event_type='complaint' OR (event_type='bounce' AND hard_bounce))
 GROUP BY lower(recipient)
 ON CONFLICT(recipient) DO UPDATE SET reason=CASE WHEN email_suppressions.reason='complaint' THEN 'complaint' ELSE excluded.reason END;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_events(p_events jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF jsonb_typeof(p_events)<>'array' OR jsonb_array_length(p_events)>100 THEN RAISE EXCEPTION 'invalid_event_batch'; END IF;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,hard_bounce,invalid_recipient)
 SELECT e->>'key',e->>'provider_id',(e->>'attempt_id')::uuid,e->>'recipient',e->>'type',(e->>'time')::timestamptz,coalesce((e->>'hard_bounce')::boolean,false),coalesce((e->>'invalid_recipient')::boolean,false)
 FROM jsonb_array_elements(p_events) e ON CONFLICT(event_key) DO NOTHING;
 PERFORM public.reconcile_email_events();
END $$;
REVOKE ALL ON FUNCTION public.record_email_events(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_events(jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.record_email_event(p_event jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.record_email_events(jsonb_build_array(p_event));
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_prepared_email(p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb; v_m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 -- Use stable digest as canonical data; nonce/ciphertext is not part of dedupe equality.
 v_result:=public.enqueue_email(p_kind,p_context,p_recipient,jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_sealed),prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_sealed::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now())
 WHERE message_id=(v_result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_internal_email_state(p_message uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT workflow_state FROM public.email_messages WHERE message_id=p_message);
END $$;

CREATE OR REPLACE FUNCTION public.refresh_email_quota(p_account text,p_region text,p_rate numeric,p_daily numeric,p_used numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity FOR UPDATE;
 IF c.account_id IS DISTINCT FROM p_account OR c.region IS DISTINCT FROM p_region OR p_rate IS NULL OR p_daily IS NULL OR p_used IS NULL OR p_rate<=0 OR p_daily<=0 OR p_used<0 THEN RAISE EXCEPTION 'email_quota_identity_mismatch'; END IF;
 UPDATE public.email_capacity SET max_rate=p_rate,daily_quota=p_daily,provider_sent_24h=p_used,quota_at=now(),wake_error=NULL,rate_factor=least(1,rate_factor+0.05) WHERE singleton;
END $$;

CREATE OR REPLACE FUNCTION public.invalidate_email_quota(p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();UPDATE public.email_capacity SET quota_at=NULL,wake_error=left(p_reason,100) WHERE singleton;END $$;
REVOKE ALL ON FUNCTION public.invalidate_email_quota(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_email_quota(text) TO service_role;

-- Explicit internal ACLs, including the invoker-only domain helpers.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('wake_email_worker','enqueue_email','email_intent_valid','claim_email','prepare_email','begin_email_send','finish_email_attempt','reconcile_email_events','record_email_event',
  'enqueue_prepared_email','get_internal_email_state','refresh_email_quota','enqueue_order_email','enqueue_paid_order_tickets','cancel_order_email_intents','apply_email_post_actions') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',p.signature);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.get_next_email_due() RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();RETURN (SELECT min(target_time) FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait'));END $$;
REVOKE ALL ON FUNCTION public.get_next_email_due() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_email_due() TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_email_quota_refresh() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_capacity SET quota_refresh_until=now()+interval '30 seconds' WHERE (quota_at IS NULL OR quota_at<now()-interval '5 minutes') AND (quota_refresh_until IS NULL OR quota_refresh_until<now());
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.reserve_email_quota_refresh() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_email_quota_refresh() TO service_role;
CREATE OR REPLACE FUNCTION public.recover_email_delivery() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_messages SET workflow_state='expired',lease_token=NULL,lease_until=NULL
 WHERE expires_at<now() AND workflow_state IN ('pending','retry_wait','blocked','preparing');
 -- Erase sensitive body after terminal state/expiry; retain correlation and dedupe tombstones.
 UPDATE public.email_messages SET prepared=NULL,data=data-'ciphertext'
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete','sale_opening_opened')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
 PERFORM public.notification_center_prepared_invalidate(e.id) FROM public.email_messages m JOIN public.notification_center_events e
  ON e.organization=m.organization AND e.kind='email_problem' AND e.data->>'messageId'=m.message_id::text
  WHERE m.message_kind='sale_opening_opened' AND m.expires_at<now()-interval '30 days' AND m.workflow_state NOT IN ('sending','unknown') AND m.recipient IS NOT NULL;
 UPDATE public.email_messages SET recipient=NULL,prepared=NULL,data='{}'
 WHERE message_kind IN ('sale_opening_opened') AND expires_at<now()-interval '30 days'
 AND workflow_state NOT IN ('sending','unknown');
 DELETE FROM public.email_confirmation_receipts WHERE expires_at<now();
 DELETE FROM public.email_delivery_events WHERE received_at<now()-interval '90 days';
 PERFORM public.apply_email_post_actions();
 PERFORM public.reconcile_email_events();
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.recover_email_delivery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_delivery() TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_unknown_email(p_message uuid,p_decision text,p_evidence text,p_provider_id text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF p_evidence IS NULL OR length(p_evidence)<10 OR p_decision NOT IN ('accepted','known_not_accepted','cancelled') THEN RAISE EXCEPTION 'reconciliation_evidence_required'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message FOR UPDATE;
 IF m.workflow_state<>'unknown' THEN RAISE EXCEPTION 'email_not_unknown'; END IF;
 IF p_decision='accepted' AND p_provider_id IS NULL THEN RAISE EXCEPTION 'provider_receipt_required'; END IF;
 UPDATE public.email_messages SET workflow_state=CASE p_decision WHEN 'accepted' THEN 'accepted' WHEN 'known_not_accepted' THEN 'pending' ELSE 'cancelled' END,
 accepted_at=CASE WHEN p_decision='accepted' THEN now() ELSE accepted_at END,provider_message_id=coalesce(p_provider_id,provider_message_id),
 target_time=now(),lease_token=NULL,lease_until=NULL,post_action=post_action||jsonb_build_object('reconciliation',jsonb_build_object('decision',p_decision,'evidence',left(p_evidence,256),'at',now()))
 WHERE message_id=p_message;
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) TO service_role;

-- SOURCE: eshop_forms/form_payment_options.sql
-- One bank selection projection for the editor and MCP. Linked accounts only;
-- bank management, connection onboarding and provider effects are separate.
CREATE OR REPLACE FUNCTION public.get_form_bank_accounts_internal(p_unit bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',ba.id,'account_number',ba.account_number,
  'account_number_human_readable',ba.account_number_human_readable,'title',ba.title,
  'supported_currencies',ba.supported_currencies,'type',ba.type,
  'bank_sync_warning',public.bank_sync_warning(ba.id)) ORDER BY uba.priority,ba.id),'[]')
 FROM eshop.unit_bank_accounts uba JOIN eshop.bank_accounts ba ON ba.id=uba.bank_account
 WHERE uba.unit=p_unit AND ba.type IS DISTINCT FROM 'CASH' AND public.payment_method_policy_enabled_internal(p_unit,'bank');
$$;
REVOKE ALL ON FUNCTION public.get_form_bank_accounts_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_form_payment_options(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,'save');
 IF p_livemode IS NULL OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='foreign form or missing Stripe environment'; END IF;
 result:=jsonb_build_object('occasionId',p_occasion,'formId',p_form,'livemode',p_livemode,
  'paymentMethodPolicy',public.resolve_payment_method_policy_internal(p_organization,p_unit),
  'bankAccounts',public.get_form_bank_accounts_internal(p_unit),
  'availability',public.form_payment_availability_internal(p_form))||public.provider_form_editor_fields_internal(p_unit,p_occasion,p_livemode);
 IF octet_length(result::text)>1048576 OR jsonb_array_length(result->'bankAccounts')>100 THEN
  RAISE program_limit_exceeded USING MESSAGE='form payment options too large'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_payment_options(bigint,bigint,bigint,bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_payment_options(bigint,bigint,bigint,bigint,boolean) TO authenticated;

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
 SELECT jsonb_build_object('code',200,'root',jsonb_build_object('id',root.id,'symbol',root.order_symbol,'createdAt',root.created_at,'state',root.state,'title',occ.title,'formLink',f.link,'communicationTone',public.effective_form_metadata_internal(f.data,(SELECT data FROM public.units WHERE id=occ.unit))->>'communication_tone','hasTickets',EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(occ.features,'[]')) feature WHERE feature->>'code'='ticket' AND feature->>'is_enabled'='true')),
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
  'payment',public.customer_order_payment_internal(o.id),
  'answers',public.customer_order_answers_internal(f.id,o.data,false),
  'ticketIds',(SELECT coalesce(jsonb_agg(t.id ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t),
  'items',CASE WHEN o.state='preparing_payment' THEN '[]'::jsonb ELSE (SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ticketId',t->'id','id',p->'id','title',p->>'title','spotTitle',p->>'spot_title','spotGroupTitle',p->>'spot_group_title','isStanding',coalesce((p->>'is_standing')::boolean,false),'standingAreaTitle',p->>'standing_area_title','price',p->'price','currency',p->>'currency_code') ORDER BY (t->>'id')::bigint,
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

-- SOURCE: eshop_stripe/checkout.sql
CREATE OR REPLACE FUNCTION public.claim_stripe_checkout_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities; a eshop.stripe_checkout_attempts; o eshop.orders; pi eshop.payment_info;
 c eshop.stripe_connections; source jsonb; lease uuid; projection jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND scope='order_pay' AND revoked_at IS NULL AND expires_at>clock_timestamp();
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 PERFORM public.payment_policy_fence_internal(oc.organization) FROM eshop.orders ord JOIN public.occasions oc ON oc.id=ord.occasion WHERE ord.id=cap.order_id;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[cap.order_id]);
 PERFORM public.authorize_stripe_capability_internal(p_token,'order_pay',cap.order_id);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=cap.order_id;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 IF a.livemode IS DISTINCT FROM p_livemode OR pi.payment_method<>'stripe' OR pi.stripe_connection_id<>a.connection_id
  OR pi.amount*100<>a.amount_minor OR pi.currency_code<>a.currency OR o.currency_code<>a.currency
  OR coalesce(pi.paid_externally,0)<>0 THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 projection:=public.provider_order_payment_projection_internal(o.id);
 IF public.payment_collection_action_internal(o.id)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN RETURN jsonb_build_object('disposition','read','payment',projection); END IF;
 IF projection->>'status' NOT IN ('open','preparing') THEN RETURN jsonb_build_object('disposition','read','payment',projection); END IF;
 IF o.price*100<>a.amount_minor THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 IF a.lease_expires_at>clock_timestamp() OR a.reservation_expires_at<=clock_timestamp() THEN
  RETURN jsonb_build_object('disposition','busy','payment',projection); END IF;
 -- Admission precedes any provider work, keyed by the hashed pay capability.
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.checkout',a.unit_id,a.organization_id),
  jsonb_build_object('actor',cap.token_hash,'unit',a.unit_id,'organization',a.organization_id));
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) INTO source
 FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities pc USING(token_hash)
 WHERE pc.order_id=o.id AND pc.scope='order_pay' AND pc.revoked_at IS NULL AND pc.expires_at>clock_timestamp()
 ORDER BY s.created_at DESC LIMIT 1;
 IF source IS NULL OR a.return_base_url IS NULL THEN RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_checkout_attempts SET lease_token=lease,lease_expires_at=clock_timestamp()+interval '120 seconds',
  state=CASE WHEN session_id IS NULL THEN 'uncertain' ELSE state END WHERE id=a.id;
 RETURN jsonb_build_object('disposition','dispatch','lease',lease,'source',source,'payment',projection,
  'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'orderReference','Order '||o.order_symbol,
   'createdAt',extract(epoch FROM a.created_at)::bigint,'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,
   'idempotencyKey',a.idempotency_key,'locale',a.checkout_locale,'returnBaseUrl',a.return_base_url,'sessionId',a.session_id,'refundCursor',a.refund_cursor));
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_checkout_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_checkout_internal(text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.commit_stripe_checkout_session_internal(p_attempt uuid,p_lease uuid,p_session text,p_url text,p_expires bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts;
BEGIN
 PERFORM public.require_service_role();
 -- Form/order first, then attempt, as in the claim and payment ingest.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT order_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt));
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR a.lease_token IS NULL OR a.lease_expires_at IS NULL OR a.lease_token IS DISTINCT FROM p_lease OR a.lease_expires_at<=clock_timestamp()
  OR p_session IS NULL OR p_session !~ '^cs_[A-Za-z0-9_]+$'
  OR p_url IS NULL OR p_url !~ '^https://checkout[.]stripe[.]com/[^[:space:]]+$'
  OR p_expires IS DISTINCT FROM extract(epoch FROM a.reservation_expires_at)::bigint
  OR (a.session_id IS NOT NULL AND a.session_id<>p_session) THEN RAISE EXCEPTION 'STRIPE_CHECKOUT_RECEIPT_INVALID'; END IF;
 UPDATE eshop.stripe_checkout_attempts SET session_id=p_session,checkout_url=p_url,
  state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END,
  lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=least(reservation_expires_at,clock_timestamp()+interval '2 minutes')
 WHERE id=a.id;
 RETURN jsonb_build_object('committed',true,'payment',public.stripe_order_payment_projection_internal(a.order_id));
END $$;
REVOKE ALL ON FUNCTION public.commit_stripe_checkout_session_internal(uuid,uuid,text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.commit_stripe_checkout_session_internal(uuid,uuid,text,text,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_stripe_checkout_internal(p_attempt uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.stripe_checkout_attempts SET state=CASE WHEN session_id IS NULL THEN 'uncertain' ELSE state END,
  lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=clock_timestamp()+interval '1 minute'
 WHERE id=p_attempt AND lease_token=p_lease;
END $$;
REVOKE ALL ON FUNCTION public.fail_stripe_checkout_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fail_stripe_checkout_internal(uuid,uuid) TO service_role;

-- Minimal read only. Knowledge of this handle cannot start Checkout or reveal PII.
CREATE OR REPLACE FUNCTION public.read_stripe_return_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities c WHERE c.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND c.scope='return_read' AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE id=c.attempt_id AND livemode=p_livemode);
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 RETURN public.provider_order_payment_projection_internal(cap.order_id)-'allowedActions'||jsonb_build_object('allowedActions',jsonb_build_array('refresh'));
END $$;
REVOKE ALL ON FUNCTION public.read_stripe_return_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_stripe_return_internal(text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.read_stripe_pay_status_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities c WHERE c.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND c.scope='order_pay' AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE order_id=c.order_id AND livemode=p_livemode);
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 RETURN public.provider_order_payment_projection_internal(cap.order_id);
END $$;
REVOKE ALL ON FUNCTION public.read_stripe_pay_status_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_stripe_pay_status_internal(text,boolean) TO service_role;

-- Shared by signed webhook delivery and bounded recovery, including retired
-- connections. Pausing new sales must not stop money/refund reconciliation.
CREATE OR REPLACE FUNCTION public.claim_stripe_sync_internal(p_account text,p_livemode boolean,
 p_attempt uuid DEFAULT NULL,p_session text DEFAULT NULL,p_intent text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; c eshop.stripe_connections; o eshop.orders; lease uuid; source jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM eshop.stripe_connections WHERE account_id=p_account AND livemode=p_livemode;
 IF NOT FOUND THEN RETURN jsonb_build_object('disposition','unrelated'); END IF;
 SELECT * INTO a FROM eshop.stripe_checkout_attempts WHERE connection_id=c.id AND
  ((p_attempt IS NOT NULL AND id=p_attempt) OR (p_session IS NOT NULL AND session_id=p_session) OR (p_intent IS NOT NULL AND payment_intent_id=p_intent))
 ORDER BY created_at DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('disposition','unrelated'); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=a.id FOR UPDATE;
 IF a.lease_expires_at>clock_timestamp() THEN RETURN jsonb_build_object('disposition','busy'); END IF;
 IF (p_session IS NOT NULL AND a.session_id IS NOT NULL AND p_session<>a.session_id)
  OR (p_intent IS NOT NULL AND a.payment_intent_id IS NOT NULL AND p_intent<>a.payment_intent_id) THEN RAISE EXCEPTION 'STRIPE_SYNC_IDENTITY_MISMATCH'; END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id;
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) INTO source
 FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities pc USING(token_hash)
 WHERE pc.order_id=o.id AND pc.scope='order_pay' ORDER BY s.created_at DESC LIMIT 1;
 -- Historical reads need no bearer secret. Creation still requires its source.
 IF a.return_base_url IS NULL OR (source IS NULL AND coalesce(a.session_id,p_session) IS NULL AND a.reservation_expires_at>clock_timestamp()) THEN
  RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_checkout_attempts SET lease_token=lease,lease_expires_at=clock_timestamp()+interval '120 seconds' WHERE id=a.id;
 RETURN jsonb_build_object('disposition','dispatch','lease',lease,'source',source,
  'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'orderReference','Order '||o.order_symbol,
   'createdAt',extract(epoch FROM a.created_at)::bigint,'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,
   'idempotencyKey',a.idempotency_key,'locale',a.checkout_locale,'returnBaseUrl',a.return_base_url,'sessionId',coalesce(a.session_id,p_session),'refundCursor',a.refund_cursor,
   'sessionLookupCursor',a.session_lookup_cursor,'sessionLookupFound',a.session_lookup_found));
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_sync_internal(text,boolean,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_sync_internal(text,boolean,uuid,text,text) TO service_role;

-- SOURCE: eshop_barion/runtime.sql
-- Single service boundary. Every operation checks service role; browser tokens
-- are independently scoped/hashed and never treated as account credentials.
CREATE OR REPLACE FUNCTION public.barion_runtime_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.barion_attempts; c eshop.barion_connections; cap eshop.barion_capabilities;
 lease uuid; facts jsonb; tx jsonb; existing eshop.barion_movements; before_projection jsonb; source jsonb;
 result jsonb; digest text; seconds integer; total bigint; refunded bigint; held boolean:=false; stamp timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.require_service_role();
 IF p_operation='recoverable' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('attemptId',q.id,'accountId',q.account_id)),'[]') FROM (
   SELECT a.id,c.account_id FROM eshop.barion_attempts a JOIN eshop.barion_connections c ON c.id=a.connection_id
   WHERE a.next_reconcile_at<=stamp AND (a.lease_expires_at IS NULL OR a.lease_expires_at<=stamp)
   ORDER BY a.next_reconcile_at,a.id LIMIT 10) q);
 ELSIF p_operation='callback_schedule' THEN
  IF p_args->>'paymentId' IS NULL OR p_args->>'paymentId' !~ '^[a-f0-9]{32}$' THEN RAISE EXCEPTION 'BARION_CALLBACK_INVALID'; END IF;
  -- Coalesce bursts; callback cannot cause a remote create or overwrite facts.
  UPDATE eshop.barion_attempts SET next_reconcile_at=least(next_reconcile_at,greatest(stamp,coalesce(last_synced_at,'-infinity')+interval '6 seconds')) WHERE remote_id=p_args->>'paymentId';
  RETURN NULL;
 ELSIF p_operation='purge' THEN
  WITH selected AS (SELECT s.attempt_id FROM eshop.barion_sources s JOIN eshop.barion_capabilities c USING(token_hash) WHERE c.expires_at<=stamp ORDER BY c.expires_at LIMIT 100),
   removed AS (DELETE FROM eshop.barion_sources WHERE attempt_id IN(SELECT attempt_id FROM selected) RETURNING 1) SELECT count(*) INTO total FROM removed;
  RETURN to_jsonb(total);
 END IF;
 IF p_operation IN ('claim_checkout','read','handoff') THEN
  IF p_args->>'token' IS NULL OR p_args->>'token' !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO cap FROM eshop.barion_capabilities WHERE token_hash=encode(extensions.digest(p_args->>'token','sha256'),'hex')
   AND scope=CASE p_operation WHEN 'claim_checkout' THEN 'order_pay' WHEN 'handoff' THEN 'handoff' ELSE p_args->>'scope' END AND expires_at>stamp;
  IF cap.token_hash IS NULL OR (p_operation='read' AND p_args->>'scope' NOT IN ('order_pay','return_read')) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=cap.attempt_id;
 ELSIF p_operation IN ('source','attach_handoff') THEN SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE order_id=(p_args->>'orderId')::bigint;
 ELSE SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=(p_args->>'attemptId')::uuid; END IF;
 SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=a.connection_id;
 IF p_operation='read' THEN RETURN public.provider_order_payment_projection_internal(a.order_id);
 ELSIF p_operation='source' THEN
  SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,
   'payBaseUrl',regexp_replace(a.return_base_url,'/payments/barion/return$','/payments/barion/pay'),'payment',public.provider_order_payment_projection_internal(a.order_id)) INTO result
  FROM eshop.barion_sources s JOIN eshop.barion_capabilities pc USING(token_hash)
   WHERE s.attempt_id=a.id AND s.command_id=(p_args->>'commandId')::uuid AND pc.scope='order_pay' AND pc.expires_at>stamp;
  IF result IS NULL THEN RETURN jsonb_build_object('payment',public.provider_order_payment_projection_internal(a.order_id)); END IF;
  RETURN result;
 ELSIF p_operation='attach_handoff' THEN
  IF p_args->>'tokenHash' IS NULL OR p_args->>'tokenHash' !~ '^[a-f0-9]{64}$' OR NOT EXISTS(SELECT 1 FROM eshop.barion_sources WHERE attempt_id=a.id AND command_id=(p_args->>'commandId')::uuid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  INSERT INTO eshop.barion_capabilities(token_hash,attempt_id,scope,expires_at) VALUES(p_args->>'tokenHash',a.id,'handoff',least(a.reservation_expires_at,stamp+interval '30 minutes')) ON CONFLICT DO NOTHING;
  RETURN NULL;
 END IF;
 IF p_operation='claim_checkout' THEN PERFORM public.payment_policy_fence_internal(a.organization_id); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 PERFORM 1 FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=a.id FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info JOIN public.occasions oc ON oc.id=o.occasion
  WHERE o.id=a.order_id AND pi.id=a.payment_info_id AND pi.payment_method='barion' AND pi.barion_connection_id=a.connection_id
   AND pi.amount*100=a.amount_minor AND pi.currency_code=a.currency AND oc.organization=a.organization_id AND oc.unit=a.unit_id) THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
 before_projection:=public.provider_order_payment_projection_internal(a.order_id);
 IF p_operation='handoff' THEN
  IF p_args->'consume'='true'::jsonb THEN
   UPDATE eshop.barion_capabilities SET consumed_at=stamp WHERE token_hash=cap.token_hash AND consumed_at IS NULL AND expires_at>stamp;
   IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   SELECT jsonb_build_object('sealed',sealed,'contentHash',content_hash,'tokenHash',token_hash) INTO source FROM eshop.barion_sources WHERE attempt_id=a.id;
   RETURN jsonb_build_object('source',source);
  END IF;
  RETURN jsonb_build_object('payment',before_projection);
 ELSIF p_operation IN ('claim_checkout','claim_sync') THEN
  IF p_operation='claim_checkout' AND public.payment_collection_action_internal(a.order_id)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN RETURN jsonb_build_object('providerId','barion','disposition','read','payment',before_projection); END IF;
  IF p_operation='claim_sync' AND p_args->>'accountId' IS DISTINCT FROM c.account_id THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
  IF a.lease_expires_at>stamp OR coalesce(a.last_synced_at,'-infinity')>stamp-interval '6 seconds' THEN
   RETURN jsonb_build_object('providerId','barion','disposition','busy','payment',before_projection); END IF;
  IF p_operation='claim_checkout' AND (a.reservation_expires_at<=stamp OR before_projection->>'status' NOT IN ('open','preparing')) THEN
   RETURN jsonb_build_object('providerId','barion','disposition','read','payment',before_projection); END IF;
  SELECT jsonb_build_object('sealed',sealed,'contentHash',content_hash,'tokenHash',token_hash) INTO source FROM eshop.barion_sources WHERE attempt_id=a.id;
  IF p_operation='claim_checkout' AND a.remote_id IS NULL AND (a.dispatched_at IS NOT NULL OR source IS NULL OR NOT c.enabled) THEN
   RETURN jsonb_build_object('providerId','barion','disposition','busy','payment',before_projection); END IF;
  IF p_operation='claim_checkout' THEN
   PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('barion.checkout',a.unit_id,a.organization_id),
    jsonb_build_object('actor',cap.token_hash,'unit',a.unit_id,'organization',a.organization_id));
  END IF;
  lease:=extensions.gen_random_uuid();
  UPDATE eshop.barion_attempts SET lease_token=lease,lease_expires_at=stamp+interval '120 seconds',
   dispatched_at=CASE WHEN p_operation='claim_checkout' AND remote_id IS NULL THEN coalesce(dispatched_at,stamp) ELSE dispatched_at END,
   state=CASE WHEN p_operation='claim_checkout' AND remote_id IS NULL THEN 'uncertain' ELSE state END WHERE id=a.id;
  RETURN jsonb_build_object('providerId','barion','disposition','dispatch','lease',lease,'checkoutId',a.remote_id,'connectorState','{}'::jsonb,'source',source,'returnBaseUrl',a.return_base_url,
   'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',false,'amountMinor',a.amount_minor,'currency',a.currency,
    'orderReference','Order '||(SELECT order_symbol FROM eshop.orders WHERE id=a.order_id),'createdAt',extract(epoch FROM a.created_at)::bigint,
    'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,'idempotencyKey',a.id,'locale',a.locale));
 END IF;
 IF p_args->>'lease' IS NULL OR a.lease_token IS NULL OR a.lease_token IS DISTINCT FROM (p_args->>'lease')::uuid OR a.lease_expires_at<=stamp THEN RAISE EXCEPTION 'BARION_LEASE_LOST'; END IF;
 IF p_operation='commit_checkout' THEN
  facts:=p_args->'checkout';
  IF facts->>'id' IS NULL OR facts->>'id' !~ '^[a-f0-9]{32}$' OR (a.remote_id IS NOT NULL AND a.remote_id<>facts->>'id')
   OR facts->>'url' IS DISTINCT FROM ('https://secure.test.barion.com/Pay?Id='||(facts->>'id'))
   OR (facts->>'expiresAt')::bigint IS DISTINCT FROM extract(epoch FROM a.reservation_expires_at)::bigint THEN RAISE EXCEPTION 'BARION_CHECKOUT_INVALID'; END IF;
  UPDATE eshop.barion_attempts SET remote_id=facts->>'id',checkout_url=facts->>'url',state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END,
   lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=stamp+interval '6 seconds' WHERE id=a.id;
 ELSIF p_operation IN ('fail','defer') THEN
  seconds:=CASE WHEN p_operation='fail' THEN 60 ELSE (p_args->>'seconds')::integer END;
  IF seconds IS NULL OR seconds NOT BETWEEN 1 AND 3600 THEN RAISE EXCEPTION 'BARION_RECOVERY_INVALID'; END IF;
  IF p_operation='defer' THEN
   PERFORM public.apply_provider_payment_effects_internal('barion',a.id,'unresolved:'||a.id,before_projection,false,true);
  END IF;
  UPDATE eshop.barion_attempts SET lease_token=NULL,lease_expires_at=NULL,reconcile_failures=reconcile_failures+1,next_reconcile_at=stamp+make_interval(secs=>seconds) WHERE id=a.id;
 ELSIF p_operation='ingest' THEN
  facts:=p_args->'facts';
  IF facts->>'checkoutId' IS NULL OR facts->>'checkoutId' !~ '^[a-f0-9]{32}$' OR facts->>'paymentId' IS DISTINCT FROM facts->>'checkoutId'
   OR (a.remote_id IS NOT NULL AND a.remote_id<>facts->>'checkoutId')
   OR facts->>'checkoutStatus' IS NULL OR facts->>'checkoutStatus' NOT IN ('open','complete','expired')
   OR jsonb_typeof(facts->'movements') IS DISTINCT FROM 'array' OR jsonb_array_length(facts->'movements')>100
   OR jsonb_typeof(facts->'disputes') IS DISTINCT FROM 'array' OR jsonb_array_length(facts->'disputes')>1
   OR facts ? 'noCheckoutVerified' THEN RAISE EXCEPTION 'BARION_FACTS_INVALID'; END IF;
  -- An incomplete or changed history never subtracts a previously proved fact.
  held:=a.financial_hold OR jsonb_array_length(facts->'disputes')>0 OR EXISTS(
   SELECT 1 FROM eshop.barion_movements m WHERE m.attempt_id=a.id AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'movements') x WHERE x->>'providerId'=m.provider_id));
  FOR tx IN SELECT * FROM jsonb_array_elements(facts->'movements') LOOP
   IF tx->>'providerId' IS NULL OR tx->>'providerId' !~ '^[a-f0-9]{32}$' OR tx->>'kind' IS NULL OR tx->>'kind' NOT IN ('payment','refund')
    OR jsonb_typeof(tx->'amountMinor') IS DISTINCT FROM 'number' OR (tx->>'amountMinor')::numeric<>trunc((tx->>'amountMinor')::numeric)
    OR (tx->>'amountMinor')::numeric NOT BETWEEN 1 AND a.amount_minor OR tx->>'currency' IS DISTINCT FROM a.currency
    OR jsonb_typeof(tx->'occurredAt') IS DISTINCT FROM 'number' OR (tx->>'occurredAt')::numeric<>trunc((tx->>'occurredAt')::numeric)
    OR (tx->>'occurredAt')::bigint<extract(epoch FROM a.created_at)::bigint OR (tx->>'occurredAt')::bigint>extract(epoch FROM stamp+interval '1 minute')::bigint
    THEN RAISE EXCEPTION 'BARION_MOVEMENT_INVALID'; END IF;
   SELECT * INTO existing FROM eshop.barion_movements WHERE connection_id=c.id AND provider_id=tx->>'providerId';
   IF FOUND THEN
    IF existing.attempt_id<>a.id OR existing.kind<>tx->>'kind' OR existing.amount_minor<>(tx->>'amountMinor')::bigint OR existing.currency<>tx->>'currency'
      OR existing.occurred_at<>to_timestamp((tx->>'occurredAt')::bigint) THEN RAISE EXCEPTION 'BARION_MOVEMENT_CONFLICT'; END IF;
   ELSE INSERT INTO eshop.barion_movements VALUES(a.id,c.id,tx->>'providerId',tx->>'kind',(tx->>'amountMinor')::bigint,a.currency,to_timestamp((tx->>'occurredAt')::bigint)); END IF;
  END LOOP;
  SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0),coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0) INTO total,refunded FROM eshop.barion_movements WHERE attempt_id=a.id;
  IF total NOT IN (0,a.amount_minor) OR refunded>total THEN RAISE EXCEPTION 'BARION_TOTALS_INVALID'; END IF;
  digest:=encode(extensions.digest(facts::text,'sha256'),'hex');
  INSERT INTO eshop.barion_observations(attempt_id,digest,facts) VALUES(a.id,digest,facts) ON CONFLICT DO NOTHING;
  UPDATE eshop.barion_attempts SET remote_id=facts->>'checkoutId',financial_hold=held,last_synced_at=stamp,reconcile_failures=0,
   state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END WHERE id=a.id;
  PERFORM public.apply_provider_payment_effects_internal('barion',a.id,digest,before_projection,facts->>'checkoutStatus'='expired',false);
  UPDATE eshop.barion_attempts SET lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=stamp+CASE WHEN total>0 THEN interval '15 minutes' ELSE interval '1 minute' END WHERE id=a.id;
 ELSE RAISE EXCEPTION 'BARION_RUNTIME_OPERATION_UNSUPPORTED';
 END IF;
 RETURN jsonb_build_object('committed',true,'payment',public.provider_order_payment_projection_internal(a.order_id));
END $$;
REVOKE ALL ON FUNCTION public.barion_runtime_internal(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.barion_runtime_internal(text,jsonb) TO service_role;

-- SOURCE: eshop_bank_accounts/get_my_admin_bank_accounts.sql
CREATE OR REPLACE FUNCTION public.get_linkable_bank_accounts(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    account_number_human_readable text,
    title text,
    creditor_name text,
    type text,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    linked_units text[],
    last_fetch_time timestamptz,
    last_fio_fetch_time timestamptz,
    bank_sync jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF public.is_demo_unit(p_unit_id) OR NOT public.can_manage_unit_bank_accounts(p_unit_id) OR NOT coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'bank'),false) THEN RAISE insufficient_privilege; END IF;
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.account_number_human_readable,
        ba.title,
        ba.creditor_name,
        ba.type,
        NULL::text as token_masked,
        NULL::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ARRAY(
            SELECT u.title
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit = u.id
            WHERE uba.bank_account = ba.id
        ) as linked_units,
        NULL::timestamptz as last_fetch_time,
        NULL::timestamptz as last_fio_fetch_time,
        NULL::jsonb AS bank_sync
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    AND upper(ba.type) <> 'CASH'
    ORDER BY ba.title;
END;
$$;

REVOKE ALL ON FUNCTION public.get_linkable_bank_accounts(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_linkable_bank_accounts(bigint) TO authenticated, service_role;

-- SOURCE: eshop_bank_accounts/update_bank_account_user.sql
CREATE OR REPLACE FUNCTION public.update_bank_account_user(
    p_bank_account_id bigint,
    p_user_email text,
    p_is_admin boolean,
    p_is_support boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user_id uuid;
BEGIN
    PERFORM public.require_bank_authoring_scope_internal(p_bank_account_id,NULL);
    -- Security Check: Caller must be an Admin of the bank account
    IF NOT public.can_manage_bank_account(p_bank_account_id) THEN
        RAISE EXCEPTION 'Permission denied: Only bank account admins can manage users.' USING ERRCODE='42501';
    END IF;

    -- Find user by email (assuming email_readonly is populated and unique-ish for lookup)
    -- In a real app, might want a better user lookup, but this fits the pattern
    SELECT id INTO v_user_id FROM public.user_info WHERE email_readonly = p_user_email LIMIT 1;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    -- If both flags are false or null, remove the user
    IF (p_is_admin IS NULL OR p_is_admin = false) AND (p_is_support IS NULL OR p_is_support = false) THEN
        DELETE FROM eshop.bank_account_users
        WHERE bank_account = p_bank_account_id AND "user" = v_user_id;
    ELSE
        IF EXISTS (SELECT 1 FROM eshop.bank_account_users WHERE bank_account = p_bank_account_id AND "user" = v_user_id) THEN
            UPDATE eshop.bank_account_users
            SET is_admin = COALESCE(p_is_admin, false), is_support = COALESCE(p_is_support, false)
            WHERE bank_account = p_bank_account_id AND "user" = v_user_id;
        ELSE
            INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin, is_support)
            VALUES (p_bank_account_id, v_user_id, COALESCE(p_is_admin, false), COALESCE(p_is_support, false));
        END IF;
    END IF;
END;
$$;

-- SOURCE: eshop_bank_sync/bank_sync_manage.sql
-- Prevent intentional suspension while issued bank instructions still reserve
-- funds. Connection -> canonical order locks match ingest; prepare holds the
-- order lock and checks connection state before issuing its immutable snapshot.
CREATE OR REPLACE FUNCTION public.check_bank_refund_source_operation_internal(p_account bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE accounts bigint[];
BEGIN
 PERFORM 1 FROM eshop.bank_sync_connections c WHERE c.bank_account_id=p_account
  OR c.id IN(SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_account)
  ORDER BY c.id FOR UPDATE;
 SELECT array_agg(DISTINCT id) INTO accounts FROM (
  SELECT p_account id UNION ALL SELECT c.bank_account_id FROM eshop.bank_sync_connections c
   WHERE c.id IN(SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_account)
  UNION ALL SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a
   JOIN eshop.bank_sync_connections c ON c.id=a.connection_id WHERE c.bank_account_id=p_account
 ) scope;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(
  SELECT o.id FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE p.bank_account=ANY(accounts) ORDER BY o.id));
 IF EXISTS(SELECT 1 FROM eshop.refund_requests r JOIN eshop.payment_info p ON p.id=r.payment_info
  WHERE p.bank_account=ANY(accounts) AND r.status IN ('pending','processing','unknown')) THEN
  RAISE EXCEPTION 'BANK_ACCOUNT_HAS_PENDING_REFUND';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_bank_refund_source_operation_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_connection(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_bank_account_id);
  SELECT jsonb_build_object('id',c.id,'remote_bank_account_id',c.remote_bank_account_id,'state',c.state,'mode',c.mode,
    'receiving_address',CASE WHEN c.pairing_code IS NOT NULL THEN c.pairing_code||'@banksync.festapp.net' END,
    'bank_pull_at',c.bank_pull_at,'receiver_commit_at',c.receiver_commit_at,'last_error',c.last_error,
    'observation_id',c.observation_id::text,'warning_pending',public.bank_sync_warning_pending(c.id),'token_expiry_at',c.token_expiry_at) INTO v_result FROM eshop.bank_sync_connections c
    WHERE c.bank_account_id=p_bank_account_id OR c.id IN
      (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_connection(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_connection(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.begin_bank_sync_operation(p_id uuid,p_account_id bigint,p_operation text,p_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_operation eshop.bank_sync_operations%ROWTYPE; v_inserted integer;
BEGIN
  PERFORM public.require_bank_authoring_scope_internal(p_account_id,NULL);
  PERFORM public.check_is_admin_for_bank_account(p_account_id);
  IF p_operation='suspend' THEN PERFORM public.check_bank_refund_source_operation_internal(p_account_id); END IF;
  INSERT INTO eshop.bank_sync_operations(id,bank_account_id,actor,operation,payload_sha256,state)
    VALUES(p_id,p_account_id,auth.uid(),p_operation,p_hash,'pending') ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  IF v_inserted>0 THEN
    PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('bank.operation',NULL,NULL),
      jsonb_build_object('actor',auth.uid(),'recipient','bank:'||p_account_id,'global','all'));
  END IF;
  SELECT * INTO STRICT v_operation FROM eshop.bank_sync_operations WHERE id=p_id OR (bank_account_id=p_account_id AND actor=auth.uid() AND operation=p_operation
      AND payload_sha256=p_hash AND state IN ('pending','running','uncertain')) ORDER BY (id=p_id) DESC LIMIT 1 FOR UPDATE;
  IF v_operation.actor IS DISTINCT FROM auth.uid() OR v_operation.bank_account_id<>p_account_id
    OR v_operation.operation<>p_operation OR v_operation.payload_sha256<>p_hash THEN
    RAISE EXCEPTION 'BANK_SYNC_OPERATION_CONFLICT';
  END IF;
  RETURN jsonb_build_object('id',v_operation.id,'state',v_operation.state,'result',v_operation.result);
END;
$$;
REVOKE ALL ON FUNCTION public.begin_bank_sync_operation(uuid,bigint,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.begin_bank_sync_operation(uuid,bigint,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_bank_sync_operation(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_op eshop.bank_sync_operations%ROWTYPE; v_account eshop.bank_accounts%ROWTYPE; v_conn eshop.bank_sync_connections%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_op FROM eshop.bank_sync_operations WHERE id=p_id;
  IF v_op.operation='suspend' THEN PERFORM public.check_bank_refund_source_operation_internal(v_op.bank_account_id); END IF;
  UPDATE eshop.bank_sync_operations SET state='running',lease_token=gen_random_uuid(),updated_at=now() WHERE id=p_id
    AND (state IN ('pending','uncertain','failed') OR (state='running' AND updated_at<now()-interval '5 minutes'))
    RETURNING * INTO v_op;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_BUSY'; END IF;
  SELECT * INTO STRICT v_account FROM eshop.bank_accounts WHERE id=v_op.bank_account_id;
  SELECT * INTO v_conn FROM eshop.bank_sync_connections WHERE bank_account_id=v_op.bank_account_id;
  RETURN jsonb_build_object('lease_token',v_op.lease_token,'account_number',v_account.account_number,'provider',COALESCE(v_conn.provider,public.bank_sync_provider_for_account(v_account.account_number)),'title',v_account.title,
    'connection_id',v_conn.id,'remote_id',v_conn.remote_bank_account_id,'pairing_code',v_conn.pairing_code,
    'state',v_conn.state,'mode',v_conn.mode,'barrier',v_conn.legacy_blocked_at,'manifest_sha256',v_conn.manifest_sha256,'request',v_op.request,'token_cipher',v_op.token_cipher);
END;
$$;
REVOKE ALL ON FUNCTION public.claim_bank_sync_operation(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_bank_sync_operation(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_bank_sync_operation(p_id uuid,p_state text,p_result jsonb,p_lease_token uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_state NOT IN ('uncertain','completed','failed') THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_STATE_INVALID'; END IF;
  UPDATE eshop.bank_sync_operations SET state=p_state,result=p_result,token_cipher=CASE WHEN p_state='completed' THEN NULL ELSE token_cipher END,updated_at=now() WHERE id=p_id AND state='running' AND lease_token=p_lease_token;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_NOT_CLAIMED'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_bank_sync_operation(uuid,text,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_bank_sync_operation(uuid,text,jsonb,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.save_bank_sync_connection(p_operation_id uuid,p_instance_id text,p_remote_id text,p_pairing_code text,p_mode text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_op eshop.bank_sync_operations%ROWTYPE; v_account eshop.bank_accounts%ROWTYPE; v_id bigint;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO STRICT v_op FROM eshop.bank_sync_operations WHERE id=p_operation_id AND state='running';
  PERFORM public.check_bank_account_writable(v_op.bank_account_id);
  IF v_op.operation<>'create' THEN RAISE EXCEPTION 'BANK_SYNC_PROVISION_OPERATION_REQUIRED'; END IF;
  SELECT * INTO STRICT v_account FROM eshop.bank_accounts WHERE id=v_op.bank_account_id FOR UPDATE;
  -- Activation adopts historical movement identities under the account lock.
  -- Existing accounts use the same canonical provisioning path as new accounts.
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256)
    VALUES(p_instance_id,'festapp',p_remote_id,v_account.id,upper(regexp_replace(v_account.account_number,'\s','','g')),
      public.bank_sync_provider_for_account(v_account.account_number),p_mode,'provisioning',p_pairing_code,v_op.payload_sha256)
    ON CONFLICT(bank_account_id) DO UPDATE SET pairing_code=EXCLUDED.pairing_code
    WHERE eshop.bank_sync_connections.remote_bank_account_id=EXCLUDED.remote_bank_account_id
      AND eshop.bank_sync_connections.instance_id=EXCLUDED.instance_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_MAPPING_CONFLICT'; END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.save_bank_sync_connection(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_bank_sync_connection(uuid,text,text,text,text) TO service_role;

DROP FUNCTION IF EXISTS public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text);
DROP FUNCTION IF EXISTS public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,text);
CREATE OR REPLACE FUNCTION public.update_bank_sync_connection_metadata(p_id bigint,p_pairing_code text,p_expiry timestamptz,p_state text,p_observation_id bigint,p_mode text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_observation_id IS NULL OR p_observation_id<=0 THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_REQUIRED'; END IF;
  UPDATE eshop.bank_sync_connections SET pairing_history=CASE WHEN p_pairing_code IS NOT NULL AND pairing_code IS DISTINCT FROM p_pairing_code
      THEN pairing_history||jsonb_build_array(jsonb_build_object('code',pairing_code,'retired_at',now())) ELSE pairing_history END,
    pairing_code=COALESCE(p_pairing_code,pairing_code),
    token_expiry_at=CASE WHEN p_mode='api' THEN p_expiry ELSE COALESCE(p_expiry,token_expiry_at) END,
    mode=COALESCE(p_mode,mode),observation_id=GREATEST(observation_id,p_observation_id),
    state=CASE WHEN p_state IN ('connected','degraded') AND observation_id>p_observation_id THEN state ELSE p_state END
    WHERE id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_NOT_FOUND'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,bigint,text) TO service_role;

CREATE OR REPLACE FUNCTION public.begin_bank_sync_observation(p_connection_id bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF NOT EXISTS(SELECT 1 FROM eshop.bank_sync_connections WHERE id=p_connection_id) THEN
    RAISE EXCEPTION 'BANK_SYNC_CONNECTION_NOT_FOUND';
  END IF;
  RETURN nextval('eshop.bank_sync_observation_ids')::text;
END;
$$;
REVOKE ALL ON FUNCTION public.begin_bank_sync_observation(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.begin_bank_sync_observation(bigint) TO service_role;

DROP FUNCTION IF EXISTS public.record_bank_sync_pull(bigint,timestamptz,text);
CREATE OR REPLACE FUNCTION public.record_bank_sync_pull(p_id bigint,p_success_at timestamptz,p_error text,p_observation_id bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_observation_id IS NULL OR p_observation_id<=0 THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_REQUIRED'; END IF;
  UPDATE eshop.bank_sync_connections SET observation_id=p_observation_id,
    bank_pull_at=GREATEST(p_success_at,bank_pull_at),last_error=left(p_error,256),
    failure_since=CASE WHEN p_error IS NULL THEN NULL
      WHEN last_error IS NULL OR (p_success_at IS NOT NULL AND (bank_pull_at IS NULL OR p_success_at>bank_pull_at)) THEN now()
      ELSE COALESCE(failure_since,now()) END,
    failure_observed_at=CASE WHEN p_error IS NOT NULL THEN now() END,
    state=CASE WHEN state IN ('connected','degraded') THEN
      CASE WHEN p_error IS NOT NULL THEN 'degraded' WHEN p_success_at IS NOT NULL THEN 'connected' ELSE state END
      ELSE state END WHERE id=p_id AND observation_id<p_observation_id;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.record_bank_sync_pull(bigint,timestamptz,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_bank_sync_pull(bigint,timestamptz,text,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_observations(p_bank_account_id bigint,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_bank_account_id);
  SELECT COALESCE(jsonb_agg(row_to_json(q)),'[]'::jsonb) INTO v_result FROM (
    SELECT i.delivery_id,i.received_at,i.outcome,i.payload->'data' AS bank_data
      FROM eshop.bank_sync_inbox i JOIN eshop.bank_sync_connections c ON c.id=i.connection_id
      WHERE (c.bank_account_id=p_bank_account_id OR c.id IN
        (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id))
        AND i.outcome LIKE 'quarantined_%' AND i.resolution IS NULL ORDER BY i.received_at DESC,i.delivery_id LIMIT LEAST(GREATEST(p_limit,1),100)
  ) q;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_observations(bigint,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_observations(bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.stage_bank_sync_operation(p_id uuid,p_hash text,p_request jsonb,p_token_cipher jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_request ? 'token' OR p_request->>'operation_id' IS DISTINCT FROM p_id::text THEN
    RAISE EXCEPTION 'BANK_SYNC_REQUEST_INVALID';
  END IF;
  UPDATE eshop.bank_sync_operations SET request=COALESCE(request,p_request||jsonb_build_object('expected_pairing',
      (SELECT c.pairing_code FROM eshop.bank_sync_connections c WHERE c.bank_account_id=bank_sync_operations.bank_account_id))),
      token_cipher=COALESCE(token_cipher,p_token_cipher)
    WHERE id=p_id AND payload_sha256=p_hash AND state IN ('pending','uncertain');
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_NOT_STAGEABLE'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.stage_bank_sync_operation(uuid,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.stage_bank_sync_operation(uuid,text,jsonb,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.get_recoverable_bank_sync_operations()
RETURNS TABLE(id uuid,request jsonb,token_cipher jsonb,payload_sha256 text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN QUERY SELECT o.id,o.request,o.token_cipher,o.payload_sha256 FROM eshop.bank_sync_operations o
    WHERE o.request IS NOT NULL AND o.state IN ('pending','uncertain','running')
      AND o.updated_at<now()-interval '5 minutes' ORDER BY o.updated_at,o.id LIMIT 10;
END;
$$;
REVOKE ALL ON FUNCTION public.get_recoverable_bank_sync_operations() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_recoverable_bank_sync_operations() TO service_role;

-- Only the authenticated management handler calls this after checking bank-admin rights.
CREATE OR REPLACE FUNCTION public.get_pending_bank_sync_details(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN (SELECT jsonb_build_object('id',id,'request',request,'payload_sha256',payload_sha256)
    FROM eshop.bank_sync_operations WHERE bank_account_id=p_bank_account_id AND operation='update_details'
    AND state IN ('pending','running','uncertain') ORDER BY created_at LIMIT 1);
END;
$$;
REVOKE ALL ON FUNCTION public.get_pending_bank_sync_details(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_bank_sync_details(bigint) TO service_role;

-- SOURCE: eshop_stripe/form_availability.sql
-- Private form projection. Configuration survives temporary provider restrictions.
CREATE OR REPLACE FUNCTION public.stripe_form_compatibility_internal(p_form bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE u bigint; currencies text[]; d jsonb; sale_end timestamptz; site text;
BEGIN
 SELECT o.unit,public.get_effective_form_data(f.id) INTO u,d
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form;
 IF u IS NULL THEN RETURN 'organizer_unavailable'; END IF;
 SELECT org.data->>'DEFAULT_URL' INTO site FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN public.organizations org ON org.id=o.organization WHERE f.id=p_form;
 IF site IS NULL OR site !~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9/_-]*)?$' THEN RETURN 'return_origin_unavailable'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.external_services WHERE unit=u AND type='FAKTUROID') THEN RETURN 'fakturoid_unsupported'; END IF;
 SELECT array_agg(DISTINCT p.currency_code::text) INTO currencies FROM public.form_fields ff
 JOIN eshop.products p ON p.product_type=ff.product_type WHERE ff.form=p_form AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false);
 IF cardinality(currencies) IS DISTINCT FROM 1 OR currencies[1] IS NULL OR NOT currencies[1]=ANY(ARRAY['CZK','EUR','PLN','USD','GBP']) THEN RETURN 'currency_unsupported'; END IF;
 IF EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
  WHERE ff.form=p_form AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false)
  AND coalesce((p.data#>>'{deposit,amount}')::numeric,0)>0) THEN RETURN 'deposit_unsupported'; END IF;
 IF EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
  WHERE ff.form=p_form AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false)
  AND coalesce(p.data->'meta_surcharge','{}'::jsonb)<>'{}'::jsonb) THEN RETURN 'surcharge_unsupported'; END IF;
 sale_end:=nullif(coalesce(d#>>'{schedule,end_time}',d->>'end_time'),'')::timestamptz;
 IF sale_end IS NOT NULL AND sale_end<=clock_timestamp()+interval '31 minutes' THEN RETURN 'sale_ending'; END IF;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.stripe_form_compatibility_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.validate_stripe_form_payment_configuration_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE config jsonb; c eshop.stripe_connections; org bigint; u bigint; reason text;
BEGIN
 SELECT f.data->'payments',o.organization,o.unit INTO config,org,u FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form;
 IF config IS NULL THEN RETURN; END IF;
 IF public.payment_provider_connection_internal(config,'stripe') IS NULL THEN RETURN; END IF;
 -- Serialize editor selection with a verified account replacement.
 PERFORM 1 FROM public.units WHERE id=u AND organization=org FOR UPDATE;
 SELECT * INTO c FROM eshop.stripe_connections WHERE id=public.payment_provider_connection_internal(config,'stripe');
 IF c.id IS NULL OR c.organization_id<>org OR c.unit_id<>u OR NOT c.model_verified OR c.state NOT IN ('connected','restricted') THEN
  RAISE EXCEPTION 'STRIPE_RECIPIENT_UNAVAILABLE'; END IF;
 reason:=public.stripe_form_compatibility_internal(p_form);
 IF reason IS NOT NULL THEN RAISE EXCEPTION 'STRIPE_CONFIGURATION_UNSUPPORTED: %',reason; END IF;
END $$;
REVOKE ALL ON FUNCTION public.validate_stripe_form_payment_configuration_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.stripe_form_payment_availability_internal(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE config jsonb; c eshop.stripe_connections; policy eshop.stripe_runtime_policy; org bigint; u bigint;
 bank boolean; card boolean; reason text; methods jsonb:='[]'::jsonb;
BEGIN
 SELECT f.data->'payments',o.organization,o.unit INTO config,org,u FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form;
 bank:=coalesce(config->'bankEnabled','false'::jsonb)='true'::jsonb AND public.payment_method_policy_enabled_internal(u,'bank');
 card:=public.payment_provider_connection_internal(config,'stripe') IS NOT NULL;
 IF bank THEN methods:=methods||jsonb_build_array('bank'); END IF;
 IF card THEN
  SELECT * INTO c FROM eshop.stripe_connections WHERE id=public.payment_provider_connection_internal(config,'stripe') AND organization_id=org AND unit_id=u;
  SELECT * INTO policy FROM eshop.stripe_runtime_policy WHERE organization_id=org AND livemode=c.livemode;
  reason:=CASE WHEN c.id IS NULL OR c.state NOT IN ('connected','restricted') THEN 'recipient_changed'
   WHEN NOT c.model_verified THEN 'model_unverified'
   WHEN c.paused THEN 'paused'
   WHEN NOT c.charges_enabled OR NOT c.card_payments_active OR c.state<>'connected' THEN 'stripe_restricted'
   WHEN NOT public.stripe_unit_feature_enabled_internal(u) OR NOT coalesce(policy.new_payments_enabled,false) THEN 'payments_disabled'
   ELSE public.stripe_form_compatibility_internal(p_form) END;
  IF reason IS NULL THEN methods:=jsonb_build_array('stripe')||methods; END IF;
 ELSE reason:='not_configured'; END IF;
 RETURN jsonb_build_object('configured',jsonb_build_object('bank',bank,'stripe',card),
  'available',methods,'stripeUnavailableReason',reason,'reservationSeconds',public.payment_sale_policy_internal()->'reservationSeconds',
  'supportedSurfaces',coalesce(to_jsonb(policy.supported_surfaces),'[]'::jsonb),
  'recipient',CASE WHEN c.id IS NOT NULL THEN jsonb_build_object('connectionId',c.id,
   'name',coalesce(nullif(btrim(c.business_name),''),(SELECT title FROM public.units WHERE id=c.unit_id AND organization=c.organization_id))) END);
END $$;
REVOKE ALL ON FUNCTION public.stripe_form_payment_availability_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assert_stripe_form_payable_internal(p_form bigint,p_expected_connection uuid,p_surface text)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; org bigint; u bigint; selected uuid; availability jsonb;
BEGIN
 SELECT public.payment_provider_connection_internal(f.data->'payments','stripe'),o.organization,o.unit INTO selected,org,u
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form FOR UPDATE OF f;
 IF selected IS NULL OR selected IS DISTINCT FROM p_expected_connection THEN RAISE EXCEPTION 'STRIPE_RECIPIENT_CHANGED'; END IF;
 -- Same locks are taken by pause/replacement and the kill switch. Submit rechecks availability under them.
 PERFORM 1 FROM public.units WHERE id=u AND organization=org FOR UPDATE;
 PERFORM 1 FROM eshop.stripe_connections WHERE id=selected FOR UPDATE;
 PERFORM 1 FROM eshop.stripe_runtime_policy WHERE organization_id=org AND livemode=(SELECT livemode FROM eshop.stripe_connections WHERE id=selected) FOR UPDATE;
 availability:=public.stripe_form_payment_availability_internal(p_form);
 IF NOT (availability->'available' ? 'stripe') THEN RAISE EXCEPTION 'STRIPE_UNAVAILABLE: %',availability->>'stripeUnavailableReason'; END IF;
 IF p_surface IS NULL OR NOT (availability->'supportedSurfaces' ? p_surface) THEN RAISE EXCEPTION 'STRIPE_SURFACE_UNVERIFIED'; END IF;
 RETURN selected;
END $$;
REVOKE ALL ON FUNCTION public.assert_stripe_form_payable_internal(bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: occasion_setup/bank_accounts.sql
CREATE OR REPLACE FUNCTION public.occasion_setup_bank_fingerprint_internal(p_bank bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('id',b.id,'account',b.account_number,
  'currencies',b.supported_currencies)::text,'UTF8'),'sha256'),'hex') FROM eshop.bank_accounts b WHERE b.id=p_bank;
$$;
REVOKE ALL ON FUNCTION public.occasion_setup_bank_fingerprint_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Draft editors see payment instructions, never credentials or account-admin
-- operations. Creating/linking accounts continues through the existing unit UI.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_bank_accounts(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF NOT coalesce(public.payment_method_policy_enabled_internal(d.unit,'bank'),false) THEN RETURN '{"canManage":false,"accounts":[]}'::jsonb; END IF;
 RETURN jsonb_build_object('canManage',public.get_is_manager_on_unit(d.unit),'accounts',coalesce((
  SELECT jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,
    'display',coalesce(nullif(b.account_number_human_readable,''),b.account_number),
    'currencies',b.supported_currencies,'priority',u.priority,'type',b.type,
    'bank_sync',(SELECT jsonb_build_object('state',c.state,'mode',c.mode)
      FROM eshop.bank_sync_connections c WHERE c.bank_account_id=b.id),
    'bank_sync_warning',public.bank_sync_warning(b.id),
    'fingerprint',public.occasion_setup_bank_fingerprint_internal(b.id)) ORDER BY u.priority,b.id)
  FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
  WHERE u.unit=d.unit AND b.type<>'CASH'),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_bank_accounts(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_bank_accounts(uuid) TO authenticated;

-- SOURCE: others/get_email_authoring_payment_accounts.sql
-- Read-only display metadata for the permission-gated email authoring endpoint.
-- The caller must first authorize the hierarchy through get_entity_email_templates.
CREATE OR REPLACE FUNCTION public.get_email_authoring_payment_accounts(
  p_unit_id bigint,
  p_occasion_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_organization bigint;
  v_linked jsonb;
  v_form_accounts jsonb;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role required' USING ERRCODE = '42501';
  END IF;

  SELECT u.organization INTO v_organization
  FROM public.units u
  JOIN public.organizations o ON o.id = u.organization
  WHERE u.id = p_unit_id;
  IF v_organization IS NULL THEN
    RAISE EXCEPTION 'Invalid email authoring unit' USING ERRCODE = '22023';
  END IF;
  IF p_occasion_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.occasions o
    WHERE o.id = p_occasion_id AND o.unit = p_unit_id
      AND o.organization = v_organization
  ) THEN
    RAISE EXCEPTION 'Invalid email authoring occasion hierarchy' USING ERRCODE = '22023';
  END IF;

  IF NOT coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'bank'),false) THEN RETURN '{"linkedAccounts":[],"formAccountIds":[]}'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'priority', uba.priority,
    'bank_accounts', jsonb_build_object(
      'id', ba.id,
      'type', ba.type,
      'account_number', ba.account_number,
      'account_number_human_readable', ba.account_number_human_readable,
      'supported_currencies', ba.supported_currencies
    )
  ) ORDER BY uba.priority, ba.id), '[]'::jsonb)
  INTO v_linked
  FROM eshop.unit_bank_accounts uba
  JOIN eshop.bank_accounts ba ON ba.id = uba.bank_account
  WHERE uba.unit = p_unit_id AND ba.type IS DISTINCT FROM 'CASH';

  SELECT COALESCE(jsonb_agg(account_id ORDER BY account_id), '[]'::jsonb)
  INTO v_form_accounts
  FROM (
    SELECT DISTINCT f.bank_account AS account_id
    FROM public.forms f
    JOIN eshop.unit_bank_accounts uba
      ON uba.bank_account = f.bank_account AND uba.unit = p_unit_id
    JOIN eshop.bank_accounts ba ON ba.id = f.bank_account
    WHERE f.occasion = p_occasion_id AND ba.type IS DISTINCT FROM 'CASH'
  ) configured;

  RETURN jsonb_build_object('linkedAccounts', v_linked, 'formAccountIds', v_form_accounts);
END;
$$;

REVOKE ALL ON FUNCTION public.get_email_authoring_payment_accounts(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_authoring_payment_accounts(bigint, bigint) TO service_role;

-- SOURCE: occasion_setup/finalize.sql
-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint; configuration_source bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 email_banner text; intro_image text; form_link text; selected_bank bigint; bank_fingerprint text; bank_currencies text[]; required_currencies text[]; wave jsonb; target jsonb; saved_wave jsonb; wave_product bigint;
 has_tickets boolean;
 unit_defaults jsonb; communication_new boolean; reply_email text; form_meta jsonb; reminder_days numeric;
 payment_method text;
 publish_to_catalog boolean;
 sale_mode text; sale_start timestamptz; sale_end timestamptz;
 blueprint_mode text; blueprint_id bigint; blueprint_source bigint; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE SQLSTATE 'PT409' USING MESSAGE='Draft changed in another session'; END IF;
 payload := public.normalize_occasion_setup_appearance_internal(d.data);
 payload:=public.normalize_setup_payments_internal(payload);
 IF payload->'paymentRepairRequired'='true'::jsonb THEN RAISE invalid_parameter_value USING MESSAGE='Payment recipient requires explicit repair'; END IF;
 PERFORM public.payment_policy_fence_internal(d.organization);
 payment_method:=CASE WHEN payload#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' WHEN payload#>'{payments,bankEnabled}'='false'::jsonb THEN 'online' ELSE 'bank' END;
 blueprint_mode:=CASE payload->>'blueprintMode'
  WHEN 'Bez plánku' THEN 'none' WHEN 'Nový' THEN 'new' WHEN 'Převzít' THEN 'copy'
  ELSE payload->>'blueprintMode' END;
 IF blueprint_mode IS NULL THEN blueprint_mode:=CASE WHEN jsonb_typeof(payload->'blueprintLayoutDraft')='object' THEN 'copy' ELSE 'none' END; END IF;
 IF blueprint_mode NOT IN ('none','new','copy') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid blueprint mode'; END IF;
 -- The form owns its sale window. Absent intent keeps historical drafts closed.
 sale_mode:=coalesce(payload->>'saleMode','preparation');
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  IF sale_mode NOT IN ('preparation','scheduled','immediate') THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid sale mode'; END IF;
  sale_end:=coalesce(nullif(payload->>'saleEnd','')::timestamptz,(payload->>'end')::timestamptz);
  IF sale_end IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='Sale end is required'; END IF;
  IF sale_mode='scheduled' THEN
   sale_start:=nullif(payload->>'saleStart','')::timestamptz;
   IF sale_start IS NULL OR sale_start<=clock_timestamp() OR sale_start>=sale_end THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid scheduled sale start'; END IF;
  ELSIF sale_mode='immediate' THEN
   IF sale_end<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='Sale has already ended'; END IF;
   sale_start:=clock_timestamp();
  END IF;
 END IF;
 PERFORM public.validate_setup_email_templates_internal(payload->'emailTemplateOverrides');
 communication_new:=payload ? 'communicationTone';
 IF communication_new THEN
  IF coalesce(payload->>'communicationTone','') NOT IN ('inherit','formal','informal')
    OR coalesce(payload->>'replyToMode','') NOT IN ('inherit','custom')
    OR coalesce(payload->>'remindersMode','') NOT IN ('inherit','enabled','disabled') THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid communication options'; END IF;
  IF payload->>'replyToMode'='custom' THEN
   reply_email:=btrim(payload->>'replyToEmail');
   IF reply_email IS NULL OR length(reply_email)>254 OR reply_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid reply email'; END IF;
  END IF;
  SELECT coalesce(u.data,'{}'::jsonb) INTO unit_defaults FROM public.units u WHERE u.id=d.unit;
 END IF;
 source_id := (payload->>'sourceId')::bigint;
 intro_image:=nullif(payload->>'introImage','');
 email_banner:=payload->>'emailBanner';
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 FOREACH configuration_source IN ARRAY ARRAY[nullif(payload->>'formSourceOccasionId','')::bigint,nullif(payload->>'blueprintSourceOccasionId','')::bigint] LOOP
  IF configuration_source IS NOT NULL AND (NOT public.can_copy_occasion_source(configuration_source) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=configuration_source AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END LOOP;
 -- A plan can be selected independently of the event/form copy. Resolve its
 -- resource scope from the stored plan, rather than the overall copy source.
 IF blueprint_mode='copy' THEN
  IF nullif(payload->>'blueprintSourceId','') IS NOT NULL THEN
   SELECT occasion INTO blueprint_source FROM eshop.blueprints WHERE id=(payload->>'blueprintSourceId')::bigint;
   IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='Blueprint source missing'; END IF;
  ELSE
   blueprint_source:=coalesce(nullif(payload->>'blueprintSourceOccasionId','')::bigint,
     nullif(payload->>'formSourceOccasionId','')::bigint,source_id);
  END IF;
  IF blueprint_source IS NOT NULL AND (NOT public.can_copy_occasion_source(blueprint_source)
    OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=blueprint_source AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END IF;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 -- Draft uploads use the existing unit-scoped image writer. Never trust an
 -- arbitrary URL supplied by a client, or adopt another unit's image.
 IF intro_image IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=intro_image AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft image access denied'; END IF;
 IF nullif(email_banner,'') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=email_banner AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft email banner access denied'; END IF;
 IF coalesce((payload->>'isPromoted')::boolean,false) AND intro_image IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Promotion requires an intro image'; END IF;
 -- Selection is sufficient; current permissions, currencies and account
 -- fingerprint are still verified under locks before materialization.
 SELECT array_agg(DISTINCT coalesce(nullif(p->>'currency_code',''),'CZK')) INTO required_currencies
 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p
 WHERE coalesce((payload->>'formEnabled')::boolean,true) AND NOT coalesce((f->>'is_hidden')::boolean,false)
   AND NOT coalesce((p->>'is_hidden')::boolean,false) AND (p->>'price')::numeric>0;
 IF payment_method='bank' AND NOT coalesce(public.payment_method_policy_enabled_internal(d.unit,'bank'),false) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
 IF required_currencies IS NOT NULL AND payment_method='bank' AND (payload ? 'bankAccountId' OR payload ? 'bankAccountConfirmed' OR sale_mode<>'preparation') THEN
  IF nullif(payload->>'bankAccountId','') IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account selection required'; END IF;
  selected_bank:=(payload->>'bankAccountId')::bigint;
  PERFORM 1 FROM eshop.bank_accounts ba JOIN eshop.unit_bank_accounts u ON u.bank_account=ba.id
   WHERE u.unit=d.unit AND ba.id=selected_bank AND ba.type<>'CASH' FOR SHARE OF ba,u;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Bank account access denied'; END IF;
  -- Take a fresh statement snapshot after acquiring locks: a concurrent account
  -- update may have committed while the locking statement was waiting.
  SELECT ba.supported_currencies,public.occasion_setup_bank_fingerprint_internal(ba.id)
   INTO bank_currencies,bank_fingerprint FROM eshop.bank_accounts ba WHERE ba.id=selected_bank;
  IF bank_currencies IS NULL OR NOT required_currencies <@ bank_currencies THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account currency mismatch'; END IF;
  IF bank_fingerprint IS DISTINCT FROM payload->>'bankAccountFingerprint' THEN
   RAISE SQLSTATE 'PT409' USING MESSAGE='Bank account details changed; select again'; END IF;
 END IF;
 -- Active form choices own enabled features, not whether an editor was visited.
 has_tickets:=coalesce((payload->>'formEnabled')::boolean,true) AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
  WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false));
 IF has_tickets THEN
  features:=features||jsonb_build_array((coalesce(nullif(payload->'ticketDraft','null'::jsonb),'{}'::jsonb)-'layout')
    ||'{"code":"ticket","is_enabled":true}'::jsonb);
 END IF;
 IF blueprint_mode<>'none' AND (
  NOT coalesce((payload->>'formEnabled')::boolean,true) OR
  NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]')) binding
   JOIN jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,layout,nodes}','[]')) node ON node->>'id'=binding->>'nodeId'
   WHERE node->>'kind'='seat' AND binding->>'productId' IS NOT NULL AND NOT coalesce((binding->>'blocked')::boolean,false)
   UNION ALL
   SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,areaBindings}','[]')) binding
   JOIN jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,layout,nodes}','[]')) node ON node->>'id'=binding->>'nodeId'
   WHERE node->>'kind'='capacityArea' AND binding->>'productId' IS NOT NULL
    AND (binding->>'inventoryContextId' IS NOT NULL OR coalesce((binding->>'capacity')::numeric,0)>0)
  )) THEN RAISE invalid_parameter_value USING MESSAGE='Selected blueprint requires a form and sellable places'; END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  features := features || jsonb_build_array(jsonb_build_object('code','form','is_enabled',true) ||
    CASE WHEN communication_new THEN jsonb_build_object(
      'reminder_is_enabled',coalesce((unit_defaults->>'is_reminder_enabled')::boolean,true),
      'reminder_interval_seconds',coalesce((unit_defaults->>'reminder_interval_seconds')::bigint,86400)) ELSE '{}'::jsonb END);
 END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 publish_to_catalog:=coalesce((payload->>'formEnabled')::boolean,true) AND sale_mode<>'preparation' AND coalesce((payload->>'listPubliclyOnPublish')::boolean,true);
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end',
  'is_hidden',NOT publish_to_catalog,
  'is_open',publish_to_catalog,
  'is_promoted',coalesce((payload->>'isPromoted')::boolean,false),
  'features',features,'data',jsonb_strip_nulls(jsonb_build_object('client_sync_v1',false,
   'setup_listing_intent',coalesce((payload->>'listPubliclyOnPublish')::boolean,true),
   'email_banner',email_banner,'image',intro_image,'place_name',nullif(btrim(payload->>'placeName'),''),'reply_to',reply_email)));
 policies:=public.abuse_policy_bundle_v1(ARRAY['occasion.creation','occasion.copy'],d.unit,d.organization);
 IF source_id IS NOT NULL AND (coalesce((payload->>'copyProgram')::boolean,false) OR coalesce((payload->>'copyInformation')::boolean,false) OR coalesce((payload->>'copyEmails')::boolean,false)) THEN
  PERFORM public.admit_occasion_copy_v1(source_id,d.unit,d.organization,policies->'occasion.copy'); END IF;
 PERFORM public.admit_occasion_creation_v1(auth.uid(),d.unit,d.organization,NULL,policies->'occasion.creation');
 PERFORM public.update_occasion_internal_v1(config);
 new_id := currval(pg_get_serial_sequence('public.occasions','id'));
 SELECT o.features INTO features FROM public.occasions o WHERE o.id=new_id;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_editor_order,is_editor_order_view)
 VALUES(new_id,auth.uid(),true,true,true,true,true);
 form_data := payload->'formDraft';
 IF form_data IS NOT NULL AND form_data<>'null'::jsonb AND coalesce((payload->>'formEnabled')::boolean,true) THEN
  -- Saved and released drafts may still contain source measurement settings.
  form_data:=jsonb_set(form_data,'{data}',public.normalize_form_metadata_internal(form_data->'data')-'analytics');
  IF communication_new THEN
   -- Semantic choices override legacy source metadata. Inherited values stay
   -- absent so reply/tone remain live unit defaults; reminder defaults above
   -- are a creation snapshot and never requeue existing events.
   form_meta:=coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)
     -'communication_tone'-'is_reminder_enabled'-'reminder_interval_seconds';
   IF payload->>'communicationTone'<>'inherit' THEN
    form_meta:=form_meta||jsonb_build_object('communication_tone',payload->>'communicationTone'); END IF;
   IF required_currencies IS NOT NULL THEN
    IF payload->>'remindersMode'<>'inherit' THEN
     form_meta:=form_meta||jsonb_build_object('is_reminder_enabled',payload->>'remindersMode'='enabled'); END IF;
    IF nullif(btrim(payload->>'reminderLeadDays'),'') IS NOT NULL THEN
     reminder_days:=replace(payload->>'reminderLeadDays',',','.')::numeric;
     IF reminder_days<0 OR reminder_days::text IN ('NaN','Infinity','-Infinity') THEN
      RAISE invalid_parameter_value USING MESSAGE='Invalid reminder interval'; END IF;
     form_meta:=form_meta||jsonb_build_object('reminder_interval_seconds',round(reminder_days*86400)::bigint);
    END IF;
   END IF;
   form_data:=jsonb_set(form_data,'{data}',form_meta);
  END IF;
  -- Explicit values also clear dates inherited from a source/default form.
  form_meta:=coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)
    -'start_time'-'end_time'-'enable_countdown';
  form_meta:=jsonb_set(form_meta,'{schedule}',coalesce(nullif(form_meta->'schedule','null'::jsonb),'{}'::jsonb)
   ||jsonb_build_object('start_time',sale_start,'end_time',sale_end,
     'enable_countdown',coalesce((payload->>'saleCountdown')::boolean,false),
     'sale_preparation',sale_mode='preparation'));
  form_meta:=form_meta-'sale_opening_notifications';
  form_meta:=jsonb_set(form_meta,'{design}',coalesce(nullif(form_meta->'design','null'),'{}')||
    jsonb_build_object('presale_header',coalesce(form_meta#>>'{design,presale_header}','event_and_date')));
  IF coalesce((payload->>'saleOpeningNotifications')::boolean,false) THEN
   IF sale_mode<>'scheduled' THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_requires_scheduled_sale'; END IF;
   form_meta:=form_meta||'{"sale_opening_notifications":{"enabled":true,"collection_paused":false}}'::jsonb;
   IF coalesce((payload->>'saleCountdown')::boolean,false) AND position('form-countdown' IN coalesce(form_meta#>>'{schedule,countdown_title}',''))=0 THEN
    form_meta:=jsonb_set(form_meta,'{schedule,countdown_title}',to_jsonb(coalesce(form_meta#>>'{schedule,countdown_title}','')||'<div class="html-editor-block form-countdown"></div>'));
   END IF;
   IF position('form-sale-opening-notification' IN coalesce(form_meta#>>'{schedule,countdown_title}',''))=0 THEN
    form_meta:=jsonb_set(form_meta,'{schedule,countdown_title}',to_jsonb(CASE
     WHEN position('<div class="html-editor-block form-countdown"></div>' IN coalesce(form_meta#>>'{schedule,countdown_title}',''))>0 THEN
      replace(form_meta#>>'{schedule,countdown_title}','<div class="html-editor-block form-countdown"></div>',
       '<div class="html-editor-block form-countdown"></div><div class="html-editor-block form-sale-opening-notification"></div>')
     ELSE coalesce(form_meta#>>'{schedule,countdown_title}','')||'<div class="html-editor-block form-sale-opening-notification"></div>' END));
   END IF;
  END IF;
  IF coalesce(nullif(payload->>'formSourceOccasionId','')::bigint,source_id) IS NOT NULL
     AND EXISTS(SELECT 1 FROM public.occasions src WHERE src.id=coalesce(nullif(payload->>'formSourceOccasionId','')::bigint,source_id) AND src.unit IS DISTINCT FROM d.unit) THEN
   form_meta:=public.strip_form_payment_connections_internal(form_meta);
  END IF;
  form_meta:=jsonb_set(form_meta,'{payments}',payload->'payments');
  IF payment_method='cash' THEN form_meta:=form_meta||'{"payment_deadline":{"mode":"none"}}'::jsonb; END IF;
  form_data:=jsonb_set(form_data,'{data}',form_meta);
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
  END IF;
  form_link:=nullif(form_data->>'link','');
  IF source_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.forms source_form WHERE source_form.occasion=source_id AND source_form.link=form_link) THEN
   form_link:=(SELECT link FROM public.forms WHERE id=form_id);
  END IF;
  IF coalesce((payload->>'formLinkAutomatic')::boolean,false) THEN
   FOR j IN 1..20 LOOP
    -- Preserve the preview where still free; re-suggest if another writer won.
    IF form_link IS NULL OR EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=form_link AND form IS DISTINCT FROM form_id) THEN
     form_link:=public.suggest_occasion_setup_form_link(p_id,payload->>'title',NULL)->>'suggestion';
    END IF;
    BEGIN
     form_link:=public.reserve_public_link_internal('form',form_id,form_link,false);
     EXIT;
    EXCEPTION WHEN unique_violation THEN
     IF j=20 THEN RAISE; END IF;
     form_link:=NULL;
    END;
   END LOOP;
  END IF;
  DELETE FROM public.form_fields WHERE form=form_id;
  DELETE FROM eshop.products WHERE occasion=new_id;
  DELETE FROM eshop.product_types WHERE occasion=new_id;
  -- Active plan owns the public seat selector. Catalog products remain available without it.
  form_data:=jsonb_set(form_data,'{fields}',coalesce((
   SELECT jsonb_agg(f) FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f
   WHERE f->>'type' IS DISTINCT FROM 'spot'),'[]'::jsonb)||
   CASE WHEN blueprint_mode<>'none' THEN jsonb_build_array('{"order":-1}'::jsonb ||
     coalesce((SELECT f FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f WHERE f->>'type'='spot' LIMIT 1),'{}'::jsonb) ||
     '{"type":"spot","is_ticket_field":true,"is_hidden":false,"is_required":true}'::jsonb) ELSE '[]'::jsonb END);
  -- Every field/product is newly owned by this occasion. Retain a local mapping
  -- for seats that referred to draft/source product IDs.
  FOR field IN SELECT value FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) LOOP
   pt := coalesce(nullif(field->'product_type_data','null'::jsonb),field->'product_type');
   IF jsonb_typeof(pt)<>'object' THEN pt := NULL; END IF;
   field := field - 'id' - 'form' - 'product_type';
   IF pt IS NOT NULL AND pt<>'null'::jsonb THEN
    old_products := old_products || coalesce(pt->'products','[]');
    products := '[]';
    FOR product IN SELECT value FROM jsonb_array_elements(coalesce(pt->'products','[]')) LOOP
     products := products || jsonb_build_array(product-'id'-'occasion'-'product_type');
    END LOOP;
    field := (field-'product_type_data') || jsonb_build_object('product_type',(pt-'id'-'occasion') || jsonb_build_object('products',products));
   END IF;
   old_types := old_types || jsonb_build_array(pt->'id');
   fields := fields || jsonb_build_array(field);
  END LOOP;
  -- This form was born inside this same setup transaction. Its original form
  -- baseline is zero; the setup revision/command still owns materialization.
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint'-'bank_account') || jsonb_build_object(
   'expected_aggregate_version',0,'id',form_id,'occasion',new_id,'link',coalesce(form_link,(SELECT link FROM public.forms WHERE id=form_id)),
   'payment_selection_intent','replace','is_open',sale_mode<>'preparation','bank_account',selected_bank,'form_fields',fields));
  IF result->>'code'<>'200' THEN RAISE EXCEPTION '%',result; END IF;
  IF jsonb_array_length(old_types)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_types)-1 LOOP
    IF old_types->>idx IS NOT NULL THEN type_map := type_map || jsonb_build_object(old_types->>idx,result->'form_fields'->idx->'product_type'->'id'); END IF;
   END LOOP;
  END IF;
  SELECT coalesce(jsonb_agg(p ORDER BY field_order,product_order),'[]') INTO new_products
  FROM (SELECT p,ff.ordinality field_order,pp.ordinality product_order
   FROM jsonb_array_elements(result->'form_fields') WITH ORDINALITY ff(f,ordinality)
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(ff.f->'product_type'->'products','[]')) WITH ORDINALITY pp(p,ordinality)) x;
  IF jsonb_array_length(old_products)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_products)-1 LOOP
    IF old_products->idx->>'id' IS NOT NULL THEN product_map := product_map || jsonb_build_object(old_products->idx->>'id',new_products->idx->'id'); END IF;
   END LOOP;
  END IF;
  IF blueprint_mode<>'none' THEN
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]')) binding
     WHERE binding->>'productId' IS NULL OR product_map->>(binding->>'productId') IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='Every blueprint seat requires a form product'; END IF;
  IF payload->'blueprintLayoutDraft' IS NOT NULL AND payload->'blueprintLayoutDraft'<>'null'::jsonb THEN
   IF payload#>>'{blueprintLayoutDraft,layout,schemaVersion}'='2' THEN
    PERFORM public.copy_blueprint_text_resources_internal(NULL,d.id,new_id,payload#>'{blueprintLayoutDraft,layout}');
   END IF;
   blueprint_id:=public.materialize_setup_blueprint_layout_internal(payload->'blueprintLayoutDraft',product_map,blueprint_source,new_id,d.unit);
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features:=features||'[{"code":"blueprint","is_enabled":true}]';
  ELSE
   RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_REQUIRED';
  END IF;
  END IF;
 END IF;
 -- Plans are materialized through the existing price-wave commands, using
 -- newly mapped product IDs. No source IDs or second scheduler escape.
 IF coalesce((payload->>'priceWavesEnabled')::boolean,false) AND coalesce((payload->>'formEnabled')::boolean,true)
   AND EXISTS(SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
     WHERE p.occasion=new_id AND ff.form=form_id AND NOT coalesce(ff.is_hidden,false)
       AND p.price>0 AND NOT coalesce(p.is_hidden,false)) THEN
  FOR wave IN SELECT value FROM jsonb_array_elements(coalesce(payload->'priceWaves','[]')) LOOP
   saved_wave:=public.create_product_price_wave((SELECT link FROM public.occasions WHERE id=new_id),(wave->>'change_time')::timestamptz);
   FOR target IN SELECT value FROM jsonb_array_elements(coalesce(wave->'targets','[]')) LOOP
    wave_product:=(product_map->>(target->>'product'))::bigint;
    IF wave_product IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='Price wave product missing'; END IF;
    PERFORM public.save_product_wave_target((saved_wave->>'id')::bigint,wave_product,(saved_wave->>'revision')::bigint,
      (target->>'price')::numeric,(target->>'is_hidden')::boolean,NULL,NULL);
   END LOOP;
  END LOOP;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF has_tickets AND payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft'||'{"code":"ticket","is_enabled":true}'::jsonb;
  SELECT jsonb_set(pt,'{layout,templates}',jsonb_object_agg(t.key,
    jsonb_set(t.value,'{elements}',coalesce((SELECT jsonb_agg(CASE WHEN e->>'binding'='productType'
      THEN jsonb_set(e,'{productTypeId}',coalesce(type_map->(e->>'productTypeId'),'null'::jsonb)) ELSE e END ORDER BY n)
      FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)),'[]'::jsonb))))
   INTO pt FROM jsonb_each(pt->'layout'->'templates') t;
  features := (SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN pt ELSE f END) FROM jsonb_array_elements(features) f);
 END IF;
 PERFORM public.validate_ticket_layout_references(new_id,f->'layout') FROM jsonb_array_elements(features) f WHERE f ? 'layout';
 final_features := features;
 UPDATE public.occasions SET features=final_features WHERE id=new_id;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN
  PERFORM public.materialize_occasion_setup_program_internal(coalesce(payload->'sourceProgram','[]'),new_id,d.unit);
 END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN
  INSERT INTO public.information(occasion,unit,title,description,type,data)
  SELECT new_id,d.unit,i->>'title',i->>'description',i->>'type',i->'data'
  FROM jsonb_array_elements(coalesce(payload->'sourceInformation','[]')) i;
 END IF;
 IF coalesce((payload->>'copyEmails')::boolean,false) AND source_id IS NOT NULL THEN
  INSERT INTO public.email_templates(occasion,unit,organization,code,title,subject,html)
  SELECT new_id,d.unit,d.organization,code,title,subject,html FROM public.email_templates WHERE occasion=source_id;
 END IF;
 PERFORM public.admit_occasion_copy_v1(new_id,d.unit,d.organization,policies->'occasion.copy');
 IF email_banner IS NOT NULL THEN
  PERFORM public.update_entity_email_banner('occasion',new_id,email_banner);
 END IF;
 -- Draft edits override copied/inherited content only on the newly created occasion.
 FOR pt IN SELECT jsonb_build_object('code',key,'content',value)
  FROM jsonb_each(coalesce(payload->'emailTemplateOverrides','{}')) LOOP
  DELETE FROM public.email_templates WHERE occasion=new_id AND code=pt->>'code';
  INSERT INTO public.email_templates(occasion,unit,organization,code,subject,html)
  VALUES(new_id,d.unit,d.organization,pt->>'code',pt#>>'{content,subject}',pt#>>'{content,html}');
 END LOOP;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion','occasion',new_id,new_id::text,1);
 INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
 VALUES(d.unit,auth.uid(),'user','occasion.setup.finalize','configuration') RETURNING * INTO v_commit;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 SELECT v_commit.commit_id,0,'occasion',new_id::text,'insert',left(title,240),ARRAY['aggregate'] FROM public.occasions WHERE id=new_id;
 PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,d.unit);
 receipt := jsonb_build_object('status','applied','code',200,'data',
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id),
   'formLink',(SELECT link FROM public.forms WHERE id=form_id),'saleMode',sale_mode,'isOpen',(SELECT is_open FROM public.occasions WHERE id=new_id),'isHidden',(SELECT is_hidden FROM public.occasions WHERE id=new_id),'isPromoted',(SELECT is_promoted FROM public.occasions WHERE id=new_id)));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;

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

-- SOURCE: others/get_ticket_layout_write_contract_v1.sql
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
  ('public.can_read_orders(bigint)','795b29c048acb37bc949683bfc586f43',true,true),
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

-- SOURCE: others/email_variable_contract.sql
-- Generated by automation/generate_email_variables.py. Retired placeholders are rejected, never translated.
CREATE OR REPLACE FUNCTION public.email_template_variables_are_canonical(p_text text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT coalesce(p_text !~ '\{\{[[:space:]]*(order_symbol|occasion_title|eventTitle|eventUrl|resetPasswordLink)[[:space:]]*\}\}',true);
$$;
CREATE OR REPLACE FUNCTION public.email_template_overrides_are_canonical(p_overrides jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT NOT EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(p_overrides)='object'
   THEN p_overrides ELSE '{}'::jsonb END) item
  WHERE NOT public.email_template_variables_are_canonical(item.value->>'subject')
     OR NOT public.email_template_variables_are_canonical(item.value->>'html'));
$$;
REVOKE ALL ON FUNCTION public.email_template_variables_are_canonical(text),public.email_template_overrides_are_canonical(jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.email_template_variables_are_canonical(text),public.email_template_overrides_are_canonical(jsonb)
 TO service_role;

-- SOURCE: payment_providers/released_bank_readers.sql
-- Mechanical compatibility for issued <=0.20.590 clients and their cached PWAs.
-- Remove once supported clients all send unit context. Ambiguity never picks a unit.
CREATE OR REPLACE FUNCTION public.released_bank_unit_internal(p_account bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE units bigint[];
BEGIN
 SELECT array_agg(u.id ORDER BY u.id) INTO units FROM public.units u
 WHERE public.can_manage_unit_bank_accounts(u.id) AND NOT public.is_demo_unit(u.id)
 AND (p_account IS NULL OR EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=u.id AND l.bank_account=p_account));
 IF coalesce(cardinality(units),0)<>1 THEN
  RAISE insufficient_privilege USING MESSAGE='PAYMENT_BANK_SCOPE_REQUIRED'; END IF;
 RETURN units[1];
END $$;
REVOKE ALL ON FUNCTION public.released_bank_unit_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_my_admin_bank_accounts()
RETURNS TABLE (
    id bigint,
    account_number text,
    account_number_human_readable text,
    title text,
    creditor_name text,
    type text,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    linked_units text[],
    last_fetch_time timestamptz,
    last_fio_fetch_time timestamptz,
    bank_sync jsonb
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT * FROM public.get_linkable_bank_accounts(public.released_bank_unit_internal());
$$;
REVOKE ALL ON FUNCTION public.get_my_admin_bank_accounts() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_my_admin_bank_accounts() TO authenticated;
CREATE OR REPLACE FUNCTION public.get_bank_transaction_history(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_read_bank_transactions(p_bank_account_id) THEN RAISE insufficient_privilege; END IF;
 RETURN public.get_bank_transaction_history(p_bank_account_id,public.released_bank_unit_internal(p_bank_account_id));
END $$;
REVOKE ALL ON FUNCTION public.get_bank_transaction_history(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_transaction_history(bigint) TO authenticated;
