DROP FUNCTION IF EXISTS get_all_user_basics_from_occasion_unit;

CREATE OR REPLACE FUNCTION public.get_all_user_basics_from_occasion_unit(p_unit_id bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  user_basics jsonb;
  org_id bigint;
BEGIN
  -- Step 1: Retrieve the organization for the given unit
  SELECT organization INTO org_id
  FROM public.units
  WHERE id = p_unit_id;

  -- If the unit does not exist, return a 404 error
  IF org_id IS NULL THEN
    RAISE EXCEPTION 'Unit not found' USING ERRCODE = 'P0002'; -- no_data_found
  END IF;

  -- Step 2: Check if the caller is a manager of the unit
  IF (SELECT get_is_manager_on_unit(p_unit_id)) <> TRUE THEN
    RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  -- Step 3: Aggregate user information and roles for sorting
  WITH relevant_occasions AS (
    -- Occasions under the same unit
    SELECT id AS occasion_id FROM public.occasions WHERE unit = p_unit_id
    UNION
    -- Occasions where the current user has privileged rights
    SELECT occasion AS occasion_id
    FROM public.occasion_users
    WHERE "user" = auth.uid()
      AND (is_manager = true OR is_editor = true OR is_approver = true)
  ),
  raw_user_roles AS (
    -- Roles from occasion_users in relevant occasions
    SELECT
      uo."user",
      uo.is_manager,
      uo.is_editor,
      uo.is_editor_order,
      uo.is_editor_view,
      uo.is_editor_order_view,
      uo.is_approver
    FROM public.occasion_users uo
    WHERE uo.occasion IN (SELECT occasion_id FROM relevant_occasions)

    UNION ALL

    -- Roles from unit_users (mapping available columns)
    SELECT
      uu."user",
      uu.is_manager,
      uu.is_editor,
      false AS is_editor_order,       -- Not in unit_users
      uu.is_editor_view,
      false AS is_editor_order_view,  -- Not in unit_users
      false AS is_approver            -- Not in unit_users
    FROM public.unit_users uu
    WHERE uu.unit = p_unit_id
  ),
  aggregated_user_roles AS (
    -- Consolidate roles per user (taking true if any occurrence is true)
    SELECT
      "user",
      bool_or(is_manager) AS is_manager,
      bool_or(is_editor) AS is_editor,
      bool_or(is_editor_order) AS is_editor_order,
      bool_or(is_editor_view) AS is_editor_view,
      bool_or(is_editor_order_view) AS is_editor_order_view,
      bool_or(is_approver) AS is_approver
    FROM raw_user_roles
    GROUP BY "user"
  )
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
    ) ORDER BY
      aur.is_manager DESC,
      aur.is_editor DESC,
      aur.is_editor_order DESC,
      aur.is_editor_view DESC,
      aur.is_editor_order_view DESC,
      aur.is_approver DESC,
      ui.surname ASC NULLS LAST,
      ui.name ASC NULLS LAST
  ) INTO user_basics
  FROM public.user_info ui
  JOIN aggregated_user_roles aur ON ui.id = aur."user"
  LEFT JOIN public.user_companions uc ON ui.id = uc.companion
    AND uc.occasion IN (SELECT id FROM public.occasions WHERE unit=p_unit_id)
  LEFT JOIN public.organization_users ou ON ui.id = ou."user" AND ou.organization = org_id
  WHERE (ou.is_hidden IS NOT TRUE);

  -- Step 4: Handle cases with no users found
  IF user_basics IS NULL THEN
    user_basics := '[]'::jsonb;
  END IF;

  -- Step 5: Return the aggregated JSON response
  RETURN user_basics;
END;
$$ LANGUAGE plpgsql;
