-- The admin audit view deliberately shows large pages. The extra row lets the
-- client determine whether another 500-row page exists without a probe query.
CREATE OR REPLACE FUNCTION public.get_client_commits_v1(
  p_occasion bigint, p_before_time timestamptz DEFAULT NULL,
  p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50,
  p_filters jsonb DEFAULT '{}'
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN NOT (public.get_is_manager_on_occasion(p_occasion)
      OR public.get_is_admin_on_occasion(p_occasion)) THEN jsonb_build_object('code',403)
    ELSE jsonb_build_object('code',200,'data',COALESCE((
      SELECT jsonb_agg(row_data ORDER BY occurred_at DESC, commit_id DESC) FROM (
        SELECT c.occurred_at,c.commit_id,jsonb_build_object(
          'commitId',c.commit_id,'occurredAt',c.occurred_at,'actorDisplay',c.actor_display,
          'actorKind',c.actor_kind,'source',c.source,'changeClass',c.change_class,
          'itemCount',(SELECT count(*) FROM public.client_commit_items ci WHERE ci.commit_id=c.commit_id),
          'components',(SELECT COALESCE(jsonb_agg(jsonb_build_object('component',cc.component,'revision',cc.resulting_revision,
            'publishedRevision',pub.published_revision,'publicationStatus',CASE WHEN pub.published_revision>=cc.resulting_revision THEN 'published' ELSE 'pending' END)),'[]')
            FROM public.client_commit_components cc LEFT JOIN LATERAL (SELECT max(cp.published_revision) published_revision
              FROM public.client_sync_publications cp WHERE cp.component=cc.component AND cp.scope_type=cc.scope_type AND cp.scope_id=cc.scope_id) pub ON true
            WHERE cc.commit_id=c.commit_id)
        ) row_data
        FROM public.client_commits c WHERE (c.occasion=p_occasion OR c.unit=(
          SELECT o.unit FROM public.occasions o WHERE o.id=p_occasion)
          OR c.organization=(SELECT o.organization FROM public.occasions o
            WHERE o.id=p_occasion))
          AND (p_before_time IS NULL OR (c.occurred_at,c.commit_id)<(p_before_time,p_before_id))
          AND (NOT p_filters ? 'source' OR c.source=p_filters->>'source')
          AND (NOT p_filters ? 'changeClass' OR c.change_class=p_filters->>'changeClass')
          AND (NOT p_filters ? 'actorKind' OR c.actor_kind=p_filters->>'actorKind')
          AND (NOT p_filters ? 'actor' OR COALESCE(c.actor_display,'') ILIKE '%'||(p_filters->>'actor')||'%')
          AND (NOT p_filters ? 'from' OR c.occurred_at >= (p_filters->>'from')::timestamptz)
          AND (NOT p_filters ? 'to' OR c.occurred_at < (p_filters->>'to')::timestamptz)
          AND (NOT p_filters ? 'component' OR EXISTS(SELECT 1 FROM public.client_commit_components fc
            WHERE fc.commit_id=c.commit_id AND fc.component=p_filters->>'component'))
        ORDER BY c.occurred_at DESC,c.commit_id DESC LIMIT LEAST(GREATEST(p_limit,1),501)
      ) page), '[]')) END;
$$;
REVOKE ALL ON FUNCTION public.get_client_commits_v1(bigint,timestamptz,uuid,integer,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_commits_v1(bigint,timestamptz,uuid,integer,jsonb) TO authenticated;
