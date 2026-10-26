-- Deployed Slunovrat REST clients move last-read markers before deleting news.
-- Restore this operation only for Slunovrat editors; notification tables and
-- other tenants' direct mutation permissions remain untouched.
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=19 AND title='Slunovrat')
    OR EXISTS (SELECT 1 FROM pg_class WHERE oid IN
      ('public.news'::regclass,'public.user_news'::regclass) AND NOT relrowsecurity)
    OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.news'::regclass
      AND polname='Enable delete for editors' AND polcmd='d') THEN
    RAISE EXCEPTION 'Expected Slunovrat news deletion security boundary missing';
  END IF;
END;
$guard$;
CREATE POLICY slunovrat_news_delete_scope ON public.news
AS RESTRICTIVE FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=news.occasion AND o.organization=19)
);

CREATE POLICY slunovrat_news_marker_insert ON public.user_news
AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (
  public.get_is_editor_on_occasion(occasion)
  AND EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=user_news.occasion AND o.organization=19)
  AND EXISTS (SELECT 1 FROM public.news n WHERE n.id=user_news.news_id AND n.occasion=user_news.occasion)
);
CREATE POLICY slunovrat_news_marker_update ON public.user_news
AS RESTRICTIVE FOR UPDATE TO authenticated USING (
  public.get_is_editor_on_occasion(occasion)
  AND EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=user_news.occasion AND o.organization=19)
) WITH CHECK (
  public.get_is_editor_on_occasion(occasion)
  AND EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=user_news.occasion AND o.organization=19)
  AND EXISTS (SELECT 1 FROM public.news n WHERE n.id=user_news.news_id AND n.occasion=user_news.occasion)
);
CREATE POLICY slunovrat_news_marker_delete ON public.user_news
AS RESTRICTIVE FOR DELETE TO authenticated USING (
  public.get_is_editor_on_occasion(occasion)
  AND EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=user_news.occasion AND o.organization=19)
);

GRANT DELETE ON public.news TO authenticated;
GRANT INSERT (news_id,"user",occasion), UPDATE (news_id,"user",occasion)
  ON public.user_news TO authenticated;
GRANT DELETE ON public.user_news TO authenticated;
NOTIFY pgrst, 'reload schema';
