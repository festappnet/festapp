BEGIN;
DO $$
<<inventory_resource_safety_test>>
DECLARE actor uuid; plain uuid; org bigint; un bigint; oc bigint; foreign_oc bigint; pool_a bigint; pool_b bigint; pool_foreign bigint;
 ctx_a bigint; ctx_b bigint; resource bigint; slot bigint; held bigint; order_id bigint; ticket_id bigint; opt bigint;
 result jsonb; pool_version bigint; original jsonb; payload jsonb; cmd uuid; hold_key uuid:=gen_random_uuid();
BEGIN
 PERFORM public.create_user_for_test('resource-safety','resource-safety@example.invalid');actor:=public.get_user_id('resource-safety');
 PERFORM public.create_user_for_test('resource-viewer','resource-viewer@example.invalid');plain:=public.get_user_id('resource-viewer');
 INSERT INTO public.organizations(title) VALUES('Resource safety') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id IN(actor,plain);
 INSERT INTO public.units(title,organization) VALUES('Resource safety',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Resource safety',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Foreign safety',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO foreign_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(oc,actor,true,true),(oc,plain,false,true);
 INSERT INTO public.inventory_pools(title,occasion) VALUES('A',oc) RETURNING id INTO pool_a;
 INSERT INTO public.inventory_pools(title,occasion) VALUES('B',oc) RETURNING id INTO pool_b;
 INSERT INTO public.inventory_pools(title,occasion) VALUES('Foreign',foreign_oc) RETURNING id INTO pool_foreign;
 INSERT INTO public.inventory_contexts(title,inventory_pool) VALUES('A',pool_a) RETURNING id INTO ctx_a;
 INSERT INTO public.inventory_contexts(title,inventory_pool) VALUES('B',pool_b) RETURNING id INTO ctx_b;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 payload:=jsonb_build_object('title','Resource','capacity',2,'inventory_pool',pool_a,'booking_rules','{}'::jsonb);
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.save_resource_client_sync_v1(oc,gen_random_uuid(),NULL,payload);ASSERT result->>'status'='applied';resource:=(result#>>'{data,resource,id}')::bigint;
 ASSERT public.save_inventory_pool_client_sync_v1(oc,gen_random_uuid(),0,jsonb_build_object('pool',jsonb_build_object('id',pool_a,'occasion',oc,'title','Stale')))->>'status'='conflict';
 EXECUTE 'RESET ROLE';
 INSERT INTO eshop.spots(occasion,inventory_context,resource,secret,secret_expiration_time)
 VALUES(oc,ctx_a,resource,hold_key,now()+interval '1 hour') RETURNING id INTO held;
 payload:=payload||jsonb_build_object('id',resource,'capacity',1);cmd:=gen_random_uuid();
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.save_resource_client_sync_v1(oc,cmd,1,payload);ASSERT result->>'status'='applied';ASSERT result#>>'{data,version}'='2';
 ASSERT public.save_resource_client_sync_v1(oc,cmd,1,payload)=result;
 result:=public.save_resource_client_sync_v1(oc,gen_random_uuid(),2,payload||jsonb_build_object('capacity',0));ASSERT result->>'status'='rejected',result::text;
 result:=public.delete_resource_client_sync_v1(oc,resource,gen_random_uuid(),2);ASSERT result->>'status'='rejected',result::text;ASSERT result::text NOT LIKE '%'||hold_key::text||'%',result::text;
 result:=public.save_resource_client_sync_v1(oc,gen_random_uuid(),2,payload||jsonb_build_object('inventory_pool',pool_b));ASSERT result->>'status'='rejected',result::text;
 EXECUTE 'RESET ROLE';
 ASSERT (SELECT inventory_pool=pool_a AND capacity=1 FROM public.resources WHERE id=inventory_resource_safety_test.resource);
 ASSERT (SELECT secret=hold_key FROM eshop.spots WHERE id=held);
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=held;
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.save_resource_client_sync_v1(oc,gen_random_uuid(),2,payload||jsonb_build_object('inventory_pool',pool_b));ASSERT result->>'status'='applied';ASSERT result#>>'{data,version}'='3';
 EXECUTE 'RESET ROLE';
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.spots WHERE inventory_context=ctx_a), 'old pool must be reconciled';
 ASSERT (SELECT count(*)=1 FROM eshop.spots WHERE inventory_context=ctx_b), 'new generic capacity created';
 INSERT INTO public.resource_slots(resource,title) VALUES(resource,'Slot') RETURNING id INTO slot;
 INSERT INTO eshop.spots(occasion,inventory_context,resource_slot,secret,secret_expiration_time) VALUES(oc,NULL,slot,hold_key,now()+interval '1 hour') RETURNING id INTO held;
 EXECUTE 'SET LOCAL ROLE authenticated';
 ASSERT public.delete_inventory_pool_client_sync_v1(oc,pool_b,gen_random_uuid(),1)->>'status'='rejected';
 ASSERT public.delete_resource_client_sync_v1(oc,resource,gen_random_uuid(),3)->>'status'='rejected';
 ASSERT public.save_resource_client_sync_v1(oc,gen_random_uuid(),3,payload||jsonb_build_object('inventory_pool',pool_a))->>'status'='rejected';
 EXECUTE 'RESET ROLE';
 UPDATE eshop.spots SET secret_expiration_time=now()-interval '1 second' WHERE id=held;
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.delete_resource_client_sync_v1(oc,resource,gen_random_uuid(),3);ASSERT result->>'status'='applied';
 EXECUTE 'RESET ROLE';
 ASSERT NOT EXISTS(SELECT 1 FROM public.resource_slots WHERE id=slot);
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.spots WHERE inventory_context=ctx_b);
 SELECT (public.get_inventory_pool_bundle(pool_a)->>'aggregate_version')::bigint INTO pool_version;
 ASSERT pool_version=3, 'create, capacity change and move advance the original pool version';
 -- Pool context removal is atomic even if public metadata was updated first.
 INSERT INTO eshop.spots(occasion,inventory_context,secret,secret_expiration_time) VALUES(oc,ctx_a,hold_key,now()+interval '1 hour') RETURNING id INTO held;
 BEGIN
  PERFORM public.save_inventory_pool_client_sync_v1(oc,gen_random_uuid(),pool_version,jsonb_build_object('pool',jsonb_build_object('id',pool_a,'occasion',oc,'title','Must roll back'),'contexts','[]'::jsonb));
  RAISE EXCEPTION 'held context deleted';
 EXCEPTION WHEN check_violation THEN NULL;END;
 ASSERT (SELECT title='A' FROM public.inventory_pools WHERE id=pool_a);
 ASSERT EXISTS(SELECT 1 FROM public.inventory_contexts WHERE id=ctx_a);
 ASSERT public.delete_inventory_pool_client_sync_v1(oc,pool_a,gen_random_uuid(),pool_version)->>'status'='rejected';
 UPDATE eshop.spots SET secret_expiration_time=now()-interval '1 second' WHERE id=held;
 ASSERT public.delete_inventory_pool_client_sync_v1(oc,pool_a,gen_random_uuid(),pool_version)->>'status'='applied';
 -- Sold spots are protected by the same capacity/move/delete guard.
 payload:=jsonb_build_object('title','Sold','capacity',1,'inventory_pool',pool_b,'booking_rules','{}'::jsonb);
 result:=public.save_resource_client_sync_v1(oc,gen_random_uuid(),NULL,payload);resource:=(result#>>'{data,resource,id}')::bigint;
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state) VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'ordered') RETURNING id INTO order_id;
 INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered') RETURNING id INTO ticket_id;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(order_id,ticket_id) RETURNING id INTO opt;
 UPDATE eshop.spots SET order_product_ticket=opt,resource=inventory_resource_safety_test.resource
 WHERE id=(SELECT id FROM eshop.spots WHERE inventory_context=ctx_b AND spots.resource IS NULL LIMIT 1);
 ASSERT public.delete_resource_client_sync_v1(oc,resource,gen_random_uuid(),1)->>'status'='rejected';
 ASSERT public.save_resource_client_sync_v1(oc,gen_random_uuid(),1,payload||jsonb_build_object('id',resource,'capacity',0))->>'status'='rejected';
 BEGIN PERFORM public.save_resource_client_sync_v1(oc,gen_random_uuid(),1,payload||jsonb_build_object('id',resource,'inventory_pool',pool_foreign));RAISE EXCEPTION 'foreign pool accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',plain::text,true);
 BEGIN PERFORM public.save_resource_client_sync_v1(oc,gen_random_uuid(),NULL,payload);RAISE EXCEPTION 'viewer wrote resource';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT NOT has_function_privilege('authenticated','public.lock_resource_pools_internal_v1(bigint,bigint)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.adjust_spot_capacity_for_pool(bigint)','EXECUTE');
 ASSERT NOT has_table_privilege('authenticated','public.resources','UPDATE');
END $$;
ROLLBACK;
