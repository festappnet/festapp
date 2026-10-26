DO $$
<<spot_test>>
DECLARE actor uuid; org bigint; un bigint; oc bigint; oc2 bigint; pool bigint; other_pool bigint; ctx bigint; foreign_ctx bigint;
 r bigint; other_r bigint; slot bigint; foreign_slot bigint; a bigint; b bigint; c bigint; foreign_spot bigint;
 pt bigint; prod bigint; order_id bigint; ticket_id bigint; opt bigint; result jsonb; changes jsonb; cmd uuid;
BEGIN
 PERFORM public.create_user_for_test('spot-boundaries','spot-boundaries@example.invalid');actor:=public.get_user_id('spot-boundaries');
 INSERT INTO public.organizations(title) VALUES('Spots') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Spots',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Spots',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Foreign',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc2;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(oc,actor,true,true);
 INSERT INTO public.inventory_pools(title,occasion) VALUES('Pool',oc) RETURNING id INTO pool;
 INSERT INTO public.inventory_pools(title,occasion) VALUES('Other pool',oc) RETURNING id INTO other_pool;
 INSERT INTO public.inventory_contexts(title,inventory_pool) VALUES('Context',pool) RETURNING id INTO ctx;
 INSERT INTO public.inventory_contexts(title,inventory_pool) VALUES('Other context',other_pool) RETURNING id INTO foreign_ctx;
 INSERT INTO public.resources(title,occasion,inventory_pool,capacity) VALUES('Resource',oc,pool,2) RETURNING id INTO r;
 INSERT INTO public.resources(title,occasion,inventory_pool,capacity) VALUES('Other',oc,other_pool,1) RETURNING id INTO other_r;
 INSERT INTO public.resource_slots(resource,title) VALUES(r,'Slot') RETURNING id INTO slot;
 INSERT INTO public.resource_slots(resource,title) VALUES(other_r,'Foreign slot') RETURNING id INTO foreign_slot;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Seats','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,title,product_type,price,currency_code) VALUES(oc,'Seat',pt,10,'CZK') RETURNING id INTO prod;
 INSERT INTO eshop.spots(occasion,title,inventory_context,product,resource,resource_slot) VALUES(oc,'A',ctx,prod,r,slot) RETURNING id INTO a;
 INSERT INTO eshop.spots(occasion,title,inventory_context,product) VALUES(oc,'B',ctx,prod) RETURNING id INTO b;
 INSERT INTO eshop.spots(occasion,title,inventory_context,product) VALUES(oc,'C',ctx,prod) RETURNING id INTO c;
 INSERT INTO eshop.spots(occasion,inventory_context) VALUES(oc,foreign_ctx) RETURNING id INTO foreign_spot;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 changes:=jsonb_build_array(jsonb_build_object('old_spot_id',a,'new_spot_id',b,'resource_id',r,'resource_slot_id',slot,'inventory_context_id',ctx));cmd:=gen_random_uuid();
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.update_spot_assignments_client_sync_v1(changes,cmd);ASSERT result->>'status'='applied';
 ASSERT public.update_spot_assignments_client_sync_v1(changes,cmd)=result;
 BEGIN PERFORM public.update_spot_assignments_client_sync_v1(changes,gen_random_uuid());RAISE EXCEPTION 'stale old assignment accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.update_spot_assignments_client_sync_v1(jsonb_build_array(jsonb_build_object('new_spot_id',a,'resource_id',r,'resource_slot_id',foreign_slot)),gen_random_uuid());RAISE EXCEPTION 'foreign slot accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.update_spot_assignments_client_sync_v1(jsonb_build_array(jsonb_build_object('new_spot_id',foreign_spot,'resource_id',r)),gen_random_uuid());RAISE EXCEPTION 'foreign context accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 -- A valid first item must roll back when a later assignment exceeds slot capacity.
 BEGIN PERFORM public.update_spot_assignments_client_sync_v1(jsonb_build_array(
  jsonb_build_object('old_spot_id',b,'new_spot_id',a,'resource_id',r,'resource_slot_id',slot),
  jsonb_build_object('new_spot_id',c,'resource_id',r,'resource_slot_id',slot)),gen_random_uuid());
  RAISE EXCEPTION 'duplicate slot accepted';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 EXECUTE 'RESET ROLE';
 ASSERT (SELECT resource IS NULL FROM eshop.spots WHERE id=a);ASSERT (SELECT resource=r FROM eshop.spots WHERE id=b);
 UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=now()+interval '1 hour' WHERE id=c;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.update_spot_assignments_client_sync_v1(jsonb_build_array(jsonb_build_object('new_spot_id',c,'resource_id',r)),gen_random_uuid());RAISE EXCEPTION 'held assignment accepted';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 BEGIN PERFORM public.swap_spot_tickets_client_sync_v1(a,c,gen_random_uuid());RAISE EXCEPTION 'held swap accepted';EXCEPTION WHEN raise_exception THEN
  ASSERT SQLERRM='BLUEPRINT_SEAT_PROTECTED',SQLERRM;END;
 EXECUTE 'RESET ROLE';
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=c;
 INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered') RETURNING id INTO ticket_id;
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,price,currency_code,data) VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'ordered',10,'CZK',
  jsonb_build_object('tickets',jsonb_build_array(jsonb_build_object('id',ticket_id,'products',jsonb_build_array(public._swap_spots_generate_product_json(prod,a)))))) RETURNING id INTO order_id;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,prod) RETURNING id INTO opt;
 UPDATE eshop.spots SET order_product_ticket=opt WHERE id=a;
 cmd:=gen_random_uuid();EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.swap_spot_tickets_client_sync_v1(a,b,cmd);ASSERT result->>'status'='applied';ASSERT public.swap_spot_tickets_client_sync_v1(a,b,cmd)=result;
 EXECUTE 'RESET ROLE';
 ASSERT (SELECT order_product_ticket IS NULL FROM eshop.spots WHERE id=a);ASSERT (SELECT order_product_ticket=opt FROM eshop.spots WHERE id=b);
 ASSERT (SELECT data#>>'{tickets,0,products,0,spot_title}'='B' FROM eshop.orders WHERE id=order_id);
 -- The legacy facade delegates exactly once, preserving its void shape.
 PERFORM public.swap_spot_tickets(a,b);ASSERT (SELECT order_product_ticket=opt FROM eshop.spots WHERE id=a);
 ASSERT NOT has_function_privilege('authenticated','public.update_spot_assignments_internal_v1(jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.swap_spot_tickets_internal_v1(bigint,bigint)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public._swap_spots_update_ticket(bigint,bigint,bigint)','EXECUTE');
END $$;
