CREATE OR REPLACE FUNCTION public.delete_order_client_sync_v1(
  p_order bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_removed_users uuid[]; v_remaining_users uuid[];
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  SELECT o.occasion,oc.unit INTO v_occasion,v_unit FROM eshop.orders o
    JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
  -- Successful deletion removes the order. Exact retries retain their verified
  -- scope in the existing receipt, and still require current scoped rights.
  IF v_occasion IS NULL THEN
    SELECT r.occasion,oc.unit INTO v_occasion,v_unit FROM public.client_mutation_receipts r
    JOIN public.occasions oc ON oc.id=r.occasion
    WHERE r.command_id=p_command_id AND r.command_name='inventory.order.delete'
      AND r.actor_id=v_actor AND r.request_sha256=v_hash AND r.status IN ('completed','expired');
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT (public.get_is_manager_on_unit(v_unit) OR public.get_is_editor_on_unit(v_unit)
      OR public.get_is_admin_on_occasion(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required'; END IF;
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.admit_order_mutation_v1(v_occasion,(SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=p_order));
  -- Match the email worker's outer send fence before form/order locks.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  PERFORM 1 FROM public.forms WHERE id=(SELECT form FROM eshop.orders WHERE id=p_order) FOR UPDATE;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_removed_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt."order"=p_order;
  PERFORM public.delete_order_internal_v1(p_order);
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=v_occasion
    AND s.user_id=ANY(v_removed_users);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed_users) id));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_remaining_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  IF cardinality(v_removed_users)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=v_occasion;
  END IF;
  RETURN public.complete_private_profile_mutation_v1(p_command_id,v_occasion,
    'inventory.order.delete',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order,'operation','delete',
      'safeLabel','Order','changedFields',jsonb_build_array(
        'tickets','membership','allocations'))),v_remaining_users,v_public,v_dirty,
    jsonb_build_object('orderId',p_order,'removedUsers',cardinality(v_removed_users)));
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  TO authenticated;
