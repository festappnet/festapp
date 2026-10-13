-- Slunovrat's deployed REST client inserts these three news columns directly.
-- Restore only that operation, gated by the existing editor policy and a
-- restrictive tenant/author policy. Other tenants retain the closed DML path.
-- No log_notifications or news_notification_outbox writes occur here.
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations
      WHERE id = 19 AND title = 'Slunovrat') THEN
    RAISE EXCEPTION 'Slunovrat organization identity mismatch';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class
      WHERE oid = 'public.news'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_policy
       WHERE polrelid = 'public.news'::regclass
         AND polname = 'Enable insert for editors' AND polcmd = 'a') THEN
    RAISE EXCEPTION 'Expected news editor RLS boundary missing';
  END IF;
END;
$guard$;

CREATE POLICY slunovrat_news_insert_scope ON public.news
AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (SELECT 1 FROM public.occasions o
    WHERE o.id = news.occasion AND o.organization = 19)
);

GRANT INSERT (occasion, message, created_by) ON public.news TO authenticated;
NOTIFY pgrst, 'reload schema';
