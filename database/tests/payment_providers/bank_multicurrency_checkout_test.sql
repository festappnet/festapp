-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); f bigint:=(x->>'form')::bigint;
 eur_bank bigint; eur_product bigint; result jsonb; bundle jsonb; payload jsonb; currency text; expected_bank bigint;
BEGIN
 UPDATE eshop.bank_accounts SET account_number='CZ6508000000192000145399' WHERE id=(x->>'bank')::bigint;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
 VALUES('Eurový účet','FIO','CZ6508000000192000145399',ARRAY['EUR']) RETURNING id INTO eur_bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account)
 SELECT unit,eur_bank FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion,is_hidden)
 SELECT 'Vstupné EUR',product_type,187,'EUR',occasion,false FROM eshop.products WHERE id=(x->>'product')::bigint
 RETURNING id INTO eur_product;
 UPDATE public.forms SET bank_account=NULL WHERE id=f;
 PERFORM public.reserve_public_link_internal('form',f,x->>'link',true);
 SET LOCAL ROLE anon;
 bundle:=public.get_form_by_link(jsonb_build_object('form_link',x->>'link','client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb))::jsonb;
 RESET ROLE;
 PERFORM assert_eq(bundle->>'code','200','anonymous public form loads');
 PERFORM assert_true(bundle#>'{data,payments,available}' ? 'bank','separate CZK/EUR accounts keep bank checkout available');
 FOREACH currency IN ARRAY ARRAY['CZK','EUR'] LOOP
  expected_bank:=CASE WHEN currency='CZK' THEN (x->>'bank')::bigint ELSE eur_bank END;
  payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=f),'email','multicurrency@example.invalid',
   'payment_method','bank','client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb,
   'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',
    CASE WHEN currency='CZK' THEN (x->>'product')::bigint ELSE eur_product END)))));
  SET LOCAL ROLE anon;
  result:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),gen_random_uuid());
  RESET ROLE;
  PERFORM assert_eq(result->>'status','applied',currency||' anonymous checkout succeeds: '||result::text);
  PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
   WHERE o.id=(result#>>'{data,order,id}')::bigint AND pi.bank_account=expected_bank AND trim(pi.currency_code)=currency
    AND pi.variable_symbol IS NOT NULL),currency||' checkout issues instructions for the correct receiving account');
 END LOOP;
 -- An explicit account cannot borrow another account's currency capabilities.
 UPDATE public.forms SET bank_account=(x->>'bank')::bigint WHERE id=f;
 PERFORM assert_false(public.form_payment_availability_internal(f)->'available' ? 'bank','pinned CZK account cannot collect EUR');
 UPDATE public.forms SET bank_account=NULL WHERE id=f;
 DELETE FROM eshop.unit_bank_accounts WHERE bank_account=eur_bank;
 PERFORM assert_false(public.form_payment_availability_internal(f)->'available' ? 'bank','missing currency coverage still fails closed');
END $$;
