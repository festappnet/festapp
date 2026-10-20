-- A cleaning resolve changes existing cleaning report rows. The client commit
-- audit vocabulary only permits insert/update/delete/import/publish, so record
-- this transition as an update. The original v1 wrapper used the unsupported
-- value "resolve", causing the audit insert (and therefore the whole command)
-- to fail with client_commit_items_operation_check.
CREATE OR REPLACE FUNCTION public.resolve_cleaning_place_client_sync_v1(
  p_place bigint,
  p_command_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_occasion bigint;
  v_begin jsonb;
  v_hash text;
  v_result jsonb;
  v_open integer;
BEGIN
  SELECT p.occasion INTO v_occasion
  FROM public.places p
  WHERE p.id = p_place;

  IF v_actor IS NULL OR v_occasion IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE = 'cleaning crew required';
  END IF;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'place', p_place
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_client_mutation_v1(
    p_command_id,
    'cleaning.resolve',
    v_occasion,
    v_actor,
    v_hash
  );
  IF v_begin->>'disposition' = 'replay' THEN
    RETURN v_begin->'response';
  END IF;

  PERFORM 1 FROM public.places p WHERE p.id = p_place FOR UPDATE;
  PERFORM 1
  FROM public.cleaning_reports cr
  WHERE cr.place = p_place AND cr.resolved_at IS NULL
  ORDER BY cr.id
  FOR UPDATE;

  SELECT count(*) INTO v_open
  FROM public.cleaning_reports cr
  WHERE cr.place = p_place AND cr.resolved_at IS NULL;

  v_result := public.resolve_cleaning_place_internal_v1(p_place);
  IF COALESCE((v_result->>'code')::integer, 500) <> 200 THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'rejected',
      COALESCE((v_result->>'code')::integer, 400),
      COALESCE(v_result->'data', '{}') ||
        jsonb_build_object('message', v_result->>'message')
    );
  END IF;

  IF v_open = 0 THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'unchanged',
      200,
      v_result->'data'
    );
  END IF;

  RETURN public.complete_client_mutation_applied_v1(
    p_command_id,
    v_occasion,
    'cleaning.resolve',
    'cleaning',
    jsonb_build_array(jsonb_build_object(
      'entityType', 'cleaning_place',
      'entityId', p_place,
      'operation', 'update',
      'safeLabel', 'Cleaning place',
      'changedFields', jsonb_build_array('resolvedAt')
    )),
    ARRAY['live_public'],
    '[]',
    jsonb_build_array(jsonb_build_object(
      'component', 'live_public',
      'entityId', p_place
    )),
    v_result->'data'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_cleaning_place_client_sync_v1(bigint, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_cleaning_place_client_sync_v1(bigint, uuid)
  TO authenticated;
