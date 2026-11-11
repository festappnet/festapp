-- Shared membership primitive. Profile and role persistence remain specialized.
CREATE OR REPLACE FUNCTION public.ensure_unit_membership_internal_v1(p_unit bigint,p_user uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE inserted integer;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(NULL,NULL,p_unit);
 IF NOT public.can_manage_unit_users(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(-p_unit);
 IF NOT public.can_manage_unit_users(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.user_info ui JOIN public.units u ON u.organization=ui.organization
   WHERE ui.id=p_user AND u.id=p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='member identity unavailable in unit'; END IF;
 INSERT INTO public.unit_users(unit,"user",is_editor,is_editor_view,is_manager)
 VALUES(p_unit,p_user,false,false,false) ON CONFLICT(unit,"user") DO NOTHING;
 GET DIAGNOSTICS inserted=ROW_COUNT;
 RETURN inserted=1;
END $$;
REVOKE ALL ON FUNCTION public.ensure_unit_membership_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.add_user_to_unit_client_sync_v1(p_unit bigint,p_user uuid,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE initial jsonb; c public.client_commits%ROWTYPE; ver bigint;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(NULL,NULL,p_unit);
 IF NOT public.can_manage_unit_users(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(-p_unit);
 initial:=public.begin_unit_client_mutation_v1(p_command_id,'profile.unit_membership.add',p_unit,auth.uid(),
  encode(extensions.digest(jsonb_build_object('unit',p_unit,'user',p_user)::text,'sha256'),'hex'));
 IF initial->>'disposition'='replay' THEN RETURN initial->'response'; END IF;
 IF NOT public.ensure_unit_membership_internal_v1(p_unit,p_user) THEN
  SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
   ON v.aggregate_type='unit_user' AND v.scope_type='unit' AND v.scope_id=p_unit AND v.aggregate_id=p_user::text;
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
   jsonb_build_object('userId',p_user,'version',ver,'reasonCode','already_member'));
 END IF;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('unit_user','unit',p_unit,p_user::text,1)
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
 SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp() RETURNING version INTO ver;
 INSERT INTO public.client_commits(unit,actor_id,actor_display,actor_kind,source,change_class)
 SELECT p_unit,auth.uid(),nullif(concat_ws(' ',ui.name,ui.surname),''),'user','profile.unit_membership.add','profile'
 FROM public.user_info ui WHERE ui.id=auth.uid() RETURNING * INTO c;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 VALUES(c.commit_id,0,'unit_user',p_user::text,'insert','Organizer membership',ARRAY['membership']);
 PERFORM public.publish_unit_user_access_change_internal_v1(c.commit_id,p_unit,p_user);
 PERFORM public.fanout_unit_catalog_v1(c.commit_id,p_unit);
 RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object('status','applied','code',200,
  'data',jsonb_build_object('userId',p_user,'version',ver),
  'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,'commitId',c.commit_id,
   'replayed',false,'occurredAt',c.occurred_at),'sync',jsonb_build_object('replacements','[]'::jsonb)),c.commit_id);
END $$;
REVOKE ALL ON FUNCTION public.add_user_to_unit_client_sync_v1(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.add_user_to_unit_client_sync_v1(bigint,uuid,uuid) TO authenticated,service_role;
