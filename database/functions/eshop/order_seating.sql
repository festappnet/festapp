CREATE OR REPLACE FUNCTION public.order_spot_metadata_bulk_internal(p_spots bigint[])
RETURNS TABLE(spot_id bigint,metadata jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY
 WITH spots AS MATERIALIZED (
  SELECT s.id,s.title,s.blueprint,s.occasion FROM eshop.spots s WHERE s.id=ANY(p_spots)
 ), plans AS (
  SELECT DISTINCT s.blueprint,s.occasion FROM spots s WHERE s.blueprint IS NOT NULL
 ), nodes AS MATERIALIZED (
  SELECT b.id blueprint,b.occasion,n.node,n.ordinal FROM plans p
  JOIN eshop.blueprints b ON b.id=p.blueprint AND b.occasion=p.occasion
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.layout->'nodes','[]')) WITH ORDINALITY n(node,ordinal)
 ), first_nodes AS (
  SELECT DISTINCT ON (n.blueprint,n.occasion,n.node->>'id') n.blueprint,n.occasion,n.node
  FROM nodes n WHERE n.node->>'id' IS NOT NULL ORDER BY n.blueprint,n.occasion,n.node->>'id',n.ordinal
 ), plan_labels AS MATERIALIZED (
  SELECT n.blueprint,n.occasion,jsonb_object_agg(n.node->>'id',n.node->'label') labels
  FROM first_nodes n GROUP BY n.blueprint,n.occasion
 )
 SELECT s.id::bigint,jsonb_build_object('spot_title',s.title,'spot_group_title',(
  SELECT p.labels->>binding.group_node::text FROM eshop.blueprint_seat_bindings binding
  JOIN plan_labels p ON p.blueprint=binding.blueprint AND p.occasion=s.occasion
  WHERE binding.spot=s.id AND binding.blueprint=s.blueprint LIMIT 1))
 FROM spots s;
END;
$$;
REVOKE ALL ON FUNCTION public.order_spot_metadata_bulk_internal(bigint[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_spot_metadata_bulk_internal(bigint[]) TO service_role;

CREATE OR REPLACE FUNCTION public.order_tickets_with_seating_bulk_internal(p_snapshots jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 WITH snapshots AS MATERIALIZED (
  SELECT nullif(key,'')::bigint AS order_id,key,value FROM jsonb_each(coalesce(p_snapshots,'{}'))
 ), tickets AS MATERIALIZED (
  SELECT s.order_id,s.key,t,ti FROM snapshots s
  CROSS JOIN LATERAL jsonb_array_elements(s.value) WITH ORDINALITY ticket(t,ti)
 ), products AS MATERIALIZED (
  SELECT t.order_id,t.key,t.ti,p,pi,(t.t->>'id')::bigint ticket_id,(p->>'id')::bigint product_id
  FROM tickets t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t.t->'products','[]')) WITH ORDINALITY product(p,pi)
 ), selected_items AS MATERIALIZED (
  SELECT DISTINCT p.order_id,p.ticket_id,p.product_id FROM products p
 ), seated_spots AS MATERIALIZED (
  SELECT DISTINCT s.id FROM selected_items item
  JOIN eshop.order_product_ticket x ON x."order"=item.order_id AND x.ticket=item.ticket_id AND x.product=item.product_id
  JOIN eshop.spots s ON s.order_product_ticket=x.id AND s.blueprint IS NOT NULL
  JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
 ), seated_metadata AS MATERIALIZED (
  SELECT m.spot_id,m.metadata FROM public.order_spot_metadata_bulk_internal(ARRAY(SELECT id FROM seated_spots)) m
 ), assignments AS MATERIALIZED (
  SELECT DISTINCT ON (x."order",x.ticket,x.product) x."order" order_id,x.ticket,x.product,
   CASE WHEN s.blueprint IS NOT NULL THEN sm.metadata ||
    jsonb_build_object('is_standing',false,'standing_area_title',NULL)
   ELSE jsonb_build_object('spot_title',NULL,'spot_group_title',NULL,
    'is_standing',true,'standing_area_title',area.node->>'label') END metadata
  FROM selected_items item JOIN eshop.order_product_ticket x ON x."order"=item.order_id AND x.ticket=item.ticket_id AND x.product=item.product_id
  JOIN eshop.spots s ON s.order_product_ticket=x.id
  LEFT JOIN seated_metadata sm ON sm.spot_id=s.id
  JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
  LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion
  LEFT JOIN eshop.blueprint_area_bindings ab ON ab.blueprint=coalesce(f.blueprint,(SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
       JOIN eshop.blueprints target ON target.id=candidate.blueprint WHERE candidate.inventory_context=s.inventory_context
         AND candidate.product=x.product AND target.occasion=o.occasion HAVING count(DISTINCT candidate.blueprint)=1))
   AND ab.inventory_context=s.inventory_context AND ab.product=x.product
  LEFT JOIN eshop.blueprints b ON b.id=ab.blueprint AND b.occasion=o.occasion
  LEFT JOIN LATERAL (SELECT n AS node FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
   WHERE n->>'id'=ab.node_id::text AND n->>'kind'='capacityArea') area ON true
  WHERE s.blueprint IS NOT NULL OR area.node IS NOT NULL
  ORDER BY x."order",x.ticket,x.product,(s.blueprint IS NOT NULL) DESC,x.id,s.id
 ), ticket_products AS MATERIALIZED (
  SELECT p.key,p.ti,jsonb_agg(p.p||coalesce(a.metadata,'{}') ORDER BY p.pi) products
  FROM products p LEFT JOIN assignments a ON a.order_id=p.order_id AND a.ticket=p.ticket_id AND a.product=p.product_id
  GROUP BY p.key,p.ti
 ), enriched AS (
  SELECT t.key,jsonb_agg(t.t||jsonb_build_object('products',coalesce(p.products,'[]')) ORDER BY t.ti) tickets
  FROM tickets t LEFT JOIN ticket_products p ON p.key=t.key AND p.ti=t.ti GROUP BY t.key
 )
 SELECT coalesce(jsonb_object_agg(s.key,coalesce(e.tickets,'[]')),'{}') INTO result
 FROM snapshots s LEFT JOIN enriched e ON e.key=s.key;
 RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.order_tickets_with_seating_bulk_internal(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_tickets_with_seating_bulk_internal(jsonb) TO service_role;

-- Presentation metadata only. Callers retain their existing order access checks.
CREATE OR REPLACE FUNCTION public.order_spot_metadata_internal(p_spot bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('spot_title',s.title,'spot_group_title',(
   SELECT n->>'label' FROM eshop.blueprint_seat_bindings binding
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
   WHERE binding.spot=s.id AND binding.blueprint=b.id AND n->>'id'=binding.group_node::text LIMIT 1
))
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
     LEFT JOIN eshop.blueprint_area_bindings ab ON ab.blueprint=coalesce(f.blueprint,(SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
       JOIN eshop.blueprints target ON target.id=candidate.blueprint WHERE candidate.inventory_context=s.inventory_context
         AND candidate.product=x.product AND target.occasion=o.occasion HAVING count(DISTINCT candidate.blueprint)=1))
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
