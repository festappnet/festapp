-- Two addressed holds consume one shared PIC capacity even though the held
-- seats themselves have no inventory_context. No separate reservations exist.
BEGIN;
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE f public.forms; ids bigint[]; product_ids bigint[]; pool_id bigint; context_id bigint; first_secret uuid:=gen_random_uuid(); second_secret uuid:=gen_random_uuid(); result jsonb; expiry timestamptz;
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned fixture required'; END IF;
 SELECT * INTO f FROM public.forms WHERE id=current_setting('festapp.fixture_form')::bigint;
 SELECT array_agg(id ORDER BY id),array_agg(product ORDER BY id) INTO ids,product_ids FROM (
  SELECT DISTINCT ON(s.product) s.id,s.product FROM eshop.spots s JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
  WHERE b.blueprint=f.blueprint AND b.selection_unit IS NULL AND s.product IS NOT NULL AND s.inventory_context IS NULL
   AND EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type WHERE ff.form=f.id AND p.id=s.product AND NOT ff.is_hidden)
  ORDER BY s.product,s.id LIMIT 2) candidates;
 IF array_length(ids,1)<>2 OR product_ids[1]=product_ids[2] THEN RAISE EXCEPTION 'two distinct addressed products required'; END IF;
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,order_product_ticket=NULL WHERE id=ANY(ids);
 UPDATE eshop.blueprint_seat_bindings SET blocked=false WHERE spot=ANY(ids);
 UPDATE eshop.products SET is_hidden=false,maximum=NULL WHERE id=ANY(product_ids);
 INSERT INTO public.inventory_pools(occasion,title,type,data,sellable_capacity) VALUES(f.occasion,'Addressed context regression','generic','{}',1) RETURNING id INTO pool_id;
 INSERT INTO public.inventory_contexts(inventory_pool,title,data) VALUES(pool_id,'Addressed context regression','{}') RETURNING id INTO context_id;
 INSERT INTO eshop.spots(occasion,inventory_context) VALUES(f.occasion,context_id);
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) SELECT unnest(product_ids),context_id,1;
 -- Remove other synthetic holds for these products only inside this rollback.
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE product=ANY(product_ids);
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','anon',true);
 result:=public.select_spot(f.key,first_secret,ids[1],true);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'first addressed hold failed %',result; END IF;
 expiry:=(result->>'expiresAt')::timestamptz;
 result:=public.select_spot(f.key,second_secret,ids[2],true);
 IF result->>'reason'<>'PRODUCT_CAPACITY_EXCEEDED' OR EXISTS(SELECT 1 FROM eshop.spots WHERE id=ids[2] AND secret IS NOT NULL) THEN RAISE EXCEPTION 'addressed holds oversubscribed shared PIC context %',result; END IF;
 result:=public.select_spot(f.key,first_secret,ids[1],true);
 IF result->>'code'<>'200' OR (result->>'expiresAt')::timestamptz<>expiry THEN RAISE EXCEPTION 'first hold retry lost original expiry'; END IF;
 PERFORM public.select_spot(f.key,first_secret,ids[1],false);
 result:=public.select_spot(f.key,second_secret,ids[2],true);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'released context not reusable %',result; END IF;
 -- A physical context assignment must not count the same held spot twice.
 PERFORM public.select_spot(f.key,second_secret,ids[2],false);
 UPDATE eshop.spots SET inventory_context=context_id WHERE id=ids[1];
 result:=public.select_spot(f.key,first_secret,ids[1],true);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'physical addressed hold counted twice %',result; END IF;
 PERFORM public.select_spot(f.key,first_secret,ids[1],false);
 -- Every PIC quantity is consumed, not merely one slot per held seat.
 UPDATE eshop.spots SET inventory_context=NULL WHERE id=ids[1];
 INSERT INTO eshop.spots(occasion,inventory_context) VALUES(f.occasion,context_id);
 UPDATE public.inventory_pools SET sellable_capacity=2 WHERE id=pool_id;
 UPDATE eshop.product_inventory_contexts SET quantity=2 WHERE product=product_ids[1] AND inventory_context=context_id;
 result:=public.select_spot(f.key,first_secret,ids[1],true);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'valid two-quantity hold failed %',result; END IF;
 result:=public.select_spot(f.key,second_secret,ids[2],true);
 IF result->>'reason'<>'PRODUCT_CAPACITY_EXCEEDED' THEN RAISE EXCEPTION 'PIC quantity not counted %',result; END IF;
 UPDATE eshop.spots SET secret_expiration_time=statement_timestamp()-interval '1 second' WHERE id=ids[1];
 result:=public.select_spot(f.key,second_secret,ids[2],true);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'expired indirect hold still consumes capacity %',result; END IF;
 RAISE NOTICE 'distinct addressed holds share PIC capacity: retry/release/reuse, direct no-double-count, quantity2, expiry PASS';
END $$;
ROLLBACK;
