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
