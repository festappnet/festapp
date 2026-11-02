-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/tests/blueprint/seating_fixture.sql
DO $$
DECLARE f jsonb; tid uuid; p jsonb; r jsonb; replay jsonb; cmd uuid:=gen_random_uuid(); snapshot jsonb; finance jsonb; c jsonb; m jsonb; s bigint; iid bigint; ticket bigint;
BEGIN
 f:=public.seating_test_fixture_internal();tid:=(f->>'transition')::uuid;
 SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) INTO snapshot FROM eshop.orders o WHERE occasion=(f->>'occasion')::bigint;
 UPDATE eshop.products SET price=999,title='Changed catalog' WHERE id=(f->>'product')::bigint;
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tid,f->'mappings')->'data';
 PERFORM public.assert_eq(jsonb_array_length(p->'blockers'),0,'nine exact mappings ready');
 r:=public.set_ticket_seat_assignments(tid,f->'mappings',p->>'fingerprint',cmd);
 PERFORM public.assert_eq(r->>'status','applied','nine assigned');
 replay:=public.set_ticket_seat_assignments(tid,f->'mappings',p->>'fingerprint',cmd);
 PERFORM public.assert_eq(replay,r,'exact replay recovers receipt');
 BEGIN PERFORM public.set_ticket_seat_assignments(tid,f->'mappings','changed',cmd); RAISE EXCEPTION 'changed UUID payload accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 c:=public.get_seating_transition_context(tid)->'data';
 PERFORM public.assert_eq((c#>>'{counts,assigned}')::int,9,'all assigned');
 PERFORM public.assert_eq((c#>>'{counts,unassigned}')::int,0,'no outstanding seats');
 PERFORM public.assert_eq((c#>>'{counts,waiting}')::int,1,'waiting remains');
 RESET ROLE;
 PERFORM public.assert_eq((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) FROM eshop.orders o WHERE occasion=(f->>'occasion')::bigint),snapshot,'entire commercial order snapshots unchanged');
 PERFORM public.apply_allocations((SELECT "order" FROM eshop.order_product_ticket WHERE id=(f#>>'{mappings,0,admissionItemId}')::bigint));
 s:=(f#>>'{mappings,0,targetSpotId}')::bigint;iid:=(f#>>'{mappings,0,admissionItemId}')::bigint;ticket:=(f#>>'{mappings,0,ticketId}')::bigint;
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=s),iid,'ordinary reconciliation preserves placement');
 m:=jsonb_build_array(jsonb_build_object('ticketId',ticket,'admissionItemId',iid,'expectedSpotId',s,'targetSpotId',NULL));
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tid,m)->'data';
 RESET ROLE;
 UPDATE eshop.tickets SET state='used' WHERE id=ticket;
 SET LOCAL ROLE authenticated;
 r:=public.set_ticket_seat_assignments(tid,m,p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','conflict','used after review protected');
 RESET ROLE;
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=s),iid,'used placement preserved');
 UPDATE eshop.tickets SET state='ordered' WHERE id=ticket;
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tid,m)->'data';
 r:=public.set_ticket_seat_assignments(tid,m,p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','explicit release');
 RESET ROLE;
 PERFORM public.assert_true((SELECT order_product_ticket IS NULL FROM eshop.spots WHERE id=s),'released exact seat');
END $$;
DO $$
DECLARE f jsonb; tr uuid; p jsonb; r jsonb; mappings jsonb; first_pair jsonb; second_pair jsonb; second_form bigint; second_order bigint; spots bigint[]; unit uuid:=gen_random_uuid(); pool bigint; ctx bigint; iid bigint; oid bigint;
BEGIN
 f:=public.seating_test_fixture_internal(2,0);tr:=(f->>'transition')::uuid;spots:=ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(f->'spots'));
 UPDATE eshop.blueprint_seat_bindings SET selection_unit=unit WHERE spot=ANY(spots[1:2]);
 first_pair:=f->'mappings'->0;second_pair:=f->'mappings'->1;
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tr,jsonb_build_array(first_pair))->'data';
 PERFORM public.assert_eq(p#>>'{blockers,0,reason}','ATOMIC_UNIT_INCOMPLETE','couch needs explicit second entitlement');
 RESET ROLE;
 -- A couch can span two authorized source forms in one cohort.
 INSERT INTO public.forms(occasion,title,is_open) VALUES((f->>'occasion')::bigint,'Second source',true) RETURNING id INTO second_form;
 SELECT "order" INTO second_order FROM eshop.order_product_ticket WHERE id=(second_pair->>'admissionItemId')::bigint;
 UPDATE eshop.orders SET form=second_form WHERE id=second_order;
 r:=public.start_seating_configuration(second_form,(f->>'blueprint')::bigint,gen_random_uuid());
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tr,f->'mappings')->'data';
 PERFORM public.assert_eq(jsonb_array_length(p->'revisions'),2,'two source revisions reviewed');
 r:=public.set_ticket_seat_assignments(tr,f->'mappings',p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','mixed-form atomic couch committed');
 RESET ROLE;
 -- Context-linked seat exchanges the purchased PIC allocation, never doubles it.
 f:=public.seating_test_fixture_internal(1,0);tr:=(f->>'transition')::uuid;iid:=(f#>>'{mappings,0,admissionItemId}')::bigint;
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE id=iid;
 INSERT INTO public.inventory_pools(occasion,sellable_capacity) VALUES((f->>'occasion')::bigint,1) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool) VALUES(pool) RETURNING id INTO ctx;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES((f->>'product')::bigint,ctx,1);
 INSERT INTO eshop.spots(occasion,inventory_context,order_product_ticket,state) VALUES((f->>'occasion')::bigint,ctx,iid,'ordered');
 UPDATE eshop.spots SET inventory_context=ctx WHERE id=(f#>>'{mappings,0,targetSpotId}')::bigint;
 UPDATE eshop.products SET maximum=1 WHERE id=(f->>'product')::bigint;
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tr,f->'mappings')->'data';
 r:=public.set_ticket_seat_assignments(tr,f->'mappings',p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','sold out entitlement assigned without another purchase');
 RESET ROLE;
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.spots WHERE order_product_ticket=iid AND inventory_context=ctx),1,'one PIC allocation');
 PERFORM public.apply_allocations(oid);
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.spots WHERE order_product_ticket=iid AND inventory_context=ctx),1,'reconciliation preserves PIC exchange');
END $$;
DO $$
DECLARE f jsonb; tr uuid; req jsonb; r jsonb; p jsonb; area uuid:=gen_random_uuid(); pool bigint; ctx bigint; res bigint; oid bigint; seat bigint; item bigint;
BEGIN
 f:=public.seating_test_fixture_internal(1,0);tr:=(f->>'transition')::uuid;item:=(f#>>'{mappings,0,admissionItemId}')::bigint;
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE id=item;
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES((f->>'occasion')::bigint,'Standing','generic',5) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Standing') RETURNING id INTO ctx;
 INSERT INTO public.resources(inventory_pool,occasion,title,capacity) VALUES(pool,(f->>'occasion')::bigint,'Standing',5) RETURNING id INTO res;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES((f->>'product')::bigint,ctx,1);
 PERFORM public.adjust_spot_capacity_for_pool(pool);
 PERFORM public.apply_allocations(oid);
 SELECT jsonb_build_object('id',b.id,'occasion',b.occasion,'organization',b.organization,'expected_layout_revision',b.layout_revision,'layout',b.layout,'textResourceIds','[]'::jsonb,'groupProductChanges','[]'::jsonb) INTO req FROM eshop.blueprints b WHERE id=(f->>'blueprint')::bigint;
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object('id',area,'kind','capacityArea','width',100,'height',100,'transform',jsonb_build_object('x',400,'y',400,'rotation',0))));
 req:=req||jsonb_build_object('seatChanges',(SELECT jsonb_agg(jsonb_build_object('nodeId',sb.node_id,'spotId',s.id,'productId',NULL,'title',s.title,'groupNodeId',sb.group_node,'selectionUnitId',sb.selection_unit,'blocked',sb.blocked,'operation','upsert','productAssignmentMode',sb.product_assignment_mode)) FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot WHERE sb.blueprint=(f->>'blueprint')::bigint),
 'areaBindingChanges',jsonb_build_array(jsonb_build_object('nodeId',area,'productId',f->'product','inventoryContextId',ctx,'operation','upsert','capacity',5)));
 req:=jsonb_set(req,'{textResourceIds}',to_jsonb(public.blueprint_text_resource_ids_internal(req->'layout',(f->>'occasion')::bigint)));
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 IF r->>'status'<>'applied' THEN RAISE EXCEPTION 'standing fixture rejected %',r; END IF;
 PERFORM public.assert_eq(r->>'status','applied','canonical saved standing-only area');
 SET LOCAL ROLE authenticated;
 r:=public.get_seating_transition_context(tr)->'data';
 PERFORM public.assert_eq((r#>>'{counts,standing}')::int,1,'existing PIC allocation is standing coverage');
 RESET ROLE;
 UPDATE eshop.tickets SET state='used' WHERE id=(f#>>'{mappings,0,ticketId}')::bigint;
 SET LOCAL ROLE authenticated;
 r:=public.get_seating_transition_context(tr)->'data';
 PERFORM public.assert_eq((r#>>'{counts,standing}')::int,1,'used valid standing remains covered');
 RESET ROLE;
 UPDATE eshop.tickets SET state='ordered' WHERE id=(f#>>'{mappings,0,ticketId}')::bigint;
 UPDATE eshop.spots SET product=(f->>'product')::bigint WHERE id=(f#>>'{mappings,0,targetSpotId}')::bigint;
 SET LOCAL ROLE authenticated;
 r:=public.get_seating_transition_context(tr)->'data';
 PERFORM public.assert_eq(r#>>'{items,0,reason}','PLACEMENT_MODE_AMBIGUOUS','mixed seat/standing SKU blocked without guessing');
 RESET ROLE;
END $$;

DO $$
DECLARE f jsonb; tr uuid; p jsonb; r jsonb; m jsonb; spot_a bigint; spot_b bigint; item bigint;
BEGIN
 f:=public.seating_test_fixture_internal(1,0);tr:=(f->>'transition')::uuid;
 p:=public.preview_ticket_seat_assignment(tr,f->'mappings')->'data';
 r:=public.set_ticket_seat_assignments(tr,f->'mappings',p->>'fingerprint',gen_random_uuid());
 spot_a:=(f#>>'{spots,0}')::bigint;spot_b:=(f#>>'{spots,1}')::bigint;item:=(f#>>'{mappings,0,admissionItemId}')::bigint;
 -- Retained partial-unit data must not masquerade as a full two-person mapping
 -- just because one person's before+after spots span both members.
 UPDATE eshop.blueprint_seat_bindings SET selection_unit=gen_random_uuid() WHERE spot=spot_a;
 UPDATE eshop.blueprint_seat_bindings SET selection_unit=(SELECT selection_unit FROM eshop.blueprint_seat_bindings WHERE spot=spot_a) WHERE spot=spot_b;
 m:=jsonb_build_array(jsonb_build_object('ticketId',f#>'{mappings,0,ticketId}','admissionItemId',item,'expectedSpotId',spot_a,'targetSpotId',spot_b));
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tr,m)->'data';
 PERFORM public.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(p->'blockers') b WHERE b->>'reason'='ATOMIC_UNIT_INCOMPLETE'),'before+after union cannot invent another couch entitlement');
 r:=public.set_ticket_seat_assignments(tr,m,p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','conflict','partial-unit mapping cannot commit');
 RESET ROLE;
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=spot_a),item,'failed partial-unit move preserves exact placement');
END $$;

DO $$
DECLARE f jsonb; tr uuid; p jsonb; r jsonb; first_two jsonb; m jsonb; a bigint; b bigint; c bigint; unit uuid:=gen_random_uuid();
BEGIN
 f:=public.seating_test_fixture_internal(3,0);tr:=(f->>'transition')::uuid;
 a:=(f#>>'{spots,0}')::bigint;b:=(f#>>'{spots,1}')::bigint;c:=(f#>>'{spots,2}')::bigint;
 UPDATE eshop.blueprint_seat_bindings SET selection_unit=unit WHERE spot IN(a,b);
 first_two:=jsonb_build_array(f->'mappings'->0,f->'mappings'->1);
 p:=public.preview_ticket_seat_assignment(tr,first_two)->'data';
 r:=public.set_ticket_seat_assignments(tr,first_two,p->>'fingerprint',gen_random_uuid());
 m:=jsonb_build_array((f->'mappings'->0)||jsonb_build_object('expectedSpotId',a),
 (f->'mappings'->1)||jsonb_build_object('expectedSpotId',b,'targetSpotId',c),
 (f->'mappings'->2)||jsonb_build_object('targetSpotId',b));
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tr,m)->'data';
 PERFORM public.assert_eq(jsonb_array_length(p->'blockers'),0,'unchanged reviewed member is allowed within a changed complete unit batch');
 r:=public.set_ticket_seat_assignments(tr,m,p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','complete couch membership can change without moving its retained member');
 BEGIN PERFORM public.preview_ticket_seat_assignment(tr,jsonb_build_array(m->0));RAISE EXCEPTION 'entire no-op batch accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 RESET ROLE;
END $$;

DO $$
DECLARE f jsonb; pool bigint; ctx bigint; legacy bigint; stock bigint; item bigint; oid bigint;
BEGIN
 f:=public.seating_test_fixture_internal(1,0);item:=(f#>>'{mappings,0,admissionItemId}')::bigint;
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE id=item;
 INSERT INTO public.inventory_pools(occasion,sellable_capacity) VALUES((f->>'occasion')::bigint,1) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool) VALUES(pool) RETURNING id INTO ctx;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES((f->>'product')::bigint,ctx,1);
 -- Both current and retained pre-binding addressed seats are physical seats,
 -- not arbitrary free stock for an ordinary order reconciliation.
 INSERT INTO eshop.spots(occasion,blueprint,product,inventory_context,title) VALUES((f->>'occasion')::bigint,(f->>'blueprint')::bigint,(f->>'product')::bigint,ctx,'Retained legacy seat') RETURNING id INTO legacy;
 INSERT INTO eshop.spots(occasion,inventory_context) VALUES((f->>'occasion')::bigint,ctx) RETURNING id INTO stock;
 PERFORM public.apply_allocations(oid);
 PERFORM public.assert_true((SELECT order_product_ticket IS NULL FROM eshop.spots WHERE id=legacy),'ordinary inventory does not claim an unbound legacy seat');
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=stock),item,'ordinary entitlement uses generic inventory stock');
END $$;
