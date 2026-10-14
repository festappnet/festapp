CREATE OR REPLACE FUNCTION public.get_demo_occasions(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info
   WHERE id=auth.uid() AND organization=p_organization) THEN
  RAISE insufficient_privilege USING MESSAGE='demo tenant access denied';
 END IF;
 RETURN jsonb_build_object(
  'hasOwnWork', EXISTS(SELECT 1 FROM public.occasions o
    WHERE o.organization=p_organization AND NOT public.is_demo_occasion(o.id)
     AND (public.get_is_manager_on_unit(o.unit) OR public.get_is_editor_on_unit(o.unit)
      OR public.get_is_manager_on_occasion(o.id) OR public.get_is_editor_on_occasion(o.id)))
   OR EXISTS(SELECT 1 FROM public.occasion_setup_drafts d WHERE d.organization=p_organization
    AND (public.get_is_manager_on_unit(d.unit) OR public.get_is_editor_on_unit(d.unit))),
  'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id',o.id,'link',o.link,'title',o.title,'demoKey',d.demo_key,
    'fixtureVersion',d.fixture_version,'description',d.description,
    'referenceAt',d.reference_at,'image',o.data->>'image') ORDER BY d.sort_order)
   FROM public.demo_occasions d JOIN public.occasions o ON o.id=d.occasion
   WHERE d.organization=p_organization AND d.is_listed),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_demo_occasions(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_demo_occasions(bigint) TO authenticated;
