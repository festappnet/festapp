-- Fixed compatibility adapters. No direct membership/group/map implementation.
CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv(
 p_occasion_id bigint,p_rows jsonb,p_delete_user_ids jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.import_profiles_client_sync_v1(p_occasion_id,extensions.gen_random_uuid(),p_rows,p_delete_user_ids);
 RETURN jsonb_build_object('code',result->'code')||result->'data';
EXCEPTION WHEN insufficient_privilege THEN RAISE EXCEPTION 'NOT_AUTHORIZED';
END $$;
CREATE OR REPLACE FUNCTION public.import_user_group_assignments(p_occasion_id bigint,p_assignments jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.replace_group_assignments_client_sync_v1(p_occasion_id,extensions.gen_random_uuid(),p_assignments);
EXCEPTION WHEN insufficient_privilege THEN RAISE EXCEPTION 'NOT_AUTHORIZED';
END $$;
-- Existing trusted reception/import callers retain their own admission.
CREATE OR REPLACE FUNCTION public.delete_occasion_user(usr uuid,oc bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN PERFORM public.remove_occasion_user_domain_internal_v1(oc,usr); END $$;
CREATE OR REPLACE FUNCTION public.delete_occasion_user_ws(usr_to_delete uuid,occasion_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE version bigint; result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_manage_occasion_participants(occasion_id) THEN
  RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
 PERFORM 1 FROM public.user_info WHERE id=usr_to_delete FOR UPDATE;
 PERFORM public.lock_activity_aggregate_internal_v1(occasion_id);
 SELECT coalesce(v.version,0) INTO version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='occasion_user' AND v.scope_type='occasion' AND v.scope_id=occasion_id AND v.aggregate_id=usr_to_delete::text;
 result:=public.delete_occasion_user_client_sync_v1(occasion_id,usr_to_delete,extensions.gen_random_uuid(),version);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'Profile deletion rejected'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.save_place_location(p_place_id bigint,p_lat double precision,p_lng double precision)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; version bigint; result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('code',401); END IF;
 SELECT occasion INTO oc FROM public.places WHERE id=p_place_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404); END IF;
 IF NOT public.can_move_map_place(oc,p_place_id) THEN
  RETURN jsonb_build_object('code',403); END IF;
 PERFORM public.lock_group_occasion_internal_v1(oc);
 SELECT coalesce(v.version,0) INTO version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='place' AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=p_place_id::text;
 BEGIN
  result:=public.move_place_client_sync_v1(oc,p_place_id,extensions.gen_random_uuid(),version,p_lat,p_lng);
 EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('code',403); END;
 RETURN jsonb_build_object('code',result->'code','data',jsonb_build_object('id',p_place_id));
END $$;
CREATE OR REPLACE FUNCTION public.game_guess(check_point_id bigint,guess text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.game_guess_client_sync_v1(check_point_id,guess,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code')||result->'data';
END $$;
REVOKE ALL ON FUNCTION public.delete_occasion_user(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.import_occasion_users_from_csv(bigint,jsonb,jsonb),public.import_user_group_assignments(bigint,jsonb),public.delete_occasion_user_ws(uuid,bigint),public.save_place_location(bigint,double precision,double precision),public.game_guess(bigint,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.import_occasion_users_from_csv(bigint,jsonb,jsonb),public.import_user_group_assignments(bigint,jsonb),public.delete_occasion_user_ws(uuid,bigint),public.save_place_location(bigint,double precision,double precision),public.game_guess(bigint,text)
 TO authenticated;
