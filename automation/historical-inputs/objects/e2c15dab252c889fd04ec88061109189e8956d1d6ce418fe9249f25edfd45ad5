CREATE OR REPLACE FUNCTION get_my_events_and_activities(
    p_occasion            BIGINT,
    p_include_description BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    current_user_id        UUID := auth.uid();
    event_ids_to_use       BIGINT[];
    eventsData             JSONB;
    eventUsersData         JSONB;
    eventUsersSavedData    JSONB;
    placesData             JSONB;
    eventGroupsData        JSONB;
    activitiesData         JSONB;
    assignmentsData        JSONB;
    assignmentEventsData   JSONB;
    assignmentPlacesData   JSONB;
BEGIN
    -- Select IDs of all events relevant to the user first
    SELECT array_agg(e.id)
    INTO event_ids_to_use
    FROM public.events e
    WHERE e.occasion   = p_occasion
      AND e.is_hidden  = FALSE
      AND (
        EXISTS (
          SELECT 1
          FROM public.event_users eu
          WHERE eu.event = e.id
            AND eu."user" = current_user_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.event_users_saved eus
          WHERE eus.event = e.id
            AND eus."user" = current_user_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.activity_assignment_events aae
          JOIN public.activity_assignments aa
            ON aa.id = aae.assignment_id
          JOIN public.activities a
            ON a.id = aa.activity_id
          WHERE aae.event_id = e.id
            AND aa."user"    = current_user_id
            AND a.occasion   = p_occasion
        )
        OR EXISTS (
          SELECT 1
            FROM public.activity_assignments aa
            JOIN public.activity_assignment_places aap ON aa.id = aap.assignment_id
            JOIN public.activities a ON a.id = aa.activity_id
           WHERE aa."user" = current_user_id
             AND a.occasion = p_occasion
             AND aap.place_id = e.place
             AND ( (aa.start_time <= e.start_time AND e.start_time < aa.end_time) OR (e.start_time <= aa.start_time AND aa.start_time < e.end_time) )
        )
      );

    -- (a) Events related to the current user, using the pre-selected IDs
    SELECT jsonb_agg(jsonb_build_object(
        'id',                   e.id,
        'created_at',           e.created_at,
        'title',                e.title,
        'start_time',           e.start_time,
        'end_time',             e.end_time,
        'max_participants',     e.max_participants,
        'type',                 e.type,
        'data',                 e.data,
        'description',          CASE WHEN p_include_description THEN e.description ELSE NULL END,
        'place',                e.place,
        'split_for_men_women',  e.split_for_men_women,
        'is_group_event',       e.is_group_event,
        'updated_at',           e.updated_at,
        'is_hidden',            e.is_hidden,
        'occasion',             e.occasion,
        'isSignedIn',           (current_user_id IS NOT NULL
                                   AND EXISTS (
                                     SELECT 1
                                       FROM public.event_users eu
                                      WHERE eu.event = e.id
                                        AND eu."user" = current_user_id
                                   )
                                ),
        'isEventInMyProgram',   (current_user_id IS NOT NULL
                                   AND EXISTS (
                                     SELECT 1
                                       FROM public.event_users_saved eus
                                      WHERE eus.event = e.id
                                        AND eus."user" = current_user_id
                                   )
                                )
    ))
    INTO eventsData
    FROM public.events e
    WHERE e.id = ANY(COALESCE(event_ids_to_use, '{}'));

    -- (b) Counts of users signed in for these events
    WITH user_counts AS (
      SELECT eu.event AS event, COUNT(*) AS cnt
      FROM public.event_users eu
      JOIN public.events e ON eu.event = e.id
      WHERE e.occasion   = p_occasion
        AND e.is_hidden = FALSE
      GROUP BY eu.event
    )
    SELECT jsonb_agg(jsonb_build_object('event', uc.event, 'count', uc.cnt))
      INTO eventUsersData
    FROM user_counts uc;

    -- (c) Counts of users who saved these events
    WITH saved_counts AS (
      SELECT eus.event AS event, COUNT(*) AS cnt
      FROM public.event_users_saved eus
      JOIN public.events e ON eus.event = e.id
      WHERE e.occasion   = p_occasion
        AND e.is_hidden = FALSE
      GROUP BY eus.event
    )
    SELECT jsonb_agg(jsonb_build_object('event', sc.event, 'count', sc.cnt))
      INTO eventUsersSavedData
    FROM saved_counts sc;

    -- (d) Places: from events and from activity assignments
    WITH place_ids AS (
      SELECT e.place AS place_id
      FROM public.events e
      WHERE e.id = ANY(COALESCE(event_ids_to_use, '{}')) AND e.place IS NOT NULL
      UNION
      SELECT ap.place_id
      FROM public.activity_assignment_places ap
      JOIN public.activity_assignments aa ON aa.id = ap.assignment_id
      JOIN public.activities a            ON a.id = aa.activity_id
      WHERE aa."user"  = current_user_id
        AND a.occasion = p_occasion
    )
    SELECT jsonb_agg(jsonb_build_object(
        'id',           p.id,
        'title',        p.title,
        'description',  p.description,
        'type',         p.type,
        'created_at',   p.created_at,
        'coordinates',  p.coordinates,
        'is_hidden',    p.is_hidden,
        'updated_at',   p.updated_at,
        'occasion',     p.occasion
    ))
    INTO placesData
    FROM public.places p
    WHERE p.id IN (SELECT place_id FROM place_ids);

    -- (NEW SECTION i for event_groups) Event groups where either parent or child is a user-related, non-hidden event for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'event_parent', eg.event_parent,
        'event_child',  eg.event_child
    ))
    INTO eventGroupsData
    FROM public.event_groups eg
    JOIN public.events e1 ON eg.event_parent = e1.id
    JOIN public.events e2 ON eg.event_child  = e2.id
    WHERE e1.occasion   = p_occasion
      AND e1.is_hidden  = FALSE
      AND e2.occasion   = p_occasion
      AND e2.is_hidden  = FALSE
      AND (e1.id = ANY(COALESCE(event_ids_to_use, '{}')) OR e2.id = ANY(COALESCE(event_ids_to_use, '{}')));

    -- (e) Activities the user is assigned to
    SELECT jsonb_agg(jsonb_build_object(
        'id',           a.id,
        'created_at',   a.created_at,
        'title',        a.title,
        'description',  CASE WHEN p_include_description THEN a.description ELSE NULL END,
        'data',         a.data,
        'type',         a.type,
        'occasion',     a.occasion,
        'unit',         a.unit,
        'is_hidden',    a.is_hidden,
        'order',        a."order",
        'updated_at',   a.updated_at
    ))
    INTO activitiesData
    FROM public.activities a
    JOIN public.activity_assignments aa ON aa.activity_id = a.id
    WHERE aa."user"    = current_user_id
      AND a.occasion   = p_occasion
      AND a.is_hidden  = FALSE;

    -- (f) User's activity assignments
    SELECT jsonb_agg(jsonb_build_object(
        'id',           aa.id,
        'activity_id',  aa.activity_id,
        'start_time',   aa.start_time,
        'end_time',     aa.end_time,
        'title',        aa.title,
        'description',  CASE WHEN p_include_description THEN aa.description ELSE NULL END,
        'data',         aa.data
    ))
    INTO assignmentsData
    FROM public.activity_assignments aa
    JOIN public.activities a ON a.id = aa.activity_id
    WHERE aa."user"    = current_user_id
      AND a.occasion   = p_occasion;

    -- (g) Assignment ↔ Event links
    SELECT jsonb_agg(jsonb_build_object(
        'assignment_id', aae.assignment_id,
        'event_id',      aae.event_id
    ))
    INTO assignmentEventsData
    FROM public.activity_assignment_events aae
    JOIN public.activity_assignments aa ON aa.id = aae.assignment_id
    JOIN public.activities a            ON a.id = aa.activity_id
    WHERE aa."user"  = current_user_id
      AND a.occasion = p_occasion;

    -- (h) Assignment ↔ Place links
    SELECT jsonb_agg(jsonb_build_object(
        'assignment_id', ap.assignment_id,
        'place_id',      ap.place_id
    ))
    INTO assignmentPlacesData
    FROM public.activity_assignment_places ap
    JOIN public.activity_assignments aa ON aa.id = ap.assignment_id
    JOIN public.activities a            ON a.id = aa.activity_id
    WHERE aa."user"  = current_user_id
      AND a.occasion = p_occasion;

    -- Final assembly
    RETURN jsonb_build_object(
      'code', 200,
      'data', jsonb_build_object(
        'events',               COALESCE(eventsData,           '[]'::jsonb),
        'event_users',          COALESCE(eventUsersData,       '[]'::jsonb),
        'event_users_saved',    COALESCE(eventUsersSavedData,  '[]'::jsonb),
        'places',               COALESCE(placesData,           '[]'::jsonb),
        'event_groups',         COALESCE(eventGroupsData,      '[]'::jsonb),
        'activities',           COALESCE(activitiesData,       '[]'::jsonb),
        'activity_assignments', COALESCE(assignmentsData,      '[]'::jsonb),
        'assignment_events',    COALESCE(assignmentEventsData, '[]'::jsonb),
        'assignment_places',    COALESCE(assignmentPlacesData, '[]'::jsonb)
      )
    );
END;
$$;
