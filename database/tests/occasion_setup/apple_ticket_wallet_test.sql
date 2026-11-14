DO $$
DECLARE org bigint; un bigint; oc bigint; oid bigint; tid bigint; mid uuid; context jsonb; previous text;
BEGIN
 PERFORM set_config('festapp.email_wake','scheduled',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 INSERT INTO public.organizations(title,data) VALUES('Apple Wallet test','{"APP_NAME":"Ukázkový portál","DEFAULT_URL":"https://tenant.invalid"}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,features)
 VALUES('Večer hudby',org,un,gen_random_uuid()::text,now()+interval '1 day',now()+interval '2 days','[{"code":"ticket","is_enabled":true}]') RETURNING id INTO oc;
 INSERT INTO eshop.ticket_wallet_integrations(organization,environment,web_origin,apple_pass_type_identifier,apple_team_identifier,apple_publishing_ready)
 VALUES(org,'disposable','https://tenant.invalid','pass.net.festapp.test','TESTTEAM01',true);
 PERFORM assert_true(public.ticket_wallet_ready(org),'Apple independently enables the shared connector');
 previous:=public.ticket_wallet_fingerprint(oc);
 INSERT INTO eshop.orders(occasion,order_symbol,order_sequence,state,data,price,currency_code)
 VALUES(oc,public.generate_order_symbol(),public.next_order_sequence(oc),'paid','{"email":"guest@example.invalid"}',0,'CZK') RETURNING id INTO oid;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(oc,'paid','APPLE-EXACT-QR') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,tid);
 PERFORM public.enqueue_paid_order_tickets(oid);
 SELECT message_id INTO STRICT mid FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets';
 context:=public.prepare_ticket_wallet(mid,tid,repeat('1',64),'{"v":"1","ciphertext":"sealed"}');
 PERFORM assert_eq(context#>>'{providers,apple}','true','Apple capability without Google issuer');
 PERFORM assert_eq(context#>>'{providers,google}','false','Google remains disabled');
 context:=public.resolve_ticket_wallet(repeat('1',64),repeat('2',64));
 PERFORM assert_eq(context#>>'{projection,ticket,ticket_symbol}','APPLE-EXACT-QR','shared original admission QR');
 PERFORM assert_eq(context->>'applePassTypeIdentifier','pass.net.festapp.test','signing identity is organization-bound');
 PERFORM assert_eq(context->>'appleTeamIdentifier','TESTTEAM01','team is organization-bound');
 UPDATE eshop.ticket_wallet_integrations SET apple_publishing_ready=false WHERE organization=org;
 PERFORM assert_true(NOT public.ticket_wallet_ready(org),'no provider is ready');
 PERFORM assert_true(previous<>public.ticket_wallet_fingerprint(oc),'provider changes invalidate unstarted email snapshots');
 PERFORM assert_true(public.prepare_ticket_wallet(mid,tid) IS NULL,'disabled provider stops new offers');
 PERFORM assert_eq(public.resolve_ticket_wallet(repeat('1',64),repeat('2',64))#>>'{providers,apple}','false','download boundary sees disabled Apple');
 BEGIN
  UPDATE eshop.ticket_wallet_integrations SET publishing_ready=true WHERE organization=org;
  RAISE EXCEPTION 'Google enabled without issuer';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  UPDATE eshop.ticket_wallet_integrations SET apple_publishing_ready=true,apple_pass_type_identifier=NULL WHERE organization=org;
  RAISE EXCEPTION 'Apple enabled without identity';
 EXCEPTION WHEN check_violation THEN NULL; END;
 UPDATE eshop.ticket_wallet_integrations SET apple_publishing_ready=true WHERE organization=org;
 UPDATE eshop.orders SET state='storno' WHERE id=oid;
 PERFORM assert_eq(public.resolve_ticket_wallet(repeat('1',64),repeat('2',64))#>>'{projection,state}','INACTIVE','storno uses shared lifecycle authority');
 RAISE NOTICE 'PASS Apple-only connector, identity, readiness, capabilities and storno';
END $$;
DO $$
DECLARE org bigint; un bigint; oc bigint; oid bigint; tid bigint; mid uuid; source jsonb; context jsonb; updated jsonb; claim jsonb; serial text:='festapp_'||repeat('b',64); auth_hash text:=repeat('c',64); tag bigint;
BEGIN
 PERFORM set_config('festapp.email_wake','scheduled',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 INSERT INTO public.organizations(title,data) VALUES('Apple updates','{"APP_NAME":"Ukázkový portál","DEFAULT_URL":"https://tenant.invalid"}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,features)
 VALUES('Hudební večer',org,un,gen_random_uuid()::text,now()+interval '1 day',now()+interval '2 days','[{"code":"ticket","is_enabled":true}]') RETURNING id INTO oc;
 INSERT INTO eshop.ticket_wallet_integrations(organization,environment,web_origin,apple_pass_type_identifier,apple_team_identifier,apple_publishing_ready)
 VALUES(org,'disposable','https://tenant.invalid','pass.net.festapp.test','TESTTEAM01',true);
 INSERT INTO eshop.orders(occasion,order_symbol,order_sequence,state,data,price,currency_code)
 VALUES(oc,public.generate_order_symbol(),public.next_order_sequence(oc),'paid','{"email":"guest@example.invalid"}',0,'CZK') RETURNING id INTO oid;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(oc,'paid','APPLE-UPDATES-QR') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,tid);
 PERFORM public.enqueue_paid_order_tickets(oid);
 SELECT message_id INTO STRICT mid FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets';
 source:=public.prepare_ticket_wallet(mid,tid,repeat('d',64),'{"v":"1","ciphertext":"sealed"}');
 context:=public.register_apple_ticket_wallet(repeat('d',64),serial,'pass.net.festapp.test','TESTTEAM01',auth_hash,'{"v":"1","ciphertext":"auth"}');
 PERFORM assert_true(context IS NOT NULL,'pass registration persisted before signature');
 PERFORM assert_eq(public.register_apple_ticket_wallet(repeat('d',64),serial,'pass.net.festapp.test','TESTTEAM01',repeat('e',64),'{}')->>'authHash',auth_hash,'retry retains authentication token');
 PERFORM assert_true(public.get_apple_ticket_wallet('pass.net.festapp.test',serial,repeat('e',64)) IS NULL,'wrong auth cannot fetch pass');
 PERFORM assert_eq(public.register_apple_wallet_device('device-library-identifier','pass.net.festapp.test',serial,auth_hash,repeat('a',64)),201,'first native registration');
 PERFORM assert_eq(public.register_apple_wallet_device('device-library-identifier','pass.net.festapp.test',serial,auth_hash,repeat('a',64)),200,'repeat native registration');
 PERFORM assert_true(public.list_apple_wallet_updates('foreign-device-identifier','pass.net.festapp.test') IS NULL,'device isolation');
 PERFORM assert_true(public.list_apple_wallet_updates('device-library-identifier','pass.net.festapp.test',context->>'updateTag') IS NULL,'unchanged pass not listed');
 UPDATE public.occasions SET title='Nový hudební večer' WHERE id=oc;
 updated:=public.get_apple_ticket_wallet('pass.net.festapp.test',serial,auth_hash);
 PERFORM assert_true((updated->>'updateTag')::bigint>(context->>'updateTag')::bigint,'same-second update tag advances');
 PERFORM assert_true((updated->>'updatedAt')::timestamptz>(context->>'updatedAt')::timestamptz,'Last-Modified advances even within same second');
 PERFORM assert_eq(jsonb_array_length(public.list_apple_wallet_updates('device-library-identifier','pass.net.festapp.test',context->>'updateTag')->'serialNumbers'),1,'changed pass listed');
 claim:=public.claim_apple_ticket_wallet();
 PERFORM assert_eq((claim->>'ticketId')::bigint,tid,'worker claims changed pass');
 PERFORM assert_true(jsonb_array_length(public.apple_wallet_push_targets(tid,(claim->>'lease')::uuid))=1,'notification pending');
 PERFORM assert_true(NOT public.finish_apple_wallet_push(tid,gen_random_uuid(),repeat('a',64),(claim->>'updateTag')::bigint),'stale lease cannot acknowledge push');
 PERFORM assert_true(public.finish_apple_wallet_push(tid,(claim->>'lease')::uuid,repeat('a',64),(claim->>'updateTag')::bigint),'notification receipt');
 PERFORM assert_true(public.finish_apple_ticket_wallet(tid,(claim->>'lease')::uuid,true),'claim completes');
 UPDATE eshop.tickets SET state='used' WHERE id=tid;
 PERFORM assert_eq(public.get_apple_ticket_wallet('pass.net.festapp.test',serial,auth_hash)#>>'{projection,state}','COMPLETED','used pass updates');
 UPDATE eshop.orders SET state='storno' WHERE id=oid;
 PERFORM assert_eq(public.get_apple_ticket_wallet('pass.net.festapp.test',serial,auth_hash)#>>'{projection,state}','INACTIVE','storno updates saved pass');
 DELETE FROM eshop.order_product_ticket WHERE ticket=tid;DELETE FROM eshop.tickets WHERE id=tid;
 updated:=public.get_apple_ticket_wallet('pass.net.festapp.test',serial,auth_hash);
 PERFORM assert_eq(updated#>>'{projection,ticket,ticket_symbol}','APPLE-UPDATES-QR','deleted pass keeps stable voided presentation');
 PERFORM assert_eq(updated->>'serial',serial,'deleted pass identity retained');
 PERFORM assert_eq(public.register_apple_wallet_device('device-library-identifier','pass.net.festapp.test',serial,auth_hash,NULL,true),200,'device unregister after deletion');
 PERFORM assert_true(public.list_apple_wallet_updates('device-library-identifier','pass.net.festapp.test') IS NULL,'removed device no longer listed');
 PERFORM assert_true(NOT has_function_privilege('anon','public.get_apple_ticket_wallet(text,text,text)','EXECUTE'),'native pass RPC not public');
 RAISE NOTICE 'PASS Apple device registration, conditional updates, used/storno/deletion and push fencing';
END $$;
