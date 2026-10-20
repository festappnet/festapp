-- test-setup: database/tests/blueprint/fixtures.sql
BEGIN;
DO $$
DECLARE f jsonb; req jsonb; r jsonb; pool bigint; ctx bigint; resource bigint; area uuid:=gen_random_uuid();
 standing bigint; seat bigint; bank bigint; order_id bigint; foreign_bp bigint; foreign_spot bigint;
 secret uuid:=gen_random_uuid(); payload jsonb; node uuid;
BEGIN
 f:=public.blueprint_test_fixture_internal();req:=f->'request';
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code)
 SELECT occasion,product_type,'Blueprint standing',50,'CZK' FROM eshop.products WHERE id=(f->>'product')::bigint RETURNING id INTO standing;
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES((f->>'occasion')::bigint,'Standing','generic',3) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Standing') RETURNING id INTO ctx;
 INSERT INTO public.resources(inventory_pool,occasion,title,capacity) VALUES(pool,(f->>'occasion')::bigint,'Standing supply',3) RETURNING id INTO resource;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(standing,ctx,1);
 PERFORM public.adjust_spot_capacity_for_pool(pool);
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object('id',area,'kind','capacityArea','width',100,'height',100,'transform',jsonb_build_object('x',400,'y',400,'rotation',0))));
 req:=jsonb_set(req,'{areaBindingChanges}',jsonb_build_array(jsonb_build_object('nodeId',area,'productId',standing,'inventoryContextId',ctx,'operation','upsert','capacity',3)));
 req:=req||jsonb_build_object('textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(req->'layout',(f->>'occasion')::bigint)));
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','seat and capacity bindings saved');
 DELETE FROM public.form_fields WHERE form=(f->>'form')::bigint;
 INSERT INTO eshop.bank_accounts(title,account_number,type,is_fetch_enabled,supported_currencies) VALUES('Test only','123456/0100','FIO',false,ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) SELECT unit,bank,1 FROM public.occasions WHERE id=(f->>'occasion')::bigint;
 UPDATE public.forms SET bank_account=bank WHERE id=(f->>'form')::bigint;
 SELECT id INTO seat FROM eshop.spots WHERE blueprint=(f->>'blueprint')::bigint ORDER BY id LIMIT 1;
 -- A held seat in another blueprint of the same occasion is still unrelated.
 INSERT INTO eshop.blueprints(occasion,organization,title,objects,layout)
 SELECT occasion,organization,'Other blueprint','[]',layout FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint RETURNING id INTO foreign_bp;
 INSERT INTO eshop.spots(occasion,blueprint,title,product,secret,secret_expiration_time)
 VALUES((f->>'occasion')::bigint,foreign_bp,'Foreign seat',(f->>'product')::bigint,secret,now()+interval '10 minutes') RETURNING id INTO foreign_spot;
 node:=(req#>>'{seatChanges,0,nodeId}')::uuid;
 INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot) VALUES(foreign_bp,node,foreign_spot);
 order_id:=public.allocate_ticket_order_identity_internal((f->>'form')::bigint);
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','anon',true);
 r:=public.get_blueprint(secret,(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,products}'),2,'seat and standing offers derive from the blueprint');
 PERFORM public.assert_eq((r#>>'{data,areaAvailability,0,available}')::int,3,'standing available without duplicate form field');
 r:=public.select_spot((f->>'formKey')::uuid,secret,foreign_spot,true);
 PERFORM public.assert_true(r->>'code'<>'200','another blueprint seat cannot be reserved through this form');
 payload:=jsonb_build_object('form',f->>'formKey','secret',secret,'email','bound-test@example.invalid','fields','[]'::jsonb,'ticket',jsonb_build_array(jsonb_build_object('spot',foreign_spot,'fields','[]'::jsonb)));
 r:=public.finalize_ticket_order_internal_v1(order_id,payload);
 PERFORM public.assert_eq(r->>'code','1007','another blueprint seat cannot be checked out through this form');
 payload:=jsonb_set(payload,'{ticket}',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',(f->>'product')::bigint)))));
 r:=public.finalize_ticket_order_internal_v1(order_id,payload);
 PERFORM public.assert_eq(r->>'errorCode','PRODUCT_SCOPE_MISMATCH','addressed product requires its actual seat, not just a product ID');
 r:=public.select_spot((f->>'formKey')::uuid,secret,seat,true);
 PERFORM public.assert_eq(r->>'code','200','assigned seat reserves without form product fields');
 payload:=jsonb_set(payload,'{ticket}',jsonb_build_array(jsonb_build_object('spot',seat,'fields','[]'::jsonb),jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',standing)))));
 r:=public.finalize_ticket_order_internal_v1(order_id,payload);
 PERFORM public.assert_eq(r->>'code','200','real mixed seat and standing checkout without form product fields');
 PERFORM public.assert_eq((SELECT price FROM eshop.orders WHERE id=order_id),150::numeric,'canonical product prices used');
 PERFORM public.assert_true((SELECT order_product_ticket IS NOT NULL FROM eshop.spots WHERE id=seat),'checkout persists the assigned seat');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.spots WHERE inventory_context=ctx AND order_product_ticket IS NOT NULL),1,'checkout allocates standing supply');
END $$;
ROLLBACK;
