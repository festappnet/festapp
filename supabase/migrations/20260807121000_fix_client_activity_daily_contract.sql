-- The admin chart is a daily, occasion-local aggregate. Permissions authorize
-- access but must never broaden the requested occasion's dataset.
CREATE OR REPLACE FUNCTION public.get_client_activity_v1(
  p_occasion bigint,
  p_from timestamptz,
  p_to timestamptz
) RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH scope AS (
    SELECT
      o.unit,
      o.organization,
      coalesce(o.data->>'timezone', 'UTC') AS timezone,
      public.get_is_manager_on_occasion(p_occasion)
        OR public.get_is_admin_on_occasion(p_occasion) AS can_occasion,
      CASE WHEN o.unit IS NULL THEN false
        ELSE public.get_is_manager_on_unit(o.unit) END AS can_unit,
      CASE WHEN o.organization IS NULL THEN false
        ELSE public.get_is_admin_on_organization(o.organization) END
        AS can_organization
    FROM public.occasions o
    WHERE o.id = p_occasion
  ),
  activity AS (
    SELECT
      (c.occurred_at AT TIME ZONE s.timezone)::date AS activity_day,
      count(*)::bigint AS action_count,
      sum(greatest(coalesce(items.item_count, 0), 1))::bigint
        AS changed_item_count,
      count(DISTINCT c.actor_id)::bigint AS active_actor_count
    FROM public.client_commits c
    CROSS JOIN scope s
    LEFT JOIN LATERAL (
      SELECT count(*)::bigint AS item_count
      FROM public.client_commit_items item
      WHERE item.commit_id = c.commit_id
    ) items ON true
    WHERE c.occurred_at >= p_from
      AND c.occurred_at < p_to
      AND c.occasion = p_occasion
    GROUP BY activity_day
  ),
  calendar AS (
    SELECT generated::date AS activity_day
    FROM scope s
    CROSS JOIN LATERAL generate_series(
      (p_from AT TIME ZONE s.timezone)::date,
      ((p_to - interval '1 microsecond') AT TIME ZONE s.timezone)::date,
      interval '1 day'
    ) generated
  )
  SELECT CASE
    WHEN p_from IS NULL OR p_to IS NULL OR p_to <= p_from
      OR p_to - p_from > interval '31 days'
      THEN jsonb_build_object('code', 400)
    WHEN NOT EXISTS (
      SELECT 1 FROM scope s
      WHERE s.can_occasion OR s.can_unit OR s.can_organization
    ) THEN jsonb_build_object('code', 403)
    ELSE jsonb_build_object(
      'code', 200,
      'data', coalesce((
        SELECT jsonb_agg(
          jsonb_build_object(
            'day', c.activity_day,
            'actionCount', coalesce(a.action_count, 0),
            'changedItemCount', coalesce(a.changed_item_count, 0),
            'activeActorCount', coalesce(a.active_actor_count, 0)
          ) ORDER BY c.activity_day
        )
        FROM calendar c
        LEFT JOIN activity a USING (activity_day)
      ), '[]'::jsonb)
    )
  END;
$$;

REVOKE ALL ON FUNCTION public.get_client_activity_v1(
  bigint, timestamptz, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_activity_v1(
  bigint, timestamptz, timestamptz
) TO authenticated;
