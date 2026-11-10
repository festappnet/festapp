-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/tests/blueprint/seating_fixture.sql
DO $$
DECLARE f jsonb; tr bigint; p jsonb; r jsonb; first_item bigint; first_ticket bigint; second_ticket bigint; second_item bigint; batch uuid; stock bigint; unsold bigint; occ bigint;
BEGIN
 f:=public.seating_test_fixture_internal(4,0);tr:=(f->>'blueprint')::bigint;occ:=(f->>'occasion')::bigint;
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
 r:=public.get_blueprint_seating_context(tr)->'data';
 PERFORM public.assert_eq((r#>>'{counts,assigned}')::int,4,'used and printed existing placements remain covered');
 PERFORM public.assert_eq(jsonb_array_length(r->'items'),4,'unsold stock ticket is never an admitted person');
 PERFORM public.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'reason'='USED_TICKET_PROTECTED'),'used row visibly immutable');
 PERFORM public.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'reason'='BATCH_TICKET_PRINT_IMMUTABLE'),'printed row visibly immutable');
 RESET ROLE;
 UPDATE eshop.spots SET order_product_ticket=NULL WHERE order_product_ticket IN(first_item,second_item);
 SET LOCAL ROLE authenticated;
 r:=public.get_blueprint_seating_context(tr)->'data';
 PERFORM public.assert_eq((r#>>'{counts,blocked}')::int,2,'used and printed without placement visibly block');
 RESET ROLE;
 UPDATE eshop.order_product_ticket SET product=NULL WHERE id=(f#>>'{mappings,2,admissionItemId}')::bigint;
 UPDATE eshop.orders SET state='preparing_payment' WHERE id=(SELECT "order" FROM eshop.order_product_ticket WHERE id=(f#>>'{mappings,3,admissionItemId}')::bigint);
 SET LOCAL ROLE authenticated;
 r:=public.get_blueprint_seating_context(tr)->'data';
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
