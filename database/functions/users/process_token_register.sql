CREATE OR REPLACE FUNCTION public.process_token_register(data jsonb) RETURNS jsonb
SET search_path = public, extensions AS $$
DECLARE
    email_exists boolean;
    inserted_id uuid;
    token uuid;
    result jsonb;
BEGIN
    -- Legacy registration helper has no application caller; retained for trusted maintenance only.
    PERFORM public.require_service_role();

    -- Check if the data contains an email
    IF NOT (data ? 'email') THEN
        -- Construct the result JSONB object with code 400
        result := jsonb_build_object('code', 400, 'message', 'Email is required');
        RETURN result;
    END IF;

    -- Call the function to get the user_id by email
    email_exists := get_user_id_by_email(data ->> 'email') IS NOT NULL;

    -- If email exists, return error
    IF email_exists THEN
        -- Construct the result JSONB object with code 400
        result := jsonb_build_object('code', 400, 'message', 'Email already exists');
        RETURN result;
    END IF;

    -- Generate token
    token := gen_random_uuid();

    -- Insert data into the token_register_user table and capture the inserted ID
    INSERT INTO token_register_user (id, token, is_activated, data)
    VALUES (gen_random_uuid(), token, false, data)
    RETURNING id INTO inserted_id;

    -- Construct the result JSONB object with code 200, ID, and token
    result := jsonb_build_object('code', 200, 'id', inserted_id, 'token', token, 'message', 'Registration successful');
    RETURN result;
END;
$$ LANGUAGE plpgsql;


REVOKE ALL ON FUNCTION public.process_token_register(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_token_register(jsonb) TO service_role;
