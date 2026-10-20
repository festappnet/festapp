CREATE OR REPLACE FUNCTION public.get_news_with_versions_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_access_to_occasion(p_occasion);
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(n)||jsonb_build_object('aggregate_version',coalesce(v.version,0)) ORDER BY n.id DESC)
  FROM public.get_news_with_views(p_occasion) n LEFT JOIN public.client_aggregate_versions v
  ON v.aggregate_type='news' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=n.id::text),'[]');
END $$;

REVOKE ALL ON FUNCTION public.get_news_with_versions_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_news_with_versions_v1(bigint) TO anon,authenticated;
