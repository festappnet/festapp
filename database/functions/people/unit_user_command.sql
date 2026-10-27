-- Receipt boundary around the existing organizer-user persistence owner.
CREATE OR REPLACE FUNCTION public.save_unit_user_client_sync_v1(p_unit bigint,p_user uuid,p_command_id uuid,p_expected_version bigint,p_changes jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE initial jsonb; current_user_row jsonb; after_row jsonb; result jsonb; usr uuid:=p_user; ver bigint;
 c public.client_commits%ROWTYPE; intent jsonb; mode text;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(NULL,NULL,p_unit);
 IF NOT public.can_manage_unit_users(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 IF jsonb_typeof(p_changes) IS DISTINCT FROM 'object' OR octet_length(p_changes::text)>131072 THEN RAISE invalid_parameter_value USING MESSAGE='invalid organizer user'; END IF;
 mode:=p_changes->>'kind';
 IF mode='roles' THEN
  IF usr IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_changes) k WHERE k NOT IN ('kind','is_manager','is_editor','is_editor_view'))
    OR EXISTS(SELECT 1 FROM jsonb_each(p_changes-'kind') x WHERE jsonb_typeof(x.value)<>'boolean') THEN
   RAISE invalid_parameter_value USING MESSAGE='explicit organizer roles required'; END IF;
 ELSIF mode='profile' THEN
  PERFORM public.prepare_profile_change_internal_v1('{}',jsonb_build_object('profileChange',p_changes-'kind'));
 ELSIF mode IS DISTINCT FROM 'editor' THEN RAISE invalid_parameter_value USING MESSAGE='unknown organizer user intent';
 END IF;
 initial:=public.begin_unit_client_mutation_v1(p_command_id,'profile.unit_user.save',p_unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('unit',p_unit,'user',p_user,'version',p_expected_version,'changes',p_changes)::text,'UTF8'),'sha256'),'hex'));
 IF initial->>'disposition'='replay' THEN RETURN initial->'response'; END IF;
 -- Serialize creation, update and revocation for this organizer. Existing UI
 -- callers also enter this owner through the released update_unit_user facade.
 PERFORM pg_catalog.pg_advisory_xact_lock(-p_unit);
 IF NOT public.can_manage_unit_users(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 IF usr IS NOT NULL THEN
  PERFORM 1 FROM public.user_info WHERE id=usr FOR UPDATE;
  SELECT to_jsonb(uu) INTO current_user_row FROM public.unit_users uu WHERE uu.unit=p_unit AND uu."user"=usr FOR UPDATE;
  IF current_user_row IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',404,'{}'); END IF;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
   VALUES('unit_user','unit',p_unit,usr::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO ver FROM public.client_aggregate_versions WHERE aggregate_type='unit_user' AND scope_type='unit' AND scope_id=p_unit AND aggregate_id=usr::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM ver THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('version',ver)); END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM public.unit_users uu JOIN public.user_info ui ON ui.id=uu."user" WHERE uu.unit=p_unit AND lower(btrim(ui.email_readonly))=lower(btrim(p_changes#>>'{data,email}'))) THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,'{}'); END IF;
  IF mode<>'editor' THEN RAISE invalid_parameter_value USING MESSAGE='creation uses organizer editor'; END IF;
 END IF;
 IF mode='editor' THEN
  intent:=(p_changes-'kind')||jsonb_build_object('unit',p_unit,'user',usr);
  -- Omitted metadata must survive ordinary grid saves.
  intent:=jsonb_set(intent,'{data}',coalesce(nullif(current_user_row->'data','null'::jsonb),'{}')||coalesce(nullif(intent->'data','null'::jsonb),'{}'));
 ELSE
  intent:=coalesce(current_user_row,'{}')||jsonb_build_object('unit',p_unit,'user',usr);
  IF mode='roles' THEN intent:=intent||(p_changes-'kind');
  ELSE intent:=intent||jsonb_build_object('data',coalesce(nullif(current_user_row->'data','null'::jsonb),'{}')||(p_changes-'kind'));
  END IF;
 END IF;
 result:=public.update_unit_user_internal_v1(intent);
 IF coalesce((result->>'code')::int,500) NOT IN(200,201) THEN
  -- The legacy persistence function catches exceptions in its own subtransaction.
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',coalesce((result->>'code')::int,400),'{}'); END IF;
 usr:=(result->>'user')::uuid;
 SELECT to_jsonb(uu) INTO after_row FROM public.unit_users uu WHERE uu.unit=p_unit AND uu."user"=usr;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('unit_user','unit',p_unit,usr::text,1) ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id)
  DO UPDATE SET version=client_aggregate_versions.version+1,updated_at=clock_timestamp() RETURNING version INTO ver;
 INSERT INTO public.client_commits(unit,actor_id,actor_display,actor_kind,source,change_class)
 SELECT p_unit,auth.uid(),nullif(concat_ws(' ',ui.name,ui.surname),''),'user','profile.unit_user.save','profile' FROM public.user_info ui WHERE ui.id=auth.uid() RETURNING * INTO c;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 VALUES(c.commit_id,0,'unit_user',usr::text,CASE WHEN p_user IS NULL THEN 'insert' ELSE 'update' END,'Organizer membership',ARRAY[mode]);
 IF current_user_row->'is_manager' IS DISTINCT FROM after_row->'is_manager'
  OR current_user_row->'is_editor' IS DISTINCT FROM after_row->'is_editor'
  OR current_user_row->'is_editor_view' IS DISTINCT FROM after_row->'is_editor_view' THEN
  PERFORM public.publish_unit_user_access_change_internal_v1(c.commit_id,p_unit,usr);
 END IF;
 PERFORM public.fanout_unit_catalog_v1(c.commit_id,p_unit);
 RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object('status','applied','code',200,'data',jsonb_build_object('userId',usr,'version',ver),
  'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,'commitId',c.commit_id,'replayed',false,'occurredAt',c.occurred_at),
  'sync',jsonb_build_object('replacements','[]'::jsonb)),c.commit_id);
END $$;
REVOKE ALL ON FUNCTION public.save_unit_user_client_sync_v1(bigint,uuid,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_unit_user_client_sync_v1(bigint,uuid,uuid,bigint,jsonb) TO authenticated,service_role;

-- Released clients use the same owner; only they may obtain an implicit baseline.
CREATE OR REPLACE FUNCTION public.update_unit_user(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE uid uuid:=(input_data->>'user')::uuid; unit_id bigint:=(input_data->>'unit')::bigint; ver bigint; result jsonb;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(NULL,NULL,unit_id);
 IF NOT public.can_manage_unit_users(unit_id) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(-unit_id);
 SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='unit_user' AND v.scope_type='unit' AND v.scope_id=unit_id AND v.aggregate_id=uid::text;
 result:=public.save_unit_user_client_sync_v1(unit_id,uid,extensions.gen_random_uuid(),ver,(input_data-'unit'-'user')||'{"kind":"editor"}');
 RETURN jsonb_build_object('code',result->'code','user',result#>'{data,userId}');
END $$;
REVOKE ALL ON FUNCTION public.update_unit_user(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_unit_user(jsonb) TO authenticated,service_role;
