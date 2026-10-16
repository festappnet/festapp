-- Retired dormant writer: the SQL HTTP extension buffers unbounded remote bodies.
-- Read-only canonical runtime inventory found zero sources/maps/import jobs.
-- Do not re-enable this path without a bounded transport and complete snapshot.
CREATE OR REPLACE FUNCTION public.sync_source_via_http(p_target_source_name text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RAISE feature_not_supported USING MESSAGE='unbounded_http_import_retired';
END $$;
REVOKE ALL ON FUNCTION public.sync_source_via_http(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sync_source_via_http(text) TO service_role;
