CREATE OR REPLACE FUNCTION get_orders_tab_data(
    p_occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_orders_data JSONB;
    v_forms_data JSONB;
BEGIN

    SELECT get_orders(p_occasion_link, NULL, '{}'::jsonb) INTO v_orders_data;

    IF (v_orders_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_orders failed: %', v_orders_data->>'message';
    END IF;

    SELECT get_all_forms_with_fields(p_occasion_link) INTO v_forms_data;

    IF (v_forms_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_all_forms_with_fields failed: %', v_forms_data->>'message';
    END IF;

    RETURN (v_orders_data->'data') || jsonb_build_object('forms', v_forms_data->'data', 'email_delivery',
      public.get_order_email_summaries((SELECT id FROM public.occasions WHERE link=p_occasion_link),
        ARRAY(SELECT (ord->>'id')::bigint FROM jsonb_array_elements(v_orders_data#>'{data,orders}') ord)));
END;
$$;
