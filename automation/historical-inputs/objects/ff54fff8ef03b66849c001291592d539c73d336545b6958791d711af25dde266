-- Presentation metadata only. Callers retain their existing order access checks.
CREATE OR REPLACE FUNCTION public.order_spot_metadata_internal(p_spot bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('spot_title',s.title,'spot_group_title',CASE WHEN b.layout IS NOT NULL THEN (
   SELECT n->>'label' FROM eshop.blueprint_seat_bindings binding
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
   WHERE binding.spot=s.id AND binding.blueprint=b.id AND n->>'id'=binding.group_node::text LIMIT 1
 ) ELSE (
   SELECT g->>'title' FROM jsonb_array_elements(coalesce(b.groups,'[]')) g
   WHERE g->>'id'=(SELECT obj->>'group' FROM jsonb_array_elements(coalesce(b.objects,'[]')) obj
     WHERE obj->>'type'='spot' AND obj->>'id'=s.id::text LIMIT 1) LIMIT 1) END)
 FROM eshop.spots s LEFT JOIN eshop.blueprints b ON b.id=s.blueprint AND b.occasion=s.occasion
 WHERE s.id=p_spot;
$$;
REVOKE ALL ON FUNCTION public.order_spot_metadata_internal(bigint) FROM PUBLIC,anon,authenticated;

-- Read enrichment also repairs old snapshots without rewriting historical orders.
CREATE OR REPLACE FUNCTION public.order_tickets_with_seating_internal(p_order bigint,p_tickets jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(t || jsonb_build_object('products',(
   SELECT coalesce(jsonb_agg(p || coalesce((
     SELECT CASE WHEN s.blueprint IS NOT NULL THEN public.order_spot_metadata_internal(s.id) ||
       jsonb_build_object('is_standing',false,'standing_area_title',NULL)
       ELSE jsonb_build_object('spot_title',NULL,'spot_group_title',NULL,
         'is_standing',true,'standing_area_title',area.node->>'label') END
     FROM eshop.order_product_ticket x JOIN eshop.spots s ON s.order_product_ticket=x.id
     JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
     LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion
     LEFT JOIN eshop.blueprint_area_bindings ab ON ab.blueprint=f.blueprint
       AND ab.inventory_context=s.inventory_context AND ab.product=x.product
     LEFT JOIN eshop.blueprints b ON b.id=ab.blueprint AND b.occasion=o.occasion
     LEFT JOIN LATERAL (SELECT n AS node FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
       WHERE n->>'id'=ab.node_id::text AND n->>'kind'='capacityArea') area ON true
     WHERE x."order"=p_order AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint
       AND (s.blueprint IS NOT NULL OR area.node IS NOT NULL)
     ORDER BY (s.blueprint IS NOT NULL) DESC,x.id,s.id LIMIT 1),'{}') ORDER BY pi),'[]')
   FROM jsonb_array_elements(coalesce(t->'products','[]')) WITH ORDINALITY products(p,pi)
 )) ORDER BY ti),'[]')
 FROM jsonb_array_elements(coalesce(p_tickets,'[]')) WITH ORDINALITY tickets(t,ti);
$$;
REVOKE ALL ON FUNCTION public.order_tickets_with_seating_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_spot_metadata_internal(bigint), public.order_tickets_with_seating_internal(bigint,jsonb) TO service_role;
