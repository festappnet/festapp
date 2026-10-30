-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
CREATE FUNCTION pg_temp.free_payment_fixture(p_currency text DEFAULT 'CZK') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE x jsonb:=pg_temp.payment_fixture(); reply jsonb; oid bigint; ticket_id bigint; pi bigint; form_key uuid;
BEGIN
 UPDATE eshop.products SET price=0,currency_code=p_currency WHERE id=(x->>'product')::bigint;
 SELECT key INTO form_key FROM public.forms WHERE id=(x->>'form')::bigint;
 SET LOCAL ROLE authenticated;
 reply:=public.create_ticket_order_client_sync_v1(jsonb_build_object('form',form_key,
   'email','free-to-payable-'||gen_random_uuid()||'@example.invalid','ticket',jsonb_build_array(
     jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))),gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(reply#>>'{data,code}','200','Free-origin checkout succeeds');
 oid:=(reply#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO pi FROM eshop.orders WHERE id=oid;
 SELECT DISTINCT opt.ticket INTO STRICT ticket_id FROM eshop.order_product_ticket opt WHERE opt."order"=oid;
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','Free origin is paid');
 PERFORM assert_true((SELECT variable_symbol IS NULL AND bank_account IS NULL FROM eshop.payment_info WHERE id=pi),'Free origin has no payment identity');
 x:=x||jsonb_build_object('order',oid,'ticket',ticket_id,'payment',pi);
 RETURN x;
END $$;

DO $$
DECLARE x jsonb:=pg_temp.free_payment_fixture(); oid bigint:=(x->>'order')::bigint;
 pi bigint:=(x->>'payment')::bigint; symbol bigint;
BEGIN
 PERFORM pg_temp.payment_edit(x,1000);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','Payable edit creates unpaid balance');
 PERFORM assert_eq((SELECT bank_account FROM eshop.payment_info WHERE id=pi),(x->>'bank')::bigint,'Payable edit resolves receiving account');
 SELECT variable_symbol INTO symbol FROM eshop.payment_info WHERE id=pi;
 PERFORM assert_true(symbol IS NOT NULL,'Payable edit allocates its payment reference');
 PERFORM pg_temp.payment_edit(x,0);
 PERFORM pg_temp.payment_edit(x,1500);
 PERFORM assert_eq((SELECT variable_symbol FROM eshop.payment_info WHERE id=pi),symbol,'Repricing reuses the issued reference');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.free_payment_fixture(); oid bigint:=(x->>'order')::bigint;
 pi bigint:=(x->>'payment')::bigint; snapshot jsonb; rejected boolean:=false;
BEGIN
 DELETE FROM eshop.unit_bank_accounts WHERE bank_account=(x->>'bank')::bigint;
 UPDATE public.forms SET bank_account=NULL WHERE id=(x->>'form')::bigint;
 snapshot:=jsonb_build_object('order',(SELECT to_jsonb(o) FROM eshop.orders o WHERE id=oid),
   'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=pi),'history',pg_temp.payment_history(oid));
 BEGIN
   PERFORM pg_temp.payment_edit(x,1000);
 EXCEPTION WHEN OTHERS THEN
   IF position('No available bank account' in SQLERRM)>0 THEN rejected:=true; ELSE RAISE; END IF;
 END;
 PERFORM assert_true(rejected,'Missing receiving account refuses repricing');
 PERFORM assert_eq(jsonb_build_object('order',(SELECT to_jsonb(o) FROM eshop.orders o WHERE id=oid),
   'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=pi),'history',pg_temp.payment_history(oid)),snapshot,
   'Failed payable edit leaves the original free order unchanged');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.free_payment_fixture('EUR'); pi bigint:=(x->>'payment')::bigint;
BEGIN
 UPDATE eshop.bank_accounts SET supported_currencies=ARRAY['CZK','EUR'],account_number='DE89370400440532013000'
 WHERE id=(x->>'bank')::bigint;
 PERFORM pg_temp.payment_edit(x,20);
 PERFORM assert_true((SELECT creditor_reference IS NOT NULL AND public.is_valid_creditor_reference(creditor_reference)
   FROM eshop.payment_info WHERE id=pi),'EUR payable edit issues a valid creditor reference');
 PERFORM assert_true(NOT has_function_privilege('authenticated',
   'public.ensure_order_payment_instructions_internal(bigint)','EXECUTE'),'instruction owner stays private');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.free_payment_fixture(); pi bigint:=(x->>'payment')::bigint;
 ns text; symbol bigint;
BEGIN
 UPDATE eshop.bank_accounts SET account_number='19-2000145399/0800' WHERE id=(x->>'bank')::bigint;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 ns:=public.enroll_payment_reference_account((x->>'bank')::bigint);
 INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256)
 VALUES((x->>'organization')::bigint,'active',repeat('a',64));
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true WHERE id=ns;
 PERFORM pg_temp.payment_edit(x,1000);
 SELECT variable_symbol INTO symbol FROM eshop.payment_info WHERE id=pi;
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations WHERE payment_info_id=pi),1::bigint,
   'Free-to-payable edit uses the physical account reservation registry');
 PERFORM pg_temp.payment_edit(x,0);
 PERFORM pg_temp.payment_edit(x,1500);
 PERFORM assert_eq((SELECT variable_symbol FROM eshop.payment_info WHERE id=pi),symbol,'Registry reference is immutable across repricing');
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations WHERE payment_info_id=pi),1::bigint,
   'Repeated repricing never reserves a duplicate');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.free_payment_fixture(); rejected boolean:=false;
BEGIN
 UPDATE public.forms SET data=jsonb_build_object('payments',jsonb_build_object('bankEnabled',false))
 WHERE id=(x->>'form')::bigint;
 BEGIN
   PERFORM pg_temp.payment_edit(x,1000);
 EXCEPTION WHEN OTHERS THEN
   IF position('BANK_PAYMENT_NOT_CONFIGURED' in SQLERRM)>0 THEN rejected:=true; ELSE RAISE; END IF;
 END;
 PERFORM assert_true(rejected,'Repricing respects disabled bank payments');
 PERFORM assert_true((SELECT amount=0 AND variable_symbol IS NULL AND bank_account IS NULL
   FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),'Disabled payment method leaves free order untouched');
END $$;
