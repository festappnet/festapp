CREATE OR REPLACE FUNCTION synchronize_my_schedule(
    p_event_ids BIGINT[],
    p_join_mode BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    event_id BIGINT;
BEGIN
    IF NOT p_join_mode THEN
        -- If not joining, clear all existing saved events for the user
        DELETE FROM public.event_users_saved eus
        WHERE eus."user" = v_user_id;
    END IF;

    -- Insert or Upsert the provided event IDs
    -- Only proceed if p_event_ids is not null and not empty
    IF p_event_ids IS NOT NULL AND array_length(p_event_ids, 1) > 0 THEN
        IF p_join_mode THEN
            -- Join mode: Insert new events, ignore conflicts (effectively an upsert for existence)
            FOREACH event_id IN ARRAY p_event_ids
            LOOP
                INSERT INTO public.event_users_saved (event, "user")
                VALUES (event_id, v_user_id)
                ON CONFLICT (event, "user") DO NOTHING;
            END LOOP;
        ELSE
            -- Not join mode (records for the user were already deleted): Insert all provided event_ids
            INSERT INTO public.event_users_saved (event, "user")
            SELECT unnest_val, v_user_id
            FROM unnest(p_event_ids) AS unnest_val;
        END IF;
    END IF;
END;
$$;