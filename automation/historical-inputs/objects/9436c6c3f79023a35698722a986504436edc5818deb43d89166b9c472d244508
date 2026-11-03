-- This function replaces the need to call `update_spot` in a loop.
-- It processes a batch of spot assignment changes for a given UI row in a single transaction.
CREATE OR REPLACE FUNCTION public.update_spot_assignments(p_changes jsonb)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_change jsonb;
    v_occasion_id bigint;
    v_checked_occasion_id bigint;
    v_old_spot_id bigint;
    v_new_spot_id bigint;
    v_resource_id bigint;
    v_resource_slot_id bigint;
BEGIN
    -- Ensure the input is a valid JSON array.
    IF jsonb_typeof(p_changes) != 'array' THEN
        RAISE EXCEPTION 'Input must be a JSONB array.';
    END IF;

    -- Loop through each change object in the JSONB array.
    FOR v_change IN SELECT * FROM jsonb_array_elements(p_changes)
    LOOP
        -- Extract IDs from the current change object.
        v_old_spot_id := (v_change->>'old_spot_id')::bigint;
        v_new_spot_id := (v_change->>'new_spot_id')::bigint;
        v_resource_id := (v_change->>'resource_id')::bigint;
        v_resource_slot_id := (v_change->>'resource_slot_id')::bigint;

        -- On the first iteration, determine the occasion from the resource and check permissions.
        IF v_occasion_id IS NULL THEN
            SELECT occasion INTO v_occasion_id
            FROM public.resources
            WHERE id = v_resource_id;

            IF v_occasion_id IS NULL THEN
                RAISE EXCEPTION 'Resource with ID % not found.', v_resource_id;
            END IF;

            -- Permission check.
            IF NOT get_is_editor_order_on_occasion(v_occasion_id) THEN
                RAISE EXCEPTION 'User is not authorized to modify assignments for this occasion.';
            END IF;
        END IF;

        -- Un-assign the old spot if one was specified.
        IF v_old_spot_id IS NOT NULL THEN
            UPDATE eshop.spots
            SET
                resource = NULL,
                resource_slot = NULL,
                updated_at = now()
            WHERE id = v_old_spot_id;
        END IF;

        -- Assign the new spot to the resource/slot if one was specified.
        IF v_new_spot_id IS NOT NULL THEN
            UPDATE eshop.spots
            SET
                resource = v_resource_id,
                resource_slot = v_resource_slot_id,
                updated_at = now()
            WHERE id = v_new_spot_id;
        END IF;
    END LOOP;
END;
$$;
