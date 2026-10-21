-- test-setup: database/tests/blueprint/fixtures.sql

DO $$
DECLARE f jsonb; req jsonb; r jsonb; pool bigint; context_id bigint; resource_id bigint; area uuid:=gen_random_uuid(); availability jsonb; opt bigint; oid bigint; tid bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal(); req:=f->'request'; PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES((f->>'occasion')::bigint,'Standing','generic',5) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Standing') RETURNING id INTO context_id;
 INSERT INTO public.resources(inventory_pool,occasion,title,capacity) VALUES(pool,(f->>'occasion')::bigint,'Standing supply',5) RETURNING id INTO resource_id;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES((f->>'product')::bigint,context_id,1);
 PERFORM public.adjust_spot_capacity_for_pool(pool);
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object('id',area,'kind','capacityArea','width',100,'height',100,'transform',jsonb_build_object('x',400,'y',400,'rotation',0))));
 req:=jsonb_set(req,'{areaBindingChanges}',jsonb_build_array(jsonb_build_object('nodeId',area,'productId',(f->>'product')::bigint,'inventoryContextId',context_id,'operation','upsert','capacity',4)));
 req:=req||jsonb_build_object('textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(req->'layout',(f->>'occasion')::bigint)));
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid()); PERFORM public.assert_eq(r->>'status','applied','standing save');
 availability:=public.blueprint_area_availability_internal((f->>'blueprint')::bigint,(f->>'form')::bigint);
 PERFORM public.assert_eq((availability#>>'{0,capacity}')::int,4,'capacity from pool cap and supply');
 PERFORM public.assert_eq((availability#>>'{0,available}')::int,4,'standing available initial');
 oid:=public.allocate_ticket_order_identity_internal((f->>'form')::bigint);
 INSERT INTO eshop.tickets(occasion,state) VALUES((f->>'occasion')::bigint,'ordered') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,(f->>'product')::bigint) RETURNING id INTO opt;
 UPDATE eshop.spots SET order_product_ticket=opt WHERE id IN(SELECT id FROM eshop.spots WHERE inventory_context=context_id ORDER BY id LIMIT 2);
 availability:=public.blueprint_area_availability_internal((f->>'blueprint')::bigint,(f->>'form')::bigint);
 PERFORM public.assert_eq((availability#>>'{0,available}')::int,2,'standing counts existing allocations');
 req:=jsonb_set(req,'{expected_layout_revision}','1'); req:=jsonb_set(req,'{seatChanges}','[]');req:=jsonb_set(req,'{areaBindingChanges,0,capacity}','1');
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 PERFORM public.assert_eq(r#>>'{data,reason}','INVENTORY_CAPACITY_BELOW_COMMITTED','capacity decrease protected');
 PERFORM public.assert_eq((SELECT sellable_capacity::int FROM public.inventory_pools WHERE id=pool),4,'capacity rollback');
 UPDATE eshop.products SET maximum=2 WHERE id=(f->>'product')::bigint;
 availability:=public.blueprint_area_availability_internal((f->>'blueprint')::bigint,(f->>'form')::bigint);
 PERFORM public.assert_eq((availability#>>'{0,available}')::int,1,'minimum product remaining and inventory');
 UPDATE eshop.product_inventory_contexts SET quantity=2 WHERE product=(f->>'product')::bigint;
 UPDATE eshop.products SET maximum=NULL WHERE id=(f->>'product')::bigint;
 availability:=public.blueprint_area_availability_internal((f->>'blueprint')::bigint,(f->>'form')::bigint);
 PERFORM public.assert_eq((availability#>>'{0,available}')::int,1,'context quantity respected');
 -- Whole-text registration, immutable descriptors and authorization are covered
 -- by canonical_text_resources_test.sql. The mutable per-glyph RPC is removed.
 PERFORM public.assert_true(to_regprocedure('public.register_blueprint_layout_font(text,jsonb)') IS NULL,'obsolete outline writer removed');
END $$;
