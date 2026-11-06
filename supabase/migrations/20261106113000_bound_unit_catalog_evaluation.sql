-- Bound form metadata, registration modes and measurement policy to one
-- evaluation per projection. Signatures, access control and sale semantics stay intact.

-- Source: database/functions/eshop_forms/form_measurement_policy.sql
CREATE OR REPLACE FUNCTION public.form_measurement_status_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH scope AS MATERIALIZED (
  SELECT coalesce(public.normalize_form_metadata_internal(f.data)#>'{analytics,enabled}'='true'::jsonb,false) requested,
   coalesce(org.data->'FORM_MEASUREMENT_ENABLED'='true'::jsonb,false) organization_enabled,
   coalesce(u.data->'measurement_enabled'='true'::jsonb,false) unit_enabled,
   coalesce(p.enabled,false) allowed,coalesce(p.revision,0) revision,
   coalesce(nullif(btrim(u.data->>'measurement_gtm_container'),''),nullif(u.data->>'measurement_scripts','')) IS NOT NULL destination,
   coalesce(r.runtime_profile='gtm-v1' AND r.runtime_origin ~ '^https://[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\.pages\.dev$'
    AND cardinality(r.parent_origins)>0 AND NOT public.is_demo_occasion(f.occasion),false) supported
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
  JOIN public.organizations org ON org.id=o.organization
  LEFT JOIN analytics.organization_policy p ON p.organization=o.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
  WHERE f.id=p_form
 ) SELECT jsonb_build_object('requested_enabled',requested,'organization_allowed',allowed,
  'organization_enabled',organization_enabled,'unit_enabled',unit_enabled,
  'runtime_supported',supported,'eligible',requested AND allowed AND organization_enabled AND unit_enabled AND destination AND supported,
  'policy_revision',revision,'consent_required',true,'enhanced_conversions_unavailable',true,
  'blocked_reasons',to_jsonb(array_remove(ARRAY[
   CASE WHEN NOT requested THEN 'disabled' END,
   CASE WHEN NOT allowed THEN 'organization_not_enabled' END,
   CASE WHEN NOT organization_enabled THEN 'organization_disabled' END,
   CASE WHEN NOT unit_enabled THEN 'unit_disabled' END,
   CASE WHEN NOT supported THEN 'runtime_unavailable' END,
   CASE WHEN NOT destination THEN 'no_destination' END],NULL))) FROM scope;
$$;

-- Source: database/functions/eshop_forms/form_measurement_policy.sql
CREATE OR REPLACE FUNCTION public.form_measurement_runtime_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH status AS MATERIALIZED (
  SELECT public.form_measurement_status_internal(p_form) AS s
 )
 SELECT jsonb_build_object('enabled',s->'requested_enabled','organization_allowed',s->'organization_allowed',
  'runtime_supported',s->'runtime_supported','eligible',s->'eligible','organization',o.organization,'unit',u.id,
  'runtime_origin',CASE WHEN s->'eligible'='true'::jsonb THEN r.runtime_origin END,
  'configuration_revision',md5(jsonb_build_array(u.data->'measurement_gtm_container',u.data->'measurement_scripts',
   u.data->'measurement_enabled',org.data->'FORM_MEASUREMENT_ENABLED',s->'requested_enabled')::text),
  'runtime_revision',coalesce(r.revision,0),'policy_revision',s->'policy_revision','valid_for_seconds',60,'consent_required',true)
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
 JOIN public.organizations org ON org.id=o.organization
 LEFT JOIN analytics.organization_policy p ON p.organization=o.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
 CROSS JOIN status
 WHERE f.id=p_form;
$$;

-- Source: database/functions/eshop_forms/form_availability.sql
CREATE OR REPLACE FUNCTION public.get_form_availability_snapshot_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH form_config AS MATERIALIZED (
  SELECT f.is_open,public.get_effective_form_data(f.id) AS d
  FROM public.forms f WHERE f.id=p_form
 )
 SELECT public.get_form_availability_from_config_internal(jsonb_build_object('manualOpen',is_open,
 'startAt',nullif(coalesce(d#>>'{schedule,start_time}',d->>'start_time'),'')::timestamptz,
 'endAt',nullif(coalesce(d#>>'{schedule,end_time}',d->>'end_time'),'')::timestamptz),p_at)
 FROM form_config;
$$;

-- Source: database/functions/eshop_waitlist/form_capacity.sql
CREATE OR REPLACE FUNCTION public.get_form_registration_mode_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 IF NOT (public.get_form_availability_snapshot_internal(p_form,p_at)->>'isWindowOpen')::boolean THEN RETURN 'closed'; END IF;
 IF f.blueprint IS NOT NULL AND EXISTS (
  SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
 ) THEN RETURN 'blueprint'; END IF;
 c:=public.get_form_capacity_snapshot_internal(p_form,p_at);
 IF f.participant_capacity IS NULL OR (c->>'remainingPublic')::bigint>0 THEN RETURN 'regular'; END IF;
 RETURN CASE WHEN f.waitlist_enabled THEN 'waitlist' ELSE 'full' END;
END $$;

-- Source: database/functions/occasion_setup/sale_status.sql
CREATE OR REPLACE FUNCTION public.get_occasion_sale_forms_internal(p_occasion bigint,p_at timestamptz DEFAULT statement_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 -- LATERAL aliases can be expanded once for every JSON field/CASE reference.
 -- Keep each form's configuration and capacity mode as one request-local value.
 WITH form_data AS MATERIALIZED (
  SELECT f.*,public.get_effective_form_data(f.id) AS effective_data
  FROM public.forms f WHERE f.occasion=p_occasion
 ), form_modes AS MATERIALIZED (
  SELECT f.*,public.get_form_registration_mode_internal(f.id,
   greatest(p_at,nullif(coalesce(f.effective_data#>>'{schedule,start_time}',
    f.effective_data->>'start_time'),'')::timestamptz)) AS registration_mode
  FROM form_data f
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',f.id,'is_open',f.is_open,
  'has_tickets',EXISTS(SELECT 1 FROM public.form_fields ticket_field WHERE ticket_field.form=f.id AND ticket_field.type='ticket' AND NOT coalesce(ticket_field.is_hidden,false)),
  'is_preparation',coalesce((f.effective_data#>>'{schedule,sale_preparation}')::boolean,false),
  'start_time',nullif(coalesce(f.effective_data#>>'{schedule,start_time}',f.effective_data->>'start_time'),''),
  'end_time',nullif(coalesce(f.effective_data#>>'{schedule,end_time}',f.effective_data->>'end_time'),''),
  'enable_countdown',coalesce((coalesce(f.effective_data#>>'{schedule,enable_countdown}',f.effective_data->>'enable_countdown'))::boolean,false),
  'registration_mode',f.registration_mode,
  'has_availability',CASE
   WHEN f.registration_mode='blueprint' THEN EXISTS (
    -- Resolve the form's small offer before running expensive inventory checks.
    -- Without this boundary a hash join can evaluate every system product.
    WITH offered_products AS MATERIALIZED (
     SELECT p.id,offered.has_capacity
     FROM public.blueprint_form_products_internal(f.id) offered
     JOIN eshop.products p ON p.id=offered.product
     WHERE NOT p.is_hidden
    )
    SELECT 1 FROM offered_products p
    WHERE public.is_product_dynamically_available(p.id)
    AND (public.blueprint_product_availability_internal(p.id)->>'available')::bigint>0
    AND (p.has_capacity OR EXISTS (
     SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
     WHERE sb.blueprint=f.blueprint AND s.product=p.id AND NOT sb.blocked
      AND NOT EXISTS (
       SELECT 1 FROM unnest(public.blueprint_selection_unit_spots_internal(s.id)) member(id)
       JOIN eshop.spots occupied ON occupied.id=member.id
       WHERE occupied.order_product_ticket IS NOT NULL OR occupied.state='black'
        OR (occupied.secret IS NOT NULL AND occupied.secret_expiration_time>p_at))
    )))
   WHEN f.registration_mode='regular' THEN NOT EXISTS (
    WITH required_fields AS MATERIALIZED (
     SELECT ff.product_type FROM public.form_fields ff
     JOIN eshop.product_types pt ON pt.id=ff.product_type
     WHERE ff.form=f.id AND NOT coalesce(ff.is_hidden,false)
     AND (pt.type='spot' OR ff.is_required)
    )
    SELECT 1 FROM required_fields ff WHERE NOT EXISTS (
      WITH field_products AS MATERIALIZED (
       SELECT p.id FROM eshop.products p
       WHERE p.product_type=ff.product_type AND NOT p.is_hidden
      )
      SELECT 1 FROM field_products p WHERE public.is_product_dynamically_available(p.id)
      AND (public.blueprint_product_availability_internal(p.id)->>'available')::bigint>0))
   ELSE f.registration_mode='waitlist' END
 ) ORDER BY f.id),'[]'::jsonb)
 FROM form_modes f;
$$;

NOTIFY pgrst, 'reload schema';
