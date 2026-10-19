CREATE OR REPLACE FUNCTION public.blueprint_test_fixture_internal(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE actor uuid; org bigint; un bigint; occ bigint; bp bigint; prod bigint; pt bigint; fid bigint; fkey uuid; d jsonb; seats jsonb; node uuid; i integer; font public.ticket_font_assets;
BEGIN
 SELECT id INTO actor FROM auth.users LIMIT 1;
 IF p_organization IS NULL THEN INSERT INTO public.organizations(title) VALUES('Blueprint integration fixture') RETURNING id INTO org;
 ELSE SELECT id INTO org FROM public.organizations WHERE id=p_organization;IF org IS NULL THEN RAISE EXCEPTION 'fixture organization not found';END IF;END IF;
 INSERT INTO public.units(title,organization) VALUES('Blueprint fixture',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Blueprint fixture',org,un,'bp-fixture-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO occ;
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',occ,link,true) WHERE id=occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor) VALUES(occ,actor,true,true,true);
 INSERT INTO eshop.blueprints(occasion,organization,title,objects) VALUES(occ,org,'Blueprint fixture','[]') RETURNING id INTO bp;
 INSERT INTO public.forms(occasion,blueprint,title,link,is_open,type) VALUES(occ,bp,'Fixture','bp-form-'||gen_random_uuid(),true,'ticket') RETURNING id,key INTO fid,fkey;
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',fid,link,true) WHERE id=fid;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Seats','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) VALUES(occ,pt,'Seat',100,'CZK',false) RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,product_type,type,is_ticket_field,is_hidden) VALUES(fid,pt,'product_type',true,false);
 SELECT * INTO font FROM public.ticket_font_assets WHERE id LIKE 'builtin:%' ORDER BY id LIMIT 1;
 UPDATE public.ticket_font_assets SET layout_outline=coalesce(layout_outline,jsonb_build_object('id',font.id,'hash',font.metadata->>'sha256','family',font.metadata->>'family','unitsPerEm',1000,'ascent',800,'descent',-200,'glyphs','{}'::jsonb)) WHERE id=font.id;
 d:='{"schemaVersion":1,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1000,"height":1000,"fill":"#ffffffff"},"nodes":[],"selectionUnits":[]}'::jsonb; d:=jsonb_set(d,'{defaultTextStyle}',jsonb_build_object('fontId',font.id,'size',24,'color','#222222FF')); seats:='[]';
 FOR i IN 1..4 LOOP
  node:=gen_random_uuid();
  d:=jsonb_set(d,'{nodes}',d->'nodes'||jsonb_build_array(jsonb_build_object('id',node,'kind','seat','width',40,'height',40,'transform',jsonb_build_object('x',i*60,'y',60,'rotation',0))));
  seats:=seats||jsonb_build_array(jsonb_build_object('nodeId',node,'spotId',NULL,'productId',prod,'title','S'||i,'groupNodeId',NULL,'selectionUnitId',NULL,'blocked',false,'operation','upsert'));
 END LOOP;
 RETURN jsonb_build_object('actor',actor,'occasion',occ,'form',fid,'formKey',fkey,'blueprint',bp,'product',prod,
  'request',jsonb_build_object('id',bp,'occasion',occ,'organization',org,'title','Fixture','expected_layout_revision',0,'layout',d,'seatChanges',seats,'groupProductChanges','[]'::jsonb,'areaBindingChanges','[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.blueprint_test_fixture_internal()
RETURNS jsonb LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.blueprint_test_fixture_internal(NULL::bigint)
$$;
DO $$
DECLARE f jsonb; req jsonb; r jsonb; pool bigint; context_id bigint; resource_id bigint; area uuid:=gen_random_uuid(); availability jsonb; opt bigint; oid bigint; tid bigint; font public.ticket_font_assets; outline jsonb;
BEGIN
 f:=public.blueprint_test_fixture_internal(); req:=f->'request'; PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES((f->>'occasion')::bigint,'Standing','generic',5) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Standing') RETURNING id INTO context_id;
 INSERT INTO public.resources(inventory_pool,occasion,title,capacity) VALUES(pool,(f->>'occasion')::bigint,'Standing supply',5) RETURNING id INTO resource_id;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES((f->>'product')::bigint,context_id,1);
 PERFORM public.adjust_spot_capacity_for_pool(pool);
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object('id',area,'kind','capacityArea','width',100,'height',100,'transform',jsonb_build_object('x',400,'y',400,'rotation',0))));
 req:=jsonb_set(req,'{areaBindingChanges}',jsonb_build_array(jsonb_build_object('nodeId',area,'productId',(f->>'product')::bigint,'inventoryContextId',context_id,'operation','upsert','capacity',4)));
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
 -- Register safe outlines in the existing font authority, then merge glyphs.
 SELECT * INTO font FROM public.ticket_font_assets ORDER BY id LIMIT 1;
 -- This rollback-only merge fixture must not reuse the live glyph metrics
 -- already generated by the genuine local Edge outline proof.
 UPDATE public.ticket_font_assets SET layout_outline=NULL WHERE id=font.id;
 outline:=jsonb_build_object('id',font.id,'hash',font.metadata->>'sha256','family',font.metadata->>'family','unitsPerEm',1000,'ascent',800,'descent',-200,'glyphs',jsonb_build_object('A',jsonb_build_object('advance',500,'path','[]'::jsonb)));
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.register_blueprint_layout_font(font.id,outline);
 outline:=jsonb_set(outline,'{glyphs}',jsonb_build_object('B',jsonb_build_object('advance',500,'path','[]'::jsonb)));
 PERFORM public.register_blueprint_layout_font(font.id,outline);
 PERFORM public.assert_true((SELECT layout_outline->'glyphs' ?& ARRAY['A','B'] FROM public.ticket_font_assets WHERE id=font.id),'font glyph merge');
 BEGIN PERFORM public.register_blueprint_layout_font(font.id,jsonb_set(outline,'{unitsPerEm}','2000'));RAISE EXCEPTION 'changed metrics accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN PERFORM public.register_blueprint_layout_font(font.id,outline); RAISE EXCEPTION 'font writer open'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.assert_true(NOT has_function_privilege('authenticated','public.register_blueprint_layout_font(text,jsonb)','EXECUTE'),'font registration service only');
 availability:=public.blueprint_layout_resources_internal(jsonb_build_object('defaultTextStyle',jsonb_build_object('fontId',font.id),'nodes','[]'::jsonb),(f->>'occasion')::bigint);
 PERFORM public.assert_true(availability->'fonts' ? font.id,'outline read follows referenced font');
END $$;
