-- test-setup: database/tests/helpers/form_measurement_fixture.sql
-- Independent buyers keep the real shared recipient budget scoped per scenario.
CREATE OR REPLACE FUNCTION pg_temp.checkout(x jsonb,tickets bigint[] DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('form',x->'key','email','discount-'||(x->>'form')||'@example.invalid','ticket',
 CASE WHEN tickets IS NULL THEN jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))
 ELSE (SELECT jsonb_agg(jsonb_build_object('ticketId',id,'fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))) FROM unnest(tickets) id) END);
$$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); oc bigint:=(x->>'occasion')::bigint; c jsonb; q jsonb; payload jsonb;
 result jsonb; replay jsonb; cmd uuid:=gen_random_uuid(); client uuid:=gen_random_uuid(); oid bigint; failed boolean; token text:=encode(extensions.gen_random_bytes(32),'hex');
BEGIN
 UPDATE public.forms SET is_open=true WHERE id=(x->>'form')::bigint;
 payload:=pg_temp.checkout(x);
 PERFORM assert_eq(public.quote_order_discount(payload||'{"discount":{"code":"TEST10"}}')->>'errorCode','DISCOUNT_INVALID','missing feature fails closed');
 UPDATE public.occasions SET features='[{"code":"discount_codes","is_enabled":true}]' WHERE id=oc;
 failed:=false;BEGIN PERFORM public.save_discount_code(oc,'{"code":"ŠLEVA","kind":"percent","value":1000}');EXCEPTION WHEN OTHERS THEN failed:=true;END;
 PERFORM assert_true(failed,'ASCII code alphabet is enforced by SQL');
 c:=public.save_discount_code(oc,jsonb_build_object('code','test10','kind','percent','value',1000,'isActive',true,'usageLimit',1));
 payload:=payload||'{"discount":{"code":" test10 "}}';
 q:=public.quote_order_discount(payload);
 PERFORM assert_eq(q->>'code','200','quote accepted');
 PERFORM assert_eq((q#>>'{quote,net}')::numeric,90::numeric,'10 percent quote');
 PERFORM assert_true(NOT (q->'quote' ?| ARRAY['codeId','uses','usage_limit','definition']),'quote keeps definitions private');
 payload:=jsonb_set(payload,'{discount,fingerprint}',q#>'{quote,fingerprint}');
 result:=public.create_ticket_order_client_sync_v1(payload,cmd,client);
 PERFORM assert_eq(result#>>'{data,code}','200','discounted checkout succeeds: '||result::text);
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),90::numeric,'order net');
 PERFORM assert_eq((SELECT amount FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=oid)),90::numeric,'payment net');
 PERFORM assert_eq((SELECT sum(net_price) FROM eshop.order_product_ticket WHERE "order"=oid),90::numeric,'line net');
 PERFORM public.issue_order_overview_internal(oid,jsonb_build_object('tokenHash',encode(extensions.digest(token,'sha256'),'hex'),'contentHash',repeat('f',64),'sealed',jsonb_build_object('ciphertext','sealed-test-double')),gen_random_uuid());
 q:=public.get_customer_order_overview(jsonb_build_object('token',token,'order_id',oid,'client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb));
 PERFORM assert_eq(q->>'code','200','email link overview capability: '||q::text);
 PERFORM assert_eq((q#>>'{orders,0,discount,net}')::numeric,90::numeric,'customer overview shows granted net');
 PERFORM assert_eq((q#>>'{orders,0,items,0,price}')::numeric,90::numeric,'customer line uses sold net');
 UPDATE public.user_info SET organization=(x->>'organization')::bigint WHERE id=(x->>'actor')::uuid;
 PERFORM pg_temp.adopt_public_link_fixtures();
 q:=public.get_report_ws(x->>'link');
 PERFORM assert_eq(q->>'code','200','authorized report: '||q::text);
 PERFORM assert_eq((q#>>'{report,money_by_currency,0,current_order_value}')::numeric,90::numeric,'report uses order net');
 PERFORM assert_eq((q#>>'{report,discounts_by_currency,0,discount_amount}')::numeric,10::numeric,'report retains grant breakdown');

 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE code_id=(c->>'id')::bigint),1::bigint,'one use');
 replay:=public.create_ticket_order_client_sync_v1(payload,cmd,client);
 PERFORM assert_eq(replay#>>'{data,order,id}',result#>>'{data,order,id}','same receipt on retry');
 PERFORM assert_eq(public.quote_order_discount(payload)->>'errorCode','DISCOUNT_INVALID','exhausted code generic error');
 failed:=false; BEGIN PERFORM public.update_ticket_products_client_sync_v1((SELECT ticket FROM eshop.order_product_ticket WHERE "order"=oid LIMIT 1),jsonb_build_array(jsonb_build_object('id',x->'product','price',80)),gen_random_uuid()); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='DISCOUNTED_ORDER_PRICE_IMMUTABLE'; END;
 PERFORM assert_true(failed,'product repricing rejected');
 UPDATE public.occasions SET features='[]' WHERE id=oc;
 replay:=public.create_ticket_order_client_sync_v1(payload,cmd,client);
 PERFORM assert_eq(replay#>>'{data,order,id}',result#>>'{data,order,id}','receipt survives feature off');
 PERFORM assert_eq(public.quote_order_discount(payload)->>'errorCode','DISCOUNT_INVALID','off denies new quote');
 q:=public.get_customer_order_overview(jsonb_build_object('token',token,'order_id',oid,'client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb));
 PERFORM assert_eq((q#>>'{orders,0,discount,net}')::numeric,90::numeric,'existing email overview still shows net after feature off');
 PERFORM assert_eq((SELECT net_amount FROM eshop.order_discounts WHERE order_id=oid),90::numeric,'snapshot survives off');
 PERFORM assert_true(NOT has_table_privilege('anon','eshop.discount_codes','SELECT'),'no public listing');
 PERFORM assert_true(NOT has_table_privilege('authenticated','eshop.order_discounts','INSERT'),'no direct write');
 PERFORM assert_true(NOT has_function_privilege('service_role','public.apply_order_discount_internal(bigint,jsonb,jsonb)','EXECUTE'),'private commit');
END $$;
DO $$
DECLARE q jsonb; lines jsonb:='[{"base":0.01,"deposit":0,"eligible":true},{"base":0.01,"deposit":0,"eligible":true},{"base":0.01,"deposit":0,"eligible":true}]'; failed boolean;
BEGIN
 q:=public.calculate_order_discount_internal(lines,'percent',5000,2);
 PERFORM assert_eq((q->>'discount')::numeric,0.02::numeric,'round once');
 PERFORM assert_eq((q#>>'{lines,0,discount}')::numeric,0.01::numeric,'first stable remainder');
 PERFORM assert_eq((q#>>'{lines,2,discount}')::numeric,0::numeric,'last stable remainder');
 q:=public.calculate_order_discount_internal(lines,'fixed',100,2);
 PERFORM assert_eq((q->>'net')::numeric,0::numeric,'fixed capped at eligible');
 failed:=false; BEGIN PERFORM public.calculate_order_discount_internal('[{"base":100,"deposit":90,"eligible":true}]','percent',1000,2); EXCEPTION WHEN OTHERS THEN failed:=true; END;
 PERFORM assert_true(failed,'net equal deposit rejected');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); oc bigint:=(x->>'occasion')::bigint; code jsonb; payload jsonb; q jsonb; r jsonb; oid bigint; n bigint; failed boolean;
BEGIN
 UPDATE public.forms SET is_open=true WHERE id=(x->>'form')::bigint;
 UPDATE public.occasions SET features='[{"code":"discount_codes","is_enabled":true}]' WHERE id=oc;
 code:=public.save_discount_code(oc,'{"code":"MATRIX","kind":"percent","value":1000,"isActive":true}');
 payload:=pg_temp.checkout(x)||'{"discount":{"code":"MATRIX"}}';
 q:=public.quote_order_discount(payload);payload:=jsonb_set(payload,'{discount,fingerprint}',q#>'{quote,fingerprint}');
 UPDATE eshop.products SET price=200 WHERE id=(x->>'product')::bigint;
 r:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,errorCode}','DISCOUNT_QUOTE_CHANGED','price wave requires new confirmation');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE code_id=(code->>'id')::bigint),0::bigint,'stale quote consumes nothing');
 UPDATE eshop.products SET price=100,data='{"deposit":{"amount":90}}' WHERE id=(x->>'product')::bigint;
 PERFORM assert_eq(public.quote_order_discount(payload)->>'reason','DISCOUNT_DEPOSIT_CONFLICT','organizer sees deposit restriction');
 PERFORM set_config('request.jwt.claim.sub','',true);
 SET LOCAL ROLE anon;
 q:=public.quote_order_discount(payload);
 RESET ROLE;
 PERFORM assert_true(NOT q ? 'reason','visitor gets same generic error');
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 UPDATE eshop.products SET data='{}' WHERE id=(x->>'product')::bigint;
 UPDATE eshop.discount_codes SET valid_from=clock_timestamp()+interval '1 hour' WHERE id=(code->>'id')::bigint;
 PERFORM assert_eq(public.quote_order_discount(payload)->>'reason','DISCOUNT_OUTSIDE_VALIDITY','before start rejected');
 UPDATE eshop.discount_codes SET valid_from=NULL,valid_until=clock_timestamp() WHERE id=(code->>'id')::bigint;
 PERFORM assert_eq(public.quote_order_discount(payload)->>'reason','DISCOUNT_OUTSIDE_VALIDITY','end instant excluded');
 UPDATE eshop.discount_codes SET valid_until=NULL,is_active=false WHERE id=(code->>'id')::bigint;
 PERFORM assert_eq(public.quote_order_discount(payload)->>'reason','DISCOUNT_INACTIVE','inactive rejected');
 UPDATE eshop.discount_codes SET is_active=true,form_ids=ARRAY[-1::bigint] WHERE id=(code->>'id')::bigint;
 PERFORM assert_eq(public.quote_order_discount(payload)->>'reason','DISCOUNT_FORM_SCOPE','form scope enforced');
 UPDATE eshop.discount_codes SET form_ids='{}',product_ids=ARRAY[-1::bigint] WHERE id=(code->>'id')::bigint;
 PERFORM assert_eq(public.quote_order_discount(payload)->>'reason','DISCOUNT_PRODUCT_SCOPE','product scope enforced');
 UPDATE eshop.discount_codes SET product_ids='{}',kind='fixed',value=50,currency_code='EUR' WHERE id=(code->>'id')::bigint;
 PERFORM assert_eq(public.quote_order_discount(payload)->>'reason','DISCOUNT_CURRENCY_MISMATCH','fixed currency enforced');
 UPDATE eshop.discount_codes SET kind='percent',value=10000,currency_code=NULL WHERE id=(code->>'id')::bigint;
 q:=public.quote_order_discount(payload);payload:=jsonb_set(payload,'{discount,fingerprint}',q#>'{quote,fingerprint}');
 r:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200','100 percent checkout');oid:=(r#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),0::numeric,'zero net');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','existing free order transition');
 PERFORM assert_true((SELECT p.variable_symbol IS NULL AND p.bank_account IS NULL AND p.amount=0 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=oid),'no bank reference on free purchase');
 UPDATE public.occasions SET features='[]' WHERE id=oc;
 PERFORM public.cancel_order_domain_internal_v1(oid,false);
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE order_id=oid),1::bigint,'cancellation retains use');
 PERFORM assert_eq((SELECT (snapshot#>>'{tickets,0,products,0,base_price}')::numeric FROM eshop.order_discounts WHERE order_id=oid),100::numeric,'sale snapshot survives detached products');
 DELETE FROM eshop.products WHERE id=(x->>'product')::bigint;
 PERFORM assert_eq((SELECT base_amount FROM eshop.order_discounts WHERE order_id=oid),100::numeric,'catalog deletion cannot change original price');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); code jsonb; payload jsonb; q jsonb; r jsonb; oid bigint; failed boolean; orig uuid:=gen_random_uuid();
BEGIN
 UPDATE public.forms SET is_open=true,data='{"payments":{"bankEnabled":false,"cashEnabled":true,"cashInstructions":"Pay at entrance","providerConnections":{}},"payment_deadline":{"mode":"none"}}',bank_account=NULL WHERE id=(x->>'form')::bigint;
 UPDATE public.occasions SET features='[{"code":"discount_codes","is_enabled":true}]' WHERE id=(x->>'occasion')::bigint;
 code:=public.save_discount_code((x->>'occasion')::bigint,'{"code":"CASH10","kind":"fixed","value":10,"currency":"CZK","isActive":true}');
 payload:=pg_temp.checkout(x)||'{"payment_method":"cash","client_capabilities":["cash_reservations","no_payment_deadline"],"discount":{"code":"CASH10"}}';
 q:=public.quote_order_discount(payload);payload:=jsonb_set(payload,'{discount,fingerprint}',q#>'{quote,fingerprint}');
 r:=public.create_ticket_order_client_sync_v1(payload,orig,gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200','cash discounted purchase: '||r::text);oid:=(r#>>'{data,order,id}')::bigint;
 PERFORM assert_eq(r#>>'{data,order,payment_info,payment_method}','cash','same cash engine');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),90::numeric,'cash net 90');
 failed:=false;BEGIN
  PERFORM public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{discount,code}','"OTHER"'),orig,gen_random_uuid());
 EXCEPTION WHEN OTHERS THEN failed:=true;END;
 PERFORM assert_true(failed,'same command different code conflicts');
 failed:=false;BEGIN PERFORM public.save_discount_code((x->>'occasion')::bigint,'{"code":"CHANGED","kind":"fixed","value":10,"currency":"CZK","isActive":true}',(code->>'id')::bigint,1);
 EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='DISCOUNT_IDENTITY_IMMUTABLE';END;
 PERFORM assert_true(failed,'used identity cannot be renamed');
 failed:=false;BEGIN PERFORM public.save_discount_code((x->>'occasion')::bigint,'{"code":"CASH10","kind":"fixed","value":10,"currency":"CZK","isActive":false}',(code->>'id')::bigint,0);
 EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='DISCOUNT_REVISION_CONFLICT';END;
 PERFORM assert_true(failed,'stale editor cannot reactivate a code');
 code:=public.save_discount_code((x->>'occasion')::bigint,'{"code":"CASH10","kind":"fixed","value":10,"currency":"CZK","isActive":false}',(code->>'id')::bigint,1);
 failed:=false;BEGIN PERFORM public.save_discount_code((x->>'occasion')::bigint,'{"code":"CASH10","kind":"fixed","value":10,"currency":"CZK","isActive":true}',(code->>'id')::bigint,1);
 EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='DISCOUNT_REVISION_CONFLICT';END;
 PERFORM assert_true(failed AND NOT (SELECT is_active FROM eshop.discount_codes WHERE id=(code->>'id')::bigint),'paused revision cannot be revived by stale editor');
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES((x->>'unit')::bigint,(x->>'actor')::uuid,true,true);
 PERFORM public.insert_manual_transaction_internal_v1(90,'CZK',(x->>'unit')::bigint,NULL,now(),'cash',(SELECT payment_info FROM eshop.orders WHERE id=oid));
 UPDATE public.occasions SET features='[]' WHERE id=(x->>'occasion')::bigint;
 r:=public.command_payment_operation(jsonb_build_object('operation','prepare_refund','orderId',oid,'method','cash','amount','90','receivedAt',now(),'note','Refund'),gen_random_uuid());
 PERFORM assert_eq((SELECT amount FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=oid)),90::numeric,'refund keeps charged net amount');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=oid)),90::numeric,'cash refund works after feature off');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE order_id=oid),1::bigint,'refund does not restore coupon use');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); c jsonb; p jsonb; q jsonb; r jsonb; oid bigint; cmd uuid:=gen_random_uuid(); claim jsonb; vs bigint;
BEGIN
 UPDATE public.forms SET is_open=true WHERE id=(x->>'form')::bigint;
 UPDATE public.occasions SET features='[{"code":"discount_codes","is_enabled":true}]' WHERE id=(x->>'occasion')::bigint;
 INSERT INTO eshop.external_services(unit,type,data) VALUES((x->>'unit')::bigint,'FAKTUROID','{}');
 c:=public.save_discount_code((x->>'occasion')::bigint,'{"code":"INVOICE10","kind":"percent","value":1000,"isActive":true}');
 p:=pg_temp.checkout(x)||'{"discount":{"code":"INVOICE10"}}';q:=public.quote_order_discount(p);p:=jsonb_set(p,'{discount,fingerprint}',q#>'{quote,fingerprint}');
 r:=public.create_ticket_order_client_sync_v1(p,cmd,gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200','invoice discount order');oid:=(r#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'preparing_payment','existing invoice gate');
 claim:=public.claim_replacement_invoice_preparation(oid,cmd);
 PERFORM assert_eq(claim->>'status','claimed','discount receipt uses existing lease');
 PERFORM assert_eq(claim->'allowCreate','true'::jsonb,'initial dispatch allowed once');
 PERFORM public.mark_replacement_invoice_dispatch(oid,cmd,(claim->>'token')::uuid);
 PERFORM public.release_replacement_invoice_preparation(oid,cmd,(claim->>'token')::uuid,false);
 UPDATE public.occasions SET features='[]' WHERE id=(x->>'occasion')::bigint;
 claim:=public.claim_replacement_invoice_preparation(oid,cmd);
 PERFORM assert_eq(claim->'allowCreate','false'::jsonb,'unknown outcome requires lookup after off');
 SELECT p.variable_symbol INTO vs FROM eshop.payment_info p JOIN eshop.orders o ON o.payment_info=p.id WHERE o.id=oid;
 PERFORM public.complete_replacement_invoice_preparation(oid,cmd,(claim->>'token')::uuid,vs);
 PERFORM assert_eq((SELECT amount FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=oid)),90::numeric,'invoice completion retains net');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE order_id=oid),1::bigint,'invoice retry does not use code twice');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); c jsonb; p jsonb; q jsonb; r jsonb; preview jsonb; oid bigint;
BEGIN
 UPDATE public.user_info SET organization=(x->>'organization')::bigint WHERE id=(x->>'actor')::uuid;
 UPDATE public.forms SET is_open=true WHERE id=(x->>'form')::bigint;
 UPDATE public.occasions SET features='[{"code":"discount_codes","is_enabled":true}]' WHERE id=(x->>'occasion')::bigint;
 c:=public.save_discount_code((x->>'occasion')::bigint,'{"code":"ADMIN10","kind":"percent","value":1000,"usageLimit":1,"isActive":true}');
 p:=pg_temp.checkout(x)||'{"discount":{"code":"ADMIN10"}}';q:=public.quote_order_discount(p);p:=jsonb_set(p,'{discount,fingerprint}',q#>'{quote,fingerprint}');
 preview:=public.preview_admin_form_order((x->>'occasion')::bigint,(x->>'organization')::bigint,(x->>'unit')::bigint,(x->>'form')::bigint,p);
 PERFORM assert_eq(preview#>>'{quote,newOrder,amount}','90.00','admin preview uses net');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE code_id=(c->>'id')::bigint),0::bigint,'admin preview is rolled back');
 r:=public.create_admin_form_order((x->>'occasion')::bigint,(x->>'organization')::bigint,(x->>'unit')::bigint,(x->>'form')::bigint,p,preview->>'confirmationHash',(x->>'actor')::uuid,gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200','admin commit: '||r::text);
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE code_id=(c->>'id')::bigint),1::bigint,'admin commit consumes once');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(1); c jsonb; p jsonb; q jsonb; r jsonb; registration jsonb; offer jsonb; source bigint; regular bigint; oid bigint; ids bigint[]; acceptance_command uuid:=gen_random_uuid(); acceptance_client uuid:=gen_random_uuid(); offer_token text:=encode(extensions.gen_random_bytes(32),'hex');
BEGIN
 UPDATE public.forms SET is_open=true WHERE id=(x->>'form')::bigint;
 UPDATE public.occasions SET features='[{"code":"discount_codes","is_enabled":true}]' WHERE id=(x->>'occasion')::bigint;
 c:=public.save_discount_code((x->>'occasion')::bigint,'{"code":"WAIT10","kind":"percent","value":1000,"isActive":true}');
 r:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x),gen_random_uuid(),gen_random_uuid());regular:=(r#>>'{data,order,id}')::bigint;
 registration:=pg_temp.register(x,2);source:=(registration->>'order')::bigint;
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE code_id=(c->>'id')::bigint),0::bigint,'waitlist registration consumes nothing');
 PERFORM public.cancel_order_domain_internal_v1(regular,false);
 offer:=pg_temp.offer(x,source,1,offer_token);ids:=ARRAY[(pg_temp.ticket_ids(source))[1]];
 p:=pg_temp.checkout(x,ids)||'{"discount":{"code":"WAIT10"}}';q:=public.quote_order_discount(p);p:=jsonb_set(p,'{discount,fingerprint}',q#>'{quote,fingerprint}');
 r:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',offer->'id','ticketIds',to_jsonb(ids),'token',offer_token,'orderDetails',p),acceptance_command,acceptance_client,NULL);
 PERFORM assert_eq(r#>>'{data,code}','200','partial waitlist accept: '||r::text);oid:=(r#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),90::numeric,'offer reuses same net owner');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE code_id=(c->>'id')::bigint),1::bigint,'partial acceptance uses once');
 UPDATE public.occasions SET features='[]' WHERE id=(x->>'occasion')::bigint;
 r:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',offer->'id','ticketIds',to_jsonb(ids),'token',offer_token,'orderDetails',p),acceptance_command,acceptance_client,NULL);
 PERFORM assert_eq((r#>>'{data,order,id}')::bigint,oid,'guest retry after offer consumption and feature off returns the same order');
 PERFORM public.cancel_order_domain_internal_v1(oid,false);
 offer:=pg_temp.offer(x,source,1);ids:=pg_temp.ticket_ids(source);
 r:=pg_temp.accept(x,offer,ids);
 PERFORM assert_eq(r#>>'{data,code}','200','second partial acceptance succeeds without a code');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=(r#>>'{data,order,id}')::bigint),100::numeric,'coupon is not inherited');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_discounts WHERE code_id=(c->>'id')::bigint),1::bigint,'cancellation and no-code acceptance retain usage');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); c jsonb; p jsonb; q jsonb; r jsonb; oid bigint; conn uuid; source jsonb;
BEGIN
 UPDATE public.forms SET is_open=true WHERE id=(x->>'form')::bigint;
 UPDATE public.occasions SET features='[{"code":"discount_codes","is_enabled":true}]' WHERE id=(x->>'occasion')::bigint;
 INSERT INTO eshop.organization_payment_method_policies(organization_id,method,enabled) VALUES((x->>'organization')::bigint,'stripe',true);
 UPDATE public.organizations SET data=coalesce(data,'{}')||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=(x->>'organization')::bigint;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused,model_verified,charges_enabled,card_payments_active)
 VALUES((x->>'organization')::bigint,(x->>'unit')::bigint,'acct_discountFixture',false,'connected',false,true,true,true) RETURNING id INTO conn;
 INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode,new_payments_enabled,online_admission_verified,reservation_policy_verified,dispute_policy_accepted,supported_surfaces)
 VALUES((x->>'organization')::bigint,false,true,true,true,true,ARRAY['web']);
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES((x->>'organization')::bigint,true,1,'fixture','discount conversion');
 UPDATE public.forms SET data=jsonb_build_object('analytics',jsonb_build_object('enabled',true),'payments',jsonb_build_object('bankEnabled',false,'providerConnections',jsonb_build_object('stripe',conn))) WHERE id=(x->>'form')::bigint;
 c:=public.save_discount_code((x->>'occasion')::bigint,'{"code":"CARD10","kind":"percent","value":1000,"isActive":true}');
 source:=jsonb_build_object('tokenHash',encode(extensions.digest(repeat('1',64),'sha256'),'hex'),'returnHash',encode(extensions.digest(repeat('2',64),'sha256'),'hex'),'contentHash',repeat('c',64),'sealed',jsonb_build_object('v','1','iv','fixture','ciphertext','fixture'));
 p:=pg_temp.checkout(x)||jsonb_build_object('payment_method','stripe','payment_type','full','expected_payment_amount_minor',9000,'expected_payment_currency','CZK','stripe_connection_id',conn,'payment_surface','web','stripePaymentSource',source,'discount',jsonb_build_object('code','CARD10'));
 q:=public.quote_order_discount(p);p:=jsonb_set(p,'{discount,fingerprint}',q#>'{quote,fingerprint}');
 PERFORM set_config('request.jwt.claim.sub','',true);
 r:=public.create_ticket_order_client_sync_v1(p,gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200','online discounted order: '||r::text);oid:=(r#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT amount_minor FROM eshop.stripe_checkout_attempts WHERE order_id=oid),9000::bigint,'installed online connector receives net');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),90::numeric,'online order receives same net');
 PERFORM assert_eq(r#>'{data,analytics}','null'::jsonb,'discounted checkout has no conversion before payment');
END $$;

DO $$
DECLARE role_name text; q jsonb;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  PERFORM assert_true(NOT has_column_privilege(role_name,'public.occasions','features','UPDATE'),'feature writes require the canonical fenced owner');
  PERFORM assert_true(NOT has_column_privilege(role_name,'eshop.orders','price','UPDATE'),'direct order price writes denied');
  PERFORM assert_true(NOT has_column_privilege(role_name,'eshop.orders','data','UPDATE'),'direct sale JSON writes denied');
  PERFORM assert_true(NOT has_column_privilege(role_name,'eshop.order_product_ticket','net_price','UPDATE'),'direct net writes denied');
  PERFORM assert_true(NOT has_column_privilege(role_name,'eshop.payment_info','amount','UPDATE'),'direct payment amount writes denied');
 END LOOP;
 q:=public.calculate_order_discount_internal('[{"base":2,"deposit":0,"eligible":true},{"base":3,"deposit":0,"eligible":true}]','percent',5000,0);
 PERFORM assert_eq((q->>'discount')::numeric,3::numeric,'zero-decimal currency rounds once');
 q:=public.calculate_order_discount_internal('[{"base":100,"deposit":0,"eligible":true},{"base":20,"deposit":0,"eligible":false}]','percent',10000,2);
 PERFORM assert_eq((q->>'net')::numeric,20::numeric,'ineligible fee is not discounted');
END $$;
