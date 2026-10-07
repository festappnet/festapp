CREATE OR REPLACE FUNCTION public.record_account_deletion_sync_v1(p_user uuid, p_organization bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_commit public.client_commits%ROWTYPE; v_occasion bigint;
  v_revision bigint; v_event bigint; v_member uuid;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF p_user IS NULL OR p_organization IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.user_info ui
    WHERE ui.id=p_user AND ui.organization=p_organization) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid account deletion sync scope';
  END IF;
  FOR v_occasion IN SELECT DISTINCT dependency.occasion FROM (
 SELECT occasion FROM public.occasion_users WHERE "user"=p_user
 UNION SELECT gi.occasion FROM public.user_groups g JOIN public.user_group_info gi ON gi.id=g."group" WHERE g."user"=p_user
 UNION SELECT a.occasion FROM public.activity_assignments x JOIN public.activities a ON a.id=x.activity_id WHERE x."user"=p_user
 UNION SELECT occasion_id FROM public.activity_history WHERE user_id=p_user
) dependency JOIN public.occasions o ON o.id=dependency.occasion WHERE o.organization=p_organization ORDER BY dependency.occasion LOOP
    PERFORM public.lock_activity_aggregate_internal_v1(v_occasion);
  END LOOP;
  INSERT INTO public.client_commits
    (organization,actor_id,actor_display,actor_kind,source,change_class,reason)
  VALUES (p_organization,p_user,NULL,'service','account.delete','profile',
    'confirmed account deletion') RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'user',p_user::text,'delete',NULL,
    ARRAY['membership','profile','private_data']);
  FOR v_occasion IN SELECT DISTINCT dependency.occasion FROM (
 SELECT occasion FROM public.occasion_users WHERE "user"=p_user
 UNION SELECT gi.occasion FROM public.user_groups g JOIN public.user_group_info gi ON gi.id=g."group" WHERE g."user"=p_user
 UNION SELECT a.occasion FROM public.activity_assignments x JOIN public.activities a ON a.id=x.activity_id WHERE x."user"=p_user
 UNION SELECT occasion_id FROM public.activity_history WHERE user_id=p_user
) dependency JOIN public.occasions o ON o.id=dependency.occasion WHERE o.organization=p_organization ORDER BY dependency.occasion LOOP
    IF EXISTS (SELECT 1 FROM public.event_users eu JOIN public.events e
        ON e.id=eu.event WHERE eu."user"=p_user AND e.occasion=v_occasion)
      OR EXISTS (SELECT 1 FROM public.event_users_saved es JOIN public.events e
        ON e.id=es.event WHERE es."user"=p_user AND e.occasion=v_occasion) THEN
      INSERT INTO public.client_sync_scopes
        (component,scope_type,scope_id,source_revision)
      VALUES ('live_public','occasion',v_occasion,1)
      ON CONFLICT (component,scope_type,scope_id) DO UPDATE SET
        source_revision=public.client_sync_scopes.source_revision+1,
        updated_at=now() RETURNING source_revision INTO v_revision;
      INSERT INTO public.client_commit_components
        (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
      VALUES (v_commit.commit_id,'live_public','occasion',v_occasion,NULL,v_revision);
      FOR v_event IN SELECT DISTINCT id FROM (
        SELECT eu.event id FROM public.event_users eu JOIN public.events e
          ON e.id=eu.event WHERE eu."user"=p_user AND e.occasion=v_occasion
        UNION SELECT es.event FROM public.event_users_saved es JOIN public.events e
          ON e.id=es.event WHERE es."user"=p_user AND e.occasion=v_occasion
      ) affected ORDER BY id LOOP
        INSERT INTO public.client_projection_dirty_keys
          (component,scope_type,scope_id,entity_id,source_revision)
        VALUES ('live_public','occasion',v_occasion,v_event,v_revision)
        ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE SET
          source_revision=EXCLUDED.source_revision,dirty_since=now(),
          claimed_at=NULL,claim_token=NULL;
      END LOOP;
    END IF;
    IF EXISTS(SELECT 1 FROM public.activity_assignments aa JOIN public.activities a ON a.id=aa.activity_id WHERE a.occasion=v_occasion AND aa."user"=p_user) OR EXISTS(SELECT 1 FROM public.activity_history WHERE occasion_id=v_occasion AND user_id=p_user AND history_type='PUBLISH') THEN
      UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_occasion::text;
      FOR v_member IN SELECT "user" FROM public.occasion_users WHERE occasion=v_occasion AND "user"<>p_user ORDER BY "user" LOOP
        INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision) VALUES('private_activity',v_occasion,v_member,1) ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp() RETURNING source_revision INTO v_revision;
        INSERT INTO public.client_commit_components(commit_id,component,scope_type,scope_id,user_id,resulting_revision) VALUES(v_commit.commit_id,'private_activity','occasion',v_occasion,v_member,v_revision);
      END LOOP;
    END IF;
    FOR v_member IN SELECT ou."user" FROM public.occasion_users ou
      WHERE ou.occasion=v_occasion AND ou."user"<>p_user ORDER BY ou."user" LOOP
      INSERT INTO public.client_sync_private_scopes
        (component,occasion,user_id,source_revision)
      VALUES ('private_profile',v_occasion,v_member,1)
      ON CONFLICT (component,occasion,user_id) DO UPDATE SET
        source_revision=public.client_sync_private_scopes.source_revision+1,
        updated_at=now() RETURNING source_revision INTO v_revision;
      INSERT INTO public.client_commit_components
        (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
      VALUES (v_commit.commit_id,'private_profile','occasion',v_occasion,
        v_member,v_revision);
    END LOOP;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='user_group'
      AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id IN (
        SELECT ug."group"::text FROM public.user_groups ug
        WHERE ug."user"=p_user);
  END LOOP;
  RETURN v_commit.commit_id;
END; $function$
;
