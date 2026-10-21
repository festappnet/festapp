CREATE OR REPLACE FUNCTION public.delete_occasion_domain_command_internal_v1(p_occasion bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_unit bigint; v_title text; v_begin jsonb;
  v_attempt int;
  v_hash text; v_commit public.client_commits%ROWTYPE;
BEGIN
  IF v_actor IS NULL THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion)::text,'UTF8'),'sha256'),'hex');
  -- A second lookup covers a concurrent delete that committed while our row
  -- lock was waiting. Tombstones retain actor, unit and exact request binding.
  FOR v_attempt IN 1..2 LOOP
    SELECT r.unit INTO v_unit FROM public.client_mutation_receipts r WHERE r.command_id=p_command_id
      AND r.actor_id=v_actor AND r.command_name='occasion.delete' AND r.request_sha256=v_hash AND r.occasion IS NULL;
    IF FOUND THEN
      v_begin:=public.begin_unit_client_mutation_v1(p_command_id,'occasion.delete',v_unit,v_actor,v_hash);
      IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
    END IF;
    PERFORM 1 FROM public.forms WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
    PERFORM 1 FROM eshop.product_types WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
    PERFORM 1 FROM eshop.products WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
    SELECT o.unit,o.title INTO v_unit,v_title FROM public.occasions o WHERE o.id=p_occasion FOR UPDATE;
    EXIT WHEN FOUND;
  END LOOP;
  IF v_unit IS NULL OR NOT public.can_delete_occasion_in_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  IF EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND coalesce((data->>'client_sync_v1')::boolean,false)) THEN
    RAISE object_not_in_prerequisite_state USING MESSAGE='disable client_sync_v1 before deleting occasion'; END IF;
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,
    'occasion.delete',v_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.delete_occasion_internal_v1(p_occasion);
  DELETE FROM public.client_sync_scopes WHERE scope_type='occasion'
    AND scope_id=p_occasion;
  DELETE FROM public.client_projection_dirty_keys WHERE scope_type='occasion'
    AND scope_id=p_occasion;
  DELETE FROM public.client_aggregate_versions WHERE scope_type='occasion'
    AND scope_id=p_occasion;
  DELETE FROM public.client_sync_public_heads WHERE scope_type='occasion'
    AND scope_id=p_occasion;
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT v_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'occasion.delete','configuration' FROM public.user_info ui WHERE ui.id=v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'occasion',p_occasion::text,'delete',
    left(v_title,240),ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object('occasionId',p_occasion),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit.commit_id,'replayed',false,'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_occasion_domain_command_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
