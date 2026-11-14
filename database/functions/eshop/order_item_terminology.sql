-- Presentation only. Issuance, scanning and delivery keep their own policies.
CREATE OR REPLACE FUNCTION public.uses_ticket_terminology_internal(p_features jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER
SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(
  CASE WHEN jsonb_typeof(p_features)='array' THEN p_features ELSE '[]'::jsonb END
 ) feature WHERE feature->>'code'='ticket' AND feature->'is_enabled'='true'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.uses_ticket_terminology_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
