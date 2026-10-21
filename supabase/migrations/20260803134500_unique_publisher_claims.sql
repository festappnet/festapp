-- Every dirty key needs its own completion token. A batch-wide token lets the
-- first completed scope delete unrelated work claimed in the same batch.
CREATE OR REPLACE FUNCTION public.claim_client_projection_dirty_v1(
  p_limit integer DEFAULT 200
)
RETURNS TABLE(
  component text,
  scope_type text,
  scope_id bigint,
  entity_id bigint,
  source_revision bigint,
  claim_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  RETURN QUERY
  WITH claimed AS (
    SELECT d.component, d.scope_type, d.scope_id, d.entity_id
    FROM public.client_projection_dirty_keys d
    JOIN public.occasions o
      ON d.scope_type = 'occasion'
     AND o.id = d.scope_id
     AND NOT o.is_hidden
    WHERE d.claimed_at IS NULL
       OR d.claimed_at < now() - interval '2 minutes'
    ORDER BY d.dirty_since
    FOR UPDATE OF d SKIP LOCKED
    LIMIT LEAST(p_limit, 1000)
  ), updated AS (
    UPDATE public.client_projection_dirty_keys d
    SET claimed_at = now(), claim_token = gen_random_uuid()
    FROM claimed c
    WHERE (d.component, d.scope_type, d.scope_id, d.entity_id) =
          (c.component, c.scope_type, c.scope_id, c.entity_id)
    RETURNING d.*
  )
  SELECT u.component, u.scope_type, u.scope_id, u.entity_id,
         u.source_revision, u.claim_token
  FROM updated u;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_client_projection_dirty_v1(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_client_projection_dirty_v1(integer)
  TO service_role;

-- Requeue public bootstrap work that may have been removed by the old shared
-- token. Existing immutable artifacts are reused by the publisher.
WITH latest AS (
  SELECT component, scope_type, scope_id, max(published_revision) AS revision
  FROM public.client_sync_publications
  GROUP BY component, scope_type, scope_id
)
INSERT INTO public.client_projection_dirty_keys
  (component, scope_type, scope_id, entity_id, source_revision)
SELECT s.component, s.scope_type, s.scope_id, 0, s.source_revision
FROM public.client_sync_scopes s
JOIN public.occasions o
  ON s.scope_type = 'occasion'
 AND o.id = s.scope_id
 AND NOT o.is_hidden
LEFT JOIN latest p
  ON p.component = s.component
 AND p.scope_type = s.scope_type
 AND p.scope_id = s.scope_id
LEFT JOIN public.client_sync_public_heads h
  ON h.scope_type = s.scope_type
 AND h.scope_id = s.scope_id
WHERE (s.component = 'live_public' AND
       (p.revision IS NULL OR h.live_revision IS NULL OR p.revision < s.source_revision))
   OR (s.component <> 'live_public' AND
       (p.revision IS NULL OR h.release_revision IS NULL))
ON CONFLICT (component, scope_type, scope_id, entity_id) DO UPDATE
SET source_revision = GREATEST(
      public.client_projection_dirty_keys.source_revision,
      EXCLUDED.source_revision
    ),
    dirty_since = now(),
    claimed_at = NULL,
    claim_token = NULL;
