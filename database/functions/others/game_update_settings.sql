CREATE OR REPLACE FUNCTION public.game_update_settings_internal_v1(oc bigint, new_start_time timestamp with time zone, new_end_time timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  existing_data JSONB;
  updated_game_data JSONB;
BEGIN
  -- Check if the user is an editor on the occasion
  IF (SELECT get_is_editor_on_occasion(oc)) <> TRUE THEN
    RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
  END IF;

  -- Retrieve existing data JSON if any
  SELECT data INTO existing_data FROM public.occasions WHERE id = oc;

  -- Create or update the "game" object with new start and end times, preserving other keys in "game"
  updated_game_data := COALESCE(existing_data->'game', '{}'::jsonb) || jsonb_build_object(
    'start', CASE WHEN new_start_time IS NOT NULL THEN to_jsonb(new_start_time) ELSE 'null'::jsonb END,
    'end', CASE WHEN new_end_time IS NOT NULL THEN to_jsonb(new_end_time) ELSE 'null'::jsonb END
  );

  -- Update the data JSON with the updated "game" data
  UPDATE public.occasions
  SET data = jsonb_set(
      COALESCE(data, '{}'::jsonb),                          -- Ensure data is an empty JSON if NULL
      ARRAY['game'],                                        -- Path to the "game" key
      updated_game_data,                                    -- Updated game data with merged start and end times
      true
    )
  WHERE id = oc;

  -- Return success response
  RETURN jsonb_build_object(
    'code', 200,
    'message', 'Game settings updated successfully'
  );
END;
$function$
;
REVOKE ALL ON FUNCTION public.game_update_settings_internal_v1(bigint,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.game_update_settings(oc bigint, new_start_time timestamp with time zone, new_end_time timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
BEGIN RETURN public.game_update_settings_client_sync_v1(
  oc,new_start_time,new_end_time,extensions.gen_random_uuid())->'data'; END; $function$
;
REVOKE ALL ON FUNCTION public.game_update_settings(bigint,timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.game_update_settings(bigint,timestamptz,timestamptz) TO authenticated;
