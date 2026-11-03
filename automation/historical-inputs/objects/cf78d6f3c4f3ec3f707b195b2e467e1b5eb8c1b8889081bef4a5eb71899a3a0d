CREATE OR REPLACE FUNCTION public.update_spot_assignments_client_sync_v1(p_changes jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[]; v_spot_ids bigint[]; v_resource_ids bigint[];
BEGIN
  IF p_changes IS NULL OR jsonb_typeof(p_changes)<>'array'
    OR jsonb_array_length(p_changes)=0 OR jsonb_array_length(p_changes)>1000
    OR octet_length(p_changes::text)>1048576 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid spot assignment batch'; END IF;
  SELECT ARRAY(SELECT DISTINCT e.value::bigint FROM jsonb_array_elements(p_changes) c
    CROSS JOIN LATERAL jsonb_each_text(c) e
    WHERE e.key IN ('old_spot_id','new_spot_id') AND nullif(e.value,'') IS NOT NULL),
    ARRAY(SELECT DISTINCT (c->>'resource_id')::bigint
      FROM jsonb_array_elements(p_changes) c)
    INTO v_spot_ids,v_resource_ids;
  SELECT occasion INTO v_occasion FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=v_actor AND command_name='inventory.spots.assign';
  IF NOT FOUND THEN
  SELECT min(r.occasion) INTO v_occasion FROM public.resources r
    WHERE r.id=ANY(v_resource_ids);
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='inventory editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'changes',p_changes)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.spots.assign',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF (SELECT count(DISTINCT r.occasion) FROM public.resources r
      WHERE r.id=ANY(v_resource_ids))<>1
    OR (SELECT count(*) FROM public.resources r WHERE r.id=ANY(v_resource_ids))
      <>cardinality(v_resource_ids)
    OR (SELECT count(*) FROM eshop.spots s WHERE s.id=ANY(v_spot_ids))
      <>cardinality(v_spot_ids)
    OR EXISTS (SELECT 1 FROM eshop.spots s WHERE s.id=ANY(v_spot_ids)
      AND s.occasion<>v_occasion)
 THEN RAISE insufficient_privilege USING MESSAGE='foreign spot assignment'; END IF;

  PERFORM public.lock_spot_assignment_scope_internal_v1(v_spot_ids,v_resource_ids);
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM eshop.spots s JOIN eshop.order_product_ticket opt
    ON opt.id=s.order_product_ticket JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE s.id=ANY(v_spot_ids);
  PERFORM public.update_spot_assignments_internal_v1(p_changes);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.spots.assign',jsonb_build_array(jsonb_build_object(
      'entityType','spot_assignment','entityId',NULL,'operation','update',
      'safeLabel','Spot assignments','changedFields',jsonb_build_array(
        'resource','resource_slot'))),v_users,jsonb_build_object(
          'changedCount',jsonb_array_length(p_changes)));
END; $function$;

REVOKE ALL ON FUNCTION public.update_spot_assignments_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_spot_assignments_client_sync_v1(jsonb,uuid) TO authenticated;
