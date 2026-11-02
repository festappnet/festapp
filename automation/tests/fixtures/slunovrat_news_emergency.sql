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
UPDATE public.abuse_policy_rules SET base_limit=3 WHERE rule_key='push.calls.unit.day';
SELECT create_user_for_test('slunovrat-emergency-editor','slunovrat-emergency-editor@example.invalid');
SELECT create_user_for_test('slunovrat-emergency-stranger','slunovrat-emergency-stranger@example.invalid');
UPDATE public.user_info SET organization=19 WHERE id IN
  (get_user_id('slunovrat-emergency-editor'),get_user_id('slunovrat-emergency-stranger'));
INSERT INTO public.units(id,title,organization) VALUES(999,'Emergency fixture',19);
INSERT INTO public.occasions(id,title,organization,unit,link,start_time,end_time,is_hidden)
VALUES(1072594,'Winter fixture',19,999,'2025we-copy-5e6268f4',now(),now()+interval '1 day',false);
UPDATE public.occasions SET data='{"client_sync_v1":true}' WHERE id=1072594;
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
SELECT statement_timestamp()+interval '3 seconds' AS expires_at \gset
-- EMERGENCY_POLICY
SELECT :'expires_at' AS previous_expires_at \gset
SELECT statement_timestamp()+interval '5 seconds' AS expires_at \gset
-- EXTEND_EMERGENCY_POLICY
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
    VALUES(1072595,19,'Must never send','Fixture');
    RAISE EXCEPTION 'Other event notification accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.log_notifications(occasion,organization,heading,content)
    VALUES(1072594,NULL,'Must never send','Fixture');
    RAISE EXCEPTION 'Null organization notification accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.log_notifications(occasion,organization,"to",heading,content)
    VALUES(1072594,19,'["00000000-0000-0000-0000-000000000001"]','Foreign recipient','Fixture');
    RAISE EXCEPTION 'Foreign recipient accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO public.log_notifications(occasion,organization,heading,content)
  VALUES(1072594,19,'Změna programu','Koncert byl zrušen.');
END $$;
RESET ROLE;
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM public.news_notification_outbox WHERE occasion=1072594)=1;
  ASSERT NOT EXISTS (SELECT 1 FROM public.log_notifications WHERE occasion=1072594);
  ASSERT (SELECT required_content_revision FROM public.news_notification_outbox WHERE occasion=1072594)=
    (SELECT source_revision FROM public.client_sync_scopes WHERE component='content_catalog'
      AND scope_type='occasion' AND scope_id=1072594);
  ASSERT (SELECT abuse_admitted_at IS NOT NULL FROM public.news_notification_outbox WHERE occasion=1072594);
END $$;
-- The actual Slunovrat occasion uses direct readers, without an R2 publisher.
UPDATE public.occasions SET data='{"client_sync_v1":false}' WHERE id=1072594;
SET LOCAL ROLE authenticated;
INSERT INTO public.log_notifications(occasion,organization,"to",heading,content)
VALUES(1072594,19,jsonb_build_array(auth.uid()),'Legacy direct reader','No external delivery.');
RESET ROLE;
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM public.log_notifications WHERE occasion=1072594)=1;
  ASSERT (SELECT count(*) FROM public.news_notification_outbox WHERE occasion=1072594)=1;
END $$;
-- Sync-enabled readers still wait until their content is published.
UPDATE public.occasions SET data='{"client_sync_v1":true}' WHERE id=1072594;
INSERT INTO public.client_sync_publications(component,scope_type,scope_id,published_revision,
  media_type,artifact_url,sha256,byte_size)
SELECT component,scope_type,scope_id,source_revision,'application/json',
  'https://fixture.invalid/catalog',repeat('0',64),1 FROM public.client_sync_scopes
WHERE component='content_catalog' AND scope_type='occasion' AND scope_id=1072594;
SET LOCAL ROLE authenticated;
INSERT INTO public.log_notifications(occasion,organization,"to",heading,content)
VALUES(1072594,19,jsonb_build_array(auth.uid()),'Synthetic self only','No external delivery.');
DO $$ BEGIN
  BEGIN
    INSERT INTO public.log_notifications(occasion,organization,heading,content)
    VALUES(1072594,19,'Over budget','No external delivery.');
    RAISE EXCEPTION 'Notification budget bypassed';
  EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM public.log_notifications WHERE occasion=1072594)=2;
  ASSERT NOT EXISTS (SELECT 1 FROM net.http_request_queue);
  ASSERT (SELECT sum(amount) FROM public.abuse_budget_usage
    WHERE rule_key='push.calls.unit.day' AND scope_id='999')=3;
END $$;
-- A modern command still owns exactly one aggregate version and publication.
SET LOCAL ROLE authenticated;
SELECT public.publish_news_client_sync_v1(1072594,true,'Modern news',false,NULL,NULL,NULL,gen_random_uuid());
RESET ROLE;
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM public.news WHERE occasion=1072594)=2;
  ASSERT (SELECT source_revision FROM public.client_sync_scopes
    WHERE component='content_catalog' AND scope_type='occasion' AND scope_id=1072594)=2;
END $$;
SELECT set_config('request.jwt.claim.sub',get_user_id('slunovrat-emergency-stranger')::text,true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    INSERT INTO public.news(occasion,message,created_by) VALUES(1072594,'Stranger',auth.uid());
    RAISE EXCEPTION 'Non-editor accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.log_notifications(occasion,organization,heading,content)
    VALUES(1072594,19,'Stranger','No external delivery.');
    RAISE EXCEPTION 'Non-editor notification accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_sleep(3.1);
SELECT set_config('request.jwt.claim.sub',get_user_id('slunovrat-emergency-editor')::text,true);
SET LOCAL ROLE authenticated;
-- Original deadline has passed, but both the policy and news trigger use the extension.
INSERT INTO public.news(occasion,message,created_by) VALUES(1072594,'Extended deadline',auth.uid());
RESET ROLE;
-- The push trigger also reaches normal admission instead of the old expiry.
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    INSERT INTO public.log_notifications(occasion,organization,heading,content)
    VALUES(1072594,19,'Extended push deadline','No external delivery.');
    RAISE EXCEPTION 'Notification budget bypassed';
  EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_sleep(2.1);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    INSERT INTO public.news(occasion,message,created_by) VALUES(1072594,'Expired grant',auth.uid());
    RAISE EXCEPTION 'Expired emergency insert accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.log_notifications(occasion,organization,heading,content)
    VALUES(1072594,19,'Expired notification','No external delivery.');
    RAISE EXCEPTION 'Expired notification accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
-- REMOVE_EMERGENCY_POLICY
DO $$ BEGIN
  ASSERT NOT has_column_privilege('authenticated','public.news','message','INSERT');
  ASSERT NOT has_table_privilege('authenticated','public.log_notifications','INSERT');
  ASSERT NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.news'::regclass
    AND polname='slunovrat_news_emergency_20261102');
  ASSERT NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname IN
    ('slunovrat_legacy_news_emergency_20261102','slunovrat_legacy_push_emergency_20261102'));
END $$;
ROLLBACK;
