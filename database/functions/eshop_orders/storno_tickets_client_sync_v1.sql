CREATE OR REPLACE FUNCTION public.storno_tickets_client_sync_v1(
  p_tickets bigint[],p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[]; v_changed_orders bigint[]; v_cancelled jsonb; v_updated jsonb;
BEGIN
  SELECT min(t.occasion) INTO v_occasion FROM eshop.tickets t
    WHERE t.id=ANY(p_tickets);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_tickets)=0
    OR (SELECT count(*) FROM eshop.tickets t
      WHERE t.id=ANY(p_tickets) AND t.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'tickets',p_tickets)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.tickets.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  -- Lock in the same order as the bulk mutation, then capture only actual changes.
  PERFORM o.id FROM eshop.orders o WHERE o.id IN (
    SELECT opt."order" FROM eshop.order_product_ticket opt
    JOIN eshop.tickets t ON t.id=opt.ticket
    WHERE t.id=ANY(p_tickets)) ORDER BY o.id FOR UPDATE;
  SELECT array_agg(DISTINCT opt."order") INTO v_changed_orders
    FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
    WHERE t.id=ANY(p_tickets) AND t.state IS DISTINCT FROM 'storno';
  PERFORM public.storno_tickets_bulk_internal_v1(p_tickets);
  SELECT coalesce(jsonb_agg(o.id ORDER BY o.id) FILTER(WHERE o.state='storno'),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('id',o.id,'email',o.data->>'email') ORDER BY o.id)
      FILTER(WHERE o.state IS DISTINCT FROM 'storno'),'[]'::jsonb)
    INTO v_cancelled,v_updated FROM eshop.orders o WHERE o.id=ANY(v_changed_orders);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.tickets.cancel',
    jsonb_build_array(jsonb_build_object('entityType','ticket','entityId',NULL,
      'operation','update','safeLabel','Ticket cancellation',
      'changedFields',jsonb_build_array('state','membership','allocations'))),
    v_before_users,jsonb_build_object('ticketIds',to_jsonb(p_tickets),
      'cancelledOrderIds',v_cancelled,'updatedOrders',v_updated));
END; $$;
REVOKE ALL ON FUNCTION public.storno_tickets_client_sync_v1(bigint[],uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storno_tickets_client_sync_v1(bigint[],uuid)
  TO authenticated;
