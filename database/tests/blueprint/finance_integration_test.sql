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
DECLARE f jsonb; r jsonb; req jsonb; seat_ids bigint[]; order_id bigint; ticket_id bigint; opt_id bigint; pay bigint; history_before int; snapshot jsonb; prod2 bigint; ticket2 bigint; opt2 bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal(); req:=f->'request'; PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 SELECT array_agg(spot ORDER BY spot) INTO seat_ids FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) SELECT occasion,product_type,'Expensive',150,'CZK' FROM eshop.products WHERE id=(f->>'product')::bigint RETURNING id INTO prod2;
 UPDATE eshop.spots SET product=prod2 WHERE id=seat_ids[2];
 order_id:=public.allocate_ticket_order_identity_internal((f->>'form')::bigint);
 INSERT INTO eshop.payment_info(amount,paid,currency_code) VALUES(100,100,'CZK') RETURNING id INTO pay;
 INSERT INTO eshop.tickets(occasion,state) VALUES((f->>'occasion')::bigint,'paid') RETURNING id INTO ticket_id;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,(f->>'product')::bigint) RETURNING id INTO opt_id;
 UPDATE eshop.orders SET state='paid',price=100,payment_info=pay,data=jsonb_build_object('name','Private customer','email','private@example.invalid','tickets',jsonb_build_array(jsonb_build_object('id',ticket_id,'products',jsonb_build_array(public._swap_spots_generate_product_json((f->>'product')::bigint,seat_ids[1]))))) WHERE id=order_id;
 UPDATE eshop.spots SET order_product_ticket=opt_id WHERE id=seat_ids[1];
 SELECT count(*) INTO history_before FROM eshop.orders_history WHERE "order"=order_id;
 SELECT to_jsonb(o) INTO snapshot FROM eshop.orders o WHERE id=order_id;
 r:=public.preview_blueprint_swap(seat_ids[1],seat_ids[2]);
 PERFORM public.assert_eq((r->>'code')::int,200,'paid swap preview accepted');
 PERFORM public.assert_eq((r#>>'{orders,0,afterAmount}')::numeric,150::numeric,'preview effective destination amount');
 PERFORM public.assert_eq((r#>>'{orders,0,delta}')::numeric,50::numeric,'preview delta');
 PERFORM public.assert_eq((SELECT to_jsonb(o) FROM eshop.orders o WHERE id=order_id),snapshot,'preview rolls back complete order');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.orders_history WHERE "order"=order_id),history_before,'preview no history');
 PERFORM public.assert_eq((SELECT amount FROM eshop.payment_info WHERE id=pay),100::numeric,'preview no payment mutation');
 r:=public.swap_spot_tickets_client_sync_v1(seat_ids[1],seat_ids[2],gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','paid swap committed');
 PERFORM public.assert_eq((SELECT price FROM eshop.orders WHERE id=order_id),150::numeric,'paid swap order total');
 PERFORM public.assert_eq((SELECT amount FROM eshop.payment_info WHERE id=pay),150::numeric,'paid swap payment due');
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=seat_ids[2]),opt_id,'same ticket moved');
 PERFORM public.assert_eq((SELECT state FROM eshop.orders WHERE id=order_id),'ordered','additional balance updates state');
 -- Currency conflict is rejected before persisting any swap side.
 UPDATE eshop.products SET currency_code='EUR' WHERE id=(f->>'product')::bigint;
 r:=public.preview_blueprint_swap(seat_ids[1],seat_ids[2]);
 PERFORM public.assert_eq(r->>'reason','BLUEPRINT_CURRENCY_MISMATCH','cross currency preview rejected');
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=seat_ids[2]),opt_id,'failed preview keeps assignment');
 -- Direct cancellation of one atomic member rejects before writes.
 UPDATE eshop.blueprint_seat_bindings SET selection_unit='12345678-1234-1234-1234-123456789012' WHERE spot=ANY(seat_ids[1:2]);
 BEGIN PERFORM public.internal_storno_tickets_221(ARRAY[ticket_id]); RAISE EXCEPTION 'partial storno accepted';
 EXCEPTION WHEN check_violation THEN PERFORM public.assert_eq(SQLERRM,'BLUEPRINT_INCOMPLETE_SELECTION_UNIT','direct storno unit guard'); END;
 -- A partly used atomic unit cannot be cancelled, replaced or swapped.
 UPDATE eshop.products SET currency_code='CZK' WHERE id=(f->>'product')::bigint;
 INSERT INTO eshop.tickets(occasion,state) VALUES((f->>'occasion')::bigint,'paid') RETURNING id INTO ticket2;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket2,(f->>'product')::bigint) RETURNING id INTO opt2;
 UPDATE eshop.spots SET order_product_ticket=opt2 WHERE id=seat_ids[1];
 UPDATE eshop.tickets SET state='used' WHERE id=ticket_id;
 UPDATE eshop.blueprint_seat_bindings SET selection_unit='22345678-1234-1234-1234-123456789012' WHERE spot=ANY(seat_ids[3:4]);
 BEGIN PERFORM public.internal_storno_tickets_221(ARRAY[ticket_id,ticket2]); RAISE EXCEPTION 'used couch cancellation accepted';
 EXCEPTION WHEN check_violation THEN PERFORM public.assert_eq(SQLERRM,'BLUEPRINT_SELECTION_UNIT_USED','used couch cancellation blocker'); END;
 r:=public.replace_blueprint_order_client_sync_v1(seat_ids[1:2],jsonb_build_object('email','synthetic@example.invalid'),gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','rejected','used couch replacement rejected');
 r:=public.preview_blueprint_swap(seat_ids[1],seat_ids[3]);
 PERFORM public.assert_eq(r->>'reason','BLUEPRINT_SELECTION_UNIT_USED','used couch swap rejected');
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=seat_ids[1]),opt2,'used couch first assignment unchanged');
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=seat_ids[2]),opt_id,'used couch second assignment unchanged');
 PERFORM public.assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket_id),'used','used state unchanged');
END $$;
