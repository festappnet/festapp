-- The duplicate command must use the audit operation accepted by
-- client_commit_items_operation_check. The old value, 'create', rolled back
-- every attempted occasion copy before it returned an occasion ID.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_domain_command_internal_v1(
  p_occasion bigint, p_command_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_unit bigint;
  v_title text;
  v_new bigint;
  v_begin jsonb;
  v_hash text;
  v_commit public.client_commits%ROWTYPE;
BEGIN
  SELECT o.unit, o.title INTO v_unit, v_title
  FROM public.occasions o WHERE o.id = p_occasion;
  IF v_actor IS NULL OR v_unit IS NULL
     OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE = 'unit manager required';
  END IF;
  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion', p_occasion)::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_unit_client_mutation_v1(
    p_command_id, 'occasion.duplicate', v_unit, v_actor, v_hash);
  IF v_begin->>'disposition' = 'replay' THEN RETURN v_begin->'response'; END IF;

  v_new := public.duplicate_occasion_internal_v1(p_occasion);
  INSERT INTO public.client_commits
    (unit, actor_id, actor_display, actor_kind, source, change_class)
  SELECT v_unit, v_actor, nullif(concat_ws(' ', ui.name, ui.surname), ''),
    'user', 'occasion.duplicate', 'configuration'
  FROM public.user_info ui WHERE ui.id = v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id, item_index, entity_type, entity_id, operation, safe_label,
     changed_fields)
  VALUES (v_commit.commit_id, 0, 'occasion', v_new::text, 'insert',
    left(COALESCE(v_title, '') || ' (Copy)', 240), ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id, v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id, jsonb_build_object(
    'status', 'applied', 'code', 200,
    'data', jsonb_build_object('occasionId', v_new),
    'mutation', jsonb_build_object('commandId', p_command_id,
      'receiptId', p_command_id, 'commitId', v_commit.commit_id,
      'replayed', false, 'occurredAt', v_commit.occurred_at),
    'sync', jsonb_build_object('replacements', '[]'::jsonb)),
    v_commit.commit_id);
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_domain_command_internal_v1(bigint, uuid)
  FROM PUBLIC, anon, authenticated;

-- A copied occasion has no occasion_users rows. Its creator needs editor rights
-- to copy its images and save the final media URLs after the database copy.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint, p_command_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_response jsonb;
  v_new bigint;
  v_unit bigint;
BEGIN
  SELECT o.unit INTO v_unit FROM public.occasions o WHERE o.id = p_occasion;
  IF v_actor IS NULL OR v_unit IS NULL
     OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE = 'unit manager required';
  END IF;

  v_response := public.duplicate_occasion_domain_command_internal_v1(
    p_occasion, p_command_id);
  v_new := NULLIF(v_response #>> '{data,occasionId}', '')::bigint;
  IF v_response->>'status' = 'applied' AND v_new IS NOT NULL THEN
    INSERT INTO public.occasion_users
      (occasion, "user", is_editor, is_editor_view)
    VALUES (v_new, v_actor, true, true)
    ON CONFLICT (occasion, "user") DO UPDATE
      SET is_editor = true, is_editor_view = true;

    UPDATE public.occasions o
    SET data = jsonb_set(COALESCE(o.data, '{}'::jsonb),
      '{client_sync_v1}', 'false'::jsonb, true)
    WHERE o.id = v_new;
  END IF;
  RETURN v_response;
END; $$;

REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid)
  TO authenticated;
