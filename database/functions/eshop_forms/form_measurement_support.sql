-- Structural support only. Resource owners retain their Unit/Occasion demo
-- exclusions and full policy/eligibility decisions.
CREATE OR REPLACE FUNCTION public.form_measurement_runtime_supported_internal(
 p_profile text,p_origin text,p_parents text[])
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT coalesce(p_profile='gtm-v1'
  AND p_origin ~ '^https://[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\.pages\.dev$'
  AND cardinality(p_parents)>0,false);
$$;
REVOKE ALL ON FUNCTION public.form_measurement_runtime_supported_internal(text,text,text[])
 FROM PUBLIC,anon,authenticated,service_role;
