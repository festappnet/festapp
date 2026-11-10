-- Unified incoming/outgoing payment operations. No activation or network jobs.

-- SOURCE: payment_providers/operations_schema.sql
-- Unified method installation and durable operation intents. No tenant activation.
ALTER TABLE eshop.bank_sync_connections ADD COLUMN IF NOT EXISTS refund_rf_verified boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS refund_write_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS hosted_checkout boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS operation_mode text;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS verification text;
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='eshop.payment_providers'::regclass AND contype='c'
  AND pg_get_constraintdef(oid) LIKE '%handler%' LOOP
  EXECUTE format('ALTER TABLE eshop.payment_providers DROP CONSTRAINT %I',c.conname);
 END LOOP;
END $$;
UPDATE eshop.payment_providers SET hosted_checkout=source_field IS NOT NULL,
 operation_mode=CASE WHEN source_field IS NOT NULL THEN 'remote' ELSE 'local' END,
 verification=CASE WHEN source_field IS NOT NULL THEN 'verified_provider_observation' ELSE 'local_commit' END;
CREATE TABLE IF NOT EXISTS eshop.refund_requests (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE RESTRICT,
 payment_info bigint NOT NULL REFERENCES eshop.payment_info(id) ON DELETE RESTRICT,
 method text NOT NULL REFERENCES eshop.payment_providers(provider_key),
 amount numeric(12,2) NOT NULL CHECK(amount>0),currency text NOT NULL,
 status text NOT NULL CHECK(status IN ('pending','processing','unknown','succeeded','cancelled','failed')),
 source_account bigint REFERENCES eshop.bank_accounts(id) ON DELETE RESTRICT,
 reference_namespace text REFERENCES eshop.payment_reference_namespaces(id),
 variable_symbol bigint,creditor_reference text,
 payload jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now(),
 created_by uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
 lease_token uuid,lease_until timestamptz,dispatched_at timestamptz,
 provider_refund_id text,result jsonb,updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS refund_requests_bank_pending ON eshop.refund_requests(payment_info)
 WHERE method='bank' AND status IN ('pending','processing','unknown');
CREATE TABLE IF NOT EXISTS eshop.refund_settlements (
 transaction_id bigint PRIMARY KEY REFERENCES eshop.transactions(id) ON DELETE RESTRICT,
 request_id uuid REFERENCES eshop.refund_requests(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now(),
 voided_at timestamptz,void_reason text,
 actor uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
 CHECK ((voided_at IS NULL)=(void_reason IS NULL))
);
CREATE TABLE IF NOT EXISTS eshop.payment_operation_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id uuid NOT NULL REFERENCES eshop.refund_requests(id) ON DELETE RESTRICT,
 operation text NOT NULL,actor uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
 details jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE eshop.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.refund_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.payment_operation_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.refund_requests,eshop.refund_settlements,eshop.payment_operation_events FROM PUBLIC,anon,authenticated,service_role;
-- No current application producer exists. Retain historical requests read-only;
-- future writes must enter the same authorized command boundary.
REVOKE INSERT,UPDATE,DELETE ON eshop.bank_account_requests FROM PUBLIC,anon,authenticated,service_role;

-- A destructive remote preflight fences subsequent money operations until its
-- same receipted deletion completes. Uncertain external deletion never times out.
CREATE TABLE IF NOT EXISTS eshop.order_deletion_fences (
 order_id bigint PRIMARY KEY REFERENCES eshop.orders(id) ON DELETE CASCADE,
 command_id uuid NOT NULL,created_by uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE eshop.order_deletion_fences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.order_deletion_fences FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: user_permissions/payment_operations.sql
-- Typed operations bind scope from stored orders, never a caller-supplied unit.
CREATE OR REPLACE FUNCTION public.can_record_order_cash(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.get_is_manager_on_unit(oc.unit) AND NOT public.is_demo_occasion(o.occasion)
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order),false);
$$;
CREATE OR REPLACE FUNCTION public.can_prepare_order_bank_refund(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.can_manage_bank_account(pi.bank_account) AND public.get_is_manager_on_unit(oc.unit)
 AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link WHERE link.unit=oc.unit AND link.bank_account=pi.bank_account)
 AND NOT public.is_demo_occasion(o.occasion)
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=p_order),false);
$$;
CREATE OR REPLACE FUNCTION public.can_prepare_order_provider_refund(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_record_order_cash(p_order);
$$;
REVOKE ALL ON FUNCTION public.can_record_order_cash(bigint),public.can_prepare_order_bank_refund(bigint),public.can_prepare_order_provider_refund(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.can_record_order_cash(bigint),public.can_prepare_order_bank_refund(bigint),public.can_prepare_order_provider_refund(bigint) TO authenticated;

-- SOURCE: payment_providers/registry.sql
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
  IF jsonb_typeof(entry.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=entry.key AND hosted_checkout) THEN
   RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  PERFORM (entry.value#>>'{}')::uuid;
 END LOOP;
 IF config->'bankEnabled'='false'::jsonb AND config->'cashEnabled'<>'true'::jsonb
  AND NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE hosted_checkout AND public.payment_provider_connection_internal(config,provider_key) IS NOT NULL)
  AND EXISTS(SELECT 1 FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id JOIN eshop.products p ON p.product_type=ff.product_type
   WHERE f.id=p_form AND f.is_open AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false) AND p.price>0) THEN
  RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INCOMPLETE'; END IF;
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
 saved:=saved||jsonb_build_object('bankEnabled',coalesce(saved->'bankEnabled','true'),'providerConnections',connections,'cashEnabled',coalesce(saved->'cashEnabled','false'),'cashInstructions',coalesce(saved->'cashInstructions','""'::jsonb));
 IF p_input IS NULL THEN p_input:=saved; END IF;
 -- SQL NULL normalizes saved data; explicit JSON null resets inheritance.
 incoming:=CASE WHEN p_input='null'::jsonb THEN '{"bankEnabled":true,"providerConnections":{},"cashEnabled":false,"cashInstructions":""}'::jsonb ELSE p_input END;
 IF incoming->'cashEnabled'='null'::jsonb THEN incoming:=jsonb_set(incoming,'{cashEnabled}','false'); END IF;
 IF incoming->'cashInstructions'='null'::jsonb THEN incoming:=jsonb_set(incoming,'{cashInstructions}','""'); END IF;
 IF incoming->'bankEnabled'='null'::jsonb THEN incoming:=jsonb_set(incoming,'{bankEnabled}','true'); END IF;
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

-- SOURCE: payment_providers/financial_facts.sql
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
 RETURN facts;
END $$;
REVOKE ALL ON FUNCTION public.provider_financial_totals_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: payment_providers/operation_sync.sql
CREATE OR REPLACE FUNCTION public.record_payment_fact_sync_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occasion_id bigint; impacts jsonb;
BEGIN
 SELECT occasion INTO STRICT occasion_id FROM eshop.orders WHERE id=p_order;
 SELECT coalesce(jsonb_agg(jsonb_build_object('component','private_inventory','userId',"user")),'[]') INTO impacts
 FROM public.occasion_users WHERE occasion=occasion_id;
 PERFORM public.record_client_sync_commit_v1(occasion_id,'orders.payment.fact','inventory',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,'operation','update','changedFields',jsonb_build_array('payment'))),
  '{}'::text[],impacts,'[]'::jsonb,CASE WHEN auth.role()='service_role' THEN 'service' ELSE 'user' END,NULL);
END $$;
REVOKE ALL ON FUNCTION public.record_payment_fact_sync_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_transactions/payment_totals.sql
-- Actual bank/cash movements have one classification owner. A bank refund
-- retains its raw type; only the settlement classifies it as a return. Historical
-- signed manual corrections remain signed receipts. A voided cash refund stays
-- auditable in the ledger and is excluded from every financial projection.
CREATE OR REPLACE FUNCTION public.payment_transaction_movements_internal(p_payment bigint DEFAULT NULL)
RETURNS TABLE(transaction_id bigint,payment_info bigint,amount numeric,currency text,
 occurred_at timestamptz,is_refund boolean,voided boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT t.id,t.payment_info,t.amount,t.currency::text,t.date::timestamptz,
  coalesce(t.transaction_type='return',false) OR s.transaction_id IS NOT NULL,
  s.voided_at IS NOT NULL
 FROM eshop.transactions t LEFT JOIN eshop.refund_settlements s ON s.transaction_id=t.id
 WHERE p_payment IS NULL OR t.payment_info=p_payment;
$$;
REVOKE ALL ON FUNCTION public.payment_transaction_movements_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One financial projection over actual ledgers. External/manual settlement is
-- retained as its own fact; disputes are an availability hold, never a refund.
CREATE OR REPLACE FUNCTION public.payment_financial_totals_internal(p_payment bigint)
RETURNS TABLE(gross_received numeric,refunded numeric,external_received numeric,
 disputed numeric,net_received numeric,available numeric,invalid_identity boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH p AS (SELECT * FROM eshop.payment_info WHERE id=p_payment),
 bank AS (SELECT
  coalesce(sum(t.amount) FILTER(WHERE NOT t.is_refund AND NOT t.voided),0) received,
  abs(coalesce(sum(t.amount) FILTER(WHERE t.is_refund AND NOT t.voided),0)) returned,
  coalesce(bool_or(t.currency IS DISTINCT FROM p.currency_code),false) invalid
  FROM p JOIN LATERAL public.payment_transaction_movements_internal(p.id) t ON true),
 provider_raw AS (SELECT CASE WHEN NOT public.payment_method_is_online_internal(payment_method) THEN '{}'::jsonb
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

-- Call only while holding the canonical order/payment locks. Corrections and
-- unpairing may not consume funds already promised by an issued instruction.
CREATE OR REPLACE FUNCTION public.assert_payment_refund_reservations_internal(p_payment bigint,p_removed numeric DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE reserved numeric; facts record;
BEGIN
 SELECT coalesce(sum(amount),0) INTO reserved FROM eshop.refund_requests
 WHERE payment_info=p_payment AND status IN ('pending','processing','unknown');
 IF reserved=0 THEN RETURN; END IF;
 SELECT * INTO STRICT facts FROM public.payment_financial_totals_internal(p_payment);
 IF facts.invalid_identity OR facts.net_received-facts.disputed-p_removed<reserved THEN
  RAISE EXCEPTION 'PAYMENT_REFUND_RESERVATION_CONFLICT';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_payment_refund_reservations_internal(bigint,numeric) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_order_refund_delete_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE order_id=p_order)
 OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.transactions t ON t.payment_info=o.payment_info
   JOIN eshop.refund_settlements s ON s.transaction_id=t.id WHERE o.id=p_order) THEN
  RAISE EXCEPTION 'ORDER_HAS_REFUND_HISTORY';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_order_refund_delete_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

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
DECLARE o eshop.orders; u bigint; tx bigint; r eshop.refund_requests; pi_id bigint; cfg jsonb;
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
  RETURN jsonb_build_object('id','cash','displayName','Cash','record',public.can_record_order_cash(o.id),
   'refund',public.can_record_order_cash(o.id) AND trim(o.currency_code) IN ('CZK','EUR','PLN','USD','GBP'),
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
    (p_args->>'receivedAt')::timestamptz,p_args->>'note',o.payment_info,'correction',NULL);
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
  bank:=FOUND AND coalesce(cfg->'bankEnabled','true')='true'::jsonb;
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
   'refund',public.can_prepare_order_bank_refund((p_args->>'orderId')::bigint) AND ready IS NOT NULL,
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
  RETURN jsonb_build_object('providerId','barion','configured',binding IS NOT NULL,'available',false,
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
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('kind',m.kind,'amount_minor',m.amount_minor,'currency',m.currency,'occurred_at',m.occurred_at)),'[]') FROM eshop.barion_movements m WHERE attempt_id=a.id);
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

-- SOURCE: payment_providers/operations.sql
-- Private context is only embedded in authorized admin readers.
CREATE OR REPLACE FUNCTION public.payment_method_context_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; f record; r record; caps jsonb; methods jsonb:='[]'; pending numeric; requests jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF pi.id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO STRICT f FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount),0) INTO pending FROM eshop.refund_requests WHERE payment_info=pi.id AND status IN ('pending','processing','unknown');
 FOR r IN SELECT * FROM eshop.payment_providers WHERE
  (NOT public.payment_method_is_online_internal(pi.payment_method) AND NOT hosted_checkout)
  OR provider_key=pi.payment_method ORDER BY provider_key LOOP
  caps:=public.payment_provider_call_internal(r.provider_key,'operation_capabilities',jsonb_build_object('orderId',o.id));
  IF NOT r.refund_write_enabled THEN caps:=caps||jsonb_build_object('refund',false,'reason','refund_write_not_enabled'); END IF;
  IF r.hosted_checkout AND NOT public.can_prepare_order_provider_refund(o.id) THEN caps:=caps||jsonb_build_object('refund',false); END IF;
  IF caps->>'id' IS DISTINCT FROM r.provider_key THEN RAISE EXCEPTION 'PAYMENT_CAPABILITY_IDENTITY_MISMATCH'; END IF;
  IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=o.id) THEN caps:=caps||jsonb_build_object('refund',false,'record',false,'reason','order_deletion_in_progress'); END IF;
  IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE payment_info=pi.id AND result->'deviation'='true'::jsonb) THEN caps:=caps||jsonb_build_object('refund',false,'reason','refund_requires_review'); END IF;
  IF o.state NOT IN ('created','ordered','paid','sent','storno','expired') OR f.invalid_identity OR f.net_received<0 THEN
   caps:=caps||jsonb_build_object('refund',false,'reason','payment_identity_or_state_unavailable'); END IF;
  IF o.state IN ('storno','expired','waiting','preparing') THEN caps:=caps||jsonb_build_object('record',false); END IF;
  methods:=methods||jsonb_build_array(caps);
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'method',method,'verification',public.payment_method_verification_internal(method),'amount',amount::text,'currency',currency,
  'status',status,'createdAt',created_at,'instructions',CASE WHEN public.payment_method_verification_internal(method)='bank_event' AND public.can_prepare_order_bank_refund(p_order) THEN payload->'instructions' END,
  'canReopen',CASE WHEN public.payment_method_verification_internal(method)='bank_event' THEN public.can_prepare_order_bank_refund(p_order) ELSE public.can_prepare_order_provider_refund(p_order) END,
  'canCancel',public.payment_method_verification_internal(method)='bank_event' AND status='pending' AND public.can_prepare_order_bank_refund(p_order),
  'canCorrect',public.can_record_order_cash(p_order) AND public.payment_method_verification_internal(method)='local_commit' AND status='succeeded' AND EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.request_id=id AND s.voided_at IS NULL),
  'transactionId',(SELECT s.transaction_id FROM eshop.refund_settlements s WHERE s.request_id=id LIMIT 1)) ORDER BY created_at),'[]') INTO requests
 FROM eshop.refund_requests WHERE payment_info=pi.id;
 RETURN jsonb_build_object('gross',f.gross_received::text,'refunded',f.refunded::text,'net',f.net_received::text,
  'pending',pending::text,'available',greatest(f.available-pending,0)::text,'currency',trim(pi.currency_code),
  'methods',methods,'requests',requests,'invalidIdentity',f.invalid_identity,
  'due',greatest(coalesce(o.price,0)-f.net_received,0)::text,'deposit',pi.deposit_amount);
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
 start_result:=public.begin_client_mutation_v1(p_command_id,'orders.payment.operation',o.occasion,auth.uid(),encode(extensions.digest(input_data::text,'sha256'),'hex'));
 IF start_result->>'disposition'='replay' THEN RETURN jsonb_set(start_result->'response','{mutation,replayed}','true'); END IF;
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
  END IF;
 END IF;
 IF req.id IS NOT NULL THEN
  INSERT INTO eshop.payment_operation_events(request_id,operation,actor,details) VALUES(req.id,op,auth.uid(),input_data);
  SELECT * INTO req FROM eshop.refund_requests WHERE id=req.id;
  result:=result||jsonb_build_object('request',jsonb_build_object('id',req.id,'method',req.method,'verification',public.payment_method_verification_internal(req.method),'status',req.status,
   'amount',req.amount::text,'currency',req.currency,'instructions',req.payload->'instructions',
   'canReopen',CASE WHEN public.payment_method_verification_internal(req.method)='bank_event' THEN public.can_prepare_order_bank_refund(o.id) ELSE public.can_prepare_order_provider_refund(o.id) END,
   'canCancel',public.payment_method_verification_internal(req.method)='bank_event' AND req.status='pending' AND public.can_prepare_order_bank_refund(o.id),
   'canCorrect',public.payment_method_verification_internal(req.method)='local_commit' AND req.status='succeeded' AND public.can_record_order_cash(o.id)));
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
 IF amount<=0 OR amount>(c->>'available')::numeric THEN RAISE EXCEPTION 'REFUND_AVAILABLE_EXCEEDED'; END IF;
 threshold:=least(coalesce(pi.deposit_amount,o.price),o.price);
 RETURN jsonb_build_object('code',200,'preview',jsonb_build_object('netAfter',((c->>'net')::numeric-amount)::text,
  'availableAfter',((c->>'available')::numeric-amount)::text,'paidThreshold',threshold::text,
  'eligibleAfter',(c->>'net')::numeric-amount>=threshold,'lifecyclePreserved',o.state IN ('storno','expired') OR public.payment_method_is_online_internal(pi.payment_method),
  'currency',trim(pi.currency_code)));
END $$;
REVOKE ALL ON FUNCTION public.preview_payment_operation(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_payment_operation(jsonb) TO authenticated;

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
 IF NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=r.method AND hosted_checkout AND (refund_write_enabled OR r.dispatched_at IS NOT NULL)) OR r.status NOT IN ('pending','processing','unknown') THEN RETURN jsonb_build_object('disposition','read'); END IF;
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

-- SOURCE: payment_providers/bank_settlement.sql
-- Called after verified BankSync fact persistence, never from an untrusted client.
CREATE OR REPLACE FUNCTION public.observe_bank_refund_internal(p_transaction bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE t eshop.transactions; pi eshop.payment_info; o eshop.orders; req eshop.refund_requests;
 ns text; owner_id bigint; recipient text; reference text; current_ns text;
BEGIN
 SELECT * INTO STRICT t FROM eshop.transactions WHERE id=p_transaction FOR UPDATE;
 IF t.amount>=0 OR t.ingest_source NOT IN ('banksync_api','fio_api') THEN RETURN jsonb_build_object('matched',false); END IF;
 IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=t.id) THEN RETURN jsonb_build_object('matched',true,'replayed',true); END IF;
 SELECT a.namespace_id INTO ns FROM eshop.payment_reference_accounts a WHERE a.bank_account_id=t.bank_account_id;
 IF ns IS NULL THEN
  SELECT pa.namespace_id INTO ns FROM eshop.bank_sync_account_aliases a JOIN eshop.bank_sync_connections c ON c.id=a.connection_id
   JOIN eshop.payment_reference_accounts pa ON pa.bank_account_id=c.bank_account_id WHERE a.bank_account_id=t.bank_account_id;
 END IF;
 IF ns IS NULL THEN RETURN jsonb_build_object('matched',false); END IF;
 reference:=public.normalize_creditor_reference(t.payer_reference);
 IF t.currency='EUR' THEN
  SELECT p.id INTO owner_id FROM eshop.payment_reference_reservations r JOIN eshop.payment_info p ON p.id=r.payment_info_id
   WHERE r.namespace_id=ns AND r.original_payment_info_id=p.id AND r.variable_symbol=p.variable_symbol
    AND p.creditor_reference=reference;
 ELSE
  IF t.vs IS NULL OR trim(t.vs) !~ '^[0-9]{1,10}$' THEN RETURN jsonb_build_object('matched',false); END IF;
  SELECT r.payment_info_id INTO owner_id FROM eshop.payment_reference_reservations r
   WHERE r.namespace_id=ns AND r.variable_symbol=t.vs::bigint AND r.original_payment_info_id=r.payment_info_id;
 END IF;
 IF owner_id IS NULL THEN RETURN jsonb_build_object('matched',false); END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE payment_info=owner_id;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[o.id]);
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=owner_id FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.refund_requests WHERE payment_info=owner_id AND method='bank' AND reference_namespace=ns) THEN
  RETURN jsonb_build_object('matched',false); END IF;
 IF t.currency IS DISTINCT FROM trim(pi.currency_code) OR (t.payment_info IS NOT NULL AND t.payment_info<>pi.id) THEN
  RETURN jsonb_build_object('matched',false,'reason','scope_or_currency_mismatch'); END IF;
 recipient:=public.try_payment_reference_account_internal(CASE WHEN t.counter_account LIKE '%/%' OR t.counter_account ~ '^[A-Za-z]{2}' THEN t.counter_account
  ELSE t.counter_account||'/'||t.bank_code END);
 -- Destination verifies the immutable instruction; it never identifies the order.
 SELECT * INTO req FROM eshop.refund_requests WHERE payment_info=pi.id AND method='bank' AND reference_namespace=ns
  AND payload#>>'{instructions,recipientIban}'=recipient
  AND (t.date::date>=created_at::date OR payload->'existingDebits' @> jsonb_build_array(t.id)) ORDER BY (status IN ('pending','processing','unknown')) DESC,created_at DESC,id DESC LIMIT 1 FOR UPDATE;
 IF req.id IS NULL THEN RETURN jsonb_build_object('matched',false,'reason','recipient_or_date_mismatch'); END IF;
 UPDATE eshop.transactions SET payment_info=pi.id WHERE id=t.id;
 INSERT INTO eshop.refund_settlements(transaction_id,request_id) VALUES(t.id,req.id);
 UPDATE eshop.refund_requests SET status='succeeded',updated_at=now(),result=jsonb_build_object('transactionId',t.id,
  'actualAmount',(-t.amount)::text,'deviation',req.amount<>-t.amount OR req.status IN ('cancelled','succeeded')) WHERE id=req.id;
 INSERT INTO eshop.payment_operation_events(request_id,operation,details) VALUES(req.id,'bank_event',jsonb_build_object('transactionId',t.id,'amount',t.amount));
 INSERT INTO eshop.transaction_pairing_events(transaction_snapshot_id,transaction_id,new_payment_info_id,action,method,actor_kind,actor_id,details)
 VALUES(t.id,t.id,pi.id,'paired','refund_settlement',CASE WHEN auth.role()='service_role' THEN 'service' ELSE 'user' END,auth.uid(),jsonb_build_object('requestId',req.id));
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 PERFORM public.reconcile_order_payment_internal_v1(o.id,'refund_fact');
 PERFORM public.record_payment_fact_sync_internal(o.id);
 RETURN jsonb_build_object('matched',true,'orderId',o.id,'requestId',req.id);
END $$;
REVOKE ALL ON FUNCTION public.observe_bank_refund_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_bank_sync/ingest_bank_sync_transaction.sql
CREATE OR REPLACE FUNCTION public.ingest_bank_sync_transaction(
  p_instance_id text, p_consumer_app_id text, p_body_sha256 text, p_envelope jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
  v_data jsonb := p_envelope->'data';
  v_delivery text := p_envelope->>'delivery_id';
  v_connection eshop.bank_sync_connections%ROWTYPE;
  v_inbox eshop.bank_sync_inbox%ROWTYPE;
  v_tx eshop.transactions%ROWTYPE;
  v_ids bigint[];
  v_identity text := v_data->>'transaction_id';
  v_amount numeric;
  v_date timestamptz;
  v_outcome text;
  v_match jsonb;
  v_receipt jsonb;
  v_source_id bigint;
  v_command_id bigint;
  v_refund jsonb;
BEGIN
  PERFORM public.require_service_role();
  IF p_consumer_app_id IS DISTINCT FROM 'festapp' OR nullif(p_instance_id,'') IS NULL
    OR p_body_sha256 IS NULL OR p_body_sha256 !~ '^[0-9a-f]{64}$'
    OR p_envelope->>'event' IS DISTINCT FROM 'transaction.received'
    OR p_envelope->>'event_version' IS DISTINCT FROM '2'
    OR v_delivery IS NULL OR v_delivery !~ '^[0-9A-HJKMNP-TV-Z]{26}$'
    OR v_data->>'currency' IS NULL OR v_data->>'currency' NOT IN ('CZK','EUR','USD')
    OR jsonb_typeof(v_data->'amount_cents') IS DISTINCT FROM 'number'
    OR v_data->>'amount_cents' !~ '^-?[0-9]+$'
    OR abs((v_data->>'amount_cents')::numeric)>9007199254740991
    OR v_data->>'id' IS NULL OR v_data->>'bank_account_id' IS NULL
    OR v_data->>'date' IS NULL OR v_data->>'date' !~ 'T.*(Z|[+-][0-9]{2}:[0-9]{2})$' THEN
    RAISE EXCEPTION 'BANK_SYNC_INVALID_ENVELOPE';
  END IF;
  v_amount := (v_data->>'amount_cents')::numeric/100;
  v_date := (v_data->>'date')::timestamptz;
  IF v_data->>'direction' IS DISTINCT FROM (CASE WHEN v_amount>0 THEN 'incoming' WHEN v_amount<0 THEN 'outgoing' ELSE 'zero' END) THEN
    RAISE EXCEPTION 'BANK_SYNC_INVALID_DIRECTION';
  END IF;

  -- Lock order: delivery advisory -> connection -> identity/ledger -> payment_info.
  -- Legacy writers hold the same account row barrier before any ledger writes.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_instance_id||':'||p_consumer_app_id||':'||v_delivery,0));
  SELECT * INTO v_inbox FROM eshop.bank_sync_inbox
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id AND delivery_id=v_delivery;
  IF FOUND THEN
    IF v_inbox.body_sha256<>p_body_sha256 THEN RAISE EXCEPTION 'BANK_SYNC_DELIVERY_CONFLICT'; END IF;
    RETURN v_inbox.receipt;
  END IF;
  SELECT * INTO v_connection FROM eshop.bank_sync_connections
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id
      AND remote_bank_account_id=v_data->>'bank_account_id' FOR UPDATE;
  INSERT INTO eshop.bank_sync_inbox(instance_id,consumer_app_id,delivery_id,body_sha256,event_version,
    remote_transaction_id,connection_id,epoch,payload)
    VALUES(p_instance_id,p_consumer_app_id,v_delivery,p_body_sha256,'2',v_data->>'id',v_connection.id,v_connection.epoch,p_envelope);

  IF v_connection.id IS NULL THEN v_outcome:='quarantined_scope';
  ELSIF v_connection.state='shadow' THEN v_outcome:='shadow_recorded';
  ELSIF v_connection.state NOT IN ('connected','degraded') OR v_connection.legacy_blocked_at IS NULL THEN v_outcome:='quarantined_scope';
  ELSIF v_data->>'identity_kind' IS DISTINCT FROM 'movement'
    OR v_data->>'identity_provenance' IS DISTINCT FROM 'fio_api_column22'
    OR v_data->>'source' IS DISTINCT FROM 'fio_api'
    OR v_connection.provider<>'FIO' OR nullif(v_identity,'') IS NULL THEN
    v_outcome:='quarantined_identity';
  ELSE
    SELECT t.* INTO v_tx FROM eshop.bank_transaction_identities i
      JOIN eshop.transactions t ON t.id=i.transaction_id
      WHERE i.instance_id=p_instance_id AND i.provider=v_connection.provider
        AND i.physical_account=v_connection.physical_account AND i.identity_kind='movement' AND i.identity_value=v_identity
      FOR UPDATE OF t;
    IF v_tx.id IS NULL AND v_identity ~ '^[0-9]{1,19}$' AND v_identity::numeric<=9223372036854775807 THEN
      v_source_id:=v_identity::bigint;
      SELECT array_agg(id ORDER BY id) INTO v_ids FROM eshop.transactions
        WHERE transaction_id=v_source_id AND ingest_source='fio_api'
          AND (bank_account_id=v_connection.bank_account_id OR bank_account_id IN
            (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=v_connection.id));
      IF cardinality(v_ids)>1 THEN v_outcome:='quarantined_conflict';
      ELSIF cardinality(v_ids)=1 THEN SELECT * INTO v_tx FROM eshop.transactions WHERE id=v_ids[1] FOR UPDATE;
      END IF;
    END IF;
    IF v_outcome IS NULL AND v_tx.id IS NOT NULL THEN
      IF NOT public.bank_sync_existing_facts_match(v_tx,v_data) THEN
        v_outcome:='quarantined_conflict';
      ELSE v_outcome:='already_ingested';
      END IF;
    END IF;
    IF v_outcome IS NULL THEN
      IF v_data->>'command_id' ~ '^[0-9]{1,19}$' AND (v_data->>'command_id')::numeric<=9223372036854775807 THEN
        v_command_id:=(v_data->>'command_id')::bigint;
      END IF;
      INSERT INTO eshop.transactions(transaction_id,bank_account_id,amount,currency,date,vs,ks,ss,
        command_id,payer_reference,message_for_recipient,counter_account,counter_account_name,bank_code,bank_name,
        user_identification,transaction_type,performed_by,comment,ingest_source)
        VALUES(v_source_id,v_connection.bank_account_id,v_amount,v_data->>'currency',v_date AT TIME ZONE 'UTC',
          nullif(v_data->>'raw_vs',''),nullif(v_data->>'ks',''),nullif(v_data->>'ss',''),v_command_id,
          v_data->>'payer_reference',v_data->>'message',v_data->>'counter_account',v_data->>'sender_name',
          v_data->>'bank_code',v_data->>'bank_name',v_data->>'user_identification',v_data->>'transaction_type',
          v_data->>'performed_by',v_data->>'comment','banksync_api') RETURNING * INTO v_tx;
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'movement',v_identity,v_tx.id);
      IF v_amount<0 THEN v_outcome:='stored_outgoing';
      ELSIF v_amount=0 THEN v_outcome:='stored_zero';
      ELSE
        v_match:=public.payment_provider_call_internal('bank','observe_payment',jsonb_build_object('transactionId',v_tx.id));
        v_outcome:=v_match->>'verdict';
        IF v_outcome NOT IN ('paired','unmatched','ambiguous','ineligible','already_paired') OR v_outcome IS NULL THEN
          RAISE EXCEPTION 'BANK_SYNC_MATCHER_INVALID_RESULT';
        END IF;
        IF v_outcome='already_paired' THEN v_outcome:='already_ingested'; END IF;
      END IF;
    END IF;
    IF v_outcome<>'quarantined_conflict' THEN
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'movement',v_identity,v_tx.id)
        ON CONFLICT (instance_id,provider,physical_account,identity_kind,identity_value) DO UPDATE
          SET transaction_id=eshop.bank_transaction_identities.transaction_id
          WHERE eshop.bank_transaction_identities.transaction_id=EXCLUDED.transaction_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_IDENTITY_CONFLICT'; END IF;
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'remote_transaction',v_data->>'id',v_tx.id)
        ON CONFLICT (instance_id,provider,physical_account,identity_kind,identity_value) DO UPDATE
          SET transaction_id=eshop.bank_transaction_identities.transaction_id
          WHERE eshop.bank_transaction_identities.transaction_id=EXCLUDED.transaction_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_IDENTITY_CONFLICT'; END IF;
    END IF;
  END IF;
  IF v_tx.id IS NOT NULL AND v_tx.amount<0 AND v_outcome IN ('stored_outgoing','already_ingested') THEN
    v_refund:=public.payment_provider_call_internal('bank','observe_refund',jsonb_build_object('transactionId',v_tx.id));
  END IF;
  v_receipt:=jsonb_build_object('ok',true,'receipt_version',1,'delivery_id',v_delivery,'outcome',v_outcome,'refund',v_refund);
  UPDATE eshop.bank_sync_inbox SET outcome=v_outcome,receipt=v_receipt,committed_at=now()
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id AND delivery_id=v_delivery;
  UPDATE eshop.bank_sync_connections SET receiver_commit_at=now(),
    last_error=CASE WHEN v_outcome LIKE 'quarantined_%' THEN v_outcome ELSE last_error END WHERE id=v_connection.id;
  RETURN v_receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) TO service_role;

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

        -- Revalidate current configuration under the form lock, including invoice
        -- services added after the form was saved. Never bypass mandatory invoicing.
        PERFORM public.validate_form_payment_configuration_internal(form_id);
        v_payment_method:=coalesce(input_data->>'payment_method',CASE WHEN form_data#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' ELSE 'bank' END);
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

        UPDATE eshop.payment_info SET data=coalesce(data,'{}')||jsonb_build_object('payment_policy',v_payment_policy-'durationSeconds') WHERE id=payment_info_id;
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

-- SOURCE: eshop_forms/form_settings.sql
-- Metadata patch owner for all administrative form settings. Private helpers;
-- authorization, locking, receipt and side effects stay in the form command.
CREATE OR REPLACE FUNCTION public.form_settings_keys_internal()
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT '{"is_reminder_enabled":null,"reminder_interval_seconds":null,"communication_tone":null,
 "variable_symbol":["type","starting_number"],"payment_message":["type"],
 "payments":["bankEnabled","stripeConnectionId","providerConnections","cashEnabled","cashInstructions"],
 "payment_deadline":["mode"],
 "analytics":["enabled"],
 "design":["embed_inherit_style","is_card_design","primary_color","secondary_color","background_mode","theme_mode","font_family","countdown_style","presale_header"],
 "sale_opening_notifications":["enabled","collection_paused"],
 "schedule":["start_time","end_time","enable_countdown","countdown_title"]}'::jsonb;
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
  IF spec.key IN ('payments','sale_opening_notifications','analytics') AND NOT d ? spec.key THEN CONTINUE; END IF;
  IF spec.value='null'::jsonb OR NOT d ? spec.key OR d->spec.key='null'::jsonb THEN
   result:=result||jsonb_build_object(spec.key,coalesce(d->spec.key,'null'::jsonb));
  ELSE
   IF spec.key='payments' THEN result:=result||jsonb_build_object(spec.key,d->spec.key); CONTINUE; END IF;
   IF jsonb_typeof(d->spec.key)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form settings section: '||spec.key; END IF;
   section:='{}';
   FOR k IN SELECT jsonb_array_elements_text(spec.value) LOOP
    IF spec.key<>'analytics' OR (d->spec.key) ? k THEN
     section:=section||jsonb_build_object(k,coalesce(d->spec.key->k,'null'::jsonb));
    END IF;
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
 IF result ? 'analytics' AND result->'analytics'<>'null'::jsonb AND (jsonb_typeof(result->'analytics')<>'object' OR
   EXISTS(SELECT 1 FROM jsonb_object_keys(result->'analytics') analytics_key WHERE analytics_key<>'enabled')) THEN
  RAISE invalid_parameter_value USING MESSAGE='unsupported analytics setting'; END IF;
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
   IF path IN ('analytics.enabled','payments.bankEnabled','design.embed_inherit_style','design.is_card_design','schedule.enable_countdown','sale_opening_notifications.enabled','sale_opening_notifications.collection_paused') THEN
    IF jsonb_typeof(v)<>'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='invalid boolean setting: '||path; END IF;
   ELSIF path='payments.providerConnections' THEN
    IF jsonb_typeof(v)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid provider connections'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_each(v) x WHERE jsonb_typeof(x.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=x.key AND hosted_checkout)) THEN
     RAISE invalid_parameter_value USING MESSAGE='unknown payment provider'; END IF;
    PERFORM (x.value#>>'{}')::uuid FROM jsonb_each(v) x;
   ELSIF path='variable_symbol.starting_number' THEN
    IF jsonb_typeof(v)<>'number' OR v::text !~ '^[0-9]{1,10}$' OR (v::text)::bigint NOT BETWEEN 1 AND 9999999999 THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid sequence starting number'; END IF;
   ELSE
    IF jsonb_typeof(v)<>'string' THEN RAISE invalid_parameter_value USING MESSAGE='invalid string setting: '||path; END IF;
    IF length(v#>>'{}')>(CASE WHEN path IN ('schedule.countdown_title') THEN 65536 ELSE 128 END) THEN
     RAISE invalid_parameter_value USING MESSAGE='form setting too long: '||path; END IF;
    IF path='payment_deadline.mode' AND v NOT IN ('"inherit"'::jsonb,'"custom"'::jsonb,'"none"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid payment deadline mode'; END IF;
    IF path='variable_symbol.type'  AND v NOT IN ('"random"'::jsonb,'"sequence"'::jsonb) OR
       path='payment_message.type' AND v NOT IN ('"name_surname"'::jsonb,'"none"'::jsonb,'"occasion_title"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid setting mode: '||path; END IF;
    IF path='design.presale_header' AND v NOT IN ('"event_and_date"'::jsonb,'"date"'::jsonb,'"none"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid presale header'; END IF;
    IF path='design.theme_mode'  AND v NOT IN ('"system"'::jsonb,'"light"'::jsonb,'"dark"'::jsonb) THEN
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

  -- A settled movement is immutable through the generic attach/unlink API.
  -- Cash voids and evidenced bank reclassification have their explicit owner.
  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id)
     AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION';
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0
     AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b WHERE b.id=v_transaction.bank_account_id
       AND upper(b.type)='CASH' AND v_transaction.transaction_type='manual'
       AND v_transaction.ingest_source='manual') THEN
    RAISE EXCEPTION 'OUTGOING_REQUIRES_REFUND_CLASSIFICATION';
  END IF;
  IF v_old_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.assert_payment_refund_reservations_internal(v_old_payment_info_id,greatest(v_transaction.amount,0));
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0 THEN
    PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-v_transaction.amount);
  END IF;

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
    IF public.payment_method_is_online_internal(v_target.payment_method) THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_target.payment_method='cash' AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b
      WHERE b.id=v_transaction.bank_account_id AND b.type='CASH' AND v_transaction.transaction_type='manual') THEN
      RAISE EXCEPTION 'CASH_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_transaction.transaction_type='manual' THEN
      IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
        JOIN eshop.orders o ON o.occasion=oc.id JOIN eshop.bank_accounts b ON b.id=link.bank_account
        WHERE o.payment_info=v_target.id AND b.id=v_transaction.bank_account_id ) THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
    END IF;
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
DECLARE
  v_unit_id bigint;
BEGIN
  SELECT oc.unit INTO v_unit_id
  FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id AND upper(b.type)='CASH'
  JOIN eshop.orders o ON o.payment_info=t.payment_info JOIN public.occasions oc ON oc.id=o.occasion
  JOIN eshop.unit_bank_accounts l ON l.bank_account=b.id AND l.unit=oc.unit
  WHERE t.id=p_transaction_id AND t.payment_info=p_payment_info_id AND t.transaction_type='manual';
  IF NOT FOUND THEN RAISE EXCEPTION 'MANUAL_TRANSACTION_PAIRING_MISMATCH'; END IF;
  IF NOT public.can_manage_unit_bank_accounts(v_unit_id) THEN
    RAISE insufficient_privilege USING MESSAGE='Cash correction requires unit manager'; END IF;

  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id) THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION'; END IF;
  PERFORM public.apply_transaction_pairing(
    p_transaction_id, NULL, 'manual_delete_unlink', 'user'
  );
  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind
  ) VALUES (
    p_transaction_id, p_transaction_id, p_payment_info_id,
    NULL, 'manual_deleted', 'manual_delete', auth.uid(), 'user'
  );
  DELETE FROM eshop.transactions WHERE id = p_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_manual_transaction_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_manual_transaction_ws(bigint,bigint)
  TO authenticated;

-- SOURCE: eshop_transactions/get_transactions_for_order.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id bigint;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT can_read_orders(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'order_state', o.state,
      'paymentOperations',public.payment_method_context_internal(o.id),
      'actions', jsonb_build_object(
        'canAddCash', EXISTS(SELECT 1 FROM jsonb_array_elements(public.payment_method_context_internal(o.id)->'methods') m WHERE m->>'id'='cash' AND m->'record'='true'::jsonb),
        'canConfigureBank', public.can_manage_unit_bank_accounts(oc.unit),
        'bankState', CASE WHEN NOT public.can_read_unit_bank_accounts(oc.unit) THEN 'restricted'
          WHEN EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN eshop.bank_accounts b ON b.id=l.bank_account
            WHERE l.unit=oc.unit AND upper(b.type)<>'CASH') THEN 'configured' ELSE 'absent' END,
        'pairingAccountId', CASE WHEN pi.payment_method='bank' AND public.can_manage_bank_account(pi.bank_account)
          AND public.can_write_orders(o.occasion) AND o.state IN ('created','ordered','paid','sent') THEN pi.bank_account END,
        'unitId', oc.unit,
        'removableTransactionIds', (SELECT coalesce(jsonb_agg(t.id),'[]')
          FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
          WHERE t.payment_info=o.payment_info AND o.state IN ('created','ordered','paid','sent')
          AND NOT public.payment_method_is_online_internal(pi.payment_method)
          AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id)
          AND CASE WHEN t.transaction_type='manual' THEN upper(b.type)='CASH'
            AND public.can_manage_unit_bank_accounts(oc.unit) AND EXISTS(
              SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=oc.unit AND l.bank_account=b.id)
            ELSE public.can_write_orders(o.occasion) AND public.can_manage_bank_account(b.id) END),
        'historyAccounts', (SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',b.title) ORDER BY b.id),'[]')
          FROM public.get_my_admin_bank_accounts() b WHERE upper(b.type)<>'CASH')
      ),
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', COALESCE((
        SELECT jsonb_agg(
            to_jsonb(t) || jsonb_build_object('isRefund',m.is_refund,'voided',m.voided,'createdByName',
                trim(both from COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, ''))
            )
        )
        FROM eshop.transactions t
        JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id
        LEFT JOIN public.user_info ui ON t.created_by = ui.id
        WHERE t.payment_info = o.payment_info
      ), '[]'::jsonb)
    )
    FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id = order_id
  );
END;
$$;

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

-- An explicit personal account reader. Order access never grants this history.
CREATE OR REPLACE FUNCTION public.get_bank_transaction_history(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_read_bank_transactions(p_bank_account_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Bank history access denied'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(t ORDER BY t.date DESC,t.id),'[]') FROM eshop.transactions t
  JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
  WHERE b.id=p_bank_account_id AND upper(b.type)<>'CASH');
END $$;
REVOKE ALL ON FUNCTION public.get_bank_transaction_history(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_transaction_history(bigint) TO authenticated;

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
    IF p_reason IS NULL OR p_reason NOT IN ('payment_fact','product_edit','refund_fact') THEN
        RAISE EXCEPTION 'INVALID_PAYMENT_RECONCILIATION_REASON';
    END IF;
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=p_order_id FOR UPDATE;
    SELECT * INTO v_payment FROM eshop.payment_info WHERE id=v_order.payment_info FOR UPDATE;
    v_was_eligible := coalesce(v_order.state IN ('paid','sent'),false);
    -- Provider facts and non-admission shells retain their existing owners.
    IF v_payment.id IS NULL OR public.payment_method_is_online_internal(v_payment.payment_method)
       OR v_order.state NOT IN ('created','ordered','expired','paid','sent') THEN
        RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_order.state,
            'eligibility_changed',false,'email_payment_version',v_order.email_payment_version);
    END IF;

    IF p_reason='refund_fact' AND v_order.state IN ('storno','expired') THEN
        RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_order.state,
            'eligibility_changed',false,'email_payment_version',v_order.email_payment_version);
    END IF;

    IF p_reason='product_edit' THEN
        PERFORM public.ensure_order_payment_instructions_internal(p_order_id);
        SELECT * INTO v_payment FROM eshop.payment_info WHERE id=v_order.payment_info;
    END IF;

    -- The saved deposit is a commercial snapshot, capped by the current price.
    v_eligible := coalesce(v_order.price,0)<=0 OR (coalesce(v_payment.paid,0)-coalesce(v_payment.returned,0))>=
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

    -- Cancellation above invalidates the old reminder version. Rebuild only this
    -- payment's eligible reminders, including the balance after a paid deposit.
    IF p_reason='product_edit' OR v_eligible IS DISTINCT FROM v_was_eligible THEN
        PERFORM public.queue_payment_reminders_internal(v_order.occasion,v_payment.id);
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

-- SOURCE: eshop_orders/update_order_and_tickets_to_paid.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_paid(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id bigint;
    transition_result jsonb;
BEGIN
    transition_result := public.mark_order_and_tickets_paid_internal_v1(order_id);
    IF transition_result->>'code' IS DISTINCT FROM '200' THEN
        RETURN transition_result;
    END IF;
    SELECT occasion INTO occasion_id FROM eshop.orders WHERE id=order_id;

    -- Queue deposit-paid or fully-paid email for orders with deposit
    DECLARE
        v_deposit_amount NUMERIC;
        v_total_amount NUMERIC;
        v_total_paid NUMERIC;
        v_email_code TEXT;
        v_org_id BIGINT;
        v_unit_id BIGINT;
    BEGIN
        -- Fetch payment info for this order
        SELECT pi.deposit_amount, pi.amount, coalesce(pi.paid,0)-coalesce(pi.returned,0)
        INTO v_deposit_amount, v_total_amount, v_total_paid
        FROM eshop.payment_info pi
        JOIN eshop.orders o ON o.payment_info = pi.id
        WHERE o.id = order_id;

        -- Only queue emails for deposit orders. The template handler branches
        -- internally on amountPaid >= totalAmount to render either the
        -- deposit-paid copy (with remaining balance + QR) or the fully-paid copy.
        IF v_deposit_amount IS NOT NULL AND v_total_paid >= v_deposit_amount THEN
            -- Get organization and unit from occasion
            SELECT occ.organization, occ.unit
            INTO v_org_id, v_unit_id
            FROM public.occasions occ
            WHERE occ.id = occasion_id;

            v_email_code := 'TICKET_ORDER_PAYMENT_DONE';

            IF v_email_code IS NOT NULL THEN
                PERFORM public.enqueue_order_email(v_email_code,jsonb_build_object('order_id',order_id),v_org_id,occasion_id,v_unit_id);
            END IF;
        END IF;
    END;

    PERFORM public.enqueue_paid_order_tickets(order_id);

    -- Return a success message with a status code 200
    RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
EXCEPTION WHEN OTHERS THEN
    -- Rollback is automatic on exception
    RETURN jsonb_build_object(
        'code', 500,
        'message', SQLERRM,
        'detail', coalesce(SQLERRM, 'An unexpected error occurred')
    );
END;
$function$;

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

-- SOURCE: eshop_orders/get_orders.sql
CREATE OR REPLACE FUNCTION public.get_orders(
    p_occasion_link TEXT,
    p_form_link TEXT DEFAULT NULL,
    p_options JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_form_id BIGINT;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    ordersHistoryData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
    usersData JSONB; -- ADDED: Variable for user info data
BEGIN
    -- This function retrieves order and reservation details for a given occasion.
    -- It can conditionally include related data like spots, history, and users.
    --
    -- 'include_orders_history': If true, it fetches 'orders_history' and the
    --                           associated 'users' who created those history records.

    -- 1. Input Validation: Ensure at least one link is provided.
    IF p_occasion_link IS NULL AND p_form_link IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Either occasion_link or form_link must be provided');
    END IF;

    -- 2. Determine occasion_id based on the provided link.
    IF p_occasion_link IS NOT NULL THEN
        SELECT id
        INTO v_occasion_id
        FROM public.occasions
        WHERE id = public.resolve_occasion_link_internal(p_occasion_link)
          AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());
    ELSE
        SELECT occasion, id
        INTO v_occasion_id, v_form_id
        FROM public.forms
        WHERE id = public.resolve_form_link_internal(p_form_link)
          AND occasion IN (SELECT o.id FROM public.occasions o WHERE o.organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()));
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT can_read_orders(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Conditionally fetch spots based on p_options for optimization
    IF (p_options->>'include_spots')::BOOLEAN = TRUE THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', s.id,
            'title', s.title,
            'product', s.product,
            'order_product_ticket', s.order_product_ticket,
            'state', CASE
                WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
                WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
                ELSE 'available'
            END
        ))
        INTO spotsData
        FROM eshop.spots s
        WHERE s.occasion = v_occasion_id
          AND s.order_product_ticket IS NOT NULL;
    END IF;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = v_occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'updated_at', t.updated_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden,
        'batch', (SELECT jsonb_build_object('id',i.batch_id,'title',b.title,'ordinal',i.ordinal,'saleOrderId',i.sale_order_id) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=t.id),
        'allowedActions',CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items i WHERE i.ticket_id=t.id) THEN
          jsonb_build_array('view') || CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts d WHERE d.kind='single' AND d.ticket_ids=ARRAY[t.id] AND d.state='ready') THEN jsonb_build_array('download') ELSE '[]'::jsonb END ||
          CASE WHEN public.can_write_orders(t.occasion) THEN jsonb_build_array('note') ||
            CASE WHEN t.state<>'storno' AND EXISTS(SELECT 1 FROM eshop.ticket_batch_items i WHERE i.ticket_id=t.id AND i.sale_order_id IS NOT NULL)
              THEN jsonb_build_array('use','reset','cancel') ELSE '[]'::jsonb END ELSE '[]'::jsonb END END,
        'data', t.data
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = v_occasion_id;

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'participant_capacity',f.participant_capacity,
        'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,
        'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'capacity',public.get_form_capacity_snapshot_internal(f.id),
        'registrationMode',public.get_form_registration_mode_internal(f.id),
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'title', f.title
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Ordinary orders need only activity/actions. Resolve ticket/offer lifecycles
    -- once only for orders that expose a full waitlist summary.
    WITH selected_orders AS MATERIALIZED (
        SELECT o.*, CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
          OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
          THEN public.get_waitlist_summary_internal(o.id)
          ELSE public.get_order_action_summary_internal(o.state)
        END AS waitlist_summary
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id
          AND (v_form_id IS NULL OR o.form = v_form_id)
    )
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN o.waitlist_summary END,
            'isActive',(o.waitlist_summary->>'isActive')::boolean,
            'allowedActions',public.get_order_allowed_actions_internal_v1(o.id,o.waitlist_summary),
            'paymentChannel',CASE WHEN o.data ? 'ticketBatchOrigin' THEN 'cash' END,
            'batchId',(SELECT b.id FROM eshop.ticket_batches b WHERE b.stock_order_id=o.id),
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data || jsonb_build_object('tickets', public.order_tickets_with_seating_internal(o.id,o.data->'tickets'))
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM selected_orders o;

    -- Extract order IDs from the (potentially filtered) ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object('id', opt.id, 'order', opt."order", 'product', opt.product, 'ticket', opt.ticket))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id, 'payment_method', pi.payment_method, 'bank_account', pi.bank_account, 'variable_symbol', pi.variable_symbol, 'amount', pi.amount, 'deposit_amount', pi.deposit_amount,
        'deposit_deadline', pi.deposit_deadline, 'paid', pi.paid, 'returned', pi.returned, 'net',coalesce(pi.paid,0)-coalesce(pi.returned,0),
        'pending',(SELECT coalesce(sum(r.amount),0) FROM eshop.refund_requests r WHERE r.payment_info=pi.id AND r.status IN ('pending','processing','unknown')),
        'paymentOperations',public.payment_method_context_internal((SELECT id FROM eshop.orders WHERE payment_info=pi.id)), 'deadline', pi.deadline, 'currency_code', pi.currency_code, 'data', pi.data,
        'bank_sync_warning', public.bank_sync_warning(pi.bank_account)
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        WHERE order_obj->>'payment_info' IS NOT NULL
    );

    -- Conditionally fetch orders history and related users based on p_options
    IF (p_options->>'include_orders_history')::BOOLEAN = TRUE THEN
        -- First, fetch the history records
        WITH order_ids AS (
            SELECT (order_obj->>'id')::BIGINT AS id
            FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', oh.id, 'created_at', oh.created_at, 'created_by', oh.created_by, 'data', oh.data,
            'order', oh."order", 'order_symbol', (SELECT o.order_symbol FROM eshop.orders o WHERE o.id=oh."order"), 'order_sequence', (SELECT o.order_sequence FROM eshop.orders o WHERE o.id=oh."order"), 'state', oh.state, 'price', oh.price, 'currency_code', oh.currency_code
        ))
        INTO ordersHistoryData
        FROM eshop.orders_history oh
        WHERE oh."order" IN (SELECT id FROM order_ids);

        -- Second, fetch the unique users who created those history records
        WITH user_ids AS (
            SELECT DISTINCT (history_obj->>'created_by')::UUID AS id
            FROM jsonb_array_elements(COALESCE(ordersHistoryData, '[]'::jsonb)) history_obj
            WHERE history_obj->>'created_by' IS NOT NULL
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', ui.id,
            'name', ui.name,
            'surname', ui.surname,
            'email_readonly', ui.email_readonly
        ))
        INTO usersData
        FROM public.user_info ui
        WHERE ui.id IN (SELECT id FROM user_ids);
    END IF;


    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'occasion_id', v_occasion_id,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb),
            'orders_history', COALESCE(ordersHistoryData, '[]'::jsonb),
            'users', COALESCE(usersData, '[]'::jsonb)
        )
    );
END;
$$;

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
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'net',(coalesce(p.paid,0)-coalesce(p.returned,0))::text,'pending',(SELECT coalesce(sum(r.amount),0)::text FROM eshop.refund_requests r WHERE r.payment_info=p.id AND r.status IN ('pending','processing','unknown'))) END)
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_snapshot_internal_v1(p_order bigint,p_detail boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.operator_order_facts_internal_v1(o.id) || jsonb_build_object(
   'createdAt',o.created_at,'updatedAt',o.updated_at,'revision',public.operator_order_revision_internal_v1(o.id),
   'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('method',p.payment_method,'amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'net',(coalesce(p.paid,0)-coalesce(p.returned,0))::text,'pending',(SELECT coalesce(sum(r.amount),0)::text FROM eshop.refund_requests r WHERE r.payment_info=p.id AND r.status IN ('pending','processing','unknown')),'policy',p.data->'payment_policy','variableSymbol',p.variable_symbol::text,'deadline',p.deadline) END)
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
   IF p_changes - ARRAY['responses','note','tickets','paymentDeadline']::text[]<>'{}'::jsonb OR p_changes='{}' THEN RAISE invalid_parameter_value USING MESSAGE='invalid order changes'; END IF;
   IF p_changes ? 'paymentDeadline' THEN
     IF v_pi.id IS NULL OR public.payment_method_is_online_internal(v_pi.payment_method)
       OR jsonb_typeof(p_changes->'paymentDeadline') NOT IN ('null','string') THEN
       RAISE invalid_parameter_value USING MESSAGE='payment deadline unavailable'; END IF;
     PERFORM public.check_order_is_mutable(p_order);
     PERFORM public.set_payment_deadline(v_pi.id,(p_changes->>'paymentDeadline')::timestamptz);
     INSERT INTO eshop.orders_history("order",data,state,price,currency_code)
     VALUES(p_order,v_order.data||jsonb_build_object('payment',public.customer_order_payment_internal(p_order)),v_order.state,v_order.price,v_order.currency_code);
   END IF;
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
     OR v_pi.id IS NULL OR public.payment_method_is_online_internal(v_pi.payment_method) OR (p_changes->>'currency') IS DISTINCT FROM trim(v_order.currency_code)
     OR (p_changes->>'amount') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' OR (p_changes->>'amount')::numeric<=0 THEN
     RAISE invalid_parameter_value USING MESSAGE='manual payment unavailable'; END IF;
   PERFORM public.command_payment_operation(p_changes||jsonb_build_object('operation','record_payment',
     'orderId',p_order,'method','cash'),md5(p_command_id::text||':payment')::uuid);
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

-- SOURCE: eshop_orders/get_order_deletion_context_v1.sql
-- Public metadata only. Credentials stay in the service-role external-services RPC.
CREATE OR REPLACE FUNCTION public.get_order_deletion_context_v1(
  p_order bigint, p_command_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion bigint; v_unit bigint; v_state text; v_vs bigint;
  v_command text; v_response jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;
  -- Deletion removes the order, so a lost response is recovered from its receipt.
  IF p_command_id IS NOT NULL THEN
    SELECT CASE WHEN r.status='expired' THEN public.expired_client_mutation_response_v1(r)
      ELSE r.response END INTO v_response FROM public.client_mutation_receipts r
    JOIN public.occasions oc ON oc.id=r.occasion
    WHERE r.command_id=p_command_id AND r.actor_id=auth.uid()
      AND r.command_name='inventory.order.delete' AND r.status IN ('completed','expired')
      AND r.request_sha256=encode(extensions.digest(convert_to(
        jsonb_build_object('order',p_order)::text,'UTF8'),'sha256'),'hex')
      AND public.can_delete_orders(oc.id);
    IF FOUND THEN RETURN jsonb_build_object('response',v_response); END IF;
    IF EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id) THEN
      RAISE insufficient_privilege USING MESSAGE='command id unavailable';
    END IF;
  END IF;
  SELECT o.occasion,oc.unit,o.state,pi.variable_symbol
    INTO v_occasion,v_unit,v_state,v_vs
  FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=p_order;
  IF v_occasion IS NULL OR NOT public.can_delete_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;
  PERFORM public.check_occasion_writable(v_occasion);
  IF v_state IN ('waitlisted','preparing_payment')
    OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=p_order)
    OR EXISTS(SELECT 1 FROM eshop.orders WHERE source_waitlist_order_id=p_order)
    OR EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts
      WHERE target_order_id=p_order OR source_order_id=p_order) THEN
    RAISE EXCEPTION 'ORDER_HAS_WAITLIST_HISTORY';
  END IF;
  IF p_command_id IS NOT NULL THEN
    -- A committed fence survives the gap between this RPC and external invoice
    -- deletion. Financial commands check it under the same order lock.
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
    SELECT o.occasion,oc.unit,o.state,pi.variable_symbol INTO v_occasion,v_unit,v_state,v_vs
    FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=p_order;
    IF v_occasion IS NULL OR NOT public.can_delete_orders(v_occasion) THEN
      RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
    END IF;
  END IF;
  PERFORM public.check_order_refund_delete_internal(p_order);
  IF p_command_id IS NOT NULL THEN
    INSERT INTO eshop.order_deletion_fences(order_id,command_id,created_by)
    VALUES(p_order,p_command_id,auth.uid()) ON CONFLICT(order_id) DO NOTHING;
    IF NOT EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=p_order
      AND command_id=p_command_id AND created_by=auth.uid()) THEN
      RAISE EXCEPTION 'ORDER_DELETION_IN_PROGRESS';
    END IF;
  END IF;
  -- Metadata reads do not charge. External deletion attempts share the order
  -- mutation burst budget before credentials/provider work; final SQL charges
  -- its own mutation and item count through the existing command boundary.
  IF p_command_id IS NOT NULL THEN
    PERFORM public.admit_order_mutation_v1(v_occasion,0);
  END IF;
  SELECT m.data->>'command_id' INTO v_command FROM public.email_messages m
    WHERE m.order_id=p_order AND m.code='TICKET_ORDER_CONFIRMATION'
    ORDER BY m.id DESC LIMIT 1;
  RETURN jsonb_build_object('hasFakturoid',EXISTS(
    SELECT 1 FROM eshop.external_services WHERE unit=v_unit AND type='FAKTUROID'),
    'commandId',v_command,'variableSymbol',v_vs);
END; $$;
REVOKE ALL ON FUNCTION public.get_order_deletion_context_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_order_deletion_context_v1(bigint,uuid)
  TO authenticated;

-- SOURCE: eshop_orders/delete_order.sql
CREATE OR REPLACE FUNCTION public.delete_order_internal_v1(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  payment_info_id BIGINT;
  order_product_ticket_ids BIGINT[];
  ticket_ids BIGINT[];
  order_oc BIGINT;
  ou_record RECORD;
  form_id BIGINT;
  related_orders BIGINT[];
  offer_ids UUID[];
  v_activity_impacts jsonb := '[]'::jsonb;
BEGIN
  -- Retrieve the order's occasion and payment_info.
  SELECT occasion, payment_info, form
    INTO order_oc, payment_info_id, form_id
    FROM eshop.orders
   WHERE id = delete_order_internal_v1.order_id;

  IF order_oc IS NULL THEN
    RAISE EXCEPTION 'Order not found.';
  END IF;

  -- Deletion belongs to scoped unit managers/editors and organization admins.
  IF auth.uid() IS NULL OR NOT public.can_delete_orders(order_oc) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;
  -- The queue send gate locks global capacity before an order. Deletion must
  -- acquire that outer lock before the form/order helper to avoid inversion.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  -- Form serialization fences offer issuance, acceptance, expiry and recovery.
  -- Lock every directly related order in ID order before changing any links.
  PERFORM 1 FROM public.forms WHERE id=form_id FOR UPDATE;
  SELECT array_agg(DISTINCT id ORDER BY id) INTO related_orders FROM (
    SELECT o.id FROM eshop.orders o WHERE o.id=delete_order_internal_v1.order_id OR o.source_waitlist_order_id=delete_order_internal_v1.order_id
      OR o.id=(SELECT source_waitlist_order_id FROM eshop.orders WHERE id=delete_order_internal_v1.order_id)
    UNION SELECT a.source_order_id FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id
    UNION SELECT a.target_order_id FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id
  ) related;
  IF EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(related_orders)
      AND (o.occasion<>order_oc OR o.form IS DISTINCT FROM form_id)) THEN
    RAISE EXCEPTION 'ORDER_WAITLIST_SCOPE_MISMATCH'; END IF;
  PERFORM public.check_batch_order_delete_internal(order_id);
  PERFORM public.lock_order_capacity_scope_internal(related_orders);
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=delete_order_internal_v1.order_id AND state='preparing_payment')
    OR EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts a
      WHERE (a.target_order_id=delete_order_internal_v1.order_id OR a.source_order_id=delete_order_internal_v1.order_id) AND a.state='preparing') THEN
    RAISE EXCEPTION 'WAITLIST_ACCEPTANCE_IN_PROGRESS'; END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(SELECT form FROM eshop.orders WHERE id=delete_order_internal_v1.order_id);
  -- Match occasion configuration/deletion: forms precede the occasion row.
  -- The group/activity advisory lock does not fence an occasion's unit move.
  PERFORM 1 FROM public.occasions WHERE id=order_oc FOR SHARE;
  PERFORM public.lock_activity_aggregate_internal_v1(order_oc);
  IF auth.uid() IS NULL OR NOT public.can_delete_orders(order_oc) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;

  -- After authorization, match the worker lock order (capacity, order,
  -- attempts, message). Recheck the order after locking against concurrent edits.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  SELECT o.payment_info INTO payment_info_id
    FROM eshop.orders o
   WHERE o.id = delete_order_internal_v1.order_id AND o.occasion = order_oc
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found or occasion changed.';
  END IF;

  PERFORM public.check_order_refund_delete_internal(order_id);

  -- Delete attention while message identities still exist. Cascading recipients
  -- and deliveries make every overview, count and badge agree immediately.
  PERFORM public.notification_center_prepared_delete_events(ARRAY(SELECT * FROM public.notification_center_prepared_order_events(delete_order_internal_v1.order_id)));
  DELETE FROM public.notification_center_events WHERE id=ANY(ARRAY(SELECT * FROM public.notification_center_prepared_order_events(delete_order_internal_v1.order_id)));
  DELETE FROM public.notification_center_source_state s
  USING public.email_messages m
  WHERE m.order_id=delete_order_internal_v1.order_id
    AND s.organization=m.organization AND s.source_key='email:'||m.message_id;

  -- Remove every queued/reminder/provider record for this order. log_emails
  -- and address suppressions are independent audit/safety records and remain.
  DELETE FROM public.email_delivery_events e
   WHERE e.message_id IN (SELECT m.message_id FROM public.email_messages m
                           WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.attempt_id IN (SELECT a.attempt_id FROM public.email_attempts a
                          JOIN public.email_messages m USING (message_id)
                         WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.provider_message_id IN (
           SELECT m.provider_message_id FROM public.email_messages m
            WHERE m.order_id = delete_order_internal_v1.order_id
           UNION
           SELECT a.provider_message_id FROM public.email_attempts a
           JOIN public.email_messages m USING (message_id)
            WHERE m.order_id = delete_order_internal_v1.order_id);

  DELETE FROM public.email_confirmation_receipts r
   WHERE r.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_attempts a
   WHERE a.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_messages m
   WHERE m.order_id = delete_order_internal_v1.order_id;

  -- Collect all order_product_ticket IDs for the order.
  SELECT ARRAY(SELECT id FROM eshop.order_product_ticket WHERE "order" = delete_order_internal_v1.order_id)
    INTO order_product_ticket_ids;

  -- Collect all ticket IDs from the order_product_ticket rows.
  SELECT ARRAY(SELECT ticket
                 FROM eshop.order_product_ticket
                WHERE "order" = delete_order_internal_v1.order_id
                  AND ticket IS NOT NULL)
    INTO ticket_ids;

  IF EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=ANY(ticket_ids) AND x."order"<>delete_order_internal_v1.order_id) THEN
    RAISE EXCEPTION 'TICKET_LINKED_TO_ANOTHER_ORDER'; END IF;

  -- Remove only this order's capability/offer evidence. Accepted children are
  -- independent orders: detach their source FK, never their tickets or finance.
  SELECT coalesce(array_agg(w.id),'{}') INTO offer_ids FROM eshop.waitlist_offers w WHERE w.order_id=delete_order_internal_v1.order_id;
  PERFORM 1 FROM eshop.waitlist_acceptance_attempts a
    WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id ORDER BY a.command_id FOR UPDATE;
  PERFORM 1 FROM eshop.waitlist_offers w WHERE w.id=ANY(offer_ids) ORDER BY w.id FOR UPDATE;
  PERFORM 1 FROM eshop.waitlist_offer_slots x
    WHERE x.offer_id=ANY(offer_ids) OR x.ticket_id=ANY(ticket_ids) OR x.resulting_order_id=delete_order_internal_v1.order_id ORDER BY x.id FOR UPDATE;
  DELETE FROM eshop.waitlist_capabilities c WHERE c.order_id=delete_order_internal_v1.order_id OR c.offer_id=ANY(offer_ids);
  DELETE FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id;
  UPDATE eshop.waitlist_offer_slots x SET resulting_order_id=NULL,updated_at=clock_timestamp() WHERE x.resulting_order_id=delete_order_internal_v1.order_id;
  DELETE FROM eshop.waitlist_offer_slots x WHERE x.offer_id=ANY(offer_ids) OR x.ticket_id=ANY(ticket_ids);
  DELETE FROM eshop.waitlist_offers w WHERE w.id=ANY(offer_ids);
  UPDATE eshop.orders o SET source_waitlist_order_id=NULL,updated_at=clock_timestamp() WHERE o.source_waitlist_order_id=delete_order_internal_v1.order_id;

  -- Free any spots that reference these order_product_ticket rows:
  -- set order_product_ticket, secret, and secret_expiration_time to NULL.
  UPDATE eshop.spots
     SET order_product_ticket      = NULL,
         secret                  = NULL,
         secret_expiration_time  = NULL,
         updated_at              = NOW()
   WHERE order_product_ticket = ANY(order_product_ticket_ids);

  -- Delete the related order_product_ticket entries.
  DELETE FROM eshop.order_product_ticket WHERE "order" = delete_order_internal_v1.order_id;

  -- Ticket-bound membership teardown has one domain owner, independent of
  -- the retired public RPC. Authorization remains the order's manager boundary.
  IF EXISTS(SELECT 1 FROM public.occasion_users WHERE ticket=ANY(ticket_ids) AND occasion<>order_oc) THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket membership belongs to another occasion';
  END IF;
  FOR ou_record IN SELECT "user",occasion FROM public.occasion_users
    WHERE ticket=ANY(ticket_ids) AND occasion=order_oc ORDER BY "user"
  LOOP
    v_activity_impacts:=v_activity_impacts || public.remove_occasion_user_domain_internal_v1(order_oc,ou_record."user");
  END LOOP;
  -- The canonical order facade already invalidates profiles for remaining members.
  -- Teardown must also invalidate affected activity projections in sorted order.
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT DISTINCT x->>'component',order_oc,(x->>'userId')::uuid,1
  FROM jsonb_array_elements(v_activity_impacts) x
  JOIN public.occasion_users ou ON ou.occasion=order_oc AND ou."user"=(x->>'userId')::uuid
  WHERE x->>'component'='private_activity' ORDER BY 1,3
  ON CONFLICT(component,occasion,user_id) DO UPDATE
    SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();

  -- Delete the related tickets.
  -- This is now safe, as any occasion_users foreign key constraints
  -- should be resolved by the loop above.
  DELETE FROM eshop.tickets WHERE id = ANY(ticket_ids);

  -- Delete order history rows.
  DELETE FROM eshop.orders_history WHERE "order" = delete_order_internal_v1.order_id;

  -- Order-specific bank requests must not keep the order alive through their FK.
  DELETE FROM eshop.bank_account_requests WHERE "order" = delete_order_internal_v1.order_id;

  -- If a payment_info row exists, first free it from the order reference, then delete it.
  IF payment_info_id IS NOT NULL THEN
    UPDATE eshop.orders
       SET payment_info = NULL
     WHERE id = delete_order_internal_v1.order_id;

    -- Retain imported/manual bank transactions while removing their payment link.
    UPDATE eshop.transactions
       SET payment_info = NULL
     WHERE payment_info = payment_info_id;

    DELETE FROM eshop.payment_info WHERE id = payment_info_id;
  END IF;

  -- Finally, delete the order record.
  DELETE FROM eshop.orders WHERE id = delete_order_internal_v1.order_id;

END;
$$;

REVOKE ALL ON FUNCTION public.delete_order_internal_v1(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_221(order_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.delete_order_client_sync_v1(
    order_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_221(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_221(bigint) TO authenticated;

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
    SELECT pi.deposit_amount, coalesce(pi.paid,0)-coalesce(pi.returned,0), pi.amount
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

-- SOURCE: eshop_waitlist/order_overview.sql
-- Private pure projection. No matcher, paid transition or payment side effect.
CREATE OR REPLACE FUNCTION public.customer_order_payment_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH facts AS (
 SELECT o.*,p.payment_method,p.amount,coalesce(p.paid,0) received,coalesce(p.returned,0) returned,
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
 SELECT CASE WHEN public.payment_method_is_online_internal(payment_method) THEN public.provider_order_payment_projection_internal(p_order)||jsonb_build_object('net',net,'pending',pending,'totalOutstanding',outstanding,'overpaid',greatest(net-amount,0)) ELSE jsonb_build_object('method',payment_method,'deadlinePolicy',payment_policy->>'mode','instructions',jsonb_build_object('cashInstructions',payment_policy->>'cashInstructions'),'currency',trim(currency_code),'paid',received,'remaining',outstanding,'status',status,'amount',amount,'received',received,'returned',returned,'net',net,'pending',pending,
 'totalOutstanding',outstanding,'overpaid',greatest(net-amount,0),'depositAmount',deposit_amount,
 'depositDeadline',deposit_deadline,'finalDeadline',deadline,
 'dueNow',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN due_now ELSE 0 END,
 'dueAt',due_at,'overdue',coalesce(due_at<statement_timestamp() AND due_now>0,false),
 'instructionsAvailable',status IN ('unpaid','partially_paid','deposit_paid') AND (payment_method='cash' OR account_number IS NOT NULL)
  AND (payment_method='cash' OR CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END),
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
  'kind',CASE WHEN m.voided THEN 'payment_adjustment_voided' WHEN m.is_refund THEN 'refund' WHEN t.amount>0 THEN 'payment_received' ELSE 'payment_adjustment' END)
  ORDER BY t.created_at NULLS LAST,t.id),'[]') FROM eshop.transactions t JOIN LATERAL public.payment_transaction_movements_internal(due.payment_info) m ON m.transaction_id=t.id WHERE t.payment_info=due.payment_info),
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
    SELECT t.* FROM payments p CROSS JOIN LATERAL public.payment_transaction_movements_internal(p.id) t
    WHERE t.currency=p.currency_code AND NOT t.voided
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
     SELECT occurred_at::date AS day,currency::text AS currency,
      coalesce(sum(amount) FILTER (WHERE NOT is_refund),0) AS received,
      coalesce(-sum(amount) FILTER (WHERE is_refund),0) AS returned
      FROM transactions_scope GROUP BY 1,2
     UNION ALL
     SELECT (occurred_at AT TIME ZONE 'Europe/Prague')::date,currency,
      (coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0)/100)::numeric(30,2),
      (coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0)/100)::numeric(30,2) FROM stripe_movements GROUP BY 1,2
    ) facts GROUP BY day,currency
  ), manual AS (
    SELECT t.payment_info, sum(t.amount) FILTER (WHERE t.transaction_type = 'manual') AS received
    FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info
    JOIN LATERAL public.payment_transaction_movements_internal(p.id) m ON m.transaction_id=t.id
    WHERE NOT m.voided AND NOT m.is_refund GROUP BY t.payment_info
  ), order_money AS (
    SELECT currency_code AS currency, sum(coalesce(price,0)) AS value
    FROM orders_scope GROUP BY currency_code
  ), payment_money AS (
    SELECT p.currency_code AS currency, sum(coalesce(ft.gross_received,0)) AS received,
      sum(coalesce(ft.refunded,0)) AS returned, sum(coalesce(m.received,0)) AS manual,
      sum(coalesce(sm.received,0)) AS stripe_received,sum(coalesce(sm.returned,0)) AS stripe_refunded,
      sum(coalesce(ft.disputed,0)) AS disputed,sum(coalesce(p.paid_externally,0)) AS external_unattributed,
      bool_or(p.deposit_amount IS NOT NULL) AS deposits,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN least(coalesce(ft.gross_received,0),p.deposit_amount) ELSE 0 END) AS deposit,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN greatest(coalesce(ft.gross_received,0)-p.deposit_amount,0) ELSE 0 END) AS beyond,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN least(coalesce(ft.net_received,0),p.deposit_amount) ELSE 0 END) AS deposit_net,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN greatest(coalesce(ft.net_received,0)-p.deposit_amount,0) ELSE 0 END) AS beyond_net
    FROM payments p LEFT JOIN manual m ON m.payment_info=p.id LEFT JOIN stripe_money sm ON sm.payment_info_id=p.id
     LEFT JOIN financial_totals ft ON ft.id=p.id GROUP BY p.currency_code
  ), money AS (
    SELECT coalesce(o.currency,p.currency)::text AS currency, coalesce(o.value,0) AS value,
      coalesce(p.received,0) AS received, coalesce(p.returned,0) AS returned,
      coalesce(p.manual,0) AS manual, coalesce(p.deposits,false) AS deposits,
      coalesce(p.stripe_received,0) AS stripe_received,coalesce(p.stripe_refunded,0) AS stripe_refunded,
      coalesce(p.disputed,0) AS disputed,coalesce(p.external_unattributed,0) AS external_unattributed,
      coalesce(p.deposit,0) AS deposit, coalesce(p.beyond,0) AS beyond,
      coalesce(p.deposit_net,0) AS deposit_net,coalesce(p.beyond_net,0) AS beyond_net
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
      'has_deposits',deposits,'deposit_received_gross',deposit::text,'beyond_deposit_received_gross',beyond::text,
      'deposit_received_net',deposit_net::text,'beyond_deposit_received_net',beyond_net::text
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
      result := result || 'Přijaté zálohy (čisté): ' || coalesce(item->>'deposit_received_net',item->>'deposit_received_gross') || E'\n'
        || 'Přijato nad zálohu (čisté): ' || coalesce(item->>'beyond_deposit_received_net',item->>'beyond_deposit_received_gross') || E'\n';
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
  result := result || E'\nSouhrn stavů odpovídá aktuálnímu stavu, nikoli historickým přechodům. Denní platby obsahují pouze zaevidované transakce. Stav paid může znamenat jen uhrazenou zálohu.\nMísta nezahrnují dočasné blokace. Ruční příjmy nejsou nutně hotovost; ostatní nejsou nutně banka.\nZálohy jsou čisté potvrzené platby po vratkách, pouze u plateb se zálohou.\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'warnings') LOOP
    result := result || 'Upozornění: ' || (item->>'code') || ' (' || (item->>'count') || E')\n';
  END LOOP;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.format_occasion_report_text(jsonb) FROM PUBLIC, anon, authenticated, service_role;

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
        WHEN COALESCE(pi.paid, 0)-COALESCE(pi.returned,0) >= new_order_price AND new_order_price > 0 THEN 'paid'
        WHEN new_order_price <= 0 THEN 'paid'
        ELSE 'ordered'
    END INTO new_state
    FROM eshop.payment_info pi WHERE pi.id=ord.payment_info;

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
        IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=ord.payment_info AND public.payment_method_is_online_internal(payment_method)) THEN
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
 IF p_message.message_kind='custom' AND p_message.code='MEASUREMENT_APPROVAL_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM analytics.unit_measurement_request q JOIN public.units u ON u.id=q.unit
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE q.unit=p_message.unit AND u.organization=p_message.organization AND NOT public.is_demo_unit(u.id)
    AND public.unit_measurement_approval_internal(u.id)->'approved'='false'::jsonb
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

-- SOURCE: account_deletion/account_deletion_contract.sql
CREATE OR REPLACE FUNCTION public.create_account_deletion_request(
  p_user uuid,
  p_organization bigint,
  p_token_hash text,
  p_expires_at timestamptz,
  p_masked_email text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_previous public.account_deletion_requests%ROWTYPE;
  v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  IF p_token_hash !~ '^[0-9a-f]{64}$' OR p_expires_at <= clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_invalid_request' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_info ui
    WHERE ui.id = p_user AND ui.organization = p_organization
  ) THEN
    RAISE EXCEPTION 'account_deletion_account_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_previous
  FROM public.account_deletion_requests
  WHERE user_id = p_user
    AND status IN ('email_pending','email_sent','deletion_pending')
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

  IF v_previous.status = 'deletion_pending' THEN
    RAISE EXCEPTION 'account_deletion_already_pending' USING ERRCODE = '55000';
  END IF;
  IF v_previous.id IS NOT NULL AND v_previous.cooldown_until > clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_cooldown' USING ERRCODE = 'P0001';
  END IF;
  IF v_previous.id IS NOT NULL THEN
    UPDATE public.account_deletion_requests
    SET status = 'revoked', token_hash = NULL, masked_email = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_previous.id;
  END IF;

  INSERT INTO public.account_deletion_requests(
    user_id, organization, token_hash, masked_email, expires_at, cooldown_until
  ) VALUES (
    p_user, p_organization, p_token_hash, p_masked_email, p_expires_at,
    clock_timestamp() + interval '5 minutes'
  ) RETURNING * INTO v_request;

  RETURN jsonb_build_object('requestId', v_request.id, 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_account_deletion_email_state(
  p_request_id uuid,
  p_delivered boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_deletion_requests
  SET status = CASE WHEN p_delivered THEN 'email_sent' ELSE 'revoked' END,
      email_sent_at = CASE WHEN p_delivered THEN clock_timestamp() ELSE NULL END,
      token_hash = CASE WHEN p_delivered THEN token_hash ELSE NULL END,
      masked_email = CASE WHEN p_delivered THEN masked_email ELSE NULL END,
      error_class = CASE WHEN p_delivered THEN NULL ELSE 'email_delivery' END,
      updated_at = clock_timestamp()
  WHERE id = p_request_id AND status = 'email_pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.inspect_account_deletion_token(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  IF p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;
  RETURN jsonb_build_object('status', 'valid', 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_account_deletion(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_request public.account_deletion_requests%ROWTYPE;
  v_completion_email text;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1 FOR UPDATE;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status IN ('deletion_pending','failed') AND v_request.used_token_hash = p_token_hash THEN
    RETURN jsonb_build_object('status','processing','requestId',v_request.id,
      'userId',v_request.user_id,'organization',v_request.organization,
      'publicDeleted',v_request.public_deleted,'authDeleted',v_request.auth_deleted,
      'onesignalDeleted',v_request.onesignal_deleted);
  END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;

  v_completion_email := public.get_user_delivery_email(v_request.user_id);

  UPDATE public.account_deletion_requests SET
    status='deletion_pending', used_token_hash=token_hash, token_hash=NULL,
    masked_email=NULL, claimed_at=clock_timestamp(), attempt_count=attempt_count+1,
    updated_at=clock_timestamp()
  WHERE id=v_request.id RETURNING * INTO v_request;
  -- The claim and first-party cleanup share one transaction. Consequently an
  -- already-issued JWT cannot regain domain access between confirmation and a
  -- later Edge call; its public.user_info row is gone before claim commits.
  PERFORM public.cleanup_account_deletion_domain(v_request.id);
  RETURN jsonb_build_object('status','processing','requestId',v_request.id,
    'userId',v_request.user_id,'organization',v_request.organization,
    'completionEmail',v_completion_email,
    'publicDeleted',true,'authDeleted',false,'onesignalDeleted',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_account_deletion_domain(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user uuid; v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE id=p_request_id FOR UPDATE;
  IF v_request.id IS NULL OR v_request.status NOT IN ('deletion_pending','failed') THEN
    RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000';
  END IF;
  IF v_request.public_deleted THEN RETURN jsonb_build_object('status','already_deleted'); END IF;
  v_user := v_request.user_id;

  PERFORM public.record_account_deletion_sync_v1(
    v_user,v_request.organization);

  UPDATE public.cleaning_reports SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.cleaning_reports SET resolved_by=NULL WHERE resolved_by=v_user;
  UPDATE public.news SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.orders_history SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.bank_account_requests SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.transactions SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.refund_requests SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.client_commits SET actor_id=NULL, actor_display=NULL WHERE actor_id=v_user;
  DELETE FROM public.event_feedback WHERE "user"=v_user;

  DELETE FROM public.client_mutation_receipts WHERE actor_id=v_user;
  DELETE FROM public.client_sync_private_scopes WHERE user_id=v_user;
  DELETE FROM public.activity_assignments WHERE "user"=v_user;
  DELETE FROM public.activity_history WHERE user_id=v_user;
  DELETE FROM public.event_users_saved WHERE "user"=v_user;
  DELETE FROM public.event_users WHERE "user"=v_user;
  DELETE FROM public.user_groups WHERE "user"=v_user;
  DELETE FROM public.user_companions WHERE "user"=v_user OR companion=v_user;
  DELETE FROM public.user_reset_token WHERE "user"=v_user;
  DELETE FROM eshop.bank_account_users WHERE "user"=v_user;
  PERFORM public.notification_center_prepared_invalidate_user(v_user);
  DELETE FROM public.occasion_users WHERE "user"=v_user;
  DELETE FROM public.unit_users WHERE "user"=v_user;
  DELETE FROM public.organization_users WHERE "user"=v_user;
  PERFORM public.invalidate_external_login_for_user_v1(v_user);
  DELETE FROM public.user_info WHERE id=v_user;

  UPDATE public.account_deletion_requests SET public_deleted=true,
    status='deletion_pending', error_class=NULL, updated_at=clock_timestamp()
  WHERE id=p_request_id;
  RETURN jsonb_build_object('status','deleted');
END;
$$;

CREATE OR REPLACE FUNCTION public.update_account_deletion_job(
  p_request_id uuid,
  p_auth_deleted boolean DEFAULT NULL,
  p_onesignal_deleted boolean DEFAULT NULL,
  p_error_class text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE; v_assets_done boolean;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  v_assets_done := COALESCE(v_request.assets_prepared AND
    (SELECT active FROM public.canonical_asset_cutover WHERE singleton) AND
    NOT EXISTS(SELECT 1 FROM public.account_deletion_assets WHERE request_id=p_request_id AND deleted_at IS NULL) AND
    NOT EXISTS(SELECT 1 FROM public.canonical_assets WHERE owner_id=v_request.user_id::text AND deleted_at IS NULL),false);
  UPDATE public.account_deletion_requests SET
    auth_deleted=coalesce(p_auth_deleted,auth_deleted),
    onesignal_deleted=coalesce(p_onesignal_deleted,onesignal_deleted),
    error_class=p_error_class,
    status=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN 'completed'
      WHEN p_error_class IS NOT NULL THEN 'failed' ELSE 'deletion_pending' END,
    completed_at=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN clock_timestamp()
      ELSE completed_at END,
    user_id=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN NULL ELSE user_id END,
    updated_at=clock_timestamp()
  WHERE id=p_request_id AND status IN ('deletion_pending','failed')
  RETURNING * INTO v_request;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
  RETURN jsonb_build_object('status',v_request.status);
END;
$$;

REVOKE ALL ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_account_deletion(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_account_deletion_domain(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_account_deletion(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_account_deletion_domain(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) TO service_role;
REVOKE ALL ON FUNCTION public.inspect_account_deletion_token(text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.inspect_account_deletion_token(text) TO anon, service_role;

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

-- SOURCE: eshop_orders/delete_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.delete_order_client_sync_v1(
  p_order bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_removed_users uuid[]; v_remaining_users uuid[];
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  SELECT o.occasion,oc.unit INTO v_occasion,v_unit FROM eshop.orders o
    JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
  -- Successful deletion removes the order. Exact retries retain their verified
  -- scope in the existing receipt, and still require current scoped rights.
  IF v_occasion IS NULL THEN
    SELECT r.occasion,oc.unit INTO v_occasion,v_unit FROM public.client_mutation_receipts r
    JOIN public.occasions oc ON oc.id=r.occasion
    WHERE r.command_id=p_command_id AND r.command_name='inventory.order.delete'
      AND r.actor_id=v_actor AND r.request_sha256=v_hash AND r.status IN ('completed','expired');
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.can_delete_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required'; END IF;
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.admit_order_mutation_v1(v_occasion,(SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=p_order));
  -- Match the email worker's outer send fence before form/order locks.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  PERFORM 1 FROM public.forms WHERE id=(SELECT form FROM eshop.orders WHERE id=p_order) FOR UPDATE;
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
  IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=p_order
    AND (command_id IS DISTINCT FROM p_command_id OR created_by IS DISTINCT FROM v_actor)) THEN
    RAISE EXCEPTION 'ORDER_DELETION_IN_PROGRESS';
  END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_removed_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt."order"=p_order;
  PERFORM public.delete_order_internal_v1(p_order);
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=v_occasion
    AND s.user_id=ANY(v_removed_users);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed_users) id));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_remaining_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  IF cardinality(v_removed_users)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=v_occasion;
  END IF;
  RETURN public.complete_private_profile_mutation_v1(p_command_id,v_occasion,
    'inventory.order.delete',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order,'operation','delete',
      'safeLabel','Order','changedFields',jsonb_build_array(
        'tickets','membership','allocations'))),v_remaining_users,v_public,v_dirty,
    jsonb_build_object('orderId',p_order,'removedUsers',cardinality(v_removed_users)));
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  TO authenticated;
