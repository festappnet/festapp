-- Real anonymous reader + unit hold authority, disposable fixture only.
BEGIN;
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE f public.forms; pair bigint[]; p bigint; second_product bigint; context_id bigint; pool_id bigint; existing_count bigint;
 hold_secret uuid:=gen_random_uuid(); response jsonb; catalog jsonb; original_expiry timestamptz; held_before jsonb; wave_change bigint; initial_price numeric;
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned fixture required'; END IF;
 SELECT * INTO f FROM public.forms WHERE id=current_setting('festapp.fixture_form')::bigint;
 SELECT array_agg(spot ORDER BY spot) INTO pair FROM eshop.blueprint_seat_bindings WHERE blueprint=f.blueprint AND selection_unit IS NOT NULL;
 IF array_length(pair,1)<>2 THEN RAISE EXCEPTION 'expected atomic pair'; END IF;
 SELECT product INTO p FROM eshop.spots WHERE id=pair[1];
 SELECT product INTO second_product FROM eshop.spots WHERE blueprint=f.blueprint AND product<>p LIMIT 1;
 -- Controlled synthetic reset is transaction-local; sold UI proof is restored.
 UPDATE eshop.spots SET order_product_ticket=NULL,secret=NULL,secret_expiration_time=NULL,product=p WHERE id=ANY(pair);
 UPDATE eshop.products SET maximum=NULL,is_hidden=false WHERE id=p;
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','anon',true);
 response:=public.get_blueprint(hold_secret,f.key,f.blueprint);
 IF response->>'code'<>'200' THEN RAISE EXCEPTION 'reader failed %',response; END IF;
 SELECT value INTO catalog FROM jsonb_array_elements(response#>'{data,products}') WHERE (value->>'id')::bigint=p;
 IF catalog IS NULL OR NOT (catalog ?& ARRAY['maximum','ordered_count','is_dynamically_available','isAvailable']) THEN RAISE EXCEPTION 'catalog availability missing'; END IF;
 IF (catalog->>'price')::numeric<>(SELECT price FROM eshop.products WHERE id=p) THEN RAISE EXCEPTION 'reader price mismatch'; END IF;
 -- Planned waves remain owned by the existing executor. Read and hold reflect
 -- its applied state, including the same public form price and hidden status.
 SELECT price INTO initial_price FROM eshop.products WHERE id=p;
 INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion)
 VALUES('products.price',p,'77',now()+interval '1 day',f.occasion) RETURNING id INTO wave_change;
 response:=public.get_blueprint(hold_secret,f.key,f.blueprint);
 SELECT value INTO catalog FROM jsonb_array_elements(response#>'{data,products}') WHERE (value->>'id')::bigint=p;
 IF (catalog->>'price')::numeric<>initial_price THEN RAISE EXCEPTION 'future price applied prematurely'; END IF;
 UPDATE eshop.planned_changes SET change_time=now()-interval '1 second' WHERE id=wave_change;
 PERFORM set_config('request.jwt.claim.role','service_role',true);PERFORM public.apply_planned_changes();
 PERFORM set_config('request.jwt.claim.role','anon',true);
 response:=public.get_blueprint(hold_secret,f.key,f.blueprint);
 SELECT value INTO catalog FROM jsonb_array_elements(response#>'{data,products}') WHERE (value->>'id')::bigint=p;
 IF (catalog->>'price')::numeric<>77 THEN RAISE EXCEPTION 'applied wave public price mismatch'; END IF;
 INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion)
 VALUES('products.is_hidden',p,'true',now()-interval '1 second',f.occasion);
 PERFORM set_config('request.jwt.claim.role','service_role',true);PERFORM public.apply_planned_changes();
 PERFORM set_config('request.jwt.claim.role','anon',true);
 response:=public.select_spot(f.key,hold_secret,pair[1],true);
 IF response->>'reason'<>'PRODUCT_HIDDEN' THEN RAISE EXCEPTION 'applied hidden wave held %',response; END IF;
 UPDATE eshop.products SET is_hidden=false WHERE id=p;
 -- A maximum allowing one ticket must reject the two-seat unit with no hold.
 SELECT count(*) INTO existing_count FROM eshop.order_product_ticket WHERE product=p;
 UPDATE eshop.products SET maximum=existing_count+1 WHERE id=p;
 response:=public.select_spot(f.key,hold_secret,pair[1],true);
 IF response->>'reason'<>'PRODUCT_CAPACITY_EXCEEDED' OR EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(pair) AND secret IS NOT NULL) THEN RAISE EXCEPTION 'partial/overlimit hold %',response; END IF;
 UPDATE eshop.products SET maximum=existing_count WHERE id=p;
 response:=public.get_blueprint(hold_secret,f.key,f.blueprint);
 SELECT value INTO catalog FROM jsonb_array_elements(response#>'{data,products}') WHERE (value->>'id')::bigint=p;
 IF existing_count>0 AND (catalog->>'isAvailable')::boolean THEN RAISE EXCEPTION 'exhausted product projected available'; END IF;
 UPDATE eshop.products SET maximum=NULL,is_hidden=true WHERE id=p;
 response:=public.select_spot(f.key,hold_secret,pair[1],true);
 IF response->>'reason'<>'PRODUCT_HIDDEN' THEN RAISE EXCEPTION 'hidden product held %',response; END IF;
 response:=public.get_blueprint(hold_secret,f.key,f.blueprint);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(response#>'{data,products}') WHERE (value->>'id')::bigint=p) THEN RAISE EXCEPTION 'hidden product offered'; END IF;
 UPDATE eshop.products SET is_hidden=false WHERE id=p;
 UPDATE public.form_fields SET is_hidden=true WHERE form=f.id AND product_type=(SELECT product_type FROM eshop.products WHERE id=p);
 response:=public.select_spot(f.key,hold_secret,pair[1],true);
 IF response->>'reason'<>'PRODUCT_NOT_IN_FORM' THEN RAISE EXCEPTION 'unoffered product held %',response; END IF;
 response:=public.get_blueprint(hold_secret,f.key,f.blueprint);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(response#>'{data,products}') WHERE (value->>'id')::bigint=p) THEN RAISE EXCEPTION 'unoffered product exposed'; END IF;
 UPDATE public.form_fields SET is_hidden=false WHERE form=f.id AND product_type=(SELECT product_type FROM eshop.products WHERE id=p);
 -- Mixed products requiring one shared remaining context cannot each pass alone.
 SELECT inventory_context,inventory_pool INTO context_id,pool_id FROM eshop.blueprint_area_bindings a JOIN public.inventory_contexts c ON c.id=a.inventory_context WHERE a.blueprint=f.blueprint LIMIT 1;
 UPDATE eshop.spots SET product=second_product WHERE id=pair[2];
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(p,context_id,1),(second_product,context_id,1) ON CONFLICT(product,inventory_context) DO UPDATE SET quantity=1;
 UPDATE eshop.products SET maximum=NULL,is_hidden=false WHERE id=second_product;
 UPDATE public.inventory_pools SET sellable_capacity=(SELECT count(*)+1 FROM eshop.spots WHERE inventory_context=context_id AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>statement_timestamp()))) WHERE id=pool_id;
 response:=public.select_spot(f.key,hold_secret,pair[1],true);
 IF response->>'reason'<>'PRODUCT_CAPACITY_EXCEEDED' OR EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(pair) AND secret IS NOT NULL) THEN RAISE EXCEPTION 'shared context overbooked/partial %',response; END IF;
 DELETE FROM eshop.product_inventory_contexts WHERE product IN(p,second_product) AND inventory_context=context_id;
 -- A successful retry and release retain authority even after availability changes.
 response:=public.select_spot(f.key,hold_secret,pair[1],true);
 IF response->>'code'<>'200' OR jsonb_array_length(response->'spotIds')<>2 THEN RAISE EXCEPTION 'valid pair failed %',response; END IF;
 original_expiry:=(response->>'expiresAt')::timestamptz;
 UPDATE eshop.products SET is_hidden=true,maximum=1 WHERE id IN(p,second_product);
 UPDATE public.forms SET is_open=false WHERE id=f.id;
 UPDATE eshop.blueprint_seat_bindings SET blocked=true WHERE spot=ANY(pair);
 response:=public.select_spot(f.key,hold_secret,pair[1],true);
 IF response->>'code'<>'200' OR (response->>'expiresAt')::timestamptz<>original_expiry THEN RAISE EXCEPTION 'own retry changed expiry/availability %',response; END IF;
 response:=public.select_spot(f.key,hold_secret,pair[1],false);
 IF response->>'code'<>'200' OR EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(pair) AND secret IS NOT NULL) THEN RAISE EXCEPTION 'own release blocked %',response; END IF;
 RAISE NOTICE 'public catalog + maximum/hidden/offered/shared-context atomicity + own retry/release PASS';
END $$;
ROLLBACK;
