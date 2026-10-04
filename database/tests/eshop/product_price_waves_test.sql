DO $$
DECLARE actor uuid; org bigint; unit_id bigint; occ bigint; other_occ bigint; pt bigint; prod bigint; prod2 bigint;
 w1 jsonb; w2 jsonb; w3 jsonb; plan jsonb; price_id bigint; n int;
 link text:='price-wave-'||gen_random_uuid(); result jsonb;
BEGIN
 SELECT id,organization INTO actor,org FROM public.user_info WHERE id=(SELECT id FROM auth.users WHERE email LIKE '%+t@t.com');
 SELECT id INTO unit_id FROM public.units WHERE organization=org LIMIT 1;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) VALUES(org,unit_id,'Waves',link,now(),now()+interval '40 days') RETURNING id INTO occ;
 INSERT INTO public.occasion_users("user",occasion,is_editor_order,is_editor_order_view) VALUES(actor,occ,true,true);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Wave products','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) VALUES(occ,pt,'First',450,'CZK',false) RETURNING id INTO prod;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) VALUES(occ,pt,'Second',100,'CZK',false) RETURNING id INTO prod2;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 w1:=public.create_product_price_wave(link,now()+interval '10 days');
 w2:=public.create_product_price_wave(link,now()+interval '20 days');
 PERFORM public.save_product_wave_target((w1->>'id')::bigint,prod,1,550,true);
 PERFORM public.save_product_wave_target((w1->>'id')::bigint,prod2,1,NULL,false);
 BEGIN PERFORM public.save_product_wave_target((w1->>'id')::bigint,prod,1,600,false); RAISE EXCEPTION 'stale target accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 result:=public.get_products_and_types_for_edit(link)::jsonb;
 PERFORM assert_eq(jsonb_array_length(result->'price_waves'),2,'Empty future wave is persisted and readable');
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE wave_id=(w1->>'id')::bigint),3,'Price and visibility are independent targets');
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=prod),450::numeric,'Scheduling does not reprice');
 PERFORM assert_false((SELECT is_hidden FROM eshop.products WHERE id=prod),'Scheduling does not hide early');
 PERFORM assert_false(has_table_privilege('authenticated','eshop.product_price_waves','SELECT'),'No direct wave reads');
 PERFORM assert_false(has_table_privilege('anon','eshop.product_price_waves','TRUNCATE'),'No direct destructive bypass');
 BEGIN PERFORM public.save_product_wave_target((w1->>'id')::bigint,prod,1,-1,false,1,1); RAISE EXCEPTION 'invalid price accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_eq((SELECT new_value FROM eshop.planned_changes WHERE wave_id=(w1->>'id')::bigint AND subject_id=prod AND change_type='products.is_hidden'),'true','Invalid price rolls back visibility');
 BEGIN PERFORM public.cancel_product_price_wave((w1->>'id')::bigint,NULL); RAISE EXCEPTION 'null revision accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 -- Wave revision fences an empty cell after the shared term changes.
 w2:=public.move_product_price_wave((w2->>'id')::bigint,1,now()+interval '21 days');
 BEGIN PERFORM public.save_product_wave_target((w2->>'id')::bigint,prod2,1,NULL,true); RAISE EXCEPTION 'stale wave accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 -- A single-product edit may leave a wave, but must not move its other targets.
 SELECT id INTO price_id FROM eshop.planned_changes WHERE wave_id=(w1->>'id')::bigint AND subject_id=prod AND change_type='products.price';
 plan:=public.save_product_price_change(prod,575,now()+interval '11 days',price_id,1);
 PERFORM assert_true(plan->>'wave_id' IS NULL,'Moving an individual target detaches it from the shared term');
 PERFORM assert_eq((SELECT change_time FROM eshop.planned_changes WHERE wave_id=(w1->>'id')::bigint AND subject_id=prod AND change_type='products.is_hidden'),(w1->>'change_time')::timestamptz,'Moving price leaves visibility queued');
 PERFORM public.save_product_wave_target((w1->>'id')::bigint,prod,1,600,true,NULL,1);
 -- Move all price/availability targets together, preserving unrelated plans.
 w1:=public.move_product_price_wave((w1->>'id')::bigint,1,now()+interval '12 days');
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE wave_id=(w1->>'id')::bigint AND change_time=(w1->>'change_time')::timestamptz),3,'Shared term moves every remaining target');
 PERFORM assert_eq((SELECT change_time FROM eshop.planned_changes WHERE id=price_id),now()+interval '11 days','Independent target remains unchanged');
 BEGIN PERFORM public.save_product_wave_target((w1->>'id')::bigint,prod,2,650,false,1,2); RAISE EXCEPTION 'old target revision accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 -- Explicit clearing removes only this product's targets in this wave.
 PERFORM public.save_product_wave_target((w1->>'id')::bigint,prod,2,NULL,NULL,2,3);
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE wave_id=(w1->>'id')::bigint AND subject_id=prod),0,'Empty price/unchanged visibility clears only selected targets');
 PERFORM public.cancel_product_price_wave((w1->>'id')::bigint,2);
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.planned_changes WHERE id=price_id),'Cancelling wave preserves independent queue entries');
 -- Legacy price and visibility plans at a common term are adopted without rewriting values.
 INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion) VALUES('products.price',prod,'750',now()+interval '25 days',occ),('products.is_hidden',prod,'true',now()+interval '25 days',occ);
 w3:=public.create_product_price_wave(link,now()+interval '25 days');
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE wave_id=(w3->>'id')::bigint),2,'Existing queue is projected into shared waves');
 UPDATE public.occasion_users SET is_editor_order=false WHERE "user"=actor AND occasion=occ;
 BEGIN PERFORM public.save_product_wave_target((w3->>'id')::bigint,prod,1,800,false,1,1); RAISE EXCEPTION 'viewer wrote wave'; EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM='viewer wrote wave' THEN RAISE; END IF; END;
 UPDATE public.occasion_users SET is_editor_order=true WHERE "user"=actor AND occasion=occ;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.cancel_product_price_wave((w3->>'id')::bigint,1); RAISE EXCEPTION 'foreign user cancelled wave'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 BEGIN PERFORM public.save_product_wave_target((w3->>'id')::bigint,-999,1,800,true); RAISE EXCEPTION 'unknown product accepted'; EXCEPTION WHEN no_data_found THEN NULL; END;
 -- Existing executor applies both target types, emits inventory sync and is idempotent.
 UPDATE eshop.planned_changes SET change_time=now()-interval '1 minute' WHERE wave_id=(w3->>'id')::bigint;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 SELECT count(*)::int INTO n FROM public.client_commits WHERE occasion=occ;
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=prod),750::numeric,'Due wave changes price');
 PERFORM assert_true((SELECT is_hidden FROM eshop.products WHERE id=prod),'Due wave hides product');
 PERFORM assert_eq((SELECT count(*)::int FROM public.client_commits WHERE occasion=occ),n+2,'Both actual product mutations emit inventory sync');
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT count(*)::int FROM public.client_commits WHERE occasion=occ),n+2,'Retry does not repeat sync');
 BEGIN PERFORM public.move_product_price_wave((w3->>'id')::bigint,1,now()+interval '30 days'); RAISE EXCEPTION 'applied wave moved'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM public.cancel_product_price_wave((w3->>'id')::bigint,1);
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE subject_id=prod AND applied),2,'Cancel preserves applied queue history');
 PERFORM assert_true((SELECT is_hidden FROM eshop.products WHERE id=prod),'Cancel does not undo already applied visibility');
 -- Deleting a product cleans pending visibility as well as prices.
 PERFORM public.delete_product(prod2);
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.planned_changes WHERE subject_id=prod2 AND NOT applied),'Product deletion removes scheduled visibility');
END $$;
