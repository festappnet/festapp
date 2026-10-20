CREATE OR REPLACE FUNCTION get_all_users_from_unit(unit_id bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  user_basics jsonb;
  org_id bigint;
BEGIN
  -- Step 1: Get the Organization ID for this Unit
  -- This also serves as a check to see if the unit exists
  SELECT organization INTO org_id
  FROM public.units
  WHERE id = unit_id;

  -- If org_id is null, the unit likely doesn't exist
  -- (Assuming all units belong to an organization)
  IF org_id IS NULL THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Unit not found');
  END IF;

  -- Step 2: Permission Check
  IF NOT EXISTS (
      SELECT 1 FROM public.unit_users
      WHERE "user" = auth.uid()
        AND unit = unit_id
        AND (is_manager = true OR is_editor = true OR is_editor_view = true)
  ) THEN
    RETURN jsonb_build_object('code', 403);
  END IF;

  -- Step 3: Retrieve Users with Hidden Filter
  SELECT jsonb_agg(user_info)
  INTO user_basics
  FROM (
    SELECT jsonb_build_object(
      'user', ui.id,
      'name', ui.name,
      'surname', ui.surname,
      'sex', ui.sex,
      'email_readonly', ui.email_readonly,
      'unit', uu.unit,
      'is_manager', uu.is_manager,
      'is_editor', uu.is_editor,
      'is_editor_view', uu.is_editor_view,
      'data', uu.data
    ) AS user_info
    FROM public.unit_users uu
    JOIN public.user_info ui ON uu."user" = ui.id

    -- Left Join to check organization-wide visibility settings
    LEFT JOIN public.organization_users ou ON ui.id = ou."user" AND ou.organization = org_id

    WHERE uu.unit = unit_id

    -- Filter out hidden users
    -- (ou.is_hidden IS NOT TRUE) includes FALSE (visible) and NULL (no record found, so visible)
    AND (ou.is_hidden IS NOT TRUE)

    ORDER BY uu.created_at DESC
  ) t;

  -- Step 4: Handle Empty Results
  IF user_basics IS NULL THEN
    user_basics := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object('code', 200, 'data', user_basics);
END;
$$ LANGUAGE plpgsql;