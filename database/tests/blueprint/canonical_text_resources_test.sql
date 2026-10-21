-- Run after layout_integration_test.sql inside a rollback-only transaction.
DO $$
DECLARE f jsonb; other jsonb; resources jsonb; resource_id text:='layout-text:'||repeat('a',64); changed jsonb; denied boolean:=false;
BEGIN
 f:=public.blueprint_test_fixture_internal();other:=public.blueprint_test_fixture_internal();
 resources:=jsonb_build_object('protocol',2,'textLayouts',jsonb_build_object(resource_id,jsonb_build_object('id',resource_id,'descriptor',jsonb_build_object('layoutResourceProtocol',2),'path','[]'::jsonb)),'numberSymbols','{}'::jsonb);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN PERFORM public.register_blueprint_text_resources((f->>'occasion')::bigint,NULL,resources);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM public.assert_eq(denied,true,'clients cannot register prepared paths');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.register_blueprint_text_resources((f->>'occasion')::bigint,NULL,resources);
 PERFORM public.register_blueprint_text_resources((f->>'occasion')::bigint,NULL,resources);
 PERFORM public.assert_eq((SELECT count(*)::int FROM public.blueprint_text_resources WHERE occasion=(f->>'occasion')::bigint AND resource_kind='text'),1,'resource replay is immutable and idempotent');
 changed:=jsonb_set(resources,ARRAY['textLayouts',resource_id,'path'],'[["M",1,2]]');denied:=false;
 BEGIN PERFORM public.register_blueprint_text_resources((f->>'occasion')::bigint,NULL,changed);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM public.assert_eq(denied,true,'same scoped ID cannot change geometry');
 PERFORM public.assert_eq((SELECT count(*)::int FROM public.blueprint_text_resources WHERE occasion=(other->>'occasion')::bigint AND resource_kind='text'),0,'foreign scope cannot inherit registered resources');
 PERFORM public.assert_eq(has_table_privilege('authenticated','public.blueprint_text_resources','select'),false,'prepared rows are not directly readable');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
END $$;

DO $$
DECLARE f jsonb; req jsonb; r jsonb; group_id uuid:=gen_random_uuid(); changed jsonb; old_mode text; second_product bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal();req:=f->'request';
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object('id',group_id,'kind','group','width',40,'height',40,'transform',jsonb_build_object('x',500,'y',500,'rotation',0))));
 req:=jsonb_set(req,'{seatChanges,0}',req#>'{seatChanges,0}'||jsonb_build_object('groupNodeId',group_id,'productAssignmentMode','inherit'));
 req:=jsonb_set(req,'{groupProductChanges}',jsonb_build_array(jsonb_build_object('groupNodeId',group_id,'productId',f->'product')));
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','explicit inherited assignment saves');
 SELECT product_assignment_mode INTO old_mode FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint AND node_id=(req#>>'{seatChanges,0,nodeId}')::uuid;
 PERFORM public.assert_eq(old_mode,'inherit','assignment mode persisted independently of equality');
 req:=jsonb_set(req,'{expected_layout_revision}','1');
 req:=jsonb_set(req,'{seatChanges}',(SELECT jsonb_agg(c||jsonb_build_object('spotId',b.spot)) FROM jsonb_array_elements(req->'seatChanges') c JOIN eshop.blueprint_seat_bindings b ON b.node_id=(c->>'nodeId')::uuid));
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) SELECT occasion,product_type,'Other product',200,'CZK',false FROM eshop.products WHERE id=(f->>'product')::bigint RETURNING id INTO second_product;
 changed:=jsonb_set(req,'{groupProductChanges,0,productId}',to_jsonb(second_product));
 r:=public.update_blueprint_client_sync_v1(changed,gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','materialized product and inheritance intent remain independent for free-only propagation');
 PERFORM public.assert_eq((SELECT layout_revision::int FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint),2,'default change increments revision without rewriting skipped seat mode');
 changed:=jsonb_set(changed,'{expected_layout_revision}','2');
 changed:=jsonb_set(changed,'{seatChanges,0,productAssignmentMode}','"override"');
 r:=public.update_blueprint_client_sync_v1(changed,gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','equal-value explicit override survives default change');
 PERFORM public.assert_eq((SELECT product_assignment_mode FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint AND node_id=(req#>>'{seatChanges,0,nodeId}')::uuid),'override','explicit override preserved');
END $$;
