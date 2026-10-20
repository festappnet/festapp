-- Private host bindings only contain commercial identities; occupancy details
-- remain in the permission-checked admin reader's existing projection.
CREATE OR REPLACE FUNCTION public.blueprint_binding_projection_internal(p_blueprint bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object(
 'seatBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',b.node_id,'spotId',b.spot,'productId',s.product,'title',s.title,'selectionUnitId',b.selection_unit,'groupNodeId',b.group_node,'blocked',b.blocked,'productAssignmentMode',b.product_assignment_mode) ORDER BY b.node_id)
  FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot WHERE b.blueprint=p_blueprint),'[]'),
 'groupProducts',coalesce((SELECT jsonb_agg(jsonb_build_object('groupNodeId',group_node,'productId',product) ORDER BY group_node) FROM eshop.blueprint_group_products WHERE blueprint=p_blueprint),'[]'),
 'areaBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',node_id,'inventoryContextId',inventory_context,'productId',product) ORDER BY node_id) FROM eshop.blueprint_area_bindings WHERE blueprint=p_blueprint),'[]'))
$$;
CREATE OR REPLACE FUNCTION public.blueprint_public_binding_projection_internal(p_blueprint bigint,p_secret uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT public.blueprint_binding_projection_internal(p_blueprint)||jsonb_build_object('seatBindings',coalesce(
 (SELECT jsonb_agg(jsonb_build_object('nodeId',b.node_id,'spotId',b.spot,'productId',s.product,'title',s.title,'selectionUnitId',b.selection_unit,'groupNodeId',b.group_node,'blocked',b.blocked,'productAssignmentMode',b.product_assignment_mode,'status',CASE
 WHEN b.blocked OR s.product IS NULL THEN 'unavailable' WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
 WHEN s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp() THEN CASE WHEN s.secret=p_secret THEN 'selected_by_me' ELSE 'selected' END
 ELSE 'available' END) ORDER BY b.node_id) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot WHERE b.blueprint=p_blueprint),'[]'))
$$;
REVOKE ALL ON FUNCTION public.blueprint_binding_projection_internal(bigint),public.blueprint_public_binding_projection_internal(bigint,uuid) FROM PUBLIC,anon,authenticated;
