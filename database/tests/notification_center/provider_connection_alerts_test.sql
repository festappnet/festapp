-- test-setup: database/tests/scanning/fixture.sql
-- test-setup: database/tests/helpers/prepared_notification_view.sql
BEGIN;
DO $$
DECLARE fx jsonb; org bigint; un bigint; oc bigint; alert_admin uuid:=gen_random_uuid(); reader uuid:=gen_random_uuid();
 conn uuid; claim jsonb; episode uuid; old_episode uuid; ev uuid; dispatch uuid; message uuid; snapshot jsonb; disconnect uuid;
 status jsonb; barion uuid; attempt uuid; pi bigint; oid bigint; remote text:=replace(gen_random_uuid()::text,'-','');
BEGIN
 fx:=public.scanner_test_fixture(1);oc:=(fx->>'occasion')::bigint;
 SELECT organization,unit INTO org,un FROM public.occasions WHERE id=oc;
 INSERT INTO auth.users(id) VALUES(alert_admin),(reader);
 INSERT INTO public.user_info(id,organization,email_delivery) VALUES(alert_admin,org,'gateway-admin@example.test'),(reader,org,'reader@example.test');
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,alert_admin,true);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,reader,true);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,reader,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '1 day');
 UPDATE public.email_capacity SET quota_at=now(),daily_quota=100000,allocated_daily=100000;
 PERFORM public.activate_notification_center_emails(org);
 INSERT INTO public.notification_center_preferences(organization,recipient,occasion,muted) VALUES(org,alert_admin,oc,true);
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused)
 VALUES(org,un,'acct_notification'||replace(gen_random_uuid()::text,'-',''),false,'connected',false) RETURNING id INTO conn;
 status:=jsonb_build_object('accountId',(SELECT account_id FROM eshop.stripe_connections WHERE id=conn),'modelVerified',true,'chargesEnabled',true,'payoutsEnabled',true,'cardPaymentsActive',true);
 FOR n IN 1..3 LOOP
  claim:=public.claim_stripe_connection_status_internal(status->>'accountId',false);
  PERFORM public.fail_stripe_connection_status_internal(conn,(claim->>'lease')::uuid);
  IF n<3 THEN PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='provider_problem'),0::bigint,'transient transport failures do not alert'); END IF;
 END LOOP;
 SELECT incident_id INTO episode FROM eshop.provider_connection_notification_incidents WHERE connection_id=conn;
 PERFORM assert_not_null(episode,'third real status failure opens one connection episode');
 claim:=public.claim_stripe_connection_status_internal(status->>'accountId',false);
 PERFORM public.commit_stripe_connection_status_internal(conn,(claim->>'lease')::uuid,status||'{"chargesEnabled":false}',NULL);
 PERFORM assert_eq((SELECT incident_id FROM eshop.provider_connection_notification_incidents WHERE connection_id=conn),episode,'reason changes retain the same connection episode');
 PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 SELECT id INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=alert_admin AND state='collecting';
 snapshot:=public.notification_center_email_context_internal(dispatch,alert_admin);
 PERFORM assert_eq(jsonb_array_length(snapshot->'items'),1,'connection admin receives one required alert with optional mail stopped and event muted');
 PERFORM assert_eq(snapshot->'items'->0->>'provider','Stripe','authorized connector presentation is retained');
 PERFORM assert_true(snapshot->'items'->0->'facts'->'count'='null'::jsonb,'connection health never computes ticket counts');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_items WHERE recipient=reader),0::bigint,'organization admin and order reader without unit management receive no gateway alert');
 PERFORM assert_true((SELECT stopped FROM public.notification_center_email_profiles WHERE recipient=alert_admin),'required alerts do not enable optional mail');
 PERFORM set_config('request.jwt.claim.sub',alert_admin::text,true);
 PERFORM assert_eq(pg_temp.prepared_notification_view(org)#>>'{items,0,kind}','provider_problem','the existing prepared center serves the same gateway incident to its admin');
 PERFORM assert_true((SELECT expires_at IS NULL AND places IS NULL FROM public.notification_center_view_members WHERE recipient=alert_admin LIMIT 1),'prepared gateway incident has neither activity expiry nor ticket counts');
 PERFORM assert_true(public.notification_center_email_settings_internal(org)->'requiredKinds' ? 'provider_problem','settings expose mandatory gateway policy');
 BEGIN
  PERFORM public.save_notification_center_email_settings(org,NULL,0,true,'cs','{"provider_problem":false}');RAISE EXCEPTION 'required toggle accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'notification_email_kind_required' THEN RAISE; END IF; END;
 UPDATE public.notification_center_email_dispatches SET opened_at=opened_at-interval '301 seconds',due_at=due_at-interval '301 seconds' WHERE id=dispatch;
 PERFORM public.enqueue_notification_center_emails(100);
 SELECT message_id INTO message FROM public.notification_center_email_dispatches WHERE id=dispatch;
 PERFORM assert_eq((SELECT message_kind FROM public.email_messages WHERE message_id=message),'admin_notification_digest','same existing queue kind transports gateway alerts');
 DELETE FROM public.unit_users WHERE unit=un AND "user"=alert_admin;
 PERFORM assert_eq(jsonb_array_length(public.notification_center_email_context_internal(dispatch,alert_admin)->'items'),0,'revocation removes gateway content before sending');
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,alert_admin,true);
 claim:=public.claim_stripe_connection_status_internal(status->>'accountId',false);
 PERFORM public.commit_stripe_connection_status_internal(conn,(claim->>'lease')::uuid,status,NULL);
 PERFORM assert_eq(jsonb_array_length(public.notification_center_email_context_internal(dispatch,alert_admin)->'items'),0,'recovery removes an unsent alert');
 PERFORM assert_true((SELECT NOT active FROM eshop.provider_connection_notification_incidents WHERE connection_id=conn),'successful authoritative status closes episode');
 -- A new confirmed restriction after recovery is a new episode, never a retry.
 claim:=public.claim_stripe_connection_status_internal(status->>'accountId',false);
 PERFORM public.commit_stripe_connection_status_internal(conn,(claim->>'lease')::uuid,status||'{"chargesEnabled":false}',NULL);
 PERFORM assert_true((SELECT incident_id<>episode FROM eshop.provider_connection_notification_incidents WHERE connection_id=conn),'new failure after recovery gets a new episode');
 -- Active incidents do not expire with ordinary activity or journal cleanup.
 PERFORM public.project_notification_center(500);
 SELECT id INTO ev FROM public.notification_center_events WHERE organization=org AND kind='provider_problem' AND data->>'incidentId'=(SELECT incident_id::text FROM eshop.provider_connection_notification_incidents WHERE connection_id=conn);
 UPDATE public.notification_center_events SET occurred_at=now()-interval '91 days' WHERE id=ev;
 UPDATE public.notification_center_deliveries SET delivered_at=now()-interval '91 days' WHERE event_id=ev;
 PERFORM public.maintain_notification_center(500);
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=ev),'active connection incident survives journal retention');
 INSERT INTO eshop.stripe_disconnect_intents(connection_id,actor,state) VALUES(conn,alert_admin,'claimed') RETURNING id INTO disconnect;
 PERFORM public.finish_stripe_disconnect_internal(disconnect,true);
 PERFORM assert_true((SELECT NOT active FROM eshop.provider_connection_notification_incidents WHERE connection_id=conn),'intentional disconnect closes rather than inventing a failure');
 -- The Barion runtime uses the same episode owner and delivery, not a poller.
 INSERT INTO eshop.barion_connections(organization_id,unit_id,account_id,business_name,enabled)
 VALUES(org,un,replace(gen_random_uuid()::text,'-',''),'Barion',true) RETURNING id INTO barion;
 SELECT o.id INTO oid FROM eshop.orders o JOIN eshop.order_product_ticket x ON x."order"=o.id WHERE x.ticket=(fx#>>'{tickets,0}')::bigint;
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method,barion_connection_id) VALUES(1,'CZK','barion',barion) RETURNING id INTO pi;
 UPDATE eshop.orders SET payment_info=pi,price=1,currency_code='CZK',state='ordered' WHERE id=oid;
 INSERT INTO eshop.barion_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,amount_minor,currency,created_at,reservation_expires_at,return_base_url,remote_id)
 VALUES(oid,pi,org,un,barion,100,'CZK',clock_timestamp()-interval '1 minute',clock_timestamp()+interval '20 minutes','https://tickets.example.test/payments/barion/return',remote) RETURNING id INTO attempt;
 FOR n IN 1..3 LOOP
  claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',attempt,'accountId',(SELECT account_id FROM eshop.barion_connections WHERE id=barion)));
  PERFORM public.barion_runtime_internal('fail',jsonb_build_object('attemptId',attempt,'lease',claim->>'lease'));
 END LOOP;
 PERFORM assert_true((SELECT active FROM eshop.provider_connection_notification_incidents WHERE connection_id=barion),'persisted Barion failures open the shared kind');
 PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_item_sources s JOIN public.notification_center_events e ON e.id=s.event_id WHERE s.recipient=alert_admin AND e.data->>'connectionId'=barion::text),1::bigint,'Barion joins the existing recipient digest once');
 claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',attempt,'accountId',(SELECT account_id FROM eshop.barion_connections WHERE id=barion)));
 PERFORM public.barion_runtime_internal('ingest',jsonb_build_object('attemptId',attempt,'lease',claim->>'lease','facts',jsonb_build_object('checkoutId',remote,'paymentId',remote,'checkoutStatus','open','movements','[]'::jsonb,'disputes','[]'::jsonb)));
 PERFORM assert_true((SELECT NOT active FROM eshop.provider_connection_notification_incidents WHERE connection_id=barion),'verified Barion recovery closes the same episode');
 PERFORM assert_false(has_function_privilege('authenticated','public.notification_center_provider_connection_internal(text,uuid)','EXECUTE'),'client cannot forge provider health');
END $$;
ROLLBACK;
