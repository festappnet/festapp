CREATE OR REPLACE FUNCTION public.get_orders_tab_data(
    p_occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_orders_data JSONB;
    v_forms_data JSONB;
    v_occasion BIGINT;
BEGIN
    SELECT id INTO v_occasion FROM public.occasions
    WHERE id=public.resolve_occasion_link_internal(p_occasion_link)
      AND organization=(SELECT organization FROM public.user_info WHERE id=auth.uid());
    IF auth.uid() IS NULL OR v_occasion IS NULL
       OR NOT coalesce(public.get_is_editor_order_view_on_occasion(v_occasion),false) THEN
        RAISE insufficient_privilege USING MESSAGE='order viewer required';
    END IF;

    SELECT get_orders(p_occasion_link, NULL, '{}'::jsonb) INTO v_orders_data;

    IF (v_orders_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_orders failed: %', v_orders_data->>'message';
    END IF;

    SELECT get_all_forms_with_fields(p_occasion_link) INTO v_forms_data;

    IF (v_forms_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_all_forms_with_fields failed: %', v_forms_data->>'message';
    END IF;

    v_orders_data:=jsonb_set(v_orders_data,'{data,orders}',coalesce((SELECT jsonb_agg(o) FROM jsonb_array_elements(v_orders_data#>'{data,orders}') o WHERE o->>'state' IS DISTINCT FROM 'stock'),'[]'));

    RETURN (v_orders_data->'data') || jsonb_build_object('forms', v_forms_data->'data', 'email_delivery',
      public.get_order_email_summaries(v_occasion,
        ARRAY(SELECT (ord->>'id')::bigint FROM jsonb_array_elements(v_orders_data#>'{data,orders}') ord)));
END;
$$;
