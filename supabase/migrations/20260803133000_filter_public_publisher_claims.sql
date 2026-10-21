-- Hidden occasions have no public sync scope. Keep their dirty keys queued so
-- a later unhide can publish them, but never lease them to the public R2
-- publisher while they are hidden.
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
DECLARE
  v_token uuid := gen_random_uuid();
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
    SET claimed_at = now(), claim_token = v_token
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
