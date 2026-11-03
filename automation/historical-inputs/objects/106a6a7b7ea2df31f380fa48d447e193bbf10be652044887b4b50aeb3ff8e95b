CREATE EXTENSION IF NOT EXISTS unaccent SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.f_unaccent(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
STRICT
SET search_path = public, extensions
AS $$
  SELECT lower(extensions.unaccent('extensions.unaccent'::regdictionary, value));
$$;

-- Search columns depend on f_unaccent(), so they live beside the helper and are
-- installed after the base tables. This keeps a fresh database reproducible
-- without relying on the one-off recovery script.
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS search_terms text;
ALTER TABLE public.places ADD COLUMN IF NOT EXISTS search_terms text;
ALTER TABLE public.information ADD COLUMN IF NOT EXISTS search_terms text;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS search_terms text;
ALTER TABLE public.speakers ADD COLUMN IF NOT EXISTS search_terms text;

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (public.f_unaccent(
    COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' ||
    COALESCE(search_terms, ''))) STORED;
ALTER TABLE public.places ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (public.f_unaccent(
    COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' ||
    COALESCE(search_terms, ''))) STORED;
ALTER TABLE public.information ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (public.f_unaccent(
    COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' ||
    COALESCE(search_terms, ''))) STORED;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (public.f_unaccent(
    COALESCE(message, '') || ' ' || COALESCE(search_terms, ''))) STORED;
ALTER TABLE public.speakers ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (public.f_unaccent(
    COALESCE(title, '') || ' ' || COALESCE(subtitle, '') || ' ' ||
    COALESCE(description, '') || ' ' ||
    COALESCE(search_terms, ''))) STORED;

CREATE INDEX IF NOT EXISTS events_search_doc_trgm_idx
  ON public.events USING gin (search_doc extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS places_search_doc_trgm_idx
  ON public.places USING gin (search_doc extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS information_search_doc_trgm_idx
  ON public.information USING gin (search_doc extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS news_search_doc_trgm_idx
  ON public.news USING gin (search_doc extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS speakers_search_doc_trgm_idx
  ON public.speakers USING gin (search_doc extensions.gin_trgm_ops);
