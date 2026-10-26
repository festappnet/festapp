CREATE OR REPLACE FUNCTION create_user_in_organization_with_data_ws(org bigint, email text, password text, data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Internal helper. The scoped parent (update_user_internal_v1) owns admission.
    -- No client EXECUTE: public registration has its own atomic email owner.
    -- Call the PURE function
    new_user_id := create_user_in_organization_with_data_pure(org, email, password, data);

    -- Return success in JSON format
    RETURN jsonb_build_object('code', 200, 'id', new_user_id);
END;
$$;
REVOKE ALL ON FUNCTION public.create_user_in_organization_with_data_ws(bigint,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
