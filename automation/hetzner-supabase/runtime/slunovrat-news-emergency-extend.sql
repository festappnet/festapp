-- Extend the existing scoped exception atomically, without reinstalling its
-- functions or changing grants. Update both cleanup jobs before this file.
-- Required psql variables: previous_expires_at, expires_at.
\set ON_ERROR_STOP on
SELECT :'expires_at'::timestamptz > greatest(statement_timestamp(), :'previous_expires_at'::timestamptz)
   AND EXISTS (SELECT 1 FROM public.occasions WHERE id=1072594 AND organization=19
     AND :'expires_at'::timestamptz <= end_time + interval '5 days')
   AND EXISTS (SELECT 1 FROM public.occasions WHERE id=1072594 AND organization=19
     AND unit=999 AND link='2025we-copy-5e6268f4')
   AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.news'::regclass
     AND polname='slunovrat_news_emergency_20261102' AND NOT polpermissive)
   AND (SELECT count(*)=2 FROM pg_trigger WHERE tgname IN
     ('slunovrat_legacy_news_emergency_20261102','slunovrat_legacy_push_emergency_20261102')
     AND tgargs=convert_to(:'previous_expires_at','UTF8') || decode('00','hex'))
   AS valid_emergency_extension \gset
\if :valid_emergency_extension
\else
DO $$ BEGIN RAISE EXCEPTION 'Emergency bridge identity/deadline mismatch'; END $$;
\endif
ALTER POLICY slunovrat_news_emergency_20261102 ON public.news WITH CHECK (
  occasion=1072594 AND created_by=auth.uid()
  AND public.can_write_news(occasion)
  AND statement_timestamp() < :'expires_at'::timestamptz
);
DROP TRIGGER slunovrat_legacy_news_emergency_20261102 ON public.news;
CREATE TRIGGER slunovrat_legacy_news_emergency_20261102
AFTER INSERT ON public.news FOR EACH ROW
WHEN (current_user='authenticated' AND NEW.occasion=1072594)
EXECUTE FUNCTION public.slunovrat_legacy_news_emergency_20261102(:'expires_at');
DROP TRIGGER slunovrat_legacy_push_emergency_20261102 ON public.log_notifications;
CREATE TRIGGER slunovrat_legacy_push_emergency_20261102
BEFORE INSERT ON public.log_notifications FOR EACH ROW
WHEN (current_user='authenticated')
EXECUTE FUNCTION public.slunovrat_legacy_push_emergency_20261102(:'expires_at');
NOTIFY pgrst, 'reload schema';
