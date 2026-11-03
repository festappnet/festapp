BEGIN;

-- The public save wrapper and the settings UI allow unit editors. The renamed
-- canonical domain command retained its older occasion-only guard, so it must
-- accept the same role before it reaches update_occasion_internal_v1.
CREATE OR REPLACE FUNCTION public.save_occasion_domain_command_internal_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_version bigint;
  v_begin jsonb;
  v_hash text;
  v_entity jsonb;
  v_old_hidden boolean;
  v_new_hidden boolean;
  v_old_unit bigint;
  v_new_unit bigint;
  v_fanout_units bigint[] := '{}';
BEGIN
  SELECT o.unit INTO v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion;

  IF v_actor IS NULL OR NOT (
    public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR (v_old_unit IS NOT NULL AND public.get_is_editor_on_unit(v_old_unit))
  ) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object'
    OR octet_length(p_config::text) > 1048576
    OR (p_config->>'id')::bigint IS DISTINCT FROM p_occasion
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_config) key
      WHERE key NOT IN (
        'id', 'start_time', 'end_time', 'is_open', 'is_hidden', 'is_promoted',
        'link', 'title', 'description', 'data', 'services', 'organization',
        'unit', 'features', 'form_link', 'has_orders', 'stats'
      )
    )
  THEN
    RAISE invalid_parameter_value USING MESSAGE = 'invalid occasion aggregate';
  END IF;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion', p_occasion,
    'expectedVersion', p_expected_version,
    'config', p_config
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_client_mutation_v1(
    p_command_id,
    'occasion.config.save',
    p_occasion,
    v_actor,
    v_hash
  );
  IF v_begin->>'disposition' = 'replay' THEN
    RETURN v_begin->'response';
  END IF;

  SELECT o.is_hidden, o.unit INTO v_old_hidden, v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'rejected',
      404,
      jsonb_build_object('version', 0, 'occasion', NULL)
    );
  END IF;

  INSERT INTO public.client_aggregate_versions(
    aggregate_type, scope_type, scope_id, aggregate_id, version
  ) VALUES ('occasion', 'occasion', p_occasion, p_occasion::text, 0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version
  FROM public.client_aggregate_versions
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version)
    INTO v_entity
    FROM public.occasions o
    WHERE o.id = p_occasion;
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'conflict',
      409,
      jsonb_build_object('version', v_version, 'occasion', v_entity)
    );
  END IF;

  PERFORM public.update_occasion_internal_v1(p_config);
  UPDATE public.client_aggregate_versions
  SET version = version + 1, updated_at = clock_timestamp()
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  RETURNING version INTO v_version;
  SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version)
  INTO v_entity
  FROM public.occasions o
  WHERE o.id = p_occasion;

  v_new_hidden := (v_entity->>'is_hidden')::boolean;
  v_new_unit := (v_entity->>'unit')::bigint;
  IF NOT v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_old_unit);
  END IF;
  IF NOT v_new_hidden AND v_new_unit IS DISTINCT FROM v_old_unit THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  ELSIF NOT v_new_hidden AND v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  END IF;

  RETURN public.complete_client_mutation_applied_v1(
    p_command_id,
    p_occasion,
    'occasion.config.save',
    'configuration',
    jsonb_build_array(jsonb_build_object(
      'entityType', 'occasion',
      'entityId', p_occasion,
      'operation', 'update',
      'safeLabel', left(v_entity->>'title', 240),
      'changedFields', jsonb_build_array('configuration')
    )),
    CASE WHEN v_old_hidden AND NOT v_new_hidden THEN ARRAY[
      'occasion_config', 'program_catalog', 'map_catalog', 'content_catalog',
      'live_public'
    ] ELSE ARRAY['occasion_config'] END,
    '[]',
    '[]',
    jsonb_build_object('version', v_version, 'occasion', v_entity),
    CASE WHEN NOT v_new_hidden THEN ARRAY['occasion_config'] ELSE '{}'::text[] END,
    '[]',
    'user',
    NULL,
    '[]',
    v_fanout_units
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_occasion_domain_command_internal_v1(
  bigint, uuid, bigint, jsonb
) FROM PUBLIC, anon, authenticated;

COMMIT;
