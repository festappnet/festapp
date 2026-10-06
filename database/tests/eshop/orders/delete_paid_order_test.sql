-- Paid-order deletion must preserve the imported bank transaction.
DO $$
DECLARE
  actor uuid := gen_random_uuid(); org bigint; unit_id bigint; oc bigint;
  bank bigint; pi bigint; ord bigint; tx bigint; result jsonb;
BEGIN
  INSERT INTO public.organizations(title) VALUES ('Delete paid order test') RETURNING id INTO org;
  INSERT INTO public.units(organization,title) VALUES (org,'Delete test') RETURNING id INTO unit_id;
  INSERT INTO auth.users(id,email) VALUES (actor,actor::text || '@example.test');
  INSERT INTO public.user_info(id,email_readonly) VALUES (actor,actor::text || '@example.test');
  INSERT INTO public.unit_users(unit,"user",is_manager) VALUES (unit_id,actor,true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  INSERT INTO public.occasions(unit,title,link,start_time,end_time)
    VALUES (unit_id,'Delete test','delete-' || actor::text,now(),now()+interval '1 day') RETURNING id INTO oc;
  INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies)
    VALUES ('Delete test','delete-' || actor::text,'FIO',ARRAY['CZK']) RETURNING id INTO bank;
  INSERT INTO eshop.payment_info(variable_symbol,amount,paid,currency_code,bank_account)
    VALUES (4288,100,100,'CZK',bank) RETURNING id INTO pi;
  INSERT INTO eshop.orders(order_symbol, occasion,payment_info,state,price,currency_code)
    VALUES (public.generate_order_symbol(), oc,pi,'paid',100,'CZK') RETURNING id INTO ord;
  INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,vs,date)
    VALUES (bank,pi,100,'CZK','4288',now()) RETURNING id INTO tx;
  -- A caller without unit-manager rights must not detach or delete anything.
  PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  BEGIN
    PERFORM public.delete_order_client_sync_v1(ord,gen_random_uuid());
    RAISE EXCEPTION 'Unauthorized deletion succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  ASSERT EXISTS(SELECT FROM eshop.orders WHERE id=ord), 'Unauthorized caller removed order';
  ASSERT EXISTS(SELECT FROM eshop.transactions WHERE id=tx AND payment_info=pi), 'Unauthorized caller detached payment';
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  result := public.delete_order_client_sync_v1(ord,gen_random_uuid());
  ASSERT (result->>'code')::int = 200, 'Deletion command rejected';
  ASSERT NOT EXISTS(SELECT FROM eshop.orders WHERE id=ord), 'Order remains after deletion';
  ASSERT NOT EXISTS(SELECT FROM eshop.payment_info WHERE id=pi), 'Payment info remains';
  ASSERT EXISTS(SELECT FROM eshop.transactions WHERE id=tx AND payment_info IS NULL AND amount=100 AND vs='4288'),
    'Imported transaction must remain with its amount/reference and no deleted payment link';
END $$;
