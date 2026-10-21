-- Canonical owner recovered from the recorded effective main schema.
-- Public signatures, response envelopes and existing execution roles are preserved.

CREATE OR REPLACE FUNCTION public.get_client_commits_v1(p_occasion bigint, p_before_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  WITH scope AS (
    SELECT o.unit, o.organization,
      public.can_read_occasion_client_commits(p_occasion) AS can_occasion,
      CASE WHEN o.unit IS NULL THEN false
        ELSE public.can_read_unit_client_commits(o.unit) END AS can_unit,
      CASE WHEN o.organization IS NULL THEN false
        ELSE public.can_read_organization_client_commits(o.organization) END AS can_organization
    FROM public.occasions o
    WHERE o.id = p_occasion
  )
  SELECT CASE
    WHEN NOT EXISTS (
      SELECT 1 FROM scope s
      WHERE public.client_commit_read_rule(s.can_occasion,s.can_unit,s.can_organization)
    ) THEN jsonb_build_object('code',403)
    ELSE jsonb_build_object('code',200,'data',COALESCE((
      SELECT jsonb_agg(row_data ORDER BY occurred_at DESC, commit_id DESC)
      FROM (
        SELECT c.occurred_at,c.commit_id,jsonb_build_object(
          'commitId',c.commit_id,'occurredAt',c.occurred_at,
          'actorDisplay',c.actor_display,'actorKind',c.actor_kind,
          'source',c.source,'changeClass',c.change_class,
          'itemCount',(SELECT count(*) FROM public.client_commit_items ci
            WHERE ci.commit_id=c.commit_id),
          'components',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'component',cc.component,'revision',cc.resulting_revision,
            'publishedRevision',pub.published_revision,
            'publicationStatus',CASE
              WHEN pub.published_revision>=cc.resulting_revision
                THEN 'published' ELSE 'pending' END)),'[]')
            FROM public.client_commit_components cc
            LEFT JOIN LATERAL (
              SELECT max(cp.published_revision) published_revision
              FROM public.client_sync_publications cp
              WHERE cp.component=cc.component
                AND cp.scope_type=cc.scope_type
                AND cp.scope_id=cc.scope_id
            ) pub ON true
            WHERE cc.commit_id=c.commit_id)
        ) row_data
        FROM public.client_commits c
        CROSS JOIN scope s
        WHERE (
          (s.can_occasion AND c.occasion=p_occasion)
          OR (s.can_unit AND c.unit=s.unit)
          OR (s.can_organization AND c.organization=s.organization)
        )
          AND (p_before_time IS NULL OR
            (c.occurred_at,c.commit_id)<(p_before_time,p_before_id))
          AND (NOT p_filters ? 'source' OR c.source=p_filters->>'source')
          AND (NOT p_filters ? 'changeClass'
            OR c.change_class=p_filters->>'changeClass')
          AND (NOT p_filters ? 'actorKind'
            OR c.actor_kind=p_filters->>'actorKind')
          AND (NOT p_filters ? 'actor'
            OR COALESCE(c.actor_display,'') ILIKE
              '%'||(p_filters->>'actor')||'%')
          AND (NOT p_filters ? 'from'
            OR c.occurred_at >= (p_filters->>'from')::timestamptz)
          AND (NOT p_filters ? 'to'
            OR c.occurred_at < (p_filters->>'to')::timestamptz)
          AND (NOT p_filters ? 'component' OR EXISTS(
            SELECT 1 FROM public.client_commit_components fc
            WHERE fc.commit_id=c.commit_id
              AND fc.component=p_filters->>'component'))
        ORDER BY c.occurred_at DESC,c.commit_id DESC
        LIMIT LEAST(GREATEST(p_limit,1),501)
      ) page
    ), '[]'))
  END
  FROM (SELECT 1) singleton;
$function$
;
REVOKE ALL ON FUNCTION public.get_client_commits_v1(bigint,timestamp with time zone,uuid,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_client_commits_v1(bigint,timestamp with time zone,uuid,integer,jsonb) TO postgres,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_client_commit_v1(p_commit_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT CASE WHEN c.commit_id IS NULL THEN jsonb_build_object('code',404)
    WHEN NOT public.can_read_client_commit(c.commit_id) THEN jsonb_build_object('code',403)
    ELSE jsonb_build_object('code',200,'data',jsonb_build_object(
      'commitId',c.commit_id,'occurredAt',c.occurred_at,
      'actorDisplay',c.actor_display,'actorKind',c.actor_kind,
      'source',c.source,'changeClass',c.change_class,'reason',c.reason,
      'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'entityType',i.entity_type,'entityId',i.entity_id,
        'operation',i.operation,'safeLabel',i.safe_label,
        'changedFields',i.changed_fields) ORDER BY i.item_index),'[]')
        FROM public.client_commit_items i WHERE i.commit_id=c.commit_id),
      'components',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'component',cc.component,'scopeType',cc.scope_type,
        'scopeId',cc.scope_id,'revision',cc.resulting_revision,
        'publishedRevision',p.published_revision,
        'publicationStatus',CASE
          WHEN p.published_revision>=cc.resulting_revision
            THEN 'published' ELSE 'pending' END)
        ORDER BY cc.component),'[]')
        FROM public.client_commit_components cc
        LEFT JOIN LATERAL (
          SELECT max(cp.published_revision) published_revision
          FROM public.client_sync_publications cp
          WHERE cp.component=cc.component
            AND cp.scope_type=cc.scope_type
            AND cp.scope_id=cc.scope_id
        ) p ON true
        WHERE cc.commit_id=c.commit_id))) END
  FROM (SELECT * FROM public.client_commits WHERE commit_id=p_commit_id) c
  RIGHT JOIN (SELECT 1) seed ON true;
$function$
;
REVOKE ALL ON FUNCTION public.get_client_commit_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_client_commit_v1(uuid) TO postgres,authenticated,service_role;
