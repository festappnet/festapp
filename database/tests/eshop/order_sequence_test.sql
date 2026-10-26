DO $$
DECLARE org bigint; u bigint; occ bigint; occ2 bigint; oid bigint; role_name text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Sequence fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Unit',org) RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('A',org,u,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('B',org,u,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ2;
 INSERT INTO eshop.orders(order_symbol,occasion,order_sequence,state) VALUES(public.generate_order_symbol(),occ,public.next_order_sequence(occ),'storno') RETURNING id INTO oid;
 PERFORM assert_eq(public.next_order_sequence(occ),2::bigint,'storno included');
 PERFORM assert_eq(public.next_order_sequence(occ2),1::bigint,'per occasion');
 BEGIN
  INSERT INTO eshop.orders(order_symbol,occasion,order_sequence) VALUES(public.generate_order_symbol(),occ,1);
  RAISE EXCEPTION 'duplicate accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  INSERT INTO eshop.orders(order_symbol,occasion,order_sequence) VALUES(public.generate_order_symbol(),occ,0);
  RAISE EXCEPTION 'zero accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  PERFORM public.next_order_sequence(NULL);
  RAISE EXCEPTION 'NULL occasion accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='NULL occasion accepted' THEN RAISE; END IF;
 END;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM assert_false(has_function_privilege(role_name,'public.next_order_sequence(bigint)','EXECUTE'),'private allocator');
  PERFORM assert_false(has_column_privilege(role_name,'eshop.orders','order_sequence','INSERT'),'RPC-only allocation');
  PERFORM assert_false(has_column_privilege(role_name,'eshop.orders','order_sequence','UPDATE'),'readonly sequence');
 END LOOP;
 PERFORM assert_true(has_column_privilege('service_role','eshop.orders','note_hidden','UPDATE'),'email row-lock privilege');
 PERFORM assert_true(to_regprocedure('public.backfill_order_sequences(bigint)') IS NULL,'temporary helper removed');
 DELETE FROM eshop.orders WHERE id=oid;
 PERFORM assert_eq(public.next_order_sequence(occ),1::bigint,'deleted highest reused');
END $$;
