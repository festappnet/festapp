CREATE OR REPLACE FUNCTION public.update_user_internal_v1(
  input_data jsonb
) RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user uuid;
  v_occasion bigint;
  v_unit_input bigint;
  v_is_manager boolean;
  v_is_editor boolean;
  v_data jsonb;
  v_email text;
  v_password text;
  v_org bigint;
  v_unit bigint;
  new_user uuid;
  existing_user_id uuid;
  v_global_before jsonb;
  v_create_response jsonb;
BEGIN
  -- Extract main fields from the input_data jsonb object
  v_user := (input_data->>'user')::uuid;
  v_occasion := (input_data->>'occasion')::bigint;
  v_unit_input := (input_data->>'unit')::bigint;
  v_is_manager := COALESCE((input_data->>'is_manager')::boolean, false);
  v_is_editor := COALESCE((input_data->>'is_editor')::boolean, false);

  -- Ensure 'data' field is a valid jsonb
  v_data := CASE
        WHEN input_data->>'data' IS NULL OR input_data->>'data' = ''
        THEN '{}'::jsonb
        ELSE input_data->'data'
       END;

  -- Determine the unit
  IF v_occasion IS NOT NULL THEN
    SELECT unit INTO v_unit FROM public.occasions WHERE id = v_occasion;
    IF v_unit IS NULL THEN
     RETURN jsonb_build_object('code', 404, 'message', 'Occasion not found');
    END IF;
  ELSIF v_unit_input IS NOT NULL THEN
    v_unit := v_unit_input;
    IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = v_unit) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Unit not found');
    END IF;
  ELSE
    RETURN jsonb_build_object('code', 400, 'message', 'Either an occasion or a unit must be provided');
  END IF;

  -- Get the organization
  SELECT organization INTO v_org FROM public.units WHERE id = v_unit;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Organization not found for the specified unit');
  END IF;

  -- Authorization check
  IF v_occasion IS NOT NULL THEN
    IF NOT EXISTS (
     SELECT 1 FROM public.occasion_users
     WHERE "user" = auth.uid()
      AND occasion = v_occasion
      AND is_manager = true
    ) THEN
     RETURN jsonb_build_object('code', 403, 'message', 'Unauthorized: Caller is not a manager for this occasion');
    END IF;
  ELSE
    IF NOT EXISTS (
        SELECT 1 FROM public.unit_users
        WHERE "user" = auth.uid()
        AND unit = v_unit
        AND is_manager = true
    ) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Unauthorized: Caller is not a manager for this unit');
    END IF;
  END IF;

  -- Logic for finding or creating user
  IF v_user IS NULL THEN
    v_email := input_data->'data'->>'email';

    IF v_email IS NULL OR v_email = '' THEN
      RETURN jsonb_build_object('code', 400, 'message', 'Email is required to find or create a user.');
    END IF;

    -- Check if user exists
    SELECT id INTO existing_user_id
    FROM auth.users
    WHERE email = v_org::text || '+' || v_email;

    IF existing_user_id IS NOT NULL THEN
      IF EXISTS(SELECT 1 FROM public.user_info WHERE id=existing_user_id AND organization IS DISTINCT FROM v_org) THEN
        RETURN jsonb_build_object('code',403,'message','User is outside the unit organization'); END IF;
      -- Create profile if missing
      IF NOT EXISTS (SELECT 1 FROM public.user_info WHERE id = existing_user_id) THEN
        INSERT INTO public.user_info (
          id, organization, email_readonly, data, name, surname, sex, phone,
          birth_date
        )
        VALUES (
            existing_user_id,
            v_org,
            v_email,
            v_data,
            v_data->>'name',
            v_data->>'surname',
            v_data->>'sex',
            v_data->>'phone',
            NULLIF(v_data->>'birthDate', '')::date
        );
      END IF;

      RETURN jsonb_build_object('code', 200, 'message', 'User found', 'user', existing_user_id::text);

    ELSE
      -- User does not exist, create new one
      v_password := encode(gen_random_bytes(16), 'hex');

      -- 1. Capture the JSONB response
      v_create_response := create_user_in_organization_with_data_ws(v_org, v_email, v_password, v_data);

      -- 2. Check if creation was successful (code 200)
      IF (v_create_response->>'code')::int != 200 THEN
          RETURN v_create_response; -- Return the error from the creation function
      END IF;

      -- 3. Extract the UUID string and cast it to UUID type
      new_user := (v_create_response->>'id')::uuid;

      RETURN jsonb_build_object(
       'code', 201,
       'message', 'User created successfully',
       'user', new_user::text
      );
    END IF;
  END IF;

  -- Global profile is the parent of its occasion projections.
  SELECT to_jsonb(ui) INTO v_global_before FROM public.user_info ui WHERE id=v_user AND organization=v_org FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',403,'message','User is outside the unit organization'); END IF;
  -- Update existing user logic
  UPDATE public.user_info
  SET
    data = COALESCE(user_info.data, '{}'::jsonb)
           || public.get_user_profile_data_patch(v_data),
    name = COALESCE(v_data->>'name', user_info.name),
    surname = COALESCE(v_data->>'surname', user_info.surname),
    sex = COALESCE(v_data->>'sex', user_info.sex),
    phone = CASE
      WHEN v_data ? 'phone' THEN v_data->>'phone'
      ELSE user_info.phone
    END,
    birth_date = CASE
      WHEN v_data ? 'birthDate'
        THEN NULLIF(v_data->>'birthDate', '')::date
      ELSE user_info.birth_date
    END
  WHERE id = v_user;

  PERFORM public.publish_user_profile_change_internal_v1(v_user,v_occasion,v_global_before);
  RETURN jsonb_build_object(
   'code', 200,
   'message', 'User details updated successfully',
   'user', v_user
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- Unit account management remains a distinct legacy scope; occasion creation uses its command.
CREATE OR REPLACE FUNCTION public.update_user(input_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF input_data->>'occasion' IS NOT NULL THEN RETURN jsonb_build_object('code',426,'message','Upgrade required: create_occasion_user_client_sync_v1'); END IF;
 RETURN public.update_user_internal_v1(input_data);
END $$;
REVOKE ALL ON FUNCTION public.update_user_internal_v1(jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.update_user(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_user(jsonb) TO authenticated;
-- No current caller of this obsolete occasion-profile overload remains.
REVOKE ALL ON FUNCTION public.update_user(uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
