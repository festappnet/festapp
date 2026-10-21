-- Run inside a rollback transaction on the owned disposable QA database only.
DO $$
DECLARE f jsonb:=current_setting('festapp.qa_fixture')::jsonb; actor uuid; ids bigint[]; target bigint; cmd uuid:=gen_random_uuid(); r jsonb; before_count bigint; ord bigint; tids bigint[];
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned local database required'; END IF;
 actor:=(f->>'actor')::uuid;
 SELECT s.id INTO target FROM eshop.spots s WHERE s.blueprint=(f->>'blueprint')::bigint AND s.order_product_ticket IS NULL ORDER BY cardinality(public.blueprint_selection_unit_spots_internal(s.id)) DESC,s.id LIMIT 1;
 ids:=public.blueprint_selection_unit_spots_internal(target);
 UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=now()+interval '1 hour' WHERE id=ANY(ids);
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.release_blueprint_holds_client_sync_v1(ARRAY[target],gen_random_uuid());
  RAISE EXCEPTION 'unauthorized release accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 r:=public.release_blueprint_holds_client_sync_v1(ARRAY[target],cmd);
 IF r->>'status'<>'applied' OR EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(ids) AND secret IS NOT NULL) THEN RAISE EXCEPTION 'hold unit not released'; END IF;
 UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=now()+interval '1 hour' WHERE id=ANY(ids);
 r:=public.release_blueprint_holds_client_sync_v1(ARRAY[target],cmd);
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(ids) AND secret IS NULL) THEN RAISE EXCEPTION 'replay released a new hold'; END IF;
 SELECT id INTO target FROM eshop.spots WHERE blueprint=(f->>'blueprint')::bigint AND order_product_ticket IS NOT NULL LIMIT 1;
 IF target IS NOT NULL THEN
  BEGIN
   PERFORM public.release_blueprint_holds_client_sync_v1(ARRAY[target],gen_random_uuid());
   RAISE EXCEPTION 'ordered spot was released';
  EXCEPTION WHEN check_violation THEN NULL; END;
 END IF;
 SELECT o.id,array_agg(DISTINCT t.id) INTO ord,tids FROM eshop.orders o JOIN eshop.order_product_ticket opt ON opt."order"=o.id JOIN eshop.tickets t ON t.id=opt.ticket WHERE o.occasion=(f->>'occasion')::bigint AND t.state IS DISTINCT FROM 'storno' GROUP BY o.id ORDER BY o.id LIMIT 1;
 IF ord IS NULL THEN RAISE EXCEPTION 'active QA order required'; END IF;
 SELECT count(*) INTO before_count FROM public.email_messages;
 r:=public.storno_tickets_client_sync_v1(tids,gen_random_uuid());
 IF NOT (r->'data'->'cancelledOrderIds' @> jsonb_build_array(ord)) OR (SELECT state FROM eshop.orders WHERE id=ord)<>'storno' THEN RAISE EXCEPTION 'last ticket did not cancel order'; END IF;
 IF (SELECT count(*) FROM public.email_messages)<>before_count THEN RAISE EXCEPTION 'cancellation sent mandatory email'; END IF;
END $$;
