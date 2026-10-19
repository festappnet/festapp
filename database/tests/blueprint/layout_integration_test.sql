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
DECLARE f jsonb; req jsonb; r jsonb; replay jsonb; cmd uuid; seat_ids bigint[]; s bigint; hold uuid:=gen_random_uuid(); before_rev bigint; projection jsonb; invalid_req jsonb; node_id text; scenario text; expected_reason text;
BEGIN
 f:=public.blueprint_test_fixture_internal(); req:=f->'request';
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 cmd:=gen_random_uuid(); r:=public.update_blueprint_client_sync_v1(req,cmd);
 PERFORM public.assert_eq(r->>'status','applied','layout save accepted');
 PERFORM public.assert_eq((r#>>'{data,layout_revision}')::int,1,'save revision');
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,seatBindings}'),4,'server bindings');
 replay:=public.update_blueprint_client_sync_v1(req,cmd); PERFORM public.assert_eq(replay,r,'receipt replay stable');
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 PERFORM public.assert_eq(r#>>'{data,reason}','BLUEPRINT_REVISION_CONFLICT','stale revision conflict');
 SELECT array_agg(spot ORDER BY spot) INTO seat_ids FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint;
 -- A late invalid product rolls back an earlier valid title update.
 req:=jsonb_set(req,'{expected_layout_revision}','1');
 req:=jsonb_set(req,'{seatChanges}',(SELECT jsonb_agg(c||jsonb_build_object('spotId',b.spot)) FROM jsonb_array_elements(req->'seatChanges') c JOIN eshop.blueprint_seat_bindings b ON b.node_id=(c->>'nodeId')::uuid));
 req:=jsonb_set(req,'{seatChanges,0,title}','"changed before failure"');
 req:=jsonb_set(req,'{seatChanges,1,productId}','-1');
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','rejected','invalid product rejection');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.spots WHERE id=ANY(seat_ids) AND title='changed before failure'),0,'save rollback precedes rejected receipt');
 PERFORM public.assert_eq((SELECT layout_revision::int FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint),1,'rejected save revision unchanged');
 -- Public authoring limits are enforced before persistence, including the
 -- 20k seat limit (25k is the distinct overall node limit).
 req:=f->'request';req:=jsonb_set(req,'{expected_layout_revision}','1'); req:=jsonb_set(req,'{seatChanges}','[]');
 FOREACH scenario IN ARRAY ARRAY['canvas','size','cycle','unknown','asset','seat_limit'] LOOP
  invalid_req:=req;
  CASE scenario
   WHEN 'canvas' THEN invalid_req:=jsonb_set(req,'{layout,canvas,width}','63');expected_reason:='BLUEPRINT_INVALID_CANVAS';
   WHEN 'size' THEN invalid_req:=jsonb_set(req,'{layout,nodes,0,width}','0');expected_reason:='BLUEPRINT_INVALID_GEOMETRY';
   WHEN 'cycle' THEN invalid_req:=jsonb_set(req,'{layout,nodes,0,parentId}',req#>'{layout,nodes,0,id}');expected_reason:='BLUEPRINT_PARENT_CYCLE';
   WHEN 'unknown' THEN invalid_req:=jsonb_set(req,'{layout,nodes,0,properties}','{}');expected_reason:='BLUEPRINT_INVALID_NODE';
   WHEN 'asset' THEN invalid_req:=jsonb_set(req,'{layout,background}','{}');expected_reason:='BLUEPRINT_ASSET_RESOURCE_NOT_READY';
   WHEN 'seat_limit' THEN invalid_req:=jsonb_set(req,'{layout,nodes}',(SELECT jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'kind','seat','width',40,'height',40,'transform',jsonb_build_object('x',0,'y',0,'rotation',0))) FROM generate_series(1,20001)));expected_reason:='BLUEPRINT_LAYOUT_LIMIT';
  END CASE;
  r:=public.update_blueprint_client_sync_v1(invalid_req,gen_random_uuid());
  PERFORM public.assert_eq(r#>>'{data,reason}',expected_reason,'strict authoring rejection '||scenario);
  PERFORM public.assert_eq((SELECT layout_revision::int FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint),1,'invalid geometry did not persist');
 END LOOP;
 PERFORM public.validate_blueprint_polygon_internal('[[0,0],[100,0],[100,100],[0,100]]',true);
 BEGIN PERFORM public.validate_blueprint_polygon_internal('[[0,0],[100,100],[100,0],[0,100]]',true); RAISE EXCEPTION 'self intersecting polygon accepted'; EXCEPTION WHEN check_violation THEN PERFORM public.assert_eq(SQLERRM,'BLUEPRINT_SELF_INTERSECTION','polygon crossing rejected'); END;
 r:=public.analyze_new_order_spots(seat_ids);
 PERFORM public.assert_eq((r->>'total_price')::numeric,400::numeric,'backend order selection total');
 PERFORM public.assert_eq(r->>'currency','CZK','backend order selection currency');
 -- Complete atomic unit succeeds; direct half mutation must reject.
 UPDATE eshop.blueprint_seat_bindings SET selection_unit='12345678-1234-1234-1234-123456789012' WHERE spot=ANY(seat_ids[1:2]);
 r:=public.select_spot((f->>'formKey')::uuid,hold,seat_ids[1],true);
 PERFORM public.assert_eq((r->>'code')::int,200,'unit hold accepted');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.spots WHERE id=ANY(seat_ids[1:2]) AND secret=hold),2,'both unit seats held');
 BEGIN PERFORM public.check_blueprint_selection_units_internal(ARRAY[seat_ids[1]]); RAISE EXCEPTION 'partial selection accepted';
 EXCEPTION WHEN check_violation THEN PERFORM public.assert_eq(SQLERRM,'BLUEPRINT_INCOMPLETE_SELECTION_UNIT','partial unit reason'); END;
 -- One blocked member leaves the entire unit released.
 PERFORM public.select_spot((f->>'formKey')::uuid,hold,seat_ids[1],false);
 UPDATE eshop.blueprint_seat_bindings SET blocked=true WHERE spot=seat_ids[2];
 r:=public.select_spot((f->>'formKey')::uuid,hold,seat_ids[1],true);
 PERFORM public.assert_eq((r->>'code')::int,409,'blocked unit rejected');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.spots WHERE id=ANY(seat_ids[1:2]) AND secret IS NOT NULL),0,'unit rejection has no partial hold');
 projection:=public.get_blueprint(NULL,(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq(projection#>>'{data,occasion}',f->>'occasion','public projection carries verified occasion scope');
 PERFORM public.assert_eq(jsonb_array_length(projection#>'{data,seatBindings}'),4,'public stable bindings');
 PERFORM public.assert_true(NOT (projection::text ~ 'order_product_ticket|secret|email|surname|note_hidden'),'public projection excludes private data');
 PERFORM public.assert_true(NOT has_table_privilege('authenticated','eshop.blueprint_seat_bindings','INSERT'),'no direct binding grant');
 PERFORM public.assert_true(NOT has_function_privilege('anon','public.preview_blueprint_swap(bigint,bigint)','EXECUTE'),'swap preview private');
 UPDATE eshop.blueprint_seat_bindings SET blocked=false WHERE spot=seat_ids[2];
 r:=public.preview_blueprint_swap(seat_ids[1],seat_ids[3]); PERFORM public.assert_eq(r->>'reason','BLUEPRINT_UNIT_SIZE_MISMATCH','mismatched unit preview rejected');
 r:=public.preview_blueprint_swap(seat_ids[3],seat_ids[4]); PERFORM public.assert_eq((r->>'code')::int,200,'empty singleton swap preview succeeds');
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.update_blueprint_client_sync_v1(req,gen_random_uuid()); RAISE EXCEPTION 'anonymous save accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
