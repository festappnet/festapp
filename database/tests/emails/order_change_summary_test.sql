BEGIN;
DO $$
DECLARE org bigint; u bigint; occ bigint; actor uuid; o bigint; foreign_order bigint;
 t1 bigint; t2 bigint; foreign_ticket bigint; base_id bigint; sent_id bigint;
 original jsonb; current_data jsonb; result jsonb; first_product jsonb;
BEGIN
 PERFORM create_user_for_test('change-summary','change-summary@example.invalid');
 actor:=get_user_id('change-summary');
 INSERT INTO public.organizations(title) VALUES('Change summary') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Change summary',org) RETURNING id INTO u;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(u,actor,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Changes',org,u,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(occ,actor,true,true);
 INSERT INTO eshop.orders(order_symbol, occasion,state,price,currency_code,data) VALUES(public.generate_order_symbol(), occ,'paid',20,'CZK','{}') RETURNING id INTO o;
 INSERT INTO eshop.orders(order_symbol, occasion,state,price,currency_code,data) VALUES(public.generate_order_symbol(), occ,'paid',0,'CZK','{}') RETURNING id INTO foreign_order;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'paid','FIRST') RETURNING id INTO t1;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'paid','SURVIVOR') RETURNING id INTO t2;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'storno','FOREIGN-PRIVATE') RETURNING id INTO foreign_ticket;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(o,t1),(o,t2),(foreign_order,foreign_ticket);
 first_product:='{"id":7,"title":"Place","price":10,"currency_code":"CZK"}';
 original:=jsonb_build_object('tickets',jsonb_build_array(
   jsonb_build_object('id',t1,'products',jsonb_build_array(first_product)),
   jsonb_build_object('id',t2,'products',jsonb_build_array(first_product))));
 UPDATE eshop.orders SET data=original,price=20 WHERE id=o;
 PERFORM assert_eq(public.get_order_change_summary_v1(o)->>'hasChanges','false','No history invents no changes');
 INSERT INTO eshop.orders_history("order",data,price,state,currency_code)
 VALUES(o,original,20,'paid','CZK') RETURNING id INTO base_id;
 PERFORM assert_eq(public.get_order_change_summary_v1(o)->>'hasChanges','false','Unchanged order has no changes');
 UPDATE eshop.orders_history SET data=data||'{"is_sent_to_customer":true}' WHERE id=base_id;
 UPDATE eshop.tickets SET state='storno' WHERE id=t1;
 current_data:=jsonb_build_object('tickets',jsonb_build_array(original#>'{tickets,1}'));
 UPDATE eshop.orders SET data=current_data,price=10 WHERE id=o;
 result:=public.get_order_change_summary_v1(o);
 PERFORM assert_eq(jsonb_array_length(result->'cancelledTickets'),1,'Identical ticket cancellation is explicit');
 PERFORM assert_eq(result#>>'{cancelledTickets,0,ticket_symbol}','FIRST','Missing history symbol uses own actual ticket');
 PERFORM assert_eq(jsonb_array_length(result->'productChanges'),0,'Cancelled products not double counted');
 PERFORM assert_eq((result->>'referenceTotal')::numeric,20::numeric,'Reference total includes both tickets');
 PERFORM assert_eq((result->>'currentTotal')::numeric,10::numeric,'Current total includes survivor');
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM assert_eq(public.get_products_for_ticket(t2)#>>'{data,order_history,is_newer_version_available}','true','Quantity change marks customer history outdated');
 PERFORM assert_eq(public.get_products_for_ticket(t2)#>'{data,order_changes}',result,'Preview consumes canonical summary');
 PERFORM assert_eq(public.get_order_details_for_email(o)#>'{data,order_changes}',result,'Email consumes same canonical summary');
 UPDATE eshop.orders SET data=jsonb_set(current_data,'{tickets,0,products,0,price}','12'),price=12 WHERE id=o;
 result:=public.get_order_change_summary_v1(o);
 PERFORM assert_eq((result->>'currentTotal')::numeric,12::numeric,'Financial total matches persisted order');
 PERFORM assert_eq((result#>>'{productChanges,0,id}')::bigint,t2,'Product changes belong to survivor');
 PERFORM assert_eq((result#>>'{productChanges,0,changed,0,from,price}')::numeric,10::numeric,'Price reference comes from same ticket');
 PERFORM assert_eq(jsonb_array_length(result#>'{productChanges,0,removed}'),0,'Cancellation not called product removal');
 -- Product removal preserves ticket identity, including an empty ticket.
 UPDATE eshop.tickets SET state='paid' WHERE id=t1;
 UPDATE eshop.orders SET data=jsonb_set(original,'{tickets,0,products}','[]'),price=10 WHERE id=o;
 result:=public.get_order_change_summary_v1(o);
 PERFORM assert_eq(jsonb_array_length(result->'cancelledTickets'),0,'Product deletion does not cancel ticket');
 PERFORM assert_eq((result#>>'{productChanges,0,id}')::bigint,t1,'Removed product belongs to surviving ticket');
 PERFORM assert_eq(jsonb_array_length(result#>'{productChanges,0,removed}'),1,'Removed product shown once');
 -- Duplicate product instances remain countable.
 UPDATE eshop.orders_history SET data=jsonb_set(original,'{tickets,0,products}',jsonb_build_array(first_product,first_product))||'{"is_sent_to_customer":true}',price=30 WHERE id=base_id;
 UPDATE eshop.orders SET data=original,price=20 WHERE id=o;
 result:=public.get_order_change_summary_v1(o);
 PERFORM assert_eq(jsonb_array_length(result#>'{productChanges,0,removed}'),1,'Duplicate product quantity is not DISTINCTed away');
 -- Storno labels require actual same-order membership, even for a free ticket.
 UPDATE eshop.orders_history SET data=jsonb_build_object('tickets',jsonb_build_array(jsonb_build_object('id',t1,'products','[]'::jsonb)),'is_sent_to_customer',true),price=0 WHERE id=base_id;
 UPDATE eshop.orders SET data='{"tickets":[]}',price=0 WHERE id=o;
 UPDATE eshop.tickets SET state='storno' WHERE id=t1;
 result:=public.get_order_change_summary_v1(o);
 PERFORM assert_eq((result->>'referenceTotal')::numeric,0::numeric,'Free historical total remains zero');
 PERFORM assert_eq((result->>'currentTotal')::numeric,0::numeric,'Free current total remains zero');
 PERFORM assert_eq(result->>'hasChanges','true','Empty free cancelled ticket is a change');
 PERFORM assert_eq(jsonb_array_length(result->'cancelledTickets'),1,'Empty free ticket is still cancelled');
 UPDATE eshop.orders_history SET data=jsonb_build_object('tickets',jsonb_build_array(jsonb_build_object('id',foreign_ticket,'products','[]'::jsonb)),'is_sent_to_customer',true) WHERE id=base_id;
 result:=public.get_order_change_summary_v1(o);
 PERFORM assert_eq(jsonb_array_length(result->'cancelledTickets'),0,'Foreign storno state is not borrowed');
 PERFORM assert_eq(jsonb_array_length(result->'removedTickets'),1,'Unproven cancellation stays neutral');
 PERFORM assert_eq(result#>>'{removedTickets,0,ticket_symbol}',NULL::text,'No foreign symbol leaks');
 UPDATE eshop.orders_history SET data='{"tickets":[{"products":[]}],"is_sent_to_customer":true}' WHERE id=base_id;
 PERFORM assert_eq(jsonb_array_length(public.get_order_change_summary_v1(o)->'removedTickets'),1,'Missing ID is not guessed');
 -- Baseline follows actual sent history, with deterministic tie-breaking.
 UPDATE eshop.orders_history SET data=original||'{"is_sent_to_customer":true}',price=20 WHERE id=base_id;
 UPDATE eshop.orders SET data=current_data,price=10 WHERE id=o;
 INSERT INTO eshop.orders_history("order",data,price,state,currency_code,created_at)
 VALUES(o,current_data||'{"is_sent_to_customer":true}',10,'paid','CZK',now()) RETURNING id INTO sent_id;
 result:=public.get_order_change_summary_v1(o);
 PERFORM assert_eq((result->>'referenceHistoryId')::bigint,sent_id,'Last sent snapshot wins tied timestamps by ID');
 PERFORM assert_eq(result->>'hasChanges','false','Already sent cancellation is not announced again');
 INSERT INTO eshop.orders_history("order",data,price,state,currency_code) VALUES(o,original,20,'paid','CZK');
 PERFORM assert_eq((public.get_order_change_summary_v1(o)->>'referenceHistoryId')::bigint,sent_id,'Unsent history cannot replace customer baseline');
 UPDATE eshop.orders SET data=original,price=20 WHERE id=o;
 PERFORM assert_eq(jsonb_array_length(public.get_order_change_summary_v1(o)->'addedTickets'),1,'New ticket is its own category');
 UPDATE eshop.orders SET data=current_data,price=11 WHERE id=o;
 result:=public.get_order_change_summary_v1(o);
 PERFORM assert_eq(result->>'hasChanges','true','Stored price-only change is visible');
 PERFORM assert_eq(jsonb_array_length(result->'productChanges'),0,'Price-only change invents no product edits');
 PERFORM assert_eq(has_function_privilege('authenticated','public.get_order_change_summary_v1(bigint)','EXECUTE'),false,'Internal summary is not a public customer-data RPC');
END $$;
ROLLBACK;
