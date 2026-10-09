create or replace function public.sign_user_to_event (ev bigint, usr uuid) returns jsonb
 language plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 as $$
declare
  i_max_participants integer;
  current_participants integer;
  event_group_count integer;
  event_group integer;
  exclusive_event_count integer;
  already_in_count integer;
  current_men_participants integer;
  current_women_participants integer;
  b_split_for_men_women boolean;
  is_current_user_male boolean;

  registration_start timestamp;
  event_start_time timestamp;
  event_end_time timestamp;
  workshops_feature jsonb;
  e RECORD;

  v_occasion bigint;
  v_is_counseling boolean;
  counseling_feature jsonb;
  v_limit integer;
  v_active integer;

begin
  -- Authorize before any membership or attendance mutation.
  IF auth.uid() IS NULL OR usr IS NULL THEN
    RETURN jsonb_build_object('code', 403);
  END IF;
  IF auth.uid() IS DISTINCT FROM usr THEN
      IF NOT EXISTS (
        SELECT 1 FROM user_companions uc
        JOIN events ce ON ce.id=ev AND ce.occasion=uc.occasion
        WHERE uc."user" = auth.uid() AND uc.companion = usr
          AND (public.get_companion_feature_policy_v1(uc.occasion)->>'is_enabled')::boolean) THEN
          IF (SELECT get_is_editor_on_occasion((SELECT occasion FROM events WHERE id = ev))) IS NOT TRUE THEN
            RETURN json_build_object('code', 403);
          END IF;
      END IF;
  END IF;

  -- Check if the user already exists on the occasion
  IF (SELECT get_exists_on_occasion_user(usr, (SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN

      -- Check if the occasion is open
      IF (SELECT is_open FROM occasions WHERE id = (SELECT occasion FROM events WHERE id = ev)) = TRUE THEN

          -- Add the user to the occasion
          PERFORM public.add_user_to_occasion_internal_v1(
            (SELECT occasion FROM events WHERE id = ev), usr);

          -- Recheck if the user now exists on the occasion
          IF (SELECT get_exists_on_occasion_user(usr, (SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN
              -- If user still doesn't exist, return a 403 response
              RETURN json_build_object('code', 403, 'message', 'Failed to add user to occasion');
          END IF;
      ELSE
          -- If the occasion is not open, return a 403 response
          RETURN json_build_object('code', 403, 'message', 'Occasion is not open');
      END IF;
  END IF;


  -- Resolve the occasion and detect whether this event is a counseling slot.
  SELECT occasion, (data->>'is_counseling_slot')::boolean IS TRUE
    INTO v_occasion, v_is_counseling
  FROM events
  WHERE id = ev;

  IF v_is_counseling THEN
    -- Counseling slots use their own registration window from the "counseling"
    -- feature; the workshops gate (104/108) does not apply (decision R1).
    SELECT elem
      INTO counseling_feature
    FROM occasions,
         jsonb_array_elements(features) elem
    WHERE id = v_occasion
      AND elem->>'code' = 'counseling'
    LIMIT 1;

    -- (a) Feature must be present and enabled, else registration is closed.
    IF counseling_feature IS NULL
       OR (counseling_feature->>'is_enabled')::boolean IS NOT TRUE THEN
      RETURN json_build_object('code', 108);
    END IF;

    registration_start := (counseling_feature->>'registration_start_time')::timestamp;
    IF registration_start IS NOT NULL THEN
      IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' < registration_start THEN
        RETURN json_build_object('code', 104, 'events_registration_start', registration_start AT TIME ZONE 'UTC');
      END IF;
    END IF;

    -- (b) Limit of the user's future counseling bookings (0 = unlimited).
    v_limit := COALESCE((counseling_feature->>'max_active_bookings')::int, 1);
    IF v_limit > 0 THEN
      SELECT count(*)
        INTO v_active
      FROM event_users eu
      JOIN events e2 ON e2.id = eu.event
      WHERE eu."user" = usr
        AND e2.occasion = v_occasion
        AND (e2.data->>'is_counseling_slot')::boolean IS TRUE
        AND e2.end_time > CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
      IF v_active >= v_limit THEN
        RETURN json_build_object('code', 109);
      END IF;
    END IF;
  ELSE
    -- Check registration start time from occasions.features for the "workshops" feature
    SELECT elem
    INTO workshops_feature
    FROM occasions,
         jsonb_array_elements(features) elem
    WHERE id = (SELECT occasion FROM events WHERE id = ev)
      AND elem->>'code' = 'workshops'
    LIMIT 1;

    IF workshops_feature IS NOT NULL THEN
      -- If the workshops feature is not enabled, do not allow sign in
      IF (workshops_feature->>'is_enabled')::boolean IS NOT TRUE THEN
        RETURN json_build_object('code', 108, 'message', 'Registration for workshops is not enabled');
      END IF;
      -- If start_time is provided, enforce registration start time
      registration_start := (workshops_feature->>'start_time')::timestamp;
      IF registration_start IS NOT NULL THEN
        IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' < registration_start THEN
          RETURN json_build_object('code', 104, 'events_registration_start', registration_start AT TIME ZONE 'UTC');
        END IF;
      END IF;
    END IF;
    -- If the workshops feature is not present or its start_time is null, sign in is enabled
  END IF;

  SELECT start_time, end_time INTO event_start_time, event_end_time
  FROM events
  WHERE id = ev;

  IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' > event_end_time THEN
    RETURN json_build_object('code', 100);
  END IF;

  SELECT count(*) FROM event_users eu WHERE eu.event = ev AND eu."user" = usr INTO already_in_count;
  IF already_in_count > 0 THEN
    RETURN json_build_object('code', 103);
  END IF;

  SELECT count(*) FROM exclusive_events WHERE event = ev INTO event_group_count;
  IF event_group_count > 0 THEN
    SELECT "group" FROM exclusive_events WHERE event = ev INTO event_group;
    SELECT count(*) FROM exclusive_events ee JOIN event_users eu ON ee.event = eu.event
      WHERE ee."group" = event_group AND eu."user" = usr INTO exclusive_event_count;
    IF exclusive_event_count > 0 THEN
      RETURN json_build_object('code', 102);
    END IF;
  END IF;

  -- Check if the event already has the maximum number of participants
  SELECT max_participants FROM events WHERE id = ev INTO i_max_participants;
  SELECT split_for_men_women FROM events WHERE id = ev INTO b_split_for_men_women;

  IF b_split_for_men_women THEN
    SELECT exists (SELECT sex FROM user_info WHERE id = usr AND sex = 'male') INTO is_current_user_male;
    SELECT count(*) FROM event_users eu JOIN user_info ei ON eu."user" = ei.id
      WHERE event = ev AND ei.sex = 'male' INTO current_men_participants;
    SELECT count(*) FROM event_users eu JOIN user_info ei ON eu."user" = ei.id
      WHERE event = ev AND ei.sex <> 'male' INTO current_women_participants;
    IF is_current_user_male AND current_men_participants >= (i_max_participants / 2) THEN
      RETURN json_build_object('code', 105);
    ELSIF NOT is_current_user_male AND current_women_participants >= (i_max_participants / 2) THEN
      RETURN json_build_object('code', 106);
    END IF;
  END IF;

  -- Loop through user_events to check for scheduling conflicts
  FOR e IN
      SELECT events.id, events.start_time, events.end_time
      FROM events
      JOIN event_users ON events.id = event_users.event
      WHERE event_users."user" = usr
  LOOP
      IF ((e.start_time < event_end_time AND e.start_time > event_start_time) OR
          (e.end_time < event_end_time AND e.end_time > event_start_time) OR
          (e.start_time = event_start_time) OR
          (e.end_time = event_end_time)) THEN
          RETURN json_build_object('code', 107);
      END IF;
  END LOOP;

  SELECT count(*) FROM event_users WHERE event = ev INTO current_participants;
  IF current_participants >= i_max_participants THEN
    RETURN json_build_object('code', 101);
  ELSE
    INSERT INTO event_users (event, "user") VALUES (ev, usr);
    RETURN json_build_object('code', 200);
  END IF;
END;
$$;

-- Error Codes:
-- 200: OK
-- 100: Event is over
-- 101: Event is full
-- 102: Exclusive event already taken
-- 103: Already signed in
-- 104: Registration not started yet (events_registration_start in response);
--      for counseling slots the window comes from the "counseling" feature
--      (registration_start_time) instead of the workshops feature.
-- 105: Maximum male participants reached
-- 106: Maximum female participants reached
-- 107: Conflicting event schedule
-- 108: Registration is not enabled — workshops feature disabled, or, for a
--      counseling slot, the "counseling" feature is missing or not enabled.
-- 109: Counseling booking limit reached (max_active_bookings of the "counseling"
--      feature; counts the user's future counseling reservations on the occasion).
