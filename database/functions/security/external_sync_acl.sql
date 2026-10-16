-- Internal service tables; retired SQL HTTP importer stays retired.
DO $$
DECLARE t text; policy record;
BEGIN
  FOREACH t IN ARRAY ARRAY['external_sync_sources','external_sync_maps','external_occasions_cache'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR policy IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename=t LOOP
      EXECUTE format('DROP POLICY %I ON public.%I', policy.policyname,t);
    END LOOP;
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role',t);
    EXECUTE format('CREATE POLICY service_only ON public.%I TO service_role USING (true) WITH CHECK (true)',t);
  END LOOP;
END $$;
REVOKE ALL ON SEQUENCE public.external_sync_maps_id_seq FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE public.external_sync_maps_id_seq TO service_role;
