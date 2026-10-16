DO $$
DECLARE org bigint; unit_id bigint; oc bigint; form_id bigint; other_form bigint;
 actor uuid; oid bigint; state_name text; result jsonb; item jsonb; expected jsonb;
 suffix text := gen_random_uuid()::text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('History bundle test') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('History bundle test',org) RETURNING id INTO unit_id;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('History bundle test',org,unit_id,'history-'||suffix,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.forms(occasion,link,key,title,data,is_open)
 VALUES(oc,'history-form-'||suffix,gen_random_uuid(),'Primary form','{}',true) RETURNING id INTO form_id;
 INSERT INTO public.forms(occasion,link,key,title,data,is_open)
 VALUES(oc,'history-other-'||suffix,gen_random_uuid(),'Other form','{}',true) RETURNING id INTO other_form;
 PERFORM public.create_user_for_test('history_reader','history-reader@example.invalid');
 actor := public.get_user_id('history_reader');
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,actor,true);
 FOREACH state_name IN ARRAY ARRAY['ordered','paid','storno','waitlisted'] LOOP
   INSERT INTO eshop.orders(occasion,form,order_sequence,order_symbol,state,data,price,currency_code)
   VALUES(oc,CASE WHEN state_name='paid' THEN other_form ELSE form_id END,
     public.next_order_sequence(oc),public.generate_order_symbol(),state_name,
     '{"name":"Test","surname":"Reader","email":"reader@example.invalid","note":"Full details"}',
     CASE WHEN state_name='waitlisted' THEN NULL ELSE 100 END,'CZK') RETURNING id INTO oid;
   INSERT INTO eshop.orders_history("order",state,price,currency_code,data,created_by)
   SELECT id,state,price,currency_code,data,actor FROM eshop.orders WHERE id=oid;
 END LOOP;
 PERFORM pg_temp.adopt_public_link_fixtures();
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 result := public.get_orders('history-'||suffix,NULL,
   '{"include_orders_history":true,"include_full_order_data":true}');
 RESET ROLE;
 PERFORM assert_eq((result->>'code')::int,200,'history reader can read its occasion');
 PERFORM assert_eq(jsonb_array_length(result#>'{data,orders}'),4,'all states retained');
 PERFORM assert_eq(jsonb_array_length(result#>'{data,orders_history}'),4,'historical snapshots retained');
 FOR item IN SELECT value FROM jsonb_array_elements(result#>'{data,orders}') LOOP
   expected := public.get_waitlist_summary_internal((item->>'id')::bigint);
   PERFORM assert_eq(item->'isActive',expected->'isActive','activity matches canonical lifecycle');
   PERFORM assert_eq(item->'allowedActions',expected->'allowedActions','actions match canonical lifecycle');
   PERFORM assert_eq(item#>>'{data,note}','Full details','full current snapshot retained');
   IF item->>'state'='waitlisted' THEN
     PERFORM assert_eq(item->'waitlistSummary',expected,'waiting order retains full summary');
   ELSE
     PERFORM assert_eq(item->'waitlistSummary','null'::jsonb,'ordinary order summary remains omitted');
   END IF;
 END LOOP;
 SET LOCAL ROLE authenticated;
 result := public.get_orders(NULL,'history-form-'||suffix,'{"include_orders_history":true}');
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(result#>'{data,orders}'),3,'form filter excludes the other form');
 PERFORM assert_eq(jsonb_array_length(result#>'{data,orders_history}'),3,'history uses the same form filter');
 PERFORM assert_eq(result#>'{data,orders,0,data,note}',NULL::jsonb,'compact current data remains compact');
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE "user"=actor;
 SET LOCAL ROLE authenticated;
 result := public.get_orders('history-'||suffix,NULL,'{"include_orders_history":true}');
 RESET ROLE;
 PERFORM assert_eq((result->>'code')::int,403,'history requires existing order-view permission');
END $$;
