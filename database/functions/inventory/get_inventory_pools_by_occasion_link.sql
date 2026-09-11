CREATE OR REPLACE FUNCTION public.get_inventory_pools_by_occasion_link(p_occasion_link text)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_occasion_data jsonb;
    v_pools_data jsonb;
    v_inventory_contexts_data jsonb;
    v_spots_data jsonb;
    result jsonb;
BEGIN
    -- Canonical merges may contain the same legacy link in multiple tenants.
    SELECT o.id
    INTO v_occasion_id
    FROM public.occasions o
    WHERE o.link = p_occasion_link
      AND o.organization = (
        SELECT ui.organization
        FROM public.user_info ui
        WHERE ui.id = auth.uid()
      );
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion with link % not found.', p_occasion_link;
    END IF;

    -- Permission check to ensure the user can view data for this occasion.
    IF NOT COALESCE((
        SELECT ou.is_editor_order_view
        FROM public.occasion_users ou
        WHERE ou."user" = auth.uid()
          AND ou.occasion = v_occasion_id
    ), false) THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Get the full occasion object
    SELECT to_jsonb(o) INTO v_occasion_data FROM public.occasions o WHERE id = v_occasion_id;

    -- Aggregate all inventory pools for the occasion, sorted by creation date.
    SELECT COALESCE(jsonb_agg(to_jsonb(ip) ORDER BY ip.created_at), '[]'::jsonb)
    INTO v_pools_data
    FROM public.inventory_pools ip
    WHERE ip.occasion = v_occasion_id;

    -- Aggregate all inventory_contexts for all pools of the occasion, sorted by the 'order' column.
    SELECT COALESCE(jsonb_agg(to_jsonb(ic) ORDER BY ic.order), '[]'::jsonb)
    INTO v_inventory_contexts_data
    FROM public.inventory_contexts ic
    WHERE ic.inventory_pool IN (SELECT id FROM public.inventory_pools WHERE occasion = v_occasion_id);

    -- Aggregate all spots that belong to any context within the occasion's pools
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'secret', s.secret,
        'secret_expiration_time', s.secret_expiration_time,
        'order_product_ticket', s.order_product_ticket,
        'inventory_context', s.inventory_context,
        'resource', s.resource,
        'state', s.state
    ) ORDER BY s.id), '[]'::jsonb)
    INTO v_spots_data
    FROM eshop.spots s
    WHERE s.inventory_context IN (
        SELECT id FROM public.inventory_contexts WHERE inventory_pool IN (
            SELECT id FROM public.inventory_pools WHERE occasion = v_occasion_id
        )
    );

    -- Construct the final bundle object with the new data
    result := jsonb_build_object(
        'occasion', v_occasion_data,
        'pools', v_pools_data,
        'inventory_contexts', v_inventory_contexts_data,
        'spots', v_spots_data
    );

    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;
