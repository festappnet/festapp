-- Released legacy shapes remain adapters; the canonical lifecycle owns every write.
-- Two-step live publication cannot preserve atomicity and requires an upgrade.
CREATE OR REPLACE FUNCTION public.update_activities(p_occasion_id bigint,p_activities_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.can_write_activity_plan(p_occasion_id),false) THEN
  RETURN jsonb_build_object('code',403); END IF;
 RETURN jsonb_build_object('code',426,'message','Upgrade required for atomic activity publication');
END $$;
CREATE OR REPLACE FUNCTION public.save_activity_history(
 p_occasion_id bigint,p_activities_data jsonb,p_history_type text,p_parent_history_id bigint,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE version bigint; result jsonb; canonical_history jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.can_write_activity_plan(p_occasion_id),false) THEN
  RETURN jsonb_build_object('code',403); END IF;
 IF p_history_type IS DISTINCT FROM 'AUTOSAVE' THEN
  RETURN jsonb_build_object('code',426,'message','Upgrade required for atomic activity publication'); END IF;
 version:=public.lock_activity_editor_internal_v1(p_occasion_id);
 canonical_history:=public.activity_graph_history_internal_v1(
  public.activity_history_graph_internal_v1(p_occasion_id,p_activities_data));
 result:=public.save_activity_draft_client_sync_v1(p_occasion_id,extensions.gen_random_uuid(),version,canonical_history,p_parent_history_id);
 RETURN jsonb_build_object('code',result->'code','message',result->>'status','data',
  jsonb_build_object('historyId',result#>'{data,draftId}',
   'created_at',(SELECT created_at FROM public.activity_history WHERE id=(result#>>'{data,draftId}')::bigint),
   'latest_publish_id',result#>'{data,latestPublishId}'));
END $$;
CREATE OR REPLACE FUNCTION public.delete_autosave_history(p_occasion_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE draft bigint; result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.can_write_activity_plan(p_occasion_id),false) THEN
  RETURN jsonb_build_object('code',403); END IF;
 PERFORM public.lock_activity_editor_internal_v1(p_occasion_id);
 SELECT id INTO draft FROM public.activity_history WHERE occasion_id=p_occasion_id
  AND user_id=auth.uid() AND history_type='AUTOSAVE' ORDER BY id DESC LIMIT 1;
 result:=public.discard_activity_draft_client_sync_v1(p_occasion_id,extensions.gen_random_uuid(),draft);
 RETURN jsonb_build_object('code',result->'code','message',result->>'status');
END $$;
REVOKE ALL ON FUNCTION public.update_activities(bigint,jsonb),public.save_activity_history(bigint,jsonb,text,bigint,text),public.delete_autosave_history(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_activities(bigint,jsonb),public.save_activity_history(bigint,jsonb,text,bigint,text),public.delete_autosave_history(bigint)
 TO authenticated;
