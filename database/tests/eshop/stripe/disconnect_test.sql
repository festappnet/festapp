DO $$
DECLARE org bigint; unit_id bigint; oc bigint; pi bigint; oid bigint; connection uuid; attempt uuid; actor uuid; impact jsonb; intent jsonb; claim jsonb; response jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Disconnect tenant') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Disconnect organizer',org) RETURNING id INTO unit_id;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Disconnect event',org,unit_id,'disconnect-'||extensions.gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO oc;
 PERFORM public.create_user_for_test('stripe_disconnect_manager','stripe-disconnect@example.test');actor:=get_user_id('stripe_disconnect_manager');
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(unit_id,actor,true);
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused,model_verified,charges_enabled,card_payments_active)
  VALUES(org,unit_id,'acct_disconnectFixture',false,'connected',false,true,true,true) RETURNING id INTO connection;
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method,stripe_connection_id) VALUES(50,'CZK','stripe',connection) RETURNING id INTO pi;
 INSERT INTO eshop.orders(occasion,payment_info,state,price,currency_code,order_sequence,order_symbol) VALUES(oc,pi,'ordered',50,'CZK',1,public.generate_order_symbol()) RETURNING id INTO oid;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,amount_minor,currency,order_revision,idempotency_key,reservation_expires_at,state)
 VALUES(oid,pi,org,unit_id,connection,false,5000,'CZK',1,'disconnect:'||extensions.gen_random_uuid(),now()+interval '31 minutes','open') RETURNING id INTO attempt;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 impact:=public.get_stripe_disconnect_impact(unit_id,false);
 PERFORM assert_eq(impact->>'openAttempts','1','preflight explains the open financial attempt');
 BEGIN
  PERFORM public.begin_stripe_disconnect(unit_id,false,connection);RAISE EXCEPTION 'disconnected an unresolved payment';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_DISCONNECT_OPEN_ATTEMPTS' THEN RAISE; END IF; END;
 PERFORM assert_true((SELECT NOT paused FROM eshop.stripe_connections WHERE id=connection),'blocked intent has no side effects');
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at) VALUES(connection,'pi_disconnectPaid',attempt,'payment',5000,'CZK',clock_timestamp());
 PERFORM public.refresh_payment_info_totals_internal(pi);
 UPDATE eshop.stripe_checkout_attempts SET state='paid',session_id='cs_test_disconnect',payment_intent_id='pi_disconnectPaid',last_synced_at=clock_timestamp() WHERE id=attempt;
 UPDATE eshop.orders SET state='paid' WHERE id=oid;
 intent:=public.begin_stripe_disconnect(unit_id,false,connection);
 PERFORM assert_eq(public.begin_stripe_disconnect(unit_id,false,connection),intent,'retry retains the durable intent');
 BEGIN
  PERFORM public.set_stripe_unit_paused(unit_id,false,false);RAISE EXCEPTION 'resumed during deauthorization';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_DISCONNECT_PENDING' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.begin_stripe_connection_flow(unit_id,false);RAISE EXCEPTION 'reauthorized during unresolved deauthorization';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_DISCONNECT_PENDING' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 claim:=public.claim_stripe_disconnect_internal((intent->>'intentId')::uuid,actor,false);
 PERFORM assert_eq(claim->>'disposition','dispatch','external revocation dispatches once');
 PERFORM assert_eq(public.claim_stripe_disconnect_internal((intent->>'intentId')::uuid,actor,false)->>'disposition','uncertain','another tab cannot replay external revocation');
 response:=public.finish_stripe_disconnect_internal((intent->>'intentId')::uuid,false);
 PERFORM assert_true((response->>'uncertain')::boolean,'timeout remains explicitly uncertain');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','an uncertain disconnect never edits financial history');
 claim:=public.claim_stripe_connection_status_internal('acct_disconnectFixture',false);
 PERFORM public.commit_stripe_connection_status_internal(connection,(claim->>'lease')::uuid,jsonb_build_object('accountId','acct_disconnectFixture','accessUnavailable',true),NULL);
 PERFORM assert_eq(public.claim_stripe_disconnect_internal((intent->>'intentId')::uuid,actor,false)->>'disposition','replay','current read resolves lost revocation response without another POST');
 PERFORM assert_true((SELECT state='revoked' AND paused FROM eshop.stripe_connections WHERE id=connection),'resolved revocation prevents new payments');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=attempt),1::bigint,'disconnection retains the economic fact');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),50::numeric,'disconnection preserves payment totals');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_true(public.begin_stripe_connection_flow(unit_id,false)->>'state' IS NOT NULL,'new OAuth is possible only after resolved revocation');
 PERFORM assert_false(has_function_privilege('authenticated','public.finish_stripe_disconnect_internal(uuid,boolean)','EXECUTE'),'client cannot claim provider revocation succeeded');
END $$;
