-- Canonical owner recovered from the recorded effective main schema.
-- Public signatures, response envelopes and existing execution roles are preserved.

CREATE OR REPLACE FUNCTION public.delete_unit_user_internal_v1(usr uuid, unit_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    IF NOT public.can_manage_unit_users(unit_id) THEN
      RAISE insufficient_privilege USING MESSAGE='unit manager required';
    END IF;
    DELETE FROM unit_users
    WHERE "user" = usr AND unit = unit_id;

    UPDATE occasion_users
    SET is_editor = false,
        is_manager = false,
        is_editor_view = false
    WHERE "user" = usr
      AND occasion IN (SELECT id FROM occasions WHERE unit = unit_id);

    RETURN jsonb_build_object('code', 200);
END;
$function$
;
REVOKE ALL ON FUNCTION public.delete_unit_user_internal_v1(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.delete_unit_user_internal_v1(uuid,bigint) TO postgres;

CREATE OR REPLACE FUNCTION public.delete_unit_user_client_sync_v1(p_user uuid, p_unit bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_before jsonb;
  v_after jsonb; v_result jsonb; v_commit public.client_commits%ROWTYPE;

BEGIN
  IF v_actor IS NULL OR p_user IS NULL
    OR NOT public.can_manage_unit_users(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  PERFORM public.lock_people_scope_internal_v1(NULL,NULL,p_unit);
  PERFORM pg_catalog.pg_advisory_xact_lock(-p_unit);
  IF NOT public.can_manage_unit_users(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'unit',p_unit,'userId',p_user)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,
    'profile.unit_access.delete',p_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT jsonb_build_object('unitUser',(SELECT to_jsonb(uu)
      FROM public.unit_users uu WHERE uu.unit=p_unit AND uu."user"=p_user),
    'occasionUsers',COALESCE((SELECT jsonb_agg(to_jsonb(ou) ORDER BY ou.occasion)
      FROM public.occasion_users ou JOIN public.occasions o ON o.id=ou.occasion
      WHERE o.unit=p_unit AND ou."user"=p_user),'[]'::jsonb)) INTO v_before;
  v_result:=public.delete_unit_user_internal_v1(p_user,p_unit);
  SELECT jsonb_build_object('unitUser',(SELECT to_jsonb(uu)
      FROM public.unit_users uu WHERE uu.unit=p_unit AND uu."user"=p_user),
    'occasionUsers',COALESCE((SELECT jsonb_agg(to_jsonb(ou) ORDER BY ou.occasion)
      FROM public.occasion_users ou JOIN public.occasions o ON o.id=ou.occasion
      WHERE o.unit=p_unit AND ou."user"=p_user),'[]'::jsonb)) INTO v_after;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('userId',p_user)); END IF;
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT p_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'profile.unit_access.delete','profile' FROM public.user_info ui
    WHERE ui.id=v_actor RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'unit_user',p_user::text,'delete','Unit access',
    ARRAY['rights']);
  PERFORM public.publish_unit_user_access_change_internal_v1(v_commit.commit_id,p_unit,p_user);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object('userId',p_user),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit.commit_id,'replayed',false,'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_unit_user_client_sync_v1(uuid,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.delete_unit_user_client_sync_v1(uuid,bigint,uuid) TO postgres,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.delete_unit_user(usr uuid, unit_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_response jsonb;
BEGIN
  v_response:=public.delete_unit_user_client_sync_v1(
    usr,unit_id,extensions.gen_random_uuid());
  RETURN jsonb_build_object('code',(v_response->>'code')::integer)
    ||COALESCE(v_response->'data','{}'::jsonb);
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_unit_user(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.delete_unit_user(uuid,bigint) TO postgres,authenticated,service_role;
