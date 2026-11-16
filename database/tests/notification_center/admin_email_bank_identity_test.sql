-- test-setup: database/tests/helpers/admin_email_fixture.sql
BEGIN;
DO $$
DECLARE fixture jsonb; u uuid; org bigint; other_org bigint; unit1 bigint; unit2 bigint; account bigint; conn bigint; incident uuid:=gen_random_uuid(); first_event uuid; first_dispatch uuid; bank_message uuid;
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
 PERFORM public.notification_center_bank_incident_internal(conn);PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 SELECT id INTO first_dispatch FROM public.notification_center_email_dispatches WHERE recipient=u AND state='collecting';
 PERFORM assert_not_null(first_dispatch,'first domain projection opens a digest');
 UPDATE public.notification_center_email_dispatches SET opened_at=opened_at-interval '301 seconds',due_at=due_at-interval '301 seconds' WHERE id=first_dispatch;
 PERFORM public.enqueue_notification_center_emails(100);
 SELECT message_id INTO bank_message FROM public.notification_center_email_dispatches WHERE id=first_dispatch;
 UPDATE public.email_messages SET workflow_state='accepted' WHERE message_id=bank_message;
 -- A second tenant projection is produced only after the first digest finished.
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(unit2,account);
 PERFORM public.notification_center_bank_incident_internal(conn);PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_items WHERE recipient=u AND delivery_key='bank:'||conn||':incident:'||incident),1::bigint,'one recipient item across tenants and windows');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_item_sources WHERE recipient=u AND delivery_key='bank:'||conn||':incident:'||incident),2::bigint,'both tenant source identities remain auditable');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_dispatches WHERE recipient=u AND state='collecting'),0::bigint,'late source does not reopen a terminal item');
 -- Retention/source deletion must not erase the shared incident identity.
 DELETE FROM public.notification_center_events WHERE organization=org AND kind='bank_problem';
 PERFORM public.notification_center_bank_incident_internal(conn);PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_items WHERE recipient=u AND delivery_key='bank:'||conn||':incident:'||incident),1::bigint,'deleting original source cannot bypass dedup');
 DELETE FROM public.notification_center_events WHERE kind='bank_problem' AND data->>'bankConnectionId'=conn::text;
 UPDATE public.notification_center_email_items SET admitted_at=now()-interval '91 days' WHERE recipient=u AND delivery_key='bank:'||conn||':incident:'||incident;
 UPDATE public.notification_center_email_profiles SET collected_at=now()-interval '2 days' WHERE recipient=u;
 PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_items WHERE recipient=u AND delivery_key='bank:'||conn||':incident:'||incident),1::bigint,'active domain incident survives journal retention even with no tenant source');
 PERFORM public.notification_center_bank_incident_internal(conn);PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_eq(public.enqueue_notification_center_emails(100),0,'no replacement notification after late/recreated source');
END $$;
ROLLBACK;
