-- Discovery remains broader than any one operation. Unit facts are evaluated
-- once per request, not once per occasion. Concrete capabilities use the same
-- SQL rule as the actual domain request; discovery never grants a write.
CREATE OR REPLACE FUNCTION public.get_operator_access_v1(
  p_organization bigint,p_unit bigint DEFAULT NULL,p_occasion bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info
    WHERE id=auth.uid() AND organization=p_organization) THEN
    RAISE insufficient_privilege USING MESSAGE='operator context unavailable';
  END IF;
  WITH unit_access AS MATERIALIZED (
    SELECT u.id,u.title,
      public.get_is_editor_on_unit(u.id) editor,
      public.get_is_manager_on_unit(u.id) manager,
      public.get_is_editor_view_on_unit(u.id) viewer
    FROM public.units u WHERE u.organization=p_organization
      AND (p_unit IS NULL OR u.id=p_unit)
  ), occasion_access AS MATERIALIZED (
    SELECT o.id,o.title,o.unit,
      public.ticket_layout_rule(true,u.editor) layout_reader
    FROM public.occasions o LEFT JOIN unit_access u ON u.id=o.unit
    WHERE o.organization=p_organization
      AND (p_unit IS NULL OR o.unit=p_unit)
      AND (p_occasion IS NULL OR o.id=p_occasion)
      AND public.operator_occasion_discovery_rule(u.editor,u.manager,u.viewer,
        public.get_is_manager_on_occasion(o.id),public.get_is_editor_on_occasion(o.id),
        public.get_is_editor_view_on_occasion(o.id),public.can_read_orders(o.id))
  ) SELECT jsonb_build_object(
    'units',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',u.id,'title',u.title,'canCreateOccasions',
      public.occasion_create_rule(u.manager,u.editor)) ORDER BY u.id)
      FROM unit_access u WHERE public.unit_discovery_rule(u.editor,u.manager,u.viewer)),'[]'::jsonb),
    'occasions',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',o.id,'title',o.title,'unitId',o.unit,
      'capabilities',jsonb_build_object('ticket_layouts.read',o.layout_reader)) ORDER BY o.id)
      FROM occasion_access o),'[]'::jsonb)) INTO v_result;
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.get_operator_access_v1(bigint,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_operator_access_v1(bigint,bigint,bigint) TO authenticated;
