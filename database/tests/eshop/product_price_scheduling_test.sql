DO $$
DECLARE
 org bigint; unit_id bigint; occ bigint; pt bigint; prod bigint; other_prod bigint; fid bigint;
 actor uuid; outsider uuid; c1 jsonb; c2 jsonb; c3 jsonb; mid jsonb; result jsonb; first_id bigint;
 n integer; link text := 'price-scheduling-'||gen_random_uuid();
BEGIN
 PERFORM assert_false(has_table_privilege('authenticated','eshop.planned_changes','TRUNCATE'),'Editor cannot bypass cancellation with TRUNCATE');
 PERFORM assert_false(has_table_privilege('anon','eshop.planned_changes','SELECT'),'Public clients cannot inspect unpublished prices directly');
 SELECT id,organization INTO actor,org FROM public.user_info WHERE id=(SELECT id FROM auth.users WHERE email LIKE '%+t@t.com');
 SELECT id INTO unit_id FROM public.units WHERE organization=org LIMIT 1;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,unit_id,'Scheduled prices',link,now(),now()+interval '30 days') RETURNING id INTO occ;
 INSERT INTO public.occasion_users("user",occasion,is_editor_order,is_editor_order_view) VALUES(actor,occ,true,true);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Tickets','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(occ,pt,'Ticket',450,'CZK') RETURNING id INTO prod;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(occ,pt,'Other',100,'CZK') RETURNING id INTO other_prod;
 INSERT INTO public.forms(occasion,title,link,is_open) VALUES(occ,'Form',link,true) RETURNING id INTO fid;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 c1 := public.save_product_price_change(prod,550,now()+interval '1 day');
 c2 := public.save_product_price_change(prod,650,now()+interval '3 days');
 c3 := public.save_product_price_change(prod,500,now()+interval '5 days');
 mid := public.save_product_price_change(prod,600,now()+interval '2 days');
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE subject_id=prod),4,'Four independent instants');
 c1 := public.save_product_price_change(prod,550,now()+interval '4 days',(c1->>'id')::bigint,1);
 PERFORM assert_eq((SELECT new_value FROM eshop.planned_changes WHERE id=(c2->>'id')::bigint),'650','Moving one plan preserves other target prices');
 BEGIN PERFORM public.save_product_price_change(prod,560,now()+interval '6 days',(c1->>'id')::bigint,1); RAISE EXCEPTION 'stale update accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 BEGIN PERFORM public.cancel_product_price_change(prod,(c1->>'id')::bigint,1); RAISE EXCEPTION 'stale cancel accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 BEGIN PERFORM public.save_product_price_change(prod,10,(c2->>'change_time')::timestamptz); RAISE EXCEPTION 'duplicate accepted'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM public.save_product_price_change(prod,100000000,now()+interval '1 day'); RAISE EXCEPTION 'overflow accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.save_product_price_change(prod,-1,now()+interval '1 day'); RAISE EXCEPTION 'negative accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.save_product_price_change(prod,'NaN'::numeric,now()+interval '1 day'); RAISE EXCEPTION 'NaN accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.save_product_price_change(prod,12.345,now()+interval '1 day'); RAISE EXCEPTION 'fraction accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.save_product_price_change(prod,12,now()-interval '1 day'); RAISE EXCEPTION 'past accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.validate_product_price_update(prod,450,'{}','EUR'); RAISE EXCEPTION 'currency changed'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.validate_product_price_update(prod,10,'{"deposit":{"amount":10}}','CZK'); RAISE EXCEPTION 'deposit accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 result := public.get_products_and_types_for_edit(link)::jsonb;
 PERFORM assert_true(result ? 'server_time','Bundle supplies server clock');
 PERFORM assert_eq(jsonb_array_length((SELECT p->'price_changes' FROM jsonb_array_elements(result->'products') p WHERE (p->>'id')::bigint=prod)),4,'Bundle contains complete pending timeline');
 PERFORM public.cancel_product_price_change(prod,(c2->>'id')::bigint,1);
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE subject_id=prod),3,'Cancel only middle plan');
 -- Both the ordinary product save and embedded form save enforce currency invariants.
 PERFORM public.update_product(jsonb_build_object('id',prod,'price',460));
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=prod),460::numeric,'Manual current price save');
 PERFORM assert_eq((SELECT new_value FROM eshop.planned_changes WHERE id=(c3->>'id')::bigint),'500','Manual save preserves future absolute targets');
 PERFORM public.update_product(jsonb_build_object('id',prod,'price',450));
 BEGIN PERFORM public.update_product(jsonb_build_object('id',prod,'currency_code','EUR')); RAISE EXCEPTION 'product currency bypass'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 result := public.update_form_internal_v1(jsonb_build_object('id',fid,'occasion',occ,'link',link,'form_fields',jsonb_build_array(
   jsonb_build_object('type','product_type','product_type',jsonb_build_object('id',pt,'title','Tickets','type','spot','products',jsonb_build_array(
     jsonb_build_object('id',prod,'title','Ticket','price',450,'currency_code','EUR','data','{}'::jsonb))))))); 
 PERFORM assert_eq(result->>'message','CANCEL_PRICE_CHANGES_BEFORE_CURRENCY_CHANGE','Form save cannot bypass pending currency protection');
 PERFORM assert_eq((SELECT currency_code::text FROM eshop.products WHERE id=prod),'CZK','Rejected form leaves currency unchanged');
 -- Viewer and foreign tenant cannot write, but viewer can inspect.
 UPDATE public.occasion_users SET is_editor_order=false WHERE "user"=actor AND occasion=occ;
 BEGIN PERFORM public.save_product_price_change(prod,999,now()+interval '10 days'); RAISE EXCEPTION 'viewer wrote'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='viewer wrote' THEN RAISE; END IF; END;
 PERFORM assert_true((public.get_products_and_types_for_edit(link)::jsonb) ? 'products','Viewer sees plans');
 UPDATE public.occasion_users SET is_editor_order=true WHERE "user"=actor AND occasion=occ;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.cancel_product_price_change(prod,(c3->>'id')::bigint,1); RAISE EXCEPTION 'foreign user wrote'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 -- Executor permission, future state, absolute chronological application and retry.
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.apply_planned_changes(); RAISE EXCEPTION 'editor ran scheduler'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=prod),450::numeric,'Future plan does nothing');
 UPDATE eshop.planned_changes SET change_time=now()-interval '3 minutes' WHERE id=(mid->>'id')::bigint;
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=prod),600::numeric,'First due price applied');
 UPDATE eshop.planned_changes SET change_time=now()-interval '2 minutes' WHERE id=(c1->>'id')::bigint;
 UPDATE eshop.planned_changes SET change_time=now()-interval '1 minute' WHERE id=(c3->>'id')::bigint;
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=prod),500::numeric,'Last due price wins, including decrease');
 SELECT count(*) INTO n FROM public.client_commits WHERE occasion=occ;
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT count(*)::int FROM public.client_commits WHERE occasion=occ),n,'Retry emits no new commits');
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE subject_id=prod AND applied),3,'Every due plan applied once');
 -- Bad legacy values, subject and type do not block independent changes.
 INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion) VALUES
 ('products.price',other_prod,'not-a-number',now()-interval '10 minutes',occ),
 ('products.price',-1,'100',now()-interval '9 minutes',occ),
 ('unknown',other_prod,'x',now()-interval '8 minutes',occ),
 ('products.price',other_prod,'120',now()-interval '7 minutes',occ),
 ('products.is_hidden',other_prod,'true',now()-interval '6 minutes',occ),
 ('forms.is_open',fid,'false',now()-interval '5 minutes',occ);
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=other_prod),120::numeric,'Invalid plan does not block good change');
 PERFORM assert_true((SELECT is_hidden FROM eshop.products WHERE id=other_prod),'Visibility regression');
 PERFORM assert_false((SELECT is_open FROM public.forms WHERE id=fid),'Form state regression');
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE occasion=occ AND failed_at IS NOT NULL),3,'Invalid plans remain visible and failed');
 -- Deposit changed after scheduling.
 INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion)
 VALUES('products.price',prod,'80',now()-interval '1 minute',occ) RETURNING id INTO first_id;
 UPDATE eshop.products SET data='{"deposit":{"amount":100}}' WHERE id=prod;
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=prod),500::numeric,'Late deposit invalidates application');
 PERFORM assert_eq((SELECT failure_code FROM eshop.planned_changes WHERE id=first_id),'DEPOSIT_AMOUNT_TOO_HIGH','Stable failure');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 mid := public.save_product_price_change(prod,200,now()+interval '1 day',first_id,2);
 PERFORM assert_true(mid->>'failed_at' IS NULL,'Explicit repair resets failure');
 PERFORM public.cancel_product_price_change(prod,first_id,3);
 c1 := public.save_product_price_change(other_prod,0,now()+interval '2 days');
 PERFORM public.delete_product(other_prod);
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.planned_changes WHERE subject_id=other_prod AND change_type='products.price' AND NOT applied),'Product deletion explicitly clears every unapplied price plan');
END $$;
