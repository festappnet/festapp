-- The duplicate command must use the audit operation accepted by
-- client_commit_items_operation_check. The old value, 'create', rolled back
-- every attempted occasion copy before it returned an occasion ID.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint, p_command_id uuid, p_target_unit bigint, p_locale text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_unit bigint;
  v_title text;
  v_source_unit bigint;
  v_org bigint;
  v_new bigint;
  v_begin jsonb;
  v_hash text;
  v_policies jsonb;
  v_commit public.client_commits%ROWTYPE;
BEGIN
  SELECT o.unit, o.title, o.organization INTO v_source_unit, v_title, v_org
  FROM public.occasions o WHERE o.id = p_occasion;
  v_unit := COALESCE(p_target_unit, v_source_unit);
  IF v_actor IS NULL OR v_source_unit IS NULL OR v_unit IS NULL
     OR NOT public.can_copy_occasion_source(p_occasion)
     OR public.is_demo_unit(v_unit)
     OR NOT public.can_copy_occasion_target(v_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units WHERE id=v_unit AND organization=v_org) THEN
    RAISE insufficient_privilege USING MESSAGE = 'unit manager required';
  END IF;
  v_hash := encode(extensions.digest(convert_to((jsonb_build_object(
    'occasion', p_occasion) || CASE WHEN v_unit = v_source_unit THEN '{}'::jsonb
        ELSE jsonb_build_object('targetUnit', v_unit) END || CASE WHEN p_locale IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('locale',p_locale) END)::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_unit_client_mutation_v1(
    p_command_id, 'occasion.duplicate', v_unit, v_actor, v_hash);
  IF v_begin->>'disposition' = 'replay' THEN RETURN v_begin->'response'; END IF;

  v_policies:=public.abuse_policy_bundle_v1(ARRAY['occasion.creation','occasion.copy'],v_unit,v_org);
  PERFORM public.admit_occasion_copy_v1(p_occasion,v_unit,v_org,v_policies->'occasion.copy');
  PERFORM public.admit_occasion_creation_v1(v_actor,v_unit,v_org,NULL,v_policies->'occasion.creation');
  v_new := public.duplicate_occasion_internal_v1(p_occasion, v_unit,coalesce(p_locale,'en'));
  PERFORM public.admit_occasion_copy_v1(v_new,v_unit,v_org,v_policies->'occasion.copy');
  INSERT INTO public.occasion_users
    (occasion, "user", is_manager, is_editor, is_editor_view, is_editor_order, is_editor_order_view)
  VALUES (v_new, v_actor, true, true, true, true, true);
  UPDATE public.occasions SET data = jsonb_set(COALESCE(data, '{}'::jsonb),
    '{client_sync_v1}', 'false'::jsonb, true) WHERE id = v_new;
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
    (SELECT left(title,240) FROM public.occasions WHERE id=v_new), ARRAY['aggregate']);
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
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid, bigint, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid, bigint, text)
  TO authenticated;


CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(p_occasion bigint,p_command_id uuid,p_target_unit bigint)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT public.duplicate_occasion_client_sync_v1(p_occasion,p_command_id,p_target_unit,NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid,bigint) TO authenticated;
-- Keep existing client signatures routed through the same canonical command.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint, p_command_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_client_sync_v1(p_occasion, p_command_id, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint, p_target_unit bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_response jsonb;
BEGIN
  v_response := public.duplicate_occasion_client_sync_v1(oc, gen_random_uuid(), p_target_unit);
  RETURN (v_response #>> '{data,occasionId}')::bigint;
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint) TO authenticated;

-- Return only authorized destinations. The navigation unit list does not carry
-- membership flags and may include units visible only through an occasion.
CREATE OR REPLACE FUNCTION public.get_occasion_copy_units(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_org bigint; v_unit bigint;
BEGIN
  SELECT organization, unit INTO v_org, v_unit FROM public.occasions WHERE id=p_occasion;
  IF auth.uid() IS NULL OR v_unit IS NULL
     OR NOT public.can_copy_occasion_source(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='source unit manager required';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id', u.id, 'title', u.title, 'organization', u.organization) ORDER BY u.title,u.id)
    FROM public.units u WHERE u.organization=v_org AND public.can_copy_occasion_target(u.id) AND NOT public.is_demo_unit(u.id)), '[]'::jsonb);
END; $$;
REVOKE ALL ON FUNCTION public.get_occasion_copy_units(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_copy_units(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint,p_target_unit bigint,p_locale text)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT (public.duplicate_occasion_client_sync_v1(oc,gen_random_uuid(),p_target_unit,p_locale)#>>'{data,occasionId}')::bigint;
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint,bigint,text) TO authenticated;
