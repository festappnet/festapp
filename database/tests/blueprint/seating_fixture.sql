-- test support only: use saved canonical layout and actual lifecycle RPC.
CREATE OR REPLACE FUNCTION public.seating_test_fixture_internal(p_admitted integer DEFAULT 9,p_waiting integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE f jsonb; req jsonb; d jsonb; node uuid; i integer; oid bigint; tid bigint; iid bigint; tickets jsonb:='[]'; mappings jsonb:='[]'; spots bigint[]; tr uuid; r jsonb;
BEGIN
 f:=public.blueprint_test_fixture_internal();
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 req:=f->'request'; d:=req->'layout';
 FOR i IN 5..12 LOOP
 node:=gen_random_uuid();
 d:=jsonb_set(d,'{nodes}',d->'nodes'||jsonb_build_array(jsonb_build_object('id',node,'kind','seat','width',40,'height',40,'transform',jsonb_build_object('x',i*60,'y',60,'rotation',0))));
 req:=jsonb_set(req,'{seatChanges}',req->'seatChanges'||jsonb_build_array(jsonb_build_object('productAssignmentMode','override','nodeId',node,'spotId',NULL,'productId',f->'product','title','S'||i,'groupNodeId',NULL,'selectionUnitId',NULL,'blocked',false,'operation','upsert')));
 END LOOP;
 req:=jsonb_set(req,'{layout}',d);
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 IF r->>'status'<>'applied' THEN RAISE EXCEPTION 'fixture layout failed %',r; END IF;
 UPDATE public.forms SET blueprint=NULL,participant_capacity=10,waitlist_enabled=true,waitlist_offer_duration_seconds=3600 WHERE id=(f->>'form')::bigint;
 UPDATE public.occasions SET features='[{"code":"blueprint","is_enabled":true}]' WHERE id=(f->>'occasion')::bigint;
 tr:=(public.start_seating_configuration((f->>'form')::bigint,(f->>'blueprint')::bigint,gen_random_uuid())#>>'{data,transitionId}')::uuid;
 SELECT array_agg(spot ORDER BY spot) INTO spots FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint;
 FOR i IN 1..p_admitted+p_waiting LOOP
 oid:=public.allocate_ticket_order_identity_internal((f->>'form')::bigint);
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES((f->>'occasion')::bigint,CASE WHEN i>p_admitted THEN 'waitlisted' ELSE 'ordered' END,CASE WHEN i<=p_admitted THEN 'SEAT-'||gen_random_uuid()::text END) RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,CASE WHEN i<=p_admitted THEN (f->>'product')::bigint END) RETURNING id INTO iid;
 UPDATE eshop.orders SET state=CASE WHEN i>p_admitted THEN 'waitlisted' ELSE 'ordered' END,price=CASE WHEN i<=p_admitted THEN 42 ELSE NULL END,
 data=jsonb_build_object('name','Holder '||i,'tickets',jsonb_build_array(jsonb_build_object('id',tid,'products',CASE WHEN i<=p_admitted THEN jsonb_build_array(jsonb_build_object('id',f->'product','price',42,'currency_code','CZK','title','Purchased title')) ELSE '[]'::jsonb END))) WHERE id=oid;
 IF i<=p_admitted THEN mappings:=mappings||jsonb_build_array(jsonb_build_object('ticketId',tid,'admissionItemId',iid,'expectedSpotId',NULL,'targetSpotId',spots[i])); END IF;
 END LOOP;
 RETURN f||jsonb_build_object('transition',tr,'mappings',mappings,'spots',spots);
END $$;
