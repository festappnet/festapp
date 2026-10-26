CREATE OR REPLACE FUNCTION game_get_correctly_guessed_checkpoints(oc BIGINT)
RETURNS JSONB
SET search_path = public, extensions AS $$
DECLARE
    user_group_data JSONB;
BEGIN
    -- Retrieve the `data` field for the user's first group where `type = 'game'` and matches the given occasion
    SELECT data
    INTO user_group_data
    FROM user_group_info ug
    JOIN user_groups ug_rel ON ug.id = ug_rel.group
    WHERE ug_rel.user = auth.uid()
      AND ug.type = 'game'
      AND ug.occasion = oc
    LIMIT 1;

    -- Extract each checkpoint as a JSON object with key "check_point" from the "game" array
    RETURN jsonb_build_object(
        'code', 200,
        'data', COALESCE(
            (SELECT jsonb_agg(jsonb_build_object('check_point', (game_entry->>'check_point')::INT))
             FROM jsonb_array_elements(user_group_data->'game') AS game_entry),
            '[]'::JSONB
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;