-- Canonical source: database/functions/others/get_operator_access_v1.sql
BEGIN;
-- A minimal delegated-access projection, using the same live rights as the UI.
-- Neither caller-supplied actor IDs nor static MCP allowlists grant authority.
CREATE OR REPLACE FUNCTION public.get_operator_access_v1(
  p_organization bigint, p_unit bigint DEFAULT NULL, p_occasion bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.user_info
      WHERE id=auth.uid() AND organization=p_organization) THEN
    RAISE insufficient_privilege USING MESSAGE='operator context unavailable';
  END IF;
  RETURN jsonb_build_object(
    'units', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',u.id,'title',u.title,'canCreateOccasions',
        public.get_is_manager_on_unit(u.id)) ORDER BY u.id)
      FROM public.units u WHERE u.organization=p_organization
        AND (p_unit IS NULL OR u.id=p_unit)
        AND (public.get_is_editor_on_unit(u.id) OR public.get_is_manager_on_unit(u.id)
          OR public.get_is_editor_view_on_unit(u.id))), '[]'::jsonb),
    'occasions', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',o.id,'title',o.title,'unitId',o.unit) ORDER BY o.id)
      FROM public.occasions o WHERE o.organization=p_organization
        AND (p_unit IS NULL OR o.unit=p_unit)
        AND (p_occasion IS NULL OR o.id=p_occasion)
        AND (public.can_edit_ticket_layout(o.id) OR public.get_is_manager_on_occasion(o.id)
          OR public.get_is_editor_on_occasion(o.id) OR public.get_is_editor_view_on_occasion(o.id)
          OR public.get_is_editor_order_view_on_occasion(o.id)
          OR public.get_is_manager_on_unit(o.unit) OR public.get_is_editor_view_on_unit(o.unit))), '[]'::jsonb));
END $$;

GRANT EXECUTE ON FUNCTION public.get_operator_access_v1(bigint,bigint,bigint) TO authenticated;

COMMIT;
