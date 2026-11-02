-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/tests/blueprint/seating_fixture.sql
DO $$
DECLARE f jsonb; c jsonb; r jsonb; actor uuid; tid uuid; occ bigint; frm bigint; bp bigint;
BEGIN
 f:=public.seating_test_fixture_internal();tid:=(f->>'transition')::uuid;occ:=(f->>'occasion')::bigint;frm:=(f->>'form')::bigint;bp:=(f->>'blueprint')::bigint;actor:=(f->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 c:=public.get_seating_transition_context(tid)->'data';
 PERFORM public.assert_eq((c#>>'{counts,unassigned}')::int,9,'all nine ordinary unpaid admissions included');
 PERFORM public.assert_eq((c#>>'{counts,waiting}')::int,1,'waiting separate');
 PERFORM public.assert_eq(jsonb_array_length(c->'compatibility'),1,'waiting-only null product is not an admission compatibility group');
 PERFORM public.assert_eq((c#>>'{compatibility,0,productId}')::bigint,(f->>'product')::bigint,'compatibility references the purchased admission product');
 PERFORM public.assert_eq((c#>>'{compatibility,0,admissions}')::int,9,'waiting does not inflate purchased admission demand');
 r:=public.start_seating_configuration(frm,bp,gen_random_uuid());
 PERFORM public.assert_eq(r#>>'{data,transitionId}',tid::text,'resume stable identity');
 BEGIN INSERT INTO public.form_seating_transitions(occasion,form,blueprint,started_by) VALUES(occ,frm,bp,actor); RAISE EXCEPTION 'direct row write accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 UPDATE public.occasion_users SET is_editor=false WHERE occasion=occ AND "user"=actor;
 SET LOCAL ROLE authenticated;
 c:=public.get_seating_transition_context(tid)->'data';
 PERFORM public.assert_true((c#>>'{capabilities,assign}')::boolean,'order-only operator can assign');
 PERFORM public.assert_eq(jsonb_array_length(c->'items'),10,'order-only holder access');
 RESET ROLE;
 UPDATE public.occasion_users SET is_editor=true,is_editor_order_view=false,is_editor_order=false WHERE occasion=occ AND "user"=actor;
 SET LOCAL ROLE authenticated;
 c:=public.get_seating_transition_context(tid)->'data';
 PERFORM public.assert_eq(jsonb_array_length(c->'items'),0,'config-only has no holders');
 PERFORM public.assert_eq((c#>>'{counts,unassigned}')::int,9,'config-only safe totals');
 BEGIN PERFORM public.preview_ticket_seat_assignment(tid,f->'mappings'); RAISE EXCEPTION 'config role assigned'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.get_seating_transition_context(tid); RAISE EXCEPTION 'outsider context accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END $$;

DO $$
DECLARE f jsonb; occ bigint; frm bigint; actor uuid;
BEGIN
 f:=public.blueprint_test_fixture_internal();occ:=(f->>'occasion')::bigint;frm:=(f->>'form')::bigint;actor:=(f->>'actor')::uuid;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 INSERT INTO public.unit_users(unit,"user",is_editor) SELECT unit,actor,true FROM public.occasions WHERE id=occ;
 UPDATE public.forms SET participant_capacity=10,waitlist_enabled=true,waitlist_offer_duration_seconds=3600 WHERE id=frm;
 -- A newly created blank canonical plan is a usable organizer workspace.
 PERFORM public.update_occasion_internal_v1(jsonb_build_object('id',occ,'features','[{"code":"blueprint","is_enabled":true}]'::jsonb));
 PERFORM public.assert_true((SELECT blueprint IS NULL FROM public.forms WHERE id=frm),'inactive source binding detached');
 PERFORM public.assert_eq((SELECT count(*)::int FROM public.form_seating_transitions WHERE occasion=occ),1,'canonical blank plan starts one configuration');
 PERFORM public.assert_eq(public.get_seating_workspace(occ)#>>'{data,status}','organizer_managed','canonical workspace available');
END $$;
DO $$
DECLARE f jsonb; tr uuid; p jsonb; r jsonb; first_item bigint; first_ticket bigint; second_ticket bigint; second_item bigint; batch uuid; stock bigint; unsold bigint; occ bigint;
BEGIN
 f:=public.seating_test_fixture_internal(4,0);tr:=(f->>'transition')::uuid;occ:=(f->>'occasion')::bigint;
 first_item:=(f#>>'{mappings,0,admissionItemId}')::bigint;first_ticket:=(f#>>'{mappings,0,ticketId}')::bigint;
 second_item:=(f#>>'{mappings,1,admissionItemId}')::bigint;second_ticket:=(f#>>'{mappings,1,ticketId}')::bigint;
 -- Used and printed already placed admissions remain covered but immutable.
 p:=public.preview_ticket_seat_assignment(tr,f->'mappings')->'data';
 r:=public.set_ticket_seat_assignments(tr,f->'mappings',p->>'fingerprint',gen_random_uuid());
 UPDATE eshop.tickets SET state='used' WHERE id=first_ticket;
 stock:=public.allocate_ticket_order_identity_internal((f->>'form')::bigint);
 UPDATE eshop.orders SET state='stock',price=NULL,payment_info=NULL,currency_code='CZK' WHERE id=stock;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'ordered','UNSOLD-'||gen_random_uuid()) RETURNING id INTO unsold;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(stock,unsold,(f->>'product')::bigint);
 INSERT INTO eshop.ticket_batches(occasion,form,stock_order_id,title,created_by,currency_code,snapshot) VALUES(occ,(f->>'form')::bigint,stock,'Print fixture',(f->>'actor')::uuid,'CZK','{}') RETURNING id INTO batch;
 INSERT INTO eshop.ticket_batch_items(batch_id,ticket_id,ordinal) VALUES(batch,second_ticket,1);
 SET LOCAL ROLE authenticated;
 r:=public.get_seating_transition_context(tr)->'data';
 PERFORM public.assert_eq((r#>>'{counts,assigned}')::int,4,'used and printed existing placements remain covered');
 PERFORM public.assert_eq(jsonb_array_length(r->'items'),4,'unsold stock ticket is never an admitted person');
 PERFORM public.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'reason'='USED_TICKET_PROTECTED'),'used row visibly immutable');
 PERFORM public.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'reason'='BATCH_TICKET_PRINT_IMMUTABLE'),'printed row visibly immutable');
 RESET ROLE;
 UPDATE eshop.spots SET order_product_ticket=NULL WHERE order_product_ticket IN(first_item,second_item);
 SET LOCAL ROLE authenticated;
 r:=public.get_seating_transition_context(tr)->'data';
 PERFORM public.assert_eq((r#>>'{counts,blocked}')::int,2,'used and printed without placement visibly block');
 RESET ROLE;
 UPDATE eshop.order_product_ticket SET product=NULL WHERE id=(f#>>'{mappings,2,admissionItemId}')::bigint;
 UPDATE eshop.orders SET state='preparing_payment' WHERE id=(SELECT "order" FROM eshop.order_product_ticket WHERE id=(f#>>'{mappings,3,admissionItemId}')::bigint);
 SET LOCAL ROLE authenticated;
 r:=public.get_seating_transition_context(tr)->'data';
 PERFORM public.assert_eq((r#>>'{counts,blocked}')::int,4,'ambiguous and preparing-payment never disappear');
 RESET ROLE;
 UPDATE public.occasion_users SET is_editor_order_view=false,is_editor=false WHERE occasion=occ AND "user"=(f->>'actor')::uuid;
 INSERT INTO public.unit_users(unit,"user",is_editor) SELECT unit,(f->>'actor')::uuid,true FROM public.occasions WHERE id=occ;
 SET LOCAL ROLE authenticated;
 r:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=occ),(f->>'blueprint')::bigint);
 PERFORM public.assert_eq(r->>'code','200','config-only can enter explicit saved plan reader');
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,tickets}'),0,'config-only reader strips holders');
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,orders}'),0,'config-only reader strips orders');
 RESET ROLE;
END $$;
DO $$
DECLARE f jsonb; r jsonb;
BEGIN
 f:=public.blueprint_test_fixture_internal();PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 UPDATE public.occasions SET features='[{"code":"blueprint","is_enabled":true}]' WHERE id=(f->>'occasion')::bigint;
 SET LOCAL ROLE authenticated;
 r:=public.get_seating_workspace((f->>'occasion')::bigint,(f->>'blueprint')::bigint)->'data';
 PERFORM public.assert_eq(r->>'status','published','existing live plan without transition is usable public mode');
 PERFORM public.assert_false((r#>>'{forms,0,canStart}')::boolean,'existing live source has no impossible start action');
 PERFORM public.assert_eq(r#>>'{forms,0,reason}','TARGET_ALREADY_PUBLIC','live target typed reason');
 RESET ROLE;
END $$;
DO $$
DECLARE f jsonb; cmd uuid:=gen_random_uuid(); r jsonb; replay jsonb;
BEGIN
 f:=public.seating_test_fixture_internal(2,0);
 SET LOCAL ROLE authenticated;
 r:=public.start_seating_configuration((f->>'form')::bigint,(f->>'blueprint')::bigint,cmd);
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,context,items}'),0,'configuration receipt never stores private holders');
 RESET ROLE;
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 replay:=public.start_seating_configuration((f->>'form')::bigint,(f->>'blueprint')::bigint,cmd);
 PERFORM public.assert_eq(replay,r,'config-only replay recovers exact safe receipt after holder access revoked');
 RESET ROLE;
END $$;
