-- Shared financial parent locks for hold admission and its atomic-unit wrapper.
CREATE OR REPLACE FUNCTION public.lock_blueprint_hold_scope_internal(p_spots bigint[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 -- Serialize all products and required inventory contexts in canonical ID order.
 PERFORM 1 FROM eshop.products WHERE id IN (SELECT product FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN (SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.spots s ON s.product=pic.product WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN (SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic
  JOIN eshop.spots s ON s.product=pic.product WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_blueprint_hold_scope_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- One admission preflight for the complete atomic unit. These are the same
-- offered fields, maximum counts and physical/context quantities as checkout.
CREATE OR REPLACE FUNCTION public.blueprint_hold_admission_internal(p_form bigint,p_spots bigint[],p_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE item record; counts jsonb; requested bigint; occupied bigint; physical bigint; cap bigint;
BEGIN
 PERFORM public.lock_blueprint_hold_scope_internal(p_spots);
 FOR item IN SELECT p.*,count(*) AS requested FROM eshop.spots s JOIN eshop.products p ON p.id=s.product
  WHERE s.id=ANY(p_spots) AND NOT coalesce(s.secret=p_secret AND s.secret_expiration_time>clock_timestamp(),false)
  GROUP BY p.id ORDER BY p.id LOOP
  IF item.is_hidden THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_HIDDEN'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.form=p_form AND ff.product_type=item.product_type
   AND (ff.type='ticket' OR (ff.type='product_type' AND ff.is_ticket_field)) AND NOT ff.is_hidden) THEN
   RETURN jsonb_build_object('code',409,'reason','PRODUCT_NOT_IN_FORM'); END IF;
  IF coalesce(item.maximum,0)>0 THEN
   SELECT count(*) INTO occupied FROM eshop.order_product_ticket WHERE product=item.id;
   SELECT occupied+count(*) INTO occupied FROM eshop.spots WHERE product=item.id AND order_product_ticket IS NULL
    AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp();
   IF occupied+item.requested>item.maximum THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_CAPACITY_EXCEEDED'); END IF;
  END IF;
  counts:=public.blueprint_product_availability_internal(item.id);
  IF (counts->>'available')::bigint<item.requested THEN RETURN jsonb_build_object('code',409,'reason',coalesce(counts->>'reason','PRODUCT_CAPACITY_EXCEEDED')); END IF;
 END LOOP;
 -- Two differently priced products can consume the same context. Sum their
 -- quantities before holding either member, rather than checking them alone.
 FOR item IN SELECT pic.inventory_context,ip.sellable_capacity,sum(pic.quantity)::bigint AS requested
  FROM eshop.spots s JOIN eshop.product_inventory_contexts pic ON pic.product=s.product
  JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
  WHERE s.id=ANY(p_spots) AND NOT coalesce(s.secret=p_secret AND s.secret_expiration_time>clock_timestamp(),false)
  GROUP BY pic.inventory_context,ip.sellable_capacity ORDER BY pic.inventory_context LOOP
  SELECT count(*),count(*) FILTER(WHERE order_product_ticket IS NOT NULL OR
   (secret IS NOT NULL AND secret_expiration_time>clock_timestamp())) INTO physical,occupied
   FROM eshop.spots WHERE inventory_context=item.inventory_context;
  -- Addressed seats usually have no inventory_context. Their existing spot
  -- holds nevertheless promise all PIC quantities at checkout. Count that
  -- same hold record, subtracting any physical occupancy already counted.
  SELECT occupied+coalesce(sum(greatest(pic.quantity-CASE
    WHEN held.inventory_context=item.inventory_context THEN 1 ELSE 0 END,0)),0)
   INTO occupied FROM eshop.spots held JOIN eshop.product_inventory_contexts pic ON pic.product=held.product
   WHERE pic.inventory_context=item.inventory_context AND held.blueprint IS NOT NULL
    AND held.order_product_ticket IS NULL AND held.secret IS NOT NULL
    AND held.secret_expiration_time>clock_timestamp();
  cap:=least(physical,coalesce(item.sellable_capacity,physical));
  IF occupied+item.requested>cap THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_CAPACITY_EXCEEDED'); END IF;
 END LOOP;
 RETURN jsonb_build_object('code',200);
END $$;
REVOKE ALL ON FUNCTION public.blueprint_hold_admission_internal(bigint,bigint[],uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.select_spot_single_internal_v1(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint; occ bigint; org bigint; un bigint; s eshop.spots; policy jsonb; scopes jsonb; costs jsonb; r jsonb; held bigint; duration_seconds integer; form_data jsonb; form_open boolean; fid bigint;
BEGIN
 IF secret_id IS NULL OR selecting IS NULL THEN RETURN jsonb_build_object('code',400,'message','Invalid reservation'); END IF;
 SELECT f.blueprint,f.occasion,o.organization,o.unit,f.id,f.is_open INTO bp,occ,org,un,fid,form_open FROM public.forms f
 JOIN public.occasions o ON o.id=f.occasion WHERE f.key=form_key;
 IF bp IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form blueprint not found'); END IF;
 PERFORM public.check_occasion_writable(occ);
 -- A buyer's active inventory is serialized before the individual spot lock.
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=bp FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','Spot not found'); END IF;
 IF s.order_product_ticket IS NOT NULL THEN RETURN jsonb_build_object('code',409,'message','Spot is already ordered'); END IF;
 IF s.secret_expiration_time<=clock_timestamp() THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=spot_id;
  s.secret:=NULL; s.secret_expiration_time:=NULL;
 END IF;
 IF s.secret IS NOT NULL AND s.secret IS DISTINCT FROM secret_id THEN
  RETURN jsonb_build_object('code',403,'message','Spot is held by another buyer'); END IF;
 IF NOT selecting THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now() WHERE id=spot_id;
  RETURN jsonb_build_object('code',200,'message','Spot deselected');
 END IF;
 -- A retry cannot move the original expiration, including after another tab reload.
 IF s.secret=secret_id THEN RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time); END IF;
 r:=public.blueprint_hold_admission_internal(fid,ARRAY[s.id],secret_id);
 IF (r->>'code')::integer<>200 THEN RETURN r; END IF;
 IF selecting AND public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN
  form_data:=public.get_effective_form_data(fid);
  IF form_open IS NOT TRUE OR
   (coalesce(form_data#>>'{schedule,start_time}',form_data->>'start_time'))::timestamptz>clock_timestamp() OR
   (coalesce(form_data#>>'{schedule,end_time}',form_data->>'end_time'))::timestamptz<clock_timestamp() THEN
   RETURN jsonb_build_object('code',403,'message','Form is not open'); END IF;
 END IF;
 policy:=public.abuse_effective_rules_v1('spot.hold',un,org);
 scopes:=jsonb_build_object('recipient',secret_id,'unit',un,'organization',org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT count(*) INTO held FROM eshop.spots WHERE secret=secret_id AND secret_expiration_time>clock_timestamp() AND order_product_ticket IS NULL;
 costs:=jsonb_build_object('hold.active.buyer',held+1);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 SELECT (x->>'base_limit')::integer INTO duration_seconds FROM jsonb_array_elements(public.abuse_effective_rules_v1('hold.duration',un,org)->'rules') x;
 IF duration_seconds IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 UPDATE eshop.spots SET secret=secret_id,secret_expiration_time=clock_timestamp()+make_interval(secs=>duration_seconds),updated_at=now() WHERE id=spot_id RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time);
END $$;
REVOKE ALL ON FUNCTION public.select_spot_single_internal_v1(uuid,uuid,bigint,boolean) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.select_spot(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; member_id bigint; r jsonb; occ bigint; bp bigint; fid bigint;
BEGIN
 SELECT occasion,blueprint,id INTO occ,bp,fid FROM public.forms WHERE key=form_key;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 ids:=public.blueprint_selection_unit_spots_internal(spot_id);
 PERFORM 1 FROM public.forms WHERE id=fid FOR UPDATE;
 PERFORM public.lock_blueprint_hold_scope_internal(ids);
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 BEGIN
  IF selecting AND EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
   WHERE s.id=ANY(ids) AND (b.blocked OR s.product IS NULL)
    AND NOT coalesce(s.secret=secret_id AND s.secret_expiration_time>clock_timestamp(),false)) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
  IF selecting THEN
   r:=public.blueprint_hold_admission_internal(fid,ids,secret_id);
   IF (r->>'code')::integer<>200 THEN RETURN r; END IF;
  END IF;
  FOREACH member_id IN ARRAY ids LOOP
   r:=public.select_spot_single_internal_v1(form_key,secret_id,member_id,selecting);
   IF coalesce((r->>'code')::integer,500)<>200 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_HOLD_REJECTED'; END IF;
  END LOOP;
 EXCEPTION WHEN check_violation THEN
  RETURN coalesce(r,jsonb_build_object('code',409,'reason',SQLERRM,'message',SQLERRM));
 END;
 RETURN r||jsonb_build_object('spotIds',to_jsonb(ids));
END $$;
REVOKE ALL ON FUNCTION public.select_spot(uuid,uuid,bigint,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_spot(uuid,uuid,bigint,boolean) TO anon,authenticated;
