CREATE OR REPLACE FUNCTION public.get_user_info_for_users(user_ids uuid[], oc bigint)
RETURNS jsonb
SECURITY definer
SET search_path = public, extensions
AS $$
DECLARE
  companions jsonb;
BEGIN
  -- Check if the user is a manager, editor, or approver for the occasion
  IF (SELECT get_is_manager_on_occasion(oc) OR get_is_editor_on_occasion(oc) OR get_is_approver_on_occasion(oc)) <> TRUE THEN
      RETURN jsonb_build_object('code', 403);
  END IF;

  -- Aggregate the user information as JSON
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ui.id,
      'created_at', ui.created_at,
      'updated_at', ui.updated_at,
      'email_readonly', ui.email_readonly,
      'name', ui.name,
      'surname', ui.surname,
      'sex', ui.sex,
      'phone', ui.phone,
      'data', ui.data,
      'birth_date', ui.birth_date,
      'companion_parent', (
        SELECT jsonb_build_object(
          'id', parent_ui.id,
          'created_at', parent_ui.created_at,
          'updated_at', parent_ui.updated_at,
          'email_readonly', parent_ui.email_readonly,
          'name', parent_ui.name,
          'surname', parent_ui.surname,
          'sex', parent_ui.sex,
          'phone', parent_ui.phone,
          'data', parent_ui.data,
          'birth_date', parent_ui.birth_date
        )
        FROM public.user_info parent_ui
        WHERE parent_ui.id = uc."user"
      )
    )
  ) INTO companions
  FROM public.user_info ui
  LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oc
  WHERE ui.id = ANY(user_ids);

  -- If no companions are found, return an empty array
  IF companions IS NULL THEN
    companions := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'code', 200,
    'data', companions
  );
END;
$$ LANGUAGE plpgsql;
