-- Cash reservations; no activation, external calls or historical policy backfill.
ALTER TABLE eshop.payment_providers DROP CONSTRAINT payment_providers_check;
ALTER TABLE eshop.payment_providers ADD CONSTRAINT payment_providers_check CHECK(
 (provider_key IN ('bank','cash') AND handler IS NULL AND source_field IS NULL)
 OR (provider_key NOT IN ('bank','cash') AND handler IS NOT NULL AND source_field IS NOT NULL));
INSERT INTO eshop.payment_providers(provider_key) VALUES('cash');
-- Unlinking preserves account facts. No account deletion may cascade away ledger rows.
ALTER TABLE eshop.transactions DROP CONSTRAINT transactions_bank_account_fkey;
ALTER TABLE eshop.transactions ADD CONSTRAINT transactions_bank_account_fkey
 FOREIGN KEY(bank_account_id) REFERENCES eshop.bank_accounts(id) ON DELETE RESTRICT;

-- SOURCE: user_permissions/bank_operations.sql
-- Account management requires both account administration and management of a
-- linked unit. Unit administration never grants bank administration implicitly.
CREATE OR REPLACE FUNCTION public.bank_account_write_rule(p_admin boolean,p_unit_manager boolean,p_demo boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT public.active_membership(p_admin AND p_unit_manager,p_demo);
$$;
REVOKE ALL ON FUNCTION public.bank_account_write_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.bank_account_write_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.get_is_admin_on_bank_account(p_bank_account bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.bank_account_users m
 WHERE m.bank_account=p_bank_account AND m."user"=auth.uid() AND m.is_admin);
$$;
REVOKE ALL ON FUNCTION public.get_is_admin_on_bank_account(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_is_admin_on_bank_account(bigint) TO authenticated,service_role;

-- Personal bank-statement read authority is independent of a live unit link.
-- Order read access alone never grants this operation.
CREATE OR REPLACE FUNCTION public.can_read_bank_transactions(p_bank_account bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_admin_on_bank_account(p_bank_account);
$$;
REVOKE ALL ON FUNCTION public.can_read_bank_transactions(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_bank_transactions(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_manage_bank_account(p_bank_account bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.bank_account_write_rule(public.get_is_admin_on_bank_account(p_bank_account),
 EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.unit_users membership
   ON membership.unit=link.unit AND membership."user"=auth.uid() AND membership.is_manager
   WHERE link.bank_account=p_bank_account AND NOT EXISTS(
     SELECT 1 FROM public.demo_unit_ids_internal() demo WHERE demo.unit_id=membership.unit)),
 public.is_demo_bank_account(p_bank_account));
$$;
REVOKE ALL ON FUNCTION public.can_manage_bank_account(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_bank_account(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_link_bank_account_to_unit(p_bank_account bigint,p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.bank_account_write_rule(public.get_is_admin_on_bank_account(p_bank_account),
   public.get_is_manager_on_unit(p_unit),public.is_demo_bank_account(p_bank_account));
$$;
REVOKE ALL ON FUNCTION public.can_link_bank_account_to_unit(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_link_bank_account_to_unit(bigint,bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_account_users_read_rule(p_admin boolean,p_support boolean,p_unit_manager boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_admin,false) OR coalesce(p_support,false) OR coalesce(p_unit_manager,false);
$$;
REVOKE ALL ON FUNCTION public.bank_account_users_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.bank_account_users_read_rule(boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.can_read_bank_account_users(p_bank_account bigint,p_unit bigint DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (p_unit IS NULL OR EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link
   WHERE link.bank_account=p_bank_account AND link.unit=p_unit))
 AND public.bank_account_users_read_rule(
  EXISTS(SELECT 1 FROM eshop.bank_account_users m WHERE m.bank_account=p_bank_account AND m."user"=auth.uid() AND m.is_admin),
  EXISTS(SELECT 1 FROM eshop.bank_account_users m WHERE m.bank_account=p_bank_account AND m."user"=auth.uid() AND m.is_support),
  p_unit IS NOT NULL AND public.get_is_manager_on_unit(p_unit));
$$;
REVOKE ALL ON FUNCTION public.can_read_bank_account_users(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_bank_account_users(bigint,bigint) TO authenticated,service_role;

-- The demo migration recreated the details writer after the old grants. Keep
-- the supported application entry points explicit, with live policy inside.
REVOKE ALL ON FUNCTION public.update_bank_account(bigint,text,text,text,text[],text,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_bank_account(bigint,text,text,text,text[],text,bigint,text) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.update_bank_account_user(bigint,text,boolean,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_bank_account_user(bigint,text,boolean,boolean) TO authenticated,service_role;

-- Existing fetch-transactions compatibility endpoint: resolve the actual
-- occasion, require its unit manager, then return only bank-authorized data.
-- Each affected account uses the same live two-role owner as BankSync manage.
CREATE OR REPLACE FUNCTION public.get_bank_sync_connections_for_occasion(p_link text)
RETURNS TABLE(connection_id bigint,remote_bank_account_id text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target_unit bigint; target_occasion bigint;
BEGIN
 SELECT o.id,o.unit INTO target_occasion,target_unit FROM public.occasions o WHERE o.link=p_link FOR SHARE;
 IF auth.uid() IS NULL OR target_occasion IS NULL OR public.is_demo_occasion(target_occasion)
   OR NOT public.can_manage_unit_bank_accounts(target_unit) THEN
   RAISE insufficient_privilege USING MESSAGE='bank account and unit administration required';
 END IF;
 RETURN QUERY SELECT DISTINCT c.id,c.remote_bank_account_id
 FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts link
   ON link.bank_account=c.bank_account_id OR link.bank_account IN
     (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id)
 JOIN eshop.bank_account_users membership ON membership.bank_account=link.bank_account
   AND membership."user"=auth.uid()
 LEFT JOIN (SELECT DISTINCT d.bank_account FROM public.demo_occasions d) protected
   ON protected.bank_account=link.bank_account
 WHERE link.unit=target_unit AND c.state IN ('connected','degraded') AND c.mode='api'
   AND c.legacy_blocked_at IS NOT NULL
   -- The single unit admission above established the live manager fact for
   -- this actual link. Keep account facts set based, without per-row RPCs.
   AND public.bank_account_write_rule(membership.is_admin,true,protected.bank_account IS NOT NULL);
END $$;
REVOKE ALL ON FUNCTION public.get_bank_sync_connections_for_occasion(text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_connections_for_occasion(text) TO authenticated;

-- SOURCE: payment_providers/payment_policy.sql
-- Configuration is resolved once, under the checkout form lock. Only metadata
-- belongs in payment_policy; amount, method, deadline and bank identity stay in columns.
-- Both stored forms and authorized draft previews pass their data to this owner.
CREATE OR REPLACE FUNCTION public.resolve_payment_policy_internal(p_metadata jsonb,p_duration bigint,p_feature jsonb,p_method text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE mode text; seconds bigint;
BEGIN
 mode:=coalesce(p_metadata#>>'{payment_deadline,mode}',CASE WHEN p_duration IS NULL THEN 'inherit' ELSE 'custom' END);
 IF mode NOT IN ('inherit','custom','none') THEN RAISE EXCEPTION 'PAYMENT_DEADLINE_INVALID'; END IF;
 IF p_method='cash' THEN RETURN jsonb_build_object('mode','none','cashInstructions',coalesce(p_metadata#>>'{payments,cashInstructions}','')); END IF;
 IF public.payment_method_is_online_internal(p_method) THEN RETURN '{"mode":"provider"}'::jsonb; END IF;
 IF mode='inherit' THEN mode:=coalesce(p_feature#>>'{payment_deadline,mode}','custom'); END IF;
 IF mode='none' THEN RETURN '{"mode":"none"}'::jsonb; END IF;
 seconds:=coalesce(p_duration,(p_feature->>'deadline_duration_seconds')::bigint,604800);
 IF seconds<0 OR (p_metadata#>>'{payment_deadline,mode}'='custom' AND p_duration IS NULL) THEN
  RAISE EXCEPTION 'PAYMENT_DEADLINE_INVALID'; END IF;
 RETURN jsonb_build_object('mode','custom','durationSeconds',seconds);
END $$;
REVOKE ALL ON FUNCTION public.resolve_payment_policy_internal(jsonb,bigint,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.resolve_form_payment_policy_internal(p_form bigint,p_method text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; feature jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 SELECT elem INTO feature FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) elem
 WHERE o.id=f.occasion AND elem->>'code'='form';
 RETURN public.resolve_payment_policy_internal(f.data,f.deadline_duration_seconds,feature,p_method);
END $$;

-- The sole bounded legacy interpretation. New snapshots retain absolute dates.
CREATE OR REPLACE FUNCTION public.refresh_order_payment_deadline_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; feature jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF public.payment_method_is_online_internal(pi.payment_method) THEN RETURN; END IF;
 IF pi.data ? 'payment_policy' THEN
  IF pi.data#>>'{payment_policy,mode}'='none' THEN
   UPDATE eshop.payment_info SET deadline=NULL,deposit_deadline=NULL WHERE id=pi.id;
  END IF;
  RETURN;
 END IF;
 SELECT elem INTO feature FROM public.occasions oc CROSS JOIN LATERAL jsonb_array_elements(oc.features) elem
 WHERE oc.id=o.occasion AND elem->>'code'='form';
 -- Historical orders alone retain the former product-editor calculation.
 UPDATE eshop.payment_info SET deadline=CASE WHEN o.price>0 THEN now()+make_interval(secs=>coalesce((feature->>'deadline_duration_seconds')::bigint,604800)) END
 WHERE id=pi.id;
 PERFORM public.queue_payment_reminders_internal(o.occasion,pi.id);
END $$;

CREATE OR REPLACE FUNCTION public.check_payment_client_capabilities_internal(p_policy jsonb,p_method text,p_capabilities jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF (p_method='cash' AND NOT coalesce(p_capabilities ? 'cash_reservations',false))
  OR (p_policy->>'mode'='none' AND NOT coalesce(p_capabilities ? 'no_payment_deadline',false)) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','PAYMENT_CLIENT_UPDATE_REQUIRED',
   'message','Open the current website to use these payment instructions.')::text;
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.guard_form_payment_write_internal(p_saved jsonb,p_candidate jsonb,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb:=p_candidate; incoming jsonb; merged jsonb;
 explicit_selection boolean:=p_input->>'payment_selection_intent'='replace'; conflict boolean:=false;
BEGIN
 IF p_input ? 'payment_selection_intent' AND p_input->>'payment_selection_intent' IS DISTINCT FROM 'replace' THEN
  RAISE EXCEPTION 'PAYMENT_SELECTION_INTENT_INVALID'; END IF;
 incoming:=coalesce(p_input#>'{settings,payments}',p_input#>'{data,payments}');
 IF NOT coalesce(explicit_selection,false) THEN
  IF p_saved#>'{payments,cashEnabled}'='true'::jsonb AND incoming IS NOT NULL THEN
   BEGIN
    merged:=public.merge_form_payments_internal(p_saved->'payments',incoming);
    conflict:=merged IS DISTINCT FROM public.merge_form_payments_internal(p_saved->'payments',NULL);
   EXCEPTION WHEN raise_exception THEN conflict:=true; END;
  END IF;
  IF incoming IS NULL AND p_saved ? 'payments' THEN result:=result||jsonb_build_object('payments',p_saved->'payments'); END IF;
  IF NOT (coalesce(p_input->'settings',p_input->'data','{}'::jsonb) ? 'payment_deadline') AND p_saved ? 'payment_deadline' THEN
   result:=result||jsonb_build_object('payment_deadline',p_saved->'payment_deadline'); END IF;
  IF conflict
   OR (p_saved#>>'{payment_deadline,mode}'='none' AND result#>>'{payment_deadline,mode}' IS DISTINCT FROM 'none')
   OR (result#>'{payments,cashEnabled}'='true'::jsonb AND p_saved#>'{payments,cashEnabled}' IS DISTINCT FROM 'true'::jsonb)
   OR (result#>>'{payment_deadline,mode}'='none' AND p_saved#>>'{payment_deadline,mode}' IS DISTINCT FROM 'none') THEN
   RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','PAYMENT_CLIENT_UPDATE_REQUIRED',
    'message','Update the editor before changing payment selection.')::text;
  END IF;
 END IF;
 IF result#>'{payments,cashEnabled}'='true'::jsonb THEN
  result:=result||'{"payment_deadline":{"mode":"none"}}'::jsonb;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.resolve_form_payment_policy_internal(bigint,text),public.refresh_order_payment_deadline_internal(bigint),
 public.check_payment_client_capabilities_internal(jsonb,text,jsonb),public.guard_form_payment_write_internal(jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
  IF jsonb_typeof(r.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=r.key AND handler IS NOT NULL) THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
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
    IF EXISTS(SELECT 1 FROM jsonb_each(v) x WHERE jsonb_typeof(x.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=x.key AND handler IS NOT NULL)) THEN
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
    analytics_write_requested boolean;
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
        -- Preserve explicit reset intent before legacy presale ingress turns a
        -- settings patch into a full metadata candidate with removed keys.
        analytics_write_requested:=CASE WHEN input_data ? 'settings' THEN
          coalesce((input_data->'settings') ? 'analytics',false) ELSE
          public.normalize_form_metadata_internal(input_data->'data') ? 'analytics' END;
        PERFORM public.guard_form_payment_write_internal(form_metadata,form_metadata,input_data);
        input_data:=public.guard_form_presale_write_internal(form_metadata,input_data);
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
          IF NOT analytics_write_requested AND NOT form_metadata ? 'analytics'
            AND public.normalize_form_metadata_internal(previous_form_metadata) ? 'analytics' THEN
            form_metadata:=form_metadata||jsonb_build_object('analytics',public.normalize_form_metadata_internal(previous_form_metadata)->'analytics');
          END IF;
          IF jsonb_typeof(form_metadata->'analytics')='object' THEN
            form_metadata:=jsonb_set(form_metadata,'{analytics}',
              coalesce(nullif(public.normalize_form_metadata_internal(previous_form_metadata)->'analytics','null'::jsonb),'{}'::jsonb) || (form_metadata->'analytics'));
          END IF;
          -- Full metadata from released clients owns only its bank/Stripe part.
          form_metadata:=jsonb_set(form_metadata,'{payments}',public.merge_form_payments_internal(
            previous_form_metadata->'payments',public.normalize_form_metadata_internal(input_data->'data')->'payments'));
          form_metadata:=public.apply_form_settings_internal(form_metadata,
            public.form_settings_from_metadata_internal(form_metadata));
        END IF;

        form_metadata:=public.guard_form_payment_write_internal(previous_form_metadata,form_metadata,input_data);
        IF form_metadata#>>'{payment_deadline,mode}' IN ('inherit','none') AND
          (coalesce(input_data->'settings',input_data->'data','{}'::jsonb) ? 'payment_deadline'
            OR form_metadata#>'{payments,cashEnabled}'='true'::jsonb) THEN
          input_data:=input_data||'{"deadline_duration_seconds":null}'::jsonb;
        END IF;

        -- Form writers can change only the boolean intent, never Unit destination code.
        -- Bind permission to the stored form/occasion after normalization.
        IF form_metadata->'analytics' IS DISTINCT FROM public.normalize_form_metadata_internal(previous_form_metadata)->'analytics'
          AND NOT public.can_manage_form_measurement(occasion_id) THEN
          RAISE insufficient_privilege USING MESSAGE='form author required to change measurement intent'; END IF;

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

-- SOURCE: eshop_forms/get_form_by_link.sql
CREATE OR REPLACE FUNCTION public.get_form_bundle_internal(p_form_id bigint,p_allow_closed boolean DEFAULT false)
RETURNS JSON LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
    allData JSON;
    generated_secret UUID := gen_random_uuid();
    form_exists BOOLEAN;
    is_editor_view BOOLEAN := false;
    occ_id BIGINT;
BEGIN
    -- Check if the form exists
    SELECT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id
    ) INTO form_exists;

    IF NOT form_exists THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Form does not exist.'
        );
    END IF;

    SELECT occasion INTO occ_id FROM public.forms WHERE id = p_form_id;
    IF public.is_demo_occasion(occ_id) AND NOT public.can_read_demo_occasion(occ_id) THEN
        RETURN jsonb_build_object('code',404,'message','Form does not exist.');
    END IF;
    is_editor_view := public.can_read_orders(occ_id);


    IF NOT p_allow_closed AND NOT is_editor_view AND NOT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id AND is_open = true
    ) THEN
        -- If the form is closed, retrieve only the 'header_off' message
        SELECT jsonb_build_object(
            'code', 400,
            'data', jsonb_build_object(
                'organizationIdentity', (SELECT CASE WHEN o.organization=u.organization THEN public.get_verified_unit_identity_internal(u.id) END FROM public.occasions o JOIN public.units u ON u.id=o.unit WHERE o.id=f.occasion),
                'header_off', f.header_off,
                'seo', public.get_occasion_seo_data(f.link, 'form'),
                'is_open', f.is_open
            )
        )
        INTO allData
        FROM public.forms f
        WHERE f.id = p_form_id;

        RETURN allData;
    END IF;

    -- If the form is open, retrieve the full form data including dynamic product availability
    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'demo_simulation', public.is_demo_occasion(f.occasion),
            'organizationIdentity', CASE WHEN o.organization=(SELECT organization FROM public.units WHERE id=o.unit) THEN public.get_verified_unit_identity_internal(o.unit) END,
            'payments',public.form_payment_availability_internal(f.id),
            'capacity', public.get_form_capacity_snapshot_internal(f.id),
            'registrationMode',public.get_form_registration_mode_internal(f.id),
            'saleOpeningNotification',public.get_sale_opening_projection_internal(f.id),
            'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'id', f.id,
            'link', f.link,
            'key', f.key,
            'created_at', f.created_at,
            'data', public.get_effective_form_data(f.id),
            'type', f.type,
            'title', f.title,
            'seo', public.get_occasion_seo_data(f.link, 'form'),
            'is_open', f.is_open,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', jsonb_build_object(
                'id', o.id,
                'title', o.title,
                'features', o.features,
                'start_time', o.start_time
            ),
            'blueprint', CASE WHEN jsonb_path_exists(o.features,
                '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN f.blueprint END,
            'deadline_duration_seconds', f.deadline_duration_seconds,
            'account_number', ba.account_number,
            'secret', generated_secret,
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'data', p.data,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum,
                                                    'is_dynamically_available', is_product_dynamically_available(p.id)
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                              AND NOT p.is_hidden
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                -- For the structural ticket field, is_hidden disables ticket
                -- issuance, not the application and its nested price choices.
                WHERE ff.form = f.id AND (ff.is_hidden = false OR ff.type = 'ticket')
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    LEFT JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    RETURN allData;
END;
$$;

REVOKE ALL ON FUNCTION public.get_form_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_form_by_link(input_data jsonb)
RETURNS json LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f bigint; policy jsonb; method text;
BEGIN
 f:=public.resolve_form_link_internal(input_data->>'form_link');
 IF f IS NOT NULL THEN
  SELECT CASE WHEN data#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' ELSE 'bank' END INTO method FROM public.forms WHERE id=f;
  policy:=public.resolve_form_payment_policy_internal(f,method);
  PERFORM public.check_payment_client_capabilities_internal(policy,method,input_data->'client_capabilities');
 END IF;
 RETURN public.get_form_bundle_internal(f,false);
EXCEPTION WHEN raise_exception THEN
 IF left(SQLERRM,1)='{' THEN RETURN SQLERRM::json; END IF; RAISE;
END $$;
CREATE OR REPLACE FUNCTION public.get_form_by_link(form_link text)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_form_by_link(jsonb_build_object('form_link',form_link));
$$;
REVOKE ALL ON FUNCTION public.get_form_by_link(jsonb),public.get_form_by_link(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_form_by_link(jsonb),public.get_form_by_link(text) TO anon,authenticated,service_role;

-- SOURCE: eshop_forms/admin_form_orders.sql
-- Administrative entrypoints delegate the same checkout and single receipt as
-- public/UI creation. No ticket/payment shadow writer or second intent exists.
CREATE OR REPLACE FUNCTION public.check_form_order_scope_internal(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_write boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,p_write);
 IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='foreign order form'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.form_order_input_internal(p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::text)>1048576
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_input) k WHERE k NOT IN ('email','fields','ticket','lang','form','payment_method','client_capabilities'))
  OR jsonb_typeof(p_input->'ticket') IS DISTINCT FROM 'array' OR jsonb_array_length(p_input->'ticket') NOT BETWEEN 1 AND 1000
  OR nullif(p_input->>'email','') IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid administrative order'; END IF;
 IF p_input ? 'form' AND p_input->>'form' IS DISTINCT FROM (SELECT key::text FROM public.forms WHERE id=p_form) THEN
  RAISE insufficient_privilege USING MESSAGE='foreign order form key'; END IF;
 IF p_input ? 'payment_method' AND public.payment_method_is_online_internal(p_input->>'payment_method') THEN
  RAISE invalid_parameter_value USING MESSAGE='administrative card payment unsupported'; END IF;
 RETURN p_input||jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=p_form),'client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb);
END $$;
CREATE OR REPLACE FUNCTION public.form_order_quote_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('newOrder',jsonb_build_object('amount',o.price::text,'currencyCode',o.currency_code,
  'state',o.state,'paymentMethod',p.payment_method,'paymentPolicy',p.data->'payment_policy','bankAccountId',p.bank_account,
  'bankAccountNumber',ba.account_number,'bankAccountDisplay',ba.account_number_human_readable,
  'ticketCount',(SELECT count(DISTINCT ticket) FROM eshop.order_product_ticket WHERE "order"=o.id)))
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info LEFT JOIN eshop.bank_accounts ba ON ba.id=p.bank_account WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.form_order_facts_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('form',(SELECT to_jsonb(f)-ARRAY['key','link','created_at'] FROM public.forms f WHERE id=p_form),
  'fields',snap->'fields','products',snap->'products','productTypes',snap->'productTypes')
 FROM (SELECT public.get_form_authoring_snapshot_internal(p_form) snap) s;
$$;
CREATE OR REPLACE FUNCTION public.preview_form_order_internal(p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE result jsonb; quote jsonb; facts jsonb; snap jsonb;
BEGIN
 facts:=public.form_order_facts_internal(p_form);
 BEGIN
  result:=public.create_ticket_order_command_internal(public.form_order_input_internal(p_form,p_input),extensions.gen_random_uuid(),extensions.gen_random_uuid(),NULL);
  IF (result->>'code')::int=200 THEN quote:=public.form_order_quote_internal((result#>>'{data,order,id}')::bigint); END IF;
  RAISE SQLSTATE 'P0F90' USING MESSAGE='rollback administrative order quote';
 EXCEPTION WHEN SQLSTATE 'P0F90' THEN NULL; END;
 IF (result->>'code')::int<>200 THEN RETURN jsonb_build_object('code',422,'reason','ORDER_NOT_CREATABLE'); END IF;
 RETURN jsonb_build_object('code',200,'quote',quote,'confirmationHash',encode(extensions.digest(
  jsonb_build_object('actor',auth.uid(),'form',p_form,'input',p_input,'facts',facts,'quote',quote)::text,'sha256'),'hex'));
END $$;
CREATE OR REPLACE FUNCTION public.lock_form_order_internal(p_occasion bigint,p_form bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 -- Same parent order as actual checkout and the administration seat flow.
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 PERFORM 1 FROM eshop.product_types WHERE id IN(SELECT product_type FROM public.form_fields WHERE form=p_form) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.products WHERE product_type IN(SELECT product_type FROM public.form_fields WHERE form=p_form) ORDER BY id FOR UPDATE;
END $$;
CREATE OR REPLACE FUNCTION public.preview_admin_form_order(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 PERFORM public.lock_form_order_internal(p_occasion,p_form);
 RETURN public.preview_form_order_internal(p_form,p_input)||jsonb_build_object('occasionId',p_occasion,'formId',p_form,'actorId',auth.uid());
END $$;
CREATE OR REPLACE FUNCTION public.create_admin_form_order(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_input jsonb,
 p_confirmation_hash text,p_expected_actor uuid,p_command_id uuid,p_client_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE prior jsonb; receipt_status text; preview jsonb; quote jsonb; result jsonb; context jsonb;
BEGIN
 IF p_expected_actor IS DISTINCT FROM auth.uid() OR auth.uid() IS NULL OR p_confirmation_hash IS NULL OR p_confirmation_hash !~ '^[a-f0-9]{64}$' THEN
  RAISE insufficient_privilege USING MESSAGE='confirmed order actor required'; END IF;
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 PERFORM public.lock_form_order_internal(p_occasion,p_form);
 SELECT response,status INTO prior,receipt_status FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid()
  AND occasion=p_occasion AND command_name='inventory.order.create';
 IF receipt_status='expired' THEN RETURN jsonb_build_object('code',410,'errorCode','COMMAND_EXPIRED_DO_NOT_REPLAY'); END IF;
 IF prior IS NOT NULL THEN quote:=prior#>'{data,adminQuote}';
 ELSE
  preview:=public.preview_form_order_internal(p_form,p_input);
  IF preview->>'confirmationHash' IS DISTINCT FROM p_confirmation_hash THEN
   RETURN jsonb_build_object('code',409,'errorCode','ORDER_CHANGED_REPREVIEW_REQUIRED'); END IF;
  quote:=preview->'quote';
 END IF;
 context:=jsonb_build_object('occasion',p_occasion,'organization',p_organization,'unit',p_unit,'form',p_form,
  'actor',auth.uid(),'confirmationHash',p_confirmation_hash,'quote',quote);
 result:=public.create_ticket_order_command_internal(public.form_order_input_internal(p_form,p_input),p_command_id,p_client_id,context);
 IF prior IS NULL AND (result->>'code')::int=200 AND
   public.form_order_quote_internal((result#>>'{data,order,id}')::bigint) IS DISTINCT FROM quote THEN
  RAISE serialization_failure USING MESSAGE='order quote changed during creation'; END IF;
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 RETURN result||jsonb_build_object('data',(result->'data')||jsonb_build_object('quote',result#>'{data,adminQuote}',
  'adminScope',jsonb_build_object('occasionId',p_occasion,'formId',p_form,'actorId',auth.uid())));
END $$;
REVOKE ALL ON FUNCTION public.check_form_order_scope_internal(bigint,bigint,bigint,bigint,boolean),
 public.form_order_input_internal(bigint,jsonb),public.form_order_quote_internal(bigint),public.preview_form_order_internal(bigint,jsonb),
 public.form_order_facts_internal(bigint),public.lock_form_order_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.preview_admin_form_order(bigint,bigint,bigint,bigint,jsonb),
 public.create_admin_form_order(bigint,bigint,bigint,bigint,jsonb,text,uuid,uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_admin_form_order(bigint,bigint,bigint,bigint,jsonb),
 public.create_admin_form_order(bigint,bigint,bigint,bigint,jsonb,text,uuid,uuid,uuid) TO authenticated;

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

-- SOURCE: eshop_transactions/insert_manual_transaction_internal_v1.sql
-- One owner for exact cash movements, account serialization and existing pairing.
CREATE OR REPLACE FUNCTION public.insert_manual_transaction_internal_v1(
 p_amount numeric,p_currency text,p_unit_id bigint,p_variable_symbol text,p_date timestamptz,
 p_note text DEFAULT NULL,p_payment_info_id bigint DEFAULT NULL)
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
    IF p_payment_info_id IS NOT NULL THEN
      SELECT * INTO STRICT v_order FROM eshop.orders WHERE payment_info=p_payment_info_id;
      PERFORM public.lock_order_capacity_scope_internal(ARRAY[v_order.id]);
      SELECT unit INTO v_unit FROM public.occasions WHERE id=v_order.occasion;
      IF v_unit IS DISTINCT FROM p_unit_id OR trim(v_order.currency_code) IS DISTINCT FROM p_currency THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
      PERFORM public.check_order_is_mutable(v_order.id);
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
        'manual',
        auth.uid(),
        'manual'
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    IF p_payment_info_id IS NOT NULL THEN
         v_payment_info_id := p_payment_info_id;
    ELSIF p_variable_symbol IS NOT NULL AND p_variable_symbol ~ '^[0-9]{1,10}$' THEN
        SELECT array_agg(pi.id ORDER BY pi.id) INTO v_candidate_ids
        FROM eshop.payment_info pi
        JOIN eshop.orders o ON o.payment_info = pi.id
        JOIN public.occasions oc ON oc.id = o.occasion
        WHERE pi.variable_symbol = p_variable_symbol::bigint
          AND upper(trim(pi.currency_code::text)) = upper(trim(p_currency))
          AND oc.unit = p_unit_id;
        IF cardinality(v_candidate_ids) = 1 THEN
          v_payment_info_id := v_candidate_ids[1];
        END IF;
    END IF;

    IF v_payment_info_id IS NOT NULL THEN
        PERFORM public.apply_transaction_pairing(
          v_new_transaction_id, v_payment_info_id, 'manual_insert', 'user'
        );
    END IF;
    RETURN v_new_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.insert_manual_transaction_internal_v1(numeric,text,bigint,text,timestamptz,text,bigint)
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
    IF v_payment.id IS NULL OR public.payment_method_is_online_internal(v_payment.payment_method)
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
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_payment_info_id AND public.payment_method_is_online_internal(payment_method)) THEN
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

  PERFORM public.refresh_order_payment_deadline_internal(v_order_id);

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
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('method',p.payment_method,'amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'policy',p.data->'payment_policy','variableSymbol',p.variable_symbol::text,'deadline',p.deadline) END)
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
   PERFORM public.insert_manual_transaction_internal_v1((p_changes->>'amount')::numeric,p_changes->>'currency',v_unit,v_pi.variable_symbol::text,
     (p_changes->>'receivedAt')::timestamptz,p_changes->>'note',v_pi.id);
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

REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[],boolean) FROM PUBLIC, anon, authenticated;

-- SOURCE: eshop_orders/order_actions.sql
-- Shared action projection for administration and delegated order tools.
CREATE OR REPLACE FUNCTION public.get_order_allowed_actions_internal_v1(p_order bigint,p_summary jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT (CASE WHEN o.state='stock' THEN jsonb_build_array('view')
 WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id WHERE i.sale_order_id=o.id AND t.state<>'storno') THEN jsonb_build_array('view','note','cancel','send')
 ELSE (coalesce(p_summary,(CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
    THEN public.get_waitlist_summary_internal(o.id) ELSE public.get_order_action_summary_internal(o.state) END))->'allowedActions') END)
    - CASE WHEN public.payment_method_is_online_internal(p.payment_method) THEN ARRAY['cancel','paid']::text[] ELSE ARRAY[]::text[] END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

REVOKE ALL ON FUNCTION public.get_order_allowed_actions_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
      WHERE pi.id=v_order.payment_info AND public.payment_method_is_online_internal(pi.payment_method)) THEN
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
        ELSIF public.payment_method_is_online_internal(v_payment_method) THEN
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
          INSERT INTO eshop.payment_info(amount,deposit_amount,currency_code,created_at,payment_method)
          VALUES(calculated_price,NULLIF(v_total_deposit,0),first_currency_code,now,v_payment_method)
          RETURNING id INTO payment_info_id;


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

-- SOURCE: emails/set_payment_deadline.sql
CREATE OR REPLACE FUNCTION public.set_payment_deadline(p_payment_info_id bigint,p_new_deadline timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE o record;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
 PERFORM public.check_payment_info_is_mutable(p_payment_info_id);
 IF p_new_deadline IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=p_payment_info_id AND payment_method='cash') THEN RAISE EXCEPTION 'CASH_DEADLINE_FORBIDDEN'; END IF;
 UPDATE eshop.payment_info SET deadline=p_new_deadline,
 deposit_deadline=CASE WHEN p_new_deadline IS NULL THEN NULL ELSE deposit_deadline END,
 data=coalesce(data,'{}')||jsonb_build_object('current_version_reminded',false,'payment_policy',coalesce(data->'payment_policy','{}')||jsonb_build_object('mode',CASE WHEN p_new_deadline IS NULL THEN 'none' ELSE 'custom' END)),
 email_reminder_version=email_reminder_version+1 WHERE id=p_payment_info_id;
 FOR o IN SELECT DISTINCT occ.id FROM eshop.orders ord JOIN public.occasions occ ON occ.id=ord.occasion WHERE ord.payment_info=p_payment_info_id LOOP
  PERFORM public.queue_payment_reminders_internal(o.id,p_payment_info_id);
 END LOOP;
END $$;

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
    AND coalesce(pi.paid,0) < pi.amount

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

-- SOURCE: eshop_waitlist/order_overview.sql
-- Private pure projection. No matcher, paid transition or payment side effect.
CREATE OR REPLACE FUNCTION public.customer_order_payment_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH facts AS (
 SELECT o.*,p.payment_method,p.amount,coalesce(p.paid,0) received,coalesce(p.returned,0) returned,
 p.data->'payment_policy' payment_policy,p.deposit_amount,p.deposit_deadline,p.deadline,p.variable_symbol,p.creditor_reference,
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
 SELECT CASE WHEN public.payment_method_is_online_internal(payment_method) THEN public.provider_order_payment_projection_internal(p_order) ELSE jsonb_build_object('method',payment_method,'deadlinePolicy',payment_policy->>'mode','instructions',jsonb_build_object('cashInstructions',payment_policy->>'cashInstructions'),'currency',trim(currency_code),'paid',received,'remaining',outstanding,'status',status,'amount',amount,'received',received,'returned',returned,
 'totalOutstanding',outstanding,'overpaid',greatest(received-amount,0),'depositAmount',deposit_amount,
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
  IF payment.payment_method='cash' THEN RETURN p_response; END IF;
  IF payment.id IS NOT NULL THEN
   details:=coalesce(payload#>'{order,payment_info}','{}')||jsonb_build_object('id',payment.id,'variable_symbol',payment.variable_symbol,
    'creditor_reference',payment.creditor_reference,'amount',payment.amount,'deposit_amount',payment.deposit_amount,
    'deadline',payment.deadline,'deposit_deadline',payment.deposit_deadline,'currency_code',payment.currency_code);
   payload:=jsonb_set(payload,'{order,payment_info}',details);
   IF public.payment_method_is_online_internal(payment.payment_method) THEN
    payload:=payload||jsonb_build_object('payment',public.provider_order_payment_projection_internal(target.id));
   END IF;
  END IF;
 END IF;
 IF p_response ? 'data' THEN RETURN jsonb_set(p_response,'{data}',payload); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.project_local_payment_reference_order_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

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

-- SOURCE: eshop_bank_accounts/get_my_admin_bank_accounts.sql
DROP FUNCTION IF EXISTS public.get_my_admin_bank_accounts();

CREATE FUNCTION public.get_my_admin_bank_accounts()
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
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.account_number_human_readable,
        ba.title,
        ba.creditor_name,
        ba.type,
        NULL::text as token_masked,
        CASE WHEN public.can_manage_bank_account(ba.id) THEN
          (public.get_bank_sync_connection(ba.id)->>'token_expiry_at')::timestamptz END as token_expiry_date,
        ba.supported_currencies,
        ARRAY(
            SELECT u.title
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit = u.id
            WHERE uba.bank_account = ba.id
        ) as linked_units,
        ba.last_fetch_time,
        ba.last_fio_fetch_time,
        CASE WHEN public.can_manage_bank_account(ba.id) THEN
          public.get_bank_sync_connection(ba.id) END AS bank_sync
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    AND upper(ba.type) <> 'CASH'
    ORDER BY ba.title;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_admin_bank_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_admin_bank_accounts() TO authenticated, service_role;

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
      'actions', jsonb_build_object(
        'canAddCash', public.can_manage_unit_bank_accounts(oc.unit)
          AND o.state IN ('created','ordered','paid','sent') AND NOT public.payment_method_is_online_internal(pi.payment_method),
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
            to_jsonb(t) || jsonb_build_object('createdByName',
                trim(both from COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, ''))
            )
        )
        FROM eshop.transactions t
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
        AND t.payment_info IS NULL
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
    SELECT org.data->>'DEFAULT_FORM_PAYMENT_METHOD' INTO payment_default
    FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
    WHERE o.id=p_occasion_id;
    IF payment_default='cash' THEN
      initial_data := initial_data || '{"payments":{"bankEnabled":false,"cashEnabled":true,"providerConnections":{}},"payment_deadline":{"mode":"none"}}'::jsonb;
    ELSIF public.payment_method_is_online_internal(payment_default) THEN
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

-- SOURCE: eshop_transactions/insert_manual_transaction.sql
CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_variable_symbol text,
    p_date text,
    p_note text DEFAULT NULL,
    p_payment_info_id int DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.check_is_manager_on_unit(p_unit_id);
    PERFORM public.insert_manual_transaction_internal_v1(p_amount::numeric,p_currency,p_unit_id::bigint,
      p_variable_symbol,p_date::timestamptz,p_note,p_payment_info_id::bigint);
END;
$$;

REVOKE ALL ON FUNCTION public.insert_manual_transaction(double precision,text,integer,text,text,text,integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision,text,integer,text,text,text,integer)
  TO authenticated;

-- Exact receipted ingress. The released floating-point RPC remains a bounded
-- compatibility facade over the same cash movement owner.
CREATE OR REPLACE FUNCTION public.insert_manual_transaction(input_data jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; u bigint; begin_result jsonb; transaction_id bigint; users uuid[]; result jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE payment_info=(input_data->>'paymentInfoId')::bigint;
 SELECT unit INTO u FROM public.occasions WHERE id=o.occasion;
 PERFORM public.check_is_manager_on_unit(u);
 IF u IS DISTINCT FROM (input_data->>'unitId')::bigint OR trim(o.currency_code) IS DISTINCT FROM input_data->>'currency' THEN
  RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
 IF jsonb_typeof(input_data->'amount') IS DISTINCT FROM 'string' OR input_data->>'amount' !~ '^-?[0-9]{1,8}(\.[0-9]{1,2})?$' THEN
  RAISE EXCEPTION 'CASH_AMOUNT_INVALID'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[o.id]);
 begin_result:=public.begin_client_mutation_v1(p_command_id,'orders.cash.record',o.occasion,auth.uid(),
  encode(extensions.digest(input_data::text,'sha256'),'hex'));
 IF begin_result->>'disposition'='replay' THEN RETURN jsonb_set(begin_result->'response','{mutation,replayed}','true'); END IF;
 transaction_id:=public.insert_manual_transaction_internal_v1((input_data->>'amount')::numeric,input_data->>'currency',u,NULL,
  (input_data->>'receivedAt')::timestamptz,input_data->>'note',o.payment_info);
 SELECT coalesce(array_agg(DISTINCT "user"),'{}') INTO users FROM public.occasion_users WHERE occasion=o.occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,'orders.cash.record',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','changedFields',jsonb_build_array('payment'))),users,
  jsonb_build_object('orderId',o.id,'transactionId',transaction_id,'payment',public.customer_order_payment_internal(o.id)));
END $$;
REVOKE ALL ON FUNCTION public.insert_manual_transaction(jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(jsonb,uuid) TO authenticated;

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
 IF public.payment_method_is_online_internal(p_input_data->>'payment_method') OR EXISTS(
  SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
  JOIN eshop.orders o ON o.id=i."order" JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE s.id=ANY(p_spot_ids) AND public.payment_method_is_online_internal(p.payment_method)) THEN RAISE EXCEPTION 'STRIPE_REPLACEMENT_UNSUPPORTED'; END IF;
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
 IF public.payment_method_is_online_internal(created#>>'{order,payment_info,payment_method}') THEN
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
   'paymentPolicy',created#>'{order,payment_info,data,payment_policy}',
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

-- SOURCE: blueprint/order_quote.sql
-- Validate one final typed quote before retaining any confirmed write effects.
CREATE OR REPLACE FUNCTION public.blueprint_seat_order_quote_internal(p_effect jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE quote jsonb:=p_effect->'quote';money jsonb;products jsonb;
BEGIN
 IF coalesce(quote#>>'{newOrder,amount}','')!~'^-?[0-9]+(\.[0-9]+)?$'
  OR length(quote#>>'{newOrder,amount}')>40
  OR coalesce(btrim(quote#>>'{newOrder,currencyCode}'),'')!~'^[A-Za-z]{3}$'
  OR coalesce(length(quote#>>'{newOrder,state}'),0) NOT BETWEEN 1 AND 64
  OR NOT public.payment_method_registered_internal(quote#>>'{newOrder,paymentMethod}')
  OR public.payment_method_is_online_internal(quote#>>'{newOrder,paymentMethod}')
  OR (quote#>>'{newOrder,ticketCount}')::int IS DISTINCT FROM jsonb_array_length(quote->'spotIds')
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(quote#>'{newOrder,products}') p
    WHERE coalesce(p->>'amount','')!~'^-?[0-9]+(\.[0-9]+)?$' OR length(p->>'amount')>40
    OR coalesce(btrim(p->>'currencyCode'),'')!~'^[A-Za-z]{3}$')
  OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(quote->'spotIds') requested(id)
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(quote#>'{newOrder,products}') p WHERE p->>'spotId'=requested.id)) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_ORDER_MONEY_UNAVAILABLE'; END IF;
 money:=public.project_order_amount_changes_internal(quote->'orders');
 SELECT coalesce(jsonb_agg(p||jsonb_build_object('currencyCode',upper(btrim(p->>'currencyCode')))),'[]') INTO products
 FROM jsonb_array_elements(quote#>'{newOrder,products}') p;
 RETURN jsonb_set(jsonb_set(jsonb_set(quote,'{orders}',money),'{newOrder,currencyCode}',to_jsonb(upper(btrim(quote#>>'{newOrder,currencyCode}')))),
  '{newOrder,products}',products);
END $$;
REVOKE ALL ON FUNCTION public.blueprint_seat_order_quote_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
   'form_fields','deleted_field_ids','deleted_product_ids','settings']
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

-- SOURCE: occasion_setup/email_preview.sql
-- Draft-scoped read projection. No caller-provided hierarchy or template ID is accepted.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(
 p_id uuid,p_expected_revision bigint,p_message_type text,p_occasion bigint,p_delivery_mode text)
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
 tone:=coalesce(nullif(nullif(d.data->>'communicationTone',''),'inherit'),CASE WHEN unit_data->>'communication_tone'='informal' THEN 'informal' ELSE 'formal' END);
 IF tone NOT IN ('formal','informal') THEN RAISE invalid_parameter_value USING MESSAGE='Invalid tone'; END IF;
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
  'sampleProducts',coalesce((SELECT jsonb_agg(p) FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f CROSS JOIN LATERAL (SELECT p FROM jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p WHERE NOT coalesce((p->>'is_hidden')::boolean,false) LIMIT 1) products(p) WHERE NOT coalesce((f->>'is_hidden')::boolean,false)),'[]'::jsonb),
  'has_custom_template',coalesce((overrides ? selected_code) OR (resolved->'template'->>'occasion') IS NOT NULL
    OR (resolved->'template'->>'unit') IS NOT NULL OR (resolved->'template'->>'organization') IS NOT NULL,false));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text) TO authenticated;

-- Keep the supported confirmation/catalog preview contract unchanged.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(p_id uuid,p_expected_revision bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.get_occasion_setup_email_preview(p_id,p_expected_revision,'order_confirmation',NULL,NULL);
$$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint) TO authenticated;
