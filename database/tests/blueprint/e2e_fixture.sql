-- Synthetic local fixture only. Load fixtures.sql first, then call with a
-- canonical font ID registered through register_blueprint_layout_font.
CREATE OR REPLACE FUNCTION public.blueprint_seed_e2e_fixture(p_font_id text,p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE f jsonb; req jsonb; result jsonb; group1 uuid:=gen_random_uuid(); couch uuid:=gen_random_uuid(); area uuid:=gen_random_uuid(); unit_id uuid:=gen_random_uuid();
 nodes jsonb; changes jsonb; item jsonb; i int:=0; product2 bigint; standing bigint; standing_type bigint; pool_id bigint; context_id bigint; order_id bigint; ticket_id bigint; opt_id bigint; seat_id bigint; occ bigint; fid bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment) THEN RAISE EXCEPTION 'disposable fixture database required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ticket_font_assets WHERE id=p_font_id AND layout_outline IS NOT NULL) THEN RAISE EXCEPTION 'registered font outline required'; END IF;
 f:=public.blueprint_test_fixture_internal(p_organization); req:=f->'request'; occ:=(f->>'occasion')::bigint; fid:=(f->>'form')::bigint;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 -- Actual canonical flat form fields. FormModel groups the flagged children
 -- under ticket; the spot control opens the picker. Standing uses no spot ID.
 INSERT INTO public.form_fields(form,title,type,is_required,is_hidden,is_ticket_field,"order",data) VALUES
  (fid,'Email','email',true,false,false,0,'{}'),
  (fid,'Tickets','ticket',true,false,false,10,'{"max_tickets":20}'),
  (fid,'Seat','spot',false,false,true,20,'{}');
 UPDATE public.form_fields SET title='Admission',"order"=30,data='{"selection_type":"select_one"}' WHERE form=fid AND type='product_type';

 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) SELECT unit,(f->>'actor')::uuid,true,true,true FROM public.occasions WHERE id=occ;
 UPDATE public.occasions SET features='[{"code":"blueprint","is_enabled":true},{"code":"form","is_enabled":true}]' WHERE id=occ;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) SELECT occasion,product_type,'Premium chair',150,'CZK' FROM eshop.products WHERE id=(f->>'product')::bigint RETURNING id INTO product2;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Standing admission','spot') RETURNING id INTO standing_type;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(occ,standing_type,'Standing admission',80,'CZK') RETURNING id INTO standing;
 INSERT INTO public.form_fields(form,title,type,product_type,is_required,is_hidden,is_ticket_field,"order",data) VALUES(fid,'Standing admission','product_type',standing_type,false,false,true,40,'{"selection_type":"select_one"}');
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES(occ,'Standing fixture','generic',5) RETURNING id INTO pool_id;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool_id,'Standing fixture') RETURNING id INTO context_id;
 INSERT INTO public.resources(inventory_pool,occasion,title,capacity) VALUES(pool_id,occ,'Standing capacity',5);
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(standing,context_id,1);
 PERFORM public.adjust_spot_capacity_for_pool(pool_id);
 nodes:='[]'; changes:='[]';
 FOR item IN SELECT * FROM jsonb_array_elements(req#>'{layout,nodes}') LOOP
  i:=i+1;
  nodes:=nodes||jsonb_build_array(item||jsonb_build_object('parentId',CASE WHEN i<=2 THEN group1 ELSE couch END,'transform',jsonb_build_object('x',CASE WHEN i%2=1 THEN -60 ELSE 60 END,'y',110,'rotation',0)));
 END LOOP;
 i:=0;
 FOR item IN SELECT * FROM jsonb_array_elements(req->'seatChanges') LOOP
  i:=i+1;
  changes:=changes||jsonb_build_array(item||jsonb_build_object('groupNodeId',CASE WHEN i<=2 THEN group1 ELSE couch END,'selectionUnitId',CASE WHEN i>2 THEN unit_id ELSE NULL END,'productId',CASE WHEN i=2 THEN product2 ELSE (f->>'product')::bigint END,'blocked',i=2));
 END LOOP;
 nodes:=nodes||jsonb_build_array(
  jsonb_build_object('id',group1,'kind','table','width',220,'height',100,'transform',jsonb_build_object('x',250,'y',220,'rotation',0),'label','Mixed table','shape','rect'),
  jsonb_build_object('id',couch,'kind','furniture','width',220,'height',100,'transform',jsonb_build_object('x',650,'y',220,'rotation',0),'label','Atomic couch','shape','roundedRect','symbol','sofa'),
  jsonb_build_object('id',area,'kind','capacityArea','width',260,'height',160,'transform',jsonb_build_object('x',450,'y',600,'rotation',0),'label','Standing','shape','rect'));
 req:=jsonb_set(req,'{layout,nodes}',nodes);
 req:=jsonb_set(req,'{layout,defaultTextStyle}',jsonb_build_object('fontId',p_font_id,'size',24,'color','#222222FF'));
 req:=jsonb_set(req,'{layout,selectionUnits}',jsonb_build_array(jsonb_build_object('id',unit_id,'nodeIds',(SELECT jsonb_agg(c->'nodeId') FROM jsonb_array_elements(changes) c WHERE c->>'selectionUnitId' IS NOT NULL))));
 req:=jsonb_set(req,'{seatChanges}',changes);
 req:=jsonb_set(req,'{groupProductChanges}',jsonb_build_array(jsonb_build_object('groupNodeId',group1,'productId',(f->>'product')::bigint),jsonb_build_object('groupNodeId',couch,'productId',(f->>'product')::bigint)));
 req:=jsonb_set(req,'{areaBindingChanges}',jsonb_build_array(jsonb_build_object('nodeId',area,'productId',standing,'inventoryContextId',context_id,'operation','upsert')));
 result:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 IF result->>'status'<>'applied' THEN RAISE EXCEPTION 'fixture save rejected: %',result; END IF;
 SELECT spot INTO seat_id FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint AND node_id=(changes#>>'{0,nodeId}')::uuid;
 order_id:=public.allocate_ticket_order_identity_internal(fid);
 INSERT INTO eshop.tickets(occasion,state,note_hidden) VALUES(occ,'paid','Synthetic private fixture note') RETURNING id INTO ticket_id;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,(f->>'product')::bigint) RETURNING id INTO opt_id;
 UPDATE eshop.orders SET state='paid',price=100,data=jsonb_build_object('name','Synthetic','surname','Customer','email','blueprint@example.invalid','tickets',jsonb_build_array(jsonb_build_object('id',ticket_id,'products',jsonb_build_array(public._swap_spots_generate_product_json((f->>'product')::bigint,seat_id))))) WHERE id=order_id;
 UPDATE eshop.spots SET order_product_ticket=opt_id WHERE id=seat_id;
 RETURN f||jsonb_build_object('request',req,'saveResult',result,'groupNodeId',group1,'couchNodeId',couch,'areaNodeId',area,'standingProduct',standing,'soldSpot',seat_id,
  'occasionLink',(SELECT link FROM public.occasions WHERE id=occ),'formLink',(SELECT link FROM public.forms WHERE id=fid));
END $$;

CREATE OR REPLACE FUNCTION public.blueprint_seed_e2e_fixture(p_font_id text)
RETURNS jsonb LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.blueprint_seed_e2e_fixture(p_font_id,NULL::bigint)
$$;
