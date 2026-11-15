CREATE OR REPLACE FUNCTION public.normalize_website_consent_provider_internal(p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE provider text:=p_config->>'provider'; a text; m text;
BEGIN
 IF jsonb_typeof(p_config) IS DISTINCT FROM 'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid_consent_provider'; END IF;
 IF provider IN ('complianz','cookiebot','wix') THEN
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

-- Preserve the confirmation receipt and binding version: only redundant inputs change.
UPDATE analytics.website_consent_bindings
SET provider_config=provider_config - ARRAY['policyId','cbid','consentValidFrom','maxAgeSeconds','revision']
WHERE provider_config ?| ARRAY['policyId','cbid','consentValidFrom','maxAgeSeconds','revision'];
