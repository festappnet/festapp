-- A single private projection serves the selected detail, initialization and
-- compatibility manifest. It never exports orders, occupancy or reservation IDs.
CREATE OR REPLACE FUNCTION public.occasion_setup_source_internal(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT jsonb_build_object(
    'occasion', jsonb_build_object('id',o.id,'title',o.title,'link',o.link,
      'start_time',o.start_time,'end_time',o.end_time,'description',o.description,
      'data',o.data,'features',o.features,'is_open',false,'is_hidden',true),
    'forms', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',f.id,'title',f.title,'link',f.link,'type',f.type,'data',f.data,'header',f.header,
      'header_off',f.header_off,'deadline_duration_seconds',f.deadline_duration_seconds,
      'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
      'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
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
      'id',b.id,'title',b.title,'unavailableReason',CASE WHEN b.layout IS NULL THEN 'legacy_requires_reviewed_geometry' ELSE NULL END) ORDER BY b.id)
      FROM eshop.blueprints b WHERE b.occasion=o.id),'[]'::jsonb),
    'program',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',e.id,'title',e.title,
      'start_time',e.start_time,'end_time',e.end_time,'description',e.description,
      'max_participants',e.max_participants,'is_hidden',e.is_hidden,'is_group_event',e.is_group_event,
      'split_for_men_women',e.split_for_men_women,'type',e.type,'order',e."order",
      'place',(SELECT jsonb_build_object('id',p.id,'title',p.title,'description',p.description,'type',p.type,
        'coordinates',p.coordinates,'is_hidden',p.is_hidden,'order',p."order",'icon',p.icon) FROM public.places p WHERE p.id=e.place),
      'children',coalesce((SELECT jsonb_agg(eg.event_child ORDER BY eg.event_child) FROM public.event_groups eg
        JOIN public.events child ON child.id=eg.event_child AND child.occasion=o.id WHERE eg.event_parent=e.id),'[]'::jsonb),
      'roles',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'title',r.title) ORDER BY r.id)
        FROM public.event_roles er JOIN public.role_info r ON r.id=er.role WHERE er.event=e.id),'[]'::jsonb),
      'exclusive_groups',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'title',g.title) ORDER BY g.id)
        FROM public.exclusive_events ee JOIN public.exclusive_groups g ON g.id=ee."group" WHERE ee.event=e.id),'[]'::jsonb)
      ) ORDER BY e."order",e.id)
      FROM public.events e WHERE e.occasion=o.id),'[]'::jsonb),
    'information',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',i.title,
      'description',i.description,'type',i.type,'data',i.data) ORDER BY i."order",i.id)
      FROM public.information i WHERE i.occasion=o.id),'[]'::jsonb)
    ) FROM public.occasions o WHERE o.id=p_occasion;
$$;
REVOKE ALL ON FUNCTION public.occasion_setup_source_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_source_list(p_unit bigint,p_source_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.units target JOIN public.units source ON source.organization=target.organization
   WHERE target.id=p_unit AND source.id=coalesce(p_source_unit,p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Source tenant denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('occasion',jsonb_build_object(
  'id',o.id,'title',o.title,'start_time',o.start_time,'end_time',o.end_time)) ORDER BY o.start_time DESC,o.id DESC)
  FROM public.occasions o WHERE o.unit=coalesce(p_source_unit,p_unit) AND public.can_copy_occasion_source(o.id)),'[]');
END $$;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_source(p_unit bigint,p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit)
  OR NOT public.can_copy_occasion_source(p_occasion)
  OR NOT EXISTS(SELECT 1 FROM public.occasions o JOIN public.units u ON u.organization=o.organization
    WHERE o.id=p_occasion AND u.id=p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 RETURN public.occasion_setup_source_internal(p_occasion);
END $$;

-- Compatibility for already deployed opt-in development clients. Remove once
-- all such clients use source_list/source; no separate projection is maintained.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_sources(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(public.occasion_setup_source_internal(o.id) ORDER BY o.start_time DESC,o.id DESC)
  FROM public.occasions o WHERE o.unit=p_unit),'[]');
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_source_list(bigint,bigint),public.get_occasion_setup_source(bigint,bigint),public.get_occasion_setup_sources(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_source_list(bigint,bigint),public.get_occasion_setup_source(bigint,bigint),public.get_occasion_setup_sources(bigint) TO authenticated;
