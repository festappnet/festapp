-- Fix ticket-container primary offers and closed-form plan-editor orders.
-- Source: database/functions/eshop_forms/primary_product_guard.sql
-- Structural primary product protection shared by authoring and catalog writes.
CREATE OR REPLACE FUNCTION public.primary_product_delete_blocked_internal(p_product bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE p.id=p_product AND pt.type='spot'
   AND EXISTS(SELECT 1 FROM public.form_fields f WHERE f.product_type=pt.id)
   AND NOT EXISTS(SELECT 1 FROM eshop.products sibling
     WHERE sibling.product_type=pt.id AND sibling.id<>p.id AND NOT sibling.is_hidden));
$$;
REVOKE ALL ON FUNCTION public.primary_product_delete_blocked_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.lock_primary_product_forms_internal(p_product bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM 1 FROM public.forms f WHERE f.id IN(
   SELECT ff.form FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
   JOIN eshop.products p ON p.product_type=pt.id WHERE p.id=p_product AND pt.type='spot')
 ORDER BY f.id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_primary_product_forms_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assert_form_primary_products_internal(p_form bigint,p_preserve bigint[] DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM unnest(p_preserve) required(id) WHERE NOT EXISTS(
   SELECT 1 FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
   -- Both ordinary offers and seated forms can own the primary catalog.
   WHERE ff.form=p_form AND pt.id=required.id AND pt.type='spot' AND ff.type IN ('product_type','ticket') AND NOT ff.is_hidden))
 OR EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
   WHERE ff.form=p_form AND pt.type='spot' AND (ff.is_hidden OR NOT EXISTS(
     SELECT 1 FROM eshop.products p WHERE p.product_type=pt.id AND NOT p.is_hidden)))
 OR (EXISTS(SELECT 1 FROM public.form_fields WHERE form=p_form AND type='ticket')
   AND EXISTS(SELECT 1 FROM public.form_fields WHERE form=p_form AND type='product_type' AND NOT is_hidden)
   AND NOT EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
     WHERE ff.form=p_form AND pt.type='spot' AND NOT ff.is_hidden)) THEN
   RAISE EXCEPTION 'FORM_DELETE_primary_product';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_form_primary_products_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop/analyze_new_order_spots.sql
CREATE OR REPLACE FUNCTION public.analyze_new_order_spots(
  p_spot_ids bigint[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_conflicts jsonb;
  v_new_order_items jsonb;
  v_occasion_id BIGINT;
  v_total numeric; v_currency text; v_order_form jsonb;
BEGIN
  -- =======================================================================
  -- 0. VALIDATION & SECURITY
  -- =======================================================================

  -- Handle empty input
  IF p_spot_ids IS NULL OR array_length(p_spot_ids, 1) IS NULL THEN
     RETURN jsonb_build_object('conflicts', '[]'::jsonb, 'new_order_items', '[]'::jsonb);
  END IF;

  -- Get Occasion ID from the first spot
  SELECT occasion INTO v_occasion_id
  FROM eshop.spots
  WHERE id = p_spot_ids[1];

  IF v_occasion_id IS NULL THEN
     RAISE EXCEPTION 'Spot ID % not found.', p_spot_ids[1];
  END IF;

  -- Consistency Check: Ensure all selected spots belong to the SAME occasion
  PERFORM 1
  FROM eshop.spots
  WHERE id = ANY(p_spot_ids)
  AND occasion != v_occasion_id;

  IF FOUND THEN
     RAISE EXCEPTION 'All selected spots must belong to the same occasion.';
  END IF;

  -- Permission Check: User must have "Order View" rights on this occasion
  IF public.can_read_orders(v_occasion_id) IS NOT TRUE THEN
     RAISE EXCEPTION 'Permission denied. User does not have view rights for occasion %.', v_occasion_id;
  END IF;

  IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spot_ids) AND occasion=v_occasion_id)<>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id)) THEN
    RAISE EXCEPTION 'BLUEPRINT_SPOT_SCOPE_MISMATCH'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion_id]);
  PERFORM public.check_blueprint_selection_units_internal(p_spot_ids);

  -- =======================================================================
  -- 1. IDENTIFY CONFLICTS
  -- =======================================================================
  WITH impacted_base AS (
    SELECT
      s.id as spot_id,
      o.id as order_id,
      o.data as order_data,
      o.state as order_state,
      t.id as ticket_id,
      t.ticket_symbol
    FROM eshop.spots s
    JOIN eshop.order_product_ticket opt ON s.order_product_ticket = opt.id
    JOIN eshop.tickets t ON opt.ticket = t.id
    JOIN eshop.orders o ON opt.order = o.id
    WHERE s.id = ANY(p_spot_ids)
    -- Include any state that implies the spot is technically "occupied"
  ),
  impacted_tickets AS (
    SELECT order_id,order_data,order_state,ticket_id,ticket_symbol,
      array_agg(DISTINCT spot_id ORDER BY spot_id) AS selected_spot_ids
    FROM impacted_base GROUP BY order_id,order_data,order_state,ticket_id,ticket_symbol
  ),
  impacted_enriched AS (
    -- Safely extract the specific ticket from JSON
    SELECT
      ib.*,
      (
        SELECT item
        FROM jsonb_array_elements(ib.order_data->'tickets') item
        WHERE (item->>'id')::bigint = ib.ticket_id
        LIMIT 1
      ) as ticket_json
    FROM impacted_tickets ib
  ),
  order_stats AS (
    -- Calculate if whole order is cancelled
    SELECT
      order_id,
      COUNT(DISTINCT ticket_id) as affected_ticket_count,
      COALESCE(jsonb_array_length(order_data->'tickets'), 0) as total_ticket_count
    FROM impacted_enriched
    GROUP BY order_id, order_data
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'order_id', ie.order_id,
      -- Extract individual fields as requested
      'email', ie.order_data->>'email',
      'name', ie.order_data->>'name',
      'surname', ie.order_data->>'surname',
      'note', ie.order_data->>'note',

      'ticket_id', ie.ticket_id,
      'selected_spot_ids', ie.selected_spot_ids,
      'ticket_symbol', ie.ticket_symbol,
      'is_fully_cancelled', (os.affected_ticket_count >= os.total_ticket_count AND os.total_ticket_count > 0),
      -- The products array from the JSON (Spot + Extras)
      'products', ie.ticket_json->'products',
      -- Sum the price (safely handle nulls)
      'total_price', CASE WHEN jsonb_typeof(ie.ticket_json->'products')='array'
        AND jsonb_array_length(ie.ticket_json->'products')>0
        AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(ie.ticket_json->'products') prod WHERE prod->>'price' IS NULL)
        THEN (SELECT SUM((prod->>'price')::numeric) FROM jsonb_array_elements(ie.ticket_json->'products') prod)
        ELSE NULL END
    )
  )
  INTO v_conflicts
  FROM impacted_enriched ie
  JOIN order_stats os ON ie.order_id = os.order_id;

  -- =======================================================================
  -- 2. PREPARE NEW ORDER ITEMS
  -- =======================================================================
  SELECT jsonb_agg(jsonb_build_object(
    'spot_id', s.id,
    'spot_title', s.title,
    'product_title', p.title,
    'price', p.price,
    'currency', p.currency_code
  ))
  INTO v_new_order_items
  FROM eshop.spots s
  LEFT JOIN eshop.products p ON s.product = p.id
  WHERE s.id = ANY(p_spot_ids);

  IF (SELECT count(DISTINCT item->>'currency') FROM jsonb_array_elements(coalesce(v_new_order_items,'[]')) item)>1 THEN RAISE EXCEPTION 'BLUEPRINT_CURRENCY_MISMATCH'; END IF;
  SELECT coalesce(sum((item->>'price')::numeric),0),min(item->>'currency') INTO v_total,v_currency FROM jsonb_array_elements(coalesce(v_new_order_items,'[]')) item;
  SELECT jsonb_build_object('key',f.key,'phone_prefixes',public.get_effective_form_data(f.id)->'phone_prefixes',
    'fields',coalesce((SELECT jsonb_agg(to_jsonb(ff) ORDER BY coalesce(ff."order",0),ff.id)
      FROM public.form_fields ff WHERE ff.form=f.id AND ff.is_required=true
      AND ff.is_hidden=false AND ff.type NOT IN ('ticket','spot','product_type')),'[]'::jsonb))
    -- Match finalization's order-editor override without opening public sales.
    INTO v_order_form FROM public.forms f WHERE f.occasion=v_occasion_id
      AND (f.is_open=true OR public.can_write_orders(v_occasion_id))
      AND f.blueprint=(SELECT blueprint FROM eshop.spots WHERE id=p_spot_ids[1])
      AND NOT EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(p_spot_ids) AND blueprint IS DISTINCT FROM (SELECT blueprint FROM eshop.spots WHERE id=p_spot_ids[1]))
    ORDER BY f.is_open DESC,f.type='ticket' DESC,f.id DESC LIMIT 1;
  RETURN jsonb_build_object(
    'conflicts', COALESCE(v_conflicts, '[]'::jsonb),
    'new_order_items', COALESCE(v_new_order_items, '[]'::jsonb),
    'total_price',v_total,'currency',v_currency,'order_form',v_order_form
  );
END;
$$;
