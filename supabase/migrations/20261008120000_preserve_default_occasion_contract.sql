-- The landing occasion belongs to the organization, not to each unit.
CREATE OR REPLACE FUNCTION public.get_unit_app_landing(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_org bigint;
  v_data jsonb;
  v_occasion bigint;
  v_title text;
  v_admin boolean;
BEGIN
  SELECT organization INTO v_org FROM public.units WHERE id = p_unit;
  v_admin := public.get_is_admin_on_organization(v_org);
  IF v_org IS NULL OR NOT (v_admin OR public.get_is_editor_view_on_unit(p_unit)
      OR public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE = 'Access denied';
  END IF;
  SELECT data INTO v_data FROM public.organizations WHERE id = v_org;
  v_occasion := (v_data->>'DEFAULT_OCCASION')::bigint;
  SELECT title INTO v_title FROM public.occasions
    WHERE id = v_occasion AND organization = v_org;
  RETURN jsonb_build_object('enabled', coalesce((v_data->>'IS_APP_SUPPORTED')::boolean, false),
    'occasion_id', v_occasion, 'occasion_title', v_title, 'can_manage', v_admin);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_unit_app_landing(
  p_unit bigint, p_occasion bigint, p_expected_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_org bigint;
  v_data jsonb;
  v_current bigint;
BEGIN
  SELECT organization INTO v_org FROM public.units WHERE id = p_unit;
  IF v_org IS NULL OR NOT public.get_is_admin_on_organization(v_org) THEN
    RAISE insufficient_privilege USING MESSAGE = 'Access denied';
  END IF;
  SELECT data INTO v_data FROM public.organizations WHERE id = v_org FOR UPDATE;
  IF NOT coalesce((v_data->>'IS_APP_SUPPORTED')::boolean, false) THEN
    RAISE invalid_parameter_value USING MESSAGE = 'Application is not enabled';
  END IF;
  v_current := (v_data->>'DEFAULT_OCCASION')::bigint;
  IF v_current IS DISTINCT FROM p_expected_occasion THEN
    RAISE serialization_failure USING MESSAGE = 'App landing changed. Refresh and try again.';
  END IF;
  IF p_occasion IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.occasions WHERE id = p_occasion
      AND unit = p_unit AND organization = v_org AND is_open = true
  ) THEN
    RAISE invalid_parameter_value USING MESSAGE = 'Choose an open occasion in this unit';
  END IF;
  -- The representative occasion is a separate application setting; preserve it.
  UPDATE public.organizations
    SET data = (coalesce(data, '{}'::jsonb) - 'DEFAULT_OCCASION')
      || CASE WHEN p_occasion IS NULL THEN '{}'::jsonb
         ELSE jsonb_build_object('DEFAULT_OCCASION', p_occasion) END
    WHERE id = v_org;
  RETURN public.get_unit_app_landing(p_unit);
END;
$$;
REVOKE ALL ON FUNCTION public.get_unit_app_landing(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_unit_app_landing(bigint, bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_unit_app_landing(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_unit_app_landing(bigint, bigint, bigint) TO authenticated;
