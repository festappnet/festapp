CREATE OR REPLACE FUNCTION public.get_map_editor_bundle_v1(p_occasion bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
  SELECT CASE WHEN public.can_read_map_editor_bundle(p_occasion) IS NOT TRUE
    THEN jsonb_build_object('code',403)
    ELSE jsonb_build_object(
      'code',200,
      'places',COALESCE((SELECT jsonb_agg(to_jsonb(p)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0)) ORDER BY p."order" NULLS LAST,p.id)
        FROM public.places p LEFT JOIN public.client_aggregate_versions v
          ON v.aggregate_type='place' AND v.scope_type='occasion'
          AND v.scope_id=p_occasion AND v.aggregate_id=p.id::text
        WHERE p.occasion=p_occasion),'[]'::jsonb),
      'placeTypes',COALESCE((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0)) ORDER BY t."order" NULLS LAST,t.id)
        FROM public.place_types t LEFT JOIN public.client_aggregate_versions v
          ON v.aggregate_type='place_type' AND v.scope_type='occasion'
          AND v.scope_id=p_occasion AND v.aggregate_id=t.id::text
        WHERE t.occasion=p_occasion),'[]'::jsonb),
      'paths',COALESCE((SELECT jsonb_agg(to_jsonb(pg)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0)) ORDER BY pg."order" NULLS LAST,pg.id)
        FROM public.path_groups pg LEFT JOIN public.client_aggregate_versions v
          ON v.aggregate_type='path' AND v.scope_type='occasion'
          AND v.scope_id=p_occasion AND v.aggregate_id=pg.id::text
        WHERE pg.occasion=p_occasion),'[]'::jsonb),
      'icons',COALESCE((SELECT jsonb_agg(to_jsonb(i)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0)) ORDER BY i.link,i.id)
        FROM public.occasions o JOIN public.icons i ON i.organization=o.organization
          AND (i.unit=o.unit OR i.unit IS NULL)
        LEFT JOIN public.client_aggregate_versions v
          ON v.aggregate_type='icon' AND v.scope_type='unit'
          AND v.scope_id=o.unit AND v.aggregate_id=i.id::text
        WHERE o.id=p_occasion),'[]'::jsonb)) END;
$function$
;

REVOKE ALL ON FUNCTION public.get_map_editor_bundle_v1(p_occasion bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_map_editor_bundle_v1(p_occasion bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.get_map_editor_bundle_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_map_editor_bundle_v1(bigint) TO authenticated,service_role;
