-- test-setup: database/tests/helpers/admin_email_fixture.sql
BEGIN;
DO $$
DECLARE fixture jsonb; u uuid; org bigint; other_org bigint; unit1 bigint; unit2 bigint; account bigint; conn bigint; incident uuid:=gen_random_uuid(); first_event uuid; first_dispatch uuid; bank_message uuid; snapshot jsonb; claim jsonb; outcome jsonb; revision bigint; reader uuid:=gen_random_uuid();
BEGIN
 fixture:=pg_temp.admin_email_fixture();u:=(fixture->>'user')::uuid;org:=(fixture->>'organization')::bigint;other_org:=(fixture->>'otherOrganization')::bigint;
 UPDATE public.email_messages SET workflow_state='accepted' WHERE message_id=(fixture->>'message')::uuid;
 UPDATE public.notification_center_email_subscriptions SET enabled_from=now()-interval '3 days',kinds=jsonb_set(kinds,'{bank_problem,enabledFrom}',to_jsonb((now()-interval '3 days')::text)) WHERE recipient=u;
 UPDATE public.notification_center_organizations SET initialized_at=now()-interval '3 days',email_collection_started_at=now()-interval '3 days' WHERE organization IN(org,other_org);
 INSERT INTO public.units(organization,title) VALUES(org,'Spolek A') RETURNING id INTO unit1;
 INSERT INTO public.units(organization,title) VALUES(other_org,'Spolek B') RETURNING id INTO unit2;
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Sdílený účet','FIO') RETURNING id INTO account;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(unit1,account);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(account,u,true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(unit1,u,true),(unit2,u,true);
 INSERT INTO public.forms(occasion,title,bank_account) SELECT id,'Přihláška',account FROM public.occasions WHERE organization IN(org,other_org);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,provider,mode,state,manifest_sha256,last_error,bank_pull_at)
 VALUES(gen_random_uuid()::text,'festapp','14141',account,gen_random_uuid()::text,'FIO','api','degraded',repeat('a',64),'bank_sync_retry_required',now()) RETURNING id INTO conn;
 INSERT INTO eshop.bank_sync_health(connection_id,warning_code,warning_since,incident_id,checked_at) VALUES(conn,'bank_error',now()-interval '25 hours',incident,now());
 INSERT INTO auth.users(id) VALUES(reader);
 INSERT INTO public.user_info(id,organization,email_delivery) VALUES(reader,org,'reader@example.test');
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) SELECT id,reader,true FROM public.occasions WHERE organization=org;
 -- A user who never opted into email still receives a captured required alert.
 DELETE FROM public.notification_center_email_subscriptions WHERE recipient=u;
 DELETE FROM public.notification_center_email_profiles WHERE recipient=u;
 INSERT INTO public.notification_center_preferences(organization,recipient,occasion,muted)
 SELECT organization,u,id,true FROM public.occasions WHERE organization IN(org,other_org);
 PERFORM public.notification_center_bank_incident_internal(conn);
 PERFORM public.project_notification_center(500);
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.notification_center_email_profiles WHERE recipient=u),'no opt-in profile before collection');
 PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_true((SELECT stopped FROM public.notification_center_email_profiles WHERE recipient=u),'required enrollment leaves optional mail stopped');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_subscriptions WHERE recipient=u),0::bigint,'required enrollment creates no subscription');
 SELECT id INTO first_dispatch FROM public.notification_center_email_dispatches WHERE recipient=u AND state='collecting';
 snapshot:=public.notification_center_email_context_internal(first_dispatch,u);
 PERFORM assert_eq(jsonb_array_length(snapshot->'items'),1,'bank alert survives missing preferences, global stop and event mute');
 PERFORM assert_eq(snapshot->'items'->0->>'kind','bank_problem','only required kind included');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_items WHERE recipient=reader),0::bigint,'order reader without bank account administration receives no bank email');
 PERFORM assert_true(NOT (public.notification_center_email_catalog_internal(ARRAY['orders:1','bank-occasion:1'],NULL) ? 'bank_problem'),'order-reader catalog has no bank email preference');
 PERFORM assert_true(public.notification_center_email_settings_internal(org)->'requiredKinds' ? 'bank_problem','settings expose required policy');
 -- A forged toggle is rejected atomically, including attempts to enable it.
 FOREACH revision IN ARRAY ARRAY[0,1]::bigint[] LOOP
  BEGIN
   PERFORM public.save_notification_center_email_settings(org,NULL,0,false,'cs',jsonb_build_object('bank_problem',revision=1));
   RAISE EXCEPTION 'expected required-kind rejection';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'notification_email_kind_required' THEN RAISE; END IF;
  END;
 END LOOP;
 -- Prepare a mixed digest, then stop optional mail before the provider permit.
 UPDATE public.notification_center_preferences SET muted=false WHERE recipient=u;
 PERFORM public.save_notification_center_email_settings(org,NULL,0,false,'cs','{"order_created":true}');
 PERFORM public.notification_center_publish_internal(org,(SELECT min(id) FROM public.occasions WHERE organization=org),'order_created','mandatory-mixed','{"count":1}');
 PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 snapshot:=public.notification_center_email_context_internal(first_dispatch,u);
 PERFORM assert_eq(jsonb_array_length(snapshot->'items'),2,'optional and required content share one digest');
 UPDATE public.notification_center_email_dispatches SET opened_at=opened_at-interval '301 seconds',due_at=due_at-interval '301 seconds' WHERE id=first_dispatch;
 PERFORM public.enqueue_notification_center_emails(100);
 SELECT message_id INTO bank_message FROM public.notification_center_email_dispatches WHERE id=first_dispatch;
 UPDATE public.email_messages SET target_time='infinity' WHERE message_id<>bank_message;
 UPDATE public.email_capacity SET paused=false,quota_at=now(),shared_account=false,max_rate=100,daily_quota=100000,provider_sent_24h=0,next_send_at='-infinity',circuit_until=NULL,probe_until=NULL;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 claim:=public.claim_email();
 PERFORM public.prepare_email(bank_message,(claim->>'lease_token')::uuid,'{"sealed":"mixed"}',jsonb_build_object('notification_fingerprint',snapshot->>'fingerprint'));
 PERFORM public.save_notification_center_email_settings(org,NULL,1,true,'cs','{"order_created":false}');
 outcome:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(outcome->>'disposition','deferred','stop invalidates mixed snapshot without cancelling required mail');
 snapshot:=public.notification_center_email_context_internal(first_dispatch,u);
 PERFORM assert_eq(jsonb_array_length(snapshot->'items'),1,'optional stop removes optional content only');
 -- Current permissions still apply to mandatory alerts.
 DELETE FROM eshop.bank_account_users WHERE "user"=u;
 PERFORM assert_eq(jsonb_array_length(public.notification_center_email_context_internal(first_dispatch,u)->'items'),0,'required policy cannot bypass current permissions');
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(account,u,true);
 snapshot:=public.notification_center_email_context_internal(first_dispatch,u);
 claim:=public.claim_email();
 PERFORM public.prepare_email(bank_message,(claim->>'lease_token')::uuid,'{"sealed":"required-only"}',jsonb_build_object('notification_fingerprint',snapshot->>'fingerprint'));
 outcome:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(outcome->>'disposition','send','required-only digest uses the existing provider permit');
 PERFORM public.finish_email_attempt((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid,'accepted','required-provider-id');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE recipient_user=u AND message_id=bank_message),1::bigint,'repreparation retains one queue intent');
END $$;
ROLLBACK;
