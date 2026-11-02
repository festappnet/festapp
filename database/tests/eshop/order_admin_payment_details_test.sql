-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/functions/eshop_orders/get_order_admin_detail.sql
-- test-setup: database/functions/eshop_orders/get_order_blueprint_view.sql
DO $$
DECLARE f jsonb; oc bigint; oid bigint; account_id bigint; payment_id bigint; result jsonb;
 reader uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); before_payment jsonb; expected_reference text; stripe_id uuid;
BEGIN
 f:=public.blueprint_test_fixture_internal(); oc:=(f->>'occasion')::bigint;
 oid:=public.allocate_ticket_order_identity_internal((f->>'form')::bigint);
 INSERT INTO auth.users(id) VALUES(reader),(outsider);
 INSERT INTO public.user_info(id,organization) SELECT reader,organization FROM public.occasions WHERE id=oc;
 INSERT INTO public.user_info(id,organization) SELECT outsider,organization FROM public.occasions WHERE id=oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor_order,is_editor)
 VALUES(oc,reader,true,false,false);
 INSERT INTO eshop.bank_accounts(account_number,account_number_human_readable,creditor_name)
 VALUES('CZ6508000000192000145399','19-2000145399/0800','Fixture organizer') RETURNING id INTO account_id;
 INSERT INTO eshop.payment_info(bank_account,payment_method,amount,paid,returned,currency_code,variable_symbol,deadline)
 VALUES(account_id,'bank',100,100,0,'CZK',3629,'2026-10-15T12:00:00Z') RETURNING id INTO payment_id;
 UPDATE eshop.orders SET payment_info=payment_id,state='paid',price=100,currency_code='CZK' WHERE id=oid;
 SELECT to_jsonb(p) INTO before_payment FROM eshop.payment_info p WHERE id=payment_id;
 PERFORM set_config('request.jwt.claim.sub',reader::text,true);
 SET LOCAL ROLE authenticated;
 result:=public.get_order_admin_detail(oid,oc);
 PERFORM assert_eq(result#>>'{data,bankPaymentDetails,account}','19-2000145399/0800','paid order keeps receiving account');
 PERFORM assert_eq(result#>>'{data,bankPaymentDetails,reference}','3629','actual payment reference, never order symbol');
 PERFORM assert_eq(result#>>'{data,bankPaymentDetails,referenceKind}','VS','CZK uses variable symbol');
 PERFORM assert_false((result#>'{data,bankPaymentDetails}') ? 'token','no bank credentials');
 PERFORM assert_eq(public.get_order_admin_detail(oid,oc+9999)->>'code','404','wrong occasion cannot read bank metadata');
 RESET ROLE;
 PERFORM assert_eq((SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=payment_id),before_payment,'viewing never issues instructions or changes payment');
 UPDATE eshop.payment_info SET currency_code='EUR',creditor_reference=public.generate_creditor_reference(variable_symbol) WHERE id=payment_id;
 SET LOCAL ROLE authenticated;
 result:=public.get_order_admin_detail(oid,oc);
 PERFORM assert_true(result#>'{data,bankPaymentDetails}'='null'::jsonb,'currency mismatch never advertises payment instructions');
 RESET ROLE;
 UPDATE eshop.orders SET currency_code='EUR' WHERE id=oid;
 SELECT creditor_reference INTO expected_reference FROM eshop.payment_info WHERE id=payment_id;
 SET LOCAL ROLE authenticated;
 result:=public.get_order_admin_detail(oid,oc);
 PERFORM assert_eq(result#>>'{data,bankPaymentDetails,referenceKind}','RF','EUR retains creditor reference');
 PERFORM assert_eq(result#>>'{data,bankPaymentDetails,reference}',expected_reference,'stored RF is retained');
 RESET ROLE;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
 SELECT organization,unit,'acct_paymentDetailsFixture'||oid,false,'connected' FROM public.occasions WHERE id=oc RETURNING id INTO stripe_id;
 UPDATE eshop.payment_info SET payment_method='stripe',stripe_connection_id=stripe_id,bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL WHERE id=payment_id;
 SET LOCAL ROLE authenticated;
 result:=public.get_order_admin_detail(oid,oc);
 PERFORM assert_true(result#>'{data,bankPaymentDetails}'='null'::jsonb,'card never displays bank instructions');
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 SET LOCAL ROLE authenticated;
 PERFORM assert_eq(public.get_order_admin_detail(oid,oc)->>'code','404','unrelated reader receives no bank metadata');
 RESET ROLE;
END $$;
