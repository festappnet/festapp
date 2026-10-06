-- Extend the existing organization app-support filter for editor template listings.
CREATE OR REPLACE FUNCTION public.get_all_email_templates(p_context jsonb)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  email_data jsonb;
  v_occ  bigint;
  v_unit bigint;
  v_org  bigint;

  v_effective_org bigint;
  is_app_supported boolean := false;
BEGIN
  -- 1. Extract context values from the JSON parameter
  v_occ  := CASE
              WHEN p_context ? 'occasion' AND (p_context->>'occasion') IS NOT NULL
              THEN (p_context->>'occasion')::bigint
              ELSE NULL
            END;
  v_unit := CASE
              WHEN p_context ? 'unit' AND (p_context->>'unit') IS NOT NULL
              THEN (p_context->>'unit')::bigint
              ELSE NULL
            END;
  v_org  := CASE
              WHEN p_context ? 'organization' AND (p_context->>'organization') IS NOT NULL
              THEN (p_context->>'organization')::bigint
              ELSE NULL
            END;

  -- 2. Determine the effective Organization ID to check settings
  -- Priority: Explicit Org -> Org from Occasion -> Org from Unit
  IF v_org IS NOT NULL THEN
    v_effective_org := v_org;
  ELSIF v_occ IS NOT NULL THEN
    SELECT organization INTO v_effective_org FROM public.occasions WHERE id = v_occ;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_effective_org FROM public.units WHERE id = v_unit;
  END IF;

  -- 3. Check if App is Supported for the effective organization
  IF v_effective_org IS NOT NULL THEN
    SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
    INTO is_app_supported
    FROM public.organizations
    WHERE id = v_effective_org;
  END IF;

  -- 4. If an occasion is provided, perform the permission check.
  IF v_occ IS NOT NULL THEN
    IF (SELECT get_is_editor_view_on_occasion(v_occ)) <> TRUE AND (SELECT get_is_editor_order_view_on_occasion(v_occ)) <> TRUE THEN
       RAISE EXCEPTION 'User is not editor view.';
    END IF;
  END IF;

  -- 5. Retrieve email templates
  SELECT jsonb_agg(result)
    INTO email_data
  FROM (
    SELECT DISTINCT ON (et.code)
           et.id,
           et.html,
           et.occasion,
           et.subject,
           et.organization,
           et.code,
           et.unit,
           et.title
    FROM public.email_templates et
    WHERE
      -- A. Filter based on context (Scope)
      (
           (v_occ IS NOT NULL AND et.occasion = v_occ)
        OR (v_unit IS NOT NULL AND et.unit = v_unit AND et.occasion IS NULL)
        OR (v_org IS NOT NULL  AND et.organization = v_org AND et.unit IS NULL AND et.occasion IS NULL)
        OR (et.organization IS NULL AND et.unit IS NULL AND et.occasion IS NULL)
      )
      -- B. Filter based on App Support (New Logic)
      AND (
        is_app_supported IS TRUE
        OR
        et.code NOT IN ('SIGN_IN_CODE', 'RESET_PASSWORD', 'APP_LINKS',
                        'ACCOUNT_DELETION_CONFIRM', 'ACCOUNT_DELETION_COMPLETE')
      )
    ORDER BY et.code,
             CASE
               WHEN (v_occ IS NOT NULL AND et.occasion = v_occ) THEN 1
               WHEN (v_unit IS NOT NULL AND et.unit = v_unit AND et.occasion IS NULL) THEN 2
               WHEN (v_org IS NOT NULL  AND et.organization = v_org AND et.unit IS NULL AND et.occasion IS NULL) THEN 3
               WHEN (et.organization IS NULL AND et.unit IS NULL AND et.occasion IS NULL) THEN 4
               ELSE 5
             END,
             et.id
  ) result;

  IF email_data IS NULL THEN
    email_data := '[]'::jsonb;
  END IF;

  RETURN email_data;
END;
$$;
