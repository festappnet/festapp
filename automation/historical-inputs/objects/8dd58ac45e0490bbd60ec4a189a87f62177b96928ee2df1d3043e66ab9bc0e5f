CREATE OR REPLACE FUNCTION public.fanout_unit_map_catalog_internal_v1(p_commit_id uuid, p_unit bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_occasion bigint; v_revision bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.client_commits c
    WHERE c.commit_id=p_commit_id) THEN
    RAISE foreign_key_violation USING MESSAGE='unit fanout requires an audit commit';
  END IF;
  FOR v_occasion IN SELECT o.id FROM public.occasions o
    WHERE o.unit=p_unit AND NOT o.is_hidden ORDER BY o.id LOOP
    INSERT INTO public.client_sync_scopes
      (component,scope_type,scope_id,source_revision)
    VALUES ('map_catalog','occasion',v_occasion,1)
    ON CONFLICT (component,scope_type,scope_id) DO UPDATE
      SET source_revision=public.client_sync_scopes.source_revision+1,
          updated_at=now()
    RETURNING source_revision INTO v_revision;
    INSERT INTO public.client_commit_components
      (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
    VALUES (p_commit_id,'map_catalog','occasion',v_occasion,NULL,v_revision);
    INSERT INTO public.client_projection_dirty_keys
      (component,scope_type,scope_id,entity_id,source_revision)
    VALUES ('map_catalog','occasion',v_occasion,0,v_revision)
    ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE
      SET source_revision=EXCLUDED.source_revision,dirty_since=now(),
          claimed_at=NULL,claim_token=NULL;
  END LOOP;
END; $function$

;

REVOKE ALL ON FUNCTION public.fanout_unit_map_catalog_internal_v1(uuid,bigint) FROM PUBLIC,anon,authenticated;
