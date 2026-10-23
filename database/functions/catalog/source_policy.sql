-- Explicit source maps are opt-in per organization. Existing tenants retain
-- their current projections until their catalog policy is deliberately migrated.
CREATE OR REPLACE FUNCTION public.catalog_includes_occasion_internal(
  p_organization bigint, p_owner bigint, p_source text,
  p_legacy_external boolean DEFAULT false
) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organizations o WHERE o.id=p_organization AND (
      p_owner=p_organization OR CASE WHEN o.data->>'CATALOG_SOURCE_POLICY'='explicit'
      THEN EXISTS (SELECT 1 FROM public.external_sync_maps m
        WHERE m.target_org_id=p_organization AND m.source_name=p_source)
      ELSE p_legacy_external AND p_source IS NOT NULL END
    )
  );
$$;
REVOKE ALL ON FUNCTION public.catalog_includes_occasion_internal(bigint,bigint,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalog_includes_occasion_internal(bigint,bigint,text,boolean) TO postgres,supabase_admin;
