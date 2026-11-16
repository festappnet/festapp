-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/customer_order_changes/fixture.sql
-- test-setup: database/tests/helpers/refund_operation_fixture.sql
CREATE OR REPLACE FUNCTION pg_temp.customer_bank_source(x jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE account text:='CZ6508000000192000145399'; ns text; bank bigint:=(x->>'bank')::bigint; pi eshop.payment_info; un bigint; con bigint;
BEGIN
 account:=public.canonical_payment_reference_account_internal(bank::text||'/2010');
 SELECT unit INTO un FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 UPDATE eshop.bank_accounts SET account_number=account,supported_currencies=ARRAY['CZK','EUR','USD'] WHERE id=bank;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,(x->>'actor')::uuid,true);
 ns:=encode(extensions.digest(account,'sha256'),'hex');
 INSERT INTO eshop.payment_reference_namespaces(id,canonical_account,allocation_enabled) VALUES(ns,account,true) ON CONFLICT(id) DO NOTHING;
 INSERT INTO eshop.payment_reference_accounts(bank_account_id,namespace_id,account_number_snapshot) VALUES(bank,ns,account);
 INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES((x->>'organization')::bigint,'active',repeat('a',64));
 SELECT * INTO pi FROM eshop.payment_info WHERE id=(x->>'payment')::bigint;
 INSERT INTO eshop.payment_reference_reservations(namespace_id,variable_symbol,source_ref,policy,payload_sha256,payment_info_id,original_payment_info_id,form_id)
 VALUES(ns,pi.variable_symbol,'refund-test-'||pi.id,'{}',repeat('a',64),pi.id,pi.id,(x->>'form')::bigint);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,provider,mode,state,manifest_sha256,legacy_blocked_at)
 VALUES('refund-test-'||bank,'festapp',bank::text,bank,account,'FIO','api','connected',repeat('a',64),now()) RETURNING id INTO con;
 RETURN x||jsonb_build_object('unit',un,'namespace',ns,'connection',con,'variableSymbol',pi.variable_symbol::text);
END $$;

DO $$
DECLARE x jsonb:=pg_temp.customer_two_fixture(); other_spot bigint; before_symbol text; payload jsonb; token text; preview jsonb; result jsonb; command uuid:=extensions.gen_random_uuid(); oid bigint:=(x->>'order')::bigint;
BEGIN
 x:=pg_temp.payment_attach_spot(x);
 INSERT INTO eshop.spots(occasion,blueprint,product,order_product_ticket,title)
 SELECT (x->>'occasion')::bigint,s.blueprint,(x->>'product')::bigint,opt.id,'Other seat' FROM eshop.spots s CROSS JOIN eshop.order_product_ticket opt
 WHERE s.id=(x->>'spot')::bigint AND opt."order"=oid AND opt.ticket=(x->>'otherTicket')::bigint RETURNING id INTO other_spot;
 SELECT ticket_symbol INTO before_symbol FROM eshop.tickets WHERE id=(x->>'otherTicket')::bigint;
 payload:=jsonb_build_object('ticketIds',jsonb_build_array(x->'ticket'));token:=pg_temp.customer_cap(x,'cancel',payload);
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 preview:=public.customer_order_change_gateway('preview',token,NULL,'cancel',payload,command);
 PERFORM assert_eq(preview->>'effect','cancel','a held seat does not prohibit cancellation');
 PERFORM assert_eq(preview->'partial','true'::jsonb,'preview identifies partial scope');
 result:=public.customer_order_change_gateway('command',token,NULL,'cancel',payload,command,preview->>'fingerprint');
 result:=public.customer_order_change_gateway('command',token,NULL,'cancel',payload,command,preview->>'fingerprint');
 RESET ROLE;
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'storno','only selected ticket canceled');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'otherTicket')::bigint),'ordered','other ticket remains active');
 PERFORM assert_eq((SELECT ticket_symbol FROM eshop.tickets WHERE id=(x->>'otherTicket')::bigint),before_symbol,'other QR identity unchanged');
 PERFORM assert_true((SELECT order_product_ticket IS NULL FROM eshop.spots WHERE id=(x->>'spot')::bigint),'selected seat released');
 PERFORM assert_true((SELECT order_product_ticket IS NOT NULL FROM eshop.spots WHERE id=other_spot),'other seat remains allocated');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),1000::numeric,'remaining sale price maintained by shared owner');
 PERFORM assert_eq((SELECT amount FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),1000::numeric,'payment due only for remaining ticket');
 PERFORM assert_eq((SELECT count(*) FROM eshop.customer_order_change_events WHERE command_id=command),1::bigint,'retry has one audit');
 PERFORM assert_eq(public.get_customer_order_overview_internal(x->>'readToken',oid)->>'code','200','original overview still works');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.customer_two_fixture(); payload jsonb:=jsonb_build_object('ticketIds',jsonb_build_array(x->'ticket')); policy jsonb; token text; preview jsonb; result jsonb; command uuid:=extensions.gen_random_uuid(); request eshop.customer_order_change_requests; recipient text:=public.canonical_payment_reference_account_internal('1234/2010');
BEGIN
 x:=pg_temp.customer_bank_source(x);
 policy:=public.customer_order_policy_internal((x->>'form')::bigint)->'policy';policy:=jsonb_set(policy,'{cancel,mode}','"approval_required"');policy:=jsonb_set(policy,'{cancel,refund_mode}','"manual"');
 PERFORM public.save_customer_order_policy_internal((x->>'form')::bigint,policy);
 PERFORM pg_temp.payment_pair(x,2000);
 token:=pg_temp.customer_cap(x,'cancel',payload);
 PERFORM set_config('request.jwt.claim.role','service_role',true);PERFORM set_config('request.jwt.claim.sub','',true);
 SET LOCAL ROLE service_role;
 preview:=public.customer_order_change_gateway('preview',token,NULL,'cancel',payload,command);
 result:=public.customer_order_change_gateway('command',token,NULL,'cancel',payload,command,preview->>'fingerprint');
 RESET ROLE;
 SELECT * INTO STRICT request FROM eshop.customer_order_change_requests WHERE order_id=(x->>'order')::bigint;
 PERFORM assert_eq(request.ticket_ids,ARRAY[(x->>'ticket')::bigint],'approval remembers exact selected identity');
 PERFORM assert_eq((SELECT count(*) FROM public.get_order_tickets_internal((x->>'order')::bigint) WHERE state='storno'),0::bigint,'request has no admission effect');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 SET LOCAL ROLE authenticated;
 result:=public.command_customer_order_request(request.id,'approve',extensions.gen_random_uuid(),request.updated_at);
 RESET ROLE;
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'otherTicket')::bigint),'paid','approval does not cancel other paid ticket');
 SELECT * INTO STRICT request FROM eshop.customer_order_change_requests WHERE id=request.id;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.command_customer_order_request(request.id,'resolve',extensions.gen_random_uuid(),request.updated_at,'Refunded');RAISE EXCEPTION 'unsettled partial refund resolved';EXCEPTION WHEN serialization_failure THEN NULL;END;
 RESET ROLE;
 PERFORM assert_eq((SELECT paid-returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),2000::numeric,'cancellation is not refund settlement');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=(x->>'order')::bigint),1000::numeric,'only selected sale line removed');
 SET LOCAL ROLE authenticated;
 result:=public.command_payment_operation(jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','1000','recipientIban',recipient,'recipientName','Customer'),extensions.gen_random_uuid());
 RESET ROLE;
 result:=pg_temp.refund_bank_event(x,90,-100000);
 PERFORM assert_true((result#>>'{refund,matched}')::boolean,'real bank observation settles selected refund');
 SET LOCAL ROLE authenticated;
 result:=public.command_customer_order_request(request.id,'resolve',extensions.gen_random_uuid(),request.updated_at,'Refund confirmed in bank history');
 RESET ROLE;
 PERFORM assert_eq((SELECT status FROM eshop.customer_order_change_requests WHERE id=request.id),'resolved','settled partial refund can resolve while other ticket remains paid');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.customer_two_fixture(); other jsonb:=pg_temp.customer_fixture(); payload jsonb; token text; result jsonb;
BEGIN
 FOR payload IN SELECT jsonb_build_object('ticketIds',ids) FROM (VALUES ('[]'::jsonb),(jsonb_build_array(x->'ticket',x->'ticket')),(jsonb_build_array(other->'ticket'))) selections(ids) LOOP
  BEGIN PERFORM public.preview_customer_order_change_internal((x->>'order')::bigint,'cancel',payload);RAISE EXCEPTION 'invalid ticket selection accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 END LOOP;
 UPDATE eshop.tickets SET state='used' WHERE id=(x->>'otherTicket')::bigint;
 result:=public.preview_customer_order_change_internal((x->>'order')::bigint,'cancel',jsonb_build_object('ticketIds',jsonb_build_array(x->'ticket')));
 PERFORM assert_eq(result->>'effect','cancel','used other ticket does not prevent unused ticket cancellation');
 PERFORM assert_true(NOT has_function_privilege('service_role','public.cancel_ticket_selection_domain_internal(bigint[],boolean)','EXECUTE'),'service role cannot call private shared effect directly');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.customer_two_fixture(); oid bigint:=(x->>'order')::bigint; payment bigint:=(x->>'payment')::bigint;
 conn uuid; attempt uuid; unit bigint; token text; payload jsonb:=jsonb_build_object('ticketIds',jsonb_build_array(x->'ticket')); preview jsonb; result jsonb; command uuid:=extensions.gen_random_uuid(); claim jsonb;
BEGIN
 SELECT o.unit INTO unit FROM public.occasions o WHERE id=(x->>'occasion')::bigint;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,model_verified)
 VALUES((x->>'organization')::bigint,unit,'acct_customerRefund',false,'connected',true) RETURNING id INTO conn;
 UPDATE eshop.payment_info SET payment_method='stripe',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL,deposit_amount=NULL,stripe_connection_id=conn WHERE id=payment;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,amount_minor,currency,order_revision,idempotency_key,reservation_expires_at,state,payment_intent_id)
 VALUES(oid,payment,(x->>'organization')::bigint,unit,conn,false,200000,'CZK',1,'customer-refund:'||command,now()+interval '30 minutes','paid','pi_customerRefund') RETURNING id INTO attempt;
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'pi_customerRefund',attempt,'payment',200000,'CZK',now());
 PERFORM public.refresh_payment_info_totals_internal(payment);
 result:=public.apply_provider_payment_effects_internal('stripe',attempt,'customer-paid',public.provider_order_payment_projection_internal(oid));
 UPDATE eshop.payment_providers SET refund_write_supported=true,refund_write_enabled=true WHERE provider_key='stripe';
 token:=pg_temp.customer_cap(x,'cancel',payload);
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 preview:=public.customer_order_change_gateway('preview',token,NULL,'cancel',payload,command);
 PERFORM assert_eq(preview->>'effect','request_cancel','partial online refund requires provider admission workflow');
 result:=public.customer_order_change_gateway('command',token,NULL,'cancel',payload,command,preview->>'fingerprint');
 RESET ROLE;
 PERFORM assert_eq((SELECT count(*) FROM public.get_order_tickets_internal(oid) WHERE state='storno'),0::bigint,'unsupported refund cannot invalidate either ticket');
 PERFORM assert_eq((SELECT count(*) FROM eshop.refund_requests WHERE order_id=oid),0::bigint,'request cannot reserve an unintended full refund');
 PERFORM assert_eq((SELECT ticket_ids FROM eshop.customer_order_change_requests WHERE order_id=oid),ARRAY[(x->>'ticket')::bigint],'manual workflow preserves exact selected scope');
END $$;
