-- Foundation contracts, deliberately not evidence of the unimplemented payment ingest.
DO $$
DECLARE org bigint; unit_a bigint; unit_b bigint; occ bigint; pi bigint; ord bigint;
 conn uuid; other_conn uuid; attempt uuid; token text; read_token text; handoff text; receipt jsonb;
 n integer; table_name text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Stripe isolated contract') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Organizer A',org) RETURNING id INTO unit_a;
 INSERT INTO public.units(title,organization) VALUES('Organizer B',org) RETURNING id INTO unit_b;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Stripe fixture',org,unit_a,'stripe-'||extensions.gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
 VALUES(org,unit_a,'acct_fixtureA',false,'connected') RETURNING id INTO conn;
 PERFORM assert_true((SELECT paused AND NOT charges_enabled AND NOT model_verified FROM eshop.stripe_connections WHERE id=conn),'new connections cannot receive charges');
 BEGIN
  INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
  VALUES(org,unit_b,'acct_fixtureA',false,'connected');
  RAISE EXCEPTION 'shared account accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
  VALUES(org,unit_a,'acct_fixtureDuplicate',false,'connected');
  RAISE EXCEPTION 'second active account accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
 VALUES(org,unit_b,'acct_fixtureB',false,'connected') RETURNING id INTO other_conn;
 INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode) VALUES(org,false);
 PERFORM assert_false((SELECT new_payments_enabled FROM eshop.stripe_runtime_policy WHERE organization_id=org),'default payment switch off');
 BEGIN
  UPDATE eshop.stripe_runtime_policy SET new_payments_enabled=true WHERE organization_id=org;
  RAISE EXCEPTION 'unverified pilot enabled';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method,stripe_connection_id)
 VALUES(1234.50,'CZK','stripe',conn) RETURNING id INTO pi;
 PERFORM assert_true((SELECT bank_account IS NULL AND variable_symbol IS NULL AND creditor_reference IS NULL FROM eshop.payment_info WHERE id=pi),'Stripe has no bank reference');
 BEGIN
  UPDATE eshop.payment_info SET variable_symbol=12345 WHERE id=pi;
  RAISE EXCEPTION 'Stripe accepted bank instructions';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO eshop.orders(occasion,payment_info,state,price,currency_code,order_sequence,order_symbol)
 VALUES(occ,pi,'ordered',1234.50,'CZK',1,public.generate_order_symbol()) RETURNING id INTO ord;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,
 amount_minor,currency,order_revision,idempotency_key,reservation_expires_at)
 VALUES(ord,pi,org,unit_a,conn,false,123450,'CZK',1,'festapp:'||extensions.gen_random_uuid(),now()+interval '30 minutes') RETURNING id INTO attempt;
 BEGIN
  INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,
  amount_minor,currency,order_revision,idempotency_key,reservation_expires_at)
  VALUES(ord,pi,org,unit_a,conn,false,123450,'CZK',1,'festapp:'||extensions.gen_random_uuid(),now()+interval '30 minutes');
  RAISE EXCEPTION 'two active attempts accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 token:=public.issue_stripe_capability_internal(ord,'order_pay',now()+interval '1 day');
 read_token:=public.issue_stripe_capability_internal(ord,'return_read',now()+interval '5 minutes',attempt);
 handoff:=public.issue_stripe_capability_internal(ord,'handoff',now()+interval '5 minutes',attempt);
 receipt:=public.authorize_stripe_capability_internal(token,'order_pay',ord);
 PERFORM assert_eq(receipt->>'scope','order_pay','separate pay scope');
 BEGIN
  PERFORM public.authorize_stripe_capability_internal(read_token,'order_pay',ord);
  RAISE EXCEPTION 'return handle obtained write scope';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_CAPABILITY' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.authorize_stripe_capability_internal(token,'order_view',ord);
  RAISE EXCEPTION 'pay token accepted as overview';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_CAPABILITY' THEN RAISE; END IF; END;
 PERFORM public.authorize_stripe_capability_internal(handoff,'handoff',ord,attempt);
 BEGIN
  PERFORM public.authorize_stripe_capability_internal(handoff,'handoff',ord,attempt);
  RAISE EXCEPTION 'handoff replay accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_CAPABILITY' THEN RAISE; END IF; END;
 UPDATE eshop.stripe_capabilities SET revoked_at=now() WHERE token_hash=encode(extensions.digest(token,'sha256'),'hex');
 BEGIN
  PERFORM public.authorize_stripe_capability_internal(token,'order_pay',ord);
  RAISE EXCEPTION 'revoked pay token accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_CAPABILITY' THEN RAISE; END IF; END;
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'pi_fixture',attempt,'payment',123450,'CZK',now());
 BEGIN
  INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
  VALUES(conn,'pi_fixture',attempt,'payment',123450,'CZK',now());
  RAISE EXCEPTION 'duplicate economic fact accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
  VALUES(other_conn,'pi_foreign',attempt,'payment',123450,'CZK',now());
  RAISE EXCEPTION 'foreign connection movement accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 FOREACH table_name IN ARRAY ARRAY['stripe_connections','stripe_runtime_policy','stripe_checkout_attempts','stripe_capabilities','stripe_payment_link_sources','stripe_event_inbox','stripe_payment_movements','stripe_disputes','stripe_admission_decisions'] LOOP
  PERFORM assert_true((SELECT relrowsecurity FROM pg_class WHERE oid=('eshop.'||table_name)::regclass),'RLS '||table_name);
  PERFORM assert_false(has_table_privilege('anon','eshop.'||table_name,'SELECT'),'anon cannot read '||table_name);
  PERFORM assert_false(has_table_privilege('authenticated','eshop.'||table_name,'INSERT'),'client cannot write '||table_name);
 END LOOP;
 PERFORM assert_false(has_function_privilege('authenticated','public.authorize_stripe_capability_internal(text,text,bigint,uuid)','EXECUTE'),'private capability boundary');
 PERFORM assert_false(has_function_privilege('anon','public.issue_stripe_capability_internal(bigint,text,timestamptz,uuid)','EXECUTE'),'cannot issue pay capability');
END $$;
