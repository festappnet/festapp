DO $$
<<product_inventory_save_test>>
DECLARE actor uuid; org bigint; un bigint; oc bigint; foreign_oc bigint; pt bigint; product bigint;
 pool bigint; context bigint; foreign_pool bigint; foreign_context bigint; result jsonb; payload jsonb; cmd uuid:=gen_random_uuid();
BEGIN
 PERFORM public.create_user_for_test('atomic-product','atomic-product@example.invalid');actor:=public.get_user_id('atomic-product');
 INSERT INTO public.organizations(title) VALUES('Atomic product') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Atomic product',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Atomic product',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Foreign product',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO foreign_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,actor,true);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,price,currency_code,occasion,product_type) VALUES('Original',10,'CZK',oc,pt) RETURNING id INTO product;
 INSERT INTO public.inventory_pools(title,occasion) VALUES('Pool',oc) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(title,inventory_pool) VALUES('Context',pool) RETURNING id INTO context;
 INSERT INTO public.inventory_pools(title,occasion) VALUES('Foreign pool',foreign_oc) RETURNING id INTO foreign_pool;
 INSERT INTO public.inventory_contexts(title,inventory_pool) VALUES('Foreign context',foreign_pool) RETURNING id INTO foreign_context;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 payload:=jsonb_build_object('id',product,'title','Must roll back','inventory_contexts',jsonb_build_array(jsonb_build_object('inventory_context_id',foreign_context,'quantity',1)));
 BEGIN PERFORM public.update_product_client_sync_v1(payload,cmd); RAISE EXCEPTION 'foreign context accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 ASSERT (SELECT title='Original' FROM eshop.products WHERE id=product);
 ASSERT NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=cmd);
 payload:=jsonb_set(payload,'{inventory_contexts}',jsonb_build_array(jsonb_build_object('inventory_context_id',context,'quantity',2)));
 result:=public.update_product_client_sync_v1(payload,cmd);
 ASSERT result->>'code'='200';ASSERT public.update_product_client_sync_v1(payload,cmd)=result;
 ASSERT (SELECT quantity=2 FROM eshop.product_inventory_contexts pic WHERE pic.product=product_inventory_save_test.product);
 PERFORM public.update_product_client_sync_v1(jsonb_build_object('id',product,'title','Omitted'),gen_random_uuid());
 ASSERT (SELECT count(*)=1 FROM eshop.product_inventory_contexts pic WHERE pic.product=product_inventory_save_test.product);
 PERFORM public.update_product_client_sync_v1(jsonb_build_object('id',product,'inventory_contexts','[]'::jsonb),gen_random_uuid());
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product=product_inventory_save_test.product);
END $$;
