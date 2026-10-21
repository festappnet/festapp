-- Groups may link to visible places from the occasion catalog. Such a link must
-- not grant the group admin permission to move that shared map point. Only the
-- hidden `group` point created specifically for a group remains movable by its
-- admin; occasion editors retain their existing permission for every place.
CREATE OR REPLACE FUNCTION public.save_place_location(
  p_place_id bigint,
  p_lat double precision,
  p_lng double precision
) RETURNS jsonb
  LANGUAGE plpgsql
  VOLATILE
  SECURITY DEFINER
  SET search_path = public, extensions
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_occasion bigint;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required to move a place');
  END IF;

  SELECT occasion INTO v_occasion FROM public.places WHERE id = p_place_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Place not found');
  END IF;

  IF NOT (
    get_is_editor_on_occasion(v_occasion)
    OR EXISTS (
      SELECT 1
      FROM public.user_groups ug
      JOIN public.user_group_info ugi ON ugi.id = ug."group"
      JOIN public.places p ON p.id = ugi.place
      WHERE ug."user" = v_user
        AND ug.is_admin
        AND ugi.place = p_place_id
        AND p.type = 'group'
        AND p.is_hidden
    )
  ) THEN
    RETURN jsonb_build_object('code', 403, 'message', 'You cannot change this place');
  END IF;

  UPDATE public.places
  SET coordinates = jsonb_build_object(
        'latLng', jsonb_build_object('lat', p_lat, 'lng', p_lng))
  WHERE id = p_place_id;

  RETURN jsonb_build_object(
    'code', 200,
    'data', jsonb_build_object('id', p_place_id)
  );
END;
$$;

-- Return the visible place catalog with the group editor data so the UI can
-- offer existing places without a second request.
CREATE OR REPLACE FUNCTION public.get_all_user_groups(
  p_occasion_id bigint,
  p_type text DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, extensions
AS $$
DECLARE
  groups_json jsonb;
  game_defs_json jsonb;
  places_json jsonb;
BEGIN
  IF NOT get_is_editor_view_on_occasion(p_occasion_id) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', ugi.id,
      'title', ugi.title,
      'description', ugi.description,
      'type', ugi.type,
      'data', ugi.data,
      'place', ugi.place,
      'places', (
        SELECT row_to_json(p)::jsonb
        FROM public.places p
        WHERE p.id = ugi.place
      ),
      'user_groups', (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'is_admin', ug.is_admin,
            'user_info', jsonb_build_object(
              'id', p_ui.id,
              'name', p_ui.name,
              'surname', p_ui.surname
            )
          )
        ), '[]'::jsonb)
        FROM public.user_groups ug
        JOIN public.user_info p_ui ON ug."user" = p_ui.id
        WHERE ug."group" = ugi.id
      )
    )
  ), '[]'::jsonb)
  INTO groups_json
  FROM public.user_group_info ugi
  WHERE ugi.occasion = p_occasion_id
    AND (p_type IS NULL AND ugi.type IS NULL OR ugi.type = p_type);

  IF p_type = 'game' THEN
    SELECT jsonb_object_agg(info.id, info.title)
    INTO game_defs_json
    FROM public.information info
    WHERE info.type = 'game' AND info.occasion = p_occasion_id;
  END IF;

  SELECT COALESCE(
    jsonb_agg(to_jsonb(p) ORDER BY p."order" NULLS LAST, p.title),
    '[]'::jsonb
  )
  INTO places_json
  FROM public.places p
  WHERE p.occasion = p_occasion_id
    AND NOT p.is_hidden
    AND p.coordinates->'latLng'->>'lat' IS NOT NULL
    AND p.coordinates->'latLng'->>'lng' IS NOT NULL;

  RETURN jsonb_build_object(
    'groups', groups_json,
    'game_definitions', game_defs_json,
    'places', places_json
  );
END;
$$;
