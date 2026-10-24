-- Domain effects are called only inside the receipted command's rollback block.
CREATE OR REPLACE FUNCTION public.update_blueprint_internal_v1(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint:=nullif(input_data->>'id','')::bigint; oc bigint:=(input_data->>'occasion')::bigint;
 org bigint; item jsonb; v_objects jsonb:='[]'; ids bigint[]:='{}'; sid bigint; product_id bigint;
 old eshop.spots; replacements jsonb:='{}'; form_id bigint:=nullif(input_data->>'form','')::bigint;
BEGIN
 IF auth.uid() IS NULL OR public.get_is_editor_order_on_occasion(oc) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=oc;
 IF org IS NULL OR org IS DISTINCT FROM (input_data->>'organization')::bigint THEN
  RETURN jsonb_build_object('code',403,'message','Blueprint organization mismatch'); END IF;
 IF form_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.forms WHERE id=form_id AND occasion=oc) THEN
  RETURN jsonb_build_object('code',403,'message','Foreign form'); END IF;
 IF bp IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=bp AND occasion=oc AND organization=org) THEN
  RETURN jsonb_build_object('code',403,'message','Foreign blueprint'); END IF;
 IF input_data ? 'objects' THEN
  IF jsonb_typeof(input_data->'objects') IS DISTINCT FROM 'array' OR jsonb_array_length(input_data->'objects')>10000 THEN
   RETURN jsonb_build_object('code',400,'message','Invalid blueprint objects'); END IF;
  -- Scope and all references validate before the first domain effect.
  FOR item IN SELECT value FROM jsonb_array_elements(input_data->'objects') LOOP
   IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR item ?| ARRAY['secret','secret_expiration_time','order_product_ticket','state'] THEN
    RETURN jsonb_build_object('code',400,'message','Occupancy is server owned'); END IF;
   IF item->>'type'='spot' THEN
    sid:=nullif(item->>'id','')::bigint; product_id:=nullif(item->>'product','')::bigint;
    IF product_id IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types t ON t.id=p.product_type
     WHERE p.id=product_id AND p.occasion=oc AND t.occasion=oc AND t.type='spot') THEN
     RETURN jsonb_build_object('code',4004,'message','Invalid seat product'); END IF;
    IF sid IS NOT NULL AND (sid<=0 OR bp IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.spots WHERE id=sid AND blueprint=bp AND occasion=oc)) THEN
     RETURN jsonb_build_object('code',403,'message','Foreign seat'); END IF;
    IF sid=ANY(ids) THEN RETURN jsonb_build_object('code',400,'message','Duplicate seat'); END IF;
    IF sid IS NOT NULL THEN ids:=array_append(ids,sid); END IF;
   END IF;
  END LOOP;
  IF (SELECT count(*) FROM jsonb_array_elements(input_data->'objects') o WHERE o ? 'client_id') <>
     (SELECT count(DISTINCT o->>'client_id') FROM jsonb_array_elements(input_data->'objects') o WHERE o ? 'client_id') THEN
   RETURN jsonb_build_object('code',400,'message','Duplicate temporary seat identity'); END IF;
 END IF;
 IF bp IS NULL THEN
  INSERT INTO eshop.blueprints(occasion,organization) VALUES(oc,org) RETURNING id INTO bp;
 END IF;
 -- The command already holds form and product parents. Hold/allocation writers
 -- also lock these actual seats; preview data cannot approve removal.
 PERFORM 1 FROM eshop.spots WHERE blueprint=bp AND occasion=oc ORDER BY id FOR UPDATE;
 PERFORM public.check_batch_blueprint_print_immutable_internal(bp,input_data);
 IF input_data ? 'objects' THEN
  FOR old IN SELECT * FROM eshop.spots WHERE blueprint=bp AND occasion=oc ORDER BY id LOOP
   IF (old.order_product_ticket IS NOT NULL OR (old.secret IS NOT NULL AND old.secret_expiration_time>clock_timestamp())) THEN
    IF NOT old.id=ANY(ids) THEN
     RETURN jsonb_build_object('code',4031,'message','Seat is allocated or held','spot_id',old.id); END IF;
    SELECT (o->>'product')::bigint INTO product_id FROM jsonb_array_elements(input_data->'objects') o WHERE (o->>'id')::bigint=old.id AND o->>'type'='spot';
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT x.ticket FROM eshop.order_product_ticket x
      WHERE x.id=old.order_product_ticket AND (old.title IS DISTINCT FROM
       (SELECT o->>'title' FROM jsonb_array_elements(input_data->'objects') o WHERE o->>'id'=old.id::text AND o->>'type'='spot'))));
    IF product_id IS DISTINCT FROM old.product THEN
     RETURN jsonb_build_object('code',409,'message','Allocated seat product cannot change','spot_id',old.id); END IF;
   END IF;
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(input_data->'objects') LOOP
   IF item->>'type'='spot' THEN
    sid:=nullif(item->>'id','')::bigint;
    IF sid IS NULL THEN
     INSERT INTO eshop.spots(occasion,blueprint,title,product) VALUES(oc,bp,item->>'title',(item->>'product')::bigint) RETURNING id INTO sid;
     IF item ? 'client_id' THEN replacements:=replacements||jsonb_build_object(item->>'client_id',sid); END IF;
     ids:=array_append(ids,sid);
    ELSE
     UPDATE eshop.spots SET title=item->>'title',product=(item->>'product')::bigint,updated_at=clock_timestamp()
     WHERE id=sid AND blueprint=bp AND occasion=oc;
    END IF;
    item:=jsonb_set(item-'title'-'product'-'client_id','{id}',to_jsonb(sid));
   END IF;
   v_objects:=v_objects||jsonb_build_array(item);
  END LOOP;
  DELETE FROM eshop.spots WHERE blueprint=bp AND occasion=oc AND NOT id=ANY(ids);
 END IF;
 UPDATE eshop.blueprints SET
  title=CASE WHEN input_data ? 'title' THEN input_data->>'title' ELSE title END,
  data=CASE WHEN input_data ? 'data' THEN input_data->'data' ELSE data END,
  configuration=CASE WHEN input_data ? 'configuration' THEN input_data->'configuration' ELSE configuration END,
  groups=CASE WHEN input_data ? 'groups' THEN input_data->'groups' ELSE groups END,
  background_svg=CASE WHEN input_data ? 'background_svg' THEN input_data->>'background_svg' ELSE background_svg END,
  objects=CASE WHEN input_data ? 'objects' THEN v_objects ELSE eshop.blueprints.objects END,
  updated_at=clock_timestamp() WHERE id=bp AND occasion=oc;
 IF form_id IS NOT NULL THEN
  PERFORM public.check_form_capacity_settings_internal(form_id,jsonb_build_object('blueprint',bp));
  UPDATE public.forms SET blueprint=bp,capacity_revision=capacity_revision+1,updated_at=clock_timestamp() WHERE id=form_id AND occasion=oc;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
   VALUES('form','occasion',oc,form_id::text,1) ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id)
   DO UPDATE SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 END IF;
 PERFORM public.notification_center_blueprint_capacity_internal(bp);
 RETURN jsonb_build_object('code',200,'blueprint_id',bp,'updated_objects',v_objects,'seat_replacements',replacements);
END $$;
REVOKE ALL ON FUNCTION public.update_blueprint_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Published clients used the admin serialization. Only this mechanical boundary
-- strips read-only fields; the command never accepts occupancy as an instruction.
CREATE OR REPLACE FUNCTION public.update_blueprint(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; normalized jsonb:=input_data-ARRAY['products','tickets','orders','order_product_ticket','created_at'];
BEGIN
 IF normalized ? 'objects' THEN
  normalized:=jsonb_set(normalized,'{objects}',coalesce((SELECT jsonb_agg(o-ARRAY['state','secret','secret_expiration_time','order_product_ticket']) FROM jsonb_array_elements(normalized->'objects') o),'[]'));
 END IF;
 result:=public.update_blueprint_client_sync_v1(normalized,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code')||result->'data';
END $$;
REVOKE ALL ON FUNCTION public.update_blueprint(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_blueprint(jsonb) TO authenticated;
