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
DECLARE f jsonb; req jsonb; r jsonb; original_bp bigint; original_occ bigint; copied_occ bigint; copied_bp bigint; unit_id bigint; source_layout jsonb; new_bp bigint; form_id bigint; group_id uuid:=gen_random_uuid(); area_id uuid:=gen_random_uuid(); selection_id uuid:=gen_random_uuid(); pool_id bigint; context_id bigint; copied_layout jsonb; copied_group uuid; copied_area uuid; copied_unit uuid; table_id uuid:=gen_random_uuid(); attachment_id uuid:=gen_random_uuid(); section_id uuid:=gen_random_uuid(); generator_id uuid:=gen_random_uuid(); preset_id uuid:=gen_random_uuid();
BEGIN
 f:=public.blueprint_test_fixture_internal();req:=f->'request';original_bp:=(f->>'blueprint')::bigint;original_occ:=(f->>'occasion')::bigint;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 SELECT unit INTO unit_id FROM public.occasions WHERE id=original_occ;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) VALUES(unit_id,(f->>'actor')::uuid,true,true,true);
 UPDATE public.user_info SET organization=(SELECT organization FROM public.occasions WHERE id=original_occ) WHERE id=(f->>'actor')::uuid;
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES(original_occ,'Copy standing','generic',5) RETURNING id INTO pool_id;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool_id,'Copy standing') RETURNING id INTO context_id;
 INSERT INTO public.resources(inventory_pool,occasion,title,capacity) VALUES(pool_id,original_occ,'Copy supply',5);
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES((f->>'product')::bigint,context_id,1);
 PERFORM public.adjust_spot_capacity_for_pool(pool_id);
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(
  jsonb_build_object('id',group_id,'kind','group','width',200,'height',100,'transform',jsonb_build_object('x',0,'y',0,'rotation',0)),
  jsonb_build_object('id',area_id,'kind','capacityArea','width',200,'height',100,'transform',jsonb_build_object('x',300,'y',300,'rotation',0))));
 req:=jsonb_set(req,'{seatChanges,0,groupNodeId}',to_jsonb(group_id));req:=jsonb_set(req,'{seatChanges,1,groupNodeId}',to_jsonb(group_id));
 req:=jsonb_set(req,'{seatChanges,2,selectionUnitId}',to_jsonb(selection_id));req:=jsonb_set(req,'{seatChanges,3,selectionUnitId}',to_jsonb(selection_id));
 req:=jsonb_set(req,'{layout,selectionUnits}',jsonb_build_array(jsonb_build_object('id',selection_id,'nodeIds',jsonb_build_array(req#>'{seatChanges,2,nodeId}',req#>'{seatChanges,3,nodeId}'))));
 req:=jsonb_set(req,'{groupProductChanges}',jsonb_build_array(jsonb_build_object('groupNodeId',group_id,'productId',(f->>'product')::bigint)));
 req:=jsonb_set(req,'{areaBindingChanges}',jsonb_build_array(jsonb_build_object('nodeId',area_id,'productId',(f->>'product')::bigint,'inventoryContextId',context_id,'operation','upsert')));
 -- Exercise every declared geometry record and reference family. A label that
 -- looks exactly like a referenced UUID remains ordinary user-visible text.
 UPDATE public.ticket_font_assets SET layout_outline=jsonb_set(layout_outline,'{glyphs}',layout_outline->'glyphs'||(SELECT jsonb_object_agg(ch,jsonb_build_object('advance',500,'path','[]'::jsonb)) FROM (SELECT DISTINCT regexp_split_to_table(group_id::text,'') ch) chars)) WHERE id=req#>>'{layout,defaultTextStyle,fontId}';
 req:=jsonb_set(req,'{layout,nodes,0,label}',to_jsonb(group_id::text));
 req:=jsonb_set(req,'{layout,nodes,0,parentId}',to_jsonb(table_id));
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object('id',table_id,'kind','table','width',200,'height',100,'transform',jsonb_build_object('x',0,'y',0,'rotation',0))));
 req:=jsonb_set(req,'{layout,attachments}',jsonb_build_array(jsonb_build_object('id',attachment_id,'seatId',req#>'{layout,nodes,0,id}','targetId',table_id,'kind','edge','edge','top','t',0.5,'gap',10)));
 req:=jsonb_set(req,'{layout,sections}',jsonb_build_array(jsonb_build_object('id',section_id,'rootId',group_id,'title','Section','levelId','balcony')));
 req:=jsonb_set(req,'{layout,generators}',jsonb_build_array(jsonb_build_object('id',generator_id,'rootId',group_id,'assemblyId',group_id,'nodeIds',jsonb_build_array(req#>'{layout,nodes,0,id}'),'kind','rows','version',1)));
 req:=jsonb_set(req,'{layout,presets}',jsonb_build_array(jsonb_build_object('id',preset_id,'title','Empty preset','document',jsonb_set(req->'layout','{nodes}','[]')-'attachments'-'sections'-'generators'-'selectionUnits')));
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());PERFORM public.assert_eq(r->>'status','applied','copy source saved');
 source_layout:=req->'layout';
 UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=now()+interval '5 minutes' WHERE blueprint=original_bp;
 copied_occ:=public.duplicate_occasion_internal_v1(original_occ,unit_id,'cs');
 SELECT id INTO copied_bp FROM eshop.blueprints WHERE occasion=copied_occ;
 SELECT layout INTO copied_layout FROM eshop.blueprints WHERE id=copied_bp;
 PERFORM public.validate_blueprint_layout_internal(copied_layout);
 PERFORM public.assert_eq((SELECT count(*)::int FROM jsonb_array_elements(source_layout->'nodes') old_node JOIN jsonb_array_elements(copied_layout->'nodes') new_node ON old_node->>'id'=new_node->>'id'),0,'copy node IDs all disjoint');
 PERFORM public.assert_eq(copied_layout#>>'{nodes,0,label}',group_id::text,'UUID-looking label preserved');
 PERFORM public.assert_true(copied_layout#>>'{sections,0,id}'<>section_id::text,'section identity remapped');
 PERFORM public.assert_true(copied_layout#>>'{selectionUnits,0,id}'<>selection_id::text,'unit identity remapped');
 PERFORM public.assert_true(copied_layout#>>'{attachments,0,id}'<>attachment_id::text,'attachment identity remapped');
 PERFORM public.assert_true(copied_layout#>>'{generators,0,id}'<>generator_id::text,'generator identity remapped');
 PERFORM public.assert_true(copied_layout#>>'{presets,0,id}'<>preset_id::text,'preset identity remapped');
 copied_group:=(copied_layout#>>'{sections,0,rootId}')::uuid;
 copied_unit:=(copied_layout#>>'{selectionUnits,0,id}')::uuid;
 SELECT (node->>'id')::uuid INTO copied_area FROM jsonb_array_elements(copied_layout->'nodes') node WHERE node->>'kind'='capacityArea';
 PERFORM public.assert_eq(copied_layout#>>'{attachments,0,seatId}',copied_layout#>>'{nodes,0,id}','attachment seat remapped');
 PERFORM public.assert_eq(copied_layout#>>'{attachments,0,targetId}',copied_layout#>>'{nodes,0,parentId}','attachment parent target remapped');
 PERFORM public.assert_eq(copied_layout#>>'{generators,0,rootId}',copied_group::text,'generator root remapped');
 PERFORM public.assert_eq(copied_layout#>>'{generators,0,assemblyId}',copied_group::text,'generator assembly remapped');
 PERFORM public.assert_eq(copied_layout#>>'{generators,0,nodeIds,0}',copied_layout#>>'{nodes,0,id}','generator members remapped');
 PERFORM public.assert_eq(copied_layout#>>'{sections,0,levelId}','balcony','named level preserved');

 PERFORM public.assert_eq((SELECT layout_revision::int FROM eshop.blueprints WHERE id=copied_bp),0,'copy new aggregate revision');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_seat_bindings WHERE blueprint=copied_bp AND selection_unit=copied_unit),2,'copy atomic membership');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_seat_bindings WHERE blueprint=copied_bp AND group_node=copied_group),2,'copy commercial group membership');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_group_products gp JOIN eshop.products p ON p.id=gp.product WHERE gp.blueprint=copied_bp AND gp.group_node=copied_group AND p.occasion=copied_occ),1,'copy default remapped product');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_area_bindings ab JOIN public.inventory_contexts ic ON ic.id=ab.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool JOIN eshop.products p ON p.id=ab.product WHERE ab.blueprint=copied_bp AND ab.node_id=copied_area AND ip.occasion=copied_occ AND p.occasion=copied_occ AND ab.inventory_context<>context_id),1,'copy standing remaps context product and pool');

 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_seat_bindings WHERE blueprint=copied_bp),4,'copy bindings complete');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_seat_bindings a JOIN eshop.blueprint_seat_bindings b ON a.spot=b.spot WHERE a.blueprint=original_bp AND b.blueprint=copied_bp),0,'copy uses new spot IDs');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.spots WHERE blueprint=copied_bp AND (secret IS NOT NULL OR order_product_ticket IS NOT NULL)),0,'copy clears reservations and orders');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.spots s JOIN eshop.products p ON p.id=s.product WHERE s.blueprint=copied_bp AND p.occasion=copied_occ),4,'copy remaps products within occasion');
 -- Enabling a blueprint for an existing form creates one valid empty V2 layout.
 UPDATE public.forms SET blueprint=NULL WHERE id=(f->>'form')::bigint;
 PERFORM public.update_occasion_internal_v1(jsonb_build_object('id',original_occ,'features',jsonb_build_array(jsonb_build_object('code','blueprint','is_enabled',true))));
 SELECT blueprint INTO new_bp FROM public.forms WHERE id=(f->>'form')::bigint;
 PERFORM public.assert_true(new_bp IS NOT NULL AND new_bp<>original_bp,'setup blueprint attached');
 PERFORM public.assert_eq(jsonb_array_length((SELECT layout->'nodes' FROM eshop.blueprints WHERE id=new_bp)),0,'setup empty layout');
 PERFORM public.assert_eq((SELECT layout#>>'{canvas,fill}' FROM eshop.blueprints WHERE id=new_bp),'#ffffffff','setup core color format');
END $$;
