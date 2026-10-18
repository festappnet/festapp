-- Identity is derived from JWT; never accept a user UUID from the reader.
CREATE OR REPLACE FUNCTION public.get_news_read_state_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE marker bigint;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.occasion_users
   WHERE occasion=p_occasion AND "user"=auth.uid()) THEN
   -- Public visitors can read public news, but never a retained private marker.
   IF auth.uid() IS NULL THEN RAISE insufficient_privilege USING MESSAGE='identity required'; END IF;
   PERFORM public.get_occasion_for_context_v1(p_occasion);
   RETURN jsonb_build_object('newsId',0);
 END IF;
 SELECT coalesce(max(news_id),0) INTO marker FROM public.user_news
 WHERE occasion=p_occasion AND "user"=auth.uid();
 RETURN jsonb_build_object('newsId',marker);
END $$;
REVOKE ALL ON FUNCTION public.get_news_read_state_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_news_read_state_v1(bigint) TO authenticated,service_role;

-- Preserve the legacy row shape and per-marker view counts, adding concurrency versions.
CREATE OR REPLACE FUNCTION public.get_news_for_context_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('aggregate_version',
   coalesce(v.version,0)) ORDER BY n.id DESC),'[]'::jsonb)
 FROM public.get_news_with_views(p_occasion) n
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='news'
 AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=n.id::text;
$$;
REVOKE ALL ON FUNCTION public.get_news_for_context_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_news_for_context_v1(bigint) TO anon,authenticated,service_role;

ALTER FUNCTION public.get_news_read_state_v1(bigint) OWNER TO postgres;

ALTER FUNCTION public.get_news_for_context_v1(bigint) OWNER TO postgres;
