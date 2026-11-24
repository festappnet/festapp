-- Carry typed seating metadata through existing authorized readers.

-- SOURCE: eshop/order_seating.sql
-- Resolve the physical assembly even when its commercial group is a wrapper.
CREATE OR REPLACE FUNCTION public.order_seating_kind_internal(p_nodes jsonb,p_seat text,p_group text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH RECURSIVE ancestors AS (
  SELECT p_nodes->p_seat node,ARRAY[p_seat] seen,0 depth
  UNION ALL
  SELECT p_nodes->(a.node->>'parentId'),a.seen||(a.node->>'parentId'),a.depth+1
  FROM ancestors a WHERE p_nodes ? (a.node->>'parentId')
    AND NOT (a.node->>'parentId')=ANY(a.seen)
 ), kinds AS (
  SELECT node,depth FROM ancestors
  UNION ALL SELECT p_nodes->p_group,2147483647
 )
 SELECT CASE WHEN node->>'kind'='table' THEN 'table'
             WHEN node->>'furniture'='couch' THEN 'couch' ELSE 'row' END
 FROM kinds WHERE node->>'kind'='table'
    OR (node->>'kind'='furniture' AND node->>'furniture'='couch')
    OR (node->>'kind'='group' AND node#>>'{assembly,kind}'='rows' AND node#>>'{assembly,rows}'='1')
 ORDER BY depth LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.order_seating_kind_internal(jsonb,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_seating_kind_internal(jsonb,text,text) TO service_role;

-- Standing inventory is identified by its purchased capacity area, not a title.
CREATE OR REPLACE FUNCTION public.order_standing_spot_metadata_internal(p_spot bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('is_standing',true,'standing_area_title',area.node->>'label')
 FROM eshop.spots s
 JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
 JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
 LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion
 JOIN eshop.blueprint_area_bindings ab ON ab.blueprint=coalesce(f.blueprint,(
   SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
   JOIN eshop.blueprints target ON target.id=candidate.blueprint
   WHERE candidate.inventory_context=s.inventory_context
     AND candidate.product=x.product AND target.occasion=o.occasion
   HAVING count(DISTINCT candidate.blueprint)=1))
   AND ab.inventory_context=s.inventory_context AND ab.product=x.product
 JOIN eshop.blueprints b ON b.id=ab.blueprint AND b.occasion=o.occasion
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.layout->'nodes','[]')) area(node)
 WHERE s.id=p_spot AND s.blueprint IS NULL
   AND area.node->>'id'=ab.node_id::text AND area.node->>'kind'='capacityArea'
 LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.order_standing_spot_metadata_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_standing_spot_metadata_internal(bigint) TO service_role;

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
 ), plan_nodes AS MATERIALIZED (
  SELECT n.blueprint,n.occasion,jsonb_object_agg(n.node->>'id',n.node) nodes
  FROM first_nodes n GROUP BY n.blueprint,n.occasion
 )
 SELECT s.id::bigint,jsonb_build_object('spot_title',s.title,
     'spot_group_title',info.nodes->info.group_node::text->>'label',
     'spot_group_kind',public.order_seating_kind_internal(info.nodes,info.node_id::text,info.group_node::text))
   || coalesce(CASE WHEN s.blueprint IS NULL
      THEN public.order_standing_spot_metadata_internal(s.id) END,'{}')
 FROM spots s
 LEFT JOIN LATERAL (
   SELECT p.nodes,binding.node_id,binding.group_node
   FROM eshop.blueprint_seat_bindings binding
   JOIN plan_nodes p ON p.blueprint=binding.blueprint AND p.occasion=s.occasion
   WHERE binding.spot=s.id AND binding.blueprint=s.blueprint LIMIT 1
 ) info ON true;
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
 SELECT metadata FROM public.order_spot_metadata_bulk_internal(ARRAY[p_spot]);
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

-- SOURCE: eshop/get_tickets_with_details.sql
CREATE OR REPLACE FUNCTION public.get_tickets_with_details(order_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    tickets JSONB;
BEGIN
    SELECT jsonb_agg(ticket_detail)
    INTO tickets
    FROM (
        SELECT DISTINCT ON (t.id)
            t.id,
            t.ticket_symbol,
            t.occasion,
            t.note,
            t.state,
            b.title AS table_title,
            (
                SELECT jsonb_agg(ticket_prod)
                FROM (
                    SELECT
                        opt2.id,
                        opt2.product,
                        s.title AS spot_title,
                        seat.metadata->>'spot_group_title' AS spot_group_title,
                        seat.metadata->>'spot_group_kind' AS spot_group_kind,
                        COALESCE((seat.metadata->>'is_standing')::boolean,false) AS is_standing,
                        seat.metadata->>'standing_area_title' AS standing_area_title
                    FROM eshop.order_product_ticket opt2
                    LEFT JOIN eshop.spots s
                        ON s.order_product_ticket = opt2.id
                    LEFT JOIN eshop.blueprints bp
                        ON bp.id = s.blueprint
                    LEFT JOIN LATERAL (SELECT public.order_spot_metadata_internal(s.id) metadata) seat ON true
                    WHERE opt2.ticket = t.id
                ) ticket_prod
            ) AS order_product_ticket,
            (
              SELECT COALESCE(SUM((prod->>'price')::numeric), 0)
              FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                   jsonb_array_elements(ticket_json->'products') prod
              WHERE (ticket_json->>'id')::bigint = t.id
            ) AS price,
            (
              SELECT (prod->>'currency_code')
              FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                   jsonb_array_elements(ticket_json->'products') prod
              WHERE (ticket_json->>'id')::bigint = t.id
              LIMIT 1
            ) AS currency_code
        FROM eshop.order_product_ticket opt
        JOIN eshop.tickets t
            ON t.id = opt.ticket
        JOIN eshop.orders ord
            ON ord.id = order_id
        LEFT JOIN public.occasions o
            ON o.id = t.occasion
        LEFT JOIN eshop.blueprints b
            ON b.occasion = o.id
        WHERE opt."order" = order_id AND t.state IS DISTINCT FROM 'waitlisted' AND t.ticket_symbol IS NOT NULL
        ORDER BY t.id
    ) ticket_detail;

    RETURN tickets;
END;
$$;

-- SOURCE: eshop/get_ticket_details_for_generating.sql
CREATE OR REPLACE FUNCTION public.get_ticket_details_for_generating(ticket_id_input BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        -- 1. Build the 'ticket' key
        'ticket', (
            SELECT to_jsonb(t_detail)
            FROM (
                SELECT
                    t.id,
                    (SELECT i.batch_id FROM eshop.ticket_batch_items i WHERE i.ticket_id=t.id) AS batch_id,
                    t.ticket_symbol,
                    t.occasion,
                    t.note,
                    t.state,
                    b.title AS table_title,
                    -- Subquery for Spot/Product details
                    (
                        SELECT jsonb_agg(ticket_prod ORDER BY ticket_prod.id)
                        FROM (
                            SELECT
                                opt2.id,
                                opt2.product,
                                s.title AS spot_title,
                                p.data->>'short_title' AS short_title,
                                p.title AS product_title,
                                seat.metadata->>'spot_group_title' AS spot_group_title,
                                seat.metadata->>'spot_group_kind' AS spot_group_kind,
                                COALESCE((seat.metadata->>'is_standing')::boolean,false) AS is_standing,
                                seat.metadata->>'standing_area_title' AS standing_area_title
                            FROM eshop.order_product_ticket opt2
                            LEFT JOIN eshop.spots s
                                ON s.order_product_ticket = opt2.id
                            LEFT JOIN eshop.products p
                                ON p.id = opt2.product
                            LEFT JOIN eshop.product_types pt
                                ON pt.id = p.product_type
                            LEFT JOIN eshop.blueprints bp
                                ON bp.id = s.blueprint
                            LEFT JOIN LATERAL (SELECT public.order_spot_metadata_internal(s.id) metadata) seat ON true
                            WHERE opt2.ticket = t.id
                              AND NOT (pt.type = 'spot' AND s.title IS NULL
                                AND seat.metadata->>'is_standing' IS DISTINCT FROM 'true')
                        ) ticket_prod
                    ) AS order_product_ticket,

                    -- Subquery for Price (extracting from ord.data)
                    (
                      SELECT COALESCE(SUM((prod->>'price')::numeric), 0)
                      FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                           jsonb_array_elements(ticket_json->'products') prod
                      WHERE (ticket_json->>'id')::bigint = t.id
                    ) AS price,

                    -- Subquery for Currency (extracting from ord.data)
                    (
                      SELECT (prod->>'currency_code')
                      FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                           jsonb_array_elements(ticket_json->'products') prod
                      WHERE (ticket_json->>'id')::bigint = t.id
                      LIMIT 1
                    ) AS currency_code
            ) t_detail
        ),

        -- 2. Build the 'occasion' key (dumps the whole occasion row including 'features')
        'occasion', to_jsonb(o)||jsonb_build_object('demo_read_only',public.is_demo_occasion(o.id),'locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=o.organization),'cs')),
        'order_data', jsonb_build_object('name', ord.data->'name', 'surname', ord.data->'surname')
    )
    INTO result
    FROM eshop.tickets t
    -- Join Occasion to get the occasion object
    JOIN public.occasions o
        ON o.id = t.occasion
    -- Join Blueprint for the table title
    LEFT JOIN eshop.blueprints b
        ON b.occasion = o.id
    -- Join Order Tables to expose 'ord.data' for the ticket sub-calculations above
    LEFT JOIN eshop.order_product_ticket opt
        ON opt.ticket = t.id
    LEFT JOIN eshop.orders ord
        ON ord.id = opt."order"
    WHERE t.id = ticket_id_input AND t.state IS DISTINCT FROM 'waitlisted' AND t.ticket_symbol IS NOT NULL
      AND ord.state IS DISTINCT FROM 'waitlisted';

    RETURN result;
END;
$$;

-- SOURCE: eshop_waitlist/order_overview.sql
CREATE OR REPLACE FUNCTION public.get_customer_order_overview_internal(p_token text,p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE root eshop.orders; cap eshop.waitlist_capabilities; occ public.occasions; f public.forms;
 ids bigint[]; result jsonb;
BEGIN
 PERFORM set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 SELECT * INTO root FROM eshop.orders WHERE id=p_order_id AND source_waitlist_order_id IS NULL;
 SELECT * INTO occ FROM public.occasions WHERE id=root.occasion;
 SELECT * INTO f FROM public.forms WHERE id=root.form AND occasion=occ.id;
 SELECT * INTO cap FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 AND kind='order_view' AND order_id=root.id AND form_id=f.id AND organization_id=occ.organization
 AND revoked_at IS NULL AND expires_at>statement_timestamp();
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' OR cap.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT array_agg(id) INTO ids FROM eshop.orders WHERE id=root.id OR (source_waitlist_order_id=root.id AND NOT (
  NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=eshop.orders.id)
  AND EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE target_order_id=eshop.orders.id AND source_order_id=root.id AND state='aborted')));
 -- Reject malformed provenance rather than expanding an apparently related scope.
 IF EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(ids) AND (o.form IS DISTINCT FROM f.id OR o.occasion IS DISTINCT FROM occ.id))
 OR EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=ANY(ids)
  AND (t.occasion<>occ.id OR EXISTS(SELECT 1 FROM eshop.order_product_ticket y WHERE y.ticket=t.id AND y."order" IS DISTINCT FROM x."order")))
 OR EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(ids) AND o.source_waitlist_order_id=root.id AND NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  JOIN eshop.order_product_ticket x ON x.ticket=s.ticket_id AND x."order"=o.id
  WHERE w.order_id=root.id AND w.form_id=f.id AND s.form_id=f.id AND s.outcome='accepted' AND s.resulting_order_id=o.id))
 OR EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=ANY(ids) AND x."order"<>root.id AND NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.ticket_id=x.ticket AND s.resulting_order_id=x."order" AND s.outcome='accepted' AND w.order_id=root.id AND w.form_id=f.id))
 THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT jsonb_build_object('code',200,'root',jsonb_build_object('id',root.id,'symbol',root.order_symbol,'createdAt',root.created_at,'state',root.state,'title',occ.title,'formLink',f.link,'communicationTone',public.effective_form_metadata_internal(f.data,(SELECT data FROM public.units WHERE id=occ.unit))->>'communication_tone','hasTickets',public.uses_ticket_terminology_internal(occ.features)),
 'timeline',(SELECT coalesce(jsonb_agg(event ORDER BY happened,sort_key),'[]') FROM (
  SELECT root.created_at happened,'0' sort_key,jsonb_build_object('kind',CASE WHEN root.state='waitlisted' THEN 'waitlist_entered' ELSE 'order_ordered' END,'at',root.created_at,'symbol',root.order_symbol) event
  WHERE root.state='waitlisted' OR NOT EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=root.id AND state='ordered')
  UNION ALL
  SELECT w.created_at,'1'||w.id::text,jsonb_build_object('kind','places_offered','at',w.created_at)
  FROM eshop.waitlist_offers w WHERE w.order_id=root.id AND w.form_id=f.id
  UNION ALL
  SELECT s.updated_at,'2'||s.id::text,jsonb_build_object('kind','offer_'||s.outcome,'at',s.updated_at)
  FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE w.order_id=root.id AND w.form_id=f.id AND s.form_id=f.id AND s.outcome IN ('accepted','declined','cancelled','expired')
  UNION ALL
  SELECT t.created_at,'4'||t.id::text,jsonb_build_object('kind',CASE WHEN m.voided THEN 'payment_adjustment_voided' WHEN m.is_refund THEN 'refund' WHEN t.amount>0 THEN 'payment_received' ELSE 'payment_adjustment' END,
   'at',t.created_at,'timeKind','recorded','amount',t.amount,'currency',trim(t.currency),'symbol',o.order_symbol,
   'paymentMethod',CASE WHEN b.type='CASH' THEN 'cash' WHEN nullif(trim(b.account_number),'') IS NOT NULL THEN 'bank' END,
   'recipientAccount',CASE WHEN b.type<>'CASH' THEN coalesce(nullif(trim(b.account_number_human_readable),''),nullif(trim(b.account_number),'')) END)
  FROM eshop.orders o JOIN eshop.transactions t ON t.payment_info=o.payment_info JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id LEFT JOIN eshop.bank_accounts b ON b.id=t.bank_account_id WHERE o.id=ANY(ids) AND t.created_at IS NOT NULL
  UNION ALL
  SELECT h.created_at,'3'||h.id::text,jsonb_build_object(
   'kind',CASE WHEN h.state IS DISTINCT FROM h.previous_state THEN 'order_'||h.state ELSE 'order_changed' END,
   'at',h.created_at,'symbol',h.order_symbol,'previousState',h.previous_state,'state',h.state,
   'previousTotal',CASE WHEN h.price IS DISTINCT FROM h.previous_price AND h.previous_state IS NOT NULL THEN h.previous_price END,
   'total',h.price,'currency',h.currency_code,
   'itemsChanged',h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items,
   'itemsBefore',CASE WHEN h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items THEN h.previous_items END,
   'itemsAfter',CASE WHEN h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items THEN h.items END,
   'detailsChanged',h.previous_state IS NOT NULL AND h.details IS DISTINCT FROM h.previous_details)
  FROM (SELECT snapshots.*,lag(state) OVER w previous_state,lag(price) OVER w previous_price,
   lag(items) OVER w previous_items,lag(details) OVER w previous_details FROM (
    SELECT h.id,h.created_at,h."order",h.state,h.price,coalesce(h.currency_code,o.currency_code) currency_code,o.order_symbol,
     (SELECT coalesce(jsonb_agg(jsonb_build_object('id',p->'id','ticketId',t->'id','ticketSymbol',t->>'ticket_symbol','title',p->>'title','price',p->'price') ORDER BY t->>'id',p->>'id'),'[]')
      FROM jsonb_array_elements(coalesce(h.data->'tickets','[]')) t
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p) items,
     jsonb_build_object('fields',coalesce(h.data->'fields',h.data#>'{input_data,fields}'),'tickets',
      (SELECT jsonb_agg(jsonb_build_object('id',t->'id','fields',t->'fields') ORDER BY t->>'id') FROM jsonb_array_elements(coalesce(h.data->'tickets','[]')) t)) details
    FROM eshop.orders_history h JOIN eshop.orders o ON o.id=h."order" WHERE h."order"=ANY(ids)
      AND h.state IN ('ordered','paid','sent','storno') AND (h.price IS NOT NULL OR h.data ? 'tickets')
   ) snapshots WINDOW w AS (PARTITION BY "order" ORDER BY created_at,id)) h
  WHERE h.state IS DISTINCT FROM h.previous_state OR h.price IS DISTINCT FROM h.previous_price
   OR h.items IS DISTINCT FROM h.previous_items OR h.details IS DISTINCT FROM h.previous_details
 ) events),
 'organizationIdentity',CASE WHEN occ.organization=(SELECT organization FROM public.units WHERE id=occ.unit) THEN public.get_verified_unit_identity_internal(occ.unit) END,
 'allowedActions',public.customer_order_actions_internal(root.id),'changeRequests',public.customer_order_change_requests_internal(root.id),
 'serverTime',statement_timestamp(),'accessExpiresAt',cap.expires_at,'actions',jsonb_build_array('refresh'),
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),'symbol',t.ticket_symbol,
  'answers',public.customer_order_answers_internal(f.id,t.data,true),'effectiveLifecycle',CASE WHEN (SELECT state FROM eshop.orders WHERE id=x."order")='preparing_payment' THEN 'preparing' ELSE public.get_effective_waitlist_ticket_lifecycle_internal(t.id) END,'currentOrderId',x."order") ORDER BY t.id),'[]')
  FROM (SELECT DISTINCT "order",ticket FROM eshop.order_product_ticket WHERE "order"=ANY(ids)) x JOIN eshop.tickets t ON t.id=x.ticket),
 'offers',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'expiresAt',w.expires_at,
  'pendingPlaces',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending' AND w.expires_at>statement_timestamp()),
  'effectiveStatus',CASE WHEN w.expires_at<=statement_timestamp() THEN 'expired'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending') THEN 'pending'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome IN ('declined','cancelled')) THEN 'cancelled' ELSE 'accepted' END)
  ORDER BY w.created_at,w.id),'[]') FROM eshop.waitlist_offers w WHERE w.order_id=root.id AND w.form_id=f.id),
 'orders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'symbol',o.order_symbol,'state',o.state,'total',o.price,'currency',o.currency_code,
  'discount',o.data->'discount',
  'metaAnalytics',public.form_meta_purchase_datalayer_internal(o.id),
  'analytics',CASE WHEN public.form_order_purchase_timing_internal(o.id)='paid' THEN public.form_purchase_datalayer_internal(o.id) END,
  'payment',public.customer_order_payment_internal(o.id),
  'answers',public.customer_order_answers_internal(f.id,o.data,false),
  'ticketIds',(SELECT coalesce(jsonb_agg(t.id ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t),
  'items',CASE WHEN o.state='preparing_payment' THEN '[]'::jsonb ELSE (SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ticketId',t->'id','id',p->'id','title',p->>'title','spotTitle',p->>'spot_title','spotGroupTitle',p->>'spot_group_title','spotGroupKind',p->>'spot_group_kind','isStanding',coalesce((p->>'is_standing')::boolean,false),'standingAreaTitle',p->>'standing_area_title','price',p->'price','basePrice',p->'base_price','discountAmount',p->'discount_amount','currency',p->>'currency_code') ORDER BY (t->>'id')::bigint,
    (SELECT min(coalesce(ff."order",0)) FROM public.form_fields ff WHERE ff.form=f.id AND ff.product_type=product.product_type) NULLS LAST,
    coalesce(product."order",0),product.id),'[]')
   FROM jsonb_array_elements(public.order_tickets_with_seating_internal(o.id,o.data->'tickets')) t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p
   JOIN eshop.products product ON product.id=(p->>'id')::bigint
   WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint)) END,
  'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),'rawState',t.state,
   'displayStatus',CASE t.state WHEN 'ordered' THEN 'awaiting_payment' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END,
   'usageStatus',CASE t.state WHEN 'ordered' THEN 'unused' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END) ORDER BY t.id),'[]')
   FROM public.get_order_tickets_internal(o.id) t)) ORDER BY o.id),'[]')
  FROM eshop.orders o WHERE o.id=ANY(ids) AND o.state IS DISTINCT FROM 'waitlisted')) INTO result;
 result:=result||jsonb_build_object('measurementFormLink',f.link);
 IF EXISTS(SELECT FROM analytics.meta_purchase_deliveries d
   WHERE d.order_id=ANY(ids) AND d.revoked_at IS NULL AND d.status IN ('pending','sent')) THEN
  result:=result||'{"metaPurchaseConsent":true}'::jsonb;
 END IF;
 RETURN result;
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;

-- SOURCE: scanning/projection.sql
-- Set based, minimal projection shared by lookup, search and immutable snapshots.
CREATE OR REPLACE FUNCTION public.scanner_ticket_projection_internal(p_occasion bigint,p_config jsonb,p_ticket bigint DEFAULT NULL)
RETURNS TABLE(ticket_id bigint,dto jsonb) LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH base AS MATERIALIZED (
 SELECT t.*,o.id oid,o.form,o.state order_state,o.updated_at order_updated,o.data order_data,o.note_hidden order_note_hidden,
 pi.amount,pi.paid,public.provider_ticket_requires_online_internal(t.id) online_required,
 coalesce(td.value,'{}'::jsonb) ticket_data,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders oz ON oz.id=z."order"
 WHERE z.ticket=t.id AND (oz.occasion IS DISTINCT FROM t.occasion OR oz.state IN ('stock','storno','waitlisted','preparing_payment'))) bad_order
 FROM eshop.tickets t
 JOIN LATERAL (SELECT x."order" FROM eshop.order_product_ticket x WHERE x.ticket=t.id ORDER BY x."order" LIMIT 1) x ON true
 JOIN eshop.orders o ON o.id=x."order" AND o.occasion=p_occasion
 LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
 LEFT JOIN LATERAL (SELECT value FROM jsonb_array_elements(coalesce(o.data->'tickets','[]'::jsonb)) WHERE value->>'id'=t.id::text LIMIT 1) td ON true
 WHERE t.occasion=p_occasion AND (p_ticket IS NULL OR t.id=p_ticket)
 ), plan_nodes AS MATERIALIZED (
 SELECT bp.id AS blueprint,jsonb_object_agg(n->>'id',n) nodes
 FROM eshop.blueprints bp CROSS JOIN LATERAL jsonb_array_elements(bp.layout->'nodes') n
 WHERE bp.occasion=p_occasion AND n->>'id' IS NOT NULL GROUP BY bp.id ), projected AS (
 SELECT b.*,coalesce(nullif(trim(concat_ws(' ',nullif(trim(b.order_data->>'name'),''),nullif(trim(b.order_data->>'surname'),''))),''),
 (SELECT string_agg(nullif(trim(a.value#>>'{}'),''),' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.order_data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND NOT ff.is_ticket_field WHERE ff.type IN ('name','surname'))) purchaser_name,
 coalesce(nullif(trim(b.order_data->>'email'),''),
 (SELECT nullif(trim(a.value#>>'{}'),'') FROM jsonb_array_elements(coalesce(b.order_data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND NOT ff.is_ticket_field WHERE ff.type='email' LIMIT 1)) purchaser_email,
 coalesce((SELECT string_agg(a.value#>>'{}',' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND ff.is_ticket_field WHERE ff.type IN ('name','surname')),
 (SELECT string_agg(v.value#>>'{}',' ' ORDER BY v.key) FROM jsonb_each(b.ticket_data) v WHERE v.key IN ('name','surname')),
 (SELECT concat_ws(' ',u.name,u.surname) FROM public.occasion_users ou JOIN public.user_info u ON u.id=ou."user" WHERE ou.ticket=b.id AND ou.occasion=p_occasion LIMIT 1),b.ticket_symbol) holder_name,
 (b.state IN ('sent','paid','ordered') AND b.ticket_symbol IS NOT NULL AND NOT b.bad_order AND b.order_state NOT IN ('stock','storno','waitlisted','preparing_payment') AND public.provider_ticket_admission_allowed_internal(b.id)) eligible
 FROM base b)
 SELECT b.id,jsonb_strip_nulls(jsonb_build_object('ticket_id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated_at',b.updated_at,
 'batch_title',(SELECT tb.title FROM eshop.ticket_batch_items bi JOIN eshop.ticket_batches tb ON tb.id=bi.batch_id WHERE bi.ticket_id=b.id AND tb.occasion=p_occasion),
 'order_id',b.oid,'order_state',b.order_state,'purchaser_name',b.purchaser_name,'purchaser_email',CASE WHEN (p_config#>>'{manual_search,tickets}')::boolean THEN b.purchaser_email END,'holder_name',b.holder_name,'admission_allowed',coalesce(b.eligible AND (b.state<>'ordered' OR (p_config#>>'{admission,allow_unpaid_online}')::boolean),false),
 'requires_unpaid_confirmation',b.state='ordered' AND NOT b.bad_order AND b.order_state<>'stock','unavailable_reason',CASE WHEN b.order_state='stock' THEN 'not_sold' END,'online_required',b.online_required,
 'eligibility_fingerprint',encode(digest(jsonb_build_object('v',1,'id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated',b.updated_at,
 'parents',(SELECT jsonb_agg(CASE WHEN pi.payment_method<>'bank' THEN jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid,pi.returned,pi.payment_method,o.email_payment_version) ELSE jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid) END ORDER BY o.id) FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE z.ticket=b.id))::text,'sha256'),'hex'),
 'remaining_amount',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN greatest(0,coalesce(b.amount,0)-coalesce(b.paid,0)) END,
 'order_note',nullif(trim(b.order_data->>'note'),''),'note',nullif(trim(b.note),''),
 'order_note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.order_note_hidden END,
 'note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.note_hidden END,
 'products',coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',p.id,'title',p.title,'short_title',nullif(trim(p.data->>'short_title'),''),'type_id',p.product_type,'type',pt.type,'type_title',pt.title,
 'price',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN p.price END)) ORDER BY array_position(ARRAY(SELECT value::text::bigint FROM jsonb_array_elements(p_config#>'{products,order}')),p.id) NULLS LAST,p."order",p.id)
 FROM eshop.products p LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.occasion=p_occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=b.id AND z.product=p.id)
 AND ((p_config#>>'{products,mode}')='all' OR ((p_config#>>'{products,mode}')='selected' AND (p_config#>'{products,ids}') @> to_jsonb(ARRAY[p.id])))),'[]'::jsonb),
 'spot',(SELECT s.title FROM eshop.spots s JOIN eshop.order_product_ticket z ON z.id=s.order_product_ticket WHERE z.ticket=b.id ORDER BY s.id LIMIT 1),
 'spot_group',coalesce((SELECT jsonb_build_object('blueprint_id',bp.id,'id',g->>'id','title',g->>'label',
    'kind',public.order_seating_kind_internal(pn.nodes,sb.node_id::text,sb.group_node::text))
 FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket
 JOIN eshop.blueprints bp ON bp.id=sp.blueprint
 JOIN eshop.blueprint_seat_bindings sb ON sb.blueprint=bp.id AND sb.spot=sp.id
 JOIN plan_nodes pn ON pn.blueprint=bp.id
 CROSS JOIN LATERAL (SELECT pn.nodes->sb.group_node::text AS g) group_node
 WHERE z.ticket=b.id AND sp.occasion=p_occasion
 AND g->>'kind' IN ('group','table','furniture')
 AND bp.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) ORDER BY sp.id LIMIT 1),
 (SELECT jsonb_build_object('kind','standing','title',standing.metadata->>'standing_area_title')
  FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket
  CROSS JOIN LATERAL (SELECT public.order_standing_spot_metadata_internal(sp.id) AS metadata) standing
  WHERE z.ticket=b.id AND sp.occasion=p_occasion AND sp.blueprint IS NULL
    AND standing.metadata IS NOT NULL ORDER BY sp.id LIMIT 1)),
 'fields',coalesce((SELECT jsonb_agg(jsonb_build_object('key',f->>'key','label',f->>'label','value',
 CASE f->>'source' WHEN 'builtin' THEN CASE f->>'key' WHEN 'holder_name' THEN to_jsonb(b.holder_name) WHEN 'note' THEN to_jsonb(b.note)
 WHEN 'spot' THEN (SELECT to_jsonb(sp.title) FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket WHERE z.ticket=b.id ORDER BY sp.id LIMIT 1)
 WHEN 'groups' THEN (SELECT jsonb_agg(gi.title ORDER BY gi.id) FROM public.occasion_users ou JOIN public.user_groups ug ON ug."user"=ou."user" JOIN public.user_group_info gi ON gi.id=ug."group" WHERE ou.ticket=b.id AND ou.occasion=p_occasion AND gi.occasion=p_occasion) END
 ELSE (SELECT e->(f->>'field_id') FROM jsonb_array_elements(CASE WHEN f->>'source'='order_field' THEN coalesce(b.order_data->'fields','[]'::jsonb) ELSE coalesce(b.data->'fields','[]'::jsonb) END) e WHERE e ? (f->>'field_id') LIMIT 1) END,
 'missing',CASE WHEN f->>'source'='builtin' THEN false ELSE NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.id=(f->>'field_id')::bigint AND ff.form=b.form) END,
 'hide_empty',coalesce((f->>'hide_empty')::boolean,true),'default_visible',coalesce((f->>'default_visible')::boolean,true)) ORDER BY idx)
 FROM jsonb_array_elements(p_config->'fields') WITH ORDINALITY a(f,idx) WHERE f->>'source'='builtin' OR (f->>'form_id')::bigint=b.form),'[]'::jsonb)))
 FROM projected b;
$$;

NOTIFY pgrst, 'reload schema';
