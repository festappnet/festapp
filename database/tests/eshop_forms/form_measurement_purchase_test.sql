-- Focused confirmed-price, policy and response-loss conversion regression.
-- Temporary fault injection is rolled back by the test runner.
ALTER TABLE public.email_messages ADD CONSTRAINT stripe_test_email_fault CHECK(message_kind<>'order_tickets') NOT VALID;
DO $$
DECLARE org bigint; u bigint; occ bigint; f bigint; pt bigint; p bigint; conn uuid; payload jsonb; result jsonb; replay jsonb;
 source jsonb:=jsonb_build_object('tokenHash',encode(extensions.digest(repeat('1',64),'sha256'),'hex'),'returnHash',encode(extensions.digest(repeat('2',64),'sha256'),'hex'),'contentHash',repeat('c',64),
  'sealed',jsonb_build_object('v','1','iv','fixture','ciphertext','fixture'));
 command uuid:=extensions.gen_random_uuid(); client uuid:=extensions.gen_random_uuid(); oid bigint; pi bigint; attempt eshop.stripe_checkout_attempts; claim jsonb; sync_claim jsonb; facts jsonb; event jsonb; response jsonb; count_before bigint;
 legacy_bank bigint; manager uuid; flow jsonb; original_attempts jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 INSERT INTO public.organizations(title,data) VALUES('Stripe create tenant','{"DEFAULT_URL":"https://tickets.example"}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Card receiver',org) RETURNING id INTO u;
 UPDATE public.organizations SET data=data||'{"FORM_MEASUREMENT_ENABLED":true}'::jsonb WHERE id=org;
 UPDATE public.units SET data=coalesce(data,'{}')||'{"measurement_privacy_url":"https://organizer.example/privacy","measurement_enabled":true}'::jsonb WHERE id=u;
 INSERT INTO eshop.stripe_unit_features(unit_id,enabled) VALUES(u,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Card order',org,u,'stripe-create-'||extensions.gen_random_uuid(),now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused,model_verified,charges_enabled,card_payments_active)
 VALUES(org,u,'acct_createFixture',false,'connected',false,true,true,true) RETURNING id INTO conn;
 INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode,new_payments_enabled,online_admission_verified,reservation_policy_verified,dispute_policy_accepted,supported_surfaces)
 VALUES(org,false,true,true,true,true,ARRAY['web']);
 INSERT INTO public.forms(occasion,data,is_open,key) VALUES(occ,jsonb_build_object('payments',jsonb_build_object('bankEnabled',false,'stripeConnectionId',conn)),true,extensions.gen_random_uuid()) RETURNING id INTO f;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'test','disposable conversion fixture');
 UPDATE public.forms SET data=data||'{"analytics":{"enabled":true}}'::jsonb WHERE id=f;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Card tickets','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code,is_hidden) VALUES(pt,occ,'Card ticket',123.45,'CZK',false) RETURNING id INTO p;
 INSERT INTO public.form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=f),'email','card@example.test','payment_method','stripe',
  'payment_type','full','expected_payment_amount_minor',12345,'expected_payment_currency','CZK','stripe_connection_id',conn,'payment_surface','web','stripePaymentSource',source,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',p)))));
 result:=public.create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','canonical card create succeeds: '||result::text);
 PERFORM assert_eq(result#>>'{data,analytics,event}','purchase','confirmed requested order receives immutable analytics facts');
 PERFORM assert_true(result#>>'{data,analytics,ecommerce,transaction_id}'<>result#>>'{data,order,order_symbol}','analytics identity is not an order capability');
 PERFORM assert_eq(result#>>'{data,analytics,ecommerce,payment_type}','card','analytics describes payment method, not paid state');
 PERFORM assert_eq(result#>'{data,analytics,ecommerce,items}',jsonb_build_array(jsonb_build_object('item_id','product_'||p,'item_name','Card ticket','price',123.45,'quantity',1)),'analytics exposes the public offer name and final buyer price');
 PERFORM assert_eq(result#>>'{data,analytics,ecommerce,value}','123.45','analytics value is the final charged line total');
 PERFORM assert_true(NOT (result#>'{data,analytics,ecommerce}') ? 'tax','VAT is not invented without a backend breakdown');
 oid:=(result#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO pi FROM eshop.orders WHERE id=oid;
 SELECT * INTO STRICT attempt FROM eshop.stripe_checkout_attempts WHERE order_id=oid;
 PERFORM assert_eq(attempt.amount_minor,12345::bigint,'price originates from product catalog');
 PERFORM assert_true(attempt.reservation_expires_at=attempt.created_at+interval '31 minutes','fixed reservation and dispatch allowance');
 BEGIN
  PERFORM public.cancel_order_domain_internal_v1(oid,false);RAISE EXCEPTION 'ordinary cancellation changed a Stripe order';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_USE_REFUND_ADMISSION_DECISION' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),123.45::numeric,'rejected ordinary cancellation retains original amount');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','rejected ordinary cancellation retains reservation');

 PERFORM assert_true((SELECT bank_account IS NULL AND variable_symbol IS NULL AND creditor_reference IS NULL AND deposit_amount IS NULL FROM eshop.payment_info WHERE id=pi),'card needs no bank account or bank instructions');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','return/create is not proof of payment');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_link_sources WHERE command_id=command),1::bigint,'source commits with order');
 PERFORM assert_true(NOT (SELECT data ? 'stripePaymentSource' FROM eshop.orders WHERE id=oid),'sealed capability excluded from order history and projection');
 PERFORM assert_eq(result#>>'{data,payment,method}','stripe','safe payment projection accompanies order');
 replay:=public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{stripePaymentSource,tokenHash}',to_jsonb(repeat('d',64))),command,client);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'same command retains original order and source');
 PERFORM assert_eq(replay#>'{data,analytics}',result#>'{data,analytics}','lost first response recovers the same authorized conversion');
 UPDATE eshop.orders SET price=0 WHERE id=oid;
 replay:=public.create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(replay#>'{data,analytics}',result#>'{data,analytics}','later order edits cannot change the original command conversion');
 UPDATE eshop.orders SET price=123.45 WHERE id=oid;
 UPDATE eshop.products SET price=999 WHERE id=p;
 PERFORM assert_eq(public.form_conversion_datalayer_internal(oid,'purchase'),result#>'{data,analytics}','later catalog prices do not rewrite conversion facts');
 UPDATE public.units SET data=data-'measurement_privacy_url' WHERE id=u;
 PERFORM assert_true(public.form_conversion_datalayer_internal(oid,'purchase') IS NULL,'missing privacy URL blocks historical conversion export');
 DELETE FROM analytics.conversion_facts WHERE "order"=oid;
 PERFORM public.record_form_conversion_internal(oid);
 PERFORM assert_false(EXISTS(SELECT FROM analytics.conversion_facts WHERE "order"=oid),'missing privacy URL prevents conversion recording');
 UPDATE public.units SET data=data||'{"measurement_privacy_url":"https://organizer.example/privacy"}' WHERE id=u;
 PERFORM public.record_form_conversion_internal(oid);
 PERFORM assert_true(EXISTS(SELECT FROM analytics.conversion_facts WHERE "order"=oid),'valid URL permits conversion recording again');
 UPDATE analytics.organization_policy SET enabled=false,revision=2 WHERE organization=org;
 PERFORM assert_true(public.form_conversion_datalayer_internal(oid,'purchase') IS NULL,'live policy revocation blocks replay projection');
 UPDATE analytics.organization_policy SET enabled=true,revision=3 WHERE organization=org;
 UPDATE eshop.products SET price=123.45 WHERE id=p;
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_checkout_attempts WHERE order_id=oid),1::bigint,'replay cannot create another attempt');

 UPDATE public.units SET data=data-'measurement_privacy_url' WHERE id=u;
 payload:=jsonb_set(jsonb_set(payload,'{stripePaymentSource,tokenHash}',to_jsonb(encode(extensions.digest(extensions.gen_random_uuid()::text,'sha256'),'hex'))),
  '{stripePaymentSource,returnHash}',to_jsonb(encode(extensions.digest(extensions.gen_random_uuid()::text,'sha256'),'hex')));
 result:=public.create_ticket_order_client_sync_v1(payload,extensions.gen_random_uuid(),extensions.gen_random_uuid());
 PERFORM assert_eq(result#>>'{data,code}','200','missing privacy URL never blocks checkout');
 PERFORM assert_true(result#>'{data,analytics}' IS NULL OR result#>'{data,analytics}'='null'::jsonb,'checkout without URL exports no conversion');
 PERFORM assert_false(EXISTS(SELECT FROM analytics.conversion_facts WHERE "order"=(result#>>'{data,order,id}')::bigint),'checkout without URL records no conversion');

END $$;
