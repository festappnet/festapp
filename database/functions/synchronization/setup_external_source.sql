-- Do not install new scheduled calls to the retired unbounded HTTP importer.
CREATE OR REPLACE FUNCTION public.setup_external_source(p_source_name text,p_supabase_url text,p_anon_key text,p_cron_schedule text DEFAULT '*/5 * * * *')
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RAISE feature_not_supported USING MESSAGE='unbounded_http_import_retired';
END $$;
REVOKE ALL ON FUNCTION public.setup_external_source(text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.setup_external_source(text,text,text,text) TO service_role;
