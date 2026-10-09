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
  v_actual_unit bigint;
  v_actual_org bigint;
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

  -- Resolve ancestors from the requested object; never trust mixed tenant IDs.
  IF v_occ IS NOT NULL THEN
    SELECT unit, organization INTO v_actual_unit, v_actual_org
    FROM public.occasions WHERE id = v_occ;
    IF NOT FOUND OR (v_unit IS NOT NULL AND v_unit IS DISTINCT FROM v_actual_unit)
        OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Invalid email template hierarchy';
    END IF;
    IF NOT public.is_service_role()
       AND public.get_is_editor_view_on_occasion(v_occ) IS NOT TRUE
       AND public.get_is_editor_order_view_on_occasion(v_occ) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Occasion template access denied';
    END IF;
    v_unit := v_actual_unit;
    v_org := v_actual_org;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_actual_org FROM public.units WHERE id = v_unit;
    IF NOT FOUND OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Invalid email template hierarchy';
    END IF;
    IF NOT public.is_service_role()
       AND public.get_is_manager_on_unit(v_unit) IS NOT TRUE
       AND public.get_is_editor_on_unit(v_unit) IS NOT TRUE
       AND public.get_is_editor_view_on_unit(v_unit) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Unit template access denied';
    END IF;
    v_org := v_actual_org;
  ELSIF NOT public.is_service_role() THEN
    IF v_org IS NULL OR public.get_is_admin_on_organization(v_org) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Organization template access denied';
    END IF;
  END IF;
  v_effective_org := v_org;

  -- 3. Check if App is Supported for the effective organization
  IF v_effective_org IS NOT NULL THEN
    SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
    INTO is_app_supported
    FROM public.organizations
    WHERE id = v_effective_org;
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

REVOKE ALL ON FUNCTION public.get_all_email_templates(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_all_email_templates(jsonb) TO authenticated, service_role;
