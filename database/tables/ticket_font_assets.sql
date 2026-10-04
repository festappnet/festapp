-- Release-owned immutable font identities. Catalog refreshes only append rows.
CREATE TABLE IF NOT EXISTS public.ticket_font_assets (
  id text PRIMARY KEY CHECK (id ~ '^(gf:|builtin:[a-z0-9-]+:)[a-f0-9]{64}$'),
  metadata jsonb NOT NULL CHECK (metadata->>'id'=id)
);
ALTER TABLE public.ticket_font_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ticket_font_assets FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT ON public.ticket_font_assets TO service_role;
-- Validators run as invoker: public metadata can be read, never client-written.
GRANT SELECT ON public.ticket_font_assets TO authenticated;
DROP POLICY IF EXISTS ticket_font_metadata_read ON public.ticket_font_assets;
CREATE POLICY ticket_font_metadata_read ON public.ticket_font_assets FOR SELECT TO authenticated USING (true);
