CREATE OR REPLACE FUNCTION select_spot(
    form_key UUID,
    secret_id UUID,
    spot_id BIGINT,
    selecting BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprint_id BIGINT;
    spot_record RECORD;
BEGIN
    PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=form_key));
    -- Check if the spot exists under the current form's blueprint
    SELECT b.id INTO blueprint_id
    FROM public.forms f
    JOIN eshop.blueprints b ON f.blueprint = b.id
    WHERE f.key = form_key;

    IF blueprint_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Form key does not exist or is not associated with a blueprint'
        );
    END IF;

    -- Check if the spot exists in the blueprint
    SELECT * INTO spot_record
    FROM eshop.spots
    WHERE id = spot_id AND blueprint = blueprint_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Spot does not exist under the current blueprint'
        );
    END IF;

    -- Check if the spot is already ordered
    IF spot_record.order_product_ticket IS NOT NULL THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Spot is already ordered'
        );
    END IF;

    -- Check if the secret expiration time is valid
    IF spot_record.secret_expiration_time IS NOT NULL
       AND spot_record.secret_expiration_time < now() THEN
        -- Expire the current secret
        UPDATE eshop.spots
        SET secret = NULL,
            secret_expiration_time = NULL
        WHERE id = spot_id;

        -- Re-fetch the spot record after potential expiration update
        -- (This is necessary because the original spot_record might be stale,
        -- but for the specific logic below, checking for NULL secret is sufficient.
        -- We will rely on the check within the ELSE block.)
    END IF;

    -- Handle selection or deselection
    IF selecting THEN
        -- Select the spot
        UPDATE eshop.spots
        SET secret = secret_id,
            secret_expiration_time = now() + interval '15 minutes',
            updated_at = now()
        WHERE id = spot_id;

        RETURN jsonb_build_object(
            'code', 200,
            'message', 'Spot successfully selected'
        );
    ELSE
        -- Deselect the spot

        -- CASE 1: Spot is already deselected (secret is NULL)
        IF spot_record.secret IS NULL THEN
            RETURN jsonb_build_object(
                'code', 200,
                'message', 'Spot is already deselected' -- Or 'Spot successfully deselected'
            );
        END IF;

        -- CASE 2: Provided secret does not match the current secret
        IF spot_record.secret IS DISTINCT FROM secret_id THEN
            RETURN jsonb_build_object(
                'code', 403,
                'message', 'Cannot deselect spot. Provided secret does not match.'
            );
        END IF;

        -- CASE 3: Deselect the spot
        UPDATE eshop.spots
        SET secret = NULL,
            secret_expiration_time = NULL,
            updated_at = now()
        WHERE id = spot_id;

        RETURN jsonb_build_object(
            'code', 200,
            'message', 'Spot successfully deselected'
        );
    END IF;
END;
$$;
