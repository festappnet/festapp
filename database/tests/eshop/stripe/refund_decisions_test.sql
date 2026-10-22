DO $$
DECLARE fx jsonb; oc bigint; org bigint; u bigint; t1 bigint; used_ticket bigint; oid bigint; pi bigint; conn uuid; attempt uuid;
 actor uuid:=extensions.gen_random_uuid(); command uuid:=extensions.gen_random_uuid(); result jsonb; count_before bigint;
BEGIN
 fx:=public.scanner_test_fixture(2);oc:=(fx->>'occasion')::bigint;t1:=(fx#>>'{tickets,0}')::bigint;
 SELECT organization,unit INTO org,u FROM public.occasions WHERE id=oc;
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE ticket=t1;
 INSERT INTO eshop.tickets(occasion,ticket_symbol,state) VALUES(oc,'STRIPE-USED-'||oc,'used') RETURNING id INTO used_ticket;
 INSERT INTO eshop.order_product_ticket("order",product,ticket) SELECT oid,product,used_ticket FROM eshop.order_product_ticket WHERE ticket=t1;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state) VALUES(org,u,'acct_decisionFixture',false,'connected') RETURNING id INTO conn;
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method,stripe_connection_id) VALUES(100,'CZK','stripe',conn) RETURNING id INTO pi;
 UPDATE eshop.orders SET payment_info=pi,price=100,currency_code='CZK' WHERE id=oid;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,amount_minor,currency,order_revision,idempotency_key,reservation_expires_at,state)
 VALUES(oid,pi,org,u,conn,false,10000,'CZK',1,'decision:'||extensions.gen_random_uuid(),now()+interval '31 minutes','paid') RETURNING id INTO attempt;
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'pi_decisionFixture',attempt,'payment',10000,'CZK',now()),(conn,'re_decisionFixture',attempt,'refund',2345,'CZK',now());
 PERFORM public.refresh_payment_info_totals_internal(pi);
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.decide_stripe_partial_refund_client_sync_v1(oid,'keep','{}','Keep admission',2345,command);RAISE EXCEPTION 'anonymous decision accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 INSERT INTO auth.users(id,email) VALUES(actor,actor||'@stripe.invalid');
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(oc,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN
  PERFORM public.storno_tickets_bulk_internal_v1(ARRAY[t1]);RAISE EXCEPTION 'ordinary storno changed Stripe price';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_USE_REFUND_ADMISSION_DECISION' THEN RAISE; END IF; END;
 result:=public.get_stripe_order_admin_detail(oid);
 PERFORM assert_true((result->>'canDecide')::boolean,'authorized editor sees partial-refund decision availability');
 PERFORM assert_eq(result->>'refundedMinor','2345','admin DTO uses exact minor units');
 PERFORM assert_eq(public.get_order_history(oid)#>>'{data,order,payment_method}','stripe','authorized history carries canonical payment method for exact amounts');
 PERFORM assert_true(result->'dashboardUrl'='null'::jsonb,'order editor is not granted unit Stripe management');
 PERFORM assert_true(result->'tickets' @> jsonb_build_array(jsonb_build_object('id',used_ticket,'state','used')),'used ticket history stays visible');
 UPDATE eshop.stripe_checkout_attempts SET state='action_required' WHERE id=attempt;
 PERFORM assert_true(NOT (public.get_stripe_order_admin_detail(oid)->>'canDecide')::boolean,'unresolved financial conflict cannot become an admission decision');
 BEGIN
  PERFORM public.decide_stripe_partial_refund_client_sync_v1(oid,'keep','{}','Unresolved money conflict',2345,extensions.gen_random_uuid());RAISE EXCEPTION 'financial conflict accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_PARTIAL_REFUND_REQUIRED' THEN RAISE; END IF; END;
 UPDATE eshop.stripe_checkout_attempts SET state='paid' WHERE id=attempt;
 result:=public.decide_stripe_partial_refund_client_sync_v1(oid,'keep','{}','Price adjustment without cancellation',2345,command);
 PERFORM assert_eq(result->>'code','200','editor can keep admission explicitly');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=t1),'sent','keep does not invalidate group');
 PERFORM assert_eq(public.get_stripe_order_admin_detail(oid)#>>'{decision,note}','Price adjustment without cancellation','admin DTO reads the audited decision note');
 PERFORM assert_true((public.get_stripe_order_admin_detail(oid)#>>'{decision,isCurrent}')::boolean,'new decision matches current immutable refund revision');
 SELECT count(*) INTO count_before FROM eshop.stripe_admission_decisions WHERE attempt_id=attempt;
 PERFORM public.decide_stripe_partial_refund_client_sync_v1(oid,'keep','{}','Price adjustment without cancellation',2345,command);
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_admission_decisions WHERE attempt_id=attempt),count_before,'command replay has one audit decision');
 BEGIN
  PERFORM public.decide_stripe_partial_refund_client_sync_v1(oid,'cancel_selected',ARRAY[used_ticket],'Cancel used ticket',2345,extensions.gen_random_uuid());RAISE EXCEPTION 'used ticket cancelled';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_REFUND_TICKET_UNAVAILABLE' THEN RAISE; END IF; END;
 result:=public.decide_stripe_partial_refund_client_sync_v1(oid,'cancel_selected',ARRAY[t1],'Refund selected unused ticket',2345,extensions.gen_random_uuid());
 PERFORM assert_eq(result->>'code','200','editor may cancel selected unused ticket');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=t1),'storno','selected ticket cancelled');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=used_ticket),'used','used admission history remains');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),100::numeric,'decision does not rewrite sale or create debt');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),23.45::numeric,'decision never creates a provider refund');
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'re_decisionExtra',attempt,'refund',100,'CZK',now());
 PERFORM assert_true(NOT (public.get_stripe_order_admin_detail(oid)#>>'{decision,isCurrent}')::boolean,'another refund makes the displayed old decision explicitly stale');
 BEGIN
  PERFORM public.decide_stripe_partial_refund_client_sync_v1(oid,'keep','{}','Changed provider refund',2345,extensions.gen_random_uuid());RAISE EXCEPTION 'stale refund decision accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_REFUND_REVISION_CHANGED' THEN RAISE; END IF; END;
 UPDATE eshop.stripe_checkout_attempts SET refund_cursor='re_recoveryPending' WHERE id=attempt;
 PERFORM assert_true(NOT (public.get_stripe_order_admin_detail(oid)->>'canDecide')::boolean,'incomplete provider pagination cannot be decided from partial totals');
 BEGIN
  PERFORM public.decide_stripe_partial_refund_client_sync_v1(oid,'keep','{}','Incomplete provider pass',2445,extensions.gen_random_uuid());RAISE EXCEPTION 'incomplete pass accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_PARTIAL_REFUND_REQUIRED' THEN RAISE; END IF; END;
END $$;
