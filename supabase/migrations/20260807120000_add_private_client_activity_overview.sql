-- The administration activity view intentionally exposes only aggregate
-- 30-minute/category totals. Actor identity and individual commit details stay
-- out of this UI contract.
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
      public.get_is_manager_on_occasion(p_occasion)
        OR public.get_is_admin_on_occasion(p_occasion) AS can_occasion,
      CASE
        WHEN o.unit IS NULL THEN false
        ELSE public.get_is_manager_on_unit(o.unit)
      END AS can_unit,
      CASE
        WHEN o.organization IS NULL THEN false
        ELSE public.get_is_admin_on_organization(o.organization)
      END AS can_organization
    FROM public.occasions o
    WHERE o.id = p_occasion
  ),
  activity AS (
    SELECT
      date_bin(
        interval '30 minutes',
        c.occurred_at,
        timestamptz '2000-01-01 00:00:00+00'
      ) AS bucket_start,
      c.change_class AS category,
      sum(greatest(coalesce(items.item_count, 0), 1))::bigint
        AS activity_count
    FROM public.client_commits c
    CROSS JOIN scope s
    LEFT JOIN LATERAL (
      SELECT count(*)::bigint AS item_count
      FROM public.client_commit_items item
      WHERE item.commit_id = c.commit_id
    ) items ON true
    WHERE c.occurred_at >= p_from
      AND c.occurred_at < p_to
      AND (
        (s.can_occasion AND c.occasion = p_occasion)
        OR (s.can_unit AND c.unit = s.unit)
        OR (s.can_organization AND c.organization = s.organization)
      )
    GROUP BY bucket_start, c.change_class
  )
  SELECT CASE
    WHEN p_from IS NULL
      OR p_to IS NULL
      OR p_to <= p_from
      OR p_to - p_from > interval '31 days'
      THEN jsonb_build_object('code', 400)
    WHEN NOT EXISTS (
      SELECT 1
      FROM scope s
      WHERE s.can_occasion OR s.can_unit OR s.can_organization
    ) THEN jsonb_build_object('code', 403)
    ELSE jsonb_build_object(
      'code', 200,
      'data', coalesce((
        SELECT jsonb_agg(
          jsonb_build_object(
            'bucketStart', a.bucket_start,
            'category', a.category,
            'activityCount', a.activity_count
          )
          ORDER BY a.bucket_start, a.category
        )
        FROM activity a
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
