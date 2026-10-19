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
  IF NOT public.get_is_editor_order_view_on_occasion(v_occasion_id) THEN
     RAISE EXCEPTION 'Permission denied. User does not have view rights for occasion %.', v_occasion_id;
  END IF;

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
    FROM impacted_base ib
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
      'ticket_symbol', ie.ticket_symbol,
      'is_fully_cancelled', (os.affected_ticket_count >= os.total_ticket_count AND os.total_ticket_count > 0),
      -- The products array from the JSON (Spot + Extras)
      'products', ie.ticket_json->'products',
      -- Sum the price (safely handle nulls)
      'total_price', (
         SELECT COALESCE(SUM((prod->>'price')::numeric), 0)
         FROM jsonb_array_elements(ie.ticket_json->'products') prod
      )
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

  RETURN jsonb_build_object(
    'conflicts', COALESCE(v_conflicts, '[]'::jsonb),
    'new_order_items', COALESCE(v_new_order_items, '[]'::jsonb)
  );
END;
$$;