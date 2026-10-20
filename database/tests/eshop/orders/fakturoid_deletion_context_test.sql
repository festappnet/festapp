DO $$
DECLARE
  actor uuid := gen_random_uuid(); org bigint; un bigint; oc bigint;
  pi bigint; ord bigint; result jsonb; cmd uuid:=gen_random_uuid();
BEGIN
  INSERT INTO public.organizations(title) VALUES ('Invoice deletion test') RETURNING id INTO org;
  INSERT INTO public.units(organization,title) VALUES (org,'Invoice deletion') RETURNING id INTO un;
  INSERT INTO auth.users(id,email) VALUES (actor,actor::text || '@example.test');
  INSERT INTO public.user_info(id,email_readonly) VALUES (actor,actor::text || '@example.test');
  INSERT INTO public.unit_users(unit,"user",is_manager) VALUES (un,actor,true);
  INSERT INTO public.occasions(unit,title,link,start_time,end_time)
    VALUES (un,'Delete test','invoice-delete-' || actor::text,now(),now()+interval '1 day') RETURNING id INTO oc;
  INSERT INTO eshop.payment_info(variable_symbol,amount,paid,currency_code)
    VALUES (4288,100,0,'CZK') RETURNING id INTO pi;
  INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,payment_info,state,price,currency_code)
    VALUES (public.next_order_sequence(oc),public.generate_order_symbol(),oc,pi,'storno',100,'CZK') RETURNING id INTO ord;
  ASSERT NOT has_function_privilege('anon','public.get_order_deletion_context_v1(bigint,uuid)','EXECUTE');
  ASSERT has_function_privilege('authenticated','public.get_order_deletion_context_v1(bigint,uuid)','EXECUTE');
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  result:=public.get_order_deletion_context_v1(ord);
  ASSERT result->>'hasFakturoid'='false';
  INSERT INTO eshop.external_services(type,unit,data)
    VALUES ('FAKTUROID',un,'{"client_secret":"never expose"}');
  result:=public.get_order_deletion_context_v1(ord);
  ASSERT result->>'hasFakturoid'='true';
  ASSERT result->>'variableSymbol'='4288';
  ASSERT NOT result::text LIKE '%never expose%';
  ASSERT EXISTS(SELECT FROM eshop.orders WHERE id=ord), 'Preflight deleted an order';
  PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  BEGIN
    PERFORM public.get_order_deletion_context_v1(ord);
    RAISE EXCEPTION 'Unauthorized preflight succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  UPDATE public.unit_users SET is_manager=false,is_editor=true WHERE unit=un AND "user"=actor;
  ASSERT public.get_order_deletion_context_v1(ord)->>'hasFakturoid'='true';
  UPDATE eshop.orders SET state='preparing_payment' WHERE id=ord;
  BEGIN
    PERFORM public.get_order_deletion_context_v1(ord);
    RAISE EXCEPTION 'Preparing order preflight succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'ORDER_HAS_WAITLIST_HISTORY' THEN RAISE; END IF;
  END;
  UPDATE eshop.orders SET state='storno' WHERE id=ord;
  result:=public.delete_order_client_sync_v1(ord,cmd);
  ASSERT result->>'code'='200';
  ASSERT public.get_order_deletion_context_v1(ord,cmd)->'response'=result,
    'Lost deletion response cannot be recovered';
  BEGIN
    PERFORM public.get_order_deletion_context_v1(ord+1,cmd);
    RAISE EXCEPTION 'Receipt replay accepted another order';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  BEGIN
    PERFORM public.get_order_deletion_context_v1(ord,cmd);
    RAISE EXCEPTION 'Receipt leaked to another actor';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
