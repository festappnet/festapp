DO $$
DECLARE actor uuid; stranger uuid; org bigint; un bigint; occ bigint; message_id uuid; legacy uuid; cmd uuid:=gen_random_uuid(); response jsonb; n bigint;
BEGIN
 -- pg_net requests become visible to its worker only on commit. The test
 -- runner rolls back this entire fixture, so no external request can execute.
 PERFORM vault.create_secret(repeat('x',40),'festapp_notify_webhook_token_v1');
 UPDATE public.notification_runtime SET endpoint='https://notification-fixture.invalid/functions/v1/notify';
 PERFORM create_user_for_test('push-abuse','push-abuse@example.invalid');actor:=get_user_id('push-abuse');
 PERFORM create_user_for_test('push-stranger','push-stranger@example.invalid');stranger:=get_user_id('push-stranger');
 INSERT INTO public.organizations(title) VALUES('Push fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Push Unit',org) RETURNING id INTO un;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) VALUES(un,actor,true,true,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_hidden)
 VALUES('Push fixture',org,un,gen_random_uuid()::text,now(),now()+interval '1 day',false) RETURNING id INTO occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view) VALUES(occ,actor,true,true);
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='push.calls.unit.day';
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 message_id:=public.enqueue_notification_v1(occ,'Heading','Canonical body',jsonb_build_array(actor));
 BEGIN
  INSERT INTO public.log_notifications(occasion,organization,heading,content) VALUES(occ,org,'Legacy','Denied');
  RAISE EXCEPTION 'legacy REST notification writer still reachable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO public.log_notifications(occasion,organization,content,abuse_admitted_at) VALUES(occ,org,'Forged',now());
  RAISE EXCEPTION 'legacy client forged an admission receipt';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 UPDATE public.abuse_policy_rules SET base_limit=10 WHERE rule_key='push.calls.unit.day';
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM public.enqueue_notification_v1(occ,'Second admitted','Second body');
 BEGIN PERFORM public.enqueue_notification_v1(occ,'Foreign','Rejected',jsonb_build_array(stranger)); RAISE EXCEPTION 'foreign push recipient accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 response:=public.publish_news_client_sync_v1(occ,true,'News body',true,'News heading','News notification',NULL,cmd);
 PERFORM public.publish_news_client_sync_v1(occ,true,'News body',true,'News heading','News notification',NULL,cmd);
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.news_notification_outbox WHERE command_id=cmd),1::bigint,'news notification remains in the existing publication outbox once');
 PERFORM assert_true((SELECT abuse_admitted_at IS NOT NULL FROM public.news_notification_outbox WHERE command_id=cmd),'publication delay retains prior admission');
 PERFORM assert_eq((SELECT count(*) FROM public.log_notifications WHERE occasion=occ),2::bigint,'news does not notify before public publication');
 PERFORM assert_eq((SELECT count(*) FROM net.http_request_queue WHERE url='https://notification-fixture.invalid/functions/v1/notify'),2::bigint,'two explicit RPCs wake delivery without a trigger; pending news and replay do not');
 PERFORM assert_true(EXISTS(SELECT 1 FROM net.http_request_queue WHERE url='https://notification-fixture.invalid/functions/v1/notify'
  AND convert_from(body,'utf8')::jsonb#>>'{record,id}'=message_id::text),'explicit dispatch references the canonical stored intent');
 SELECT sum(amount) INTO n FROM public.abuse_budget_usage WHERE rule_key='push.calls.unit.day' AND scope_id=un::text;
 PERFORM assert_eq(n,3::bigint,'both explicit RPC calls and publication each charge exactly once');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.admit_notification_delivery_v1(message_id);
 PERFORM public.admit_notification_delivery_v1(message_id);
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='push.calls.unit.day' AND scope_id=un::text),3::numeric,'provider retry cannot charge another intent');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='push.dispatch.unit.burst' AND scope_id=un::text),2::numeric,'provider retry consumes bounded dispatch work');
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='push.dispatch.unit.burst';
 PERFORM assert_false((public.admit_notification_delivery_v1(message_id)->>'allowed')::boolean,'dispatch denial is a committed boolean result');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='push.dispatch.unit.burst' AND scope_id=un::text),3::numeric,'denied provider attempt remains counted');
END $$;
