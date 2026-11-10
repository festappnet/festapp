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
