-- Canonical merges can contain the same legacy occasion link in more than one
-- organization. Resolve the edit reader inside the authenticated user's tenant
-- before checking occasion-level permissions.
CREATE OR REPLACE FUNCTION public.get_occasion_for_edit_v1(p_link text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_occasion bigint;
  v_result jsonb;
BEGIN
  SELECT o.id
  INTO v_occasion
  FROM public.occasions o
  WHERE o.link = p_link
    AND o.organization = (
      SELECT ui.organization
      FROM public.user_info ui
      WHERE ui.id = auth.uid()
    );

  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE = 'occasion not found';
  END IF;

  IF NOT (
    public.get_is_editor_view_on_occasion(v_occasion)
    OR public.get_is_manager_on_occasion(v_occasion)
    OR public.get_is_admin_on_occasion(v_occasion)
  ) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor view required';
  END IF;

  SELECT to_jsonb(o) || jsonb_build_object(
    'aggregate_version', COALESCE(v.version, 0)
  )
  INTO v_result
  FROM public.occasions o
  LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type = 'occasion'
    AND v.scope_type = 'occasion'
    AND v.scope_id = o.id
    AND v.aggregate_id = o.id::text
  WHERE o.id = v_occasion;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_occasion_for_edit_v1(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_for_edit_v1(text) TO authenticated;
