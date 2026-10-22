-- Existing admission products remain assignable after their first sale.
-- The existing inventory command owns allocation and preserves addressed seats.
BEGIN;
DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; pt bigint; product_id bigint;
 pool bigint; context_id bigint; order_id bigint; ticket_id bigint; item_id bigint;
 seat_id bigint; before_order jsonb; before_ticket jsonb; before_item jsonb;
 result jsonb;
BEGIN
 PERFORM public.create_user_for_test('standing-existing','standing-existing@example.invalid');
 actor:=public.get_user_id('standing-existing');
 INSERT INTO public.organizations(title) VALUES('Standing existing product') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Standing existing product',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,features)
 VALUES('Standing existing product',org,un,gen_random_uuid()::text,now(),now()+interval '1 day',
 '[{"code":"blueprint","is_enabled":true}]') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,actor,true);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,price,currency_code,occasion,product_type)
 VALUES('Existing seat product',500,'CZK',oc,pt) RETURNING id INTO product_id;
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state)
 VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'ordered') RETURNING id INTO order_id;
 INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered') RETURNING id INTO ticket_id;
 INSERT INTO eshop.order_product_ticket("order",ticket,product)
 VALUES(order_id,ticket_id,product_id) RETURNING id INTO item_id;
 INSERT INTO eshop.spots(occasion,product,order_product_ticket,title)
 VALUES(oc,product_id,item_id,'Existing addressed seat') RETURNING id INTO seat_id;
 SELECT to_jsonb(o) INTO before_order FROM eshop.orders o WHERE id=order_id;
 SELECT to_jsonb(t) INTO before_ticket FROM eshop.tickets t WHERE id=ticket_id;
 SELECT to_jsonb(i) INTO before_item FROM eshop.order_product_ticket i WHERE id=item_id;
 INSERT INTO public.inventory_pools(title,occasion,sellable_capacity)
 VALUES('Standing supply',oc,100) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(title,inventory_pool) VALUES('Standing',pool) RETURNING id INTO context_id;
 INSERT INTO public.resources(title,occasion,inventory_pool,capacity) VALUES('Standing supply',oc,pool,100);
 PERFORM public.adjust_spot_capacity_for_pool(pool);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 result:=public.update_product_inventory_contexts_client_sync_v1(product_id,
   jsonb_build_array(jsonb_build_object('inventory_context_id',context_id,'quantity',1)),gen_random_uuid());
 ASSERT result->>'status'='applied',result::text;
 ASSERT EXISTS(SELECT 1 FROM eshop.spots WHERE id=seat_id AND order_product_ticket=item_id), 'addressed seat changed';
 ASSERT (SELECT count(*)=1 FROM eshop.spots WHERE inventory_context=context_id AND order_product_ticket=item_id), 'existing sale not allocated';
 ASSERT (SELECT to_jsonb(o)=before_order FROM eshop.orders o WHERE id=order_id), 'order changed';
 ASSERT (SELECT to_jsonb(t)=before_ticket FROM eshop.tickets t WHERE id=ticket_id), 'ticket changed';
 ASSERT (SELECT to_jsonb(i)=before_item FROM eshop.order_product_ticket i WHERE id=item_id), 'sold item changed';
 ASSERT (SELECT price=500 FROM eshop.products WHERE id=product_id), 'product price changed';
 -- A later capacity decrease is still rejected by the canonical inventory owner.
 BEGIN
  PERFORM public.update_inventory_pool_bundle(jsonb_build_object('pool',
   jsonb_build_object('id',pool,'occasion',oc,'title','Standing supply','sellable_capacity',0)));
  RAISE EXCEPTION 'capacity below committed sale accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'INVENTORY_CAPACITY_BELOW_COMMITTED' THEN RAISE; END IF;
 END;
 ASSERT (SELECT sellable_capacity=100 FROM public.inventory_pools WHERE id=pool), 'rejected capacity change retained';
END $$;
ROLLBACK;
