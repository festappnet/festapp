-- One typed SQL entrypoint for connector-owned persistence and financial facts.
-- The handler identifier is read from a migration-owned table and quoted from
-- pg_catalog; all business inputs are passed as bound parameters.
CREATE OR REPLACE FUNCTION public.payment_provider_call_internal(p_provider text,p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE handler_name name; result jsonb;
BEGIN
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
 SELECT public.payment_method_registered_internal(p_method) AND p_method NOT IN ('bank','cash');
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
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE handler IS NOT NULL ORDER BY provider_key LOOP
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
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE handler IS NOT NULL ORDER BY provider_key LOOP
  BEGIN
   current:=public.payment_provider_call_internal(r.provider_key,'unit_fields',jsonb_build_object('unitId',p_unit));
   IF jsonb_typeof(current) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_PROJECTION_INVALID'; END IF;
  EXCEPTION WHEN OTHERS THEN current:='{"available":false,"reason":{"code":"provider_unavailable"}}'; END;
  fields:=fields||jsonb_build_object(r.provider_key,current);
 END LOOP;
 RETURN jsonb_build_object('payment_providers',features,'providerFields',fields)
  ||CASE WHEN fields ? 'stripe' THEN jsonb_build_object('stripe_preview_enabled',fields#>'{stripe,stripe_preview_enabled}') ELSE '{}'::jsonb END;
END $$;
CREATE OR REPLACE FUNCTION public.payment_sale_policy_internal()
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT '{"reservationSeconds":1860,"fullPaymentOnly":true,"depositsSupported":false,"surchargesSupported":false}'::jsonb;
$$;
CREATE OR REPLACE FUNCTION public.form_payment_availability_internal(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; current jsonb; providers jsonb:='{}'; available jsonb:='[]'; config jsonb; bank boolean; cash boolean; configured boolean; enabled boolean;
BEGIN
 SELECT data->'payments' INTO config FROM public.forms WHERE id=p_form;
 bank:=FOUND AND coalesce(config->'bankEnabled','true'::jsonb)='true'::jsonb;
 cash:=config->'cashEnabled'='true'::jsonb;
 bank:=bank AND EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
   JOIN eshop.unit_bank_accounts link ON link.unit=o.unit JOIN eshop.bank_accounts b ON b.id=link.bank_account
   WHERE f.id=p_form AND (f.bank_account IS NULL OR f.bank_account=b.id) AND b.type IS DISTINCT FROM 'CASH'
   AND NOT EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
    WHERE ff.form=f.id AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false)
    AND p.price>0 AND NOT coalesce(b.supported_currencies,'{}'::text[]) @> ARRAY[trim(p.currency_code)]));
 IF bank THEN available:=jsonb_build_array('bank'); END IF;
 IF cash THEN available:=jsonb_build_array('cash'); END IF;
 FOR r IN SELECT provider_key,legacy_connection_field FROM eshop.payment_providers WHERE handler IS NOT NULL ORDER BY provider_key LOOP
  configured:=nullif(config#>>ARRAY['providerConnections',r.provider_key],'') IS NOT NULL OR nullif(config->>r.legacy_connection_field,'') IS NOT NULL;
  BEGIN
   PERFORM public.payment_provider_connection_internal(config,r.provider_key);
   current:=public.payment_provider_call_internal(r.provider_key,'form_availability',jsonb_build_object('formId',p_form));
   IF jsonb_typeof(current) IS DISTINCT FROM 'object' OR current->>'providerId' IS DISTINCT FROM r.provider_key
    OR jsonb_typeof(current->'available') IS DISTINCT FROM 'boolean' OR jsonb_typeof(current->'configured') IS DISTINCT FROM 'boolean'
    OR jsonb_typeof(current->'supportedSurfaces') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_PROJECTION_INVALID'; END IF;
   enabled:=configured AND current->'available'='true'::jsonb AND current->'configured'='true'::jsonb;
   current:=current||jsonb_build_object('available',enabled,'configured',configured,'policy',public.payment_sale_policy_internal());
  EXCEPTION WHEN OTHERS THEN
   current:=jsonb_build_object('providerId',r.provider_key,'configured',configured,'available',false,
    'reason',jsonb_build_object('code',CASE WHEN configured THEN 'provider_unavailable' ELSE 'not_configured' END),
    'supportedSurfaces','[]'::jsonb,'recipient',NULL,'policy',public.payment_sale_policy_internal());
   enabled:=false;
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
 IF config->'cashEnabled'='true'::jsonb AND EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
   JOIN eshop.external_services e ON e.unit=o.unit AND e.type='FAKTUROID' WHERE f.id=p_form) THEN
  RAISE EXCEPTION 'CASH_FAKTUROID_UNSUPPORTED: Cash reservations cannot use mandatory Fakturoid invoicing'; END IF;
 PERFORM public.resolve_form_payment_policy_internal(p_form,CASE WHEN config->'cashEnabled'='true'::jsonb THEN 'cash' ELSE 'bank' END);
 connections:=coalesce(config->'providerConnections','{}'::jsonb);
 IF jsonb_typeof(connections)<>'object' THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 FOR entry IN SELECT * FROM jsonb_each(connections) LOOP
  IF jsonb_typeof(entry.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=entry.key AND handler IS NOT NULL) THEN
   RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  PERFORM (entry.value#>>'{}')::uuid;
 END LOOP;
 IF config->'bankEnabled'='false'::jsonb AND config->'cashEnabled'<>'true'::jsonb
  AND NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE handler IS NOT NULL AND public.payment_provider_connection_internal(config,provider_key) IS NOT NULL)
  AND EXISTS(SELECT 1 FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id JOIN eshop.products p ON p.product_type=ff.product_type
   WHERE f.id=p_form AND f.is_open AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false) AND p.price>0) THEN
  RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INCOMPLETE'; END IF;
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE handler IS NOT NULL LOOP
  IF public.payment_provider_connection_internal(config,r.provider_key) IS NOT NULL THEN
   PERFORM public.payment_provider_call_internal(r.provider_key,'validate_form',jsonb_build_object('formId',p_form));
  END IF;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.provider_form_editor_fields_internal(p_unit bigint,p_occasion bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; fields jsonb:='{}'; current jsonb;
BEGIN
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE handler IS NOT NULL ORDER BY provider_key LOOP
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
