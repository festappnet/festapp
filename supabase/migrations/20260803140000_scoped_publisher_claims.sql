-- One canonical claim implementation serves both full-fleet maintenance and
-- explicitly scoped production rollouts. Only the narrow wrappers are
-- grantable; clients cannot call the internal lease primitive.
CREATE OR REPLACE FUNCTION public.claim_client_projection_dirty_internal_v1(
  p_scope_ids bigint[],
  p_limit integer
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
    WHERE (p_scope_ids IS NULL OR d.scope_id = ANY(p_scope_ids))
      AND (d.claimed_at IS NULL
        OR d.claimed_at < now() - interval '2 minutes')
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

REVOKE ALL ON FUNCTION public.claim_client_projection_dirty_internal_v1(bigint[], integer)
  FROM PUBLIC, anon, authenticated, service_role;

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
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM public.claim_client_projection_dirty_internal_v1(NULL, p_limit);
$$;

CREATE OR REPLACE FUNCTION public.claim_client_projection_dirty_scopes_v1(
  p_scope_ids bigint[],
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
  IF p_scope_ids IS NULL OR cardinality(p_scope_ids) = 0 THEN
    RAISE EXCEPTION 'at least one publication scope is required';
  END IF;
  RETURN QUERY
  SELECT *
  FROM public.claim_client_projection_dirty_internal_v1(p_scope_ids, p_limit);
END;
$$;

REVOKE ALL ON FUNCTION public.claim_client_projection_dirty_v1(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_client_projection_dirty_v1(integer)
  TO service_role;
REVOKE ALL ON FUNCTION public.claim_client_projection_dirty_scopes_v1(bigint[], integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_client_projection_dirty_scopes_v1(bigint[], integer)
  TO service_role;
