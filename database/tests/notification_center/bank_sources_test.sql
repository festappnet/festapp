-- test-setup: database/tests/helpers/prepared_notification_view.sql
BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; account bigint; conn bigint; editor uuid:=gen_random_uuid(); admin uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 item jsonb; incident uuid; first_event uuid; rev bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Bankovní pořadatel') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Spolek',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Ples',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(editor),(admin),(outsider);
 INSERT INTO public.user_info(id,organization) VALUES(editor,org),(admin,org),(outsider,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,editor,true);
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Bankovní účet','FIO') RETURNING id INTO account;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,account);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(account,admin,true),(account,editor,true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,admin,true);
 INSERT INTO public.forms(occasion,bank_account,link) VALUES(oc,account,gen_random_uuid()::text);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,provider,mode,state,manifest_sha256,bank_pull_at)
 VALUES(gen_random_uuid()::text,'festapp','123',account,gen_random_uuid()::text,'FIO','api','connected',repeat('a',64),now()) RETURNING id INTO conn;
 PERFORM public.initialize_notification_center_internal(org);
 UPDATE public.notification_center_organizations SET initialized_at=now()-interval '1 day',collection_started_at=now()-interval '1 day' WHERE organization=org;
 PERFORM public.record_bank_sync_health(org,conn,NULL,'bank_sync_retry_required',true,true,true,public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_eq((SELECT count(*)::int FROM public.notification_center_events WHERE organization=org AND kind='bank_problem'),0,'domain grace stays silent');
 UPDATE eshop.bank_sync_health SET warning_since=now()-interval '61 minutes' WHERE connection_id=conn;
 SELECT incident_id INTO incident FROM eshop.bank_sync_health WHERE connection_id=conn;
 PERFORM public.notification_center_bank_incident_internal(conn);
 SELECT id,attention_revision INTO first_event,rev FROM public.notification_center_events WHERE organization=org AND kind='bank_problem';
 PERFORM assert_not_null(first_event,'ready domain incident is projected');
 PERFORM assert_true((SELECT data->>'incidentId'=incident::text FROM public.notification_center_events WHERE id=first_event),'center uses domain UUID');
 PERFORM public.notification_center_bank_incident_internal(conn);
 PERFORM assert_eq((SELECT count(*)::int FROM public.notification_center_events WHERE organization=org AND kind='bank_problem'),1,'projection replay does not open another episode');
 PERFORM public.project_notification_center(500);
 PERFORM assert_eq((SELECT count(*)::int FROM public.notification_center_deliveries WHERE organization=org AND recipient=editor),1,'order reader gets safe event context');
 PERFORM assert_eq((SELECT count(*)::int FROM public.notification_center_deliveries WHERE organization=org AND recipient=admin),1,'dual-role bank admin captured');
 PERFORM assert_eq((SELECT count(*)::int FROM public.notification_center_recipients WHERE event_id=first_event AND recipient=outsider),0,'unrelated identity excluded');
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 item:=pg_temp.prepared_notification_view(org)#>'{items,0}';
 PERFORM assert_false((item->'data') ? 'bankAccountId','order reader cannot open bank settings');
 PERFORM assert_false((item->'data') ? 'bankConnectionId','mapping remains private');
 PERFORM assert_eq(jsonb_array_length(item#>'{data,affectedOccasions}'),1,'affected context remains authorized');
 PERFORM set_config('request.jwt.claim.sub',admin::text,true);
 item:=pg_temp.prepared_notification_view(org)#>'{items,0}';
 PERFORM assert_eq((item#>>'{data,bankAccountId}')::bigint,account,'dual-role admin gets bank detail');
 -- Retry symptoms refine one domain episode without another attention event.
 UPDATE eshop.bank_sync_connections SET failure_since=now()-interval '61 minutes' WHERE id=conn;
 PERFORM public.record_bank_sync_health(org,conn,NULL,'bank_sync_unavailable',NULL,NULL,NULL,public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_true((SELECT incident_id=incident FROM eshop.bank_sync_health WHERE connection_id=conn),'ordinary reason changes preserve domain episode');
 PERFORM assert_eq((SELECT attention_revision FROM public.notification_center_events WHERE id=first_event),rev,'no duplicate attention for reason change');
 PERFORM public.record_bank_sync_pull(conn,now(),NULL,public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE id=first_event),'recovered','successful domain pull recovers center');
 PERFORM assert_false(public.notification_center_bank_episode_current((SELECT e FROM public.notification_center_events e WHERE id=first_event)),'old episode cannot reappear');
 PERFORM assert_true(to_regprocedure('public.claim_notification_center_bank_health(integer)') IS NULL,'second poller RPC removed');
 PERFORM assert_true(to_regclass('public.notification_center_bank_health') IS NULL,'second health ledger removed');
END $$;
ROLLBACK;
