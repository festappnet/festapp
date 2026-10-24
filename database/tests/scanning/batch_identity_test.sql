BEGIN;
DO $$
DECLARE fx jsonb; oc bigint; fm bigint; tid bigint; oid bigint; stock bigint; bid uuid;
 actor uuid:=gen_random_uuid(); cfg jsonb; dto jsonb; native jsonb; session jsonb; snapshot jsonb; page jsonb; item jsonb; response jsonb;
BEGIN
 fx:=public.scanner_test_fixture();oc:=(fx->>'occasion')::bigint;fm:=(fx->>'form')::bigint;tid:=(fx#>>'{tickets,0}')::bigint;
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE ticket=tid LIMIT 1;
 -- Model a completed anonymous sale, with a separate original stock order.
 UPDATE eshop.orders SET data='{}' WHERE id=oid;
 INSERT INTO auth.users(id,email) VALUES(actor,actor||'@scanner.invalid');
 INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data)
 VALUES(oc,fm,'stock',public.generate_order_symbol(),3,'{}') RETURNING id INTO stock;
 INSERT INTO eshop.ticket_batches(occasion,form,stock_order_id,title,created_by,currency_code,snapshot)
 VALUES(oc,fm,stock,'drahe',actor,'CZK','{}') RETURNING id INTO bid;
 INSERT INTO eshop.ticket_batch_items(batch_id,ticket_id,ordinal,sale_order_id) VALUES(bid,tid,1,oid);
 UPDATE public.scanner_settings SET config=jsonb_set(config,'{manual_search,tickets}','true') WHERE occasion_id=oc RETURNING config INTO cfg;
 SELECT p.dto INTO dto FROM public.scanner_ticket_projection_internal(oc,cfg,tid) p;
 PERFORM assert_eq(dto->>'batch_title','drahe','anonymous ticket has its real batch title');
 PERFORM assert_true(dto->>'purchaser_name' IS NULL,'batch title is not fabricated as purchaser');
 PERFORM assert_true((dto->>'admission_allowed')::boolean,'sold anonymous ticket remains admissible');
 native:=public.scan_ticket(dto->>'symbol',fx->>'scan_code');
 PERFORM assert_eq(native->>'code','200','native scan succeeds without purchaser');
 PERFORM assert_eq(native#>>'{ticket,batch,title}','drahe','native scan carries the same title');
 SELECT value INTO native FROM jsonb_array_elements(public.get_all_tickets_for_scan(fx->>'scan_code')) WHERE (value->>'id')::bigint=tid;
 PERFORM assert_eq(native#>>'{batch,title}','drahe','native manual search carries title');
 session:=(public.open_scanner_session(fx->>'scan_code'))->'data';
 response:=public.search_scanner_tickets((session->>'session_id')::uuid,session->>'token','drahe');
 PERFORM assert_eq(jsonb_array_length(response->'data'),1,'batch name is searchable without customer data');
 snapshot:=(public.prepare_scanner_snapshot((session->>'session_id')::uuid,session->>'token'))->'data';
 FOR page IN SELECT value FROM jsonb_array_elements(snapshot->'pages') LOOP
  response:=public.get_scanner_snapshot_page((session->>'session_id')::uuid,session->>'token',(snapshot->>'snapshot_id')::uuid,(page->>'index')::integer);
  SELECT value INTO item FROM jsonb_array_elements((response#>>'{data,payload_text}')::jsonb) WHERE (value->>'ticket_id')::bigint=tid;
  IF item IS NOT NULL THEN
   PERFORM assert_eq(item->>'batch_title','drahe','offline snapshot preserves title');
   native:=item;
  END IF;
 END LOOP;
 PERFORM assert_eq(native->>'batch_title','drahe','ticket was found in offline snapshot');
 SELECT p.dto INTO dto FROM public.scanner_ticket_projection_internal(oc,cfg,(fx#>>'{tickets,1}')::bigint) p;
 PERFORM assert_false(dto ? 'batch_title','ordinary ticket has no invented batch');
END $$;
ROLLBACK;
