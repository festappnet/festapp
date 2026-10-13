-- Apply as the verified extensions schema owner (supabase_admin on canonical
-- runtime). postgres is not the owner there: its GRANT only emits a warning.
GRANT USAGE ON SCHEMA extensions TO authenticated;
DO $verify$
BEGIN
  IF NOT has_schema_privilege('authenticated','extensions','USAGE') THEN
    RAISE EXCEPTION 'news_search_schema_grant_failed: apply as verified extensions schema owner';
  END IF;
END;
$verify$;
NOTIFY pgrst, 'reload schema';
