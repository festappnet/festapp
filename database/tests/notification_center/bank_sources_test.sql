BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; foreign_org bigint; foreign_oc bigint; account bigint; conn bigint; editor uuid:=gen_random_uuid(); admin uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 claim jsonb; tok uuid; item jsonb; ts timestamptz:=clock_timestamp(); ev uuid; minute integer;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Health tenant') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Health unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Health occasion',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.organizations(title) VALUES('Foreign health tenant') RETURNING id INTO foreign_org;
 INSERT INTO public.occasions(title,organization,link,start_time,end_time) VALUES('Foreign occasion',foreign_org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO foreign_oc;
 INSERT INTO auth.users(id) VALUES(editor),(admin),(outsider);
 INSERT INTO public.user_info(id,organization) VALUES(editor,org),(admin,org),(outsider,foreign_org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,editor,true),(foreign_oc,outsider,true);
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Health bank','FIO') RETURNING id INTO account;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,account);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(account,admin,true),(account,editor,true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,admin,true);
 INSERT INTO public.forms(occasion,bank_account,link) VALUES(oc,account,gen_random_uuid()::text);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,provider,mode,state,manifest_sha256,bank_pull_at)
 VALUES(gen_random_uuid()::text,'festapp','123',account,gen_random_uuid()::text,'FIO','api','connected',repeat('a',64),ts) RETURNING id INTO conn;
 UPDATE eshop.bank_sync_connections SET last_error='fio_token_invalid_or_inactive' WHERE id=conn;
 PERFORM public.initialize_notification_center_internal(org);
 -- A known problem at activation stays silent until a genuine successful pull.
 claim:=public.claim_notification_center_bank_health();SELECT (x->>'token')::uuid INTO tok FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn;
 PERFORM public.complete_notification_center_bank_health(conn,tok,ts,'fio_token_invalid_or_inactive');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='bank_problem'),0::bigint,'existing bank problem baseline is silent');
 UPDATE public.notification_center_bank_health SET next_at='-infinity' WHERE connection_id=conn;
 claim:=public.claim_notification_center_bank_health();SELECT (x->>'token')::uuid INTO tok FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn;
 PERFORM public.complete_notification_center_bank_health(conn,tok,clock_timestamp(),NULL);
 UPDATE public.notification_center_bank_health SET next_at='-infinity' WHERE connection_id=conn;
 ts:=clock_timestamp();

 claim:=public.claim_notification_center_bank_health();SELECT (x->>'token')::uuid INTO tok FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn;
 PERFORM assert_not_null(tok,'service health claims mapped account');
 PERFORM public.complete_notification_center_bank_health(conn,tok,ts,'fio_token_invalid_or_inactive',ts+interval '1 minute');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='bank_problem'),1::bigint,'confirmed token failure immediate');
 PERFORM public.project_notification_center(100);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org AND recipient=editor),1::bigint,'organizer gets safe affected payment impact');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org AND recipient=admin),1::bigint,'account admin receives issue');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_recipients r JOIN public.notification_center_events e ON e.id=r.event_id WHERE e.organization=org AND r.recipient=outsider),0::bigint,'unrelated tenant has no snapshot');
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 item:=public.open_notification_center(org)#>'{groups,0,items,0}';
 PERFORM assert_false((item->'data') ? 'bankAccountId','organizer cannot see bank settings target');
 PERFORM assert_false((item->'data') ? 'bankConnectionId','no internal mapping in DTO');
 PERFORM assert_eq(jsonb_array_length(item#>'{data,affectedOccasions}'),1,'safe exact affected event');
 PERFORM set_config('request.jwt.claim.sub',admin::text,true);
 item:=public.open_notification_center(org)#>'{groups,0,items,0}';
 PERFORM assert_eq((item#>>'{data,bankAccountId}')::bigint,account,'bank admin gets authorized detail target');
 -- Recovery requires a new successful pull; storing a token isn't sufficient.
 UPDATE public.notification_center_bank_health SET next_at='-infinity' WHERE connection_id=conn;
 claim:=public.claim_notification_center_bank_health();SELECT (x->>'token')::uuid INTO tok FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn;
 PERFORM public.complete_notification_center_bank_health(conn,tok,ts+interval '2 minutes',NULL,ts+interval '2 minutes');
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE organization=org AND kind='bank_problem'),'recovered'::text,'successful pull recovers');
 PERFORM assert_eq((SELECT attention_revision FROM public.notification_center_events WHERE organization=org AND kind='bank_problem'),1::bigint,'recovery has no new attention');
 -- Short transport errors do not create token incidents; persistence spans >=15 minutes.
 FOREACH minute IN ARRAY ARRAY[3,8,19] LOOP
  UPDATE public.notification_center_bank_health SET next_at='-infinity' WHERE connection_id=conn;
  claim:=public.claim_notification_center_bank_health();SELECT (x->>'token')::uuid INTO tok FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn;
  PERFORM public.complete_notification_center_bank_health(conn,tok,NULL,'transport_unavailable',ts+make_interval(mins=>minute));
  PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='bank_problem'),
   CASE WHEN minute=19 THEN 2 ELSE 1 END::bigint,'transport tolerance and dedupe');
 END LOOP;
 UPDATE public.notification_center_bank_health SET next_at='-infinity' WHERE connection_id=conn;
 claim:=public.claim_notification_center_bank_health();SELECT (x->>'token')::uuid INTO tok FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn;
 PERFORM public.complete_notification_center_bank_health(conn,tok,NULL,'fio_token_invalid_or_inactive',ts+interval '19 minutes 30 seconds');
 PERFORM assert_eq((SELECT data->>'reason' FROM public.notification_center_events WHERE organization=org AND source_key='bank:'||conn||':episode:2'),'fio_token_invalid_or_inactive'::text,'confirmed token evidence immediately refines existing transport episode');
 PERFORM assert_eq((SELECT attention_revision FROM public.notification_center_events WHERE organization=org AND source_key='bank:'||conn||':episode:2'),1::bigint,'reason refinement does not duplicate the episode');
 UPDATE public.notification_center_bank_health SET next_at='-infinity' WHERE connection_id=conn;
 claim:=public.claim_notification_center_bank_health();SELECT (x->>'token')::uuid INTO tok FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn;
 PERFORM public.complete_notification_center_bank_health(conn,tok,ts+interval '20 minutes',NULL,ts+interval '20 minutes');
 -- A missing fresh pull is independently unhealthy even with no provider error.
 FOREACH minute IN ARRAY ARRAY[120,136] LOOP
  UPDATE public.notification_center_bank_health SET next_at='-infinity' WHERE connection_id=conn;
  claim:=public.claim_notification_center_bank_health();SELECT (x->>'token')::uuid INTO tok FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn;
  PERFORM public.complete_notification_center_bank_health(conn,tok,NULL,NULL,ts+make_interval(mins=>minute));
 END LOOP;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='bank_problem'),3::bigint,'stale pull creates one new persistent episode');
 UPDATE eshop.bank_sync_connections SET state='suspended' WHERE id=conn;
 UPDATE public.notification_center_bank_health SET next_at='-infinity' WHERE connection_id=conn;
 claim:=public.claim_notification_center_bank_health();
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(claim) x WHERE (x->>'id')::bigint=conn),'manual suspend is not monitored as failure');
 -- Stale lease cannot write after completion.
 BEGIN PERFORM public.complete_notification_center_bank_health(conn,tok,ts,NULL);RAISE EXCEPTION 'lost lease accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'notification_health_lease_lost' THEN RAISE; END IF; END;
END $$;
ROLLBACK;
