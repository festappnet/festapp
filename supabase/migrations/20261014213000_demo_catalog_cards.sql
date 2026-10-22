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
    'referenceAt',d.reference_at,'image',o.data->>'image',
    'start_time',o.start_time,'end_time',o.end_time,
    'data',jsonb_build_object('timezone',o.data->>'timezone'),
    'features',(SELECT jsonb_agg(jsonb_build_object(
      'code',feature->>'code','is_enabled',(feature->>'is_enabled')::boolean))
      FROM jsonb_array_elements(o.features) feature),
    'stats',(SELECT jsonb_build_object(
      'total',count(*),'storno',count(*) FILTER(WHERE state='storno'),
      'paid_or_sent',count(*) FILTER(WHERE state IN ('paid','sent')),
      'ordered',count(*) FILTER(WHERE state='ordered'),
      'used',count(*) FILTER(WHERE state='used'),
      'users',(SELECT count(*) FROM public.occasion_users ou
        LEFT JOIN public.organization_users org_u
          ON org_u."user"=ou."user" AND org_u.organization=p_organization
        WHERE ou.occasion=o.id AND org_u.is_hidden IS NOT TRUE))
      FROM eshop.tickets t WHERE t.occasion=o.id)) ORDER BY d.sort_order)
   FROM public.demo_occasions d JOIN public.occasions o ON o.id=d.occasion
   WHERE d.organization=p_organization AND d.is_listed),'[]'::jsonb));
END $$;
