-- Configuration-only extraction of the existing occasion-copy owner. Physical
-- inventory is copied exactly; capacity is never inferred from slot count.
CREATE OR REPLACE FUNCTION public.copy_inventory_resource_configuration_internal(p_source bigint,p_pool bigint,p_place bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r public.resources; target public.inventory_pools; target_unit bigint; target_org bigint; new_id bigint; slot record; new_slot bigint; slots jsonb:='{}';
BEGIN
 SELECT * INTO r FROM public.resources WHERE id=p_source;
 SELECT * INTO target FROM public.inventory_pools WHERE id=p_pool;
 SELECT unit,organization INTO target_unit,target_org FROM public.occasions WHERE id=target.occasion;
 IF r.id IS NULL OR target.id IS NULL OR NOT public.can_copy_occasion_source(r.occasion)
  OR target_org IS DISTINCT FROM (SELECT organization FROM public.occasions WHERE id=r.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Inventory copy source denied'; END IF;
 IF public.get_is_editor_order_on_occasion(target.occasion) IS NOT TRUE AND public.get_is_manager_on_unit(target_unit) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='Inventory copy target denied'; END IF;
 IF p_place IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.places WHERE id=p_place AND occasion=target.occasion) THEN RAISE check_violation USING MESSAGE='Inventory copy place denied'; END IF;
 INSERT INTO public.resources(title,description,capacity,booking_rules,inventory_pool,place,occasion,unit,data)
 VALUES(r.title,r.description,r.capacity,r.booking_rules,p_pool,p_place,target.occasion,target_unit,r.data) RETURNING id INTO new_id;
 FOR slot IN SELECT * FROM public.resource_slots WHERE resource=r.id ORDER BY id LOOP
  INSERT INTO public.resource_slots(resource,title,data) VALUES(new_id,slot.title,slot.data) RETURNING id INTO new_slot;
  slots:=slots||jsonb_build_object(slot.id::text,new_slot);
 END LOOP;
 RETURN jsonb_build_object('resourceId',new_id,'slotMap',slots);
END $$;
REVOKE ALL ON FUNCTION public.copy_inventory_resource_configuration_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.copy_empty_inventory_spot_internal(p_source bigint,p_occasion bigint,p_product bigint,p_blueprint bigint,p_context bigint,p_resource bigint,p_slot bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE source eshop.spots; new_id bigint;
BEGIN
 SELECT * INTO source FROM eshop.spots WHERE id=p_source;
 IF source.id IS NULL OR NOT public.can_copy_occasion_source(source.occasion)
  OR (SELECT organization FROM public.occasions WHERE id=p_occasion) IS DISTINCT FROM
     (SELECT organization FROM public.occasions WHERE id=source.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Inventory copy source denied'; END IF;
 IF public.get_is_editor_order_on_occasion(p_occasion) IS NOT TRUE AND public.get_is_manager_on_unit((SELECT unit FROM public.occasions WHERE id=p_occasion)) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='Inventory copy target denied'; END IF;
 IF (p_product IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=p_product AND occasion=p_occasion))
  OR (p_blueprint IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion))
  OR (p_context IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.inventory_contexts c JOIN public.inventory_pools p ON p.id=c.inventory_pool WHERE c.id=p_context AND p.occasion=p_occasion))
  OR (p_resource IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.resources WHERE id=p_resource AND occasion=p_occasion))
  OR (p_slot IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.resource_slots WHERE id=p_slot AND resource=p_resource)) THEN RAISE check_violation USING MESSAGE='Inventory copy target denied'; END IF;
 INSERT INTO eshop.spots(created_at,occasion,product,updated_at,secret,secret_expiration_time,title,order_product_ticket,blueprint,inventory_context,resource,resource_slot)
 VALUES(now(),p_occasion,p_product,now(),NULL,NULL,source.title,NULL,p_blueprint,p_context,p_resource,p_slot) RETURNING id INTO new_id;
 RETURN new_id;
END $$;
REVOKE ALL ON FUNCTION public.copy_empty_inventory_spot_internal(bigint,bigint,bigint,bigint,bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
