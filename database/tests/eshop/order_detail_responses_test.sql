-- test-setup: database/tests/blueprint/fixtures.sql
DO $$
DECLARE f jsonb; oc bigint; form_id bigint; oid bigint; tid bigint; ofield bigint; tfield bigint; unsupported bigint; email_field bigint; note_field bigint; hidden_note_field bigint; r jsonb; before_fields jsonb; order_fields jsonb; before_orders jsonb; reader uuid:=gen_random_uuid();
BEGIN
 f:=public.blueprint_test_fixture_internal();oc:=(f->>'occasion')::bigint;form_id:=(f->>'form')::bigint;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 INSERT INTO public.form_fields(form,type,title,is_ticket_field) VALUES(form_id,'text','Company',false) RETURNING id INTO ofield;
 INSERT INTO public.form_fields(form,type,title,is_ticket_field,data) VALUES(form_id,'select_one','Order choice',false,'{"options":[{"value":"Soup"},{"value":"Salad"}]}') RETURNING id INTO tfield;
 INSERT INTO public.form_fields(form,type,title,is_ticket_field) VALUES(form_id,'name','Unsupported ticket field',true) RETURNING id INTO unsupported;
 INSERT INTO public.form_fields(form,type,title,is_ticket_field) VALUES(form_id,'email','Email',false) RETURNING id INTO email_field;
 INSERT INTO public.form_fields(form,type,title,is_ticket_field,is_hidden) VALUES(form_id,'note','Customer note',false,false) RETURNING id INTO note_field;
 INSERT INTO public.form_fields(form,type,title,is_ticket_field,is_hidden) VALUES(form_id,'note','Hidden form note',false,true) RETURNING id INTO hidden_note_field;
 oid:=public.allocate_ticket_order_identity_internal(form_id);
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data) VALUES(oc,'paid','ANSWER-ONE','{"fields":[]}'::jsonb) RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,(f->>'product')::bigint);
 UPDATE eshop.orders SET state='paid',price=100,currency_code='CZK',note_hidden='Internal memo',data=jsonb_build_object('note','Original customer note','fields','[]'::jsonb,'tickets',jsonb_build_array(jsonb_build_object('id',tid,'products',jsonb_build_array(jsonb_build_object('id',f->'product','title','Historical product','price',100))))) WHERE id=oid;
 PERFORM assert_true(to_regprocedure('public.update_order_detail_responses(bigint,bigint,bigint,jsonb,jsonb)') IS NULL,'unsupported ticket response writer removed');
 PERFORM assert_false(has_function_privilege('anon','public.update_order_detail_responses(bigint,bigint,jsonb,jsonb)','EXECUTE'),'anonymous cannot edit');
 INSERT INTO auth.users(id) VALUES(reader);
 INSERT INTO public.user_info(id,organization) SELECT reader,organization FROM public.occasions WHERE id=oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor_order,is_editor) VALUES(oc,reader,true,false,false);
 PERFORM set_config('request.jwt.claim.sub',reader::text,true);
 SET LOCAL ROLE authenticated;
 r:=public.update_order_detail_responses(oid,form_id,'[]',jsonb_build_object(ofield::text,'Reader write'));
 PERFORM assert_eq(r->>'code','404','reader cannot mutate');
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 SET LOCAL ROLE authenticated;
 r:=public.update_order_detail_responses(oid,form_id+9999,'[]',jsonb_build_object(ofield::text,'Wrong form'));
 PERFORM assert_eq(r->>'code','404','wrong form rejected');
 r:=public.update_order_detail_responses(oid,form_id,'[]',jsonb_build_object(ofield::text,'Local company'));
 PERFORM assert_eq(r->>'code','200','existing order response owner succeeds');
 r:=public.update_order_detail_responses(oid,form_id,'[]',jsonb_build_object(ofield::text,'Stale overwrite'));
 PERFORM assert_eq(r->>'code','409','stale order answers rejected');
 RESET ROLE;
 SELECT data->'fields' INTO order_fields FROM eshop.orders WHERE id=oid;
 SET LOCAL ROLE authenticated;
 r:=public.update_order_detail_responses(oid,form_id,order_fields,jsonb_build_object(tfield::text,'Salad'));
 PERFORM assert_eq(r->>'code','200','configured order choice updated');
 RESET ROLE;
 SELECT data->'fields' INTO before_fields FROM eshop.orders WHERE id=oid;
 SELECT data->'fields' INTO order_fields FROM eshop.orders WHERE id=oid;
 PERFORM assert_eq((SELECT value->>tfield::text FROM jsonb_array_elements(before_fields) WHERE value ? tfield::text),'Salad','order choice persisted');
 PERFORM assert_eq((SELECT data#>>'{tickets,0,products,0,title}' FROM eshop.orders WHERE id=oid),'Historical product','snapshot title retained');
 PERFORM assert_eq((SELECT data#>>'{tickets,0,products,0,price}' FROM eshop.orders WHERE id=oid),'100','snapshot price retained');
 PERFORM assert_true((SELECT data->'fields' @> jsonb_build_array(jsonb_build_object(ofield::text,'Local company')) FROM eshop.orders WHERE id=oid),'second order edit preserves first answer');
 SET LOCAL ROLE authenticated;
 r:=public.update_order_detail_responses(oid,form_id,before_fields,jsonb_build_object(note_field::text,E'First line\nSecond line',ofield::text,'Updated company'));
 PERFORM assert_eq(r->>'code','200','legacy customer note can be edited with another answer');
 r:=public.update_order_detail_responses(oid,form_id,before_fields,jsonb_build_object(note_field::text,'Stale note'));
 PERFORM assert_eq(r->>'code','409','stale customer note rejected');
 RESET ROLE;
 SELECT data->'fields' INTO before_fields FROM eshop.orders WHERE id=oid;
 PERFORM assert_eq((SELECT value->>note_field::text FROM jsonb_array_elements(before_fields) WHERE value ? note_field::text),E'First line\nSecond line','form note persisted');
 PERFORM assert_eq((SELECT data->>'note' FROM eshop.orders WHERE id=oid),E'First line\nSecond line','order note projection updated');
 PERFORM assert_true(before_fields @> jsonb_build_array(jsonb_build_object(ofield::text,'Updated company')),'other answer persisted in the same write');
 PERFORM assert_eq((SELECT note_hidden FROM eshop.orders WHERE id=oid),'Internal memo','internal memo retained');
 PERFORM assert_eq((SELECT data->>'note' FROM eshop.orders_history WHERE "order"=oid ORDER BY id DESC LIMIT 1),E'First line\nSecond line','customer note recorded in order history');
 SET LOCAL ROLE authenticated;
 r:=public.update_order_detail_responses(oid,form_id,before_fields,jsonb_build_object(note_field::text,''));
 PERFORM assert_eq(r->>'code','200','customer note can be cleared');
 RESET ROLE;
 SELECT data->'fields' INTO before_fields FROM eshop.orders WHERE id=oid;
 PERFORM assert_eq((SELECT value->>note_field::text FROM jsonb_array_elements(before_fields) WHERE value ? note_field::text),'','form note cleared');
 PERFORM assert_eq((SELECT data->>'note' FROM eshop.orders WHERE id=oid),'','order note projection cleared');
 order_fields:=before_fields;
 SET LOCAL ROLE authenticated;
 BEGIN
   PERFORM public.update_order_detail_responses(oid,form_id,before_fields,jsonb_build_object(hidden_note_field::text,'Hidden note'));
   RAISE EXCEPTION 'Hidden form note unexpectedly accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
   PERFORM public.update_order_detail_responses(oid,form_id,before_fields,jsonb_build_object(unsupported::text,'Cross scope'));
   RAISE EXCEPTION 'Cross scope unexpectedly accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
   PERFORM public.update_order_detail_responses(oid,form_id,before_fields,jsonb_build_object(tfield::text,'Not configured'));
   RAISE EXCEPTION 'Unknown option unexpectedly accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
   PERFORM public.update_order_detail_responses(oid,form_id,order_fields,jsonb_build_object(email_field::text,'changed@example.invalid'));
   RAISE EXCEPTION 'Email bypass unexpectedly accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 RESET ROLE;
 UPDATE eshop.orders SET state='storno' WHERE id=oid;
 SET LOCAL ROLE authenticated;
 BEGIN
   PERFORM public.update_order_detail_responses(oid,form_id,before_fields,jsonb_build_object(note_field::text,'Cancelled note'));
   RAISE EXCEPTION 'Cancelled note unexpectedly accepted';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN
   PERFORM assert_true(SQLERRM LIKE 'ORDER_CANCELLED:%','cancelled order rejected');
 END;
 RESET ROLE;
END $$;
