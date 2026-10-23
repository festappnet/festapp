-- Shared ticketing profiles. No production provisioning or Stripe activation.

-- SOURCE: eshop_stripe/feature_settings.sql (discovery function only)
CREATE OR REPLACE FUNCTION public.stripe_unit_feature_enabled_internal(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(f.enabled,org.data->>'DEFAULT_FORM_PAYMENT_METHOD'='stripe',false)
 FROM public.units u JOIN public.organizations org ON org.id=u.organization
 LEFT JOIN eshop.stripe_unit_features f ON f.unit_id=u.id WHERE u.id=p_unit
$$;
REVOKE ALL ON FUNCTION public.stripe_unit_feature_enabled_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: catalog/source_policy.sql
-- The existing service-role-only source map is the catalog allowlist. A new
-- organization has no maps and therefore no implicit external catalog.
CREATE OR REPLACE FUNCTION public.catalog_includes_occasion_internal(
  p_organization bigint, p_owner bigint, p_source text
) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
  SELECT p_owner = p_organization OR EXISTS (
    SELECT 1 FROM public.external_sync_maps m
    WHERE m.target_org_id = p_organization AND m.source_name = p_source
  );
$$;
REVOKE ALL ON FUNCTION public.catalog_includes_occasion_internal(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalog_includes_occasion_internal(bigint,bigint,text) TO postgres,supabase_admin;

-- SOURCE: others/get_available_occasions.sql
CREATE OR REPLACE FUNCTION public.get_available_occasions(
  p_organization_id bigint,
  p_unit_id bigint DEFAULT NULL
)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  result_data jsonb;
  occasions_data jsonb;
BEGIN
  -- 1. Validation
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
    RAISE EXCEPTION 'organization_not_found: Organization % does not exist.', p_organization_id USING ERRCODE = 'P0002';
  END IF;

  IF p_unit_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = p_unit_id AND organization = p_organization_id) THEN
      RAISE EXCEPTION 'unit_not_found: Unit % not found in Org %.', p_unit_id, p_organization_id USING ERRCODE = 'P0002';
    END IF;
  END IF;

  -- 2. Fetch Occasions with Source Integration
  -- We LEFT JOIN external_occasions_cache to get source metadata
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'title', o.title,
        'description', o.description,
        'link', o.link,
        'start_time', o.start_time,
        'end_time', o.end_time,
        'is_open', o.is_open,
        'is_hidden', o.is_hidden,
        'is_promoted', o.is_promoted, -- Added for frontend filtering
        'features', o.features,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'data', o.data,
        -- New Architectural Fields:
        'source_name', c.source_name,         -- "From Source X"
        'last_synced_at', c.last_synced_at,   -- "Synced 5m ago"
        'is_external', (c.source_name IS NOT NULL),
        -- Form Info (Preserved from original logic)
        'form', (
           SELECT jsonb_build_object(
              'id', f.id,
              'created_at', f.created_at,
              'data', f.data,
              'type', f.type,
              'is_open', f.is_open,
              'link', f.link,
              'header', f.header
           )
           FROM public.forms f
           WHERE f.occasion = o.id
           ORDER BY f.is_open DESC, f.id
           LIMIT 1
        )
      )
      ORDER BY o.start_time DESC
    ),
    '[]'::jsonb
  )
  INTO occasions_data
  FROM public.occasions o
  LEFT JOIN public.external_occasions_cache c ON o.link = c.link
  WHERE 
    -- Use the same explicit source-map policy as the other public projection.
    public.catalog_includes_occasion_internal(p_organization_id, o.organization, c.source_name)
    -- Unit Filter (Optional)
    AND (p_unit_id IS NULL OR o.unit = p_unit_id)
    -- Visibility Rules
    AND o.is_hidden = false
    -- Promotion Rule: STRICT - Must be promoted, even if external
    AND (p_unit_id IS NOT NULL OR o.is_promoted = true);

  -- 3. Construct Result Object
  IF p_unit_id IS NULL THEN
      result_data := jsonb_build_object(
        'title', 'All Occasions',
        'organization', p_organization_id,
        'occasions', occasions_data
      );
  ELSE
      SELECT jsonb_build_object(
        'id', u.id,
        'title', u.title,
        'organization', u.organization,
        'occasions', occasions_data
      )
      INTO result_data
      FROM public.units u
      WHERE u.id = p_unit_id;
  END IF;

  RETURN result_data;
END;
$$ LANGUAGE plpgsql;

-- SOURCE: others/get_public_occasions.sql
CREATE OR REPLACE FUNCTION public.get_public_occasions(
  p_organization_id bigint,
  p_unit_id bigint DEFAULT NULL
)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  result_data jsonb;
  occasions_data jsonb;
BEGIN
  -- 1. First, check if the provided organization exists.
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
    RAISE EXCEPTION 'organization_not_found: Organization with id % does not exist.', p_organization_id
      USING ERRCODE = 'P0002'; -- P0002 = no_data_found
  END IF;

  -- 2. Handle the case where unit_id IS NULL.
  -- Fetch all occasions for the given organization.
  IF p_unit_id IS NULL THEN

    -- Query all non-hidden, open, and promoted occasions for the specified organization
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', o.id,
          'title', o.title,
          'created_at', o.created_at,
          'updated_at', o.updated_at,
          'data', o.data,
          'description', o.description,
          'is_hidden', o.is_hidden,
          'is_open', o.is_open,
          'start_time', o.start_time,
          'end_time', o.end_time,
          'link', o.link,
          'organization', o.organization,
          'services', o.services,
          'unit', o.unit,
          'features', o.features,
          'form', (
             SELECT jsonb_build_object(
                'id', f.id,
                'created_at', f.created_at,
                'data', f.data,
                'occasion', f.occasion,
                'type', f.type,
                'is_open', f.is_open,
                'link', f.link,
                'blueprint', f.blueprint,
                'header', f.header,
                'header_off', f.header_off,
                'updated_at', f.updated_at
             )
             FROM public.forms f
             WHERE f.occasion = o.id
             -- Sort by is_open DESC (True first), then by ID
             ORDER BY f.is_open DESC, f.id
             LIMIT 1
          )
        )
        ORDER BY o.start_time DESC
      ),
      '[]'::jsonb
    )
    INTO occasions_data
    FROM public.occasions o
    LEFT JOIN public.external_occasions_cache c ON c.link = o.link
    WHERE public.catalog_includes_occasion_internal(p_organization_id, o.organization, c.source_name)
      AND o.is_hidden = false
      AND o.is_promoted = true;

    -- Build a "virtual" unit object to hold these occasions,
    -- matching the structure of the "ELSE" block.
    result_data := jsonb_build_object(
      'id', NULL,
      'created_at', NULL,
      'title', 'All Occasions', -- Placeholder title
      'organization', p_organization_id,
      'data', NULL,
      'features', NULL,
      'occasions', occasions_data
    );

  -- 3. Handle the case where unit_id IS NOT NULL.
  -- Fetch data for that specific unit.
  ELSE
    -- Check if the unit exists AND belongs to the specified organization
    IF NOT EXISTS (
      SELECT 1
      FROM public.units
      WHERE id = p_unit_id
        AND organization = p_organization_id
    ) THEN
      RAISE EXCEPTION 'unit_not_found: Unit with id % in organization % does not exist.', p_unit_id, p_organization_id
        USING ERRCODE = 'P0002'; -- P0002 = no_data_found
    END IF;

    -- If check passes, run the original query.
    SELECT jsonb_build_object(
      'id', u.id,
      'created_at', u.created_at,
      'title', u.title,
      'organization', u.organization,
      'data', u.data,
      'features', u.features,
      'occasions', (
         SELECT COALESCE(
           jsonb_agg(
             jsonb_build_object(
               'id', o.id,
               'title', o.title,
               'created_at', o.created_at,
               'updated_at', o.updated_at,
               'data', o.data,
               'description', o.description,
               'is_hidden', o.is_hidden,
               'is_open', o.is_open,
               'start_time', o.start_time,
               'end_time', o.end_time,
               'link', o.link,
               'organization', o.organization,
               'services', o.services,
               'unit', o.unit,
               'features', o.features,
               'form', (
                  SELECT jsonb_build_object(
                     'id', f.id,
                     'created_at', f.created_at,
                     'data', f.data,
                     'occasion', f.occasion,
                     'type', f.type,
                     'is_open', f.is_open,
                     'link', f.link,
                     'blueprint', f.blueprint,
                     'header', f.header,
                     'header_off', f.header_off,
                     'updated_at', f.updated_at
                  )
                  FROM public.forms f
                  WHERE f.occasion = o.id
                  -- Sort by is_open DESC (True first), then by ID
                  ORDER BY f.is_open DESC, f.id
                  LIMIT 1
               )
             )
             ORDER BY o.start_time DESC
           ),
           '[]'::jsonb
         )
         FROM public.occasions o
         WHERE o.unit = u.id
           AND o.is_hidden = false
      )
    )
    INTO result_data
    FROM public.units u
    WHERE u.id = p_unit_id;
  END IF;

  -- 4. Return the resulting JSON object directly.
  RETURN result_data;
END;
$$ LANGUAGE plpgsql;

-- SOURCE: others/get_occasion_seo_data.sql
-- Public metadata only. Route kind keeps form and occasion namespaces distinct.
-- Existing one-argument callers retain their form-first resolution contract.
CREATE OR REPLACE FUNCTION public.get_occasion_seo_data(p_link_slug text, p_route_type text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_occasion_id bigint; v_form public.forms%ROWTYPE; v_result json;
BEGIN
    IF p_route_type NOT IN ('form', 'event') OR p_route_type IS NULL THEN
        RAISE invalid_parameter_value USING MESSAGE = 'Invalid public SEO route';
    END IF;
    IF p_route_type = 'form' THEN
        SELECT * INTO v_form FROM public.forms
        WHERE id = public.resolve_form_link_internal(p_link_slug);
        v_occasion_id := v_form.occasion;
    ELSE
        v_occasion_id := public.resolve_occasion_link_internal(p_link_slug);
    END IF;
    SELECT json_build_object(
        'title', o.title, 'description', o.description,
        'form_title', v_form.title, 'form_description', v_form.header,
        'form_link', v_form.link, 'occasion_link', o.link,
        'start_time', o.start_time, 'end_time', o.end_time,
        'image', o.data->>'image', 'org_title', org.title, 'unit_title', u.title
    ) INTO v_result
    FROM public.occasions o
    JOIN public.organizations org ON org.id = o.organization
    LEFT JOIN public.units u ON u.id = o.unit
    WHERE o.id = v_occasion_id;
    RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_seo_data(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_occasion_seo_data(text,text) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_occasion_seo_data(p_link_slug text)
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path = public, extensions AS $$
    SELECT coalesce(public.get_occasion_seo_data(p_link_slug, 'form'), public.get_occasion_seo_data(p_link_slug, 'event'));
$$;
REVOKE ALL ON FUNCTION public.get_occasion_seo_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_occasion_seo_data(text) TO anon, authenticated, service_role;

-- Host-scoped public projection. Keeps the saved-slug resolver and metadata
-- owner above; a foreign object is never rebranded with this host's origin.
CREATE OR REPLACE FUNCTION public.get_occasion_seo_data(
  p_link_slug text, p_route_type text, p_organization_id bigint
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_id bigint; v_owner bigint; v_source text;
BEGIN
  IF p_route_type = 'form' THEN
    SELECT occasion INTO v_id FROM public.forms WHERE id=public.resolve_form_link_internal(p_link_slug);
  ELSIF p_route_type = 'event' THEN
    v_id:=public.resolve_occasion_link_internal(p_link_slug);
  ELSE
    RAISE invalid_parameter_value USING MESSAGE='Invalid public SEO route';
  END IF;
  SELECT o.organization,c.source_name INTO v_owner,v_source
  FROM public.occasions o LEFT JOIN public.external_occasions_cache c ON c.link=o.link WHERE o.id=v_id;
  IF p_organization_id IS NULL OR v_owner IS NULL OR
     NOT public.catalog_includes_occasion_internal(p_organization_id,v_owner,v_source) THEN RETURN NULL; END IF;
  RETURN public.get_occasion_seo_data(p_link_slug,p_route_type);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_seo_data(text,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_occasion_seo_data(text,text,bigint) TO anon,authenticated,service_role;

-- SOURCE: eshop_stripe/checkout_locale.sql
-- Forward-only snapshot extension; old attempts keep their original provider body.
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN IF NOT EXISTS checkout_locale text NOT NULL DEFAULT 'auto'
  CHECK (checkout_locale IN ('auto','cs','en','de','pl','sk'));

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
    IF payment_default = 'stripe' THEN
      -- A closed draft can await Connect without inventing a recipient or bank.
      initial_data := initial_data || '{"payments":{"bankEnabled":false}}'::jsonb;
    END IF;
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
          THEN data #- '{payments,stripeConnectionId}' ELSE data END,
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
        'paymentMethod',CASE WHEN (SELECT data->>'DEFAULT_FORM_PAYMENT_METHOD' FROM public.organizations WHERE id=d.organization)='stripe' THEN 'stripe' ELSE NULL END,
        'paymentChoicesEnabled',public.stripe_unit_feature_enabled_internal(d.unit))
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
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  policy:=public.abuse_effective_rules_v1('occasion.draft',d.unit,d.organization);
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,0,false,true,policy);
  configuration := public.build_occasion_setup_configuration(d.unit,p_id);
  UPDATE public.occasion_setup_drafts SET data =
    jsonb_build_object('defaultConfiguration',configuration,
      'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true,
        'paymentMethod',CASE WHEN (SELECT data->>'DEFAULT_FORM_PAYMENT_METHOD' FROM public.organizations WHERE id=d.organization)='stripe' THEN 'stripe' ELSE NULL END,
        'paymentChoicesEnabled',public.stripe_unit_feature_enabled_internal(d.unit))
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
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001'; END IF;
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
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
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
 intro_image text; form_link text; selected_bank bigint; bank_fingerprint text; bank_currencies text[]; required_currencies text[]; wave jsonb; target jsonb; saved_wave jsonb; wave_product bigint;
 has_tickets boolean;
 unit_defaults jsonb; communication_new boolean; reply_email text; form_meta jsonb; reminder_days numeric;
 payment_method text;
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
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
 payload := public.normalize_occasion_setup_appearance_internal(d.data);
 payment_method:=payload->>'paymentMethod';
 IF payment_method IS NOT NULL AND payment_method NOT IN ('stripe','bank','both') THEN
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
  IF sale_end IS NULL OR sale_end>(payload->>'end')::timestamptz THEN
   RAISE invalid_parameter_value USING MESSAGE='Sale must end no later than the event'; END IF;
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
 IF coalesce((payload->>'isPromoted')::boolean,false) AND intro_image IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Promotion requires an intro image'; END IF;
 -- Selection is sufficient; current permissions, currencies and account
 -- fingerprint are still verified under locks before materialization.
 SELECT array_agg(DISTINCT coalesce(nullif(p->>'currency_code',''),'CZK')) INTO required_currencies
 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p
 WHERE coalesce((payload->>'formEnabled')::boolean,true) AND NOT coalesce((f->>'is_hidden')::boolean,false)
   AND NOT coalesce((p->>'is_hidden')::boolean,false) AND (p->>'price')::numeric>0;
 IF required_currencies IS NOT NULL AND payment_method IS DISTINCT FROM 'stripe' AND (payload ? 'bankAccountId' OR payload ? 'bankAccountConfirmed' OR payment_method IN ('bank','both')) THEN
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
   RAISE serialization_failure USING MESSAGE='Bank account details changed; select again'; END IF;
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
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'is_promoted',coalesce((payload->>'isPromoted')::boolean,false),
  'features',features,'data',jsonb_strip_nulls(jsonb_build_object('client_sync_v1',false,
   'setup_listing_intent',coalesce((payload->>'listPubliclyOnPublish')::boolean,true),
   'image',intro_image,'place_name',nullif(btrim(payload->>'placeName'),''),'reply_to',reply_email)));
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
  IF coalesce(nullif(payload->>'formSourceOccasionId','')::bigint,source_id) IS NOT NULL
     AND EXISTS(SELECT 1 FROM public.occasions src WHERE src.id=coalesce(nullif(payload->>'formSourceOccasionId','')::bigint,source_id) AND src.unit IS DISTINCT FROM d.unit) THEN
   form_meta:=form_meta #- '{payments,stripeConnectionId}';
  END IF;
  IF payment_method IS NOT NULL THEN
   form_meta:=jsonb_set(form_meta,'{payments}',coalesce(form_meta->'payments','{}'::jsonb)
      ||jsonb_build_object('bankEnabled',payment_method<>'stripe'));
   IF payment_method='bank' THEN form_meta:=form_meta #- '{payments,stripeConnectionId}'; END IF;
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
   'formLink',(SELECT link FROM public.forms WHERE id=form_id),'saleMode',sale_mode));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;

-- SOURCE: eshop_orders/update_scan_code.sql
CREATE OR REPLACE FUNCTION update_scan_code(
    occasion_link TEXT,
    new_scan_code TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    occasions_hidden_id BIGINT;
BEGIN
    -- 1. Retrieve occasion_id using occasion_link
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- 2. Check if occasion_link is valid
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion link does not exist.'
        );
    END IF;

    -- 3. Verify if the user is an editor on the occasion
    IF NOT can_write_orders(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to edit this occasion.'
        );
    END IF;

    PERFORM 1 FROM public.scanner_settings WHERE scanner_settings.occasion_id=v_occasion_id FOR UPDATE;
    UPDATE public.scanner_settings SET epoch=epoch+1 WHERE scanner_settings.occasion_id=v_occasion_id;
    -- 4. Check if occasions_hidden exists for the occasion
    SELECT o.occasion_hidden
    INTO occasions_hidden_id
    FROM public.occasions o
    WHERE o.id = v_occasion_id;

    IF occasions_hidden_id IS NOT NULL THEN
        -- Update existing scan_code
        UPDATE public.occasions_hidden
        SET secret = new_scan_code
        WHERE id = occasions_hidden_id;
    ELSE
        -- Insert new occasions_hidden record
        INSERT INTO public.occasions_hidden (secret)
        VALUES (new_scan_code)
        RETURNING id INTO occasions_hidden_id;

        -- Update the occasion to link to the new occasions_hidden
        UPDATE public.occasions
        SET occasion_hidden = occasions_hidden_id
        WHERE id = v_occasion_id;
    END IF;

    -- 5. Return a success message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Scan code updated successfully.'
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Handle any unexpected exceptions
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;

REVOKE ALL ON FUNCTION public.update_scan_code(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_scan_code(text,text) TO authenticated,service_role;

-- SOURCE: eshop/seating_worker_access.sql
-- The durable email/PDF worker invokes these enrichers as service_role.
-- Keep client access revoked; no geometry writes are granted.
GRANT SELECT ON eshop.blueprint_seat_bindings, eshop.blueprint_area_bindings TO service_role;

-- SOURCE: eshop/get_ticket_details_for_generating.sql
CREATE OR REPLACE FUNCTION public.get_ticket_details_for_generating(ticket_id_input BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        -- 1. Build the 'ticket' key
        'ticket', (
            SELECT to_jsonb(t_detail)
            FROM (
                SELECT
                    t.id,
                    t.ticket_symbol,
                    t.occasion,
                    t.note,
                    t.state,
                    b.title AS table_title,
                    -- Subquery for Spot/Product details
                    (
                        SELECT jsonb_agg(ticket_prod ORDER BY ticket_prod.id)
                        FROM (
                            SELECT
                                opt2.id,
                                opt2.product,
                                s.title AS spot_title,
                                p.data->>'short_title' AS short_title,
                                p.title AS product_title,
                                (
                                    SELECT g.value->>'title'
                                    FROM jsonb_array_elements(bp.groups) AS g(value)
                                    WHERE (g.value->>'id')::bigint = (
                                        SELECT (o2.value->>'group')::bigint
                                        FROM jsonb_array_elements(bp.objects) AS o2(value)
                                        WHERE (o2.value->>'id')::bigint = s.id
                                          AND o2.value->>'type' = 'spot'
                                        LIMIT 1
                                    )
                                    LIMIT 1
                                ) AS spot_group_title
                            FROM eshop.order_product_ticket opt2
                            LEFT JOIN eshop.spots s
                                ON s.order_product_ticket = opt2.id
                            LEFT JOIN eshop.products p
                                ON p.id = opt2.product
                            LEFT JOIN eshop.product_types pt
                                ON pt.id = p.product_type
                            LEFT JOIN eshop.blueprints bp
                                ON bp.id = s.blueprint
                            WHERE opt2.ticket = t.id
                              AND NOT (pt.type = 'spot' AND s.title IS NULL)
                        ) ticket_prod
                    ) AS order_product_ticket,

                    -- Subquery for Price (extracting from ord.data)
                    (
                      SELECT COALESCE(SUM((prod->>'price')::numeric), 0)
                      FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                           jsonb_array_elements(ticket_json->'products') prod
                      WHERE (ticket_json->>'id')::bigint = t.id
                    ) AS price,

                    -- Subquery for Currency (extracting from ord.data)
                    (
                      SELECT (prod->>'currency_code')
                      FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                           jsonb_array_elements(ticket_json->'products') prod
                      WHERE (ticket_json->>'id')::bigint = t.id
                      LIMIT 1
                    ) AS currency_code
            ) t_detail
        ),

        -- 2. Build the 'occasion' key (dumps the whole occasion row including 'features')
        'occasion', to_jsonb(o)||jsonb_build_object('demo_read_only',public.is_demo_occasion(o.id),'locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=o.organization),'cs')),
        'order_data', jsonb_build_object('name', ord.data->'name', 'surname', ord.data->'surname')
    )
    INTO result
    FROM eshop.tickets t
    -- Join Occasion to get the occasion object
    JOIN public.occasions o
        ON o.id = t.occasion
    -- Join Blueprint for the table title
    LEFT JOIN eshop.blueprints b
        ON b.occasion = o.id
    -- Join Order Tables to expose 'ord.data' for the ticket sub-calculations above
    LEFT JOIN eshop.order_product_ticket opt
        ON opt.ticket = t.id
    LEFT JOIN eshop.orders ord
        ON ord.id = opt."order"
    WHERE t.id = ticket_id_input AND t.state IS DISTINCT FROM 'waitlisted' AND t.ticket_symbol IS NOT NULL
      AND ord.state IS DISTINCT FROM 'waitlisted';

    RETURN result;
END;
$$;

-- SOURCE: eshop/get_order_details_for_email.sql
CREATE OR REPLACE FUNCTION public.get_order_details_for_email(p_order_id bigint)
RETURNS jsonb
STABLE
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
        'payment_info', to_jsonb(pi.*),
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
            public.get_effective_form_data(f.id)     -- Form data with unit defaults
        INTO
            form_fields_data,
            form_data
        FROM
            public.form_fields AS ff
        JOIN
            public.forms AS f ON ff.form = f.id
        WHERE
            f.key = form_key
        GROUP BY
            f.id; -- Group by the form used for effective data

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
$$ LANGUAGE plpgsql;

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
 PERFORM public.check_occasion_writable(v_occ);
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF v_org IS NULL OR p_kind NOT IN ('order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 -- Snapshot the tenant default only for new unlocalized domain intents. Existing
 -- messages, explicit locales and prepared/encrypted Auth content are untouched.
 IF NOT coalesce(p_data,'{}'::jsonb) ? 'lang' AND
    (p_kind LIKE 'order_%' OR p_kind IN ('waitlist_confirmation','waitlist_offer')) AND
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
      AND h.incident_id::text=p_message.data->>'incident_id' AND h.warning_code IS NOT NULL
      AND c.state IN ('connected','degraded') AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
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
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND payment_method='stripe')
   AND public.stripe_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method='stripe' THEN RETURN false; END IF;
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
  UPDATE public.email_messages SET workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
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
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds' WHERE singleton; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
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
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
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

-- SOURCE: emails/fakturoid_email_gate.sql
-- A Fakturoid checkout is not an accepted order until its proforma exists.
-- Keep its confirmation out of the email worker until checkout finalizes it.
CREATE OR REPLACE FUNCTION public.enqueue_ticket_order_confirmation_v1(
  p_command_id uuid, p_occasion bigint, p_order_payload jsonb, p_language text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_organization bigint;
  v_unit bigint;
  v_order_id bigint := (p_order_payload#>>'{order,id}')::bigint;
  v_await_fakturoid boolean;
BEGIN
  SELECT o.organization, o.unit INTO v_organization, v_unit
  FROM public.occasions o WHERE o.id = p_occasion;
  IF v_organization IS NULL OR p_command_id IS NULL OR v_order_id IS NULL
     OR p_order_payload IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order effect';
  END IF;
  SELECT (coalesce((p_order_payload#>>'{order,payment_info,amount}')::numeric,0)>0)
    AND EXISTS (SELECT 1 FROM eshop.external_services es
                WHERE es.unit=v_unit AND es.type='FAKTUROID')
  INTO v_await_fakturoid;
  IF v_await_fakturoid THEN
    UPDATE eshop.orders SET state='preparing_payment', updated_at=now()
    WHERE id=v_order_id AND occasion=p_occasion AND state='ordered';
    IF NOT FOUND THEN
      RAISE check_violation USING MESSAGE='Fakturoid order is not ready for preparation';
    END IF;
  END IF;
  PERFORM public.enqueue_order_email('TICKET_ORDER_CONFIRMATION',jsonb_build_object(
    'command_id',p_command_id,'ticket_order',p_order_payload,'lang',coalesce(nullif(p_language,''),(SELECT CASE WHEN data->>'DEFAULT_LANGUAGE'='en' THEN 'en' ELSE 'cs' END FROM public.organizations WHERE id=v_organization),'cs'),
    'fakturoid_pending',v_await_fakturoid),v_organization,p_occasion,v_unit,
    CASE WHEN v_await_fakturoid THEN 'infinity'::timestamptz ELSE now() END);

END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_ticket_order_confirmation_v1(uuid,bigint,jsonb,text)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_fakturoid_ticket_order_state_v1(p_order_id bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_state text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state INTO v_state FROM eshop.orders o WHERE o.id=p_order_id;
  IF v_state IS NULL THEN
    RAISE no_data_found USING MESSAGE='ticket order not found';
  END IF;
  RETURN v_state;
END;
$$;
REVOKE ALL ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.complete_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid, p_variable_symbol bigint
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_currency text;
  v_payment_id bigint;
  v_existing_vs bigint;
  v_occasion bigint;
  v_queue_id bigint;
  v_impacts jsonb;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
  IF EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE target_order_id=p_order_id AND command_id=p_command_id AND state='aborted') THEN
    RAISE EXCEPTION 'Acceptance attempt aborted'; END IF;
  SELECT o.state,trim(o.currency_code),o.payment_info,o.occasion,pi.variable_symbol
  INTO v_state,v_currency,v_payment_id,v_occasion,v_existing_vs
  FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
  WHERE o.id=p_order_id FOR UPDATE OF o,pi;
  IF v_state IS NULL OR p_command_id IS NULL OR p_variable_symbol NOT BETWEEN 1 AND 9999999999 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid Fakturoid completion';
  END IF;
  IF v_state IN ('ordered','paid') THEN
    RETURN v_existing_vs;
  END IF;
  IF v_state<>'preparing_payment' THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.email_messages q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  IF v_currency NOT IN ('CZK','EUR') OR v_existing_vs IS DISTINCT FROM p_variable_symbol THEN
    RAISE check_violation USING MESSAGE='Fakturoid symbol differs from application payment reference';
  END IF;
  UPDATE eshop.waitlist_acceptance_attempts SET state='completed',updated_at=clock_timestamp()
   WHERE target_order_id=p_order_id AND command_id=p_command_id AND state='preparing';
  UPDATE eshop.orders SET state='ordered',updated_at=now() WHERE id=p_order_id;
  UPDATE public.email_messages SET target_time=now(),workflow_state='pending',
    data=jsonb_set(data-'fakturoid_pending','{ticket_order,order,payment_info,variable_symbol}',to_jsonb(p_variable_symbol))
  WHERE id=v_queue_id;
  PERFORM public.wake_email_worker();
  SELECT coalesce(jsonb_agg(jsonb_build_object('component',component,
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
  FROM public.occasion_users ou CROSS JOIN unnest(
    ARRAY['private_profile','private_inventory']) component
  WHERE ou.occasion=v_occasion;
  PERFORM public.record_client_sync_commit_v1(v_occasion,
    'fakturoid.order.complete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order_id,'operation','update',
      'safeLabel','Order payment ready','changedFields',
      jsonb_build_array('state','payment_info'))),'{}',v_impacts,'[]',
    'service',NULL);
  RETURN p_variable_symbol;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.abort_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_occasion bigint;
  v_queue_id bigint;
  v_before_users uuid[];
  v_abort_command uuid := extensions.gen_random_uuid();
  v_hash text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
  IF EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command_id AND target_order_id=p_order_id AND state='aborted') THEN RETURN; END IF;
  SELECT o.state,o.occasion INTO v_state,v_occasion
  FROM eshop.orders o WHERE o.id=p_order_id FOR UPDATE;
  IF v_state='storno' THEN RETURN; END IF;
  IF v_state IS DISTINCT FROM 'preparing_payment' OR p_command_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.email_messages q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
  FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order_id,'reason','fakturoid_failed')::text,'UTF8'),'sha256'),'hex');
  PERFORM public.begin_anonymous_client_mutation_v1(v_abort_command,
    'inventory.order.fakturoid_abort',v_occasion,extensions.gen_random_uuid(),v_hash);
  UPDATE public.email_messages SET workflow_state='cancelled',last_error='fakturoid_aborted' WHERE id=v_queue_id;
  IF NOT public.abort_waitlist_acceptance_internal(p_order_id,p_command_id) THEN
    UPDATE eshop.orders SET state='ordered' WHERE id=p_order_id;
    PERFORM public.cancel_order_domain_internal_v1(p_order_id,false);
  END IF;
  PERFORM public.complete_profile_inventory_membership_mutation_v1(
    v_abort_command,v_occasion,'inventory.order.fakturoid_abort',
    jsonb_build_array(jsonb_build_object('entityType','order',
      'entityId',p_order_id,'operation','update','safeLabel','Failed order',
      'changedFields',jsonb_build_array('state','tickets','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order_id),'service');
END;
$$;
REVOKE ALL ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  TO service_role;

-- SOURCE: eshop_stripe/order_creation.sql
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
  (pi.amount*100)::bigint,pi.currency_code,1,'festapp:checkout:'||attempt,stamp,stamp+interval '31 minutes',
  (SELECT rtrim(data->>'DEFAULT_URL','/')||'/stripe/return' FROM public.organizations WHERE id=c.organization_id),
  (SELECT CASE WHEN data->>'DEFAULT_LANGUAGE' IN ('cs','en','de','pl','sk') THEN data->>'DEFAULT_LANGUAGE' ELSE 'en' END FROM public.organizations WHERE id=c.organization_id));
 UPDATE eshop.payment_info SET deadline=stamp+interval '31 minutes' WHERE id=pi.id;
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
  WHEN a.state='expired' OR a.reservation_expires_at<=clock_timestamp() OR o.state IN ('expired','storno') THEN 'expired'
  WHEN a.state IN ('uncertain','preparing') THEN 'preparing' ELSE 'open' END;
 admission:=CASE WHEN totals.disputed>0 OR status IN ('refunded','action_required') THEN 'hold'
  WHEN status IN ('paid','partially_refunded') AND o.state IN ('paid','sent') THEN 'valid' ELSE 'pending' END;
 SELECT CASE workflow_state WHEN 'accepted' THEN 'accepted' WHEN 'failed' THEN 'failed' WHEN 'suppressed' THEN 'suppressed' WHEN 'cancelled' THEN 'suppressed' ELSE 'pending' END INTO delivery
 FROM public.email_messages WHERE order_id=o.id AND message_kind='order_tickets' ORDER BY created_at DESC,id DESC LIMIT 1;
 RETURN jsonb_build_object('method','stripe','status',status,'amount',pi.amount::text,'received',totals.gross_received::numeric(30,2)::text,
  'returned',totals.refunded::numeric(30,2)::text,'currency',trim(pi.currency_code),'admissionState',admission,'deliveryState',coalesce(delivery,'not_requested'),
  'orderState',o.state,'reservationExpiresAt',a.reservation_expires_at,'serverNow',clock_timestamp(),
  'lastSyncedAt',a.last_synced_at,'reconciliationPending',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL,'reconciliationFailures',a.reconcile_failures,
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
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[cap.order_id]);
 PERFORM public.authorize_stripe_capability_internal(p_token,'order_pay',cap.order_id);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=cap.order_id;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 IF a.livemode IS DISTINCT FROM p_livemode OR pi.payment_method<>'stripe' OR pi.stripe_connection_id<>a.connection_id
  OR pi.amount*100<>a.amount_minor OR pi.currency_code<>a.currency OR o.currency_code<>a.currency
  OR coalesce(pi.paid_externally,0)<>0 THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 projection:=public.stripe_order_payment_projection_internal(o.id);
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
 RETURN public.stripe_order_payment_projection_internal(cap.order_id)-'allowedActions'||jsonb_build_object('allowedActions',jsonb_build_array('refresh'));
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
 RETURN public.stripe_order_payment_projection_internal(cap.order_id);
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
