CREATE OR REPLACE FUNCTION public.game_guess_internal_v1(check_point_id BIGINT, guess TEXT)
RETURNS JSONB
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    hidden_value TEXT;
    correct_reference BIGINT;
    user_occasion BIGINT;
    user_in_group BOOLEAN;
    current_time TIMESTAMPTZ := NOW() AT TIME ZONE 'UTC';
    game_start TIMESTAMPTZ;
    game_end TIMESTAMPTZ;
    user_id UUID := auth.uid();  -- Retrieve the user ID from the authentication context
    existing_game_data JSONB;
BEGIN
    -- Step 1: Get the reference to `information_hidden` in `information` and check if it exists
    SELECT information_hidden::BIGINT INTO correct_reference
    FROM information
    WHERE id = check_point_id;

    IF correct_reference IS NULL THEN
        RETURN jsonb_build_object('code', 4041, 'message', 'Correct reference not found in information');
    END IF;

    -- Step 2: Retrieve the correct answer from `information_hidden.data` under the "correct" key and the occasion
    SELECT data->>'correct', occasion INTO hidden_value, user_occasion
    FROM information_hidden
    WHERE id = correct_reference;

    IF hidden_value IS NULL THEN
        RETURN jsonb_build_object('code', 4042, 'message', 'Hidden info not found or correct answer missing');
    END IF;

    -- Step 3: Retrieve game start and end times from the occasion data JSON, casting directly to TIMESTAMPTZ
    SELECT
        COALESCE((data->'game'->>'start')::TIMESTAMPTZ, NULL),
        COALESCE((data->'game'->>'end')::TIMESTAMPTZ, NULL)
    INTO game_start, game_end
    FROM occasions
    WHERE id = user_occasion;

    -- Step 4: Check if the current time is within the game time window
    IF game_start IS NOT NULL AND game_end IS NOT NULL THEN
        IF (CURRENT_DATE + current_time)::TIMESTAMPTZ < game_start OR (CURRENT_DATE + current_time)::TIMESTAMPTZ > game_end THEN
            RETURN jsonb_build_object('code', 4033, 'message', 'Guessing is only allowed within the game time window');
        END IF;
    END IF;

    -- Step 5: Check if the user is part of the occasion
    IF NOT EXISTS (
        SELECT 1
        FROM occasion_users
        WHERE "user" = user_id
          AND occasion = user_occasion
    ) THEN
        RETURN jsonb_build_object('code', 4031, 'message', 'User not in occasion');
    END IF;

    -- Step 6: Check if user is in a "game" type user group associated with the occasion
    user_in_group := EXISTS (
        SELECT 1
        FROM user_groups ug
        JOIN user_group_info ugi ON ug."group" = ugi.id
        WHERE ug."user" = user_id
          AND ugi.occasion = user_occasion
          AND ugi.type = 'game'
    );

    IF NOT user_in_group THEN
        RETURN jsonb_build_object('code', 4032, 'message', 'User not part of a game group');
    END IF;

    -- Step 7: Compare `guess` with `hidden_value` (ignoring diacritics, case, and trimming whitespace)
    IF unaccent(LOWER(TRIM(guess))) = unaccent(LOWER(TRIM(hidden_value))) THEN

        -- Step 8: Retrieve existing `game` array from `data` JSON and check if checkpoint already exists
        SELECT COALESCE(data->'game', '[]'::jsonb) INTO existing_game_data
        FROM user_group_info
        WHERE id = (
            SELECT "group"
            FROM user_groups
            WHERE "user" = user_id
              AND "group" IN (SELECT id FROM user_group_info WHERE occasion = user_occasion AND type = 'game')
            LIMIT 1
        );

        -- If `game` array does not exist, initialize it as an empty array
        IF existing_game_data IS NULL OR existing_game_data = 'null'::jsonb THEN
            existing_game_data := '[]'::jsonb;
        END IF;

        -- Append the new checkpoint if it does not already exist in the `game` array
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(existing_game_data) AS elem
            WHERE (elem->>'check_point')::INT = check_point_id
        ) THEN
            existing_game_data := existing_game_data || jsonb_build_array(
                jsonb_build_object('check_point', check_point_id, 'time', current_time)
            );

            -- Update the `data` JSON with the modified `game` array
            UPDATE user_group_info
            SET data = jsonb_set(COALESCE(data, '{}'::jsonb), '{game}', existing_game_data, true)
            WHERE id = (
                SELECT "group"
                FROM user_groups
                WHERE "user" = user_id
                  AND "group" IN (SELECT id FROM user_group_info WHERE occasion = user_occasion AND type = 'game')
                LIMIT 1
            );
        END IF;

        RETURN jsonb_build_object('code', 200, 'message', 'Correct answer');
    ELSE
        RETURN jsonb_build_object('code', 4001, 'message', 'Incorrect guess');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.game_guess(check_point_id bigint, guess text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.game_guess_internal_v1(check_point_id,guess);
$$;
