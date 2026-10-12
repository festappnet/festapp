CREATE OR REPLACE FUNCTION public.sign_user_out_of_event(ev BIGINT, usr UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    event_end_time TIMESTAMP;
BEGIN
  -- Authorize before any membership or attendance mutation.
  IF auth.uid() IS NULL OR usr IS NULL THEN
    RETURN jsonb_build_object('code', 403);
  END IF;
    IF auth.uid() IS DISTINCT FROM usr THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_companions uc
            JOIN events ce ON ce.id=ev AND ce.occasion=uc.occasion
            WHERE uc."user" = auth.uid() AND uc.companion = usr
              AND (public.get_companion_feature_policy_v1(uc.occasion)->>'is_enabled')::boolean ) THEN
            IF (SELECT get_is_editor_on_occasion((SELECT occasion FROM events WHERE id = ev))) IS NOT TRUE THEN
                    RETURN json_build_object('code', 403);
            END IF;
        END IF;
    END IF;
    -- Existing checks for occasion user and editor
    IF (SELECT get_exists_on_occasion_user(usr, (SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN
        RETURN json_build_object('code', 403);
    END IF;


    -- Check if the user is signed in to the event
    IF (SELECT COUNT(*) FROM event_users WHERE event = ev AND "user" = usr) = 0 THEN
        RETURN json_build_object('code', 404, 'message', 'User is not signed into this event');
    END IF;

    -- Retrieve event end time
    SELECT end_time INTO event_end_time
    FROM events
    WHERE id = ev;

    -- Check if the event has already ended
    IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' > event_end_time THEN
        RETURN json_build_object('code', 201, 'message', 'Cannot sign out after the event has ended');
    END IF;

    -- Remove the user from the event
    DELETE FROM event_users WHERE event = ev AND "user" = usr;
    RETURN json_build_object('code', 200, 'message', 'User signed out successfully');
END;
$$;
