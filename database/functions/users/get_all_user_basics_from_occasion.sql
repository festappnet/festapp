CREATE OR REPLACE FUNCTION public.get_all_user_basics_from_occasion(oc bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  org_id bigint;
  user_basics jsonb;
BEGIN
  -----------------------------------------------------
  -- 1. Permission Check
  -----------------------------------------------------
  -- Check if the user is a manager, editor, or approver for the occasion
  IF (SELECT get_is_manager_on_occasion(oc) OR get_is_editor_on_occasion(oc) OR get_is_approver_on_occasion(oc)) <> TRUE THEN
      RETURN jsonb_build_object('code', 403);
  END IF;

  -----------------------------------------------------
  -- 2. Get Organization ID
  -----------------------------------------------------
  -- We need the org_id to check the specific organization_users table
  SELECT organization INTO org_id
  FROM public.occasions
  WHERE id = oc;

  -----------------------------------------------------
  -- 3. Aggregate User Data
  -----------------------------------------------------
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ui.id,
      'name', ui.name,
      'surname', ui.surname,
      'sex', ui.sex,
      'email_readonly', ui.email_readonly,
      'companion_parent', (
        SELECT jsonb_build_object(
          'id', parent_ui.id,
          'name', parent_ui.name,
          'surname', parent_ui.surname,
          'sex', parent_ui.sex,
          'email_readonly', parent_ui.email_readonly
        )
        FROM public.user_info parent_ui
        WHERE parent_ui.id = uc."user"
      )
    )
  ) INTO user_basics
  FROM public.user_info ui
  LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oc
  JOIN public.occasion_users uo ON ui.id = uo."user"

  -- LEFT JOIN to check visibility settings
  LEFT JOIN public.organization_users ou ON ui.id = ou."user" AND ou.organization = org_id

  WHERE uo.occasion = oc

  -- FILTER: Exclude only if explicitly hidden
  -- (NULL or FALSE means visible)
  AND (ou.is_hidden IS NOT TRUE);

  -----------------------------------------------------
  -- 4. Handle Empty Results & Return
  -----------------------------------------------------
  -- If no users are found, return an empty array
  IF user_basics IS NULL THEN
    user_basics := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'code', 200,
    'data', user_basics
  );
END;
$$ LANGUAGE plpgsql;
