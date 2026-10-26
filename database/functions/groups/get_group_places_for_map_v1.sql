-- The map's authenticated occasion members retain their existing group-place
-- projection, scoped to one occasion and carrying the original place revision.
CREATE OR REPLACE FUNCTION public.get_group_places_for_map_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_read_group_places(p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='occasion member required'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'place',g.place,'places',
  jsonb_build_object('id',p.id,'occasion',p.occasion,'unit',p.unit,'title',p.title,'description',p.description,
    'coordinates',p.coordinates,'type',p.type,'is_hidden',p.is_hidden,'order',p."order",'icon',p.icon,'aggregate_version',coalesce(v.version,0))) ORDER BY g.id)
  FROM public.user_group_info g JOIN public.places p ON p.id=g.place AND p.occasion=g.occasion
  LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=p.id::text
  WHERE g.occasion=p_occasion AND (NOT public.is_demo_unit(p.unit) OR public.demo_unit_can_read(p.unit))),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_group_places_for_map_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_group_places_for_map_v1(bigint) TO authenticated;
