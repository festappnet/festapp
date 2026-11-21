CREATE OR REPLACE FUNCTION public.get_products_for_ticket(
  ticket_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion_id bigint;
  v_order_json jsonb;
  v_payment_info_json jsonb;
  v_ticket jsonb;
  v_latest_sent_at timestamptz;
  v_is_newer_available boolean := FALSE;
  v_order_id bigint;
  v_changes jsonb;
  v_admission jsonb;
  v_ticket_state text;
  v_batch boolean;
  v_actions jsonb;
  reference_history_data jsonb;
BEGIN
  -- Find the order containing the ticket and LEFT JOIN its associated payment_info.
  SELECT
    o.id,
    o.occasion,
    to_jsonb(o),
    to_jsonb(pi)
  INTO
    v_order_id,
    v_occasion_id,
    v_order_json,
    v_payment_info_json
  FROM eshop.orders AS o
  LEFT JOIN eshop.payment_info AS pi ON o.payment_info = pi.id
  WHERE EXISTS (
    SELECT 1
    FROM   jsonb_array_elements(o.data->'tickets') AS t
    WHERE  (t->>'id')::bigint = ticket_id
  );

  -- Check if the order was found.
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'code',    404,
      'message', 'Ticket not found'
    );
  END IF;

  -- Permission check.
  IF public.can_read_orders(v_occasion_id) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'code',    403,
      'message', 'Not authorized to view this ticket'
    );
  END IF;

  -- Extract the full JSON object for the specified ticket from the order's data.
  SELECT t
  INTO   v_ticket
  FROM   jsonb_array_elements(v_order_json->'data'->'tickets') AS t
  WHERE  (t->>'id')::bigint = ticket_id;

  v_admission := public.ticket_admission_integrity_internal(v_order_id,ticket_id)-'productIds';
  v_admission := v_admission||jsonb_build_object('recordedPlaces',coalesce((
    SELECT jsonb_agg(DISTINCT concat_ws(' · ',place->>'groupTitle',place->>'title'))
    FROM jsonb_array_elements(public.order_admin_places_internal(v_order_id)) place
    WHERE place->>'ticketId'=ticket_id::text),'[]'));
  v_actions := CASE WHEN public.can_write_orders(v_occasion_id) IS TRUE
    THEN public.get_order_allowed_actions_internal_v1(v_order_id) ELSE '["view"]'::jsonb END;
  SELECT t.state, EXISTS(SELECT 1 FROM eshop.ticket_batch_items bi WHERE bi.ticket_id=t.id)
  INTO v_ticket_state,v_batch FROM eshop.tickets t WHERE t.id=ticket_id;
  v_ticket := public.order_ticket_admission_snapshot_internal(v_ticket,v_occasion_id)
    || jsonb_build_object('state',v_ticket_state,'batch',CASE WHEN v_batch THEN '{}'::jsonb END);
  v_order_json := v_order_json || jsonb_build_object('allowedActions',v_actions,'payment_method',v_payment_info_json->'payment_method');

  v_changes := public.get_order_change_summary_v1(v_order_id);
  reference_history_data := v_changes->'referenceOrder';
  v_latest_sent_at := (v_changes->>'latestSentAt')::timestamptz;
  v_is_newer_available := (v_changes->>'hasChanges')::boolean;

  -- Build the simplified and comprehensive JSONB response object.
  RETURN jsonb_build_object(
    'code', 200,
    'data', jsonb_build_object(
      'ticket', v_ticket,
      'admission', v_admission,
      'canEdit', public.can_write_orders(v_occasion_id) IS TRUE AND v_actions ? 'edit'
        AND v_ticket_state NOT IN ('used','storno','waitlisted') AND NOT v_batch
        AND v_admission->>'reason' IS NULL
        AND NOT public.payment_method_is_online_internal(v_payment_info_json->>'payment_method')
        AND NOT EXISTS(SELECT 1 FROM eshop.order_discounts d WHERE d.order_id=v_order_id),
      'order', v_order_json,
      'payment_info', v_payment_info_json,
      'order_history', jsonb_build_object(
          'latest_sent_at', v_latest_sent_at,
          'is_newer_version_available', v_is_newer_available
      ),
      'reference_order_data', reference_history_data,
      'order_changes', v_changes
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'code',    500,
    'message', SQLERRM
  );
END;
$$;
