-- App's two deletion branches: move read markers, or remove markers if last news.
CREATE TABLE public.user_news(news_id bigint REFERENCES public.news(id),
 "user" uuid,occasion bigint REFERENCES public.occasions(id),PRIMARY KEY("user",occasion));
ALTER TABLE public.user_news ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Enable all for editors" ON public.user_news FOR ALL
 USING(public.get_is_editor_on_occasion(occasion)) WITH CHECK(public.get_is_editor_on_occasion(occasion));
CREATE POLICY own_marker ON public.user_news FOR ALL USING(auth.uid()="user") WITH CHECK(auth.uid()="user");
CREATE POLICY marker_read ON public.user_news FOR SELECT USING(true);
CREATE POLICY "Enable delete for editors" ON public.news FOR DELETE USING(public.get_is_editor_on_occasion(occasion));
GRANT SELECT ON public.user_news TO authenticated;
\ir ../../../supabase/migrations/20261013103000_slunovrat_news_delete.sql
INSERT INTO public.news(id,occasion,message,created_by) VALUES
 (901,101,'Older','00000000-0000-0000-0000-000000000001'),
 (902,101,'Newer','00000000-0000-0000-0000-000000000001'),
 (903,102,'Other tenant','00000000-0000-0000-0000-000000000001');
INSERT INTO public.user_news VALUES(902,'00000000-0000-0000-0000-000000000002',101),
 (903,'00000000-0000-0000-0000-000000000002',102);
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
INSERT INTO public.user_news(news_id,"user",occasion)
VALUES(901,'00000000-0000-0000-0000-000000000002',101)
ON CONFLICT("user",occasion) DO UPDATE SET news_id=excluded.news_id;
DELETE FROM public.news WHERE id=902;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.news WHERE id=902)
    OR NOT EXISTS(SELECT 1 FROM public.user_news WHERE occasion=101 AND news_id=901) THEN
  RAISE EXCEPTION 'move marker then delete failed';
 END IF;
 BEGIN
  UPDATE public.user_news SET news_id=903 WHERE occasion=101;
  RAISE EXCEPTION 'cross occasion marker accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
DELETE FROM public.user_news WHERE news_id=901;
DELETE FROM public.news WHERE id=901;
DELETE FROM public.news WHERE id=903;
DELETE FROM public.user_news WHERE occasion=102;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.news WHERE id IN(901,902))
 OR EXISTS(SELECT 1 FROM public.user_news WHERE occasion=101)
 OR NOT EXISTS(SELECT 1 FROM public.news WHERE id=903)
 OR NOT EXISTS(SELECT 1 FROM public.user_news WHERE occasion=102) THEN
  RAISE EXCEPTION 'last news or cross tenant deletion boundary failed';
 END IF;
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
DELETE FROM public.news WHERE id=902;
DELETE FROM public.user_news WHERE occasion=101;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.news WHERE id=902)
 OR NOT EXISTS(SELECT 1 FROM public.user_news WHERE occasion=101) THEN
  RAISE EXCEPTION 'non-editor deletion accepted';
 END IF;
END $$;
ROLLBACK;
