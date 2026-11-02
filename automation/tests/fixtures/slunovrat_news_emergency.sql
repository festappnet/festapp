BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM festapp_test_support.disposable_environment
    WHERE singleton AND project LIKE 'festapp-%') THEN
    RAISE EXCEPTION 'Disposable local test database required';
  END IF;
END $$;
-- ASSERTION_HELPERS
-- Block all external delivery even if a future regression adds a sender.
UPDATE public.notification_runtime SET endpoint=NULL;
SELECT create_user_for_test('slunovrat-emergency-editor','slunovrat-emergency-editor@example.invalid');
SELECT create_user_for_test('slunovrat-emergency-stranger','slunovrat-emergency-stranger@example.invalid');
UPDATE public.user_info SET organization=19 WHERE id IN
  (get_user_id('slunovrat-emergency-editor'),get_user_id('slunovrat-emergency-stranger'));
INSERT INTO public.units(id,title,organization) VALUES(999,'Emergency fixture',19);
INSERT INTO public.occasions(id,title,organization,unit,link,start_time,end_time,is_hidden)
VALUES(1072594,'Winter fixture',19,999,'2025we-copy-5e6268f4',now(),now()+interval '1 day',false);
INSERT INTO public.occasions(id,title,organization,unit,link,start_time,end_time,is_hidden)
VALUES(1072595,'Other fixture',19,999,'emergency-other-fixture',now(),now()+interval '1 day',false);
INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view)
VALUES(1072594,get_user_id('slunovrat-emergency-editor'),true,true);
INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view)
VALUES(1072595,get_user_id('slunovrat-emergency-editor'),true,true);
SELECT set_config('request.jwt.claim.sub',get_user_id('slunovrat-emergency-editor')::text,true);
SET LOCAL ROLE authenticated;
-- Exact old native operation: three supplied columns and RETURNING (*).
DO $$ BEGIN
  BEGIN
    INSERT INTO public.news(occasion,message,created_by)
    VALUES(1072594,'Before bridge',auth.uid()) RETURNING id;
    RAISE EXCEPTION 'Expected the old native insert to be denied';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
SELECT statement_timestamp()+interval '2 seconds' AS expires_at \gset
-- EMERGENCY_POLICY
SET LOCAL ROLE authenticated;
DO $$ DECLARE saved public.news; BEGIN
  INSERT INTO public.news(occasion,message,created_by)
  VALUES(1072594,'Moc se omlouváme, koncert The Klezmatics byl zrušen.',auth.uid())
  RETURNING * INTO saved;
  ASSERT saved.message='Moc se omlouváme, koncert The Klezmatics byl zrušen.';
  ASSERT (SELECT count(*) FROM public.news WHERE id=saved.id)=1;
  BEGIN
    INSERT INTO public.news(id,occasion,message,created_by) VALUES(2147483600,1072594,'Forged id',auth.uid());
    RAISE EXCEPTION 'Explicit news id accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.news(occasion,message,created_by)
    VALUES(1072594,'Spoofed author','00000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'Spoofed author accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.news(occasion,message,created_by) VALUES(1072595,'Other event',auth.uid());
    RAISE EXCEPTION 'Other event accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.log_notifications(occasion,organization,heading,content)
    VALUES(1072594,19,'Must never send','Fixture');
    RAISE EXCEPTION 'Legacy notification write accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',get_user_id('slunovrat-emergency-stranger')::text,true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    INSERT INTO public.news(occasion,message,created_by) VALUES(1072594,'Stranger',auth.uid());
    RAISE EXCEPTION 'Non-editor accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_sleep(2.1);
SELECT set_config('request.jwt.claim.sub',get_user_id('slunovrat-emergency-editor')::text,true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    INSERT INTO public.news(occasion,message,created_by) VALUES(1072594,'Expired grant',auth.uid());
    RAISE EXCEPTION 'Expired emergency insert accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
-- REMOVE_EMERGENCY_POLICY
DO $$ BEGIN
  ASSERT NOT has_column_privilege('authenticated','public.news','message','INSERT');
  ASSERT NOT has_table_privilege('authenticated','public.log_notifications','INSERT');
  ASSERT NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.news'::regclass
    AND polname='slunovrat_news_emergency_20261102');
END $$;
ROLLBACK;
