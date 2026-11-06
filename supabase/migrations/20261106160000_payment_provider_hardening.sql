-- Payment provider hardening. Forward-only; no sales activation or network jobs.

-- SOURCE: payment_providers/configuration.sql
SET LOCAL ROLE postgres;
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
 saved:=saved||jsonb_build_object('bankEnabled',coalesce(saved->'bankEnabled','true'),'providerConnections',connections);
 IF p_input IS NULL THEN RETURN saved; END IF;
 incoming:=coalesce(nullif(p_input,'null'),'{}');
 IF jsonb_typeof(incoming)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(incoming) k WHERE k NOT IN ('bankEnabled','providerConnections','stripeConnectionId'))
  OR (incoming ? 'bankEnabled' AND jsonb_typeof(incoming->'bankEnabled')<>'boolean') THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 IF incoming ? 'providerConnections' THEN
  connections:=incoming->'providerConnections';
  IF jsonb_typeof(connections) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  IF incoming ? 'stripeConnectionId' AND incoming->>'stripeConnectionId' IS DISTINCT FROM connections->>'stripe' THEN RAISE EXCEPTION 'PAYMENT_RECIPIENT_CONFLICT'; END IF;
 ELSE
  -- A present legacy object owns Stripe only. Removing it never unbinds another provider.
  connections:=connections-'stripe';
  IF incoming->>'stripeConnectionId' IS NOT NULL THEN connections:=connections||jsonb_build_object('stripe',incoming->>'stripeConnectionId'); END IF;
 END IF;
 FOR r IN SELECT * FROM jsonb_each(connections) LOOP
  IF jsonb_typeof(r.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=r.key AND handler IS NOT NULL) THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  PERFORM (r.value#>>'{}')::uuid;
 END LOOP;
 RETURN jsonb_build_object('bankEnabled',coalesce(incoming->'bankEnabled',saved->'bankEnabled'),'providerConnections',connections);
END $$;
-- Legacy draft translation uses saved recipient evidence, never a registry default.
CREATE OR REPLACE FUNCTION public.normalize_setup_payments_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE config jsonb; method text:=p_data->>'paymentMethod'; result jsonb:=p_data-'paymentMethod'; connections jsonb;
BEGIN
 config:=public.merge_form_payments_internal(coalesce(p_data->'payments',p_data#>'{formDraft,data,payments}'),NULL);
 IF method IS NOT NULL THEN
  IF method='bank' THEN config:='{"bankEnabled":true,"providerConnections":{}}';
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
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE handler IS NOT NULL ORDER BY provider_key LOOP
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
RESET ROLE;

-- SOURCE: payment_providers/registry.sql
SET LOCAL ROLE postgres;
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
CREATE OR REPLACE FUNCTION public.strip_payment_sources_internal(p_input jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_input-coalesce((SELECT array_agg(source_field) FROM eshop.payment_providers WHERE source_field IS NOT NULL),'{}'::text[]);
$$;
CREATE OR REPLACE FUNCTION public.provider_order_payment_projection_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE method text; result jsonb;
BEGIN
 SELECT p.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
 IF method IS NULL OR method='bank' THEN RETURN NULL; END IF;
 result:=public.payment_provider_call_internal(method,'projection',jsonb_build_object('orderId',p_order));
 IF result->>'method' IS DISTINCT FROM method THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_IDENTITY_MISMATCH'; END IF;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.attach_provider_order_source_internal(p_order bigint,p_command uuid,p_input jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE method text; field text;
BEGIN
 SELECT p.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
 IF method IS NULL OR method='bank' THEN RETURN; END IF;
 SELECT source_field INTO STRICT field FROM eshop.payment_providers WHERE provider_key=method;
 PERFORM public.payment_provider_call_internal(method,'attach_source',jsonb_build_object('orderId',p_order,'commandId',p_command,'source',p_input->field));
END $$;
CREATE OR REPLACE FUNCTION public.provider_ticket_requires_online_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
 JOIN eshop.payment_info p ON p.id=o.payment_info WHERE x.ticket=p_ticket AND p.payment_method<>'bank');
$$;
CREATE OR REPLACE FUNCTION public.provider_ticket_admission_allowed_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
 JOIN eshop.payment_info p ON p.id=o.payment_info WHERE x.ticket=p_ticket AND p.payment_method<>'bank'
 AND public.provider_order_payment_projection_internal(o.id)->>'admissionState' IS DISTINCT FROM 'valid');
$$;
CREATE OR REPLACE FUNCTION public.provider_paid_guard_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE method text;
BEGIN
 SELECT p.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
 IF method IS NULL OR method='bank' THEN RETURN NULL; END IF;
 RETURN public.payment_provider_call_internal(method,'paid_guard',jsonb_build_object('orderId',p_order));
END $$;
CREATE OR REPLACE FUNCTION public.provider_payment_movements_internal(p_payment bigint)
RETURNS TABLE(kind text,amount_minor bigint,currency text,occurred_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE method text; rows jsonb;
BEGIN
 SELECT p.payment_method INTO method FROM eshop.payment_info p WHERE p.id=p_payment;
 IF method IS NULL OR method='bank' THEN RETURN; END IF;
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
DECLARE r record; current jsonb; providers jsonb:='{}'; available jsonb:='[]'; config jsonb; bank boolean; configured boolean; enabled boolean;
BEGIN
 SELECT data->'payments' INTO config FROM public.forms WHERE id=p_form;
 bank:=FOUND AND coalesce(config->'bankEnabled','true'::jsonb)='true'::jsonb;
 IF bank THEN available:=jsonb_build_array('bank'); END IF;
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
 RETURN jsonb_build_object('bank',jsonb_build_object('configured',bank,'available',bank),'available',available,'providers',providers,
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
  WHERE k NOT IN ('bankEnabled','providerConnections') AND NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE legacy_connection_field=k))
  OR (config ? 'bankEnabled' AND jsonb_typeof(config->'bankEnabled')<>'boolean') THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 connections:=coalesce(config->'providerConnections','{}'::jsonb);
 IF jsonb_typeof(connections)<>'object' THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 FOR entry IN SELECT * FROM jsonb_each(connections) LOOP
  IF jsonb_typeof(entry.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=entry.key AND handler IS NOT NULL) THEN
   RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  PERFORM (entry.value#>>'{}')::uuid;
 END LOOP;
 IF config->'bankEnabled'='false'::jsonb
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
RESET ROLE;

-- SOURCE: payment_providers/financial_facts.sql
SET LOCAL ROLE postgres;
CREATE OR REPLACE FUNCTION public.provider_financial_totals_internal(p_provider text,p_payment bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE facts jsonb; k text;
BEGIN
 facts:=public.payment_provider_call_internal(p_provider,'totals',jsonb_build_object('paymentId',p_payment));
 IF facts IS NULL OR jsonb_typeof(facts)<>'object' OR NOT facts ?& ARRAY['received','returned','held','invalid']
  OR jsonb_typeof(facts->'invalid') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'PAYMENT_FINANCIAL_FACTS_INCOMPLETE'; END IF;
 FOREACH k IN ARRAY ARRAY['received','returned','held'] LOOP
  IF jsonb_typeof(facts->k) IS DISTINCT FROM 'number' OR (facts->>k)::numeric<0
   OR (facts->>k)::numeric*100<>trunc((facts->>k)::numeric*100) THEN RAISE EXCEPTION 'PAYMENT_FINANCIAL_FACTS_INVALID'; END IF;
 END LOOP;
 IF (facts->>'returned')::numeric>(facts->>'received')::numeric THEN RAISE EXCEPTION 'PAYMENT_FINANCIAL_FACTS_INVALID'; END IF;
 RETURN facts;
END $$;
REVOKE ALL ON FUNCTION public.provider_financial_totals_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
RESET ROLE;

-- SOURCE: eshop_transactions/payment_totals.sql
-- One financial projection over actual ledgers. External/manual settlement is
-- retained as its own fact; disputes are an availability hold, never a refund.
CREATE OR REPLACE FUNCTION public.payment_financial_totals_internal(p_payment bigint)
RETURNS TABLE(gross_received numeric,refunded numeric,external_received numeric,
 disputed numeric,net_received numeric,available numeric,invalid_identity boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH p AS (SELECT * FROM eshop.payment_info WHERE id=p_payment),
 bank AS (SELECT
  coalesce(sum(t.amount) FILTER(WHERE t.transaction_type IS DISTINCT FROM 'return'),0) received,
  abs(coalesce(sum(t.amount) FILTER(WHERE t.transaction_type='return'),0)) returned,
  coalesce(bool_or(t.currency IS DISTINCT FROM p.currency_code),false) invalid
  FROM p JOIN eshop.transactions t ON t.payment_info=p.id),
 provider_raw AS (SELECT CASE WHEN payment_method='bank' THEN '{}'::jsonb
   ELSE public.provider_financial_totals_internal(payment_method,id) END facts FROM p),
 provider AS (SELECT coalesce((facts->>'received')::numeric,0) received,
  coalesce((facts->>'returned')::numeric,0) returned,coalesce((facts->>'invalid')::boolean,false) invalid FROM provider_raw),
 holds AS (SELECT coalesce((facts->>'held')::numeric,0) held FROM provider_raw),
 totals AS (SELECT bank.received+provider.received gross,bank.returned+provider.returned returned,
  coalesce(p.paid_externally,0) external,holds.held,bank.invalid OR provider.invalid invalid
  FROM p CROSS JOIN bank CROSS JOIN provider CROSS JOIN holds)
 -- The legacy external field has no attributable movement identity/date.
 -- Preserve it explicitly, without guessing whether it overlaps stored paid.
 SELECT gross,returned,external,held,gross-returned,
  greatest(gross-returned-held,0),invalid FROM totals;
$$;
REVOKE ALL ON FUNCTION public.payment_financial_totals_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.refresh_payment_info_totals_internal(p_payment bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE totals record;
BEGIN
 PERFORM 1 FROM eshop.payment_info WHERE id=p_payment FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_INFO_NOT_FOUND'; END IF;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(p_payment);
 IF totals.invalid_identity THEN RAISE EXCEPTION 'PAYMENT_FACT_IDENTITY_MISMATCH'; END IF;
 UPDATE eshop.payment_info SET paid=totals.gross_received,returned=totals.refunded WHERE id=p_payment;
 -- paid_externally is deliberately not rewritten or converted into a bank movement.
END $$;
REVOKE ALL ON FUNCTION public.refresh_payment_info_totals_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_stripe/form_availability.sql
SET LOCAL ROLE postgres;
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
 bank:=coalesce(config->'bankEnabled','true'::jsonb)='true'::jsonb;
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
RESET ROLE;

-- SOURCE: eshop_stripe/provider.sql
SET LOCAL ROLE postgres;
-- Stripe is one connector. All Stripe storage/identity and price restrictions
-- remain here; the order lifecycle dispatches through the common registry.
CREATE OR REPLACE FUNCTION public.stripe_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE input jsonb; connection uuid; payment_id bigint; attempt uuid; expires timestamptz;
 amount numeric; currency text; target bigint; result jsonb;
BEGIN
 target:=(p_args->>'orderId')::bigint;
 IF p_operation='projection' THEN RETURN public.stripe_order_payment_projection_internal(target);
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
  SELECT coalesce(jsonb_agg(jsonb_build_object('kind',m.kind,'amount_minor',m.amount_minor,'currency',m.currency,'occurred_at',m.occurred_at)),'[]') INTO result
   FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id WHERE a.payment_info_id=(p_args->>'paymentId')::bigint;
  RETURN result;
 END IF;
 RAISE EXCEPTION 'PAYMENT_PROVIDER_OPERATION_UNSUPPORTED';
END $$;
REVOKE ALL ON FUNCTION public.stripe_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.payment_info'::regclass AND conname='payment_info_stripe_connection_identity') THEN
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_stripe_connection_identity CHECK(
 (payment_method='stripe')=(stripe_connection_id IS NOT NULL)); END IF; END $$;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,legacy_connection_field)
 VALUES('stripe','public.stripe_payment_provider_internal(text,jsonb)'::regprocedure,'stripePaymentSource','stripeConnectionId') ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,source_field=excluded.source_field,legacy_connection_field=excluded.legacy_connection_field;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.payment_info'::regclass AND conname='payment_info_registered_method') THEN
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_registered_method
 FOREIGN KEY(payment_method) REFERENCES eshop.payment_providers(provider_key); END IF; END $$;
RESET ROLE;

-- SOURCE: eshop_stripe/connections.sql
SET LOCAL ROLE postgres;
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
 IF NOT public.stripe_unit_feature_enabled_internal(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='STRIPE_FEATURE_DISABLED'; END IF;
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
    AND public.payment_provider_connection_internal(form.data->'payments','stripe')=current_connection ORDER BY form.occasion LOOP
   mutation:=substr(encode(extensions.digest(f.id::text||':forms:'||occasion_scope::text,'sha256'),'hex'),1,32)::uuid;
   PERFORM public.begin_anonymous_client_mutation_v1(mutation,'inventory.form.stripe_recipient',occasion_scope,mutation,
    encode(extensions.digest(f.id::text||':'||c.id::text||':'||occasion_scope::text,'sha256'),'hex'));
   SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO members FROM public.occasion_users ou WHERE ou.occasion=occasion_scope;
   WITH updated AS (
    UPDATE public.forms SET data=jsonb_set(data,'{payments}',public.merge_form_payments_internal(data->'payments',NULL)||jsonb_build_object('providerConnections',
      coalesce(public.merge_form_payments_internal(data->'payments',NULL)->'providerConnections','{}')||jsonb_build_object('stripe',c.id))),updated_at=clock_timestamp()
     WHERE occasion=occasion_scope AND public.payment_provider_connection_internal(data->'payments','stripe')=current_connection RETURNING id
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
RESET ROLE;

-- SOURCE: payment_providers/effects.sql
SET LOCAL ROLE postgres;
-- Lock order: capacity/form scope -> order -> payment -> provider attempt -> tickets.
-- All facts are read back from connector storage. No caller-supplied markPaid/amount.
CREATE OR REPLACE FUNCTION public.apply_provider_payment_effects_internal(
 p_provider text,p_attempt uuid,p_revision text,p_before jsonb,p_expired boolean DEFAULT false,
 p_unresolved boolean DEFAULT false,p_action text DEFAULT 'observe',p_tickets bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE context jsonb; prior jsonb; o eshop.orders; pi eshop.payment_info; totals record; projection jsonb; transition jsonb;
 received numeric; refunded numeric; payment_time timestamptz; deadline timestamptz; cancelled bigint[];
 conflict boolean; action_required boolean; changed boolean:=false; args jsonb:=jsonb_build_object('attemptId',p_attempt); decision jsonb;
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
   SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t WHERE coalesce(t.state,'') NOT IN ('used','storno');
   PERFORM public.internal_storno_tickets_221(cancelled);
   PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','full_refund','revision',p_revision,'tickets',to_jsonb(coalesce(cancelled,'{}'))));
   UPDATE eshop.orders SET state='storno',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   PERFORM public.cancel_order_email_intents(o.id);changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND (p_expired OR (p_unresolved AND deadline<=clock_timestamp())) AND o.state='ordered' THEN
  SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t WHERE coalesce(t.state,'') NOT IN ('used','storno');
  PERFORM public.internal_storno_tickets_221(cancelled);
  UPDATE eshop.orders SET state='expired',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
  -- Releasing inventory does not prove financial absence. Keep uncertain recovery alive.
  IF NOT p_unresolved THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"expired"}'); END IF;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
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
 RETURN jsonb_build_object('changed',changed,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.apply_provider_payment_effects_internal(text,uuid,text,jsonb,boolean,boolean,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;
RESET ROLE;

-- SOURCE: eshop_stripe/admission.sql
SET LOCAL ROLE postgres;
-- Used by every server-side admission writer. Bank tickets retain their current
-- configured online/offline policy; card tickets require a current SQL decision.
CREATE OR REPLACE FUNCTION public.stripe_ticket_requires_online_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.provider_ticket_requires_online_internal(p_ticket);
$$;
CREATE OR REPLACE FUNCTION public.stripe_ticket_admission_allowed_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.provider_ticket_admission_allowed_internal(p_ticket);
$$;
REVOKE ALL ON FUNCTION public.stripe_ticket_requires_online_internal(bigint),public.stripe_ticket_admission_allowed_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
RESET ROLE;

-- SOURCE: eshop_stripe/ingest.sql
SET LOCAL ROLE postgres;
-- Sole provider-to-domain write boundary. Raw signature verification and current
-- account-scoped provider reads happen in Edge; every effect below commits once.
CREATE OR REPLACE FUNCTION public.ingest_stripe_payment_internal(
 p_attempt uuid,p_lease uuid,p_event jsonb,p_facts jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; c eshop.stripe_connections; o eshop.orders; pi eshop.payment_info;
 existing eshop.stripe_event_inbox; movement eshop.stripe_payment_movements; d eshop.stripe_disputes;
 fact jsonb; totals record; before_projection jsonb; projection jsonb; v_receipt jsonb; transition jsonb;
 command uuid; input_hash text; mutation_claim jsonb; before_users uuid[]; cancelled bigint[]; payment_time timestamptz;
 card_received numeric; card_refunded numeric; financial_conflict boolean;
 changed boolean:=false; observed timestamptz:=(p_facts->>'observedAt')::timestamptz;
 no_session boolean:=coalesce(p_facts->'noSessionVerified'='true'::jsonb,false);
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 IF p_event->>'id' IS NULL OR p_event->>'id' !~ '^evt_[A-Za-z0-9]+$'
  OR p_event->>'bodyHash' IS NULL OR p_event->>'bodyHash' !~ '^[a-f0-9]{64}$'
  OR p_event->>'accountId' IS DISTINCT FROM c.account_id OR (p_event->>'livemode')::boolean IS DISTINCT FROM a.livemode
  OR nullif(p_event->>'type','') IS NULL OR length(p_event->>'type')>100 THEN RAISE EXCEPTION 'STRIPE_EVENT_IDENTITY_INVALID'; END IF;
 SELECT * INTO existing FROM eshop.stripe_event_inbox WHERE connection_id=c.id AND event_id=p_event->>'id';
 IF FOUND THEN
  IF existing.body_sha256<>p_event->>'bodyHash' OR existing.receipt IS NULL THEN RAISE EXCEPTION 'STRIPE_EVENT_RECEIPT_INVALID'; END IF;
  RETURN existing.receipt;
 END IF;
 command:=(substr(encode(extensions.digest(c.id::text||':'||(p_event->>'id'),'sha256'),'hex'),1,32))::uuid;
 -- Event body identity is immutable; a replay may have newer provider reads.
 input_hash:=encode(extensions.digest(p_event::text,'sha256'),'hex');
 mutation_claim:=public.begin_anonymous_client_mutation_v1(command,'inventory.order.stripe_sync',
  (SELECT occasion FROM eshop.orders WHERE id=a.order_id),command,input_hash);
 IF mutation_claim->>'disposition'='replay' THEN RETURN mutation_claim->'response'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR a.lease_token IS NULL OR a.lease_expires_at IS NULL OR a.lease_token IS DISTINCT FROM p_lease OR a.lease_expires_at<=clock_timestamp()
  OR observed IS NULL OR observed>clock_timestamp()+interval '1 minute'
  OR observed<coalesce(a.last_synced_at,'-infinity') THEN RAISE EXCEPTION 'STRIPE_SYNC_LEASE_INVALID'; END IF;
 IF pi.id<>o.payment_info OR pi.payment_method<>'stripe' OR pi.stripe_connection_id<>c.id
  OR pi.amount*100<>a.amount_minor OR pi.currency_code<>a.currency
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=a.organization_id AND unit=a.unit_id)
  OR (NOT no_session AND (p_facts->>'sessionId' IS NULL OR p_facts->>'sessionId' !~ '^cs_[A-Za-z0-9_]+$'))
  OR (no_session AND (a.session_id IS NOT NULL OR a.session_lookup_found IS NOT NULL OR p_facts->>'sessionId' IS NOT NULL
   OR p_facts->>'paymentIntentId' IS NOT NULL OR p_facts->>'sessionStatus' IS DISTINCT FROM 'expired'
   OR a.reservation_expires_at>clock_timestamp()
   OR p_event->>'type' IS DISTINCT FROM 'festapp.reconcile' OR p_facts->'movements'<>'[]'::jsonb OR p_facts->'disputes'<>'[]'::jsonb))
  OR (a.session_id IS NOT NULL AND a.session_id<>p_facts->>'sessionId')
  OR (a.payment_intent_id IS NOT NULL AND a.payment_intent_id IS DISTINCT FROM p_facts->>'paymentIntentId')
  OR p_facts->>'sessionStatus' IS NULL OR p_facts->>'sessionStatus' NOT IN ('open','complete','expired')
  OR jsonb_typeof(p_facts->'movements') IS DISTINCT FROM 'array' OR jsonb_array_length(p_facts->'movements')>501
  OR jsonb_typeof(p_facts->'disputes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_facts->'disputes')>100 THEN
  RAISE EXCEPTION 'STRIPE_FACT_IDENTITY_INVALID'; END IF;
 IF p_facts->>'refundCursor' IS NOT NULL AND (p_facts->>'refundCursor' !~ '^re_[A-Za-z0-9]+$'
  OR p_facts->>'refundCursor'=a.refund_cursor) THEN RAISE EXCEPTION 'STRIPE_REFUND_CURSOR_INVALID'; END IF;
 before_projection:=public.stripe_order_payment_projection_internal(o.id);
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO before_users FROM public.occasion_users ou WHERE ou.occasion=o.occasion;
 INSERT INTO eshop.stripe_event_inbox(connection_id,event_id,body_sha256,event_type,provider_created_at)
 VALUES(c.id,p_event->>'id',p_event->>'bodyHash',p_event->>'type',to_timestamp((p_event->>'created')::bigint));
 FOR fact IN SELECT value FROM jsonb_array_elements(p_facts->'movements') LOOP
  IF fact->>'kind' IS NULL OR fact->>'kind' NOT IN ('payment','refund') OR fact->>'currency' IS DISTINCT FROM a.currency
   OR (fact->>'amountMinor')::numeric IS NULL OR (fact->>'amountMinor')::numeric<>trunc((fact->>'amountMinor')::numeric)
   OR (fact->>'amountMinor')::bigint NOT BETWEEN 1 AND a.amount_minor
   OR (fact->>'kind'='payment' AND (fact->>'providerId' IS DISTINCT FROM p_facts->>'paymentIntentId' OR fact->>'providerId' !~ '^pi_[A-Za-z0-9]+$' OR (fact->>'amountMinor')::bigint<>a.amount_minor))
   OR (fact->>'kind'='refund' AND (fact->>'providerId' IS NULL OR fact->>'providerId' !~ '^re_[A-Za-z0-9]+$'))
   OR (fact->>'occurredAt')::bigint IS NULL OR (fact->>'occurredAt')::bigint<0 THEN RAISE EXCEPTION 'STRIPE_MOVEMENT_INVALID'; END IF;
  SELECT * INTO movement FROM eshop.stripe_payment_movements WHERE connection_id=c.id AND provider_id=fact->>'providerId' AND kind=fact->>'kind';
  IF FOUND THEN
   IF movement.attempt_id<>a.id OR movement.amount_minor<>(fact->>'amountMinor')::bigint OR movement.currency<>a.currency
    OR movement.occurred_at<>to_timestamp((fact->>'occurredAt')::bigint) THEN RAISE EXCEPTION 'STRIPE_MOVEMENT_CHANGED'; END IF;
  ELSE
   INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
   VALUES(c.id,fact->>'providerId',a.id,fact->>'kind',(fact->>'amountMinor')::bigint,a.currency,to_timestamp((fact->>'occurredAt')::bigint));
   changed:=true;
  END IF;
 END LOOP;
 FOR fact IN SELECT value FROM jsonb_array_elements(p_facts->'disputes') LOOP
  IF fact->>'providerId' IS NULL OR fact->>'providerId' !~ '^(dp|du)_[A-Za-z0-9]+$'
   OR (fact->>'amountMinor') IS NULL OR (fact->>'amountMinor')::numeric<>trunc((fact->>'amountMinor')::numeric) OR (fact->>'amountMinor')::bigint NOT BETWEEN 1 AND a.amount_minor OR fact->>'currency' IS DISTINCT FROM a.currency
   OR fact->>'status' IS NULL OR fact->>'status' NOT IN ('warning_needs_response','warning_under_review','warning_closed','needs_response','under_review','won','lost') THEN
   RAISE EXCEPTION 'STRIPE_DISPUTE_INVALID'; END IF;
  SELECT * INTO d FROM eshop.stripe_disputes WHERE connection_id=c.id AND provider_id=fact->>'providerId';
  IF FOUND AND (d.attempt_id<>a.id OR d.amount_minor<>(fact->>'amountMinor')::bigint) THEN RAISE EXCEPTION 'STRIPE_DISPUTE_CHANGED'; END IF;
  IF d.status IS DISTINCT FROM fact->>'status' THEN changed:=true; END IF;
  INSERT INTO eshop.stripe_disputes(connection_id,provider_id,attempt_id,amount_minor,status,observed_at)
  VALUES(c.id,fact->>'providerId',a.id,(fact->>'amountMinor')::bigint,fact->>'status',observed)
  ON CONFLICT(connection_id,provider_id) DO UPDATE SET status=excluded.status,observed_at=excluded.observed_at;
 END LOOP;
 UPDATE eshop.stripe_checkout_attempts SET session_id=p_facts->>'sessionId',payment_intent_id=p_facts->>'paymentIntentId',refund_cursor=p_facts->>'refundCursor',
  session_lookup_cursor=NULL,session_lookup_found=NULL WHERE id=a.id;
 BEGIN
  transition:=public.apply_provider_payment_effects_internal('stripe',a.id,p_event->>'id',before_projection,p_facts->>'sessionStatus'='expired');
 EXCEPTION WHEN raise_exception THEN
  -- Retained service RPC diagnostic; domain behavior still has one owner.
  IF SQLERRM='PAYMENT_PAID_TRANSITION_FAILED' THEN RAISE EXCEPTION 'STRIPE_PAID_TRANSITION_FAILED'; END IF;
  RAISE;
 END;
 projection:=transition->'payment';changed:=changed OR (transition->>'changed')::boolean;
 UPDATE eshop.stripe_checkout_attempts SET last_synced_at=observed,lease_token=NULL,lease_expires_at=NULL,reconcile_failures=0,
  next_reconcile_at=clock_timestamp()+CASE WHEN refund_cursor IS NOT NULL THEN interval '10 seconds' WHEN state IN ('paid','action_required') THEN interval '1 day' ELSE interval '2 minutes' END WHERE id=a.id;
 v_receipt:=public.complete_profile_inventory_membership_mutation_v1(command,o.occasion,'inventory.order.stripe_sync',
  CASE WHEN changed THEN jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update',
   'safeLabel','Card payment update','changedFields',jsonb_build_array('payment','state','tickets','admission','allocations'))) ELSE '[]'::jsonb END,
  before_users,jsonb_build_object('committed',true,'payment',projection),'service');
 UPDATE eshop.stripe_event_inbox SET committed_at=clock_timestamp(),receipt=v_receipt WHERE connection_id=c.id AND event_id=p_event->>'id';
 PERFORM public.notification_center_order_state_internal(o.id);
 PERFORM public.notification_center_order_capacity_internal(o.id);
 RETURN v_receipt;
END $$;
REVOKE ALL ON FUNCTION public.ingest_stripe_payment_internal(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_stripe_payment_internal(uuid,uuid,jsonb,jsonb) TO service_role;
RESET ROLE;

-- SOURCE: eshop_stripe/refund_decisions.sql
SET LOCAL ROLE postgres;
CREATE OR REPLACE FUNCTION public.decide_stripe_partial_refund_client_sync_v1(
 p_order bigint,p_action text,p_tickets bigint[],p_note text,p_expected_refunded_minor bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); o eshop.orders; a eshop.stripe_checkout_attempts; totals record; v_occasion bigint;
 hash text; claim jsonb; ids bigint[]; before_users uuid[]; revision text; decision uuid; card_refunded bigint;
BEGIN
 SELECT ord.occasion INTO v_occasion FROM eshop.orders ord WHERE ord.id=p_order;
 IF actor IS NULL OR v_occasion IS NULL OR NOT coalesce(public.can_write_orders(v_occasion),false)
  OR NOT EXISTS(SELECT 1 FROM public.occasions occasion JOIN public.user_info viewer ON viewer.organization=occasion.organization AND viewer.id=actor WHERE occasion.id=v_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF p_action IS NULL OR p_action NOT IN ('keep','cancel_selected') OR p_command_id IS NULL
  OR nullif(trim(p_note),'') IS NULL OR length(trim(p_note)) NOT BETWEEN 3 AND 500
  OR p_expected_refunded_minor IS NULL THEN RAISE EXCEPTION 'STRIPE_REFUND_DECISION_INVALID'; END IF;
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(coalesce(p_tickets,'{}'::bigint[])) id ORDER BY id);
 IF (p_action='keep' AND cardinality(ids)<>0) OR (p_action='cancel_selected' AND cardinality(ids) NOT BETWEEN 1 AND 1000) THEN
  RAISE EXCEPTION 'STRIPE_REFUND_DECISION_INVALID'; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('order',p_order,'action',p_action,'tickets',ids,
  'note',trim(p_note),'refundedMinor',p_expected_refunded_minor)::text,'sha256'),'hex');
 claim:=public.begin_client_mutation_v1(p_command_id,'inventory.order.stripe_refund_decision',v_occasion,actor,hash);
 IF claim->>'disposition'='replay' THEN RETURN claim->'response'; END IF;
 PERFORM public.admit_order_mutation_v1(v_occasion,greatest(cardinality(ids),1));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=p_order ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(a.payment_info_id);
 SELECT coalesce(sum(amount_minor),0) INTO card_refunded FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 IF card_refunded IS DISTINCT FROM p_expected_refunded_minor THEN RAISE EXCEPTION 'STRIPE_REFUND_REVISION_CHANGED'; END IF;
 IF card_refunded<=0 OR card_refunded>=a.amount_minor OR a.state<>'paid' OR o.state NOT IN ('paid','sent')
  OR totals.invalid_identity OR a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=o.payment_info AND id=a.payment_info_id AND payment_method='stripe' AND stripe_connection_id=a.connection_id) THEN
  RAISE EXCEPTION 'STRIPE_PARTIAL_REFUND_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(ids) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id
  WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'STRIPE_REFUND_TICKET_UNAVAILABLE'; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO before_users FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
 SELECT encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_array(provider_id,amount_minor) ORDER BY provider_id)::text,'[]'),'sha256'),'hex')
 INTO revision FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 claim:=public.apply_provider_payment_effects_internal('stripe',a.id,revision,public.stripe_order_payment_projection_internal(o.id),false,false,p_action,ids);
 decision:=(claim->>'decisionId')::uuid;
 INSERT INTO eshop.orders_history("order",state,price,data) VALUES(o.id,o.state,o.price,jsonb_build_object('action','stripe_partial_refund_decision',
  'decisionId',decision,'actor',actor,'ticketIds',ids,'note',trim(p_note),'providerRevision',revision));
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,v_occasion,'inventory.order.stripe_refund_decision',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','safeLabel','Refund admission decision',
   'changedFields',jsonb_build_array('tickets','admission','allocations'))),before_users,
  jsonb_build_object('decisionId',decision,'payment',public.stripe_order_payment_projection_internal(o.id)));
END $$;
REVOKE ALL ON FUNCTION public.decide_stripe_partial_refund_client_sync_v1(bigint,text,bigint[],text,bigint,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.decide_stripe_partial_refund_client_sync_v1(bigint,text,bigint[],text,bigint,uuid) TO authenticated;
RESET ROLE;

-- SOURCE: eshop_stripe/order_creation.sql
SET LOCAL ROLE postgres;
-- A fixed 31-minute reservation leaves one minute to dispatch Stripe's minimum
-- 30-minute Session. Retries never extend it. Product acceptance is a pilot gate.
CREATE OR REPLACE FUNCTION public.create_stripe_order_attempt_internal(p_order bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; c eshop.stripe_connections; attempt uuid:=extensions.gen_random_uuid(); stamp timestamptz:=date_trunc('second',clock_timestamp());
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=pi.stripe_connection_id;
 IF pi.payment_method<>'stripe' OR pi.amount<=0 OR pi.amount<>o.price OR pi.currency_code<>o.currency_code
  OR pi.amount*100<>trunc(pi.amount*100) OR o.state<>'ordered' OR o.form IS NULL OR EXISTS(
   SELECT 1 FROM eshop.stripe_checkout_attempts WHERE order_id=o.id) THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 INSERT INTO eshop.stripe_checkout_attempts(id,order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,
  amount_minor,currency,order_revision,idempotency_key,created_at,reservation_expires_at,return_base_url,checkout_locale)
 VALUES(attempt,o.id,pi.id,c.organization_id,c.unit_id,c.id,c.livemode,
  (pi.amount*100)::bigint,pi.currency_code,1,'festapp:checkout:'||attempt,stamp,stamp+make_interval(secs=>(public.payment_sale_policy_internal()->>'reservationSeconds')::integer),
  (SELECT rtrim(data->>'DEFAULT_URL','/')||'/stripe/return' FROM public.organizations WHERE id=c.organization_id),
  (SELECT CASE WHEN data->>'DEFAULT_LANGUAGE' IN ('cs','en','de','pl','sk') THEN data->>'DEFAULT_LANGUAGE' ELSE 'en' END FROM public.organizations WHERE id=c.organization_id));
 UPDATE eshop.payment_info SET deadline=stamp+make_interval(secs=>(public.payment_sale_policy_internal()->>'reservationSeconds')::integer) WHERE id=pi.id;
 RETURN attempt;
END $$;
REVOKE ALL ON FUNCTION public.create_stripe_order_attempt_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Edge prepares random tokens and AES-GCM source using the existing email key.
-- Only hashes and the sealed source commit, in the same transaction as the order.
CREATE OR REPLACE FUNCTION public.attach_stripe_order_pay_source_internal(p_order bigint,p_command uuid,p_source jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; expiry timestamptz:=clock_timestamp()+interval '30 days';
BEGIN
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=p_order FOR UPDATE;
 IF p_command IS NULL OR p_source->>'tokenHash' IS NULL OR p_source->>'tokenHash' !~ '^[a-f0-9]{64}$'
  OR p_source->>'returnHash' IS NULL OR p_source->>'returnHash' !~ '^[a-f0-9]{64}$'
  OR p_source->>'tokenHash'=p_source->>'returnHash'
  OR p_source->>'contentHash' IS NULL OR p_source->>'contentHash' !~ '^[a-f0-9]{64}$'
  OR jsonb_typeof(p_source->'sealed') IS DISTINCT FROM 'object'
  OR p_source#>>'{sealed,v}' IS DISTINCT FROM '1'
  OR nullif(p_source#>>'{sealed,ciphertext}','') IS NULL OR nullif(p_source#>>'{sealed,iv}','') IS NULL THEN
  RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_REQUIRED'; END IF;
 INSERT INTO eshop.stripe_capabilities(token_hash,scope,order_id,attempt_id,expires_at)
 VALUES(p_source->>'tokenHash','order_pay',p_order,NULL,expiry),
  (p_source->>'returnHash','return_read',p_order,a.id,a.reservation_expires_at+interval '1 day');
 INSERT INTO eshop.stripe_payment_link_sources(token_hash,sealed,content_hash,expires_at,command_id)
 VALUES(p_source->>'tokenHash',p_source->'sealed',p_source->>'contentHash',expiry,p_command);
END $$;
REVOKE ALL ON FUNCTION public.attach_stripe_order_pay_source_internal(bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.stripe_order_payment_projection_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; a eshop.stripe_checkout_attempts; totals record; status text; admission text; delivery text; card_refunded numeric;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info AND payment_method='stripe';
 IF pi.id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1;
 SELECT * INTO totals FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount_minor),0)/100 INTO card_refunded FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 status:=CASE WHEN totals.disputed>0 THEN 'disputed'
  WHEN card_refunded>=a.amount_minor/100.0 THEN 'refunded'
  WHEN a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL THEN 'pending'
  WHEN a.state='action_required' OR (totals.gross_received>=pi.amount AND o.state NOT IN ('paid','sent')) THEN 'action_required'
  WHEN card_refunded>0 THEN 'partially_refunded'
  WHEN totals.gross_received>=pi.amount AND o.state IN ('paid','sent') THEN 'paid'
  WHEN a.state='uncertain' AND a.session_id IS NULL AND a.reservation_expires_at<=clock_timestamp() THEN 'pending'
  WHEN a.state='expired' OR a.reservation_expires_at<=clock_timestamp() OR o.state IN ('expired','storno') THEN 'expired'
  WHEN a.state IN ('uncertain','preparing') THEN 'preparing' ELSE 'open' END;
 admission:=CASE WHEN totals.disputed>0 OR status IN ('refunded','action_required') THEN 'hold'
  WHEN status IN ('paid','partially_refunded') AND o.state IN ('paid','sent') THEN 'valid' ELSE 'pending' END;
 SELECT CASE workflow_state WHEN 'accepted' THEN 'accepted' WHEN 'failed' THEN 'failed' WHEN 'suppressed' THEN 'suppressed' WHEN 'cancelled' THEN 'suppressed' ELSE 'pending' END INTO delivery
 FROM public.email_messages WHERE order_id=o.id AND message_kind='order_tickets' ORDER BY created_at DESC,id DESC LIMIT 1;
 RETURN jsonb_build_object('method','stripe','status',status,'amount',pi.amount::text,'received',totals.gross_received::numeric(30,2)::text,
  'returned',totals.refunded::numeric(30,2)::text,'currency',trim(pi.currency_code),'admissionState',admission,'deliveryState',coalesce(delivery,'not_requested'),
  'orderState',o.state,'reservationExpiresAt',a.reservation_expires_at,'serverNow',clock_timestamp(),
  'lastSyncedAt',a.last_synced_at,'reconciliationPending',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL OR (a.state='uncertain' AND a.session_id IS NULL),'reconciliationFailures',a.reconcile_failures,
  'allowedActions',CASE WHEN status IN ('open','preparing') AND NOT coalesce(a.lease_expires_at>clock_timestamp(),false) THEN jsonb_build_array('refresh','pay') ELSE jsonb_build_array('refresh') END);
END $$;
REVOKE ALL ON FUNCTION public.stripe_order_payment_projection_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_stripe_order_pay_source_internal(p_order bigint,p_command uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,
  'payment',public.stripe_order_payment_projection_internal(c.order_id),
  'payBaseUrl',(SELECT regexp_replace(return_base_url,'/stripe/return$','/stripe/pay') FROM eshop.stripe_checkout_attempts WHERE order_id=c.order_id ORDER BY created_at DESC LIMIT 1))
 INTO result FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities c USING(token_hash)
 WHERE s.command_id=p_command AND c.order_id=p_order AND c.scope='order_pay'
  AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp() AND s.expires_at=c.expires_at;
 IF result IS NULL THEN
  result:=jsonb_build_object('payment',public.stripe_order_payment_projection_internal(p_order));
  IF result#>>'{payment,method}' IS DISTINCT FROM 'stripe' OR result#>>'{payment,status}' IN ('open','preparing') THEN
   RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_order_pay_source_internal(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_stripe_order_pay_source_internal(bigint,uuid) TO service_role;
RESET ROLE;

-- SOURCE: eshop_stripe/reconciliation.sql
SET LOCAL ROLE postgres;
-- Machine-only recovery remains available with new sales disabled or the
-- connection retired. Claiming each job uses the same lease as webhooks/pay.
CREATE OR REPLACE FUNCTION public.get_recoverable_stripe_attempts_internal(p_livemode boolean,p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_livemode IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'STRIPE_RECOVERY_LIMIT_INVALID'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('attemptId',x.id,'accountId',x.account_id) ORDER BY x.next_reconcile_at,x.id),'[]'::jsonb)
 INTO result FROM (
  SELECT a.id,c.account_id,a.next_reconcile_at FROM eshop.stripe_checkout_attempts a
   JOIN eshop.stripe_connections c ON c.id=a.connection_id
   WHERE a.livemode=p_livemode AND a.next_reconcile_at<=statement_timestamp()
    AND coalesce(a.lease_expires_at<=statement_timestamp(),true)
   ORDER BY a.next_reconcile_at,a.id LIMIT p_limit
 ) x;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_recoverable_stripe_attempts_internal(boolean,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_recoverable_stripe_attempts_internal(boolean,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_stripe_reconciliation_internal(p_attempt uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 -- A stale worker cannot clear another worker's lease or reset its cursor.
 UPDATE eshop.stripe_checkout_attempts SET reconcile_failures=least(reconcile_failures+1,1000),
  next_reconcile_at=clock_timestamp()+make_interval(secs=>least(3600,30*power(2,least(reconcile_failures,7)))::integer),
  lease_token=NULL,lease_expires_at=NULL WHERE id=p_attempt AND lease_token=p_lease AND p_lease IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION public.fail_stripe_reconciliation_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fail_stripe_reconciliation_internal(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.checkpoint_stripe_session_lookup_internal(p_attempt uuid,p_lease uuid,p_cursor text,p_found text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts;
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT order_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt));
 PERFORM 1 FROM eshop.orders WHERE id=(SELECT order_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt) FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=(SELECT payment_info_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt) FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR p_lease IS DISTINCT FROM a.lease_token OR a.lease_expires_at<=clock_timestamp()
  OR a.session_id IS NOT NULL OR p_cursor IS NULL OR p_cursor !~ '^cs_[A-Za-z0-9_]+$' OR p_cursor=a.session_lookup_cursor
  OR (p_found IS NOT NULL AND p_found !~ '^cs_[A-Za-z0-9_]+$')
  OR (a.session_lookup_found IS NOT NULL AND a.session_lookup_found IS DISTINCT FROM p_found) THEN RAISE EXCEPTION 'STRIPE_SESSION_LOOKUP_INVALID'; END IF;
 IF a.reservation_expires_at<=clock_timestamp() THEN
  PERFORM public.defer_stripe_recovery_internal(p_attempt,p_lease,10);
 END IF;
 UPDATE eshop.stripe_checkout_attempts SET session_lookup_cursor=p_cursor,session_lookup_found=p_found,
  lease_token=NULL,lease_expires_at=NULL,reconcile_failures=0,next_reconcile_at=clock_timestamp()+interval '10 seconds' WHERE id=a.id;
END $$;
REVOKE ALL ON FUNCTION public.checkpoint_stripe_session_lookup_internal(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.checkpoint_stripe_session_lookup_internal(uuid,uuid,text,text) TO service_role;

-- Retain economic facts and capability hashes; erase only expired bearer sources.
-- Historical account-scoped reads deliberately do not depend on these secrets.
CREATE OR REPLACE FUNCTION public.purge_expired_stripe_sources_internal(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE removed integer;
BEGIN
 PERFORM public.require_service_role();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'STRIPE_RECOVERY_LIMIT_INVALID'; END IF;
 WITH expired AS (
  SELECT token_hash FROM eshop.stripe_payment_link_sources WHERE expires_at<=clock_timestamp()
   ORDER BY expires_at,token_hash LIMIT p_limit FOR UPDATE SKIP LOCKED
 ) DELETE FROM eshop.stripe_payment_link_sources s USING expired e WHERE s.token_hash=e.token_hash;
 GET DIAGNOSTICS removed=ROW_COUNT;
 RETURN removed;
END $$;
REVOKE ALL ON FUNCTION public.purge_expired_stripe_sources_internal(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_stripe_sources_internal(integer) TO service_role;

-- Uncertainty releases only elapsed inventory through the common domain owner.
-- No payment fact, absent checkout or successful remote expiry is manufactured.
CREATE OR REPLACE FUNCTION public.defer_stripe_recovery_internal(p_attempt uuid,p_lease uuid,p_retry_seconds integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; o eshop.orders; before_users uuid[]; before_projection jsonb; result jsonb;
 command uuid:=extensions.gen_random_uuid(); claim jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_retry_seconds IS NULL OR p_retry_seconds NOT BETWEEN 1 AND 3600 THEN RAISE EXCEPTION 'STRIPE_RECOVERY_LIMIT_INVALID'; END IF;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id;
 claim:=public.begin_anonymous_client_mutation_v1(command,'inventory.order.stripe_sync',o.occasion,command,
  encode(extensions.digest(p_attempt::text||p_lease::text,'sha256'),'hex'));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR a.lease_token IS DISTINCT FROM p_lease OR a.lease_expires_at IS NULL OR a.lease_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'STRIPE_SYNC_LEASE_INVALID'; END IF;

 SELECT coalesce(array_agg("user"),'{}'::uuid[]) INTO before_users FROM public.occasion_users WHERE occasion=o.occasion;
 before_projection:=public.stripe_order_payment_projection_internal(o.id);
 result:=public.apply_provider_payment_effects_internal('stripe',a.id,'unresolved:'||p_lease::text,before_projection,false,true);
 UPDATE eshop.stripe_checkout_attempts SET lease_token=NULL,lease_expires_at=NULL,
  reconcile_failures=least(reconcile_failures+1,1000),next_reconcile_at=clock_timestamp()+make_interval(secs=>greatest(p_retry_seconds,least(3600,30*power(2,least(reconcile_failures,7)))::integer)) WHERE id=a.id;
 PERFORM public.complete_profile_inventory_membership_mutation_v1(command,o.occasion,'inventory.order.stripe_sync',
  CASE WHEN result->'changed'='true'::jsonb THEN jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','safeLabel','Payment recovery','changedFields',jsonb_build_array('payment','state','tickets','admission','allocations'))) ELSE '[]'::jsonb END,
  before_users,jsonb_build_object('committed',true,'payment',result->'payment'),'service');
 PERFORM public.notification_center_order_state_internal(o.id);
 PERFORM public.notification_center_order_capacity_internal(o.id);
END $$;
REVOKE ALL ON FUNCTION public.defer_stripe_recovery_internal(uuid,uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.defer_stripe_recovery_internal(uuid,uuid,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.request_payment_reconciliation(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF p_project_url IS NULL OR p_project_url !~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$' THEN RAISE EXCEPTION 'PAYMENT_RECOVERY_ORIGIN_INVALID'; END IF;
 PERFORM net.http_post(url:=p_project_url||'/functions/v1/payment-reconcile',
  body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=90000);
END $$;
REVOKE ALL ON FUNCTION public.request_payment_reconciliation(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.request_payment_reconciliation(text) TO service_role;
-- Retained installed SQL callers use the same scheduler work, never a second job.
CREATE OR REPLACE FUNCTION public.request_stripe_reconciliation(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.request_payment_reconciliation(p_project_url);
END $$;

REVOKE ALL ON FUNCTION public.request_stripe_reconciliation(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.request_stripe_reconciliation(text) TO service_role;
RESET ROLE;

-- SOURCE: eshop_forms/form_settings.sql
-- Metadata patch owner for all administrative form settings. Private helpers;
-- authorization, locking, receipt and side effects stay in the form command.
CREATE OR REPLACE FUNCTION public.form_settings_keys_internal()
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT '{"is_reminder_enabled":null,"reminder_interval_seconds":null,"communication_tone":null,
 "variable_symbol":["type","starting_number"],"payment_message":["type"],
 "payments":["bankEnabled","stripeConnectionId","providerConnections"],
 "design":["embed_inherit_style","is_card_design","primary_color","secondary_color","background_mode","theme_mode","font_family","countdown_style"],
 "sale_opening_notifications":["enabled","collection_paused"],
 "schedule":["start_time","end_time","enable_countdown","show_before_start_message","before_start_message","countdown_title"]}'::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.normalize_form_metadata_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:='{}'; item jsonb; section jsonb; k text;
BEGIN
 IF p_data IS NULL OR p_data='null'::jsonb THEN RETURN result; END IF;
 IF jsonb_typeof(p_data)='object' THEN result:=p_data;
 ELSIF jsonb_typeof(p_data)='array' THEN
  -- Released readers already normalize historical [null,{metadata}] bundles.
  FOR item IN SELECT value FROM jsonb_array_elements(p_data) LOOP
   IF item='null'::jsonb THEN CONTINUE; END IF;
   IF jsonb_typeof(item)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form metadata'; END IF;
   result:=result||item;
  END LOOP;
 ELSE RAISE invalid_parameter_value USING MESSAGE='invalid form metadata';
 END IF;
 section:=coalesce(nullif(result->'schedule','null'::jsonb),'{}'::jsonb);
 IF jsonb_typeof(section)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form schedule'; END IF;
 FOREACH k IN ARRAY ARRAY['start_time','end_time'] LOOP
  -- Match the runtime reader's historical nested/root precedence, then retire
  -- the root alias. Otherwise clearing a nested override resurrects old dates.
  IF (NOT section ? k OR section->k='null'::jsonb) AND result ? k THEN
   section:=section||jsonb_build_object(k,result->k);
  END IF;
  result:=result-k;
  IF section->>k='' THEN section:=section-k;
  ELSIF section->>k IS NOT NULL AND (section->>k) !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' THEN
   -- Interpret released timestamps exactly as the existing runtime did. Emit
   -- an explicit instant for current editors; new patches still require ISO.
   section:=section||jsonb_build_object(k,(section->>k)::timestamptz);
  END IF;
 END LOOP;
 IF section='{}'::jsonb THEN result:=result-'schedule';
 ELSE result:=result||jsonb_build_object('schedule',section); END IF;
 RETURN result;
END $$;

-- Full released-client metadata is translated to the same known-settings patch.
CREATE OR REPLACE FUNCTION public.form_settings_from_metadata_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:='{}'; d jsonb:=public.normalize_form_metadata_internal(p_data); spec record; k text; section jsonb;
BEGIN
 FOR spec IN SELECT * FROM jsonb_each(public.form_settings_keys_internal()) LOOP
  IF spec.key IN ('payments','sale_opening_notifications') AND NOT d ? spec.key THEN CONTINUE; END IF;
  IF spec.value='null'::jsonb OR NOT d ? spec.key OR d->spec.key='null'::jsonb THEN
   result:=result||jsonb_build_object(spec.key,coalesce(d->spec.key,'null'::jsonb));
  ELSE
   IF spec.key='payments' THEN result:=result||jsonb_build_object(spec.key,d->spec.key); CONTINUE; END IF;
   IF jsonb_typeof(d->spec.key)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form settings section: '||spec.key; END IF;
   section:='{}';
   FOR k IN SELECT jsonb_array_elements_text(spec.value) LOOP
    section:=section||jsonb_build_object(k,coalesce(d->spec.key->k,'null'::jsonb));
   END LOOP;
   result:=result||jsonb_build_object(spec.key,section);
  END IF;
 END LOOP;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.apply_form_settings_internal(p_data jsonb,p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:=public.normalize_form_metadata_internal(p_data); spec jsonb:=public.form_settings_keys_internal();
 entry record; field record; section jsonb; v jsonb; k text; path text; n numeric; starts timestamptz; ends timestamptz;
BEGIN
 IF p_patch IS NULL OR jsonb_typeof(p_patch)<>'object' OR octet_length(p_patch::text)>131072 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid form settings patch'; END IF;
 FOR entry IN SELECT * FROM jsonb_each(p_patch) LOOP
  IF NOT spec ? entry.key THEN RAISE invalid_parameter_value USING MESSAGE='unsupported form setting: '||entry.key; END IF;
  IF spec->entry.key='null'::jsonb THEN
   IF entry.value='null'::jsonb THEN result:=result-entry.key; CONTINUE; END IF;
   IF entry.key='is_reminder_enabled' AND jsonb_typeof(entry.value)<>'boolean' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid reminder mode'; END IF;
   IF entry.key='reminder_interval_seconds' THEN
    IF jsonb_typeof(entry.value)<>'number' THEN RAISE invalid_parameter_value USING MESSAGE='invalid reminder interval'; END IF;
    n:=(entry.value::text)::numeric;
    IF n<>trunc(n) OR n<0 OR n>9007199254740991 THEN RAISE invalid_parameter_value USING MESSAGE='invalid reminder interval'; END IF;
   END IF;
   IF entry.key='communication_tone' AND entry.value NOT IN ('"formal"'::jsonb,'"informal"'::jsonb) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid communication tone'; END IF;
   result:=result||jsonb_build_object(entry.key,entry.value);
   CONTINUE;
  END IF;
  IF entry.value<>'null'::jsonb AND jsonb_typeof(entry.value)<>'object' THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid form settings section: '||entry.key; END IF;
  IF entry.key='payments' THEN
   result:=jsonb_set(result,'{payments}',public.merge_form_payments_internal(result->'payments',entry.value));
   CONTINUE;
  END IF;
  section:=coalesce(nullif(result->entry.key,'null'::jsonb),'{}'::jsonb);
  IF jsonb_typeof(section)<>'object' THEN section:='{}'; END IF;
  FOR field IN
   SELECT * FROM jsonb_each(CASE WHEN entry.value='null'::jsonb THEN
    (SELECT jsonb_object_agg(value,'null'::jsonb) FROM jsonb_array_elements_text(spec->entry.key)) ELSE entry.value END)
  LOOP
   k:=field.key;v:=field.value;path:=entry.key||'.'||k;
   IF NOT (spec->entry.key) ? k THEN RAISE invalid_parameter_value USING MESSAGE='unsupported form setting: '||path; END IF;
   IF v='null'::jsonb THEN section:=section-k;CONTINUE; END IF;
   IF path IN ('payments.bankEnabled','design.embed_inherit_style','design.is_card_design','schedule.enable_countdown','schedule.show_before_start_message','sale_opening_notifications.enabled','sale_opening_notifications.collection_paused') THEN
    IF jsonb_typeof(v)<>'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='invalid boolean setting: '||path; END IF;
   ELSIF path='payments.providerConnections' THEN
    IF jsonb_typeof(v)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid provider connections'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_each(v) x WHERE jsonb_typeof(x.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=x.key AND handler IS NOT NULL)) THEN
     RAISE invalid_parameter_value USING MESSAGE='unknown payment provider'; END IF;
    PERFORM (x.value#>>'{}')::uuid FROM jsonb_each(v) x;
   ELSIF path='variable_symbol.starting_number' THEN
    IF jsonb_typeof(v)<>'number' OR v::text !~ '^[0-9]{1,10}$' OR (v::text)::bigint NOT BETWEEN 1 AND 9999999999 THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid sequence starting number'; END IF;
   ELSE
    IF jsonb_typeof(v)<>'string' THEN RAISE invalid_parameter_value USING MESSAGE='invalid string setting: '||path; END IF;
    IF length(v#>>'{}')>(CASE WHEN path IN ('schedule.before_start_message','schedule.countdown_title') THEN 65536 ELSE 128 END) THEN
     RAISE invalid_parameter_value USING MESSAGE='form setting too long: '||path; END IF;
    IF path='variable_symbol.type' AND v NOT IN ('"random"'::jsonb,'"sequence"'::jsonb) OR
       path='payment_message.type' AND v NOT IN ('"name_surname"'::jsonb,'"none"'::jsonb,'"occasion_title"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid setting mode: '||path; END IF;
    IF path='design.theme_mode' AND v NOT IN ('"system"'::jsonb,'"light"'::jsonb,'"dark"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid form theme mode'; END IF;
    IF path='design.background_mode' AND v NOT IN ('"solid"'::jsonb,'"gradient"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid background mode'; END IF;
    IF path IN ('design.primary_color','design.secondary_color') AND (v#>>'{}') !~ '^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$' THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid design color'; END IF;
    IF path IN ('design.font_family','design.countdown_style') AND length(btrim(v#>>'{}'))=0 THEN
     RAISE invalid_parameter_value USING MESSAGE='empty design setting'; END IF;
    IF path='payments.stripeConnectionId' THEN PERFORM (v#>>'{}')::uuid; END IF;
    IF path IN ('schedule.start_time','schedule.end_time') THEN
     IF (v#>>'{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' THEN
      RAISE invalid_parameter_value USING MESSAGE='schedule requires an ISO instant with explicit timezone'; END IF;
     PERFORM (v#>>'{}')::timestamptz;
    END IF;
   END IF;
   section:=section||jsonb_build_object(k,v);
  END LOOP;
  -- Section reset removes only known authoring keys, preserving lifecycle flags
  -- (sale_preparation) and unrelated metadata owned by other contracts.
  IF section='{}'::jsonb THEN result:=result-entry.key;
  ELSE result:=result||jsonb_build_object(entry.key,section); END IF;
 END LOOP;
 IF p_patch ? 'variable_symbol' AND result#>>'{variable_symbol,type}'='sequence' AND
   (coalesce(result#>>'{variable_symbol,starting_number}','') !~ '^[0-9]{1,10}$' OR
    (result#>>'{variable_symbol,starting_number}')::bigint NOT BETWEEN 1 AND 9999999999) THEN
  RAISE invalid_parameter_value USING MESSAGE='sequence requires starting number'; END IF;
 IF p_patch ? 'schedule' THEN
  starts:=nullif(result#>>'{schedule,start_time}','')::timestamptz;
  ends:=nullif(result#>>'{schedule,end_time}','')::timestamptz;
  IF ends<starts THEN RAISE invalid_parameter_value USING MESSAGE='form sale end precedes start'; END IF;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.form_settings_keys_internal(),public.normalize_form_metadata_internal(jsonb),
 public.form_settings_from_metadata_internal(jsonb),public.apply_form_settings_internal(jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/update_form.sql
CREATE OR REPLACE FUNCTION public.update_form_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ----------------------------------------------------------------------------
    -- Declarations
    ----------------------------------------------------------------------------
    result JSONB;
    availability_at timestamptz;
    form_metadata jsonb;
    previous_form_metadata jsonb;
    availability_new boolean;
    deleted_fields BIGINT[];
    deleted_products BIGINT[];
    deletion_reason TEXT;
    deletion_row RECORD;
    protected_primary_types bigint[];

    form_id          BIGINT;               -- ID of the form being created/updated
    occasion_id      BIGINT;               -- ID of the occasion to which the form belongs
    now_ts           TIMESTAMPTZ := NOW(); -- Current timestamp for record updates

    link_param           TEXT;         -- Unique link for the form, must not conflict within the same org
    occasion_org         BIGINT;       -- Organization stored in the occasions table
    occasion_unit        BIGINT;       -- The 'unit' that must match for bank accounts
    conflict_check       INT;          -- Used for verifying uniqueness constraints
    deadline_val         BIGINT;       -- Field for validating form deadlines
    price_val            NUMERIC;      -- Field for validating product price

    bank_account_val     BIGINT;       -- Bank account from input_data
    bank_account_unit    BIGINT;       -- Unit of the bank account, must match occasion_unit

    v_seconds_before_deadline BIGINT; -- For calling the reminder queue function

    ----------------------------------------------------------------------------
    -- Since product_type data is now inside form_fields, we no longer read from
    -- a top-level product_types array. Instead, we will parse product_type objects
    -- directly from each form_field (if present).
    ----------------------------------------------------------------------------

    product_type_data    JSONB;        -- The JSONB data for product_type within a form_field
    product_type_id      BIGINT;       -- ID (new or existing) of the product_type
    product_type_occ     BIGINT;       -- For checking product_type's occasion

    products_data        JSONB;        -- JSONB array of products inside a product_type
    product_array_data   JSONB;        -- Rebuilt array of products
    product_data         JSONB;        -- Each product object from the products array
    product_id           BIGINT;       -- ID for a product (new or existing)
    product_occ          BIGINT;       -- Occasion check for an existing product

    ----------------------------------------------------------------------------
    -- form_fields data
    ----------------------------------------------------------------------------
    form_fields_data     JSONB := '[]'::JSONB; -- Final array of form_fields for the response
    field_data           JSONB;                -- Each form_field from input
    field_id             BIGINT;               -- ID for a form_field (new or existing)
    field_product_type   BIGINT;               -- Will store the final product_type.id for the form_field
    field_occ            BIGINT;               -- Verify product_type's occasion if referenced
BEGIN
    BEGIN
        /* All logic is inside this sub-block so we can catch exceptions similarly
           to how it's done in create_ticket_order, with a single EXCEPTION WHEN OTHERS THEN.
           We raise exceptions in JSON form, and if it's JSON, we return it as-is; otherwise,
           we build a default JSON error response. */

        ----------------------------------------------------------------------------
        -- Begin main logic


        ----------------------------------------------------------------------------

        -- Validate that input_data and essential fields exist
        IF input_data IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing')::TEXT;
        END IF;

        IF input_data->>'occasion' IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data')::TEXT;
        END IF;

        occasion_id := (input_data->>'occasion')::BIGINT;
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Invalid or missing occasion ID')::TEXT;
        END IF;

        -- Retrieve the occasion's organization and unit
        SELECT o.organization, o.unit
          INTO occasion_org, occasion_unit
          FROM public.occasions o
         WHERE o.id = occasion_id
         LIMIT 1;

        IF occasion_org IS NULL OR occasion_unit IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4017, 'message', 'Occasion not found or missing required fields')::TEXT;
        END IF;

        IF NOT public.is_service_role() AND NOT public.can_author_forms(occasion_id) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
        PERFORM public.notification_center_initialized_internal(occasion_org);
        PERFORM public.lock_blueprint_scope_internal(ARRAY[occasion_id]);
        availability_at:=clock_timestamp();
        form_id := NULLIF(input_data->>'id','')::bigint;
        availability_new:=form_id IS NULL;
        IF form_id IS NOT NULL THEN
          IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          PERFORM 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id FOR UPDATE;
          PERFORM public.notification_center_form_availability_internal(form_id,availability_at);
        END IF;
        IF form_id IS NULL THEN
          INSERT INTO public.forms(created_at,occasion) VALUES(now_ts,occasion_id) RETURNING id INTO form_id;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',true);
        ELSE
          IF NOT EXISTS (SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN
            RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',false);
        END IF;

        IF input_data ? 'settings' AND input_data ? 'data' THEN
          RAISE invalid_parameter_value USING MESSAGE='choose settings patch or released metadata, not both'; END IF;
        SELECT data INTO form_metadata FROM public.forms WHERE id=form_id;
        previous_form_metadata:=form_metadata;
        IF input_data ? 'settings' THEN
          form_metadata:=public.apply_form_settings_internal(form_metadata,input_data->'settings');
        ELSIF input_data ? 'data' THEN
          -- Released full-metadata boundary, same settings owner/validation.
          form_metadata:=public.normalize_form_metadata_internal(input_data->'data')
            ||CASE WHEN NOT public.normalize_form_metadata_internal(input_data->'data') ? 'sale_opening_notifications'
              AND public.normalize_form_metadata_internal(form_metadata) ? 'sale_opening_notifications'
              THEN jsonb_build_object('sale_opening_notifications',public.normalize_form_metadata_internal(form_metadata)->'sale_opening_notifications') ELSE '{}'::jsonb END;
          -- Released clients predate embed_inherit_style. Omission in their full
          -- metadata is not a request to reset a newer setting. An explicit null
          -- or boolean still goes through the one settings validator below.
          IF jsonb_typeof(coalesce(nullif(form_metadata->'design','null'::jsonb),'{}'::jsonb))='object'
            AND NOT coalesce(form_metadata->'design','{}'::jsonb) ? 'embed_inherit_style'
            AND public.normalize_form_metadata_internal(previous_form_metadata)#>'{design,embed_inherit_style}' IS NOT NULL THEN
            form_metadata:=jsonb_set(form_metadata,'{design}',
              coalesce(nullif(form_metadata->'design','null'::jsonb),'{}'::jsonb) ||
              jsonb_build_object('embed_inherit_style',public.normalize_form_metadata_internal(previous_form_metadata)#>'{design,embed_inherit_style}'));
          END IF;
          -- Full metadata from released clients owns only its bank/Stripe part.
          form_metadata:=jsonb_set(form_metadata,'{payments}',public.merge_form_payments_internal(
            previous_form_metadata->'payments',public.normalize_form_metadata_internal(input_data->'data')->'payments'));
          form_metadata:=public.apply_form_settings_internal(form_metadata,
            public.form_settings_from_metadata_internal(form_metadata));
        END IF;

        -- Explicit removals are part of this save transaction, never inferred from
        -- omitted fields in partial/older-client payloads. Exceptions roll back the save.
        SELECT coalesce(array_agg(DISTINCT pt.id),'{}'::bigint[]) INTO protected_primary_types
        FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
        WHERE ff.form=form_id AND pt.type='spot';
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_fields
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_field_ids', '[]'::jsonb));
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_products
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_product_ids', '[]'::jsonb));

        IF EXISTS (SELECT 1 FROM unnest(deleted_fields) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM public.form_fields ff WHERE ff.id = removed.id AND ff.form = form_id))
          OR EXISTS (SELECT 1 FROM unnest(deleted_products) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
            WHERE p.id = removed.id AND ff.form = form_id)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;

        -- Removing the ticket container also removes its nested fields.
        IF EXISTS (SELECT 1 FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields) AND ff.type = 'ticket') THEN
            SELECT deleted_fields || COALESCE(array_agg(ff.id), '{}'::bigint[]) INTO deleted_fields
            FROM public.form_fields ff WHERE ff.form = form_id AND ff.is_ticket_field;
        END IF;

        -- Serialize product-type references and product FK insertions before checking
        -- usage, including ON DELETE CASCADE inventory links.
        PERFORM 1 FROM eshop.product_types pt WHERE pt.id IN (
            SELECT ff.product_type FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
            UNION SELECT p.product_type FROM eshop.products p WHERE p.id = ANY(deleted_products)
        ) ORDER BY pt.id FOR UPDATE;
        SELECT deleted_products || COALESCE(array_agg(p.id), '{}'::bigint[]) INTO deleted_products
        FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
        WHERE ff.id = ANY(deleted_fields);
        PERFORM 1 FROM eshop.products p WHERE p.id = ANY(deleted_products) ORDER BY p.id FOR UPDATE;

        FOR deletion_row IN SELECT ff.* FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
        LOOP
            SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.data->'fields') = 'array' THEN o.data->'fields' ELSE '[]'::jsonb END) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
            WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
           OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form)) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END INTO deletion_reason
            FROM public.form_fields ff WHERE ff.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        FOR deletion_row IN SELECT p.* FROM eshop.products p WHERE p.id = ANY(deleted_products)
        LOOP
            SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END INTO deletion_reason
            FROM eshop.products p WHERE p.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f
            WHERE (f->>'id')::bigint = ANY(deleted_fields))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f,
            jsonb_array_elements(COALESCE(NULLIF(f->'product_type'->'products', 'null'::jsonb), '[]'::jsonb)) p
            WHERE (p->>'id')::bigint = ANY(deleted_products)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;
        DELETE FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields);
        DELETE FROM eshop.planned_changes WHERE subject_id=ANY(deleted_products) AND change_type IN('products.price','products.is_hidden') AND NOT applied;
        DELETE FROM eshop.products p WHERE p.id = ANY(deleted_products);
        DELETE FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion'
          AND scope_id=occasion_id AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(deleted_products) id));

        ----------------------------------------------------------------------------
        -- Process form_fields array from input_data if present
        -- Each form_field may contain a product_type object. If so, we insert/update
        -- the product_type and its products, then set the resulting product_type.id
        -- in the form_field.
        ----------------------------------------------------------------------------
        IF (input_data->'form_fields') IS NOT NULL THEN
            form_fields_data := '[]'::JSONB;

            FOR field_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'form_fields')
            LOOP
                IF field_data->>'type' IN ('select_one','select_many') THEN
                    IF jsonb_typeof(field_data#>'{data,options}') IS DISTINCT FROM 'array' THEN
                        RAISE EXCEPTION '%', jsonb_build_object('code', 422,
                            'message', 'FORM_SELECTION_OPTIONS_REQUIRED', 'fieldId', field_data->'id')::text;
                    END IF;
                    IF jsonb_array_length(field_data#>'{data,options}') = 0
                       OR EXISTS (SELECT 1 FROM jsonb_array_elements(field_data#>'{data,options}') option
                           WHERE jsonb_typeof(option->'value') IS DISTINCT FROM 'string'
                              OR btrim(option->>'value') = '') THEN
                        RAISE EXCEPTION '%', jsonb_build_object('code', 422,
                            'message', 'FORM_SELECTION_OPTIONS_REQUIRED', 'fieldId', field_data->'id')::text;
                    END IF;
                END IF;
                field_id := NULLIF(field_data->>'id', '')::BIGINT;
                IF field_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields WHERE id=field_id AND form=form_id) THEN
                  RAISE invalid_parameter_value USING MESSAGE='Foreign form field'; END IF;

                ----------------------------------------------------------------------------
                -- product_type logic now lives here, inside each form_field
                ----------------------------------------------------------------------------
                product_type_data := field_data->'product_type';  -- This is JSONB (could be null)
                IF field_data->>'type' = 'ticket' AND field_data#>>'{data,max_tickets}' IS NOT NULL THEN
                    IF (field_data#>>'{data,max_tickets}')::numeric < 1 OR
                       (field_data#>>'{data,max_tickets}')::numeric > public.ticket_order_limit() OR
                       trunc((field_data#>>'{data,max_tickets}')::numeric) <> (field_data#>>'{data,max_tickets}')::numeric THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 400,
                            'message', 'Invalid maximum tickets per order',
                            'limit', public.ticket_order_limit())::TEXT;
                    END IF;
                END IF;
                field_product_type := NULL;                        -- We'll store numeric ID here if we have a product_type

                IF field_data ? 'product_type_id' THEN
                    field_product_type := (field_data->>'product_type_id')::bigint;
                    IF field_product_type IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_types
                      WHERE id=field_product_type AND occasion=occasion_id) THEN
                      RAISE invalid_parameter_value USING MESSAGE='Foreign product type'; END IF;
                ELSIF product_type_data IS NOT NULL AND product_type_data::TEXT <> 'null' THEN
                    -- Attempt to parse the product_type.id if it exists
                    product_type_id := NULLIF(product_type_data->>'id', '')::BIGINT;

                    IF product_type_id IS NULL THEN
                        ----------------------------------------------------------------------------
                        -- New product_type
                        ----------------------------------------------------------------------------
                        INSERT INTO eshop.product_types (
                            created_at,
                            updated_at,
                            occasion,
                            title,
                            description,
                            type,
                            data
                        )
                        VALUES (
                            now_ts,
                            now_ts,
                            occasion_id,
                            product_type_data->>'title',
                            product_type_data->>'description',
                            product_type_data->>'type',
                            product_type_data->'data'
                        )
                        RETURNING id INTO product_type_id;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{id}',
                            TO_JSONB(product_type_id)
                        );
                    ELSE
                        ----------------------------------------------------------------------------
                        -- Existing product_type: check existence and occasion
                        ----------------------------------------------------------------------------
                        SELECT pt.occasion
                          INTO product_type_occ
                          FROM eshop.product_types pt
                         WHERE pt.id = product_type_id
                         LIMIT 1;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4006,
                                    'message', 'Product type not found',
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        IF product_type_occ <> occasion_id THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4007,
                                    'message', 'product_type occasion does not match form occasion',
                                    'product_type_occasion', product_type_occ,
                                    'form_occasion', occasion_id,
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        PERFORM 1 FROM public.occasions WHERE id=occasion_id FOR UPDATE;
                        UPDATE eshop.product_types
                           SET
                               updated_at = now_ts,
                               title = product_type_data->>'title',
                               description = product_type_data->>'description',
                               type = product_type_data->>'type',
                               data = product_type_data->'data'
                         WHERE id = product_type_id;
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Process products within this product_type, if any
                    ----------------------------------------------------------------------------
                    PERFORM public.advance_ticketing_authoring_version_internal_v1('product_type',occasion_id,product_type_id);
                    products_data := product_type_data->'products';
                    IF products_data IS NOT NULL AND products_data::TEXT <> 'null' THEN
                        product_array_data := '[]'::JSONB;

                        FOR product_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(products_data)
                        LOOP
                            product_id := NULLIF(product_data->>'id', '')::BIGINT;

                            -- Validate product price must be > 0
                            price_val := COALESCE(NULLIF(product_data->>'price',''), '0')::NUMERIC;
                            IF price_val < 0 THEN
                                RAISE EXCEPTION '%',
                                    JSONB_BUILD_OBJECT(
                                        'code', 4015,
                                        'message', 'Product price must be greater or equal to zero',
                                        'details', product_data
                                    )::TEXT;
                            END IF;

                            IF product_id IS NULL THEN
                                ----------------------------------------------------------------------------
                                -- New product
                                ----------------------------------------------------------------------------
                                PERFORM public.validate_product_price(price_val,product_data->'data',left(product_data->>'currency_code',3));
                                INSERT INTO eshop.products (
                                    created_at,
                                    updated_at,
                                    product_type,
                                    occasion,
                                    title,
                                    description,
                                    price,
                                    currency_code,
                                    data,
                                    is_hidden,
                                    "order",
                                    maximum
                                )
                                VALUES (
                                    now_ts,
                                    now_ts,
                                    product_type_id,
                                    occasion_id,
                                    product_data->>'title',
                                    product_data->>'description',
                                    price_val,
                                    left(product_data->>'currency_code', 3),
                                    product_data->'data',
                                    COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                    NULLIF(product_data->>'order','')::BIGINT,
                                    NULLIF(product_data->>'maximum','')::BIGINT
                                )
                                RETURNING id INTO product_id;

                                product_data := jsonb_set(product_data, '{id}', TO_JSONB(product_id));
                            ELSE
                                ----------------------------------------------------------------------------
                                -- Existing product: must match the same occasion and product_type
                                ----------------------------------------------------------------------------
                                SELECT p.occasion
                                  INTO product_occ
                                  FROM eshop.products p
                                 WHERE p.id = product_id
                                   AND p.product_type = product_type_id
                                 LIMIT 1;

                                IF NOT FOUND THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4008,
                                            'message', 'Product not found or does not match product_type',
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                IF product_occ <> occasion_id THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4009,
                                            'message', 'Product occasion does not match form occasion',
                                            'product_occasion', product_occ,
                                            'form_occasion', occasion_id,
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                PERFORM public.validate_product_price_update(product_id,price_val,product_data->'data',left(product_data->>'currency_code',3));
                                UPDATE eshop.products
                                   SET
                                       updated_at = now_ts,
                                       title = product_data->>'title',
                                       description = product_data->>'description',
                                       price = price_val,
                                       currency_code = left(product_data->>'currency_code', 3),
                                       data = product_data->'data',
                                       is_hidden = COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                       "order" = NULLIF(product_data->>'order','')::BIGINT,
                                       maximum = NULLIF(product_data->>'maximum','')::BIGINT
                                 WHERE id = product_id
                                   AND product_type = product_type_id;
                            END IF;

                            PERFORM public.advance_ticketing_authoring_version_internal_v1('product',occasion_id,product_id);
                            product_array_data := product_array_data || product_data;
                        END LOOP;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{products}',
                            product_array_data
                        );
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Store product_type_id in field_product_type for the form_fields table
                    ----------------------------------------------------------------------------
                    field_product_type := product_type_id;

                    ----------------------------------------------------------------------------
                    -- Merge updated product_type_data back into the field_data
                    ----------------------------------------------------------------------------
                    field_data := jsonb_set(field_data, '{product_type}', product_type_data);
                END IF;

                ----------------------------------------------------------------------------
                -- Insert or update the form_field itself
                ----------------------------------------------------------------------------
                IF field_id IS NOT NULL THEN
                    -- Update existing form_field
                    UPDATE public.form_fields
                       SET
                           title = field_data->>'title',
                           description = field_data->>'description',
                           data = CASE WHEN field_data ? 'data' THEN field_data->'data' ELSE data END,
                           type = field_data->>'type',
                           is_required = COALESCE((field_data->>'is_required')::BOOLEAN, false),
                           is_hidden = COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                           "order" = NULLIF(field_data->>'order','')::BIGINT,
                           product_type = CASE WHEN field_data ? 'product_type' OR field_data ? 'product_type_id' THEN field_product_type ELSE product_type END,
                           is_ticket_field = COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false),
                           form = form_id
                     WHERE id = field_id
                       AND form = form_id;

                    IF NOT FOUND THEN
                        RAISE EXCEPTION '%',
                            JSONB_BUILD_OBJECT(
                                'code', 4012,
                                'message', 'No matching form_field found to update (or does not belong to this form)',
                                'details', field_data
                            )::TEXT;
                    END IF;
                ELSE
                    -- Insert new form_field
                    INSERT INTO public.form_fields (
                        created_at,
                        title,
                        description,
                        data,
                        type,
                        is_required,
                        form,
                        is_hidden,
                        "order",
                        product_type,
                        is_ticket_field
                    )
                    VALUES (
                        now_ts,
                        field_data->>'title',
                        field_data->>'description',
                        field_data->'data',
                        field_data->>'type',
                        COALESCE((field_data->>'is_required')::BOOLEAN, false),
                        form_id,
                        COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                        NULLIF(field_data->>'order','')::BIGINT,
                        field_product_type,
                        COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false)
                    )
                    RETURNING id INTO field_id;

                    field_data := jsonb_set(field_data, '{id}', TO_JSONB(field_id));
                END IF;

                form_fields_data := form_fields_data || field_data;
            END LOOP;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate that deadline_duration_seconds is zero, positive, or null
        ----------------------------------------------------------------------------
        deadline_val := NULLIF(input_data->>'deadline_duration_seconds','')::BIGINT;
        IF deadline_val IS NOT NULL AND deadline_val < 0 THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT(
                    'code', 4016,
                    'message', 'deadline_duration_seconds must be zero or higher or null'
                )::TEXT;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate bank_account belongs to the same unit as the occasion, if provided
        ----------------------------------------------------------------------------
        bank_account_val := NULLIF(input_data->>'bank_account','')::BIGINT;
        IF bank_account_val IS NOT NULL THEN
            SELECT ba.unit
              INTO bank_account_unit
              FROM eshop.unit_bank_accounts ba
             WHERE ba.bank_account = bank_account_val
               AND ba.unit = occasion_unit
             LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4020,
                        'message', 'Bank account not found',
                        'bank_account', bank_account_val
                    )::TEXT;
            END IF;

            IF bank_account_unit <> occasion_unit THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4021,
                        'message', 'Bank account does not belong to the same unit as the occasion',
                        'bank_account_unit', bank_account_unit,
                        'occasion_unit', occasion_unit
                    )::TEXT;
            END IF;
        END IF;

        ----------------------------------------------------------------------------
        -- Update the main form record with all validated fields
        ----------------------------------------------------------------------------
        IF input_data->>'blueprint' IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM eshop.blueprints WHERE id=(input_data->>'blueprint')::bigint AND occasion=occasion_id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',403,'message','Foreign blueprint')::text; END IF;
        PERFORM public.check_form_capacity_settings_internal(form_id,input_data);
        UPDATE public.forms
           SET
               participant_capacity = CASE WHEN input_data ? 'participant_capacity' THEN (input_data->>'participant_capacity')::integer ELSE participant_capacity END,
               waitlist_enabled = CASE WHEN input_data ? 'waitlist_enabled' THEN (input_data->>'waitlist_enabled')::boolean ELSE waitlist_enabled END,
               show_remaining_capacity = CASE WHEN input_data ? 'show_remaining_capacity' THEN (input_data->>'show_remaining_capacity')::boolean ELSE show_remaining_capacity END,
               waitlist_offer_duration_seconds = CASE WHEN input_data ? 'waitlist_offer_duration_seconds' THEN (input_data->>'waitlist_offer_duration_seconds')::integer ELSE waitlist_offer_duration_seconds END,
               capacity_revision = capacity_revision+1,
               title = CASE WHEN input_data ? 'title' THEN input_data->>'title' ELSE title END,
               -- Opening the real form ends its initial preparation phase.
               -- Later closing it is a pause, irrespective of test orders.
               data = CASE WHEN coalesce((input_data->>'is_open')::boolean,is_open) THEN
                 jsonb_set(coalesce(form_metadata,'{}'::jsonb),'{schedule}',
                  coalesce((form_metadata)->'schedule','{}'::jsonb)
                   ||'{"sale_preparation":false}'::jsonb)
                 ELSE form_metadata END,
               header = CASE WHEN input_data ? 'header' THEN input_data->>'header' ELSE header END,
               header_off = CASE WHEN input_data ? 'header_off' THEN input_data->>'header_off' ELSE header_off END,
               link = link_param,
               blueprint = CASE WHEN input_data ? 'blueprint' THEN NULLIF(input_data->>'blueprint','')::BIGINT ELSE blueprint END,
               bank_account = CASE WHEN input_data ? 'bank_account' THEN bank_account_val ELSE bank_account END,
               deadline_duration_seconds = CASE WHEN input_data ? 'deadline_duration_seconds' THEN deadline_val ELSE deadline_duration_seconds END,
               is_open = CASE WHEN input_data ? 'is_open' THEN (input_data->>'is_open')::boolean ELSE is_open END
         WHERE id = form_id;

        IF input_data ? 'form_fields' OR cardinality(deleted_fields)>0 OR cardinality(deleted_products)>0 THEN
          PERFORM public.assert_form_primary_products_internal(form_id,protected_primary_types);
        END IF;
        PERFORM public.validate_form_payment_configuration_internal(form_id);

        ----------------------------------------------------------------------------
        -- After updating the form, requeue payment reminders for the whole occasion
        -- as the form's settings (e.g., is_reminder_enabled) might have changed.
        ----------------------------------------------------------------------------
        -- First, find the 'seconds_before_deadline' setting from the occasion's 'form' feature.
        SELECT (elem->>'reminder_interval_seconds')::BIGINT
          INTO v_seconds_before_deadline
          FROM public.occasions, jsonb_array_elements(features) AS elem
         WHERE id = occasion_id
           AND elem->>'code' = 'form'
         LIMIT 1;

        -- If the setting is found, call the function to rebuild the reminder queue.
        PERFORM public.queue_payment_reminders(occasion_id, COALESCE(v_seconds_before_deadline,86400));

        ----------------------------------------------------------------------------
        -- Prepare a success response
        ----------------------------------------------------------------------------
        PERFORM public.assert_form_seating_source_internal(form_id);
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'link', link_param,
            'form_fields', form_fields_data
        );

        PERFORM public.sync_sale_opening_settings_internal(form_id,previous_form_metadata);

        IF availability_new THEN
          PERFORM public.notification_center_form_created_internal(form_id);
        ELSE
          PERFORM public.notification_center_form_availability_internal(form_id,availability_at);
        END IF;
        PERFORM public.notification_center_form_capacity_internal(form_id);
    EXCEPTION WHEN raise_exception THEN
        -- Catch any exception and attempt to parse it as JSON; if not JSON, wrap it in our own JSON.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.update_form_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
    v_result:=public.update_form_internal_v1(p_form-'expected_aggregate_version'-'expected_product_versions'-'expected_product_type_versions');
    IF coalesce((v_result->>'code')::integer,500)<>200 THEN
      RAISE SQLSTATE 'P0F01' USING MESSAGE='authoring domain rejected'; END IF;
  EXCEPTION WHEN SQLSTATE 'P0F01' THEN NULL;
  END;
  IF coalesce((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer BETWEEN 100 AND 599 THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  v_form:=(v_result->>'form_id')::bigint;
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
        'paymentMethod',(SELECT CASE WHEN public.payment_method_registered_internal(data->>'DEFAULT_FORM_PAYMENT_METHOD') AND data->>'DEFAULT_FORM_PAYMENT_METHOD'<>'bank' THEN data->>'DEFAULT_FORM_PAYMENT_METHOD' END FROM public.organizations WHERE id=d.organization),
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
        'paymentMethod',(SELECT CASE WHEN public.payment_method_registered_internal(data->>'DEFAULT_FORM_PAYMENT_METHOD') AND data->>'DEFAULT_FORM_PAYMENT_METHOD'<>'bank' THEN data->>'DEFAULT_FORM_PAYMENT_METHOD' END FROM public.organizations WHERE id=d.organization),
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
 payment_method:=CASE WHEN payload#>'{payments,bankEnabled}'='false'::jsonb THEN 'online' ELSE 'bank' END;
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
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint'-'bank_account') || jsonb_build_object(
   'id',form_id,'occasion',new_id,'link',coalesce(form_link,(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',sale_mode<>'preparation','bank_account',selected_bank,'form_fields',fields));
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

-- SOURCE: payment_providers/configuration_upgrade.sql
UPDATE public.forms SET data=jsonb_set(data,'{payments}',public.merge_form_payments_internal(data->'payments',NULL))
 WHERE jsonb_typeof(data)='object' AND data ? 'payments';
UPDATE public.occasion_setup_drafts SET data=public.normalize_setup_payments_internal(data)
 WHERE NOT data ? 'finalizedOccasion';
