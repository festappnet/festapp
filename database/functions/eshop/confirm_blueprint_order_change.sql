CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_internal_v1(
  p_spot_ids BIGINT[],
  p_input_data JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_analysis JSONB;
  v_ticket_ids_to_cancel BIGINT[];
  v_occasion_id BIGINT;
  v_form_key UUID;
  v_ticket_payloads JSONB := '[]'::JSONB;
  v_order_details JSONB;
  v_new_spot_rec RECORD;
  v_email TEXT;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id=ANY(p_spot_ids)));
  PERFORM public.check_blueprint_selection_units_internal(p_spot_ids);
  -- Extract Email for validation
  v_email := p_input_data->>'email';

  IF v_email IS NULL OR v_email = '' THEN
      RAISE EXCEPTION 'Email is required in input data.';
  END IF;

  -- 1. Analyze impacts
  v_analysis := public.analyze_new_order_spots(p_spot_ids);

  -- 2. Extract Ticket IDs for Storno
  SELECT ARRAY_AGG((elem->>'ticket_id')::BIGINT)
  INTO v_ticket_ids_to_cancel
  FROM jsonb_array_elements(v_analysis->'conflicts') elem
  WHERE elem->>'ticket_id' IS NOT NULL;

  -- 3. Perform Storno (if any conflicts exist)
  IF v_ticket_ids_to_cancel IS NOT NULL AND array_length(v_ticket_ids_to_cancel, 1) > 0 THEN
      PERFORM public.storno_tickets_bulk_internal_v1(v_ticket_ids_to_cancel);
  END IF;

  -- 4. Clean up Secrets on selected spots
  UPDATE eshop.spots
  SET secret = NULL, secret_expiration_time = NULL
  WHERE id = ANY(p_spot_ids);

  -- 5. Prepare Data for New Order

  -- Get occasion ID
  SELECT occasion INTO v_occasion_id FROM eshop.spots WHERE id = p_spot_ids[1];

  -- Security Check: User must be editor
  IF NOT public.get_is_editor_order_on_occasion(v_occasion_id) THEN
      RAISE EXCEPTION 'Permission denied. User is not an editor for occasion %', v_occasion_id;
  END IF;

  -- Validation: All spots must be on same occasion
  PERFORM 1 FROM eshop.spots
  WHERE id = ANY(p_spot_ids) AND occasion != v_occasion_id;

  IF FOUND THEN
      RAISE EXCEPTION 'All selected spots must belong to the same occasion.';
  END IF;

  -- Find a suitable Form
  v_form_key := (v_analysis->'order_form'->>'key')::uuid;
  IF p_input_data->>'form_key' IS NOT NULL AND p_input_data->>'form_key' IS DISTINCT FROM v_form_key::text THEN
    RAISE EXCEPTION 'The active order form changed. Reopen the order.';
  END IF;

  IF v_form_key IS NULL THEN
      RAISE EXCEPTION 'No open form found for this occasion to create the new order.';
  END IF;

  -- Build "ticket" array for the payload
  FOR v_new_spot_rec IN
      SELECT s.id, s.product
      FROM eshop.spots s
      WHERE s.id = ANY(p_spot_ids)
  LOOP
      v_ticket_payloads := v_ticket_payloads || JSONB_BUILD_OBJECT(
          'spot', v_new_spot_rec.id,
          'fields', coalesce(p_input_data->'ticket_fields'->v_new_spot_rec.id::text,'[]'::jsonb)
      );
  END LOOP;

  -- Construct payload for Edge Function
  -- We start with basic fields, then MERGE (||) the p_input_data
  -- This allows passing 'name', 'surname', 'note' in input_data automatically.
  v_order_details := JSONB_BUILD_OBJECT(
      'form', v_form_key,
      'ticket', v_ticket_payloads,
      'lang', 'cs'
  ) || (p_input_data - 'ticket_fields' - 'form_key' - 'form' - 'ticket');

  -- Return Success + Payload
  RETURN JSONB_BUILD_OBJECT(
      'success', true,
      'message', 'Storno performed. Ready to create new order.',
      'orderDetails', v_order_details
  );

EXCEPTION WHEN OTHERS THEN
  RETURN JSONB_BUILD_OBJECT('success', false, 'message', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_internal_v1(bigint[],jsonb) FROM PUBLIC,anon,authenticated,service_role;
