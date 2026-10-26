CREATE OR REPLACE FUNCTION public.import_users_from_tickets_ws_internal_v1(p_occasion_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    -- Declare a variable to hold the JSONB result from the import function.
    import_results JSONB;
BEGIN
    -- Verify if the user is an editor on the occasion.
    -- If this check fails, it will raise an exception.
    IF (SELECT get_is_editor_on_occasion(p_occasion_id)) <> TRUE THEN
        RAISE EXCEPTION 'User is not an editor for this occasion.';
    END IF;

    -- Call the original function to import users and store the returned JSONB
    -- in our variable instead of discarding it with PERFORM.
    import_results := public.import_ticket_profiles_internal_v1(p_occasion_id);

    -- Return a new JSONB object that includes the standard success code/message
    -- as well as the 'data' key containing the actual import results.
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Import completed successfully.',
        'data', import_results
    );
END;
$function$
;
REVOKE ALL ON FUNCTION public.import_users_from_tickets_ws_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.import_users_from_tickets_ws(p_occasion_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN RETURN public.import_users_from_tickets_client_sync_v1(p_occasion_id,extensions.gen_random_uuid()); END $$;
REVOKE ALL ON FUNCTION public.import_users_from_tickets_ws(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_users_from_tickets_ws(bigint) TO authenticated;
