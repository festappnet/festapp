-- Temporary native-client bridge, explicitly limited to the Winter Edition.
-- Run inside a transaction with psql -v expires_at=<UTC timestamp>.
-- No notification grants, data writes, triggers or delivery calls.
\set ON_ERROR_STOP on
SELECT :'expires_at'::timestamptz > statement_timestamp()
   AND :'expires_at'::timestamptz <= statement_timestamp() + interval '48 hours'
   AS valid_emergency_deadline \gset
\if :valid_emergency_deadline
\else
DO $$ BEGIN RAISE EXCEPTION 'Emergency deadline must be within 48 hours'; END $$;
\endif
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=19 AND title='Slunovrat')
    OR NOT EXISTS (SELECT 1 FROM public.occasions
      WHERE id=1072594 AND organization=19 AND unit=999
        AND link='2025we-copy-5e6268f4')
    OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.news'::regclass)
    OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.news'::regclass
      AND polname='Enable insert for editors' AND polcmd='a') THEN
    RAISE EXCEPTION 'Slunovrat emergency news identity/RLS mismatch';
  END IF;
END $$;
CREATE POLICY slunovrat_news_emergency_20261102 ON public.news
AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (
  occasion=1072594 AND created_by=auth.uid()
  AND public.can_write_news(occasion)
  AND statement_timestamp() < :'expires_at'::timestamptz
);
GRANT INSERT (occasion,message,created_by) ON public.news TO authenticated;
NOTIFY pgrst, 'reload schema';
