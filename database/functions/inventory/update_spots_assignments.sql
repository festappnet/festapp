-- Batch boundary used by both the legacy RPC and Client Sync v1 command.
CREATE OR REPLACE FUNCTION public.update_spot_assignments(p_changes jsonb)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    c jsonb;
    v_resource public.resources%ROWTYPE;
    v_spot eshop.spots%ROWTYPE;
    context_id bigint;
    slot_id bigint;
    spot_id bigint;
BEGIN
    IF jsonb_typeof(p_changes) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Input must be a JSONB array.' USING ERRCODE='22023';
    END IF;

    -- Serialize competing batches before checking capacity or changing assignments.
    -- Stable lock order also covers resources from all subsequent batch elements.
    PERFORM id FROM public.resources
    WHERE id IN (SELECT (value->>'resource_id')::bigint FROM jsonb_array_elements(p_changes))
    ORDER BY id FOR UPDATE;

    -- Validate every object before the first write. NULL identity/permission denies.
    FOR c IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
        SELECT * INTO v_resource FROM public.resources WHERE id=(c->>'resource_id')::bigint;
        IF NOT FOUND OR v_resource.occasion IS NULL OR
           public.get_is_editor_order_on_occasion(v_resource.occasion) IS NOT TRUE THEN
            RAISE EXCEPTION 'Not authorized for resource' USING ERRCODE='42501';
        END IF;
        context_id := (c->>'inventory_context_id')::bigint;
        slot_id := (c->>'resource_slot_id')::bigint;
        IF NOT EXISTS (SELECT 1 FROM public.inventory_contexts ic
            JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
            WHERE ic.id=context_id AND ic.inventory_pool=v_resource.inventory_pool AND ip.occasion=v_resource.occasion) THEN
            RAISE EXCEPTION 'Invalid inventory context' USING ERRCODE='42501';
        END IF;
        IF slot_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.resource_slots WHERE id=slot_id AND resource=v_resource.id) THEN
            RAISE EXCEPTION 'Invalid resource slot' USING ERRCODE='42501';
        END IF;
        FOREACH spot_id IN ARRAY ARRAY[(c->>'old_spot_id')::bigint,(c->>'new_spot_id')::bigint] LOOP
            IF spot_id IS NULL THEN CONTINUE; END IF;
            SELECT * INTO v_spot FROM eshop.spots WHERE id=spot_id FOR UPDATE;
            IF NOT FOUND OR v_spot.occasion IS DISTINCT FROM v_resource.occasion OR
               v_spot.inventory_context IS DISTINCT FROM context_id THEN
                RAISE EXCEPTION 'Invalid spot scope' USING ERRCODE='42501';
            END IF;
            IF v_spot.resource IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.resources prior
                WHERE prior.id=v_spot.resource AND prior.occasion=v_resource.occasion AND prior.inventory_pool=v_resource.inventory_pool) THEN
                RAISE EXCEPTION 'Invalid prior resource' USING ERRCODE='42501';
            END IF;
            IF v_spot.resource_slot IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.resource_slots prior
                WHERE prior.id=v_spot.resource_slot AND prior.resource=v_spot.resource) THEN
                RAISE EXCEPTION 'Invalid prior slot' USING ERRCODE='42501';
            END IF;
        END LOOP;
        IF (c->>'old_spot_id') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM eshop.spots
            WHERE id=(c->>'old_spot_id')::bigint AND resource=v_resource.id AND resource_slot IS NOT DISTINCT FROM slot_id) THEN
            RAISE EXCEPTION 'Old spot no longer belongs to row' USING ERRCODE='42501';
        END IF;
    END LOOP;

    FOR c IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
        UPDATE eshop.spots SET resource=NULL, resource_slot=NULL, updated_at=now()
        WHERE id=(c->>'old_spot_id')::bigint;
        UPDATE eshop.spots SET resource=(c->>'resource_id')::bigint,
            resource_slot=(c->>'resource_slot_id')::bigint, updated_at=now()
        WHERE id=(c->>'new_spot_id')::bigint;
    END LOOP;
    IF EXISTS (SELECT 1 FROM eshop.spots s JOIN public.resources r ON r.id=s.resource
        WHERE r.id IN (SELECT (value->>'resource_id')::bigint FROM jsonb_array_elements(p_changes))
        GROUP BY r.id,r.capacity,s.inventory_context HAVING count(*)>r.capacity)
       OR EXISTS (SELECT 1 FROM eshop.spots s
        WHERE s.resource_slot IS NOT NULL AND s.resource IN
            (SELECT (value->>'resource_id')::bigint FROM jsonb_array_elements(p_changes))
        GROUP BY s.resource_slot,s.inventory_context HAVING count(*)>1) THEN
        RAISE EXCEPTION 'Resource capacity exceeded' USING ERRCODE='23514';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_spot_assignments(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_spot_assignments(jsonb) TO authenticated, service_role;
