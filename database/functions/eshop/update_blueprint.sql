CREATE OR REPLACE FUNCTION update_blueprint(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprint_id BIGINT;
    updated_objects JSONB := '[]'::JSONB;
    object_data JSONB;
    spot_id BIGINT;
    now TIMESTAMP WITH TIME ZONE := NOW();
    spot RECORD;
    spot_ids_in_objects BIGINT[] := ARRAY[]::BIGINT[];
    existing_spot_ids BIGINT[];
    occasion_id BIGINT;
    organization_id BIGINT;
    product_id BIGINT;
    spot_title TEXT; -- Updated variable name for title
BEGIN
    -- Validate input data
    IF input_data IS NULL THEN
        RETURN JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing');
    END IF;

    -- Get occasion ID from input data
    IF input_data->>'occasion' IS NULL THEN
        RETURN JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data');
    END IF;

    occasion_id := (input_data->>'occasion')::BIGINT;

    IF (SELECT get_is_editor_order_on_occasion(occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    -- Get organization ID from input data
    IF input_data->>'organization' IS NULL THEN
        RETURN JSONB_BUILD_OBJECT('code', 4003, 'message', 'Missing organization ID in input data');
    END IF;

    organization_id := (input_data->>'organization')::BIGINT;

    -- Get blueprint ID
    blueprint_id := NULLIF(input_data->>'id', '')::BIGINT;

    IF blueprint_id IS NULL THEN
        -- Create a new blueprint
        INSERT INTO eshop.blueprints (
            created_at
        )
        VALUES (
            now
        )
        RETURNING id INTO blueprint_id;
    END IF;

    -- Process objects in input_data->'objects'
    IF input_data->'objects' IS NOT NULL THEN
        FOR object_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'objects') LOOP
            -- Handle "spot" type objects
            IF object_data->>'type' = 'spot' THEN
                -- Extract spot title
                spot_title := object_data->>'title';

                -- Validate product_id
                product_id := NULL;
                IF object_data ? 'product' AND object_data->>'product' IS NOT NULL THEN
                    product_id := (object_data->>'product')::BIGINT;

                    -- Ensure the product exists in eshop.products
                    IF NOT EXISTS (
                        SELECT 1
                        FROM eshop.products
                        WHERE id = product_id AND occasion = occasion_id
                    ) THEN
                        product_id := NULL;
                    END IF;
                END IF;

                -- Return error for invalid or missing product_id
                IF product_id IS NULL THEN
                    RETURN JSONB_BUILD_OBJECT(
                        'code', 4004,
                        'message', 'Invalid or missing product. Ensure the product exists and is part of the occasion.',
                        'details', JSONB_BUILD_OBJECT(
                            'product_id', NULL,
                            'object', object_data
                        )
                    );
                END IF;

                -- Collect spot IDs from objects
                IF object_data ? 'id' AND object_data->>'id' IS NOT NULL THEN
                    spot_ids_in_objects := spot_ids_in_objects || (object_data->>'id')::BIGINT;

                    -- Update the spot's product and title if applicable
                    UPDATE eshop.spots
                    SET
                        product = product_id,
                        title = spot_title,
                        updated_at = now
                    WHERE id = (object_data->>'id')::BIGINT;
                ELSE
                    -- Create a new spot if ID is null
                    INSERT INTO eshop.spots (
                        created_at,
                        updated_at,
                        occasion,
                        blueprint,
                        title,
                        product
                    )
                    VALUES (
                        now,
                        now,
                        occasion_id,
                        blueprint_id,
                        spot_title,
                        product_id
                    )
                    RETURNING id INTO spot_id;

                    -- Append the new spot ID to the list
                    spot_ids_in_objects := spot_ids_in_objects || spot_id;

                    -- Update the object with the new spot ID
                    object_data := jsonb_set(object_data, '{id}', TO_JSONB(spot_id));
                END IF;

                -- Remove title and product from the object before adding to updated_objects
                object_data := object_data - 'title' - 'product';
            END IF;

            -- Add updated object to the updated_objects array
            updated_objects := updated_objects || object_data;
        END LOOP;
    END IF;

    -- Get all spot IDs currently associated with the blueprint
    SELECT ARRAY_AGG(id) INTO existing_spot_ids
    FROM eshop.spots
    WHERE blueprint = blueprint_id;

    IF existing_spot_ids IS NULL THEN
        existing_spot_ids := ARRAY[]::BIGINT[];
    END IF;

    -- Identify and validate spots to delete
    FOR spot_id IN SELECT unnest(existing_spot_ids) LOOP
        IF NOT spot_id = ANY(spot_ids_in_objects) THEN
            -- Fetch the spot
            SELECT * INTO spot FROM eshop.spots WHERE id = spot_id;

            -- Check conditions for deletion
            IF (spot.secret_expiration_time IS NULL OR spot.secret_expiration_time < now OR spot.secret IS NULL)
               AND spot.order_product_ticket IS NULL THEN
                -- Safe to delete
                DELETE FROM eshop.spots WHERE id = spot.id;
            ELSE
                -- Spot cannot be deleted, return error
                RETURN JSONB_BUILD_OBJECT(
                    'code', 4031,
                    'message', 'Cannot delete spot due to invalid state',
                    'spot_id', spot.id,
                    'details', JSONB_BUILD_OBJECT(
                        'secret', spot.secret,
                        'secret_expiration_time', spot.secret_expiration_time,
                        'order_product_ticket', spot.order_product_ticket
                    )
                );
            END IF;
        END IF;
    END LOOP;

    -- Update blueprint's objects field
    UPDATE eshop.blueprints
    SET
        updated_at = now,
        data = input_data->'data',
        title = input_data->>'title',
        configuration = input_data->'configuration',
        groups = input_data->'groups',
        objects = updated_objects,
        background_svg = (input_data->>'background_svg')::TEXT,
        occasion = occasion_id,
        organization = organization_id
    WHERE id = blueprint_id;

    -- Return success response
    RETURN JSONB_BUILD_OBJECT(
        'code', 200,
        'message', 'Blueprint updated successfully',
        'blueprint_id', blueprint_id,
        'updated_objects', updated_objects
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM);
END;
$$;
