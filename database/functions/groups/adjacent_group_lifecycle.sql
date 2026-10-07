CREATE OR REPLACE FUNCTION public.advance_group_profile_heads_internal_v1(p_occasion bigint,p_users uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
 SELECT 'private_profile',p_occasion,(x->>'userId')::uuid,1 FROM jsonb_array_elements(public.group_profile_impacts_internal_v1(p_occasion,p_users)) x ORDER BY x->>'userId'
 ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();
END $$;
REVOKE ALL ON FUNCTION public.advance_group_profile_heads_internal_v1(bigint,uuid[]) FROM PUBLIC,anon,authenticated;
-- Adjacent lifecycle owners: only group lock/version seam corrections.
CREATE OR REPLACE FUNCTION public.import_profiles_client_sync_v1(p_occasion bigint, p_command_id uuid, p_rows jsonb, p_delete_user_ids jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_unit bigint;
  v_result jsonb; v_before_users uuid[]; v_after_users uuid[]; v_current_users uuid[];
  v_event_ids bigint[]; v_group_ids bigint[]; v_private_impacts jsonb;
  v_publishable boolean; v_actor_replacements jsonb:='[]'::jsonb; v_before_state jsonb; v_after_state jsonb; v_old_impacts jsonb;
BEGIN
  SELECT o.unit,NOT o.is_hidden INTO v_unit,v_publishable
    FROM public.occasions o WHERE o.id=p_occasion;
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='profile import permission required'; END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array'
    OR p_delete_user_ids IS NULL OR jsonb_typeof(p_delete_user_ids)<>'array'
    OR jsonb_array_length(p_rows)>10000 OR jsonb_array_length(p_delete_user_ids)>10000
    OR octet_length(p_rows::text)+octet_length(p_delete_user_ids::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid profile import'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'rows',p_rows,'deleteUserIds',p_delete_user_ids)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.users.import',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  IF NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR public.get_is_editor_on_unit(v_unit)) THEN RAISE insufficient_privilege USING MESSAGE='profile import permission required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM 1 FROM public.user_group_info g WHERE g.occasion=p_occasion
    ORDER BY g.id FOR UPDATE;
  v_before_state:=public.profile_group_import_state_internal_v1(p_occasion);
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT e.id),'{}'::bigint[]) INTO v_event_ids
    FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
    LEFT JOIN public.event_users_saved es ON es.event=e.id
    WHERE e.occasion=p_occasion AND (eu."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))) OR
      es."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))));
  SELECT COALESCE(array_agg(DISTINCT ug."group"),'{}'::bigint[]) INTO v_group_ids
    FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
    JOIN public.user_info ui ON ui.id=ug."user"
    WHERE g.occasion=p_occasion AND (ug."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))) OR ug."user"=ANY(
      COALESCE((SELECT array_agg((row->>'user_id')::uuid)
        FROM jsonb_array_elements(p_rows) row
        WHERE NULLIF(row->>'user_id','') IS NOT NULL),'{}'::uuid[])) OR
      lower(btrim(ui.email_readonly))=ANY(COALESCE((SELECT array_agg(
        lower(btrim(row#>>'{data,email}'))) FROM jsonb_array_elements(p_rows) row),
        '{}'::text[])));
  v_old_impacts:=public.group_profile_impacts_internal_v1(p_occasion,ARRAY(
    SELECT DISTINCT id FROM (
      SELECT value::uuid id FROM jsonb_array_elements_text(p_delete_user_ids)
      UNION SELECT ug."user" FROM public.user_groups ug WHERE ug."group"=ANY(v_group_ids)
      UNION SELECT ou."user" FROM public.occasion_users ou JOIN public.user_info ui ON ui.id=ou."user" WHERE ou.occasion=p_occasion AND (ou."user"=ANY(ARRAY(SELECT (row->>'user_id')::uuid FROM jsonb_array_elements(p_rows) row WHERE NULLIF(row->>'user_id','') IS NOT NULL)) OR lower(btrim(ui.email_readonly))=ANY(ARRAY(SELECT lower(btrim(row#>>'{data,email}')) FROM jsonb_array_elements(p_rows) row)))
    ) impacted));
  v_private_impacts:=public.remove_user_activity_internal_v1(p_occasion,ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(p_delete_user_ids)));
  v_result:=public.import_occasion_users_from_csv_internal_v1(
    p_occasion,p_rows,p_delete_user_ids);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE data_exception USING MESSAGE=COALESCE(v_result->>'message','profile import failed');
  END IF;
  v_after_state:=public.profile_group_import_state_internal_v1(p_occasion);
  IF v_before_state=v_after_state THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,v_result); END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_after_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT ou."user" ORDER BY ou."user"),'{}'::uuid[])
    INTO v_current_users FROM public.occasion_users ou
    JOIN public.user_info ui ON ui.id=ou."user"
    WHERE ou.occasion=p_occasion AND (ou."user"=ANY(COALESCE((SELECT array_agg(
      (row->>'user_id')::uuid) FROM jsonb_array_elements(p_rows) row
      WHERE NULLIF(row->>'user_id','') IS NOT NULL),'{}'::uuid[])) OR
      lower(btrim(COALESCE(ui.email_readonly,ou.data->>'email')))=ANY(COALESCE((
        SELECT array_agg(lower(btrim(row#>>'{data,email}')))
        FROM jsonb_array_elements(p_rows) row),'{}'::text[])) OR
      NOT ou."user"=ANY(v_before_users));
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_group_ids||COALESCE((
    SELECT array_agg(DISTINCT ug."group") FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    WHERE g.occasion=p_occasion AND ug."user"=ANY(v_current_users)),
    '{}'::bigint[])) id ORDER BY id) INTO v_group_ids;
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_current_users||COALESCE((
    SELECT array_agg(DISTINCT ug."user") FROM public.user_groups ug
    WHERE ug."group"=ANY(v_group_ids)),'{}'::uuid[])) id
    JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id
    ORDER BY id) INTO v_current_users;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'occasion_user','occasion',p_occasion,id::text,1
    FROM unnest(v_current_users) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'user_group','occasion',p_occasion,key,1 FROM jsonb_each(v_after_state->'groups') WHERE value IS DISTINCT FROM v_before_state->'groups'->key
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  DELETE FROM public.client_aggregate_versions v WHERE v.aggregate_type='occasion_user'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=ANY(ARRAY(SELECT value FROM jsonb_array_elements_text(
      p_delete_user_ids)));
  v_private_impacts:=v_private_impacts||v_old_impacts||public.group_profile_impacts_internal_v1(p_occasion,v_current_users);
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'component',x->>'userId'),'[]') INTO v_private_impacts FROM (SELECT DISTINCT value x FROM jsonb_array_elements(v_private_impacts) WHERE EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=(value->>'userId')::uuid)) current_impacts;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'component'='private_profile' AND x->>'userId'=v_actor::text) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.users.import','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',NULL,'operation','import',
      'safeLabel','Profile CSV import','changedFields',jsonb_build_array('profiles','services','groups'))),
    CASE WHEN cardinality(v_event_ids)>0 AND v_publishable
      THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    v_private_impacts,CASE WHEN cardinality(v_event_ids)>0 AND v_publishable
      THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'component','live_public','entityId',id)) FROM unnest(v_event_ids) id),'[]'::jsonb)
      ELSE '[]'::jsonb END,v_result,'{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
CREATE OR REPLACE FUNCTION public.delete_occasion_user_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_profile jsonb; v_event_ids bigint[]; v_group_ids bigint[];
  v_private_impacts jsonb; v_publishable boolean;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'userId',p_user,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.user.delete',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  IF NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion)) THEN RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'unchanged',200,jsonb_build_object('version',0,'profile',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,p_user::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='occasion_user' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_user::text FOR UPDATE;
  v_profile:=public.get_occasion_user_command_data_v1(p_occasion,p_user);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'profile',v_profile)); END IF;
  SELECT COALESCE(array_agg(DISTINCT e.id),'{}'::bigint[]) INTO v_event_ids
  FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
  LEFT JOIN public.event_users_saved es ON es.event=e.id
  WHERE e.occasion=p_occasion AND (eu."user"=p_user OR es."user"=p_user);
  SELECT COALESCE(array_agg(ug."group"),'{}'::bigint[]) INTO v_group_ids
  FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
  WHERE ug."user"=p_user AND g.occasion=p_occasion;
  v_private_impacts:=public.remove_occasion_user_domain_internal_v1(p_occasion,p_user);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_private_impacts) impact
    WHERE impact->>'userId'=v_actor::text) THEN
    v_actor_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.user.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation','delete',
      'safeLabel','Occasion user','changedFields',jsonb_build_array('membership'))),
    CASE WHEN v_publishable AND cardinality(v_event_ids)>0 THEN ARRAY['live_public']
      ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_publishable THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',id)) FROM unnest(v_event_ids) id),'[]'::jsonb)
      ELSE '[]'::jsonb END,
    jsonb_build_object('version',v_version,'profile',NULL),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
CREATE OR REPLACE FUNCTION public.delete_owned_companion_internal_v1(p_occasion bigint, p_companion uuid, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_event_ids bigint[];
  v_group_ids bigint[]; v_private_impacts jsonb; v_replacements jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR p_companion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid companion delete'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_companions uc
    JOIN public.occasion_users ou ON ou."user"=uc.companion AND ou.occasion=p_occasion
    WHERE uc."user"=v_actor AND uc.companion=p_companion) THEN
    RAISE insufficient_privilege USING MESSAGE='companion owner required'; END IF;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou
    WHERE ou."user"=p_companion AND ou.occasion<>p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='cross-occasion companion requires manual cleanup'; END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'companion',p_companion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.delete',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-owner:'||v_actor::text||':'||p_occasion::text,0));
  PERFORM 1 FROM public.user_info ui WHERE ui.id=p_companion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('companion',NULL)); END IF;
  SELECT COALESCE(array_agg(DISTINCT event_id ORDER BY event_id),'{}'::bigint[])
    INTO v_event_ids FROM (
      SELECT eu.event event_id FROM public.event_users eu JOIN public.events e
        ON e.id=eu.event WHERE eu."user"=p_companion AND e.occasion=p_occasion
      UNION SELECT es.event FROM public.event_users_saved es JOIN public.events e
        ON e.id=es.event WHERE es."user"=p_companion AND e.occasion=p_occasion
    ) affected;
  SELECT COALESCE(array_agg(ug."group" ORDER BY ug."group"),'{}'::bigint[])
    INTO v_group_ids FROM public.user_groups ug JOIN public.user_group_info g
      ON g.id=ug."group" WHERE ug."user"=p_companion AND g.occasion=p_occasion;
  PERFORM 1 FROM public.events e WHERE e.id=ANY(v_event_ids) ORDER BY e.id FOR UPDATE;
  PERFORM 1 FROM public.user_group_info g WHERE g.id=ANY(v_group_ids) ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',impacted.user_id)),'[]'::jsonb) INTO v_private_impacts FROM (
      SELECT v_actor user_id UNION SELECT ug."user" FROM public.user_groups ug
        WHERE ug."group"=ANY(v_group_ids) AND ug."user"<>p_companion
    ) impacted JOIN public.occasion_users ou ON ou.occasion=p_occasion
      AND ou."user"=impacted.user_id;
  v_private_impacts:=v_private_impacts||public.remove_user_activity_internal_v1(p_occasion,ARRAY[p_companion]);
  UPDATE public.news SET created_by=NULL WHERE created_by=p_companion;
  DELETE FROM public.user_groups WHERE "user"=p_companion;
  DELETE FROM public.event_users WHERE "user"=p_companion;
  DELETE FROM public.user_news WHERE "user"=p_companion;
  DELETE FROM public.event_users_saved WHERE "user"=p_companion;
  DELETE FROM public.occasion_users WHERE "user"=p_companion;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=p_companion::text;
  DELETE FROM public.user_reset_token WHERE "user"=p_companion;
  DELETE FROM public.user_companions WHERE "user"=p_companion OR companion=p_companion;
  DELETE FROM public.user_info WHERE id=p_companion;
  DELETE FROM auth.identities WHERE user_id=p_companion;
  DELETE FROM auth.users WHERE id=p_companion;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(v_group_ids) id));
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.companion.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','companion','entityId',p_companion,'operation','delete',
      'safeLabel','Companion','changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND cardinality(v_event_ids)>0
      THEN ARRAY['live_public'] ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_is_publishable THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',event_id)) FROM unnest(v_event_ids) event_id),
      '[]'::jsonb) ELSE '[]'::jsonb END,
    jsonb_build_object('companion',NULL),'{}','[]','user',NULL,v_replacements);
END; $function$
;
CREATE OR REPLACE FUNCTION public.game_guess_client_sync_v1(p_checkpoint bigint, p_guess text, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_group bigint;
  v_begin jsonb; v_hash text; v_result jsonb; v_before jsonb; v_after jsonb;
  v_version bigint; v_impacts jsonb; v_replacements jsonb;
  v_domain_code integer;
BEGIN
  SELECT ih.occasion INTO v_occasion FROM public.information i
    JOIN public.information_hidden ih ON ih.id=i.information_hidden
    WHERE i.id=p_checkpoint;
  IF v_actor IS NULL OR v_occasion IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='occasion participant required'; END IF;
  SELECT ug."group" INTO v_group FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    WHERE ug."user"=v_actor AND g.occasion=v_occasion AND g.type='game'
    ORDER BY g.id LIMIT 1;
  IF v_group IS NULL THEN RAISE insufficient_privilege USING MESSAGE='game group required'; END IF;
  IF p_guess IS NULL OR length(p_guess)>2000 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid game guess'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'checkpoint',p_checkpoint,'guess',p_guess)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.game.guess',
    v_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(v_occasion);
  IF NOT EXISTS(SELECT 1 FROM public.user_groups WHERE "group"=v_group AND "user"=v_actor) THEN RAISE insufficient_privilege USING MESSAGE='game group required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.user_groups WHERE "group"=v_group AND "user"=v_actor) THEN RAISE insufficient_privilege USING MESSAGE='game group required'; END IF;
  SELECT g.data INTO v_before FROM public.user_group_info g WHERE g.id=v_group FOR UPDATE;
  v_result:=public.game_guess_internal_v1(p_checkpoint,p_guess);
  v_domain_code:=COALESCE((v_result->>'code')::integer,500);
  IF v_domain_code<>200 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',CASE WHEN v_domain_code BETWEEN 4030 AND 4039 THEN 403
      WHEN v_domain_code BETWEEN 4040 AND 4049 THEN 404 ELSE 400 END,
    jsonb_build_object('domainCode',v_domain_code,'message',v_result->>'message'));
  END IF;
  SELECT g.data INTO v_after FROM public.user_group_info g WHERE g.id=v_group;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('user_group','occasion',v_occasion,v_group::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='user_group' AND scope_type='occasion'
      AND scope_id=v_occasion AND aggregate_id=v_group::text FOR UPDATE;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('domainCode',200,'correct',true,'version',v_version)); END IF;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_group::text
    RETURNING version INTO v_version;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',ug."user")),'[]'::jsonb) INTO v_impacts FROM public.user_groups ug
    WHERE ug."group"=v_group;
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(v_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'profile.game.guess','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',v_group,'operation','update',
      'safeLabel','Game checkpoint','changedFields',jsonb_build_array('game'))),
    '{}',v_impacts,'[]',jsonb_build_object('domainCode',200,'correct',true,
      'version',v_version),'{}','[]','user',NULL,v_replacements);
END; $function$
;
