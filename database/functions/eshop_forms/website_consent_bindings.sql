-- Managed CMS imports are public configuration references, never credentials.
CREATE TABLE IF NOT EXISTS analytics.website_consent_bindings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
 website_origin text NOT NULL,
 platform text NOT NULL CHECK(platform IN ('wordpress','joomla','wix','html')),
 provider_config jsonb NOT NULL,
 version bigint NOT NULL CHECK(version>0),
 enabled boolean NOT NULL DEFAULT false,
 confirmed_revision text,
 confirmed_by uuid REFERENCES auth.users(id),
 confirmed_at timestamptz,
 UNIQUE(unit,website_origin)
);
ALTER TABLE analytics.website_consent_bindings DROP CONSTRAINT IF EXISTS website_consent_bindings_platform_check;
ALTER TABLE analytics.website_consent_bindings ADD CONSTRAINT website_consent_bindings_platform_check CHECK(platform IN ('wordpress','joomla','wix','html'));
ALTER TABLE analytics.website_consent_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.website_consent_bindings FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.website_consent_binding_effective_internal(p_binding analytics.website_consent_bindings)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(b.enabled AND b.website_origin ~ (public.configuration_settings_contract_internal_v1()#>>'{unit,measurement_websites,items,allOf,0,pattern}')
  AND b.confirmed_revision=public.unit_measurement_consent_scope_internal(u.id)->>'consentRevision'
  AND u.data->'measurement_consent_bridge'='true'::jsonb
  AND NOT public.is_demo_unit(u.id)
  AND coalesce(u.data->'measurement_websites','[]'::jsonb) ? b.website_origin,false)
 FROM public.units u
 CROSS JOIN LATERAL (SELECT (p_binding).*) b WHERE u.id=b.unit;
$$;
REVOKE ALL ON FUNCTION public.website_consent_binding_effective_internal(analytics.website_consent_bindings) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.website_consent_bindings_policy_internal(p_unit bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'version',b.version,'websiteOrigin',b.website_origin,
  'effective',public.website_consent_binding_effective_internal(b)) ORDER BY b.website_origin),'[]'::jsonb)
 FROM analytics.website_consent_bindings b WHERE b.unit=p_unit
  AND b.website_origin ~ (public.configuration_settings_contract_internal_v1()#>>'{unit,measurement_websites,items,allOf,0,pattern}');
$$;
REVOKE ALL ON FUNCTION public.website_consent_bindings_policy_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Validate provider inputs once, at the authoritative write boundary. Category
-- bounds count UTF-16 code units, matching the existing JavaScript CMP adapter.
CREATE OR REPLACE FUNCTION public.normalize_website_consent_provider_internal(p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE provider text:=p_config->>'provider'; a text; m text;
BEGIN
 IF jsonb_typeof(p_config) IS DISTINCT FROM 'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid_consent_provider'; END IF;
 IF provider='complianz' THEN
  IF jsonb_typeof(p_config->'policyId') IS DISTINCT FROM 'string' OR (p_config->>'policyId') !~ '^[1-9][0-9]{0,15}$' THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid_complianz_policy'; END IF;
  RETURN jsonb_build_object('provider',provider,'policyId',p_config->>'policyId');
 ELSIF provider IN ('cookiebot','wix') THEN
  RETURN jsonb_build_object('provider',provider);
 ELSIF provider='cookieconsent' THEN
  IF NOT p_config ? 'categories' THEN RETURN jsonb_build_object('provider',provider); END IF;
  a:=p_config#>>'{categories,analytics}'; m:=p_config#>>'{categories,marketing}';
  IF a IS NULL OR m IS NULL OR a=m
   OR jsonb_typeof(p_config#>'{categories,analytics}') IS DISTINCT FROM 'string'
   OR jsonb_typeof(p_config#>'{categories,marketing}') IS DISTINCT FROM 'string'
   OR length(a)=0 OR length(m)=0
   OR (SELECT coalesce(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0) FROM regexp_split_to_table(a,'') c)>128
   OR (SELECT coalesce(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0) FROM regexp_split_to_table(m,'') c)>128 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid_cookieconsent_mapping'; END IF;
  RETURN jsonb_build_object('provider',provider,'categories',jsonb_build_object('analytics',a,'marketing',m));
 END IF;
 RAISE invalid_parameter_value USING MESSAGE='unsupported_consent_provider';
END $$;
REVOKE ALL ON FUNCTION public.normalize_website_consent_provider_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_website_consent_bindings(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_manage_unit_configuration(p_unit) THEN RAISE insufficient_privilege; END IF;
 RETURN public.unit_measurement_consent_scope_internal(p_unit)||jsonb_build_object(
  'saved_origins',(SELECT coalesce(data->'measurement_websites','[]'::jsonb) FROM public.units WHERE id=p_unit),'bindings',
  coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'websiteOrigin',b.website_origin,'platform',b.platform,
   'providerConfig',b.provider_config,'version',b.version,'confirmedRevision',b.confirmed_revision,
   'state',CASE WHEN NOT b.enabled THEN CASE WHEN b.confirmed_revision IS NULL THEN 'draft' ELSE 'disabled' END
     WHEN b.confirmed_revision IS DISTINCT FROM public.unit_measurement_consent_scope_internal(p_unit)->>'consentRevision' THEN 'confirmation_required'
     WHEN public.website_consent_binding_effective_internal(b) THEN 'ready' ELSE 'unavailable' END)
    ORDER BY b.website_origin) FROM analytics.website_consent_bindings b WHERE b.unit=p_unit),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_unit_website_consent_bindings(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_website_consent_bindings(bigint) TO authenticated;

-- A Unit lock serializes authoring with the canonical Unit aggregate save.
-- Version zero means absent. Every write advances the version, including off.
CREATE OR REPLACE FUNCTION public.save_unit_website_consent_binding(p_unit bigint,p_website_origin text,p_platform text,
 p_provider_config jsonb,p_expected_version bigint,p_expected_consent_revision text,p_confirm boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u public.units; b analytics.website_consent_bindings; scope jsonb; config jsonb; confirmation_time timestamptz;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_manage_unit_configuration(p_unit) THEN RAISE insufficient_privilege; END IF;
 SELECT * INTO STRICT u FROM public.units WHERE id=p_unit FOR UPDATE;
 IF p_website_origin IS NULL OR length(p_website_origin)>2048 OR NOT coalesce(u.data->'measurement_websites','[]'::jsonb) ? p_website_origin
  OR p_platform IS NULL OR p_platform NOT IN ('wordpress','joomla','wix','html') OR p_confirm IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid_website_binding'; END IF;
 -- Use the canonical exact-origin validation, rather than accepting URLs.
 PERFORM public.validate_configuration_value_internal_v1(jsonb_build_array(p_website_origin),public.configuration_settings_contract_internal_v1()#>'{unit,measurement_websites}');
 scope:=public.unit_measurement_consent_scope_internal(p_unit);
 SELECT * INTO b FROM analytics.website_consent_bindings WHERE unit=p_unit AND website_origin=p_website_origin FOR UPDATE;
 IF p_expected_version IS DISTINCT FROM coalesce(b.version,0) OR p_expected_consent_revision IS DISTINCT FROM scope->>'consentRevision' THEN
  RAISE serialization_failure USING MESSAGE='website_consent_conflict'; END IF;
 config:=public.normalize_website_consent_provider_internal(p_provider_config);
 -- Timestamped CMP records must postdate this explicit coverage confirmation.
 -- The caller cannot backdate coverage or extend the server's one-year ceiling.
 confirmation_time:=CASE WHEN p_confirm THEN clock_timestamp() END;
 IF p_confirm AND config->>'provider' IN ('cookiebot','wix','cookieconsent') THEN
  config:=config||jsonb_build_object('consentValidFrom',to_char(confirmation_time AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'maxAgeSeconds',31536000);
 END IF;
 INSERT INTO analytics.website_consent_bindings(unit,website_origin,platform,provider_config,version,enabled,confirmed_revision,confirmed_by,confirmed_at)
 VALUES(p_unit,p_website_origin,p_platform,config,1,p_confirm,CASE WHEN p_confirm THEN scope->>'consentRevision' END,
  CASE WHEN p_confirm THEN auth.uid() END,confirmation_time)
 ON CONFLICT(unit,website_origin) DO UPDATE SET platform=excluded.platform,provider_config=excluded.provider_config,
  version=analytics.website_consent_bindings.version+1,enabled=excluded.enabled,confirmed_revision=excluded.confirmed_revision,
  confirmed_by=excluded.confirmed_by,confirmed_at=excluded.confirmed_at;
 RETURN public.get_unit_website_consent_bindings(p_unit);
END $$;
REVOKE ALL ON FUNCTION public.save_unit_website_consent_binding(bigint,text,text,jsonb,bigint,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_unit_website_consent_binding(bigint,text,text,jsonb,bigint,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.disable_unit_website_consent_binding(p_binding uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE un bigint;
BEGIN
 SELECT unit INTO un FROM analytics.website_consent_bindings WHERE id=p_binding;
 IF auth.uid() IS NULL OR NOT coalesce(public.can_manage_unit_configuration(un),false) THEN RAISE insufficient_privilege; END IF;
 PERFORM 1 FROM public.units WHERE id=un FOR UPDATE;
 UPDATE analytics.website_consent_bindings SET enabled=false,version=version+1 WHERE id=p_binding AND version=p_expected_version;
 IF NOT FOUND THEN RAISE serialization_failure USING MESSAGE='website_consent_conflict'; END IF;
 RETURN public.get_unit_website_consent_bindings(un);
END $$;
REVOKE ALL ON FUNCTION public.disable_unit_website_consent_binding(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.disable_unit_website_consent_binding(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.export_unit_website_consent_binding(p_binding uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b analytics.website_consent_bindings; scope jsonb; origin text;
BEGIN
 SELECT * INTO b FROM analytics.website_consent_bindings WHERE id=p_binding;
 IF auth.uid() IS NULL OR NOT coalesce(public.can_manage_unit_configuration(b.unit),false) THEN RAISE insufficient_privilege; END IF;
 IF b.version IS DISTINCT FROM p_expected_version THEN RAISE serialization_failure USING MESSAGE='website_consent_conflict'; END IF;
 IF NOT coalesce(public.website_consent_binding_effective_internal(b),false) THEN RAISE invalid_parameter_value USING MESSAGE='website_consent_not_ready'; END IF;
 SELECT rtrim(o.data->>'DEFAULT_URL','/') INTO origin FROM public.units u JOIN public.organizations o ON o.id=u.organization WHERE u.id=b.unit;
 IF origin IS NULL OR origin !~ '^https://[a-z0-9.-]+(:[0-9]+)?$' THEN RAISE invalid_parameter_value USING MESSAGE='website_consent_service_origin_missing'; END IF;
 scope:=public.unit_measurement_consent_scope_internal(b.unit);
 RETURN jsonb_build_object('schemaVersion',1,'serviceOrigin',origin,'websiteOrigin',b.website_origin,
  'binding',jsonb_build_object('id',b.id,'version',b.version),'providerConfig',b.provider_config||
   jsonb_build_object('organization',scope->'organization','unit',b.unit,'consentRevision',b.confirmed_revision,'origin',b.website_origin));
END $$;
REVOKE ALL ON FUNCTION public.export_unit_website_consent_binding(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.export_unit_website_consent_binding(uuid,bigint) TO authenticated;
