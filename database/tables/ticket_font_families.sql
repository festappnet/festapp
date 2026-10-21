-- Immutable family manifests extend the existing Ticket font registry. Faces
-- retain their byte-hash IDs; a family ID never changes the meaning of a face ID.
CREATE TABLE IF NOT EXISTS public.ticket_font_families (
 id text PRIMARY KEY CHECK(id ~ '^font-family:[a-f0-9]{64}$'),
 manifest jsonb NOT NULL CHECK(manifest->>'id'=id AND manifest->>'version'='1'
  AND manifest->>'hash'=substr(id,13) AND jsonb_typeof(manifest->'faces')='object')
);
ALTER TABLE public.ticket_font_families ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ticket_font_families FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON public.ticket_font_families TO service_role;
GRANT SELECT ON public.ticket_font_families TO authenticated;
DROP POLICY IF EXISTS ticket_font_families_read ON public.ticket_font_families;
CREATE POLICY ticket_font_families_read ON public.ticket_font_families FOR SELECT TO authenticated USING(true);
