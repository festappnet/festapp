CREATE OR REPLACE FUNCTION get_current_quote(unit_id bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_rec RECORD;
    unit_features jsonb;
    quotes_feature jsonb;
    feature_idx int;
    feature jsonb;
    feature_found BOOLEAN := FALSE;
    curr_quote_id bigint;
    curr_quote_date text;  -- stored as 'YYYY-MM-DD'
    curr_quote_rec RECORD;
    next_quote_rec RECORD;
    updated_features jsonb;
    v_current_date text := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD');
BEGIN
    -- Lock the unit row to prevent concurrent updates
    SELECT *
    INTO unit_rec
    FROM public.units
    WHERE id = unit_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Unit not found');
    END IF;

    unit_features := unit_rec.features;
    IF unit_features IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No features configured for this unit');
    END IF;

    -- Find the enabled "quotes" feature in the JSON array
    FOR feature_idx IN 0 .. jsonb_array_length(unit_features) - 1 LOOP
        feature := unit_features -> feature_idx;
        IF (feature ->> 'code') = 'quotes'
           AND (feature ->> 'is_enabled') = 'true' THEN
            quotes_feature := feature;
            feature_found := TRUE;
            EXIT;
        END IF;
    END LOOP;

    IF NOT feature_found THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Quotes feature is not enabled for this unit');
    END IF;

    -- Retrieve stored quote_id and quote_date from the feature
    curr_quote_id := NULL;
    IF quotes_feature ? 'quote_id' THEN
        curr_quote_id := (quotes_feature ->> 'quote_id')::bigint;
    END IF;

    curr_quote_date := NULL;
    IF quotes_feature ? 'quote_date' THEN
        curr_quote_date := quotes_feature ->> 'quote_date';
    END IF;

    -- If a stored quote exists and its date equals today's UTC date, try to fetch it
    IF curr_quote_id IS NOT NULL AND curr_quote_date = v_current_date THEN
        SELECT *
        INTO curr_quote_rec
        FROM public.information
        WHERE id = curr_quote_id
          AND type = 'quote'
          AND occasion IS NULL
          AND unit = unit_id
          AND is_hidden = false
        LIMIT 1;

        IF FOUND THEN
            RETURN jsonb_build_object('code', 200, 'data', row_to_json(curr_quote_rec));
        END IF;
    END IF;

    -- No valid quote for today; select a new random quote.
    SELECT *
    INTO next_quote_rec
    FROM public.information
    WHERE type = 'quote'
      AND occasion IS NULL
      AND unit = unit_id
      AND is_hidden = false
    ORDER BY random()
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No quotes found for this unit');
    END IF;

    -- Update the feature with the new quote id and today's UTC date
    updated_features := unit_features;
    FOR feature_idx IN 0 .. jsonb_array_length(unit_features) - 1 LOOP
        feature := unit_features -> feature_idx;
        IF (feature ->> 'code') = 'quotes'
           AND (feature ->> 'is_enabled') = 'true' THEN
            updated_features := jsonb_set(
                updated_features,
                ARRAY[feature_idx::text],
                (feature || jsonb_build_object(
                    'quote_id', next_quote_rec.id,
                    'quote_date', v_current_date
                ))
            );
            EXIT;
        END IF;
    END LOOP;

    UPDATE public.units
    SET features = updated_features
    WHERE id = unit_id;

    RETURN jsonb_build_object('code', 200, 'data', row_to_json(next_quote_rec));
END;
$$ LANGUAGE plpgsql;
