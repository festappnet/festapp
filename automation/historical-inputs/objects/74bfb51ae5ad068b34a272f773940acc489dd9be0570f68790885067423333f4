CREATE OR REPLACE FUNCTION get_events(
    p_occasion            BIGINT,
    p_include_description BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    current_user_id        UUID;
    eventsData             JSONB;
    placesData             JSONB;
    eventGroupsData        JSONB;
    eventRolesData         JSONB;
    eventUsersData         JSONB;
    eventUsersSavedData    JSONB;
BEGIN
    -- grab current_user_id user after entering PL/pgSQL execution
    current_user_id := auth.uid();

    -- (a) all non-hidden events, with per-user flags and conditional fields
    SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id',                   e.id,
        'title',                e.title,
        'start_time',           e.start_time,
        'end_time',             e.end_time,
        'max_participants',     e.max_participants,
        'updated_at',           e.updated_at,
        'description',          CASE WHEN p_include_description THEN e.description ELSE NULL END,
        'type',                 e.type,
        'data',                 (SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb)
                                   FROM jsonb_each(e.data)
                                  WHERE value <> 'false'::jsonb),
        'place',                e.place,
        'split_for_men_women',  NULLIF(e.split_for_men_women, FALSE),
        'is_group_event',       NULLIF(e.is_group_event, FALSE),
        'isSignedIn',           NULLIF((current_user_id IS NOT NULL
                                   AND EXISTS (
                                     SELECT 1
                                       FROM public.event_users eu
                                      WHERE eu.event = e.id
                                        AND eu."user" = current_user_id
                                   )
                                ), FALSE),
        'isEventInMyProgram',   NULLIF((current_user_id IS NOT NULL
                                   AND EXISTS (
                                     SELECT 1
                                       FROM public.event_users_saved eus
                                      WHERE eus.event = e.id
                                        AND eus."user" = current_user_id
                                   )
                                ), FALSE)
    )))
    INTO eventsData
    FROM public.events e
    WHERE e.occasion   = p_occasion
      AND e.is_hidden = FALSE;

    -- (b) places for this occasion (unchanged)
    SELECT jsonb_agg(jsonb_build_object(
        'id',           p.id,
        'order',        p."order",
        'title',        p.title
    ))
    INTO placesData
    FROM public.places p
    WHERE p.occasion = p_occasion;

    -- (c) event_groups only for non-hidden events (unchanged)
    SELECT jsonb_agg(jsonb_build_object(
        'event_parent', eg.event_parent,
        'event_child',  eg.event_child
    ))
    INTO eventGroupsData
    FROM public.event_groups eg
    JOIN public.events e1 ON eg.event_parent = e1.id
    JOIN public.events e2 ON eg.event_child  = e2.id
    WHERE e1.occasion   = p_occasion AND e1.is_hidden = FALSE
      AND e2.occasion   = p_occasion AND e2.is_hidden = FALSE;

    -- (d) event_roles only on non-hidden events (unchanged)
    SELECT jsonb_agg(jsonb_build_object(
        'event', er.event,
        'role',  er.role
    ))
    INTO eventRolesData
    FROM public.event_roles er
    JOIN public.events e ON er.event = e.id
    WHERE e.occasion   = p_occasion
      AND e.is_hidden = FALSE;

    -- (e) signed-in counts for non-hidden events (unchanged)
    WITH user_counts AS (
      SELECT eu.event AS event, COUNT(*) AS cnt
      FROM public.event_users eu
      JOIN public.events e ON eu.event = e.id
      WHERE e.occasion   = p_occasion
        AND e.is_hidden = FALSE
      GROUP BY eu.event
    )
    SELECT jsonb_agg(jsonb_build_object(
      'event', uc.event,
      'count', uc.cnt
    ))
    INTO eventUsersData
    FROM user_counts uc;

    -- (f) saved-for-later counts for non-hidden events (unchanged)
    WITH saved_counts AS (
      SELECT eus.event AS event, COUNT(*) AS cnt
      FROM public.event_users_saved eus
      JOIN public.events e ON eus.event = e.id
      WHERE e.occasion   = p_occasion
        AND e.is_hidden = FALSE
      GROUP BY eus.event
    )
    SELECT jsonb_agg(jsonb_build_object(
      'event', sc.event,
      'count', sc.cnt
    ))
    INTO eventUsersSavedData
    FROM saved_counts sc;

    -- (g) final assembly (unchanged)
    RETURN jsonb_build_object(
      'code', 200,
      'data', jsonb_build_object(
        'events',            COALESCE(eventsData,          '[]'::jsonb),
        'places',            COALESCE(placesData,          '[]'::jsonb),
        'event_groups',      COALESCE(eventGroupsData,     '[]'::jsonb),
        'event_roles',       COALESCE(eventRolesData,      '[]'::jsonb),
        'event_users',       COALESCE(eventUsersData,      '[]'::jsonb),
        'event_users_saved', COALESCE(eventUsersSavedData, '[]'::jsonb)
      )
    );
END;
$$;
