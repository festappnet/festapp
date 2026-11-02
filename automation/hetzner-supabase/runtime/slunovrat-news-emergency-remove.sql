-- Remove only the explicit emergency bridge; canonical RPCs stay unchanged.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.news'::regclass
    AND polname='slunovrat_news_emergency_20261102') THEN
    RAISE EXCEPTION 'Emergency bridge absent; inspect current ACLs before removal';
  END IF;
END $$;
REVOKE INSERT (occasion,message,created_by) ON public.news FROM authenticated;
REVOKE INSERT (occasion,organization,"to",heading,content,data) ON public.log_notifications FROM authenticated;
DROP TRIGGER slunovrat_legacy_news_emergency_20261102 ON public.news;
DROP TRIGGER slunovrat_legacy_push_emergency_20261102 ON public.log_notifications;
DROP FUNCTION public.slunovrat_legacy_news_emergency_20261102();
DROP FUNCTION public.slunovrat_legacy_push_emergency_20261102();
DROP POLICY slunovrat_news_emergency_20261102 ON public.news;
NOTIFY pgrst, 'reload schema';
