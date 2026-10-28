DROP FUNCTION IF EXISTS public.get_orders_tab_data(text);
CREATE OR REPLACE FUNCTION public.get_orders_tab_data(
    p_occasion_link TEXT,
    p_notification_group JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_orders_data JSONB;
    v_forms_data JSONB;
    v_notification_ids JSONB := '[]'::jsonb;
BEGIN

    SELECT get_orders(p_occasion_link, NULL, '{}'::jsonb) INTO v_orders_data;

    IF (v_orders_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_orders failed: %', v_orders_data->>'message';
    END IF;

    SELECT get_all_forms_with_fields(p_occasion_link) INTO v_forms_data;

    IF (v_forms_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_all_forms_with_fields failed: %', v_forms_data->>'message';
    END IF;

    v_orders_data:=jsonb_set(v_orders_data,'{data,orders}',coalesce((SELECT jsonb_agg(o) FROM jsonb_array_elements(v_orders_data#>'{data,orders}') o WHERE o->>'state' IS DISTINCT FROM 'stock'),'[]'));
    IF p_notification_group IS NOT NULL THEN
      SELECT public.notification_center_order_selection(
        (v_orders_data->>'occasion_id')::bigint,p_notification_group) INTO v_notification_ids;
      -- Keep only records in the independently authorized orders response.
      SELECT coalesce(jsonb_agg(o->'id'),'[]'::jsonb) INTO v_notification_ids
      FROM jsonb_array_elements(v_orders_data#>'{data,orders}') o
      WHERE (o->>'id')::bigint IN (SELECT value::bigint FROM jsonb_array_elements_text(v_notification_ids));
    END IF;
    IF p_notification_group->>'markRead'='true' THEN
      PERFORM public.mark_notification_center_item_read(
        (p_notification_group->>'organization')::bigint,p_notification_group);
    END IF;
    -- No orders means no delivery status. Do not resolve an ambiguous event slug.
    RETURN (v_orders_data->'data') || jsonb_build_object('notification_order_ids',v_notification_ids,'forms', v_forms_data->'data', 'email_delivery',
      CASE WHEN jsonb_array_length(v_orders_data#>'{data,orders}') = 0
        THEN '{}'::jsonb
        ELSE public.get_order_email_summaries(
          (v_orders_data->>'occasion_id')::bigint,
          ARRAY(SELECT (ord->>'id')::bigint
            FROM jsonb_array_elements(v_orders_data#>'{data,orders}') ord))
      END);
END;
$$;

REVOKE ALL ON FUNCTION public.get_orders_tab_data(text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_orders_tab_data(text,jsonb) TO anon,authenticated,service_role;
