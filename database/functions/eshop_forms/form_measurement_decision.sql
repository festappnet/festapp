-- Evaluate each form's current configuration once per caller. The order
-- cohort, visitor consent and payment evidence are checked by their own owners.
CREATE OR REPLACE FUNCTION public.form_measurement_decision_internal(p_form bigint)
RETURNS TABLE(requested_enabled boolean,organization_allowed boolean,organization_enabled boolean,
 unit_enabled boolean,privacy_policy_valid boolean,runtime_supported boolean,destination_configured boolean,
 policy_revision bigint,conversion_eligible boolean,browser_eligible boolean,capi_unit bigint,purchase_timing text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH scope AS MATERIALIZED (
  SELECT public.normalize_form_metadata_internal(f.data)->'analytics' settings,
   coalesce(p.enabled,false) organization_allowed,coalesce(p.revision,0) policy_revision,
   coalesce(org.data->'FORM_MEASUREMENT_ENABLED'='true'::jsonb,false) organization_enabled,
   coalesce(u.data->'measurement_enabled'='true'::jsonb,false) unit_enabled,
   coalesce(length(u.data->>'measurement_privacy_url') BETWEEN 1 AND 2048
    AND (u.data->>'measurement_privacy_url') ~ (public.configuration_settings_contract_internal_v1()#>>'{unit,measurement_privacy_url,pattern}'),false)
    privacy_policy_valid,
   public.form_measurement_runtime_supported_internal(r.runtime_profile,r.runtime_origin,r.parent_origins) runtime_supported,
   coalesce(nullif(btrim(u.data->>'measurement_gtm_container'),''),nullif(u.data->>'measurement_scripts','')) IS NOT NULL destination_configured,
   public.is_demo_occasion(f.occasion) demo,
   c.unit connector_unit,c.paused_at
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
  JOIN public.organizations org ON org.id=o.organization
  LEFT JOIN analytics.organization_policy p ON p.organization=o.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
  LEFT JOIN analytics.meta_purchase_forms m ON m.form=f.id AND m.unit=u.id
  LEFT JOIN analytics.meta_purchase_connectors c ON c.unit=m.unit AND c.enabled
  WHERE f.id=p_form
 ), readiness AS (
  SELECT scope.*,coalesce(settings->'enabled'='true'::jsonb,false) requested_enabled,
   coalesce(settings->'enabled'='true'::jsonb,false) AND organization_allowed AND organization_enabled
    AND unit_enabled AND privacy_policy_valid conversion_eligible
  FROM scope
 )
 SELECT d.requested_enabled,d.organization_allowed,d.organization_enabled,d.unit_enabled,d.privacy_policy_valid,
  d.runtime_supported AND NOT d.demo,d.destination_configured,d.policy_revision,d.conversion_eligible,
  d.conversion_eligible AND d.runtime_supported AND NOT d.demo AND d.destination_configured,
  CASE WHEN NOT d.demo AND d.paused_at IS NULL THEN d.connector_unit END,
  CASE WHEN (d.connector_unit IS NOT NULL AND NOT d.demo) OR d.settings->>'purchase_timing'='paid'
   THEN 'paid' ELSE 'order' END
 FROM readiness d;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_decision_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
