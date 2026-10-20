CREATE OR REPLACE FUNCTION public.get_all_email_templates(p_context jsonb)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  email_data jsonb;
  v_occ bigint;
  v_unit bigint;
  v_org bigint;
  v_effective_org bigint;
  is_app_supported boolean := false;
BEGIN
  v_occ := CASE
    WHEN p_context ? 'occasion' AND (p_context->>'occasion') IS NOT NULL
      THEN (p_context->>'occasion')::bigint
    ELSE NULL
  END;
  v_unit := CASE
    WHEN p_context ? 'unit' AND (p_context->>'unit') IS NOT NULL
      THEN (p_context->>'unit')::bigint
    ELSE NULL
  END;
  v_org := CASE
    WHEN p_context ? 'organization' AND (p_context->>'organization') IS NOT NULL
      THEN (p_context->>'organization')::bigint
    ELSE NULL
  END;

  IF v_org IS NOT NULL THEN
    v_effective_org := v_org;
  ELSIF v_occ IS NOT NULL THEN
    SELECT organization INTO v_effective_org
    FROM public.occasions WHERE id = v_occ;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_effective_org
    FROM public.units WHERE id = v_unit;
  END IF;

  IF v_effective_org IS NOT NULL THEN
    SELECT COALESCE((data->>'IS_APP_SUPPORTED')::boolean, false)
    INTO is_app_supported
    FROM public.organizations
    WHERE id = v_effective_org;
  END IF;

  IF v_occ IS NOT NULL THEN
    IF (SELECT public.get_is_editor_view_on_occasion(v_occ)) <> true
      AND (SELECT public.get_is_editor_order_view_on_occasion(v_occ)) <> true THEN
      RAISE EXCEPTION 'User is not editor view.';
    END IF;
  END IF;

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
    WHERE (
      (v_occ IS NOT NULL AND et.occasion = v_occ)
      OR (v_unit IS NOT NULL AND et.unit = v_unit AND et.occasion IS NULL)
      OR (v_org IS NOT NULL AND et.organization = v_org
        AND et.unit IS NULL AND et.occasion IS NULL)
      OR (et.organization IS NULL AND et.unit IS NULL AND et.occasion IS NULL)
    )
    AND (is_app_supported IS true
      OR et.code NOT IN ('SIGN_IN_CODE', 'RESET_PASSWORD'))
    ORDER BY et.code,
      CASE
        WHEN (v_occ IS NOT NULL AND et.occasion = v_occ) THEN 1
        WHEN (v_unit IS NOT NULL AND et.unit = v_unit AND et.occasion IS NULL) THEN 2
        WHEN (v_org IS NOT NULL AND et.organization = v_org
          AND et.unit IS NULL AND et.occasion IS NULL) THEN 3
        WHEN (et.organization IS NULL AND et.unit IS NULL
          AND et.occasion IS NULL) THEN 4
        ELSE 5
      END,
      et.id
  ) result;

  RETURN COALESCE(email_data, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.get_all_email_templates(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_all_email_templates(jsonb)
TO authenticated, service_role;
