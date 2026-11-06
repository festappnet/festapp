-- Payment provider connectors. Forward-only; no provider activation or production application.

-- SOURCE: payment_providers/schema.sql
SET LOCAL ROLE postgres;
-- Installed connectors are migration-owned configuration, never client input.
CREATE TABLE eshop.payment_providers (
 provider_key text PRIMARY KEY CHECK(provider_key ~ '^[a-z][a-z0-9_-]{0,31}$'),
 handler regprocedure,
 source_field text UNIQUE,
 legacy_connection_field text UNIQUE,
 CHECK((provider_key='bank' AND handler IS NULL AND source_field IS NULL)
    OR (provider_key<>'bank' AND handler IS NOT NULL AND source_field IS NOT NULL))
);
ALTER TABLE eshop.payment_providers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.payment_providers FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key) VALUES('bank');
-- The existing Stripe connection column belongs to that connector. Other
-- connectors may have their own typed storage without changing payment_info.
ALTER TABLE eshop.payment_info DROP CONSTRAINT payment_info_payment_method_check;
ALTER TABLE eshop.payment_info DROP CONSTRAINT payment_info_stripe_identity;
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_provider_instructions CHECK(
 payment_method='bank' OR (bank_account IS NULL AND variable_symbol IS NULL
  AND creditor_reference IS NULL AND deposit_amount IS NULL));
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
DECLARE r record; result jsonb:='{}';
BEGIN
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE provider_key<>'bank' LOOP
  result:=result||jsonb_build_object(r.provider_key,public.payment_provider_call_internal(r.provider_key,'unit_feature',jsonb_build_object('unitId',p_unit)));
 END LOOP;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.provider_unit_public_fields_internal(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; result jsonb;
BEGIN
 result:=jsonb_build_object('payment_providers',public.provider_unit_features_internal(p_unit));
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE handler IS NOT NULL LOOP
  result:=result||public.payment_provider_call_internal(r.provider_key,'unit_fields',jsonb_build_object('unitId',p_unit));
 END LOOP;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.form_payment_availability_internal(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r record; current jsonb; result jsonb; providers jsonb:='{}'; available jsonb:='[]';
BEGIN
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE provider_key<>'bank' ORDER BY provider_key LOOP
  current:=public.payment_provider_call_internal(r.provider_key,'form_availability',jsonb_build_object('formId',p_form));
  IF result IS NULL THEN result:=current; END IF;
  providers:=providers||jsonb_build_object(r.provider_key,current);
  available:=available||coalesce(current->'available','[]');
 END LOOP;
 SELECT coalesce(jsonb_agg(value ORDER BY ordinal),'[]') INTO available FROM
  (SELECT value,min(ordinal) ordinal FROM jsonb_array_elements(available) WITH ORDINALITY x(value,ordinal) GROUP BY value) x;
 RETURN coalesce(result,jsonb_build_object('available','[]'::jsonb))||jsonb_build_object('available',available,'providers',providers);
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
DECLARE r record; result jsonb:='{}';
BEGIN
 FOR r IN SELECT provider_key FROM eshop.payment_providers WHERE provider_key<>'bank' LOOP
  result:=result||public.payment_provider_call_internal(r.provider_key,'form_editor_fields',jsonb_build_object('unitId',p_unit,'occasionId',p_occasion,'livemode',p_livemode));
 END LOOP;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.payment_provider_call_internal(text,text,jsonb),public.payment_method_registered_internal(text),
 public.strip_payment_sources_internal(jsonb),public.provider_order_payment_projection_internal(bigint),
 public.attach_provider_order_source_internal(bigint,uuid,jsonb),public.provider_ticket_requires_online_internal(bigint),
 public.provider_ticket_admission_allowed_internal(bigint),public.provider_paid_guard_internal(bigint),
 public.provider_payment_movements_internal(bigint),public.form_payment_availability_internal(bigint),
 public.payment_provider_connection_internal(jsonb,text),public.strip_form_payment_connections_internal(jsonb),
 public.provider_unit_public_fields_internal(bigint),public.provider_unit_features_internal(bigint),public.validate_form_payment_configuration_internal(bigint),public.provider_form_editor_fields_internal(bigint,bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
RESET ROLE;

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
  'available',methods,'stripeUnavailableReason',reason,'reservationSeconds',1860,
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
 ELSIF p_operation='unit_fields' THEN RETURN jsonb_build_object('stripe_preview_enabled',public.stripe_unit_feature_enabled_internal((p_args->>'unitId')::bigint));
 ELSIF p_operation='unit_feature' THEN RETURN to_jsonb(public.stripe_unit_feature_enabled_internal((p_args->>'unitId')::bigint));
 ELSIF p_operation='form_availability' THEN
  RETURN public.stripe_form_payment_availability_internal((p_args->>'formId')::bigint);
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
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_stripe_connection_identity CHECK(
 (payment_method='stripe')=(stripe_connection_id IS NOT NULL));
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,legacy_connection_field)
 VALUES('stripe','public.stripe_payment_provider_internal(text,jsonb)'::regprocedure,'stripePaymentSource','stripeConnectionId');
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_registered_method
 FOREIGN KEY(payment_method) REFERENCES eshop.payment_providers(provider_key);
RESET ROLE;

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
 -- Snapshot the tenant default only for new unlocalized domain intents. Existing
 -- messages, explicit locales and prepared/encrypted Auth content are untouched.
 IF NOT coalesce(p_data,'{}'::jsonb) ? 'lang' AND
    (p_kind LIKE 'order_%' OR p_kind IN ('waitlist_confirmation','waitlist_offer','sale_opening_opened')) AND
    (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=v_org)='en' THEN
   p_data:=coalesce(p_data,'{}'::jsonb)||'{"lang":"en"}'::jsonb;
 END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',p_data-'requested_by','code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
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
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.occasion_team_invitations i
   JOIN public.occasions o ON o.id=i.occasion AND o.unit=i.unit AND o.organization=i.organization
   JOIN public.unit_users uu ON uu.unit=i.unit AND uu."user"=i.created_by AND uu.is_manager
   WHERE i.message_id=p_message.message_id AND i.accepted_at IS NULL AND i.expires_at>now()
    AND i.email=p_message.recipient AND i.occasion=p_message.occasion AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
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
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND payment_method<>'bank')
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
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method<>'bank' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
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

-- SOURCE: eshop/confirm_blueprint_order_change.sql
CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_internal_v1(p_spot_ids bigint[],p_input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE analysis jsonb;details jsonb;tickets bigint[];occ bigint;
BEGIN
 PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id=ANY(p_spot_ids)));
 PERFORM public.check_blueprint_selection_units_internal(p_spot_ids);
 SELECT occasion INTO occ FROM eshop.spots WHERE id=p_spot_ids[1];
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(p_spot_ids) AND secret IS NOT NULL
  AND secret_expiration_time>clock_timestamp() AND secret IS DISTINCT FROM (p_input_data->>'secret')::uuid) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_PROTECTED'; END IF;
 analysis:=public.analyze_new_order_spots(p_spot_ids);
 details:=public.blueprint_order_input_internal(p_spot_ids,p_input_data,analysis);
 IF p_input_data->>'payment_method'<>'bank' OR EXISTS(
  SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
  JOIN eshop.orders o ON o.id=i."order" JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE s.id=ANY(p_spot_ids) AND p.payment_method<>'bank') THEN RAISE EXCEPTION 'STRIPE_REPLACEMENT_UNSUPPORTED'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT x."order" FROM eshop.spots s
  JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spot_ids)));
 PERFORM 1 FROM eshop.spots WHERE id=ANY(p_spot_ids) ORDER BY id FOR UPDATE;
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT x.ticket FROM eshop.spots s
  JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spot_ids)));
 SELECT array_agg((e->>'ticket_id')::bigint) INTO tickets FROM jsonb_array_elements(analysis->'conflicts') e
 WHERE e->>'ticket_id' IS NOT NULL;
 IF coalesce(cardinality(tickets),0)>0 THEN PERFORM public.storno_tickets_bulk_internal_v1(tickets); END IF;
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=ANY(p_spot_ids);
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 RETURN jsonb_build_object('success',true,'message','Storno performed. Ready to create new order.','orderDetails',details);
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('success',false,'message',SQLERRM);
END $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_internal_v1(bigint[],jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
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

        form_deadline_duration := COALESCE(form_deadline_duration,
            (SELECT (elem->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) elem WHERE elem->>'code'='form'),604800);

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

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

        v_payment_method:=coalesce(input_data->>'payment_method','bank');
        IF NOT public.payment_method_registered_internal(v_payment_method) THEN RAISE EXCEPTION 'PAYMENT_METHOD_INVALID'; END IF;
        IF calculated_price=0 THEN v_payment_method:='bank'; END IF;
        IF calculated_price=0 THEN
          bank_account_id:=NULL;
          INSERT INTO eshop.payment_info(amount,currency_code,created_at) VALUES(0,first_currency_code,now) RETURNING id INTO payment_info_id;
        ELSIF v_payment_method<>'bank' THEN
          v_provider_payment:=public.payment_provider_call_internal(v_payment_method,'initialize_payment',jsonb_build_object(
            'formId',form_id,'input',input_data,'amount',calculated_price,'currency',first_currency_code,'deposit',v_total_deposit,'createdAt',now));
          payment_info_id:=(v_provider_payment->>'paymentInfoId')::bigint;
          IF payment_info_id IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.payment_info provider_payment
            WHERE provider_payment.id=payment_info_id AND provider_payment.payment_method=v_payment_method
              AND provider_payment.amount=calculated_price AND provider_payment.currency_code=first_currency_code) THEN
            RAISE EXCEPTION 'PAYMENT_PROVIDER_PREPARATION_INVALID'; END IF;
          bank_account_id:=NULL;
        ELSE
          IF input_data->>'payment_type' = 'full' THEN v_total_deposit:=0; END IF;
          INSERT INTO eshop.payment_info(amount,deposit_amount,currency_code,created_at)
          VALUES(calculated_price,NULLIF(v_total_deposit,0),first_currency_code,now)
          RETURNING id INTO payment_info_id;


        END IF;

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

          -- NULL inherits the occasion default; zero is an explicit immediate deadline.
          form_deadline_duration := coalesce(form_deadline_duration,
            (SELECT (feature->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) feature WHERE feature->>'code'='form'),604800);
          -- Calculate deadline if deadline duration is provided
          IF v_payment_method<>'bank' THEN
              v_provider_payment:=public.payment_provider_call_internal(v_payment_method,'create_attempt',jsonb_build_object('orderId',order_id));
              deadline:=(v_provider_payment->>'expiresAt')::timestamptz;
              IF deadline IS NULL THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_DEADLINE_INVALID'; END IF;
          ELSIF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
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
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
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
            'payment',public.provider_order_payment_projection_internal(order_id),
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

-- SOURCE: eshop/get_report_ws.sql
CREATE OR REPLACE FUNCTION public.get_report_ws(occasion_link text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE r jsonb; invalid_payment boolean;
BEGIN
  WITH scope AS MATERIALIZED (
    SELECT o.id, o.title FROM public.occasions o
    JOIN public.user_info u ON u.organization = o.organization AND u.id = auth.uid()
    WHERE o.id = public.resolve_occasion_link_internal(occasion_link) AND public.can_read_orders(o.id)
  ), orders_scope AS MATERIALIZED (
    SELECT o.* FROM eshop.orders o JOIN scope s ON s.id = o.occasion WHERE o.state IS DISTINCT FROM 'stock'
  ), payments AS MATERIALIZED (
    SELECT p.* FROM eshop.payment_info p
    WHERE p.id IN (SELECT payment_info FROM orders_scope)
  ), invalid AS (
    SELECT EXISTS (SELECT 1 FROM payments p JOIN eshop.orders o ON o.payment_info = p.id
      WHERE o.occasion IS DISTINCT FROM (SELECT id FROM scope)
         OR o.currency_code IS DISTINCT FROM p.currency_code) AS value
  ), transactions_scope AS MATERIALIZED (
    SELECT t.* FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info
    WHERE t.currency=p.currency_code
  ), stripe_movements AS MATERIALIZED (
    SELECT m.*,p.id AS payment_info_id FROM payments p
    CROSS JOIN LATERAL public.provider_payment_movements_internal(p.id) m WHERE m.currency=p.currency_code::text
  ), financial_totals AS MATERIALIZED (
    SELECT p.id,t.* FROM payments p CROSS JOIN LATERAL public.payment_financial_totals_internal(p.id) t
  ), stripe_money AS (
    SELECT payment_info_id,(coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0)/100)::numeric(30,2) AS received,
     (coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0)/100)::numeric(30,2) AS returned
    FROM stripe_movements GROUP BY payment_info_id
  ), order_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,currency_code::text AS currency,count(*) AS count
    FROM orders_scope GROUP BY 1,2
  ), payment_days AS (
    SELECT day,currency,sum(received)::text AS received,sum(returned)::text AS returned FROM (
     SELECT date::date AS day,currency::text AS currency,
      coalesce(sum(amount) FILTER (WHERE amount>0),0) AS received,
      coalesce(-sum(amount) FILTER (WHERE amount<0),0) AS returned
      FROM transactions_scope GROUP BY 1,2
     UNION ALL
     SELECT (occurred_at AT TIME ZONE 'Europe/Prague')::date,currency,
      (coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0)/100)::numeric(30,2),
      (coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0)/100)::numeric(30,2) FROM stripe_movements GROUP BY 1,2
    ) facts GROUP BY day,currency
  ), manual AS (
    SELECT t.payment_info, sum(t.amount) FILTER (WHERE t.transaction_type = 'manual' AND t.amount > 0) AS received
    FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info GROUP BY t.payment_info
  ), order_money AS (
    SELECT currency_code AS currency, sum(coalesce(price,0)) AS value
    FROM orders_scope GROUP BY currency_code
  ), payment_money AS (
    SELECT p.currency_code AS currency, sum(coalesce(p.paid,0)) AS received,
      sum(coalesce(p.returned,0)) AS returned, sum(coalesce(m.received,0)) AS manual,
      sum(coalesce(sm.received,0)) AS stripe_received,sum(coalesce(sm.returned,0)) AS stripe_refunded,
      sum(coalesce(ft.disputed,0)) AS disputed,sum(coalesce(p.paid_externally,0)) AS external_unattributed,
      bool_or(p.deposit_amount IS NOT NULL) AS deposits,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN least(coalesce(p.paid,0),p.deposit_amount) ELSE 0 END) AS deposit,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN greatest(coalesce(p.paid,0)-p.deposit_amount,0) ELSE 0 END) AS beyond
    FROM payments p LEFT JOIN manual m ON m.payment_info=p.id LEFT JOIN stripe_money sm ON sm.payment_info_id=p.id
     LEFT JOIN financial_totals ft ON ft.id=p.id GROUP BY p.currency_code
  ), money AS (
    SELECT coalesce(o.currency,p.currency)::text AS currency, coalesce(o.value,0) AS value,
      coalesce(p.received,0) AS received, coalesce(p.returned,0) AS returned,
      coalesce(p.manual,0) AS manual, coalesce(p.deposits,false) AS deposits,
      coalesce(p.stripe_received,0) AS stripe_received,coalesce(p.stripe_refunded,0) AS stripe_refunded,
      coalesce(p.disputed,0) AS disputed,coalesce(p.external_unattributed,0) AS external_unattributed,
      coalesce(p.deposit,0) AS deposit, coalesce(p.beyond,0) AS beyond
    FROM order_money o FULL JOIN payment_money p USING(currency)
  ), ticket_scope AS (
    SELECT t.* FROM eshop.tickets t JOIN scope s ON s.id=t.occasion
    WHERE EXISTS (SELECT 1 FROM eshop.order_product_ticket i JOIN orders_scope o ON o.id=i."order" WHERE i.ticket=t.id)
  ), valid_orders AS MATERIALIZED (
    SELECT * FROM orders_scope WHERE state IS DISTINCT FROM 'storno' AND state IS DISTINCT FROM 'waitlisted'
  ), valid_tickets AS MATERIALIZED (
    SELECT t.* FROM ticket_scope t
    WHERE t.state IS DISTINCT FROM 'storno' AND EXISTS (
      SELECT 1 FROM eshop.order_product_ticket i JOIN valid_orders o ON o.id=i."order"
      WHERE i.ticket=t.id
    )
  ), valid_order_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,currency_code::text AS currency,count(*) AS count
    FROM valid_orders GROUP BY 1,2
  ), ticket_order_dates AS (
    SELECT DISTINCT ON (t.id) t.id,CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items b WHERE b.ticket_id=t.id AND b.sale_order_id=o.id) THEN o.created_at ELSE t.created_at END AS created_at,o.currency_code
    FROM ticket_scope t JOIN eshop.order_product_ticket i ON i.ticket=t.id
    JOIN orders_scope o ON o.id=i."order"
    ORDER BY t.id,o.created_at,o.id
  ), valid_ticket_order_dates AS (
    SELECT DISTINCT ON (t.id) t.id,CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items b WHERE b.ticket_id=t.id AND b.sale_order_id=o.id) THEN o.created_at ELSE t.created_at END AS created_at,o.currency_code
    FROM valid_tickets t JOIN eshop.order_product_ticket i ON i.ticket=t.id
    JOIN valid_orders o ON o.id=i."order"
    ORDER BY t.id,o.created_at,o.id
  ), ticket_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,
      currency_code::text AS currency,count(*) AS count
    FROM ticket_order_dates GROUP BY 1,2
  ), valid_ticket_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,
      currency_code::text AS currency,count(*) AS count
    FROM valid_ticket_order_dates GROUP BY 1,2
  ), order_states AS (
    SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM orders_scope GROUP BY 1
  ), ticket_states AS (
    SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM ticket_scope GROUP BY 1
  ), spots AS (
    SELECT count(*) AS total,count(*) FILTER (WHERE order_product_ticket IS NOT NULL) AS occupied,
      count(*) FILTER (WHERE order_product_ticket IS NULL) AS free
    FROM eshop.spots WHERE occasion IN (SELECT id FROM scope)
  ), products AS (
    SELECT p.id::text AS product_id,coalesce(p.title,'') AS product_title,
      pt.id::text AS type_id,pt.title AS type_title,count(*) AS confirmed_count
    FROM orders_scope o JOIN eshop.order_product_ticket i ON i."order"=o.id
    JOIN eshop.products p ON p.id=i.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
    WHERE o.state IN ('paid','sent','used') GROUP BY p.id,pt.id
  ), warnings AS (
    SELECT 'missing_order_price' AS code,count(*) AS count FROM orders_scope WHERE price IS NULL AND state IS DISTINCT FROM 'waitlisted' HAVING count(*)>0
    UNION ALL SELECT 'transaction_currency_mismatch',count(*) FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info WHERE t.currency<>p.currency_code HAVING count(*)>0
    UNION ALL SELECT 'negative_other_received',count(*) FROM money WHERE received-manual<0 HAVING count(*)>0
    UNION ALL SELECT 'external_unattributed',count(*) FROM payments WHERE coalesce(paid_externally,0)<>0 HAVING count(*)>0
    UNION ALL SELECT 'payment_total_without_ledger',count(*) FROM payments p JOIN financial_totals ft ON ft.id=p.id
     WHERE coalesce(p.paid,0)<>ft.gross_received OR coalesce(p.returned,0)<>ft.refunded HAVING count(*)>0
  )
  SELECT jsonb_build_object(
    'schema_version',1,'occasion',jsonb_build_object('id',s.id::text,'title',coalesce(s.title,'')),
    'generated_at',to_char(statement_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'spots',(SELECT to_jsonb(spots) FROM spots),
    'orders',jsonb_build_object('total',(SELECT count(*) FROM orders_scope),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM order_states x),'[]'::jsonb)),
    'tickets',jsonb_build_object('total',(SELECT count(*) FROM ticket_scope),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM ticket_states x),'[]'::jsonb)),
    'valid',jsonb_build_object(
      'orders',jsonb_build_object('total',(SELECT count(*) FROM valid_orders),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM (SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM valid_orders GROUP BY 1) x),'[]'::jsonb)),
      'tickets',jsonb_build_object('total',(SELECT count(*) FROM valid_tickets),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM (SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM valid_tickets GROUP BY 1) x),'[]'::jsonb)),
      'ticket_days',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM valid_ticket_days d),'[]'::jsonb),
      'order_days',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM valid_order_days d),'[]'::jsonb)
    ),
    'money_by_currency',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'currency',currency,'current_order_value',value::text,'received',received::text,'returned',returned::text,
      'net_received',(received-returned)::text,'manual_received',manual::text,'other_received',(received-manual)::text,
      'has_deposits',deposits,'deposit_received_gross',deposit::text,'beyond_deposit_received_gross',beyond::text
    ) || CASE WHEN stripe_received>0 OR stripe_refunded>0 OR disputed>0 THEN jsonb_build_object(
      'stripe_received',stripe_received::numeric(30,2)::text,'stripe_refunded',stripe_refunded::numeric(30,2)::text,'disputed',disputed::numeric(30,2)::text,
      'available_after_disputes',greatest(received-returned-disputed,0)::numeric(30,2)::text) ELSE '{}'::jsonb END
      || CASE WHEN external_unattributed<>0 THEN jsonb_build_object('external_unattributed',external_unattributed::text) ELSE '{}'::jsonb END
     ORDER BY currency) FROM money),'[]'::jsonb),
    'timeline',jsonb_build_object(
      'order_timezone','Europe/Prague','payment_date_basis','bank_transaction_date_and_provider_occurrence',
      'tickets',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM ticket_days d),'[]'::jsonb),
      'orders',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day) FROM order_days d),'[]'::jsonb),
      'payments',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM payment_days d),'[]'::jsonb)
    ),
    'products',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY type_id,product_id) FROM products p),'[]'::jsonb),
     'ticket_batches', (SELECT jsonb_build_object('total',count(*),'available',count(*) FILTER(WHERE i.sale_order_id IS NULL AND t.state<>'storno'),
      'sold_active',count(*) FILTER(WHERE i.sale_order_id IS NOT NULL AND t.state<>'storno'),
      'voided_unsold',count(*) FILTER(WHERE i.sale_order_id IS NULL AND t.state='storno'),
      'cancelled_after_sale',count(*) FILTER(WHERE i.sale_order_id IS NOT NULL AND t.state='storno'))
      FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id JOIN eshop.tickets t ON t.id=i.ticket_id
      WHERE b.occasion IN(SELECT id FROM scope)),
    'warnings',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY code) FROM warnings w),'[]'::jsonb)
  ), invalid.value INTO r,invalid_payment FROM scope s CROSS JOIN invalid;
  IF r IS NULL THEN RETURN jsonb_build_object('code',403,'message','Report unavailable or access denied.'); END IF;
  IF invalid_payment THEN RETURN jsonb_build_object('code',409,'message','Report payment allocation is inconsistent.'); END IF;
  RETURN jsonb_build_object('code',200,'data',public.format_occasion_report_text(r),'report',r);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('code',500,'message','Report could not be generated.');
END;
$$;
REVOKE ALL ON FUNCTION public.get_report_ws(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_report_ws(text) TO authenticated;

-- SOURCE: eshop/swap_spot_tickets.sql
CREATE OR REPLACE FUNCTION public._swap_spots_generate_product_json(
    p_product_id BIGINT,
    p_spot_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions
AS $$
DECLARE
    product_data RECORD;
BEGIN
    -- This query joins product, its type, and the spot (if provided)
    -- to get all data needed for the JSON object.
    SELECT
        p.id,
        p.price,
        p.title,
        p.description,
        p.currency_code,
        pt.title AS type_title,
        pt.type AS type,
        s.title AS spot_title
    INTO
        product_data
    FROM
        eshop.products AS p
    JOIN
        eshop.product_types AS pt ON p.product_type = pt.id
    LEFT JOIN
        eshop.spots AS s ON s.id = p_spot_id -- Use p_spot_id for spot_title
    WHERE
        p.id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product data not found for product_id %', p_product_id;
    END IF;

    -- Build the JSON object.
    -- jsonb_strip_nulls ensures that if 'spot_title' is NULL
    -- (because p_spot_id was NULL), the key is removed entirely.
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'id', product_data.id,
        'type', product_data.type,
        'price', product_data.price,
        'title', product_data.title,
        'spot_title', product_data.spot_title,
        'type_title', product_data.type_title,
        'description', product_data.description,
        'currency_code', product_data.currency_code
    )) || coalesce(public.order_spot_metadata_internal(p_spot_id), '{}'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public._swap_spots_update_ticket(
    p_opt_id BIGINT,
    p_new_product_id BIGINT,
    p_new_spot_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    opt RECORD;
    ord RECORD;
    original_product_id BIGINT;
    original_product_json JSONB;
    original_price NUMERIC;

    new_product_json JSONB;
    new_price NUMERIC;
    new_data JSONB;
    new_order_price NUMERIC;
    new_state TEXT;

    price_delta NUMERIC;
    history_needed BOOLEAN;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Get current ticket and order data
    SELECT * INTO opt FROM eshop.order_product_ticket WHERE id = p_opt_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order Product Ticket % not found', p_opt_id; END IF;

    PERFORM public.check_ticket_is_mutable(opt.ticket);
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[opt.ticket]);
    SELECT * INTO ord FROM eshop.orders WHERE id = opt."order" FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', opt."order"; END IF;

    original_product_id := opt.product;

    -- 2. Find the *original* product JSON and price from the order_ids.data
    SELECT prod, (prod->>'price')::numeric
    INTO original_product_json, original_price
    FROM jsonb_array_elements(ord.data->'tickets') tckt,
         jsonb_array_elements(tckt->'products') prod
    WHERE (tckt->>'id')::bigint = opt.ticket
      AND (prod->>'id')::bigint = original_product_id;

    IF original_price IS NULL THEN
        RAISE EXCEPTION 'Could not find original price for product % on ticket %', original_product_id, opt.ticket;
    END IF;

    -- 3. Generate the *new* product JSON
    new_product_json := public._swap_spots_generate_product_json(p_new_product_id, p_new_spot_id);
    new_price := (new_product_json->>'price')::numeric;
    IF new_product_json->>'currency_code' IS DISTINCT FROM ord.currency_code THEN
      RAISE EXCEPTION 'BLUEPRINT_CURRENCY_MISMATCH'; END IF;

    -- 4. Check if an update is even needed.
    -- If the new JSON is identical to the old, nothing needs to be done.
    IF original_product_json = new_product_json THEN
        RETURN;
    END IF;

    -- 5. Calculate financials and state
    price_delta := new_price - original_price;
    history_needed := (original_product_id IS DISTINCT FROM p_new_product_id);
    new_order_price := COALESCE(ord.price, 0) + price_delta;

    -- Recalculate order state
    SELECT CASE
        WHEN COALESCE(pi.paid, 0) >= new_order_price AND new_order_price > 0 THEN 'paid'
        WHEN new_order_price <= 0 THEN 'paid'
        ELSE 'ordered'
    END INTO new_state
    FROM (SELECT COALESCE((SELECT paid FROM eshop.payment_info WHERE id=ord.payment_info),0) AS paid) pi;

    -- 6. Build the new order_ids.data JSON
    new_data := jsonb_set(
        ord.data,
        '{tickets}',
        (SELECT jsonb_agg(
            -- Find the matching ticket
            CASE WHEN (tckt->>'id')::bigint = opt.ticket
            THEN jsonb_set(
                tckt,
                '{products}',
                (SELECT jsonb_agg(
                    -- Find the matching product and replace it
                    CASE
                        WHEN (prod->>'id')::bigint = original_product_id
                        THEN new_product_json -- Swap in the new product JSON
                        ELSE prod
                    END
                ) FROM jsonb_array_elements(tckt->'products') prod)
            )
            ELSE tckt
            END
        ) FROM jsonb_array_elements(ord.data->'tickets') tckt)
    );

    -- 7. Perform all database updates

    -- Update payment info
    IF price_delta <> 0 THEN
        IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=ord.payment_info AND payment_method<>'bank') THEN
            RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;
        UPDATE eshop.payment_info SET amount = amount + price_delta WHERE id = ord.payment_info;
    END IF;

    -- Update the order itself
    UPDATE eshop.orders
    SET
        price = new_order_price,
        data = new_data,
        state = new_state,
        updated_at = now_time
    WHERE id = ord.id;

    -- Update the link table
    UPDATE eshop.order_product_ticket
    SET
        product = p_new_product_id
    WHERE id = p_opt_id;

    -- 8. Create history log *only if* the product ID actually changed
    IF history_needed THEN
        INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
        VALUES (ord.id, new_data, new_state, new_order_price, ord.currency_code);
    END IF;

END;
$$;


-- Only the aggregate applier calls this worker, after locking the complete
-- assignment graph and checking scope, holds and atomic-unit eligibility.
-- The price/order helper remains the sole financial calculation.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_pair_locked_internal(p_first bigint,p_second bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE first_spot eshop.spots;second_spot eshop.spots;
BEGIN
 SELECT * INTO STRICT first_spot FROM eshop.spots WHERE id=p_first;
 SELECT * INTO STRICT second_spot FROM eshop.spots WHERE id=p_second;
 IF first_spot.order_product_ticket IS NOT NULL AND second_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(first_spot.order_product_ticket,second_spot.product,p_second);
  PERFORM public._swap_spots_update_ticket(second_spot.order_product_ticket,first_spot.product,p_first);
 ELSIF first_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(first_spot.order_product_ticket,second_spot.product,p_second);
 ELSIF second_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(second_spot.order_product_ticket,first_spot.product,p_first);
 ELSE RETURN;
 END IF;
 UPDATE eshop.spots SET order_product_ticket=CASE WHEN id=p_first THEN second_spot.order_product_ticket ELSE first_spot.order_product_ticket END
 WHERE id IN(p_first,p_second);
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_pair_locked_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.swap_spot_tickets(spot_id_1 bigint,spot_id_2 bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.swap_spot_tickets_client_sync_v1(
    spot_id_1,spot_id_2,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets(bigint,bigint) TO authenticated;

REVOKE ALL ON FUNCTION public._swap_spots_generate_product_json(bigint,bigint),public._swap_spots_update_ticket(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

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
    initial_data jsonb := '{"is_reminder_enabled": true}'::jsonb;
BEGIN
    SELECT org.data->>'DEFAULT_FORM_PAYMENT_METHOD' INTO payment_default
    FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
    WHERE o.id=p_occasion_id;
    IF payment_default<>'bank' AND public.payment_method_registered_internal(payment_default) THEN
      -- A closed draft can await Connect without inventing a recipient or bank.
      initial_data := initial_data || '{"payments":{"bankEnabled":false}}'::jsonb;
    END IF;
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
        604800, -- Default to 7 days
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
 WHERE uba.unit=p_unit AND ba.type IS DISTINCT FROM 'CASH';
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
  'bankAccounts',public.get_form_bank_accounts_internal(p_unit),
  'availability',public.form_payment_availability_internal(p_form))||public.provider_form_editor_fields_internal(p_unit,p_occasion,p_livemode);
 IF octet_length(result::text)>1048576 OR jsonb_array_length(result->'bankAccounts')>100 THEN
  RAISE program_limit_exceeded USING MESSAGE='form payment options too large'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_payment_options(bigint,bigint,bigint,bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_payment_options(bigint,bigint,bigint,bigint,boolean) TO authenticated;

-- SOURCE: eshop_orders/create_ticket_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_command_internal(
  p_order jsonb,p_command_id uuid,p_client_id uuid,p_context jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_symbol text; v_before_users uuid[]; v_actor_kind text; v_origin jsonb; v_form bigint;
BEGIN
  IF p_order IS NULL OR jsonb_typeof(p_order)<>'object'
    OR octet_length(p_order::text)>4194304 OR p_command_id IS NULL
    OR (v_actor IS NULL AND p_client_id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order command'; END IF;
  SELECT f.occasion INTO v_occasion FROM public.forms f
    WHERE f.key=NULLIF(p_order->>'form','')::uuid;
  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket order form not found'; END IF;
  v_hash:=encode(extensions.digest(convert_to((jsonb_build_object(
    'occasion',v_occasion,'order',public.strip_payment_sources_internal(p_order))
      ||CASE WHEN p_context IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('administration',p_context) END)::text,'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,p_client_id,v_hash);
    v_actor_kind:='unknown';
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,v_actor,v_hash);
    v_actor_kind:='user';
  END IF;
  IF v_begin->>'disposition'='replay' THEN
    v_result := v_begin->'response';
    IF v_result#>'{data,order}' IS NOT NULL AND v_result#>>'{data,order,order_symbol}' IS NULL THEN
      v_symbol := public.read_order_identity((v_result#>>'{data,order,id}')::bigint,
        v_occasion, (SELECT organization FROM public.occasions WHERE id=v_occasion));
      IF v_symbol IS NOT NULL THEN
        v_result := jsonb_set(v_result, '{data,order,order_symbol}', to_jsonb(v_symbol));
      END IF;
    END IF;
    RETURN public.project_local_payment_reference_order_internal(v_result);
  END IF;
  IF p_order ? 'checkoutOrigin' THEN
    SELECT id INTO v_form FROM public.forms WHERE key=(p_order->>'form')::uuid;
    v_origin:=public.read_checkout_origin_internal(p_order->>'checkoutOrigin',v_form);
    IF v_origin IS NULL THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',400,
        jsonb_build_object('code',400,'errorCode','CHECKOUT_CONTEXT_EXPIRED'));
    END IF;
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.create_ticket_order_internal_v1(public.strip_payment_sources_internal(p_order)-'checkoutOrigin');
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  PERFORM public.attach_checkout_origin_internal((v_result#>>'{order,id}')::bigint,v_origin);
  PERFORM public.attach_provider_order_source_internal((v_result#>>'{order,id}')::bigint,p_command_id,p_order);
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,p_order->>'lang');
  IF p_context IS NOT NULL THEN v_result:=v_result||jsonb_build_object('adminQuote',p_context->'quote','paymentPreparationPolicy','leased_keep_pending'); END IF;
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.create',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Ticket order','changedFields',jsonb_build_array(
        'tickets','products','allocations','membership'))),v_before_users,v_result,
    v_actor_kind);
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_command_internal(jsonb,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Released RPC signature and ordinary checkout hashes remain unchanged.
CREATE OR REPLACE FUNCTION public.create_ticket_order_client_sync_v1(p_order jsonb,p_command_id uuid,p_client_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.create_ticket_order_command_internal(p_order,p_command_id,p_client_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) TO anon,authenticated;

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
 IF pi.amount>0 AND pi.amount>coalesce(pi.paid,0) AND pi.payment_method='bank' THEN
   SELECT * INTO STRICT f FROM public.forms WHERE id=o.form;
   SELECT unit,organization INTO unit_id,org_id FROM public.occasions WHERE id=o.occasion;
   IF pi.bank_account IS NULL THEN
     IF pi.variable_symbol IS NOT NULL OR pi.creditor_reference IS NOT NULL THEN
       RAISE EXCEPTION 'PAYMENT_RECIPIENT_REQUIRED'; END IF;
     form_data:=public.get_effective_form_data(f.id);
     IF coalesce(form_data#>'{payments,bankEnabled}','true'::jsonb)<>'true'::jsonb THEN
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

-- SOURCE: eshop_orders/get_all_tickets_for_scan.sql
CREATE OR REPLACE FUNCTION public.get_all_tickets_for_scan(scan_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id_val bigint;
    result jsonb; policy jsonb; max_items bigint; max_bytes bigint; found_items bigint;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1(NULL) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    SELECT o.id
    INTO occasion_id_val
    FROM public.occasions o
    JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
    WHERE oh.secret = scan_code
    LIMIT 1;

    IF occasion_id_val IS NULL THEN
         PERFORM public.admit_scan_access_v1(NULL,false);
         RETURN jsonb_build_object('code',401,'message','invalid_scan_code');
    END IF;

    IF NOT public.admit_scan_access_v1(occasion_id_val,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    policy:=public.abuse_effective_rules_v1('scan.export',(SELECT unit FROM public.occasions WHERE id=occasion_id_val),(SELECT organization FROM public.occasions WHERE id=occasion_id_val));
    SELECT (r->>'base_limit')::bigint INTO max_items FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='scan.export.items';
    SELECT (r->>'base_limit')::bigint INTO max_bytes FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='scan.export.bytes';
    IF max_items IS NULL OR max_bytes IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
    SELECT count(*) INTO found_items FROM (SELECT id FROM eshop.tickets WHERE occasion=occasion_id_val LIMIT max_items+1) bounded;
    IF found_items>max_items THEN RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded'); END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'id', t.id,
            'ticket_symbol', t.ticket_symbol,
            'state', t.state,
            'batch', (SELECT jsonb_build_object('title',b.title) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=t.id AND b.occasion=occasion_id_val),
            'related_order', jsonb_build_object(
                 'data', t.data
            )
        ) 
    )
    INTO result
    FROM (
        SELECT DISTINCT ON (t.id) t.id, t.ticket_symbol, t.state, o.data
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE o.occasion = occasion_id_val
          AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted'
          AND t.ticket_symbol IS NOT NULL AND o.state IS DISTINCT FROM 'waitlisted'
          AND NOT public.provider_ticket_requires_online_internal(t.id)
        ORDER BY t.id
    ) t;

    IF octet_length(result::text)>max_bytes THEN RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded'); END IF;
    RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

-- SOURCE: eshop_orders/mark_order_and_tickets_paid_internal_v1.sql
-- Shared state transition. Public callers own authorization and delivery intent.
CREATE OR REPLACE FUNCTION public.mark_order_and_tickets_paid_internal_v1(order_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occasion_id bigint; current_state text; provider_guard jsonb;
BEGIN
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    -- Retrieve the occasion associated with the order
    SELECT occasion, state INTO occasion_id, current_state FROM eshop.orders WHERE id = order_id FOR UPDATE;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    provider_guard:=public.provider_paid_guard_internal(order_id);
    IF provider_guard IS NOT NULL THEN RETURN provider_guard; END IF;
    -- Check if the order is in 'ordered' or 'created' state before proceeding
    -- Allow 'created' to support direct payments (e.g. manual cash) without explicit confirmation step
    -- FIX: Allow 'expired' too, as late payments should reactivate the order
    IF current_state != 'ordered' AND current_state != 'created' AND current_state != 'expired' THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Order is not in "ordered", "created" or "expired" state (current: ' || current_state || ')');
    END IF;

    -- Update the state of the order to 'paid'
    UPDATE eshop.orders
    SET state = 'paid', updated_at = now(),email_payment_version=email_payment_version+1
    WHERE id = order_id;

    -- Update the state of all tickets linked to the order to 'paid', except those with state 'storno'
    UPDATE eshop.tickets
    SET state = 'paid', updated_at = now()
    FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = order_id
    AND eshop.tickets.state IN ('ordered','expired','paid');

    PERFORM public.notification_center_order_state_internal(order_id);
    RETURN jsonb_build_object('code',200,'message','Update successful');
END $$;
REVOKE ALL ON FUNCTION public.mark_order_and_tickets_paid_internal_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_and_tickets_paid_internal_v1(bigint) TO service_role;

-- SOURCE: eshop_orders/operator_orders.sql
-- Thin delegated adapters over the existing order, payment, report and mail owners.
-- Scope is locked in the same transaction as every read, write and receipt replay.
CREATE OR REPLACE FUNCTION public.check_operator_order_scope_internal_v1(
  p_occasion bigint,p_organization bigint,p_unit bigint,p_write boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.organization=o.organization AND ui.id=auth.uid()
    WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE OF o;
  IF NOT FOUND OR public.can_read_orders(p_occasion) IS DISTINCT FROM TRUE OR (p_write AND public.can_write_orders(p_occasion) IS DISTINCT FROM TRUE) THEN
    RAISE insufficient_privilege USING MESSAGE='order context unavailable'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.operator_order_revision_internal_v1(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('order',to_jsonb(o),
   'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE p.id=o.payment_info),
   'items',(SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i WHERE i."order"=o.id),
   'tickets',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id)))::text,'UTF8'),'sha256'),'hex')
 FROM eshop.orders o WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_facts_internal_v1(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('id',o.id,'occasionId',o.occasion,'symbol',o.order_symbol,'state',o.state,
   'ticketCount',(SELECT count(DISTINCT i.ticket) FROM eshop.order_product_ticket i JOIN eshop.tickets t ON t.id=i.ticket WHERE i."order"=o.id AND o.state IS DISTINCT FROM 'storno' AND o.state IS DISTINCT FROM 'waitlisted' AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted'),
   'price',o.price::text,'currency',o.currency_code,'allowedActions',public.get_order_allowed_actions_internal_v1(o.id),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text) END)
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_snapshot_internal_v1(p_order bigint,p_detail boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.operator_order_facts_internal_v1(o.id) || jsonb_build_object(
   'createdAt',o.created_at,'updatedAt',o.updated_at,'revision',public.operator_order_revision_internal_v1(o.id),
   'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('method',p.payment_method,'amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'variableSymbol',p.variable_symbol::text,'deadline',p.deadline) END)
   || CASE WHEN p_detail THEN jsonb_build_object('note',o.note_hidden,'responses',coalesce(o.data->'fields','[]'),
     'formFields',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'type',f.type) ORDER BY f.id),'[]') FROM public.form_fields f WHERE f.form=o.form),
     'tickets',public.order_tickets_with_seating_internal(o.id,(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'state',t.state,
        'products',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',pr.id,'title',pr.title,'price',jsonb_path_query_first(o.data,'$.tickets[*] ? (@.id == $ticket).products[*] ? (@.id == $product).price',jsonb_build_object('ticket',t.id,'product',pr.id))#>>'{}','currentPrice',pr.price::text) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i JOIN eshop.products pr ON pr.id=i.product WHERE i."order"=o.id AND i.ticket=t.id)) ORDER BY t.id),'[]')
       FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id)))) ELSE '{}'::jsonb END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_summary_internal_v1(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_set(facts,'{allowedActions}',
   CASE WHEN facts->'allowedActions' ? 'view' THEN '["view"]'::jsonb ELSE '[]'::jsonb END)
 FROM (SELECT public.operator_order_facts_internal_v1(p_order) facts) safe;
$$;

CREATE OR REPLACE FUNCTION public.get_operator_order_summaries_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL,
  p_limit integer DEFAULT 25,p_before bigint DEFAULT NULL,p_state text DEFAULT NULL,p_symbol text DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; v_next bigint;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR (p_symbol IS NOT NULL AND p_symbol !~ '^[A-Z0-9]{10}$')
   OR (p_state IS NOT NULL AND length(p_state)>40)
   OR (p_order IS NOT NULL AND (p_before IS NOT NULL OR p_state IS NOT NULL OR p_symbol IS NOT NULL OR p_limit<>25)) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid order summary page'; END IF;
 IF p_order IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
   RETURN jsonb_build_object('occasionId',p_occasion,'orders',jsonb_build_array(public.operator_order_summary_internal_v1(p_order)),'nextCursor',NULL);
 END IF;
 WITH page AS MATERIALIZED(SELECT id FROM eshop.orders WHERE occasion=p_occasion AND (p_before IS NULL OR id<p_before)
   AND (p_state IS NULL OR state=p_state) AND (p_symbol IS NULL OR order_symbol=p_symbol)
   ORDER BY id DESC LIMIT p_limit+1), visible AS(SELECT id FROM page ORDER BY id DESC LIMIT p_limit)
 SELECT coalesce(jsonb_agg(public.operator_order_summary_internal_v1(id) ORDER BY id DESC),'[]'),
   CASE WHEN p_symbol IS NULL AND (SELECT count(*) FROM page)>p_limit THEN min(id) END INTO rows,v_next FROM visible;
 RETURN jsonb_build_object('occasionId',p_occasion,'orders',rows,'nextCursor',v_next);
END $$;

REVOKE ALL ON FUNCTION public.operator_order_facts_internal_v1(bigint),public.operator_order_summary_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_operator_order_report_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb; v_link text;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 SELECT link INTO v_link FROM public.occasions WHERE id=p_occasion;
 r:=public.get_report_ws(v_link);
 IF (r->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='order report unavailable'; END IF;
 RETURN jsonb_build_object('occasionId',p_occasion,'report',r->'report',
   'waitingTickets',(SELECT count(*) FROM eshop.tickets WHERE occasion=p_occasion AND state='waitlisted'));
END $$;

CREATE OR REPLACE FUNCTION public.get_operator_orders_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL,
  p_limit integer DEFAULT 25,p_before bigint DEFAULT NULL,p_state text DEFAULT NULL,p_search text DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; v_next bigint;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR coalesce(length(p_search),0)>200 THEN RAISE invalid_parameter_value USING MESSAGE='invalid order page'; END IF;
 IF p_order IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
   RETURN jsonb_build_object('occasionId',p_occasion,'orders',jsonb_build_array(public.operator_order_snapshot_internal_v1(p_order,true)),'nextCursor',NULL);
 END IF;
 WITH page AS MATERIALIZED(SELECT id FROM eshop.orders WHERE occasion=p_occasion AND (p_before IS NULL OR id<p_before)
   AND (p_state IS NULL OR state=p_state) AND (nullif(p_search,'') IS NULL OR position(lower(p_search) IN lower(concat_ws(' ',order_symbol,data->>'name',data->>'surname',data->>'email')))>0)
   ORDER BY id DESC LIMIT p_limit+1), visible AS(SELECT id FROM page ORDER BY id DESC LIMIT p_limit)
 SELECT coalesce(jsonb_agg(public.operator_order_snapshot_internal_v1(id) ORDER BY id DESC),'[]'),
   CASE WHEN (SELECT count(*) FROM page)>p_limit THEN min(id) END INTO rows,v_next FROM visible;
 RETURN jsonb_build_object('occasionId',p_occasion,'orders',rows,'nextCursor',v_next);
END $$;

CREATE OR REPLACE FUNCTION public.manage_operator_order_v1(p_occasion bigint,p_organization bigint,p_unit bigint,
  p_order bigint,p_command_id uuid,p_expected_revision text,p_action text,p_changes jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_unit bigint; v_begin jsonb; v_hash text; v_child uuid;
 v_result jsonb; v_actions jsonb; v_item jsonb; v_products jsonb; v_message jsonb; v_users uuid[]; v_data jsonb;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,true);
 IF p_action IS NULL OR p_expected_revision IS NULL OR p_action NOT IN('update','cancel','mark_paid','record_payment','send_tickets') OR p_expected_revision !~ '^[a-f0-9]{64}$'
   OR p_changes IS NULL OR jsonb_typeof(p_changes)<>'object' OR octet_length(p_changes::text)>65536 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid order command'; END IF;
 IF p_action NOT IN('update','record_payment') AND p_changes<>'{}'::jsonb THEN RAISE invalid_parameter_value USING MESSAGE='unexpected order changes'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('order',p_order,'occasion',p_occasion,'organization',p_organization,'unit',p_unit,'revision',p_expected_revision,'action',p_action,'changes',p_changes)::text,'UTF8'),'sha256'),'hex');
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 v_begin:=public.begin_client_mutation_v1(p_command_id,'orders.operator.'||p_action,p_occasion,auth.uid(),v_hash);
 IF v_begin->>'disposition'='replay' THEN RETURN jsonb_set(v_begin->'response','{mutation,replayed}','true'); END IF;
 -- Preserve the domain lock order, including form -> order and blueprint scope.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_order AND occasion=p_occasion FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion;
 IF public.operator_order_revision_internal_v1(p_order) IS DISTINCT FROM p_expected_revision THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('orderId',p_order,'reason','ORDER_CHANGED_RELOAD_REQUIRED')); END IF;
 v_actions:=public.get_order_allowed_actions_internal_v1(p_order);
 IF NOT (v_actions ? CASE p_action WHEN 'update' THEN CASE WHEN p_changes ? 'note' AND p_changes - 'note'='{}'::jsonb THEN 'note' ELSE 'edit' END WHEN 'cancel' THEN 'cancel' WHEN 'mark_paid' THEN 'paid' WHEN 'record_payment' THEN 'edit' ELSE 'send' END) THEN
   RAISE insufficient_privilege USING MESSAGE='order action unavailable'; END IF;
 v_child:=md5(p_command_id::text||':domain')::uuid;
 IF p_action='cancel' THEN
   v_result:=public.storno_order_client_sync_v1(p_order,v_child);
 ELSIF p_action='update' THEN
   IF p_changes - ARRAY['responses','note','tickets']::text[]<>'{}'::jsonb OR p_changes='{}' THEN RAISE invalid_parameter_value USING MESSAGE='invalid order changes'; END IF;
   IF p_changes ? 'responses' THEN PERFORM public.update_order_responses(p_order,p_changes->'responses'); END IF;
   IF p_changes ? 'note' THEN
     v_result:=public.update_order_note_hidden(p_order,p_changes->>'note');
     IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='order note rejected'; END IF;
   END IF;
   FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_changes->'tickets','[]')) LOOP
     IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=p_order AND ticket=(v_item->>'ticketId')::bigint) THEN RAISE insufficient_privilege USING MESSAGE='ticket unavailable'; END IF;
     SELECT coalesce(jsonb_agg(jsonb_build_object('id',x->'productId','price',x->'price')),'[]') INTO v_products FROM jsonb_array_elements(v_item->'products') x;
     v_result:=public.update_ticket_products_client_sync_v1((v_item->>'ticketId')::bigint,v_products,md5(p_command_id::text||':ticket:'||(v_item->>'ticketId'))::uuid);
     IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='ticket products rejected'; END IF;
   END LOOP;
 ELSIF p_action='mark_paid' THEN
   v_result:=public.update_order_and_tickets_to_paid_ws(p_order);
   IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='payment state rejected'; END IF;
   v_result:=NULL;
 ELSIF p_action='record_payment' THEN
   IF NOT (p_changes ?& ARRAY['amount','currency','receivedAt']) OR p_changes - ARRAY['amount','currency','receivedAt','note']::text[]<>'{}'::jsonb
     OR jsonb_typeof(p_changes->'amount') IS DISTINCT FROM 'string' OR jsonb_typeof(p_changes->'currency') IS DISTINCT FROM 'string' OR jsonb_typeof(p_changes->'receivedAt') IS DISTINCT FROM 'string'
     OR v_pi.id IS NULL OR v_pi.payment_method<>'bank' OR (p_changes->>'currency') IS DISTINCT FROM trim(v_order.currency_code)
     OR (p_changes->>'amount') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' OR (p_changes->>'amount')::numeric<=0 THEN
     RAISE invalid_parameter_value USING MESSAGE='manual payment unavailable'; END IF;
   PERFORM public.insert_manual_transaction((p_changes->>'amount')::double precision,p_changes->>'currency',v_unit::int,v_pi.variable_symbol::text,
     p_changes->>'receivedAt',p_changes->>'note',v_pi.id::int);
 ELSIF p_action='send_tickets' THEN
   v_message:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',p_order,'requested_by',auth.uid()),p_organization,p_occasion,v_unit,now(),'operator:'||p_command_id);
 END IF;
 v_data:=jsonb_build_object('orderId',p_order,'occasionId',p_occasion,'revision',public.operator_order_revision_internal_v1(p_order))
   ||CASE WHEN v_message IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('delivery','queued','messageId',v_message->'message_id') END;
 IF v_result ? 'mutation' THEN
   IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='cancellation rejected'; END IF;
   v_result:=jsonb_set(v_result,'{data}',v_data);
   v_result:=jsonb_set(v_result,'{mutation,commandId}',to_jsonb(p_command_id));v_result:=jsonb_set(v_result,'{mutation,receiptId}',to_jsonb(p_command_id));
   RETURN public.finish_client_mutation_v1(p_command_id,v_result,(v_result#>>'{mutation,commitId}')::uuid);
 END IF;
 IF p_action='send_tickets' THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,v_data);
 END IF;
 SELECT coalesce(array_agg(DISTINCT "user"),'{}') INTO v_users FROM public.occasion_users WHERE occasion=p_occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,p_occasion,'orders.operator.'||p_action,
   jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,'operation','update','safeLabel','Order management','changedFields',jsonb_build_array(p_action))),v_users,v_data);
END $$;

REVOKE ALL ON FUNCTION public.check_operator_order_scope_internal_v1(bigint,bigint,bigint,boolean),public.operator_order_revision_internal_v1(bigint),
 public.operator_order_snapshot_internal_v1(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_operator_order_report_v1(bigint,bigint,bigint),public.get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint),
 public.manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_operator_order_report_v1(bigint,bigint,bigint),public.get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint),
 public.manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb) TO authenticated;

-- SOURCE: eshop_orders/order_actions.sql
-- Shared action projection for administration and delegated order tools.
CREATE OR REPLACE FUNCTION public.get_order_allowed_actions_internal_v1(p_order bigint,p_summary jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT (CASE WHEN o.state='stock' THEN jsonb_build_array('view')
 WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id WHERE i.sale_order_id=o.id AND t.state<>'storno') THEN jsonb_build_array('view','note','cancel','send')
 ELSE (coalesce(p_summary,(CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
    THEN public.get_waitlist_summary_internal(o.id) ELSE public.get_order_action_summary_internal(o.state) END))->'allowedActions') END)
    - CASE WHEN p.payment_method<>'bank' THEN ARRAY['cancel','paid']::text[] ELSE ARRAY[]::text[] END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

REVOKE ALL ON FUNCTION public.get_order_allowed_actions_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_orders/recalculate_order_payment_status.sql
-- One financial eligibility decision for bank facts and actual product changes.
-- Callers own authorization; this private invoker owns no history snapshots.
CREATE OR REPLACE FUNCTION public.reconcile_order_payment_internal_v1(p_order_id bigint, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    v_order eshop.orders;
    v_payment eshop.payment_info;
    v_eligible boolean;
    v_was_eligible boolean;
    v_transition jsonb;
    v_final_state text;
    v_final_version bigint;
    v_promote boolean;
BEGIN
    IF p_reason IS NULL OR p_reason NOT IN ('payment_fact','product_edit') THEN
        RAISE EXCEPTION 'INVALID_PAYMENT_RECONCILIATION_REASON';
    END IF;
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=p_order_id FOR UPDATE;
    SELECT * INTO v_payment FROM eshop.payment_info WHERE id=v_order.payment_info FOR UPDATE;
    v_was_eligible := coalesce(v_order.state IN ('paid','sent'),false);
    -- Provider facts and non-admission shells retain their existing owners.
    IF v_payment.id IS NULL OR v_payment.payment_method<>'bank'
       OR v_order.state NOT IN ('created','ordered','expired','paid','sent') THEN
        RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_order.state,
            'eligibility_changed',false,'email_payment_version',v_order.email_payment_version);
    END IF;

    IF p_reason='product_edit' THEN
        PERFORM public.ensure_order_payment_instructions_internal(p_order_id);
        SELECT * INTO v_payment FROM eshop.payment_info WHERE id=v_order.payment_info;
    END IF;

    -- The saved deposit is a commercial snapshot, capped by the current price.
    v_eligible := coalesce(v_order.price,0)<=0 OR coalesce(v_payment.paid,0)>=
        least(coalesce(v_payment.deposit_amount,v_order.price),v_order.price);
    v_promote := v_eligible AND NOT v_was_eligible;

    IF p_reason='product_edit' OR v_eligible IS DISTINCT FROM v_was_eligible THEN
        PERFORM public.cancel_order_email_intents(p_order_id);
        -- The paid primitive owns the single version bump when promoting.
        IF NOT v_promote THEN
            UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=now()
            WHERE id=p_order_id;
        END IF;
    END IF;

    IF v_promote THEN
        -- Reuse the existing atomic primitive and delivery boundary. A failed
        -- receipt must abort its outer pairing or receipted product command.
        v_transition := public.update_order_and_tickets_to_paid(p_order_id);
        IF v_transition->>'code' IS DISTINCT FROM '200' THEN
            RAISE EXCEPTION 'ORDER_PAID_TRANSITION_FAILED: %',
                coalesce(v_transition->>'message','invalid transition receipt');
        END IF;
    ELSIF NOT v_eligible AND v_was_eligible THEN
        UPDATE eshop.orders SET state='ordered',updated_at=now() WHERE id=p_order_id;
        UPDATE eshop.tickets t SET state='ordered',updated_at=now()
        FROM eshop.order_product_ticket opt
        WHERE opt.ticket=t.id AND opt."order"=p_order_id AND t.state IN ('paid','sent');
    ELSIF p_reason='product_edit' THEN
        -- An eligible paid order needs the edited content at its final version.
        -- Already sent admission stays sent; used/cancelled tickets stay intact.
        PERFORM public.enqueue_paid_order_tickets(p_order_id);
    END IF;

    PERFORM public.notification_center_order_state_internal(p_order_id);
    SELECT state,email_payment_version INTO v_final_state,v_final_version FROM eshop.orders WHERE id=p_order_id;
    RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_final_state,
        'eligibility_changed',v_eligible IS DISTINCT FROM v_was_eligible,
        'email_payment_version',v_final_version);
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_order_payment_internal_v1(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_order_payment_internal_v1(bigint,text) TO postgres,service_role;

CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.reconcile_order_payment_internal_v1(p_order_id,'payment_fact');
END;
$$;

-- SOURCE: eshop_orders/scan_ticket.sql
CREATE OR REPLACE FUNCTION public.scan_ticket(scanned_id TEXT, scanned_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ticket_row RECORD;
    order_json JSONB;
    products_json JSONB;
    spot_json JSONB;
    groups_json JSONB; -- New variable for groups
    order_id BIGINT;
    occasion_id BIGINT;
    hide_price BOOLEAN := FALSE;
    target_user_id UUID; -- New variable to store the resolved User ID
    expected_scan_code TEXT;
    is_uuid BOOLEAN;
    -- Deposit info variables
    v_deposit_amount NUMERIC;
    v_paid NUMERIC;
    v_amount NUMERIC;
    v_deposit_deadline_days INT;
    v_deposit_deadline TEXT;
    v_occ_start_time TIMESTAMPTZ;
    v_occ_features JSONB;
    v_deposit_feature JSONB;
    v_deposit_info JSONB;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1((SELECT occasion FROM eshop.tickets WHERE ticket_symbol=scanned_id LIMIT 1)) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    -----------------------------------------------------
    -- 1. Attempt to find ticket by Ticket Symbol
    -----------------------------------------------------
    SELECT *
      INTO ticket_row
    FROM eshop.tickets
    WHERE ticket_symbol = scanned_id
    LIMIT 1;

    -----------------------------------------------------
    -- 1.a. Fallback: Scan by User ID if Ticket Symbol not found
    -----------------------------------------------------
    IF ticket_row IS NULL THEN
        -- Check if the scanned_id is a valid UUID format
        is_uuid := scanned_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

        IF is_uuid THEN
            -- If scanned by UUID, we know the user immediately
            target_user_id := scanned_id::UUID;

            SELECT t.*
              INTO ticket_row
            FROM public.occasion_users ou
            JOIN public.occasions o ON ou.occasion = o.id
            JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
            JOIN eshop.tickets t ON ou.ticket = t.id
            WHERE ou.user = target_user_id
              AND oh.secret = scanned_code
            LIMIT 1;
        END IF;
    END IF;

    -----------------------------------------------------
    -- 1.b. Final Check if Ticket is still missing
    -----------------------------------------------------
    IF ticket_row IS NULL OR ticket_row.state='waitlisted' OR ticket_row.ticket_symbol IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket or User with valid ticket not found');
    END IF;

    -----------------------------------------------------
    -- 2. Retrieve the associated order ID
    -----------------------------------------------------
    SELECT opt."order" INTO order_id
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ticket_row.id
    LIMIT 1;

    IF order_id IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code', 404, 'message', 'Order for ticket not found');
    END IF;

    -----------------------------------------------------
    -- 3. Retrieve the occasion ID from the order
    -----------------------------------------------------
    SELECT o.occasion, NOT coalesce((ss.config#>>'{sensitive,price}')::boolean,true)
      INTO occasion_id, hide_price
    FROM eshop.orders o
    JOIN public.occasions occ ON occ.id = o.occasion
    LEFT JOIN public.scanner_settings ss ON ss.occasion_id=occ.id
    WHERE o.id = order_id
    LIMIT 1;

    PERFORM public.check_occasion_writable(occasion_id);
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion for order not found');
    END IF;

    -----------------------------------------------------
    -- 3.b. Resolve User ID if not already found via UUID scan
    -----------------------------------------------------
    -- If we found the ticket via Symbol (Step 1), we need to find who holds it
    IF target_user_id IS NULL THEN
        SELECT "user" INTO target_user_id
        FROM public.occasion_users
        WHERE ticket = ticket_row.id
          AND occasion = occasion_id
        LIMIT 1;
    END IF;

    -----------------------------------------------------
    -- 4. Retrieve the expected scan_code
    -----------------------------------------------------
    SELECT oh.secret
      INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    IF expected_scan_code IS NULL THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object('code', 400, 'message', 'Scan code not defined for this occasion');
    END IF;

    -----------------------------------------------------
    -- 5. Validate the scanned_code
    -----------------------------------------------------
    IF scanned_code IS DISTINCT FROM expected_scan_code THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object('code', 401, 'message', 'Scan code is not correct');
    END IF;

    -----------------------------------------------------
    -- 6. Fetch order, products, spot, AND GROUPS
    -----------------------------------------------------

    IF NOT public.admit_scan_access_v1(occasion_id,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    IF NOT public.provider_ticket_admission_allowed_internal(ticket_row.id) THEN
        RETURN jsonb_build_object('code',403,'message','stripe_admission_hold');
    END IF;

    -- A. Fetch Order
    SELECT CASE
             WHEN hide_price THEN
               (to_jsonb(o) - 'price') || jsonb_build_object(
                 'data',
                 CASE
                   WHEN jsonb_typeof(o.data->'tickets') = 'array' THEN
                     jsonb_set(
                       o.data,
                       '{tickets}',
                       COALESCE(
                         (
                           SELECT jsonb_agg(
                             CASE
                               WHEN jsonb_typeof(ticket->'products') = 'array' THEN
                                 jsonb_set(
                                   ticket,
                                   '{products}',
                                   COALESCE(
                                     (
                                       SELECT jsonb_agg(product - 'price')
                                       FROM jsonb_array_elements(ticket->'products') AS product
                                     ),
                                     '[]'::jsonb
                                   ),
                                   FALSE
                                 )
                               ELSE ticket
                             END
                           )
                           FROM jsonb_array_elements(o.data->'tickets') AS ticket
                         ),
                         '[]'::jsonb
                       ),
                       FALSE
                     )
                   ELSE o.data
                 END
               )
             ELSE to_jsonb(o)
           END
      INTO order_json
    FROM eshop.orders o
    WHERE o.id = order_id;

    -- B. Fetch Products
    SELECT jsonb_agg(
             CASE
               WHEN hide_price THEN
                 jsonb_build_object(
                   'id', p.id,
                   'title', p.title,
                   'order', p."order",
                   'description', p.description,
                   'currency_code', p.currency_code
                 )
               ELSE
                 jsonb_build_object(
                   'id', p.id,
                   'title', p.title,
                   'price', p.price,
                   'order', p."order",
                   'description', p.description,
                   'currency_code', p.currency_code
                 )
             END
           )
      INTO products_json
    FROM eshop.products p
    WHERE p.id IN (
        SELECT opt.product
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    );

    -- C. Fetch Spot
    SELECT row_to_json(s) INTO spot_json
    FROM eshop.spots s
    WHERE s.order_product_ticket IN (
        SELECT opt.id
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    )
    LIMIT 1;

    -- D. Fetch User Groups (New Logic)
    IF target_user_id IS NOT NULL THEN
        -- We construct a JSON object compatible with UserGroupInfoModel
        -- We join user_groups -> user_group_info -> places to get full context
        SELECT jsonb_agg(
                 to_jsonb(ugi) ||
                 jsonb_build_object(
                    'place_object', row_to_json(p)
                 )
               )
        INTO groups_json
        FROM public.user_groups ug
        JOIN public.user_group_info ugi ON ug."group" = ugi.id
        LEFT JOIN public.places p ON ugi.place = p.id
        WHERE ug."user" = target_user_id
          AND ugi.occasion = occasion_id;
    END IF;

    -----------------------------------------------------
    -- 6E. Fetch deposit info for deposit orders
    -----------------------------------------------------
    SELECT pi.deposit_amount, pi.paid, pi.amount
    INTO v_deposit_amount, v_paid, v_amount
    FROM eshop.payment_info pi
    JOIN eshop.orders o ON o.payment_info = pi.id
    WHERE o.id = order_id;

    IF v_deposit_amount IS NOT NULL THEN
        -- Get occasion features and start_time for deposit deadline
        SELECT occ.features, occ.start_time
        INTO v_occ_features, v_occ_start_time
        FROM public.occasions occ
        WHERE occ.id = occasion_id;

        -- Read deposit deadline from deposit feature in features JSONB
        SELECT elem INTO v_deposit_feature
        FROM jsonb_array_elements(v_occ_features) elem
        WHERE elem->>'code' = 'deposit';

        v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
        v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

        v_deposit_info := jsonb_build_object(
            'remaining_amount', GREATEST(0, COALESCE(v_amount, 0) - COALESCE(v_paid, 0)),
            'is_fully_paid', COALESCE(v_paid, 0) >= COALESCE(v_amount, 0),
            'deadline_type', CASE
                WHEN v_deposit_deadline = 'on_site' THEN 'on_site'
                WHEN v_deposit_deadline_days IS NOT NULL THEN 'date'
                ELSE NULL
            END,
            'deadline_date', CASE
                WHEN v_deposit_deadline_days IS NOT NULL AND v_deposit_deadline IS DISTINCT FROM 'on_site'
                THEN (v_occ_start_time - make_interval(days => v_deposit_deadline_days))::text
                ELSE NULL
            END,
            'deposit_amount', v_deposit_amount,
            'total_amount', v_amount,
            'paid_amount', COALESCE(v_paid, 0)
        );
    END IF;

    -----------------------------------------------------
    -- 7. Return the compiled JSONB response
    -----------------------------------------------------
    RETURN jsonb_build_object(
        'code', 200,
        'ticket', to_jsonb(ticket_row)||jsonb_build_object('online_required',public.provider_ticket_requires_online_internal(ticket_row.id),'batch',(SELECT jsonb_build_object('title',b.title) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=ticket_row.id AND b.occasion=occasion_id)),
        'order', order_json,
        'products', products_json,
        'spot', spot_json,
        'groups', COALESCE(groups_json, '[]'::jsonb),
        'deposit_info', v_deposit_info
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred: ' || SQLERRM
        );
END;
$$;

-- SOURCE: eshop_orders/storno_tickets_bulk.sql
CREATE OR REPLACE FUNCTION public.storno_tickets_bulk_internal_v1(p_ticket_ids BIGINT[], p_send_email BOOLEAN DEFAULT TRUE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
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
        -- 2. SECURITY CHECK
        -- Verify that the current user has editor permissions on the occasion associated with the order.
        IF NOT public.can_write_orders(v_occasion_id) THEN
            RAISE EXCEPTION 'Permission denied to storno tickets for order % on occasion %', v_order_id, v_occasion_id;
        END IF;

        -- Repeated selected tickets in an otherwise active order are a no-op.
        IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
          WHERE opt."order"=v_order_id AND t.id=ANY(p_ticket_ids) AND t.state IS DISTINCT FROM 'storno') THEN
          CONTINUE;
        END IF;
        PERFORM public.check_order_is_mutable(v_order_id);
        IF EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=v_order_id AND pi.payment_method<>'bank') THEN
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

REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[],boolean) FROM PUBLIC, anon, authenticated;

-- SOURCE: eshop_orders/update_order_and_tickets_to_storno.sql
CREATE OR REPLACE FUNCTION public.cancel_order_domain_internal_v1(order_id BIGINT,p_notify boolean)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_ids BIGINT[];
    updated_order_data jsonb;
    v_order eshop.orders;
    v_occasion public.occasions;
    v_notice jsonb;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=order_id)]);
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=order_id FOR UPDATE;
    IF v_order.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
    IF v_order.state='storno' THEN RETURN; END IF;
    PERFORM public.check_order_is_mutable(order_id);
    -- Card finances and admission are resolved by provider facts and the
    -- audited refund decision, never by resetting an order's original price.
    IF EXISTS(SELECT 1 FROM eshop.payment_info pi
      WHERE pi.id=v_order.payment_info AND pi.payment_method<>'bank') THEN
        RAISE EXCEPTION 'STRIPE_USE_REFUND_ADMISSION_DECISION';
    END IF;
    PERFORM public.cancel_order_email_intents(order_id);
    -- Retrieve all ticket ids associated with the order
    SELECT ARRAY_AGG(t.id) INTO ticket_ids
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = order_id;

    -- Check if the order exists and has associated tickets
    IF ticket_ids IS NULL THEN
        -- This is not an error, just an order with no tickets yet.
        -- But we can still storno the order itself.
        RAISE NOTICE 'No tickets found for order %, proceeding to storno order shell.', order_id;
    END IF;

    -- Call the helper to storno all tickets and their relations
    -- The helper function gracefully handles an empty/NULL array
    PERFORM internal_storno_tickets_221(ticket_ids);

    -- Set the order state to 'storno', price to 0, and update the data field
    UPDATE eshop.orders
    SET state = 'storno',
        price = 0,
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object('tickets', '[]'::jsonb),
        updated_at = NOW()
    WHERE id = order_id
    RETURNING data INTO updated_order_data;
    PERFORM public.notification_center_order_state_internal(order_id);

    -- Finish the original email recovery task in the same cancellation transaction.
    -- Keep provider messages and delivery history intact.
    UPDATE public.notification_center_events e SET status='recovered'
    FROM public.email_messages m
    WHERE m.order_id=v_order.id AND m.occasion=v_order.occasion
      AND m.message_kind<>'order_storno' AND e.organization=m.organization
      AND e.kind='email_problem' AND e.source_key='email:'||m.message_id;


    -- Save the change to orders_history by inserting the updated order row
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        order_id,
        'storno',
        0,
        updated_order_data,
        NOW()
    );

    -- The full transition owns the durable automatic commitment for every caller.
    SELECT * INTO v_occasion FROM public.occasions WHERE id=v_order.occasion;
    IF p_notify AND position('@' in v_order.data->>'email')>0
      AND length(v_order.data->>'email')<=320 THEN
      v_notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',
        jsonb_build_object('order_id',order_id),v_occasion.organization,
        v_occasion.id,v_occasion.unit);
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_order_domain_internal_v1(bigint,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
-- Compatibility for trusted SQL callers; domain logic exists only above.
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_221(order_id bigint)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.cancel_order_domain_internal_v1(order_id,true);
$$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_221(bigint)
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_orders/update_ticket_products_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id    bigint,
  p_products     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS
$$
DECLARE
  v_order_id         bigint;
  v_occasion_id      bigint;
  v_payment_info_id  bigint;
  v_currency_code    char(3);
  v_state            text;
  v_old_data         jsonb;
  v_new_data         jsonb;
  v_sum_old          numeric := 0;
  v_sum_new          numeric := 0;
  v_diff             numeric;
  v_products_json    jsonb;
  v_old_products     jsonb;
  v_old_ids          bigint[];
  v_new_ids          bigint[];
  v_price            numeric;
  v_reconciliation   jsonb;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_deadline_duration_seconds bigint;
  v_new_deadline      timestamptz;
  v_current_products_for_compare jsonb;
BEGIN
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=p_ticket_id));
  /* 0) Lookup & permission */
  SELECT opt."order", o.occasion, o.payment_info, o.currency_code, o.data, o.state, occ.features
    INTO v_order_id, v_occasion_id, v_payment_info_id, v_currency_code, v_old_data, v_state, v_occasion_features
  FROM eshop.order_product_ticket AS opt
  JOIN eshop.orders              AS o   ON o.id = opt."order"
  JOIN public.occasions          AS occ ON occ.id = o.occasion
  WHERE opt.ticket = p_ticket_id
  LIMIT 1 FOR UPDATE OF o;

  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 404, 'message', 'Ticket not linked to any order')::text;
  END IF;

  IF NOT public.can_write_orders(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  PERFORM public.check_ticket_is_mutable(p_ticket_id);
  PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[p_ticket_id]);
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_payment_info_id AND payment_method<>'bank') THEN
    RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;

  /* Check for negative prices in the input */
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_products) AS p
    WHERE (p.value->>'price')::numeric < 0
  ) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 400, 'message', 'Product prices cannot be negative.')::text;
  END IF;

  PERFORM public.lock_ticket_order_products_internal(v_order_id,jsonb_build_object('ticket',jsonb_build_array(jsonb_build_object('fields',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('product_type',x->'id')),'[]') FROM jsonb_array_elements(p_products) x)))));
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_products) x JOIN eshop.products p ON p.id=(x->>'id')::bigint
    WHERE p.maximum>0 AND (SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id)+
      CASE WHEN EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket_id AND product=p.id) THEN 0 ELSE 1 END>p.maximum) THEN
    RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;
  /* get old products for the ticket */
  SELECT jsonb_path_query_first(v_old_data, '$.tickets[*] ? (@.id == $tid).products', jsonb_build_object('tid', p_ticket_id))
  INTO v_old_products;
  v_old_products := COALESCE(v_old_products, '[]'::jsonb);

  /* compute old/new ID arrays and check for changes */
  SELECT array_agg((p->>'id')::bigint) INTO v_old_ids FROM jsonb_array_elements(v_old_products) p;
  SELECT array_agg((p->>'id')::bigint) INTO v_new_ids FROM jsonb_array_elements(p_products) p;

  -- Create a comparable representation of products (id and price)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
  INTO v_current_products_for_compare
  FROM jsonb_array_elements(v_old_products) p;

  -- If product sets (ID and price) are identical, bail early.
  IF v_current_products_for_compare = (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
    FROM jsonb_array_elements(p_products) p
  ) THEN
    RETURN jsonb_build_object('code',200,'data',v_old_data, 'message', 'No changes detected.');
  END IF;

  /* 1) old subtotal */
  SELECT COALESCE(SUM((p->>'price')::numeric), 0)
  INTO v_sum_old
  FROM jsonb_array_elements(v_old_products) AS p;

  /* 2) new products JSON + subtotal (FIXED HERE) */
  -- We now find the matching old product and merge it (||) with the new data.
  -- This preserves 'spot_title', 'spot_id' or any other extra fields.
  SELECT
    jsonb_agg(
      -- Start with the old product object if it exists (for this ID)
      COALESCE(
        (
           SELECT old_p
           FROM jsonb_array_elements(v_old_products) AS old_p
           WHERE (old_p->>'id')::bigint = p_info.id
           LIMIT 1
        ),
        '{}'::jsonb
      )
      ||
      -- Overwrite with refreshed/new standard fields
      jsonb_build_object(
        'id',            p_info.id,
        'type',          pt.type,
        'price',         (p_new.data->>'price')::numeric, -- Use price from input
        'title',         p_info.title,
        'type_title',    pt.title,
        'currency_code', p_info.currency_code
      )
    ),
    COALESCE(SUM((p_new.data->>'price')::numeric), 0)
  INTO v_products_json, v_sum_new
  FROM jsonb_array_elements(p_products) AS p_new(data)
  JOIN eshop.products           AS p_info ON p_info.id = (p_new.data->>'id')::bigint
  LEFT JOIN eshop.product_types AS pt     ON pt.id = p_info.product_type
  WHERE p_info.occasion = v_occasion_id;

  v_products_json := COALESCE(v_products_json, '[]'::jsonb);

  /* 3) rewrite just that ticket’s products array in orders.data */
  SELECT jsonb_set(
    v_old_data,
    '{tickets}',
    (
      SELECT jsonb_agg(
        CASE WHEN (tckt->>'id')::bigint = p_ticket_id
             THEN jsonb_set(tckt, '{products}', v_products_json)
             ELSE tckt
        END
      )
      FROM jsonb_array_elements(v_old_data->'tickets') AS tckt
    )
  ) INTO v_new_data;

  UPDATE eshop.orders
     SET data = v_new_data
   WHERE id = v_order_id;

  /* Update the ticket timestamp */
  UPDATE eshop.tickets
     SET updated_at = now()
   WHERE id = p_ticket_id;

  /* 4) granularly update the link‐table rows */
  v_old_ids := COALESCE(v_old_ids, ARRAY[]::bigint[]);
  v_new_ids := COALESCE(v_new_ids, ARRAY[]::bigint[]);

  -- Before deleting order_product_ticket rows, nullify the reference in eshop.spots
  UPDATE eshop.spots s
     SET order_product_ticket = NULL
  WHERE s.order_product_ticket IN (
      SELECT opt.id
      FROM eshop.order_product_ticket opt
      WHERE opt.ticket = p_ticket_id
        AND opt.product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids))
  );

  -- Delete link-table rows for products that were removed.
  DELETE FROM eshop.order_product_ticket
  WHERE ticket = p_ticket_id
    AND product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids));

  -- Insert new link-table rows for products that were added.
  INSERT INTO eshop.order_product_ticket ("order", ticket, product)
  SELECT v_order_id, p_ticket_id, new_pid
    FROM (SELECT unnest FROM unnest(v_new_ids) EXCEPT SELECT unnest FROM unnest(v_old_ids)) AS t(new_pid)
  ON CONFLICT DO NOTHING;

  /* 5) adjust payment_info.amount and order.price by the delta */
  v_diff := v_sum_new - v_sum_old;
  IF v_diff <> 0 THEN
      UPDATE eshop.payment_info
         SET amount = amount + v_diff
       WHERE id = v_payment_info_id;
      UPDATE eshop.orders
         SET price      = COALESCE(price,0) + v_diff,
             updated_at = now()
       WHERE id = v_order_id;
  END IF;

  /* 5a) the shared owner decides eligibility and owns one invalidation. */
  v_reconciliation := public.reconcile_order_payment_internal_v1(v_order_id,'product_edit');
  SELECT price INTO v_price FROM eshop.orders WHERE id=v_order_id;

  IF v_price > 0 THEN
    -- If there's a balance due, set/update the payment deadline.
    SELECT elem INTO v_form_settings
    FROM jsonb_array_elements(v_occasion_features) AS elem
    WHERE elem->>'code' = 'form';

    v_deadline_duration_seconds := COALESCE(
        (v_form_settings->>'deadline_duration_seconds')::bigint,
        604800 -- Default to 7 days (604800 seconds) if not specified
    );

    v_new_deadline := now() + make_interval(secs => v_deadline_duration_seconds);
    PERFORM public.set_payment_deadline(v_payment_info_id, v_new_deadline);
  ELSE
    -- If the order is free or paid off, clear the payment deadline.
    PERFORM public.set_payment_deadline(v_payment_info_id, NULL);
  END IF;

  PERFORM public.apply_allocations(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_reconciliation->>'final_state',
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

  RETURN jsonb_build_object('code',200,'data',v_new_data);
END;
$$;

-- The receipted Client Sync command must use the same payment and email
-- transition as the legacy RPC, rather than its pre-email-cutover copy.
CREATE OR REPLACE FUNCTION public.update_ticket_products_internal_v1(
  p_ticket_id bigint, p_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
  RETURN public.update_ticket_products_wsv2(p_ticket_id, p_products);
END;
$$;
REVOKE ALL ON FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  FROM PUBLIC, anon, authenticated;

-- SOURCE: eshop_payment_references/replay.sql
-- Called only after the originating receipt's actor/hash checks. No new public
-- order-ID lookup or capability is introduced; the receipt itself stays immutable.
CREATE OR REPLACE FUNCTION public.project_local_payment_reference_order_internal(p_response jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=CASE WHEN p_response ? 'data' THEN p_response->'data' ELSE p_response END;
 target eshop.orders; payment eshop.payment_info; details jsonb;
BEGIN
 IF payload#>>'{order,id}' IS NULL THEN RETURN p_response; END IF;
 SELECT * INTO target FROM eshop.orders WHERE id=(payload#>>'{order,id}')::bigint;
 IF target.id IS NULL OR target.state='storno' THEN
  payload:=jsonb_set(payload,'{order,payment_info}','null')||jsonb_build_object('code',409,'errorCode','ORDER_NOT_PAYABLE');
 ELSE
  SELECT * INTO payment FROM eshop.payment_info WHERE id=target.payment_info;
  IF payment.id IS NOT NULL THEN
   details:=coalesce(payload#>'{order,payment_info}','{}')||jsonb_build_object('id',payment.id,'variable_symbol',payment.variable_symbol,
    'creditor_reference',payment.creditor_reference,'amount',payment.amount,'deposit_amount',payment.deposit_amount,
    'deadline',payment.deadline,'deposit_deadline',payment.deposit_deadline,'currency_code',payment.currency_code);
   payload:=jsonb_set(payload,'{order,payment_info}',details);
   IF payment.payment_method<>'bank' THEN
    payload:=payload||jsonb_build_object('payment',public.provider_order_payment_projection_internal(target.id));
   END IF;
  END IF;
 END IF;
 IF p_response ? 'data' THEN RETURN jsonb_set(p_response,'{data}',payload); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.project_local_payment_reference_order_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_transactions/apply_transaction_pairing.sql
CREATE OR REPLACE FUNCTION public.apply_transaction_pairing(
  p_transaction_id bigint,
  p_payment_info_id bigint,
  p_method text,
  p_actor_kind text DEFAULT 'system',
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_target eshop.payment_info%ROWTYPE;
  v_old_payment_info_id bigint;
  v_order_id bigint;
  v_order_ids bigint[];
  v_order_bindings jsonb;
  v_locked_order_bindings jsonb;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id));
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
  IF p_method IS NULL OR p_method !~ '^[a-z0-9_]{1,64}$' THEN
    RAISE EXCEPTION 'PAIRING_INVALID_METHOD';
  END IF;
  IF p_actor_kind NOT IN ('service', 'user', 'system') THEN
    RAISE EXCEPTION 'PAIRING_INVALID_ACTOR_KIND';
  END IF;

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_TRANSACTION_NOT_FOUND'; END IF;
  v_old_payment_info_id := v_transaction.payment_info;

  -- The transaction row stabilizes the old target (also held by ingest/matcher).
  -- Acquire every stored old/new form and order before either payment row,
  -- matching product edit and cancellation. Never trust a caller's scope list.
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]),
    coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_order_ids,v_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  PERFORM public.lock_order_capacity_scope_internal(v_order_ids);
  SELECT coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_locked_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  IF v_order_bindings IS DISTINCT FROM v_locked_order_bindings THEN
    RAISE EXCEPTION 'PAIRING_ORDER_SCOPE_CHANGED' USING ERRCODE='40001';
  END IF;
  PERFORM 1 FROM eshop.payment_info WHERE id IN (v_old_payment_info_id,p_payment_info_id)
  ORDER BY id FOR UPDATE;

  IF p_actor_kind='user' THEN
    FOR v_order_id IN SELECT id FROM eshop.orders
      WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id) ORDER BY id LOOP
      PERFORM public.check_order_is_mutable(v_order_id);
    END LOOP;
  END IF;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF v_target.payment_method<>'bank' THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF upper(trim(v_transaction.currency::text)) <> upper(trim(v_target.currency_code::text)) THEN
      RAISE EXCEPTION 'PAIRING_CURRENCY_MISMATCH';
    END IF;
    IF v_transaction.transaction_type IS DISTINCT FROM 'manual'
       AND v_transaction.bank_account_id <> v_target.bank_account
       AND NOT public.bank_sync_accounts_match(p_transaction_id,v_target.bank_account) THEN
      RAISE EXCEPTION 'PAIRING_BANK_ACCOUNT_MISMATCH';
    END IF;
  END IF;

  UPDATE eshop.transactions SET payment_info = p_payment_info_id WHERE id = p_transaction_id;

  IF v_old_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(v_old_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(p_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind, details
  ) VALUES (
    p_transaction_id, p_transaction_id, v_old_payment_info_id,
    p_payment_info_id, CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    p_method, auth.uid(), p_actor_kind, COALESCE(p_details, '{}'::jsonb)
  );

  RETURN jsonb_build_object('status', CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    'transaction_id', p_transaction_id, 'payment_info_id', p_payment_info_id);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_transaction_pairing(bigint,bigint,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

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
   ELSE public.payment_provider_call_internal(payment_method,'totals',jsonb_build_object('paymentId',id)) END facts FROM p),
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

-- SOURCE: eshop_waitlist/accept_offer.sql
CREATE OR REPLACE FUNCTION public.validate_waitlist_answers_internal(p_form bigint,p_input jsonb,p_people jsonb,p_waitlist boolean)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.form_fields; person jsonb; values jsonb; k text; max_people integer; email text;
BEGIN
 IF nullif(p_input->>'email','') IS NOT NULL AND NOT public.email_address_is_valid(p_input->>'email') THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','INVALID_EMAIL')::text; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND type='email' AND NOT is_hidden
 AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  FOR email IN
   SELECT answer->>k FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE NOT f.is_ticket_field AND answer ? k
   UNION ALL
   SELECT answer->>k FROM jsonb_array_elements(coalesce(p_people,'[]')) participant(value),
    LATERAL jsonb_array_elements(coalesce(participant.value->'fields','[]')) answer WHERE f.is_ticket_field AND answer ? k
  LOOP
   IF nullif(email,'') IS NOT NULL AND NOT public.email_address_is_valid(email) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','INVALID_EMAIL','fieldId',f.id)::text; END IF;
  END LOOP;
 END LOOP;
 IF jsonb_typeof(p_people)<>'array' OR jsonb_array_length(p_people)<1 OR jsonb_array_length(p_people)>public.ticket_order_limit() THEN
  RAISE EXCEPTION 'Invalid participant count'; END IF;
 SELECT min((data->>'max_tickets')::integer) INTO max_people FROM public.form_fields WHERE form=p_form AND type='ticket';
 IF jsonb_array_length(p_people)>coalesce(max_people,public.ticket_order_limit()) THEN RAISE EXCEPTION 'Maximum participants exceeded'; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND is_required AND NOT is_hidden
 AND type NOT IN ('ticket','html','product_type') AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  IF f.is_ticket_field THEN
   FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
    -- Selected seats use the ticket's top-level spot transport. The finalizer
    -- checks occasion ownership, availability and reservation secret afterward.
    IF f.type='spot' AND (p_waitlist OR nullif(person->>'spot','') IS NOT NULL) THEN
     CONTINUE;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(person->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
     RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
   END LOOP;
  ELSE
   IF nullif(p_input->>f.type,'') IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
  END IF;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.accept_waitlist_offer_internal(p_payload jsonb,p_command uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE w eshop.waitlist_offers; o eshop.orders; fid bigint; target bigint; ids bigint[]; selected_slots uuid[];
 n integer; remaining integer; result jsonb; input jsonb; old_tickets jsonb; old_slots jsonb; old_links jsonb; conversion text;
 original_group jsonb; remaining_group jsonb; accepted_group jsonb; history_snapshot jsonb;
BEGIN
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=(p_payload->>'offerId')::uuid;
 fid:=public.check_waitlist_scope_internal(w.order_id,w.id,p_payload->>'token',p_actor,'accept');
 PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=w.order_id)]);
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[w.order_id]);
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=w.id FOR UPDATE;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=w.order_id;
 PERFORM public.expire_waitlist_form_internal(fid);
 IF w.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 IF o.state<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 SELECT array_agg(x::bigint) INTO ids FROM jsonb_array_elements_text(p_payload->'ticketIds') x;
 n:=coalesce(cardinality(ids),0);
 IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(ids) x) THEN RAISE EXCEPTION 'Invalid selected persons'; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id) ORDER BY id FOR UPDATE;
 original_group:=public.snapshot_waitlist_tickets_internal(o.id);
 IF n<>(SELECT count(*) FROM public.get_order_tickets_internal(o.id) p WHERE p.id=ANY(ids) AND state='waitlisted'
 AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE s.ticket_id=p.id AND s.outcome='pending' AND s.offer_id<>w.id)) THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Preserve slots already attached to selected people, then exchange only the necessary unused bindings.
 SELECT array_agg(id ORDER BY CASE WHEN ticket_id=ANY(ids) THEN 0 ELSE 1 END,id) INTO selected_slots
 FROM (SELECT * FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending'
 ORDER BY CASE WHEN ticket_id=ANY(ids) THEN 0 ELSE 1 END,id LIMIT n FOR UPDATE) s;
 IF coalesce(cardinality(selected_slots),0)<>n THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 -- Journal the exact pre-swap bindings, including displaced offered people.
 SELECT jsonb_agg(to_jsonb(p)) INTO old_tickets FROM eshop.tickets p
 WHERE id=ANY(ids) OR id IN(SELECT ticket_id FROM eshop.waitlist_offer_slots WHERE id=ANY(selected_slots));
 SELECT jsonb_agg(to_jsonb(s)) INTO old_slots FROM eshop.waitlist_offer_slots s WHERE id=ANY(selected_slots);
 SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO old_links FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=ANY(ids);
 -- Release temporary bindings using a terminal outcome so the pending uniqueness invariant never needs deferral.
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(selected_slots);
 WITH persons AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(ids) id), slots AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(selected_slots) id)
 UPDATE eshop.waitlist_offer_slots s SET ticket_id=p.id FROM persons p JOIN slots x USING(n) WHERE s.id=x.id;
 SELECT count(*) INTO remaining FROM public.get_order_tickets_internal(o.id) WHERE state='waitlisted';
 conversion:=CASE WHEN remaining=n THEN 'in_place' ELSE 'split' END;
 target:=CASE WHEN conversion='in_place' THEN o.id ELSE public.allocate_ticket_order_identity_internal(fid) END;
 IF conversion='split' THEN UPDATE eshop.orders SET source_waitlist_order_id=o.id WHERE id=target; END IF;
 input:=p_payload->'orderDetails';
 input:=jsonb_set(input,'{ticket}',public.normalize_form_ticket_answers_internal(fid,input->'ticket'));
 IF (input->>'form')::uuid IS DISTINCT FROM (SELECT key FROM public.forms WHERE id=fid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF jsonb_array_length(input->'ticket')<>n THEN RAISE EXCEPTION 'Selected people and tickets differ'; END IF;
 -- Each selected person must explicitly bind their stable ID to their submitted ticket.
 IF n<>(SELECT count(DISTINCT (t->>'ticketId')::bigint) FROM jsonb_array_elements(input->'ticket') t WHERE (t->>'ticketId')::bigint=ANY(ids)) THEN
  RAISE EXCEPTION 'Invalid participant ticket binding'; END IF;
 PERFORM public.validate_waitlist_answers_internal(fid,input,input->'ticket',false);
 UPDATE eshop.order_product_ticket SET "order"=target WHERE "order"=o.id AND ticket=ANY(ids);
 result:=public.finalize_ticket_order_internal_v1(target,public.strip_payment_sources_internal(input),true);
 IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted',resulting_order_id=target,updated_at=clock_timestamp() WHERE id=ANY(selected_slots);
 PERFORM public.attach_provider_order_source_internal(target,p_command,input);
 PERFORM public.enqueue_ticket_order_confirmation_v1(p_command,o.occasion,result,input->>'lang');
 IF (SELECT state='preparing_payment' FROM eshop.orders WHERE id=target) THEN
  INSERT INTO eshop.waitlist_acceptance_attempts(command_id,source_order_id,target_order_id,offer_id,conversion,ticket_ids,slot_ids,previous_order_data,previous_tickets,previous_links,previous_slots)
  VALUES(p_command,o.id,target,w.id,conversion,ids,selected_slots,to_jsonb(o),old_tickets,old_links,old_slots);
 ELSE
  UPDATE eshop.waitlist_capabilities SET revoked_at=clock_timestamp() WHERE offer_id=w.id
   AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending');
 END IF;
 remaining_group:=CASE WHEN conversion='split' THEN public.snapshot_waitlist_tickets_internal(o.id) ELSE '[]'::jsonb END;
 accepted_group:=public.snapshot_waitlist_tickets_internal(target);
 history_snapshot:=jsonb_build_object('action','waitlist_accept','commandId',p_command,'sourceOrderId',o.id,
  'targetOrderId',target,'ticketIds',ids,'conversion',conversion,'ticketsBefore',original_group,
  'ticketsAfter',remaining_group,'acceptedTickets',accepted_group);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(o.id,(SELECT state FROM eshop.orders WHERE id=o.id),history_snapshot);
 IF conversion='split' THEN
  INSERT INTO eshop.orders_history("order",state,data) VALUES(target,(SELECT state FROM eshop.orders WHERE id=target),history_snapshot);
 END IF;
 RETURN result||jsonb_build_object('sourceOrderId',o.id,'conversion',conversion,'waitlistSummary',public.get_waitlist_summary_internal(o.id));
END $$;
REVOKE ALL ON FUNCTION public.validate_waitlist_answers_internal(bigint,jsonb,jsonb,boolean),public.accept_waitlist_offer_internal(jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop_waitlist/commands.sql
-- Edge is the trusted preparation boundary for random capabilities and sealed email.
-- It verifies the bearer user; SQL still checks the explicit actor's occasion rights.
CREATE OR REPLACE FUNCTION public.sanitize_waitlist_history_internal(p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(key,public.sanitize_waitlist_history_internal(value)),'{}') INTO result
  FROM jsonb_each(p_value) WHERE lower(key) NOT IN
   ('token','secret','password','offertoken','managetoken','capability','waitlistenvelope','sealed','tokenhash') AND lower(key) NOT IN(SELECT lower(source_field) FROM eshop.payment_providers WHERE source_field IS NOT NULL);
  RETURN result;
 ELSIF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(value) ORDER BY ordinal),'[]') INTO result
  FROM jsonb_array_elements(p_value) WITH ORDINALITY item(value,ordinal);
  RETURN result;
 END IF;
 RETURN p_value;
END $$;
CREATE OR REPLACE FUNCTION public.snapshot_waitlist_tickets_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(to_jsonb(p)||jsonb_build_object('answers',p.data,'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(p.id))) ORDER BY created_at,id),'[]')
 FROM public.get_order_tickets_internal(p_order) p;
$$;
REVOKE ALL ON FUNCTION public.sanitize_waitlist_history_internal(jsonb),public.snapshot_waitlist_tickets_internal(bigint)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.execute_waitlist_command_client_sync_v1(
 p_operation text,p_payload jsonb,p_command_id uuid,p_client_id uuid,p_actor uuid DEFAULT NULL,p_deliveries jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; occ bigint; oid bigint; offer uuid; mode text; c jsonb; result jsonb; claim jsonb;
 hash text; selected bigint[]; expected integer; changed integer; recipients jsonb; r jsonb; delivery jsonb;
 person jsonb; created_ticket bigint; slot_ids uuid[]; expiry timestamptz; f public.forms; people jsonb; n integer; before_users uuid[];
 previous_sub text; actor_kind text; o eshop.orders; entity_changes jsonb:='[]';
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_operation NOT IN ('register','send','accept','decline','cancel','withdraw') OR p_command_id IS NULL OR p_client_id IS NULL
 OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4194304 THEN RAISE EXCEPTION 'Invalid waitlist command'; END IF;
 IF p_operation='register' THEN SELECT id INTO fid FROM public.forms WHERE key=(p_payload->>'form')::uuid;
 ELSIF p_operation='send' THEN fid:=(p_payload->>'formId')::bigint;
 ELSIF p_operation='withdraw' THEN oid:=(p_payload->>'orderId')::bigint; SELECT form INTO fid FROM eshop.orders WHERE id=oid;
 ELSE offer:=(p_payload->>'offerId')::uuid; SELECT order_id,form_id INTO oid,fid FROM eshop.waitlist_offers WHERE id=offer; END IF;
 SELECT * INTO f FROM public.forms WHERE id=fid; occ:=f.occasion;
 PERFORM public.check_occasion_writable(occ);
 IF occ IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Match checkout and cancellation: scope precedes the form/order parents.
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 IF p_operation IN ('send','cancel') AND NOT public.can_write_orders_as_actor_internal(p_actor,occ) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 previous_sub:=current_setting('request.jwt.claim.sub',true);
 PERFORM set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
 hash:=encode(extensions.digest(jsonb_build_object('operation',p_operation,'payload',CASE WHEN p_payload ? 'orderDetails' THEN jsonb_set(p_payload,'{orderDetails}',public.strip_payment_sources_internal(p_payload->'orderDetails')) ELSE p_payload END,'actor',p_actor)::text,'sha256'),'hex');
 BEGIN
  IF p_actor IS NULL THEN claim:=public.begin_anonymous_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_client_id,hash); actor_kind:='unknown';
  ELSE claim:=public.begin_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_actor,hash); actor_kind:='user'; END IF;
 EXCEPTION WHEN invalid_parameter_value THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  RETURN jsonb_build_object('code',409,'errorCode','COMMAND_PAYLOAD_CONFLICT');
 END;
 IF claim->>'disposition'='replay' THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN public.project_local_payment_reference_order_internal(claim->'response'); END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO before_users FROM public.occasion_users WHERE occasion=occ;
 BEGIN
  PERFORM 1 FROM public.forms WHERE id=fid FOR UPDATE;
 IF p_operation IN ('accept','decline','cancel','withdraw') THEN
  PERFORM public.check_waitlist_scope_internal(oid,offer,p_payload->>'token',p_actor,p_operation); END IF;

  PERFORM public.expire_waitlist_form_internal(fid);
  c:=public.get_form_capacity_snapshot_internal(fid);
  IF p_operation='register' THEN
   mode:=public.get_form_registration_mode_internal(fid);
   IF mode<>'waitlist' THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   people:=public.normalize_form_ticket_answers_internal(fid,p_payload->'tickets');
   PERFORM public.validate_waitlist_answers_internal(fid,p_payload,people,true);
   IF nullif(p_payload->>'email','') IS NULL THEN RAISE EXCEPTION 'Email required'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(people) p CROSS JOIN LATERAL jsonb_array_elements(coalesce(p->'fields','[]')) a WHERE a ? 'product_type') THEN
    RAISE EXCEPTION 'Waitlist does not accept products'; END IF;
   oid:=public.allocate_ticket_order_identity_internal(fid);
   UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=p_payload-'tickets'-'token' WHERE id=oid;
   FOR person IN SELECT * FROM jsonb_array_elements(people) LOOP
    INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data,waitlist_queue_at)
     VALUES(occ,'waitlisted',NULL,public.extract_ticket_answers_internal(fid,person),clock_timestamp()) RETURNING id INTO created_ticket;
    INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,created_ticket,NULL); END LOOP;
   result:=jsonb_build_object('code',200,'order',jsonb_build_object('id',oid,'order_symbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),'state','waitlisted','payment_info',NULL,'price',NULL),
    'waitlistSummary',public.get_waitlist_summary_internal(oid),'email',public.enqueue_waitlist_email_internal(oid,NULL,p_command_id,p_deliveries->0));
  ELSIF p_operation='send' THEN
   SELECT * INTO f FROM public.forms WHERE id=fid;
   IF NOT f.waitlist_enabled THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   IF f.capacity_revision<>(p_payload->>'revision')::bigint THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','OFFER_CHANGED','capacity',c)::text; END IF;
   expiry:=(p_payload->>'expiresAt')::timestamptz;
   IF expiry IS NULL OR expiry<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
   recipients:=p_payload->'recipients';
   IF jsonb_typeof(recipients)<>'array' OR jsonb_array_length(recipients)<1 OR
    jsonb_array_length(recipients)<>(SELECT count(DISTINCT x->>'orderId') FROM jsonb_array_elements(recipients) x) THEN RAISE EXCEPTION 'Invalid recipients'; END IF;
   SELECT sum((x->>'count')::integer) INTO n FROM jsonb_array_elements(recipients) x;
   IF n>(c->>'offerablePlaces')::integer THEN RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
   PERFORM 1 FROM eshop.orders WHERE id IN(SELECT (x->>'orderId')::bigint FROM jsonb_array_elements(recipients) x) ORDER BY id FOR UPDATE;
   result:=jsonb_build_object('code',200,'offers','[]'::jsonb);
   FOR r IN SELECT * FROM jsonb_array_elements(recipients) ORDER BY (value->>'orderId')::bigint LOOP
    oid:=(r->>'orderId')::bigint; n:=(r->>'count')::integer;
    IF n<1 OR NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND form=fid AND state='waitlisted') THEN RAISE EXCEPTION 'Invalid recipient scope'; END IF;
    SELECT array_agg(id) INTO selected FROM (SELECT p.id FROM eshop.tickets p WHERE p.state='waitlisted'
     AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=p.id AND x."order"=oid)
     AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE ticket_id=p.id AND outcome='pending')
     ORDER BY waitlist_queue_at,created_at,id LIMIT n FOR UPDATE) tickets;
    IF coalesce(cardinality(selected),0)<>n THEN RAISE EXCEPTION 'OFFER_CHANGED'; END IF;
    INSERT INTO eshop.waitlist_offers(order_id,form_id,created_by,expires_at,revision) VALUES(oid,fid,p_actor,expiry,f.capacity_revision) RETURNING id INTO offer;
    INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id) SELECT offer,id,fid FROM unnest(selected) id;
    SELECT x INTO delivery FROM jsonb_array_elements(p_deliveries) x WHERE (x->>'orderId')::bigint=oid;
    result:=jsonb_set(result,'{offers}',result->'offers'||jsonb_build_array(jsonb_build_object('orderId',oid,'offerId',offer,'count',n,'expiresAt',expiry,
     'email',public.enqueue_waitlist_email_internal(oid,offer,p_command_id,delivery))));
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,'waitlisted',jsonb_build_object('action','offer_sent','offerId',offer,'count',n,'expiresAt',expiry));
    entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist offer','changedFields',jsonb_build_array('waitlistSummary')));
   END LOOP;
  ELSIF p_operation='accept' THEN
   result:=public.accept_waitlist_offer_internal(p_payload,p_command_id,p_actor);
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',result#>>'{order,id}','operation','update','safeLabel','Accepted order','changedFields',jsonb_build_array('state','tickets','products','allocations')));
  ELSE
   PERFORM public.lock_order_capacity_scope_internal(ARRAY[oid]);
   IF (SELECT state FROM eshop.orders WHERE id=oid)<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   SELECT array_agg(x::bigint) INTO selected FROM jsonb_array_elements_text(p_payload->'ticketIds') x; n:=coalesce(cardinality(selected),0);
   IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(selected) x) THEN RAISE EXCEPTION 'Invalid persons'; END IF;
   IF n<>(SELECT count(*) FROM public.get_order_tickets_internal(oid) WHERE id=ANY(selected) AND state='waitlisted') THEN
    RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   IF p_operation IN ('decline','cancel') AND n<>(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=offer AND outcome='pending' AND ticket_id=ANY(selected)) THEN
    RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   UPDATE eshop.waitlist_offer_slots SET outcome=CASE WHEN p_operation='decline' THEN 'declined' ELSE 'cancelled' END,updated_at=clock_timestamp()
    WHERE ticket_id=ANY(selected) AND outcome='pending' AND (p_operation='withdraw' OR offer_id=offer);
   UPDATE eshop.tickets SET state=CASE WHEN p_operation='withdraw' THEN 'storno' ELSE state END,
    waitlist_queue_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=ANY(selected);
   UPDATE eshop.waitlist_capabilities cap SET revoked_at=clock_timestamp() WHERE cap.order_id=oid AND kind='offer' AND NOT EXISTS
    (SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=cap.offer_id AND outcome='pending');
   result:=jsonb_build_object('code',200,'orderId',oid,'waitlistSummary',public.get_waitlist_summary_internal(oid));
  END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=fid;
  IF p_operation<>'send' THEN
   -- Acceptance owns its richer before/after snapshot at the same transaction
   -- boundary; avoid a second action-only row hiding that record in the detail.
   IF p_operation<>'accept' THEN
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,(SELECT state FROM eshop.orders WHERE id=oid),
     jsonb_build_object('action','waitlist_'||p_operation,'commandId',p_command_id,
     'ticketIds',CASE WHEN p_operation='register' THEN
       (SELECT jsonb_agg(id ORDER BY created_at,id) FROM public.get_order_tickets_internal(oid))
       ELSE to_jsonb(selected) END,
     'tickets',public.snapshot_waitlist_tickets_internal(oid)));
   END IF;
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist order','changedFields',jsonb_build_array('waitlistSummary','tickets')));
  END IF;
  IF p_operation='register' THEN
   PERFORM public.notification_center_order_internal(oid,'waitlist_registered','created',p_actor);
  ELSIF p_operation='accept' THEN
   PERFORM public.notification_center_order_internal((result#>>'{order,id}')::bigint,'offer_accepted',offer::text||':'||p_command_id,p_actor,
    jsonb_build_object('offerId',offer,'count',jsonb_array_length(p_payload->'ticketIds')));
  ELSIF p_operation='withdraw' THEN
   PERFORM public.notification_center_order_internal(oid,'order_cancelled','withdraw:'||p_command_id,p_actor,jsonb_build_object('count',n));
  ELSIF p_operation='decline' THEN
   PERFORM public.notification_center_order_internal(oid,'offer_declined',offer::text||':'||p_command_id,p_actor,jsonb_build_object('offerId',offer,'count',n));
  END IF;
  PERFORM public.notification_center_form_capacity_internal(fid,p_actor);
  result:=result||jsonb_build_object('capacity',public.get_form_capacity_snapshot_internal(fid));
 EXCEPTION WHEN OTHERS THEN
  result:=CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',409,'errorCode',SQLERRM,'message',SQLERRM) END;
  result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
   CASE WHEN (result->>'code')::integer BETWEEN 200 AND 599 THEN (result->>'code')::integer ELSE 409 END,result);
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN result;
 END;
 entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','form','entityId',fid,'operation','update','safeLabel','Form capacity','changedFields',jsonb_build_array('capacity','registrationMode')));
 IF p_operation='accept' AND p_payload ? 'administrativeApproval' THEN
  result:=result||jsonb_build_object('adminQuote',p_payload#>'{administrativeApproval,quote}',
   'adminScope',p_payload#>'{administrativeApproval,scope}','paymentPreparationPolicy','leased_keep_pending'); END IF;
 result:=public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.waitlist.'||p_operation,entity_changes,before_users,result,actor_kind);
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) TO service_role;

-- SOURCE: eshop_waitlist/order_overview.sql
-- Private pure projection. No matcher, paid transition or payment side effect.
CREATE OR REPLACE FUNCTION public.customer_order_payment_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH facts AS (
 SELECT o.*,p.payment_method,p.amount,coalesce(p.paid,0) received,coalesce(p.returned,0) returned,
 p.deposit_amount,p.deposit_deadline,p.deadline,p.variable_symbol,p.creditor_reference,
 b.account_number,b.account_number_human_readable,
 coalesce(nullif(trim(b.creditor_name),''),(SELECT left(trim(regexp_replace(org.title,'[[:space:][:cntrl:]]+',' ','g')),70) FROM public.occasions occ JOIN public.organizations org ON org.id=occ.organization WHERE occ.id=o.occasion)) creditor_name,
 CASE WHEN o.state='preparing_payment' THEN 'preparing'
 WHEN o.state='storno' THEN 'cancelled'
 WHEN o.state='waitlisted' AND p.id IS NULL THEN 'not_required_yet'
 WHEN o.price=0 THEN 'free'
 WHEN p.id IS NULL OR p.currency_code IS DISTINCT FROM o.currency_code OR p.amount IS NULL OR p.amount<0 OR coalesce(p.paid,0)<0 OR coalesce(p.paid_externally,0)<>0
  OR (o.state IN ('paid','sent') AND o.price>0 AND coalesce(p.paid,0)=0) THEN 'unknown'
 WHEN coalesce(p.paid,0)>=p.amount THEN 'fully_paid'
 WHEN coalesce(p.paid,0)=0 THEN 'unpaid'
 WHEN p.deposit_amount>0 AND p.paid>=p.deposit_amount THEN 'deposit_paid'
 ELSE 'partially_paid' END status
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info
 LEFT JOIN eshop.bank_accounts b ON b.id=p.bank_account WHERE o.id=p_order),
 due AS (SELECT *,greatest(amount-received,0) outstanding,
 CASE WHEN deposit_amount>received THEN greatest(deposit_amount-received,0) ELSE greatest(amount-received,0) END due_now,
 CASE WHEN deposit_amount>received THEN deposit_deadline ELSE deadline END due_at FROM facts)
 SELECT CASE WHEN payment_method<>'bank' THEN public.provider_order_payment_projection_internal(p_order) ELSE jsonb_build_object('status',status,'amount',amount,'received',received,'returned',returned,
 'totalOutstanding',outstanding,'overpaid',greatest(received-amount,0),'depositAmount',deposit_amount,
 'depositDeadline',deposit_deadline,'finalDeadline',deadline,
 'dueNow',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN due_now ELSE 0 END,
 'dueAt',due_at,'overdue',coalesce(due_at<statement_timestamp() AND due_now>0,false),
 'instructionsAvailable',status IN ('unpaid','partially_paid','deposit_paid') AND account_number IS NOT NULL
  AND CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END,
 'reference',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN
  CASE WHEN currency_code='EUR' THEN creditor_reference ELSE variable_symbol::text END END,
 'qrPayment',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') AND due_now>0 AND account_number IS NOT NULL
  AND CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END
 THEN jsonb_build_object('amount',due_now,'currency_code',trim(currency_code),'account_number',account_number,
  'account_number_human_readable',account_number_human_readable,'creditor_name',creditor_name,
  'variable_symbol',variable_symbol,'creditor_reference',creditor_reference) END,
 'referenceKind',CASE WHEN currency_code='EUR' THEN 'RF' ELSE 'VS' END,
 'transactions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
  'date',t.date::date,'recordedAt',t.created_at,'amount',t.amount,'currency',trim(t.currency),
  'kind',CASE WHEN t.transaction_type='return' THEN 'refund' WHEN t.amount>0 THEN 'payment_received' ELSE 'payment_adjustment' END)
  ORDER BY t.created_at NULLS LAST,t.id),'[]') FROM eshop.transactions t WHERE t.payment_info=due.payment_info),
 'publicAccount',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN coalesce(account_number_human_readable,account_number) END)
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

CREATE OR REPLACE FUNCTION public.get_customer_order_overview(p_token text,p_order_id bigint)
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
 SELECT jsonb_build_object('code',200,'root',jsonb_build_object('id',root.id,'symbol',root.order_symbol,'createdAt',root.created_at,'state',root.state,'title',occ.title,'formLink',f.link,'hasTickets',EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(occ.features,'[]')) feature WHERE feature->>'code'='ticket' AND feature->>'is_enabled'='true')),
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
  SELECT t.created_at,'4'||t.id::text,jsonb_build_object('kind',CASE WHEN t.transaction_type='return' THEN 'refund' WHEN t.amount>0 THEN 'payment_received' ELSE 'payment_adjustment' END,
   'at',t.created_at,'timeKind','recorded','amount',t.amount,'currency',trim(t.currency),'symbol',o.order_symbol,
   'paymentMethod',CASE WHEN b.type='CASH' THEN 'cash' WHEN nullif(trim(b.account_number),'') IS NOT NULL THEN 'bank' END,
   'recipientAccount',CASE WHEN b.type<>'CASH' THEN coalesce(nullif(trim(b.account_number_human_readable),''),nullif(trim(b.account_number),'')) END)
  FROM eshop.orders o JOIN eshop.transactions t ON t.payment_info=o.payment_info LEFT JOIN eshop.bank_accounts b ON b.id=t.bank_account_id WHERE o.id=ANY(ids) AND t.created_at IS NOT NULL
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
REVOKE ALL ON FUNCTION public.get_customer_order_overview(text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_customer_order_overview(text,bigint) TO anon,authenticated,service_role;

-- SOURCE: scanning/admission.sql
-- Parents before ticket, shared by web and retained native/admin writers.
CREATE OR REPLACE FUNCTION public.scanner_lock_ticket_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE parents bigint[]; current_parents bigint[]; parent bigint;
BEGIN
 SELECT array_agg(DISTINCT x."order" ORDER BY x."order") INTO parents FROM eshop.order_product_ticket x WHERE x.ticket=p_ticket;
 PERFORM public.lock_order_capacity_scope_internal(parents);
 FOREACH parent IN ARRAY coalesce(parents,ARRAY[]::bigint[]) LOOP
  PERFORM 1 FROM eshop.orders WHERE id=parent FOR UPDATE;
 END LOOP;
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
 SELECT array_agg(DISTINCT x."order" ORDER BY x."order") INTO current_parents FROM eshop.order_product_ticket x WHERE x.ticket=p_ticket;
 IF parents IS DISTINCT FROM current_parents THEN RAISE serialization_failure USING MESSAGE='ticket_parent_changed'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.scanner_admit_ticket_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_ticket_is_mutable(p_ticket);
 IF NOT public.provider_ticket_admission_allowed_internal(p_ticket) THEN RAISE EXCEPTION 'stripe_admission_hold'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=p_ticket AND state='used') THEN RAISE EXCEPTION 'already_used'; END IF;
 UPDATE eshop.tickets SET state='used',updated_at=clock_timestamp() WHERE id=p_ticket;
END $$;
CREATE OR REPLACE FUNCTION public.lookup_scanner_ticket(p_session uuid,p_token text,p_symbol text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; tid bigint; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 SELECT t.id INTO tid FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol=p_symbol LIMIT 1;
 IF tid IS NULL AND p_symbol ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN
  SELECT t.id INTO tid FROM public.occasion_users ou JOIN eshop.tickets t ON t.id=ou.ticket WHERE ou.occasion=s.occasion_id AND ou."user"=p_symbol::uuid AND t.occasion=s.occasion_id LIMIT 1;
 END IF;
 SELECT dto INTO result FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid) WHERE ticket_id=tid;
 IF result IS NOT NULL THEN result:=result||jsonb_build_object('can_reset_password',public.scanner_can_reset_password_internal(s.occasion_id,tid)); END IF;
 RETURN jsonb_build_object('code',CASE WHEN result IS NULL THEN 404 ELSE 200 END,'reason',CASE WHEN result IS NULL THEN 'not_found' ELSE 'found' END,
 'data',result,'settings_revision',cfg.revision,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.search_scanner_tickets(p_session uuid,p_token text,p_query text,p_after bigint DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token); SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT coalesce((cfg.config#>>'{manual_search,tickets}')::boolean,false) THEN RAISE insufficient_privilege USING MESSAGE='manual_search_disabled'; END IF;
 IF length(p_query) NOT BETWEEN 2 AND 100 THEN RETURN jsonb_build_object('code',400,'reason','invalid_query','server_time',now()); END IF;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT coalesce(jsonb_agg(dto ORDER BY ticket_id),'[]'::jsonb) INTO result FROM (
 SELECT * FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config) WHERE ticket_id>p_after
 AND (strpos(lower(dto->>'holder_name'),lower(p_query))>0 OR strpos(lower(dto->>'batch_title'),lower(p_query))>0 OR strpos(lower(dto->>'symbol'),lower(p_query))>0) ORDER BY ticket_id LIMIT 30) found;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.sync_scanner_operations(p_session uuid,p_token text,p_operations jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; op jsonb; canonical jsonb; h text; prior public.scanner_operations;
 tid bigint; proj jsonb; receipt jsonb; outcome text; reason text; results jsonb:='[]'; existing boolean; snap public.scanner_snapshots;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF p_operations IS NULL OR jsonb_typeof(p_operations)<>'array' OR jsonb_array_length(p_operations) NOT BETWEEN 1 AND 50 OR octet_length(p_operations::text)>262144 THEN
  RETURN jsonb_build_object('code',400,'reason','invalid_batch','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now()); END IF;
 FOR op IN SELECT value FROM jsonb_array_elements(p_operations) LOOP
  IF op->>'action' IS DISTINCT FROM 'admit_ticket' OR op->>'origin_session_id' IS DISTINCT FROM p_session::text
   OR op->>'eligibility_fingerprint' IS NULL OR length(op->>'eligibility_fingerprint')<>64
   OR op->>'operation_id' IS NULL OR op->>'ticket_id' IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid_operation'; END IF;
  tid:=(op->>'ticket_id')::bigint;
  canonical:=jsonb_build_object('operation_id',(op->>'operation_id')::uuid,'origin_session_id',p_session,'occasion_id',s.occasion_id,
   'ticket_id',tid,'action','admit_ticket','snapshot_id',op->'snapshot_id','settings_revision',op->'settings_revision',
   'eligibility_fingerprint',op->'eligibility_fingerprint','confirm_unpaid',coalesce((op->>'confirm_unpaid')::boolean,false),'captured_at',op->'captured_at');
  h:=encode(digest(canonical::text,'sha256'),'hex');
  -- Serializes global identity before any domain mutation. No incomplete receipt survives a transaction.
  PERFORM pg_advisory_xact_lock(hashtextextended(op->>'operation_id',5317));
  SELECT * INTO prior FROM public.scanner_operations WHERE operation_id=(op->>'operation_id')::uuid;
  IF FOUND THEN
   IF prior.session_id<>p_session OR prior.payload_hash<>h THEN
    results:=results||jsonb_build_array(jsonb_build_object('operation_id',op->>'operation_id','outcome','rejected','reason','operation_payload_mismatch'));
   ELSE results:=results||jsonb_build_array(prior.receipt||jsonb_build_object('replayed',true)); END IF;
   CONTINUE;
  END IF;
  IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN
   RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now());
  END IF;
  outcome:='rejected'; reason:='not_found'; proj:=NULL;
  IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=tid AND occasion=s.occasion_id) THEN
   PERFORM public.scanner_lock_ticket_internal(tid);
   PERFORM public.check_occasion_writable(s.occasion_id);
   SELECT dto INTO proj FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid);
   IF op->>'snapshot_id' IS NOT NULL AND coalesce((proj->>'online_required')::boolean,false) THEN reason:='online_required';
   ELSIF proj->>'state'='used' THEN outcome:='conflict'; reason:='already_used';
   ELSIF proj->>'state' IN ('storno','waitlisted') OR NOT coalesce((proj->>'admission_allowed')::boolean,false) THEN reason:='admission_not_allowed';
   ELSIF proj->>'eligibility_fingerprint' IS DISTINCT FROM op->>'eligibility_fingerprint' THEN outcome:='conflict'; reason:='eligibility_changed';
   ELSIF (proj->>'requires_unpaid_confirmation')::boolean AND (NOT coalesce((op->>'confirm_unpaid')::boolean,false) OR op->>'snapshot_id' IS NOT NULL) THEN reason:='unpaid_confirmation_required';
   ELSE
    reason:='admitted'; outcome:='accepted';
    IF op->>'snapshot_id' IS NOT NULL THEN
     SELECT * INTO snap FROM public.scanner_snapshots WHERE id=(op->>'snapshot_id')::uuid AND session_id=p_session;
     IF snap.id IS NULL OR snap.expires_at<=now() OR s.offline_until<=now() OR NOT EXISTS(
      SELECT 1 FROM public.scanner_snapshot_pages pg CROSS JOIN LATERAL jsonb_array_elements(pg.payload_text::jsonb) item
      WHERE pg.snapshot_id=snap.id AND item->>'ticket_id'=tid::text AND item->>'eligibility_fingerprint'=op->>'eligibility_fingerprint') THEN
      outcome:='conflict'; reason:='offline_grant_invalid'; END IF;
    END IF;
    IF outcome='accepted' THEN
     PERFORM public.scanner_admit_ticket_internal(tid);
    END IF;
   END IF;
  END IF;
  receipt:=jsonb_build_object('operation_id',op->>'operation_id','ticket_id',tid,'outcome',outcome,'reason',reason,
   'committed_at',clock_timestamp(),'eligibility_fingerprint',op->>'eligibility_fingerprint');
  INSERT INTO public.scanner_operations(operation_id,session_id,occasion_id,ticket_id,payload_hash,payload,receipt)
   VALUES((op->>'operation_id')::uuid,p_session,s.occasion_id,tid,h,canonical,receipt);
  results:=results||jsonb_build_array(receipt);
 END LOOP;
 RETURN jsonb_build_object('code',200,'data',results,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_receipts(p_session uuid,p_token text,p_operation_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token,true);
 IF coalesce(array_length(p_operation_ids,1),0)>50 THEN RAISE invalid_parameter_value; END IF;
 -- Expired/revoked devices can reconcile their immutable history, never perform a new write.
 SELECT coalesce(jsonb_agg(receipt),'[]'::jsonb) INTO result FROM public.scanner_operations WHERE session_id=p_session AND operation_id=ANY(p_operation_ids);
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_summary(p_session uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 WITH eligible AS MATERIALIZED (
 SELECT t.id,t.state FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol IS NOT NULL
 AND t.state IN ('used','paid','sent','ordered') AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=t.id)
 AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" WHERE z.ticket=t.id AND (o.state IN ('stock','storno','waitlisted','preparing_payment') OR o.occasion<>s.occasion_id)))
 SELECT jsonb_build_object('used_current',count(*) FILTER(WHERE state='used'),'unused_eligible',count(*) FILTER(WHERE state IN ('paid','sent')),
 'eligible_total',count(*) FILTER(WHERE state IN ('used','paid','sent')),'unpaid_conditional',count(*) FILTER(WHERE state='ordered'),
 -- Count the same ticket population as the offline projection, including unpaid/stock records.
 'snapshot_ticket_count',(SELECT count(*) FROM eshop.tickets t WHERE t.occasion=s.occasion_id
 AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" WHERE z.ticket=t.id)),
 'definition_version',1,'definition','used + paid/sent; excludes conditional unpaid, cancelled and waitlisted',
 'server_time',now(),'settings_revision',(SELECT revision FROM public.scanner_settings WHERE occasion_id=s.occasion_id)) INTO result FROM eligible;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.resolve_scanner_conflict(p_operation uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE op public.scanner_operations;
BEGIN
 SELECT * INTO STRICT op FROM public.scanner_operations WHERE operation_id=p_operation;
 PERFORM public.check_is_editor_order_on_occasion(op.occasion_id);
 IF auth.uid() IS NULL OR op.receipt->>'outcome'<>'conflict' THEN RAISE insufficient_privilege; END IF;
 INSERT INTO public.scanner_conflict_resolutions(operation_id,actor_user_id,reason) VALUES(p_operation,auth.uid(),p_reason) ON CONFLICT DO NOTHING;
 RETURN jsonb_build_object('code',200,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.lookup_scanner_ticket(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lookup_scanner_ticket(uuid,text,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.search_scanner_tickets(uuid,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.search_scanner_tickets(uuid,text,text,bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.sync_scanner_operations(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.sync_scanner_operations(uuid,text,jsonb) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_receipts(uuid,text,uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_receipts(uuid,text,uuid[]) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_summary(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_summary(uuid,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.resolve_scanner_conflict(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_scanner_conflict(uuid,text) TO authenticated,service_role;

-- SOURCE: scanning/projection.sql
-- Set based, minimal projection shared by lookup, search and immutable snapshots.
CREATE OR REPLACE FUNCTION public.scanner_ticket_projection_internal(p_occasion bigint,p_config jsonb,p_ticket bigint DEFAULT NULL)
RETURNS TABLE(ticket_id bigint,dto jsonb) LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH base AS MATERIALIZED (
 SELECT t.*,o.id oid,o.form,o.state order_state,o.updated_at order_updated,o.data order_data,o.note_hidden order_note_hidden,
 pi.amount,pi.paid,public.provider_ticket_requires_online_internal(t.id) online_required,
 coalesce(td.value,'{}'::jsonb) ticket_data,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders oz ON oz.id=z."order"
 WHERE z.ticket=t.id AND (oz.occasion IS DISTINCT FROM t.occasion OR oz.state IN ('stock','storno','waitlisted','preparing_payment'))) bad_order
 FROM eshop.tickets t
 JOIN LATERAL (SELECT x."order" FROM eshop.order_product_ticket x WHERE x.ticket=t.id ORDER BY x."order" LIMIT 1) x ON true
 JOIN eshop.orders o ON o.id=x."order"
 LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
 LEFT JOIN LATERAL (SELECT value FROM jsonb_array_elements(coalesce(o.data->'tickets','[]'::jsonb)) WHERE value->>'id'=t.id::text LIMIT 1) td ON true
 WHERE t.occasion=p_occasion AND (p_ticket IS NULL OR t.id=p_ticket)
 ), projected AS (
 SELECT b.*,coalesce(nullif(trim(concat_ws(' ',nullif(trim(b.order_data->>'name'),''),nullif(trim(b.order_data->>'surname'),''))),''),
 (SELECT string_agg(nullif(trim(a.value#>>'{}'),''),' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.order_data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND NOT ff.is_ticket_field WHERE ff.type IN ('name','surname'))) purchaser_name,
 coalesce((SELECT string_agg(a.value#>>'{}',' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND ff.is_ticket_field WHERE ff.type IN ('name','surname')),
 (SELECT string_agg(v.value#>>'{}',' ' ORDER BY v.key) FROM jsonb_each(b.ticket_data) v WHERE v.key IN ('name','surname')),
 (SELECT concat_ws(' ',u.name,u.surname) FROM public.occasion_users ou JOIN public.user_info u ON u.id=ou."user" WHERE ou.ticket=b.id AND ou.occasion=p_occasion LIMIT 1),b.ticket_symbol) holder_name,
 (b.state IN ('sent','paid','ordered') AND b.ticket_symbol IS NOT NULL AND NOT b.bad_order AND b.order_state NOT IN ('stock','storno','waitlisted','preparing_payment') AND public.provider_ticket_admission_allowed_internal(b.id)) eligible
 FROM base b)
 SELECT b.id,jsonb_strip_nulls(jsonb_build_object('ticket_id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated_at',b.updated_at,
 'batch_title',(SELECT tb.title FROM eshop.ticket_batch_items bi JOIN eshop.ticket_batches tb ON tb.id=bi.batch_id WHERE bi.ticket_id=b.id AND tb.occasion=p_occasion),
 'order_id',b.oid,'purchaser_name',b.purchaser_name,'holder_name',b.holder_name,'admission_allowed',coalesce(b.eligible AND (b.state<>'ordered' OR (p_config#>>'{admission,allow_unpaid_online}')::boolean),false),
 'requires_unpaid_confirmation',b.state='ordered' AND NOT b.bad_order AND b.order_state<>'stock','unavailable_reason',CASE WHEN b.order_state='stock' THEN 'not_sold' END,'online_required',b.online_required,
 'eligibility_fingerprint',encode(digest(jsonb_build_object('v',1,'id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated',b.updated_at,
 'parents',(SELECT jsonb_agg(CASE WHEN pi.payment_method<>'bank' THEN jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid,pi.returned,pi.payment_method,o.email_payment_version) ELSE jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid) END ORDER BY o.id) FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE z.ticket=b.id))::text,'sha256'),'hex'),
 'remaining_amount',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN greatest(0,coalesce(b.amount,0)-coalesce(b.paid,0)) END,
 'order_note',nullif(trim(b.order_data->>'note'),''),'note',nullif(trim(b.note),''),
 'order_note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.order_note_hidden END,
 'note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.note_hidden END,
 'products',coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',p.id,'title',p.title,'short_title',nullif(trim(p.data->>'short_title'),''),'type_id',p.product_type,'type',pt.type,'type_title',pt.title,
 'price',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN p.price END)) ORDER BY array_position(ARRAY(SELECT value::text::bigint FROM jsonb_array_elements(p_config#>'{products,order}')),p.id) NULLS LAST,p."order",p.id)
 FROM eshop.products p LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.occasion=p_occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=b.id AND z.product=p.id)
 AND ((p_config#>>'{products,mode}')='all' OR ((p_config#>>'{products,mode}')='selected' AND (p_config#>'{products,ids}') @> to_jsonb(ARRAY[p.id])))),'[]'::jsonb),
 'spot',(SELECT s.title FROM eshop.spots s JOIN eshop.order_product_ticket z ON z.id=s.order_product_ticket WHERE z.ticket=b.id ORDER BY s.id LIMIT 1),
 'spot_group',(SELECT jsonb_build_object('blueprint_id',bp.id,'id',g->>'id','title',g->>'label')
 FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket
 JOIN eshop.blueprints bp ON bp.id=sp.blueprint
 JOIN eshop.blueprint_seat_bindings sb ON sb.blueprint=bp.id AND sb.spot=sp.id
 CROSS JOIN LATERAL jsonb_array_elements(bp.layout->'nodes') g
 WHERE z.ticket=b.id AND sp.occasion=p_occasion AND g->>'id'=sb.group_node::text
 AND g->>'kind' IN ('group','table')
 AND bp.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) ORDER BY sp.id LIMIT 1),
 'fields',coalesce((SELECT jsonb_agg(jsonb_build_object('key',f->>'key','label',f->>'label','value',
 CASE f->>'source' WHEN 'builtin' THEN CASE f->>'key' WHEN 'holder_name' THEN to_jsonb(b.holder_name) WHEN 'note' THEN to_jsonb(b.note)
 WHEN 'spot' THEN (SELECT to_jsonb(sp.title) FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket WHERE z.ticket=b.id ORDER BY sp.id LIMIT 1)
 WHEN 'groups' THEN (SELECT jsonb_agg(gi.title ORDER BY gi.id) FROM public.occasion_users ou JOIN public.user_groups ug ON ug."user"=ou."user" JOIN public.user_group_info gi ON gi.id=ug."group" WHERE ou.ticket=b.id AND ou.occasion=p_occasion AND gi.occasion=p_occasion) END
 ELSE (SELECT e->(f->>'field_id') FROM jsonb_array_elements(CASE WHEN f->>'source'='order_field' THEN coalesce(b.order_data->'fields','[]'::jsonb) ELSE coalesce(b.data->'fields','[]'::jsonb) END) e WHERE e ? (f->>'field_id') LIMIT 1) END,
 'missing',CASE WHEN f->>'source'='builtin' THEN false ELSE NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.id=(f->>'field_id')::bigint AND ff.form=b.form) END,
 'hide_empty',coalesce((f->>'hide_empty')::boolean,true),'default_visible',coalesce((f->>'default_visible')::boolean,true)) ORDER BY idx)
 FROM jsonb_array_elements(p_config->'fields') WITH ORDINALITY a(f,idx) WHERE f->>'source'='builtin' OR (f->>'form_id')::bigint=b.form),'[]'::jsonb)))
 FROM projected b;
$$;

-- SOURCE: blueprint/apply_seat_order_internal.sql
-- Actual cancellation + creation, shared by rollback quote and the one receipt.
-- Commercial calculation remains in the existing cancellation/finalize owners.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_order_internal(p_spots bigint[],p_input jsonb,p_command uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];affected bigint[];seats jsonb;occ bigint;form_id bigint;analysis jsonb;details jsonb;normalized jsonb;products bigint[];
 old_orders bigint[];before_orders jsonb;before_facts jsonb;form_facts jsonb;prepared jsonb;created jsonb;
 effects jsonb;new_order eshop.orders;new_products jsonb;semantic jsonb;revision jsonb;
BEGIN
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(p_spots) id WHERE id IS NOT NULL ORDER BY id);
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id=ANY(ids);
 IF occ IS NULL OR cardinality(ids)=0 OR cardinality(ids)>20000 OR
  (SELECT count(*) FROM eshop.spots WHERE id=ANY(ids) AND occasion=occ)<>cardinality(ids)
  OR public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 affected:=public.blueprint_order_affected_spots_internal(ids);
 PERFORM public.check_blueprint_swap_scope_internal(occ,affected);
 analysis:=public.analyze_new_order_spots(ids);
 details:=public.blueprint_order_input_internal(ids,p_input,analysis);
 SELECT id INTO form_id FROM public.forms WHERE key=(details->>'form')::uuid;
 -- Lock destination and existing forms together, before any order/product child.
 PERFORM 1 FROM public.forms WHERE id IN(SELECT form_id UNION SELECT o.form
  FROM eshop.orders o JOIN eshop.order_product_ticket i ON i."order"=o.id
  JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(ids)) ORDER BY id FOR UPDATE;
 analysis:=public.analyze_new_order_spots(ids);
 IF analysis#>>'{order_form,key}' IS DISTINCT FROM details->>'form' THEN
  RAISE serialization_failure USING MESSAGE='order form changed; retry the same command'; END IF;
 normalized:=public.normalize_form_ticket_answers_internal(form_id,details->'ticket');
 SELECT ARRAY(SELECT DISTINCT (f->>'product_type')::bigint FROM jsonb_array_elements(normalized) t
  CROSS JOIN LATERAL jsonb_array_elements(t->'fields') f WHERE f->>'product_type' IS NOT NULL ORDER BY 1) INTO products;
 IF EXISTS(SELECT 1 FROM unnest(products) requested(id) LEFT JOIN eshop.products p ON p.id=requested.id
  LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.id IS NULL OR pt.occasion IS DISTINCT FROM occ) THEN
  RAISE insufficient_privilege USING MESSAGE='order product scope unavailable'; END IF;
 PERFORM public.lock_spot_assignment_scope_internal(affected,'{}'::bigint[],true,products);
 IF affected IS DISTINCT FROM public.blueprint_order_affected_spots_internal(ids) THEN
  RAISE serialization_failure USING MESSAGE='order seat parents changed; retry the same command'; END IF;
 PERFORM public.check_blueprint_swap_scope_internal(occ,affected);
 IF EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
  WHERE p.id=ANY(products) AND pt.occasion IS DISTINCT FROM occ) THEN
  RAISE insufficient_privilege USING MESSAGE='order product scope unavailable'; END IF;
 PERFORM public.check_blueprint_selection_units_internal(ids);
 SELECT array_agg(DISTINCT i."order") INTO old_orders FROM eshop.spots s
 JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket WHERE s.id=ANY(ids);
 before_orders:=public.order_payment_snapshot_internal(old_orders);
 -- Customer facts and all required form definitions bind consent privately;
 -- the scoped MCP projection never receives existing customer identities.
 analysis:=public.analyze_new_order_spots(ids);
 SELECT to_jsonb(f)-'updated_at'-'created_at' INTO form_facts FROM public.forms f WHERE id=form_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'revision',b.layout_revision) ORDER BY b.id),'[]')
 INTO revision FROM eshop.blueprints b WHERE b.id IN(SELECT blueprint FROM eshop.spots WHERE id=ANY(affected));
 WITH lifecycle AS MATERIALIZED (SELECT * FROM public.blueprint_spot_facts_internal(occ,affected))
 SELECT coalesce(jsonb_object_agg(s.id::text,jsonb_build_object('spot',s.id,'product',s.product,'price',p.price,'currency',p.currency_code,
  'item',s.order_product_ticket,'ticketState',t.state,'hold',s.secret,'expires',extract(epoch FROM s.secret_expiration_time),'state',lifecycle.state,'ticket',i.ticket,'order',i."order")),'{}')
 INTO before_facts FROM eshop.spots s LEFT JOIN eshop.products p ON p.id=s.product
 LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket LEFT JOIN eshop.tickets t ON t.id=i.ticket LEFT JOIN lifecycle ON lifecycle.id=s.id WHERE s.id=ANY(affected);
 prepared:=public.confirm_blueprint_order_change_internal_v1(ids,p_input);
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF coalesce((prepared->>'success')::boolean,false) IS NOT TRUE THEN
  RAISE check_violation USING MESSAGE='replacement preparation rejected',DETAIL=prepared::text; END IF;
 created:=public.create_ticket_order_internal_v1(prepared->'orderDetails');
 IF coalesce((created->>'code')::integer,500)<>200 THEN
  RAISE check_violation USING MESSAGE='replacement order rejected',DETAIL=created::text; END IF;
 PERFORM public.enqueue_ticket_order_confirmation_v1(p_command,occ,created,coalesce(p_input->>'lang',prepared#>>'{orderDetails,lang}'));
 SELECT * INTO new_order FROM eshop.orders WHERE id=(created#>>'{order,id}')::bigint;
 IF created#>>'{order,payment_info,payment_method}'<>'bank' THEN
  RAISE check_violation USING MESSAGE='STRIPE_REPLACEMENT_UNSUPPORTED'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',id,'beforeAmount',(before_orders->id::text->>'amount')::numeric,
  'afterAmount',price,'delta',price-(before_orders->id::text->>'amount')::numeric,'currencyCode',currency_code,
  'beforeState',before_orders->id::text->>'state','afterState',state) ORDER BY id),'[]')
 INTO effects FROM eshop.orders WHERE id=ANY(old_orders);
 WITH ticket_spots AS MATERIALIZED (SELECT s.id,i.ticket FROM eshop.spots s
  JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket WHERE s.id=ANY(ids))
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'productId',(p->>'id')::bigint,'title',p->'title',
  'amount',p->>'price','currencyCode',p->'currency_code') ORDER BY s.id,(p->>'id')::bigint,(p->>'price')::numeric),'[]')
 INTO new_products FROM jsonb_array_elements(new_order.data->'tickets') t
 JOIN ticket_spots s ON s.ticket=(t->>'id')::bigint CROSS JOIN LATERAL jsonb_array_elements(t->'products') p;
 WITH lifecycle AS MATERIALIZED (SELECT * FROM public.blueprint_spot_facts_internal(occ,affected))
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'blueprintId',s.blueprint,'blueprintTitle',b.title,'title',s.title,
  'stateBefore',before_facts->s.id::text->'state','stateAfter',f.state,
  'previousOrderId',before_facts->s.id::text->'order','previousTicketId',before_facts->s.id::text->'ticket',
  'productId',s.product,'productTitle',p.title) ORDER BY s.id),'[]')
 INTO seats FROM eshop.spots s LEFT JOIN eshop.products p ON p.id=s.product LEFT JOIN eshop.blueprints b ON b.id=s.blueprint LEFT JOIN lifecycle f ON f.id=s.id WHERE s.id=ANY(affected);
 semantic:=jsonb_build_object('spotIds',ids,'affectedSpotIds',affected,
  'releasedSpotIds',ARRAY(SELECT id FROM unnest(affected) id WHERE NOT id=ANY(ids)),
  'seats',seats,'blueprints',revision,'formKey',details->'form','orders',effects,
  'newOrder',jsonb_build_object('amount',new_order.price::text,'currencyCode',new_order.currency_code,
   'state',new_order.state,'paymentMethod',created#>'{order,payment_info,payment_method}',
   'ticketCount',(SELECT count(DISTINCT ticket) FROM eshop.order_product_ticket WHERE "order"=new_order.id),
   'products',new_products));
 PERFORM public.check_occasion_writable(occ);
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 RETURN jsonb_build_object('result',created,'quote',semantic,'analysis',analysis,
  'confirmationHash',encode(extensions.digest(convert_to(jsonb_build_object('actor',auth.uid(),'quote',semantic,
   'input',p_input,'beforeOrders',before_orders,'facts',before_facts,'analysis',analysis,'form',form_facts,
   'paymentRecipient',jsonb_build_object('account',created#>'{order,payment_info,account_number}',
    'accountLabel',created#>'{order,payment_info,account_number_human_readable}',
    'creditor',created#>'{order,payment_info,creditor_name}','deposit',created#>'{order,payment_info,deposit_amount}'),
   'effectiveForm',created#>'{order,form,data}','occasionFeatures',created#>'{order,occasion,features}')::text,'UTF8'),'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_order_internal(bigint[],jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;

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
  IF spec.key='sale_opening_notifications' AND NOT d ? spec.key THEN CONTINUE; END IF;
  IF spec.value='null'::jsonb OR NOT d ? spec.key OR d->spec.key='null'::jsonb THEN
   result:=result||jsonb_build_object(spec.key,coalesce(d->spec.key,'null'::jsonb));
  ELSE
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

-- SOURCE: eshop_forms/duplicate_form_to_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_internal_v1(
    source_form_id BIGINT,
    target_occasion_link TEXT,
    p_locale TEXT DEFAULT 'en'
)
RETURNS BIGINT -- Returns the ID of the new form
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    user_id UUID := auth.uid();
    target_occasion_id BIGINT;
    target_organization_id BIGINT;
    source_occasion_id BIGINT;
    source_unit_id BIGINT;
    has_source_permission BOOLEAN;
    has_target_permission BOOLEAN;
    new_form_id BIGINT;
    v_new_form_link TEXT;
    form_field_record RECORD;
    new_product_type_id BIGINT;
    product_record RECORD;
BEGIN
    -- Step 1: Resolve the target occasion ID and its organization ID from its link.
    SELECT id, organization INTO target_occasion_id, target_organization_id
    FROM public.occasions WHERE id = public.resolve_occasion_link_internal(target_occasion_link);
    IF target_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Target occasion not found for link: %', target_occasion_link;
    END IF;

    PERFORM public.check_occasion_writable(target_occasion_id);

    PERFORM public.notification_center_initialized_internal(target_organization_id);
    -- Step 2: Get the source occasion and unit IDs for permission checking.
    SELECT f.occasion, o.unit
    INTO source_occasion_id, source_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = source_form_id;

    IF source_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Source form not found.';
    END IF;

    -- Step 3: Check if the user has editor_view rights on the source occasion or its unit.
    SELECT public.can_copy_form_source(source_occasion_id)
    INTO has_source_permission;

    IF NOT has_source_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to view the source form.';
    END IF;

    -- Step 4: Check if the user has editor rights on the target occasion.
    SELECT public.can_copy_form_target(target_occasion_id)
    INTO has_target_permission;

    IF NOT has_target_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to create a form in the target occasion.';
    END IF;

    -- Step 6: Copy the main form record to the target occasion.
    INSERT INTO public.forms (title, data, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds)
    SELECT
        public.copy_occasion_title_internal(title,p_locale),
        CASE WHEN source_unit_id IS DISTINCT FROM (SELECT unit FROM public.occasions WHERE id=target_occasion_id)
          THEN public.strip_form_payment_connections_internal(public.normalize_form_metadata_internal(data)) ELSE public.normalize_form_metadata_internal(data) END - 'sale_opening_notifications',
        target_occasion_id,
        type,
        bank_account,
        deadline_duration_seconds,
        CASE WHEN source_unit_id IS DISTINCT FROM (SELECT unit FROM public.occasions WHERE id=target_occasion_id)
          AND data#>'{payments,bankEnabled}'='false'::jsonb THEN false ELSE is_open END,
        NULL,
        blueprint,
        header,
        header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds
    FROM public.forms
    WHERE id = source_form_id
    RETURNING id INTO new_form_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,NULL,true) WHERE id=new_form_id;

    -- Step 7: Loop through each field of the source form and perform a deep copy.
    FOR form_field_record IN
        SELECT * FROM public.form_fields WHERE form = source_form_id
    LOOP
        -- Check if the field is linked to a product type.
        IF form_field_record.product_type IS NOT NULL THEN
            -- A) If yes, perform a deep copy of the product type and its products.
            INSERT INTO eshop.product_types (title, description, type, data, occasion, maximum)
            SELECT title, description, type, data, target_occasion_id, maximum
            FROM eshop.product_types
            WHERE id = form_field_record.product_type
            RETURNING id INTO new_product_type_id;

            FOR product_record IN
                SELECT * FROM eshop.products WHERE product_type = form_field_record.product_type
            LOOP
                INSERT INTO eshop.products (title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
                VALUES (
                    product_record.title, product_record.description, product_record.price, product_record.data,
                    new_product_type_id, target_occasion_id, product_record.is_hidden, product_record.currency_code,
                    product_record.order, product_record.maximum
                );
            END LOOP;

            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                new_product_type_id, form_field_record.is_ticket_field
            );
        ELSE
            -- B) If not, perform a simple copy of the form field.
            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                NULL, form_field_record.is_ticket_field
            );
        END IF;
    END LOOP;

    -- Step 8: Return the ID of the newly created form.
    PERFORM public.notification_center_form_created_internal(new_form_id);
    PERFORM public.assert_form_seating_source_internal(new_form_id);
    RETURN new_form_id;
END;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion(source_form_id bigint,target_occasion_link text)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (public.duplicate_form_to_occasion_client_sync_v1(source_form_id,target_occasion_link,gen_random_uuid())#>>'{data,formId}')::bigint;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion(bigint,text) TO authenticated;

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
  RETURN to_jsonb(d);
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
      jsonb_build_object('defaultConfiguration',configuration,
        'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true,
        'paymentMethod',(SELECT CASE WHEN public.payment_method_registered_internal(data->>'DEFAULT_FORM_PAYMENT_METHOD') AND data->>'DEFAULT_FORM_PAYMENT_METHOD'<>'bank' THEN data->>'DEFAULT_FORM_PAYMENT_METHOD' END FROM public.organizations WHERE id=d.organization),
        'paymentChoicesEnabled',EXISTS(SELECT 1 FROM jsonb_each(public.provider_unit_features_internal(d.unit)) x WHERE x.value='true'::jsonb))
      || d.data WHERE id = p_id RETURNING * INTO d;
    PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,d.organization,octet_length(d.data::text),false,false,policy);
  END IF;
  RETURN to_jsonb(d);
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
      jsonb_array_length(d.data#>'{defaultConfiguration,forms}')>0) THEN RETURN to_jsonb(d); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = 'PT409';
  END IF;
  policy:=public.abuse_effective_rules_v1('occasion.draft',d.unit,d.organization);
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,0,false,true,policy);
  configuration := public.build_occasion_setup_configuration(d.unit,p_id);
  UPDATE public.occasion_setup_drafts SET data =
    jsonb_build_object('defaultConfiguration',configuration,
      'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true,
        'paymentMethod',(SELECT CASE WHEN public.payment_method_registered_internal(data->>'DEFAULT_FORM_PAYMENT_METHOD') AND data->>'DEFAULT_FORM_PAYMENT_METHOD'<>'bank' THEN data->>'DEFAULT_FORM_PAYMENT_METHOD' END FROM public.organizations WHERE id=d.organization),
        'paymentChoicesEnabled',EXISTS(SELECT 1 FROM jsonb_each(public.provider_unit_features_internal(d.unit)) x WHERE x.value='true'::jsonb))
    || (d.data-'defaultConfiguration'), revision = revision+1, updated_at=now()
    WHERE id=p_id RETURNING * INTO d;
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,octet_length(d.data::text),false,false,policy);
  RETURN to_jsonb(d);
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
  p_data := p_data - 'finalizedOccasion' - 'finalizeResponse';
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
  IF d.revision = p_expected_revision + 1 AND d.data = p_data AND d.current_step = p_step THEN RETURN to_jsonb(d); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = 'PT409'; END IF;
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,octet_length(p_data::text),false,false);
  UPDATE public.occasion_setup_drafts SET data = p_data, current_step = p_step,
    revision = revision + 1, updated_at = now() WHERE id = p_id RETURNING * INTO d;
  RETURN to_jsonb(d);
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
 payment_method:=payload->>'paymentMethod';
 IF payment_method IS NOT NULL AND payment_method NOT IN ('bank','both') AND NOT public.payment_method_registered_internal(payment_method) THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid payment method'; END IF;
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
 IF required_currencies IS NOT NULL AND (payment_method IS NULL OR payment_method IN ('bank','both')) AND (payload ? 'bankAccountId' OR payload ? 'bankAccountConfirmed' OR payment_method IN ('bank','both')) THEN
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
  IF payment_method IS NOT NULL THEN
   form_meta:=jsonb_set(form_meta,'{payments}',coalesce(form_meta->'payments','{}'::jsonb)
      ||jsonb_build_object('bankEnabled',payment_method IN ('bank','both')));
   IF payment_method='bank' THEN form_meta:=public.strip_form_payment_connections_internal(form_meta); END IF;
  END IF;
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

-- SOURCE: public_links/reserved_paths.sql
-- Shared roots must never become occasion slugs.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.occasion_link_reservations WHERE slug IN ('stripe','payments') AND occasion IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.legacy_occasion_link_bindings WHERE slug IN ('stripe','payments') AND occasion IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.occasions WHERE link IN ('stripe','payments')) THEN
  RAISE EXCEPTION 'Payment route conflicts with an existing occasion slug';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.occasion_reserved_public_paths_internal()
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
 SELECT ARRAY['resetPassword','forgotPassword','reset-password','forgot-password','login','signup','settings','install','unit','admin','form','order','scan','transfer','app','privacy','terms','support','delete-account','google-auth','stripe','payments','assets','icons','flutter','index.html','flutter.html','favicon.ico','manifest.json','robots.txt','version.json','backend-activation.json'];
$$;

REVOKE ALL ON FUNCTION public.occasion_reserved_public_paths_internal() FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: others/get_app_config.sql
CREATE OR REPLACE FUNCTION public.get_app_config_v218(data_in jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    org_id bigint := (data_in->>'organization')::bigint;
    link_txt text := data_in->>'link';
    form_link text := data_in->>'form_link';
    unit_id bigint := (data_in->>'unit_id')::bigint;
    platform_info jsonb := data_in->'platform';
    platform_name text := platform_info->>'platform';
    occasionId bigint;
    default_unit bigint;
    editor_unit_id bigint;
    is_open_bool BOOLEAN;
    is_app_supported_bool BOOLEAN := FALSE;
    occasion_user occasion_users%rowtype;
    unit_user unit_users%rowtype;
    is_admin_bool BOOLEAN;
    v_organization_admin boolean := false;
    v_context_organization public.organizations%ROWTYPE;
    v_context_occasion public.occasions%ROWTYPE;
    v_membership_added boolean := false;
    v_demo boolean := false;
    v_demo_read boolean := false;
    v_demo_unit_ids bigint[];
    occasion_link text;
    occasion_unit bigint;
    bank_account_ids bigint[];
    bank_capabilities jsonb;
    occasion_json jsonb;
    unit_json jsonb;
    user_info_json jsonb;
    org_json jsonb;
    user_groups_json jsonb;
    is_editor_view_on_occasion_bool BOOLEAN;
    user_occasions_json jsonb;
    user_units_json jsonb;
    current_user_id UUID := auth.uid();
BEGIN
    -- A direct unit link must stay inside the requested tenant.
    IF unit_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.units u
        WHERE u.id = unit_id AND u.organization = org_id
    ) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Unit not found');
    END IF;

    SELECT * INTO v_context_organization FROM public.organizations WHERE id=org_id;
    v_organization_admin := public.can_manage_organization_settings(org_id);

    -- Log the request details in log_app_config table
    INSERT INTO public.log_app_config (organization, platform)
    VALUES (org_id, platform_info);

    -- Map "pwa" to "web" for platform consistency
    IF platform_name = 'pwa' THEN
        platform_name := 'web';
    END IF;

    -- =========================================================
    -- RESOLVE CONTEXT (Occasion vs Unit)
    -- Priority: Form/Link > Representative Occasion > Unit ID > Default Occasion
    -- =========================================================

    -- 1. Try to find occasion via form_link
    IF form_link IS NOT NULL AND form_link <> '' THEN
        SELECT o.* INTO v_context_occasion
        FROM public.forms f
        JOIN public.occasions o ON f.occasion = o.id
        WHERE f.id = public.resolve_form_link_internal(form_link)
          AND o.organization = org_id;
        occasionId := v_context_occasion.id;
        occasion_link := v_context_occasion.link;
        IF occasionId IS NULL THEN
            RETURN jsonb_build_object('code',404,'message','Form not found');
        END IF;
    END IF;

    -- 2. If no occasion found yet, try via link_txt
    IF occasionId IS NULL AND link_txt IS NOT NULL AND link_txt <> '' THEN
        SELECT o.* INTO v_context_occasion
        FROM public.occasions o
        WHERE o.id = public.resolve_occasion_link_internal(link_txt,org_id)
          AND o.organization = org_id;
        occasionId := v_context_occasion.id;
        occasion_link := v_context_occasion.link;

        -- If link_txt is provided but *not* found, this is a hard 404.
        IF occasionId IS NULL THEN
            RETURN jsonb_build_object(
                'code', 404,
                'message', 'Occasion not found'
            );
        END IF;
    END IF;

    -- 3. If no specific link found, check for REPRESENTATIVE OCCASION
    IF occasionId IS NULL AND unit_id IS NULL THEN
        occasionId := (v_context_organization.data->>'REPRESENTATIVE_OCCASION')::bigint;

        -- If found, fetch its link for consistency
        IF occasionId IS NOT NULL THEN
            SELECT link INTO occasion_link
            FROM occasions
            WHERE id = occasionId AND organization = org_id;
        END IF;
    END IF;

    -- 4. If no occasion (and no Representative Occasion), try to use unit_id
    IF occasionId IS NULL AND unit_id IS NOT NULL THEN
        occasionId := NULL; -- Ensure no occasion is loaded.

        default_unit := unit_id;

        SELECT jsonb_build_object('id', u.id, 'title', u.title, 'data', u.data)
            INTO unit_json
        FROM units u
        WHERE u.id = default_unit;

        SELECT *
            INTO unit_user
        FROM unit_users
        WHERE unit = default_unit
            AND "user" = current_user_id;

    -- If no occasion and no unit found yet, try Default Occasion
    ELSIF occasionId IS NULL THEN
        -- Try to get the DEFAULT_OCCASION (Representative was already checked in step 3)
        occasionId := (v_context_organization.data->>'DEFAULT_OCCASION')::bigint;

        IF occasionId IS NOT NULL THEN
            -- Default occasion exists; fetch its link
            SELECT link
              INTO occasion_link
            FROM occasions
            WHERE id = occasionId AND organization = org_id;
        END IF;
    END IF;

    -- =========================================================
    -- GATHER DATA
    -- =========================================================

    IF occasionId IS NOT NULL THEN
        -- Process occasion-related queries only if an occasion was determined

        -- Link/form resolution already loaded this exact tenant-bound row.
        -- Reuse it within the request instead of reading it a second time.
        IF v_context_occasion.id IS DISTINCT FROM occasionId THEN
          SELECT o.* INTO v_context_occasion FROM public.occasions o
            WHERE o.id=occasionId AND o.organization=org_id;
        END IF;
        IF v_context_occasion.id IS NULL THEN
          RETURN jsonb_build_object('code',404,'message','Occasion not found');
        END IF;
        is_open_bool := v_context_occasion.is_open;
        occasion_unit := v_context_occasion.unit;
        v_demo := public.is_demo_occasion(occasionId);
        v_demo_read := CASE WHEN v_demo THEN public.can_read_demo_occasion(occasionId) ELSE false END;
        IF v_demo AND NOT v_demo_read THEN
            RETURN jsonb_build_object('code',403,'message','Demo access denied');
        END IF;

        -- Get the occasion user record if it exists
        SELECT *
          INTO occasion_user
        FROM occasion_users
        WHERE occasion = occasionId
          AND "user" = current_user_id;

        -- Get the unit user record if it exists
        SELECT *
          INTO unit_user
        FROM unit_users
        WHERE unit = occasion_unit
          AND "user" = current_user_id;

        -- Check if the current user is an admin on the occasion
        is_admin_bool := public.active_membership(
          v_organization_admin,v_demo);

        -- Check if the current user has editor_view permissions on the occasion
        is_editor_view_on_occasion_bool := public.readable_membership(occasion_user.is_editor_view,v_demo,v_demo_read);

        -- Retrieve IS_APP_SUPPORTED from Organization data. Defaults to FALSE.
        is_app_supported_bool := coalesce((v_context_organization.data->>'IS_APP_SUPPORTED')::boolean,false);

        -- If the occasion is not open, enforce access restrictions
        -- BUT bypass this check if is_app_supported_bool is FALSE.
        IF is_open_bool = FALSE AND is_app_supported_bool = TRUE THEN
            IF NOT public.context_private_access_rule(is_editor_view_on_occasion_bool,
               public.can_read_orders(occasionId),public.get_is_editor_on_unit(occasion_unit)) THEN
                RETURN jsonb_build_object(
                    'code', 403,
                    'message', 'Access forbidden',
                    'link', occasion_link,
                    'unit_user', COALESCE(to_jsonb(unit_user)::jsonb, NULL)
                );
            END IF;
        END IF;

        -- If the occasion user record is not found and the user is authenticated, add the user to the occasion
        IF occasion_user IS NULL AND current_user_id IS NOT NULL AND NOT public.is_demo_occasion(occasionId) THEN
            IF is_app_supported_bool IS TRUE
               OR public.unit_discovery_rule(unit_user.is_editor,unit_user.is_manager,unit_user.is_editor_view) THEN
                PERFORM add_user_to_occasion(occasionId, current_user_id);
                v_membership_added := true;

                SELECT *
                  INTO occasion_user
                FROM occasion_users
                WHERE occasion = occasionId
                  AND "user" = current_user_id;
            END IF;
        END IF;
    ELSE
        -- If no occasion is set (because a specific unit was used and no Rep Occasion existed), use the unit as the context
        occasion_unit := default_unit;
        is_admin_bool := false;
    END IF;

    -- Retrieve unit_user again in case the user was added and now belongs to the unit
    IF unit_user IS NULL AND occasion_unit IS NOT NULL AND current_user_id IS NOT NULL THEN
        SELECT *
          INTO unit_user
        FROM unit_users
        WHERE unit = occasion_unit
          AND "user" = current_user_id;
    END IF;

    -- Request-local facts for this projection only. Writers independently
    -- reauthorize against the live registry; this is never a permission cache.
    SELECT coalesce(array_agg(demo.unit_id),'{}'::bigint[]) INTO v_demo_unit_ids
      FROM public.demo_unit_ids_internal() demo;

    -- Fetch list of bank account IDs where the user is an admin
    SELECT array_agg(m.bank_account),jsonb_object_agg(m.bank_account,
      CASE WHEN public.bank_account_write_rule(m.is_admin,managed.bank_account IS NOT NULL,protected.bank_account IS NOT NULL)
        THEN public.bank_context_capabilities(true,true,false)
        ELSE public.bank_context_capabilities(false,false,false) END)
      INTO bank_account_ids,bank_capabilities
    FROM eshop.bank_account_users m
    LEFT JOIN (SELECT DISTINCT link.bank_account FROM eshop.unit_bank_accounts link
      JOIN public.unit_users membership ON membership.unit=link.unit
      WHERE membership."user"=current_user_id AND membership.is_manager
        AND NOT membership.unit=ANY(v_demo_unit_ids)) managed
      ON managed.bank_account=m.bank_account
    LEFT JOIN (SELECT DISTINCT bank_account FROM public.demo_occasions) protected
      ON protected.bank_account=m.bank_account
    WHERE m."user"=current_user_id AND m.is_admin=true;

    -- Fetch full occasion details as a JSON object if an occasion is set
    IF occasionId IS NOT NULL THEN
        IF v_membership_added THEN
            SELECT to_jsonb(o) INTO occasion_json FROM public.occasions o WHERE o.id=occasionId;
        ELSE
            occasion_json := to_jsonb(v_context_occasion);
        END IF;
    ELSE
        occasion_json := '{}'::jsonb;
    END IF;

    -- Fetch full unit details as a JSON object
    IF occasion_unit IS NOT NULL AND unit_json IS NULL THEN
        SELECT jsonb_build_object('id', u.id, 'title', u.title, 'data', u.data)
          INTO unit_json
        FROM units u
        WHERE u.id = occasion_unit;
    ELSE
        IF unit_json IS NULL THEN
            unit_json := '{}'::jsonb;
        END IF;
    END IF;

    -- Fetch occasions for the user based on the specified logic
    IF occasion_unit IS NOT NULL AND current_user_id IS NOT NULL THEN
        IF public.occasion_list_read_rule(is_editor_view_on_occasion_bool,
          current_user_id IS NOT NULL AND public.get_is_editor_on_unit(occasion_unit)) THEN
            -- If user is an editor or unit editor, get all occasions for the unit
            SELECT jsonb_agg(jsonb_build_object('id', o.id, 'title', o.title, 'link', o.link, 'start_time', o.start_time, 'end_time', o.end_time) ORDER BY o.start_time DESC)
            INTO user_occasions_json
            FROM (
                SELECT * FROM public.occasions
                WHERE unit = occasion_unit
                ORDER BY start_time DESC
                LIMIT 100
            ) o;
        ELSE
            -- Otherwise, get only occasions the user is explicitly on for that unit
            -- AND where they have privileged access (manager, editor, etc.)
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', o.id,
                    'title', o.title,
                    'link', o.link,
                    'start_time', o.start_time,
                    'end_time', o.end_time
                ) ORDER BY o.start_time DESC
            )
            INTO user_occasions_json
            FROM (
                 SELECT o.*
                 FROM public.occasions o
                 JOIN public.occasion_users ou ON ou.occasion = o.id
                 WHERE ou."user" = current_user_id
                 AND o.unit = occasion_unit
                 AND public.occasion_staff_navigation_rule(ou.is_manager,ou.is_editor,ou.is_editor_view,ou.is_editor_order,ou.is_editor_order_view)
                 ORDER BY o.start_time DESC
                 LIMIT 100
            ) o;
        END IF;
    END IF;

    -- Fetch units for the user based on unit rights or occasion rights
    SELECT jsonb_agg(jsonb_build_object('id', u.id, 'title', u.title) ORDER BY u.title)
    INTO user_units_json
    FROM public.units u
    WHERE u.organization = org_id AND (
        EXISTS (
            SELECT 1
            FROM public.unit_users uu
            WHERE uu.unit = u.id
            AND uu."user" = current_user_id
            AND uu.is_editor_view = TRUE
        )
        OR
        EXISTS (
            SELECT 1
            FROM public.occasions o
            JOIN public.occasion_users ou ON ou.occasion = o.id
            WHERE o.unit = u.id
            AND ou."user" = current_user_id
            AND public.occasion_staff_navigation_rule(ou.is_manager,ou.is_editor,ou.is_editor_view,ou.is_editor_order,ou.is_editor_order_view)
        )
    );

    -- Fetch user information along with associated units and occasions
    SELECT to_jsonb(ui)::jsonb || jsonb_build_object(
            'units', COALESCE(user_units_json, '[]'::jsonb),
            'occasions', COALESCE(user_occasions_json, '[]'::jsonb)
          )
      INTO user_info_json
    FROM public.user_info ui
    WHERE ui.id = current_user_id;

    -- Fetch organization info
    org_json := CASE WHEN v_context_organization.id IS NOT NULL THEN jsonb_build_object(
        'title', v_context_organization.title,
        'APP_NAME', v_context_organization.data->>'APP_NAME',
        'PLATFORMS', v_context_organization.data->'PLATFORMS',
        'DEFAULT_URL', v_context_organization.data->>'DEFAULT_URL',
        'DEFAULT_LANGUAGE', v_context_organization.data->>'DEFAULT_LANGUAGE',
        'IS_REGISTRATION_ENABLED', (v_context_organization.data->>'IS_REGISTRATION_ENABLED')::boolean,
        'IS_UNIT_CREATION_ENABLED', (v_context_organization.data->>'IS_UNIT_CREATION_ENABLED')::boolean,
        'IS_APP_SUPPORTED', (v_context_organization.data->>'IS_APP_SUPPORTED')::boolean,
        'DEFAULT_UNIT', (v_context_organization.data->>'DEFAULT_UNIT')::int,
        'REPRESENTATIVE_OCCASION', (v_context_organization.data->>'REPRESENTATIVE_OCCASION')::int
    ) ELSE NULL END;

    -- Fetch the user's groups for the specific occasion
    IF occasionId IS NOT NULL THEN
        user_groups_json := public.get_user_groups_for_context_internal_v1(occasionId,
          public.active_membership(occasion_user.is_editor,v_demo),
          public.readable_membership(occasion_user.is_editor_view,v_demo,v_demo_read),NOT v_demo);
    END IF;

    RETURN jsonb_build_object(
        'code', 200,
        'is_admin', is_admin_bool,
        'capabilities', public.get_context_capabilities_v1(occasionId,occasion_user,unit_user,is_admin_bool,
          v_demo,coalesce(COALESCE(occasion_unit,default_unit)=ANY(v_demo_unit_ids),false),v_demo_read,
          coalesce(jsonb_array_length(user_units_json),0)>0,
          EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(user_units_json,'[]'::jsonb)) listed
            WHERE (listed->>'id')::bigint=occasion_unit),
          public.reception_enabled(occasion_json->'features')) || public.organization_context_capabilities(v_organization_admin),
        'demo_read_only', v_demo_read,
        'occasion_user', COALESCE(to_jsonb(occasion_user)::jsonb, NULL),
        'unit_user', COALESCE(to_jsonb(unit_user)::jsonb, NULL),
        'occasion', COALESCE(occasion_json, '{}'::jsonb),
        'unit', COALESCE(unit_json, '{}'::jsonb) || public.provider_unit_public_fields_internal((unit_json->>'id')::bigint),
        'bank_accounts_admin', COALESCE(bank_account_ids, '{}'),
        'bank_capabilities',coalesce(bank_capabilities,'{}'::jsonb),
        'user_info', COALESCE(user_info_json, '{}'::jsonb),
        'organization', COALESCE(org_json::jsonb, '{}'::jsonb),
        'groups', COALESCE(user_groups_json, '{}'::jsonb)
    );
END;
$$;

-- SOURCE: eshop/format_occasion_report_text.sql
CREATE OR REPLACE FUNCTION public.format_occasion_report_text(report jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE result text; item jsonb; section text;
BEGIN
  result := (report->'occasion'->>'title') || E'\n' || (report->>'generated_at') || E'\n';
  FOREACH section IN ARRAY ARRAY['orders','tickets'] LOOP
    result := result || CASE section WHEN 'orders' THEN 'Počet objednávek celkem: ' ELSE 'Počet vstupenek celkem: ' END || (report->section->>'total') || E'\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->section->'by_state') LOOP
      result := result || '  ' || (item->>'state') || ': ' || (item->>'count') || E'\n';
    END LOOP;
  END LOOP;
  result := result || 'Místa (obsazená / celkem): ' || (report->'spots'->>'occupied') || ' / ' || (report->'spots'->>'total') || E'\n';
  IF coalesce((report#>>'{ticket_batches,total}')::bigint,0)>0 THEN
    result:=result||'Předgenerované - neprodáno: '||(report#>>'{ticket_batches,available}')||E'\n'
      ||'Předgenerované - prodáno: '||(report#>>'{ticket_batches,sold_active}')||E'\n'
      ||'Předgenerované - zneplatněno: '||(report#>>'{ticket_batches,voided_unsold}')||E'\n';
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(report->'money_by_currency') LOOP
    result := result || E'\n' || (item->>'currency') || E'\n'
      || 'Aktuální hodnota objednávek: ' || (item->>'current_order_value') || E'\n'
      || 'Přijato: ' || (item->>'received') || E'\n'
      || 'Vráceno: ' || (item->>'returned') || E'\n'
      || 'Čistý příjem: ' || (item->>'net_received') || E'\n'
      || 'Ručně evidováno: ' || (item->>'manual_received') || E'\n'
      || 'Ostatní příjmy: ' || (item->>'other_received') || E'\n';
    IF item ? 'stripe_received' THEN
      result:=result||'Z toho přijato platební bránou: '||(item->>'stripe_received')||E'\n'
       ||'Z toho vráceno platební bránou: '||(item->>'stripe_refunded')||E'\n'
       ||'Částka ve sporu (není vratka): '||(item->>'disputed')||E'\n'
       ||'Dostupné po odečtení sporů: '||(item->>'available_after_disputes')||E'\n';
    END IF;
    IF item ? 'external_unattributed' THEN
      result:=result||'Externí částka bez doloženého přiřazení: '||(item->>'external_unattributed')||E'\n';
    END IF;
    IF (item->>'has_deposits')::boolean THEN
      result := result || 'Přijaté zálohy (hrubé): ' || (item->>'deposit_received_gross') || E'\n'
        || 'Přijato nad zálohu (hrubé): ' || (item->>'beyond_deposit_received_gross') || E'\n';
    END IF;
  END LOOP;
  IF report ? 'timeline' THEN
    result := result || E'\nNové objednávky po dnech (Europe/Prague, včetně později stornovaných):\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->'timeline'->'orders') LOOP
      result := result || (item->>'day') || ' ' || (item->>'currency') || ': ' || (item->>'count') || E'\n';
    END LOOP;
    result := result || E'\nZaevidované platby po dnech (datum bankovní transakce nebo čas pohybu Stripe v Europe/Prague; včetně částečných plateb):\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->'timeline'->'payments') LOOP
      result := result || (item->>'day') || ' ' || (item->>'currency') || ': přijato ' || (item->>'received') || ', vráceno ' || (item->>'returned') || E'\n';
    END LOOP;
  END IF;
  result := result || E'\nProdukty v potvrzených objednávkách (paid/sent/used, včetně záloh):\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'products') LOOP
    result := result || coalesce(item->>'type_title','Bez typu') || ' / ' || (item->>'product_title') || ': ' || (item->>'confirmed_count') || E'\n';
  END LOOP;
  result := result || E'\nSouhrn stavů odpovídá aktuálnímu stavu, nikoli historickým přechodům. Denní platby obsahují pouze zaevidované transakce. Stav paid může znamenat jen uhrazenou zálohu.\nMísta nezahrnují dočasné blokace. Ruční příjmy nejsou nutně hotovost; ostatní nejsou nutně banka.\nZálohy jsou hrubé platby před vratkami, pouze u plateb se zálohou.\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'warnings') LOOP
    result := result || 'Upozornění: ' || (item->>'code') || ' (' || (item->>'count') || E')\n';
  END LOOP;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.format_occasion_report_text(jsonb) FROM PUBLIC, anon, authenticated, service_role;
