-- Test-provider identities never leave this rollback-only SQL fixture.
DO $$
DECLARE org bigint; u bigint; occ bigint; f bigint; pt bigint; p bigint; conn uuid; payload jsonb; result jsonb; oid bigint;
 source jsonb:=jsonb_build_object('tokenHash',repeat('a',64),'returnHash',repeat('b',64),'contentHash',repeat('c',64),'sealed',jsonb_build_object('v','1','iv','fixture','ciphertext','fixture'));
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 INSERT INTO organizations(title,data) VALUES('English locale test','{"DEFAULT_URL":"https://tickets.example","DEFAULT_LANGUAGE":"en"}') RETURNING id INTO org;
 INSERT INTO units(title,organization) VALUES('English organizer',org) RETURNING id INTO u;
 INSERT INTO eshop.stripe_unit_features(unit_id,enabled) VALUES(u,true);
 INSERT INTO occasions(title,organization,unit,link,start_time,end_time) VALUES('English evening',org,u,'locale-'||gen_random_uuid(),now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused,model_verified,charges_enabled,card_payments_active) VALUES(org,u,'acct_localeFixture',false,'connected',false,true,true,true) RETURNING id INTO conn;
 INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode,new_payments_enabled,online_admission_verified,reservation_policy_verified,dispute_policy_accepted,supported_surfaces) VALUES(org,false,true,true,true,true,ARRAY['web']);
 INSERT INTO forms(occasion,data,is_open,key) VALUES(occ,jsonb_build_object('payments',jsonb_build_object('bankEnabled',false,'stripeConnectionId',conn)),true,gen_random_uuid()) RETURNING id INTO f;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Admission','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code,is_hidden) VALUES(pt,occ,'Ticket',123.45,'CZK',false) RETURNING id INTO p;
 INSERT INTO form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 payload:=jsonb_build_object('form',(SELECT key FROM forms WHERE id=f),'email','locale@example.test','payment_method','stripe','payment_type','full','expected_payment_amount_minor',12345,'expected_payment_currency','CZK','stripe_connection_id',conn,'payment_surface','web','stripePaymentSource',source,'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',p)))));
 result:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(result#>>'{data,code}','200','English order uses canonical command');
 SELECT order_id INTO oid FROM eshop.stripe_checkout_attempts WHERE organization_id=org;
 PERFORM assert_eq((SELECT checkout_locale FROM eshop.stripe_checkout_attempts WHERE order_id=oid),'en','trusted tenant snapshots English Checkout locale');
 PERFORM assert_eq((SELECT data->>'lang' FROM email_messages WHERE order_id=oid AND code='TICKET_ORDER_CONFIRMATION'),'en','missing client language uses trusted English tenant');
 PERFORM set_config('ticketing_test.order',oid::text,true);
 PERFORM assert_true(has_function_privilege('authenticated','public.update_scan_code(text,text)','EXECUTE'),'organizer can create a scanner code through checked RPC');
 PERFORM assert_false(has_function_privilege('anon','public.update_scan_code(text,text)','EXECUTE'),'anonymous callers cannot rotate scanner codes');
 PERFORM assert_false(has_table_privilege('authenticated','eshop.blueprint_area_bindings','SELECT'),'worker access does not expose private geometry to clients');
END $$;
SET LOCAL ROLE service_role;
SELECT assert_eq(public.get_order_details_for_email(current_setting('ticketing_test.order')::bigint)#>>'{data,occasion,locale}','en','real email role can read seating enrichment and trusted locale');
