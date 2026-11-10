CREATE SCHEMA IF NOT EXISTS analytics;
REVOKE ALL ON SCHEMA analytics FROM PUBLIC,anon,authenticated,service_role;

-- Platform deployment permission is distinct from administrator-owned switches.
CREATE TABLE IF NOT EXISTS analytics.organization_policy (
 organization bigint PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
 enabled boolean NOT NULL DEFAULT false,
 revision bigint NOT NULL CHECK(revision>0),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 operator text NOT NULL CHECK(length(btrim(operator))>0),
 reason text NOT NULL CHECK(length(btrim(reason))>0)
);
-- Runtime code is authored by Unit managers, so each Unit has its own site.
CREATE TABLE IF NOT EXISTS analytics.unit_runtime (
 unit bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 runtime_origin text NOT NULL UNIQUE CHECK(runtime_origin ~ '^https://[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\.pages\.dev$'),
 runtime_profile text NOT NULL CHECK(runtime_profile='gtm-v1'),
 parent_origins text[] NOT NULL CHECK(cardinality(parent_origins)>0),
 collector_origins text[] NOT NULL DEFAULT '{}',
 revision bigint NOT NULL CHECK(revision>0),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 operator text NOT NULL CHECK(length(btrim(operator))>0),
 reason text NOT NULL CHECK(length(btrim(reason))>0)
);
ALTER TABLE analytics.unit_runtime ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.unit_runtime FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE analytics.organization_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.organization_policy FROM PUBLIC,anon,authenticated,service_role;

-- Shared redaction for public/catalog Unit projections. Manager reads retain
-- the single canonical Unit configuration; browsers never get raw script data.
CREATE OR REPLACE FUNCTION public.form_measurement_unit_data_internal(p_unit bigint,p_data jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN public.can_manage_unit_configuration(p_unit) THEN jsonb_build_object('measurement_consent_version',1,'measurement_consent_bridge',false)||coalesce(p_data,'{}'::jsonb)
  ELSE (jsonb_build_object('measurement_consent_version',1,'measurement_consent_bridge',false)||coalesce(p_data,'{}'::jsonb))-'measurement_gtm_container'-'measurement_scripts' END;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_unit_data_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- consent_required denotes the required notice/choice controls, not an execution gate.
-- required_purposes describes reported choices; neither purpose must be granted to run.
-- Single status owner. Configuration belongs to Unit; forms contain only intent.
CREATE OR REPLACE FUNCTION public.form_measurement_status_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH scope AS MATERIALIZED (
  SELECT coalesce(public.normalize_form_metadata_internal(f.data)#>'{analytics,enabled}'='true'::jsonb,false) requested,
   coalesce(org.data->'FORM_MEASUREMENT_ENABLED'='true'::jsonb,false) organization_enabled,
   coalesce(u.data->'measurement_enabled'='true'::jsonb,false) unit_enabled,
   coalesce(length(u.data->>'measurement_privacy_url') BETWEEN 1 AND 2048
    AND (u.data->>'measurement_privacy_url') ~ (public.configuration_settings_contract_internal_v1()#>>'{unit,measurement_privacy_url,pattern}'),false) privacy_policy_valid,
   coalesce(p.enabled,false) allowed,coalesce(p.revision,0) revision,
   coalesce(nullif(btrim(u.data->>'measurement_gtm_container'),''),nullif(u.data->>'measurement_scripts','')) IS NOT NULL destination,
   public.form_measurement_runtime_supported_internal(r.runtime_profile,r.runtime_origin,r.parent_origins)
    AND NOT public.is_demo_occasion(f.occasion) supported
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
  JOIN public.organizations org ON org.id=o.organization
  LEFT JOIN analytics.organization_policy p ON p.organization=o.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
  WHERE f.id=p_form
 ) SELECT jsonb_build_object('requested_enabled',requested,'organization_allowed',allowed,
  'organization_enabled',organization_enabled,'unit_enabled',unit_enabled,
  'runtime_supported',supported,'eligible',requested AND allowed AND organization_enabled AND unit_enabled AND destination AND supported AND privacy_policy_valid,
  'policy_revision',revision,'consent_required',true,'enhanced_conversions_unavailable',false,
  'blocked_reasons',to_jsonb(array_remove(ARRAY[
   CASE WHEN NOT requested THEN 'disabled' END,
   CASE WHEN NOT allowed THEN 'organization_not_enabled' END,
   CASE WHEN NOT organization_enabled THEN 'organization_disabled' END,
   CASE WHEN NOT unit_enabled THEN 'unit_disabled' END,
   CASE WHEN NOT supported THEN 'runtime_unavailable' END,
   CASE WHEN NOT destination THEN 'no_destination' END,
   CASE WHEN NOT privacy_policy_valid THEN 'no_privacy_policy' END],NULL))) FROM scope;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_status_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.form_measurement_runtime_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH status AS MATERIALIZED (
  SELECT public.form_measurement_status_internal(p_form) AS s
 )
 SELECT jsonb_build_object('enabled',s->'requested_enabled','organization_allowed',s->'organization_allowed',
  'runtime_supported',s->'runtime_supported','eligible',s->'eligible','organization',o.organization,'unit',u.id,
  'runtime_origin',CASE WHEN s->'eligible'='true'::jsonb THEN r.runtime_origin END,
  'measurement_consent_bridge',coalesce(u.data->'measurement_consent_bridge'='true'::jsonb,false),
  'privacy_url',CASE WHEN s->'eligible'='true'::jsonb THEN u.data->>'measurement_privacy_url' END,
  'consent_notice',CASE WHEN s->'eligible'='true'::jsonb THEN jsonb_build_object('layout',coalesce(u.data->>'measurement_consent_layout','bar'),
   'title',nullif(btrim(u.data->>'measurement_consent_title'),''),'text',nullif(btrim(u.data->>'measurement_consent_text'),'')) END,
  'approved_hosts',CASE WHEN s->'eligible'='true'::jsonb THEN to_jsonb(r.parent_origins) ELSE '[]'::jsonb END,
  'measurement_protocol',3,'form_link',f.link,'profile',r.runtime_profile,'required_purposes',jsonb_build_array('analytics','marketing'),
  'enhanced_conversions_unavailable',false,
  -- Append the opt-in only when enabled to preserve existing saved choices.
  'processing_revision',md5((jsonb_build_array(3,o.organization,u.id,u.data->'measurement_gtm_container',u.data->'measurement_scripts',
   u.data->'measurement_privacy_url',coalesce(u.data->'measurement_consent_version','1'::jsonb),r.runtime_profile,r.runtime_origin,
   r.parent_origins,r.collector_origins,r.revision,s->'policy_revision',u.data->'measurement_enabled',
   org.data->'FORM_MEASUREMENT_ENABLED',s->'requested_enabled')
   ||CASE WHEN u.data->'measurement_consent_bridge'='true'::jsonb THEN jsonb_build_array(true) ELSE '[]'::jsonb END)::text),
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
REVOKE ALL ON FUNCTION public.form_measurement_runtime_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS analytics.conversion_facts (
 "order" bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('purchase','waitlist','free_registration')),
 PRIMARY KEY("order",kind),
 event_id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
 payload jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE analytics.conversion_facts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.conversion_facts FROM PUBLIC,anon,authenticated,service_role;
