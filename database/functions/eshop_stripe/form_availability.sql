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

CREATE OR REPLACE FUNCTION public.validate_form_payment_configuration_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE config jsonb; c eshop.stripe_connections; org bigint; u bigint; reason text;
BEGIN
 SELECT f.data->'payments',o.organization,o.unit INTO config,org,u FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form;
 IF config IS NULL THEN RETURN; END IF;
 IF jsonb_typeof(config)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(config) k WHERE k NOT IN ('bankEnabled','stripeConnectionId'))
  OR (config ? 'bankEnabled' AND jsonb_typeof(config->'bankEnabled')<>'boolean') THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 IF nullif(config->>'stripeConnectionId','') IS NULL THEN
  IF config->'bankEnabled'='false'::jsonb AND EXISTS (
    SELECT 1 FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id
    JOIN eshop.products p ON p.product_type=ff.product_type
    WHERE f.id=p_form AND f.is_open AND NOT coalesce(ff.is_hidden,false)
      AND NOT coalesce(p.is_hidden,false) AND p.price>0
  ) THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INCOMPLETE'; END IF;
  RETURN;
 END IF;
 -- Serialize editor selection with a verified account replacement.
 PERFORM 1 FROM public.units WHERE id=u AND organization=org FOR UPDATE;
 SELECT * INTO c FROM eshop.stripe_connections WHERE id=(config->>'stripeConnectionId')::uuid;
 IF c.id IS NULL OR c.organization_id<>org OR c.unit_id<>u OR NOT c.model_verified OR c.state NOT IN ('connected','restricted') THEN
  RAISE EXCEPTION 'STRIPE_RECIPIENT_UNAVAILABLE'; END IF;
 reason:=public.stripe_form_compatibility_internal(p_form);
 IF reason IS NOT NULL THEN RAISE EXCEPTION 'STRIPE_CONFIGURATION_UNSUPPORTED: %',reason; END IF;
END $$;
REVOKE ALL ON FUNCTION public.validate_form_payment_configuration_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.form_payment_availability_internal(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE config jsonb; c eshop.stripe_connections; policy eshop.stripe_runtime_policy; org bigint; u bigint;
 bank boolean; card boolean; reason text; methods jsonb:='[]'::jsonb;
BEGIN
 SELECT f.data->'payments',o.organization,o.unit INTO config,org,u FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form;
 bank:=coalesce(config->'bankEnabled','true'::jsonb)='true'::jsonb;
 card:=nullif(config->>'stripeConnectionId','') IS NOT NULL;
 IF bank THEN methods:=methods||jsonb_build_array('bank'); END IF;
 IF card THEN
  SELECT * INTO c FROM eshop.stripe_connections WHERE id=(config->>'stripeConnectionId')::uuid AND organization_id=org AND unit_id=u;
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
REVOKE ALL ON FUNCTION public.form_payment_availability_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assert_stripe_form_payable_internal(p_form bigint,p_expected_connection uuid,p_surface text)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; org bigint; u bigint; selected uuid; availability jsonb;
BEGIN
 SELECT (f.data#>>'{payments,stripeConnectionId}')::uuid,o.organization,o.unit INTO selected,org,u
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form FOR UPDATE OF f;
 IF selected IS NULL OR selected IS DISTINCT FROM p_expected_connection THEN RAISE EXCEPTION 'STRIPE_RECIPIENT_CHANGED'; END IF;
 -- Same locks are taken by pause/replacement and the kill switch. Submit rechecks availability under them.
 PERFORM 1 FROM public.units WHERE id=u AND organization=org FOR UPDATE;
 PERFORM 1 FROM eshop.stripe_connections WHERE id=selected FOR UPDATE;
 PERFORM 1 FROM eshop.stripe_runtime_policy WHERE organization_id=org AND livemode=(SELECT livemode FROM eshop.stripe_connections WHERE id=selected) FOR UPDATE;
 availability:=public.form_payment_availability_internal(p_form);
 IF NOT (availability->'available' ? 'stripe') THEN RAISE EXCEPTION 'STRIPE_UNAVAILABLE: %',availability->>'stripeUnavailableReason'; END IF;
 IF p_surface IS NULL OR NOT (availability->'supportedSurfaces' ? p_surface) THEN RAISE EXCEPTION 'STRIPE_SURFACE_UNVERIFIED'; END IF;
 RETURN selected;
END $$;
REVOKE ALL ON FUNCTION public.assert_stripe_form_payable_internal(bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
