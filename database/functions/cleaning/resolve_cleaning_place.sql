CREATE OR REPLACE FUNCTION public.resolve_cleaning_place_internal_v1(place_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_occasion bigint;
  v_count integer;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required');
  END IF;

  SELECT occasion INTO v_occasion FROM public.places WHERE id = place_id;
  IF v_occasion IS NULL THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Toilet not found');
  END IF;

  IF NOT public.get_is_cleaning_crew_on_occasion(v_occasion) THEN
    RETURN jsonb_build_object('code', 403, 'message', 'Cleaning crew access required');
  END IF;

  WITH updated AS (
    UPDATE public.cleaning_reports
    SET resolved_by = v_user,
        resolved_at = now()
    WHERE place = place_id
      AND resolved_at IS NULL
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM updated;

  RETURN jsonb_build_object(
    'code', 200,
    'data', jsonb_build_object('resolved', v_count)
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.resolve_cleaning_place_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.resolve_cleaning_place(place_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.resolve_cleaning_place_client_sync_v1(place_id,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code','message',result#>'{data,message}','data',result->'data');
END $$;
REVOKE ALL ON FUNCTION public.resolve_cleaning_place(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.resolve_cleaning_place(bigint) TO authenticated;
