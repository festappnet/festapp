-- Owner fixtures, rolled back by the existing runner. No public test switch.
DO $$
DECLARE s text; org bigint; u bigint; occ bigint; occ2 bigint; oid bigint; before_row jsonb; c text;
BEGIN
 FOR i IN 1..2000 LOOP
  s := public.generate_order_symbol();
  PERFORM assert_true(s ~ '^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$', '10 continuous alphabet characters');
 END LOOP;
 INSERT INTO public.organizations(title) VALUES('Order symbol A') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Unit A',org) RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('A',org,u,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.organizations(title) VALUES('Order symbol B') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Unit B',org) RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('B',org,u,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ2;
 INSERT INTO eshop.orders(order_sequence, order_symbol,occasion,state,data,price) VALUES(public.next_order_sequence(occ), '7G4K9M2R6A',occ,'ordered','{"note":"unchanged"}',0) RETURNING id INTO oid;
 BEGIN
  INSERT INTO eshop.orders(order_sequence, order_symbol,occasion) VALUES(public.next_order_sequence(occ2), '7G4K9M2R6A',occ2);
  RAISE EXCEPTION 'duplicate accepted';
 EXCEPTION WHEN unique_violation THEN
  GET STACKED DIAGNOSTICS c=CONSTRAINT_NAME;
  PERFORM assert_eq(c,'orders_order_symbol_key','global named constraint across tenants');
 END;
 FOREACH s IN ARRAY ARRAY['7G4K9M2R6A ', '7G-4K-9M-2R-6A','0G4K9M2R6A','7O4K9M2R6A','7g4k9m2r6a'] LOOP
  BEGIN
   INSERT INTO eshop.orders(order_sequence, order_symbol,occasion) VALUES(public.next_order_sequence(occ), s,occ);
   RAISE EXCEPTION 'invalid symbol accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
 END LOOP;
 FOREACH s IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM assert_false(has_table_privilege(s,'eshop.orders','INSERT'),'RPC-only creation');
  PERFORM assert_false(has_table_privilege(s,'eshop.orders','UPDATE'),'no table UPDATE bypass');
  PERFORM assert_false(has_column_privilege(s,'eshop.orders','order_symbol','UPDATE'),'identity immutable for API roles');
  PERFORM assert_false(has_function_privilege(s,'public.generate_order_symbol()','EXECUTE'),'generator private');
 END LOOP;
 SET LOCAL ROLE authenticated;
 BEGIN
  UPDATE eshop.orders SET order_symbol='8A8C8E8F8G' WHERE id=oid;
  RAISE EXCEPTION 'direct symbol mutation allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO eshop.orders(order_sequence, order_symbol,occasion) VALUES(public.next_order_sequence(occ), '8A8C8E8F8G',occ) ON CONFLICT(order_symbol) DO UPDATE SET order_symbol=excluded.order_symbol;
  RAISE EXCEPTION 'direct upsert allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 UPDATE eshop.orders SET state='storno',data=data||'{"note":"edited"}'::jsonb WHERE id=oid;
 PERFORM assert_eq((SELECT order_symbol FROM eshop.orders WHERE id=oid),'7G4K9M2R6A','state/note edit preserves symbol');
 PERFORM assert_true(public.read_order_identity(oid,occ2,org) IS NULL,'foreign scope cannot expose symbol');
 PERFORM assert_true(to_regprocedure('public.backfill_order_symbols(bigint[])') IS NULL,'migration setter retired');
END $$;
