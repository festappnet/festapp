-- Configuration only: no responses, orders, customers or reservation secrets.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_sources(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
    RAISE EXCEPTION 'Source access denied' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'occasion', jsonb_build_object('id',o.id,'title',o.title,'link',o.link,
      'start_time',o.start_time,'end_time',o.end_time,'description',o.description,
      'data',o.data,'features',o.features,'is_open',false,'is_hidden',true),
    'forms', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'title',f.title,'link',f.link,'type',f.type,'data',f.data,'header',f.header,
      'header_off',f.header_off,'deadline_duration_seconds',f.deadline_duration_seconds,
      'is_open',false,'blueprint',f.blueprint,
      'fields',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'title',ff.title,'description',ff.description,'data',ff.data,'type',ff.type,
        'is_required',ff.is_required,'is_hidden',ff.is_hidden,'order',ff."order",
        'is_ticket_field',ff.is_ticket_field,
        'product_type_data',(SELECT jsonb_build_object('id',pt.id,'title',pt.title,
          'description',pt.description,'type',pt.type,'data',pt.data,
          'products',COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'id',p.id,'title',p.title,'description',p.description,'price',p.price,
            'currency_code',p.currency_code,'maximum',p.maximum,'data',p.data,
            'is_hidden',p.is_hidden,'order',p."order") ORDER BY p."order",p.id)
            FROM eshop.products p WHERE p.product_type=pt.id),'[]'::jsonb))
          FROM eshop.product_types pt WHERE pt.id=ff.product_type)) ORDER BY ff."order",ff.id)
        FROM public.form_fields ff WHERE ff.form=f.id),'[]'::jsonb)) ORDER BY f.id)
      FROM public.forms f WHERE f.occasion=o.id),'[]'::jsonb),
    'blueprints',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'blueprintLayoutDraft',CASE WHEN b.layout IS NULL THEN NULL ELSE jsonb_build_object(
        'layout',b.layout,
        'seatBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',sb.node_id,'productId',spot.product,'title',spot.title,'groupNodeId',sb.group_node,'selectionUnitId',sb.selection_unit,'blocked',sb.blocked) ORDER BY sb.node_id)
          FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots spot ON spot.id=sb.spot WHERE sb.blueprint=b.id),'[]'),
        'groupProducts',coalesce((SELECT jsonb_agg(jsonb_build_object('groupNodeId',gp.group_node,'productId',gp.product) ORDER BY gp.group_node) FROM eshop.blueprint_group_products gp WHERE gp.blueprint=b.id),'[]'),
        'areaBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',ab.node_id,'productId',ab.product,'inventoryContextId',ab.inventory_context) ORDER BY ab.node_id) FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=b.id),'[]')) END,
      'id',b.id,'title',b.title) ORDER BY b.id)
      FROM eshop.blueprints b WHERE b.occasion=o.id AND b.layout IS NOT NULL),'[]'::jsonb),
    'program',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',e.title,
      'start_time',e.start_time,'end_time',e.end_time,'description',e.description))
      FROM public.events e WHERE e.occasion=o.id),'[]'::jsonb),
    'information',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',i.title,
      'description',i.description,'type',i.type,'data',i.data) ORDER BY i."order",i.id)
      FROM public.information i WHERE i.occasion=o.id),'[]'::jsonb)
    ) ORDER BY o.start_time DESC,o.id DESC) FROM public.occasions o WHERE o.unit=p_unit),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_sources(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_sources(bigint) TO authenticated;
