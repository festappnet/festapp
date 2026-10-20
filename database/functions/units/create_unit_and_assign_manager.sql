CREATE OR REPLACE FUNCTION public.create_unit_and_assign_manager(
  title text
) RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid;
  v_org_id bigint;
  v_email text;
  v_new_unit_id bigint;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Unauthorized');
  END IF;

  SELECT organization, email_readonly 
  INTO v_org_id, v_email
  FROM public.user_info 
  WHERE id = v_user_id;

  IF v_org_id IS NULL THEN
     RETURN jsonb_build_object('code', 404, 'message', 'User info or organization not found');
  END IF;

  -- Check if unit creation is enabled for organization
  DECLARE
      v_is_enabled boolean;
  BEGIN
      SELECT (data->>'IS_UNIT_CREATION_ENABLED')::boolean 
      INTO v_is_enabled
      FROM public.organizations 
      WHERE id = v_org_id;
      
      IF v_is_enabled IS NOT TRUE THEN
          RETURN jsonb_build_object('code', 403, 'message', 'Unit creation is disabled for this organization');
      END IF;
  END;

  PERFORM public.admit_unit_creation_v1(v_user_id,v_org_id);

  INSERT INTO public.units (title, organization, data)
  VALUES (
    title, 
    v_org_id,
    jsonb_build_object(
        'reply_to', lower(trim(COALESCE(v_email, ''))),
        'timezone', 'Europe/Prague'
    )
  )
  RETURNING id INTO v_new_unit_id;

  INSERT INTO public.unit_users (unit, "user", is_manager, is_editor, is_editor_view)
  VALUES (v_new_unit_id, v_user_id, true, true, true);

  RETURN jsonb_build_object(
    'code', 200, 
    'message', 'Unit created successfully', 
    'data', jsonb_build_object('id', v_new_unit_id)
  );

EXCEPTION WHEN SQLSTATE 'PT429' THEN
  RETURN jsonb_build_object('code',429,'message','Capacity is temporarily limited. Try again later.');
WHEN OTHERS THEN
  RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION public.create_unit_and_assign_manager(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_unit_and_assign_manager(text) TO authenticated;
