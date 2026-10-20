BEGIN;

-- Mutation finalization runs inside a trusted SECURITY DEFINER command. The
-- public publisher wrapper is intentionally service-role-only, so calling it
-- here makes authenticated writes roll back while building their response.
-- Use the authorization-aware core materializer instead.
CREATE OR REPLACE FUNCTION public.complete_client_mutation_applied_v1(
  p_command_id uuid,
  p_occasion bigint,
  p_source text,
  p_change_class text,
  p_items jsonb,
  p_public_components text[],
  p_private_impacts jsonb,
  p_dirty_keys jsonb,
  p_data jsonb,
  p_immediate_public_components text[] DEFAULT '{}',
  p_extra_replacements jsonb DEFAULT '[]',
  p_actor_kind text DEFAULT 'user',
  p_reason text DEFAULT NULL,
  p_immediate_private_replacements jsonb DEFAULT '[]',
  p_unit_catalog_fanout_units bigint[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_commit jsonb;
  v_component text;
  v_component_data jsonb;
  v_private_replacement jsonb;
  v_private_revision bigint;
  v_replacements jsonb := COALESCE(p_extra_replacements, '[]'::jsonb);
  v_response jsonb;
  v_fanout_unit bigint;
BEGIN
  IF p_data IS NULL OR octet_length(p_data::text) > 4194304
    OR jsonb_typeof(v_replacements) <> 'array'
    OR jsonb_typeof(COALESCE(p_immediate_private_replacements, '[]')) <> 'array'
    OR NOT COALESCE(p_immediate_public_components, '{}')
      <@ COALESCE(p_public_components, '{}')
  THEN
    RAISE invalid_parameter_value USING MESSAGE = 'invalid applied mutation result';
  END IF;

  v_commit := public.record_client_sync_commit_v1(
    p_occasion,
    p_source,
    p_change_class,
    p_items,
    p_public_components,
    p_private_impacts,
    p_dirty_keys,
    p_actor_kind,
    p_reason
  );
  FOR v_fanout_unit IN
    SELECT DISTINCT id
    FROM unnest(COALESCE(p_unit_catalog_fanout_units, '{}')) id
  LOOP
    PERFORM public.fanout_unit_catalog_v1(
      (v_commit->>'commitId')::uuid,
      v_fanout_unit
    );
  END LOOP;

  FOREACH v_component IN ARRAY COALESCE(p_immediate_public_components, '{}')
  LOOP
    v_component_data := public.get_public_client_sync_component_core_v1(
      v_component,
      'occasion',
      p_occasion
    );
    v_replacements := v_replacements || jsonb_build_array(jsonb_build_object(
      'component', v_component,
      'revision', v_component_data->'revision',
      'payload', v_component_data->'payload'
    ));
  END LOOP;

  FOR v_private_replacement IN
    SELECT value
    FROM jsonb_array_elements(COALESCE(p_immediate_private_replacements, '[]'))
  LOOP
    IF v_private_replacement->>'component' NOT LIKE 'private\_%'
      OR NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(p_private_impacts, '[]')) impact
        WHERE impact->>'component' = v_private_replacement->>'component'
          AND impact->>'userId' = v_private_replacement->>'userId'
      )
    THEN
      RAISE invalid_parameter_value
        USING MESSAGE = 'invalid immediate private replacement';
    END IF;
    SELECT s.source_revision INTO STRICT v_private_revision
    FROM public.client_sync_private_scopes s
    WHERE s.component = v_private_replacement->>'component'
      AND s.occasion = p_occasion
      AND s.user_id = (v_private_replacement->>'userId')::uuid;
    v_replacements := v_replacements || jsonb_build_array(jsonb_build_object(
      'component', v_private_replacement->>'component',
      'revision', v_private_revision,
      'payload', v_private_replacement->'payload'
    ));
  END LOOP;

  v_response := jsonb_build_object(
    'status', 'applied',
    'code', 200,
    'data', p_data,
    'mutation', jsonb_build_object(
      'commandId', p_command_id,
      'receiptId', p_command_id,
      'commitId', v_commit->>'commitId',
      'replayed', false,
      'occurredAt', v_commit->>'occurredAt'
    ),
    'sync', jsonb_build_object('replacements', v_replacements)
  );
  RETURN public.finish_client_mutation_v1(
    p_command_id,
    v_response,
    (v_commit->>'commitId')::uuid
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_client_mutation_applied_v1(
  uuid, bigint, text, text, jsonb, text[], jsonb, jsonb, jsonb, text[], jsonb,
  text, text, jsonb, bigint[]
) FROM PUBLIC, anon, authenticated;

COMMIT;
