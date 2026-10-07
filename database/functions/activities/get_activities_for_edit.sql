CREATE OR REPLACE FUNCTION public.get_activities_for_edit(
    p_occasion BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    eventsData              JSONB;
    placesData              JSONB;
    activitiesData          JSONB;
    assignmentPlaceLinksData JSONB;
    assignmentEventLinksData JSONB;
    aaData                  JSONB;
    usersData               JSONB;
BEGIN

   -- Authorization check
    IF (SELECT get_is_editor_view_on_occasion(p_occasion)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this occasion''s edit data');
    END IF;

    -- (a) all events
    SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'created_at', e.created_at, 'title', e.title, 'start_time', e.start_time,
        'end_time', e.end_time, 'max_participants', e.max_participants, 'description', e.description,
        'place', e.place, 'split_for_men_women', e.split_for_men_women, 'is_group_event', e.is_group_event,
        'updated_at', e.updated_at, 'is_hidden', e.is_hidden, 'occasion', e.occasion, 'type', e.type, 'data', e.data
    )) INTO eventsData
    FROM public.events e WHERE e.occasion = p_occasion;

    -- (b) all places for this occasion, sorted by places.order
    -- The jsonb_agg function will respect the order of the rows it aggregates.
    SELECT jsonb_agg(place_obj ORDER BY place_order ASC)
    INTO placesData
    FROM (
        SELECT jsonb_build_object(
            'id', p.id, 'title', p.title, 'description', p.description, 'type', p.type, 'created_at', p.created_at,
            'coordinates', p.coordinates, 'is_hidden', p.is_hidden, 'updated_at', p.updated_at, 'occasion', p.occasion,
            'order', p."order"
        ) AS place_obj,
        p."order" AS place_order
        FROM public.places p
        WHERE p.occasion = p_occasion
    ) AS ordered_places;


    -- (c) all activities
    SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'created_at', a.created_at, 'updated_at', a.updated_at, 'title', a.title,
        'description', a.description, 'type', a.type, 'occasion', a.occasion, 'unit', a.unit,
        'is_hidden', a.is_hidden, 'order', a."order", 'data', a.data
    )) INTO activitiesData
    FROM public.activities a WHERE a.occasion = p_occasion;

    -- (d) activity_assignment_places links (now assignment_id <-> place_id)
    SELECT jsonb_agg(jsonb_build_object(
        'assignment_id', apl.assignment_id,
        'place_id',      apl.place_id
    )) INTO assignmentPlaceLinksData
    FROM public.activity_assignment_places apl
    JOIN public.activity_assignments aa ON apl.assignment_id = aa.id
    JOIN public.activities a ON aa.activity_id = a.id
    WHERE a.occasion = p_occasion;

    -- (e) activity_assignment_events links (now assignment_id <-> event_id)
    SELECT jsonb_agg(jsonb_build_object(
        'assignment_id', ael.assignment_id,
        'event_id',      ael.event_id
    )) INTO assignmentEventLinksData
    FROM public.activity_assignment_events ael
    JOIN public.activity_assignments aa ON ael.assignment_id = aa.id
    JOIN public.activities a ON aa.activity_id = a.id
    WHERE a.occasion = p_occasion;

    -- (f) activity_assignments
    SELECT jsonb_agg(jsonb_build_object(
        'id', aa.id, 'activity_id', aa.activity_id, 'user', aa."user", 'start_time', aa.start_time,
        'end_time', aa.end_time, 'title', aa.title, 'description', aa.description, 'data', aa.data
    )) INTO aaData
    FROM public.activity_assignments aa
    JOIN public.activities a ON aa.activity_id = a.id
    WHERE a.occasion = p_occasion;

    -- (g) users for this occasion who are volunteers
    SELECT jsonb_agg(jsonb_build_object(
        'id', ui.id, 'name', ui.name, 'surname', ui.surname, 'sex', ui.sex, 'email', ui.email_readonly
    )) INTO usersData
    FROM public.user_info ui
    JOIN public.occasion_users ou ON ui.id = ou."user"
    WHERE ou.occasion = p_occasion AND (ou.data->>'is_volunteer')::boolean = TRUE;

    -- (h) assemble
    RETURN jsonb_build_object(
      'code', 200,
      'message', 'Data for editing activities retrieved successfully.',
      'data', jsonb_build_object(
        'events',                  COALESCE(eventsData, '[]'::jsonb),
        'places',                  COALESCE(placesData, '[]'::jsonb),
        'activities',              COALESCE(activitiesData, '[]'::jsonb),
        'assignment_place_links',  COALESCE(assignmentPlaceLinksData, '[]'::jsonb),
        'assignment_event_links',  COALESCE(assignmentEventLinksData, '[]'::jsonb),
        'activity_assignments',    COALESCE(aaData, '[]'::jsonb),
        'user_info',               COALESCE(usersData, '[]'::jsonb)
      )
    );
END;
$$;
