-- Canonical owner: database/functions/authoring/lifecycle.sql.
-- Preserve UI revision/replay semantics instead of a second serialization check.
BEGIN;
CREATE OR REPLACE FUNCTION public.manage_occasion_setup_authoring(p_unit bigint,p_organization bigint,p_draft uuid,p_expected_revision bigint DEFAULT NULL,p_command_id uuid DEFAULT NULL,p_source_scopes jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE draft public.occasion_setup_drafts; source bigint; binding jsonb; source_ids bigint[];
BEGIN
 PERFORM public.lock_people_scope_internal_v1(NULL,p_organization,p_unit);
 IF NOT public.can_create_occasion(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='setup author required'; END IF;
 SELECT * INTO draft FROM public.occasion_setup_drafts WHERE id=p_draft AND unit=p_unit AND organization=p_organization FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='setup draft unavailable'; END IF;
 IF p_command_id IS NULL THEN RETURN public.get_occasion_setup_draft(p_draft); END IF;
 IF draft.data ? 'finalizeResponse' THEN RETURN public.finalize_occasion_setup_draft(p_draft,p_expected_revision,p_command_id); END IF;
 source_ids:=ARRAY(SELECT DISTINCT x::bigint FROM unnest(ARRAY[draft.data->>'sourceId',draft.data->>'formSourceOccasionId',draft.data->>'blueprintSourceOccasionId']) x WHERE nullif(x,'') IS NOT NULL);
 IF jsonb_typeof(p_source_scopes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_source_scopes)<>cardinality(source_ids) THEN RAISE insufficient_privilege USING MESSAGE='source consent required'; END IF;
 FOREACH source IN ARRAY source_ids LOOP
  SELECT x INTO binding FROM jsonb_array_elements(p_source_scopes) x WHERE (x->>'occasionId')::bigint=source;
  IF binding IS NULL THEN RAISE insufficient_privilege USING MESSAGE='source consent required'; END IF;
  PERFORM public.lock_people_scope_internal_v1(source,p_organization,(binding->>'unitId')::bigint);
  IF NOT public.can_copy_occasion_source(source) THEN RAISE insufficient_privilege USING MESSAGE='source read denied'; END IF;
 END LOOP;
 RETURN public.finalize_occasion_setup_draft(p_draft,p_expected_revision,p_command_id);
END $$;
REVOKE ALL ON FUNCTION public.manage_occasion_setup_authoring(bigint,bigint,uuid,bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_occasion_setup_authoring(bigint,bigint,uuid,bigint,uuid,jsonb) TO authenticated;

COMMIT;
