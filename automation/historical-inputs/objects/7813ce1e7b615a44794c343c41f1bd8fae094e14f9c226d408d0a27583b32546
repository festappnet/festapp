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
  IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
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

  v_changes := public.get_order_change_summary_v1(v_order_id);
  reference_history_data := v_changes->'referenceOrder';
  v_latest_sent_at := (v_changes->>'latestSentAt')::timestamptz;
  v_is_newer_available := (v_changes->>'hasChanges')::boolean;

  -- Build the simplified and comprehensive JSONB response object.
  RETURN jsonb_build_object(
    'code', 200,
    'data', jsonb_build_object(
      'ticket', v_ticket,
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
