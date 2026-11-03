CREATE OR REPLACE FUNCTION public.get_all_user_basics_for_scan(scan_code text)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  oid bigint;
  org_id bigint;
  user_basics jsonb;
BEGIN
  -----------------------------------------------------
  -- 1. Validate Code & Get Occasion AND Organization ID
  -----------------------------------------------------
  SELECT o.id, o.organization INTO oid, org_id
  FROM public.occasions o
  JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
  WHERE oh.secret = scan_code
  LIMIT 1;

  -- Security Check: If ID is null, the code is invalid
  IF oid IS NULL THEN
      RAISE EXCEPTION 'Invalid scan code';
  END IF;

  -----------------------------------------------------
  -- 2. Retrieve User Data for this Occasion
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
  LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oid
  JOIN public.occasion_users uo ON ui.id = uo."user"

  -- This keeps the user in the list even if they have no record in organization_users
  LEFT JOIN public.organization_users ou ON ui.id = ou."user" AND ou.organization = org_id

  WHERE uo.occasion = oid

  -- "IS NOT TRUE" covers two cases:
  -- 1. is_hidden is FALSE
  -- 2. is_hidden is NULL (record doesn't exist)
  AND (ou.is_hidden IS NOT TRUE);

  -----------------------------------------------------
  -- 3. Handle Empty Results & Return
  -----------------------------------------------------
  IF user_basics IS NULL THEN
    user_basics := '[]'::jsonb;
  END IF;

  RETURN user_basics;
END;
$$ LANGUAGE plpgsql;
