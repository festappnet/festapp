CREATE OR REPLACE FUNCTION public.write_activity_history_internal_v1(p_occasion bigint,p_actor uuid,p_data jsonb,p_type text,p_parent bigint,p_note text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE hid bigint;
BEGIN
 IF p_type NOT IN ('AUTOSAVE','PUBLISH') OR (p_parent IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.activity_history WHERE id=p_parent AND occasion_id=p_occasion AND history_type='PUBLISH')) THEN RAISE invalid_parameter_value USING MESSAGE='invalid history parent or type'; END IF;
 IF p_type='AUTOSAVE' THEN PERFORM public.clear_activity_draft_internal_v1(p_occasion,p_actor,NULL,false); END IF;
 INSERT INTO public.activity_history(occasion_id,user_id,activities_data,history_type,note,parent_history_id) VALUES(p_occasion,p_actor,p_data,p_type,p_note,p_parent) RETURNING id INTO hid;
 RETURN hid;
END $$;
CREATE OR REPLACE FUNCTION public.clear_activity_draft_internal_v1(p_occasion bigint,p_actor uuid,p_parent bigint,p_check_parent boolean)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n int;
BEGIN
 DELETE FROM public.activity_history WHERE occasion_id=p_occasion AND user_id=p_actor AND history_type='AUTOSAVE' AND (NOT p_check_parent OR parent_history_id IS NOT DISTINCT FROM p_parent);
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.write_activity_history_internal_v1(bigint,uuid,jsonb,text,bigint,text),public.clear_activity_draft_internal_v1(bigint,uuid,bigint,boolean) FROM PUBLIC,anon,authenticated;
-- Exact released contracts remain callable until G3. Split legacy publish remains unsafe.
CREATE OR REPLACE FUNCTION public.save_activity_history(p_occasion_id bigint,p_activities_data jsonb,p_history_type text,p_parent_history_id bigint,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE latest bigint; published_at timestamptz;
BEGIN
 IF NOT public.get_is_editor_on_occasion(p_occasion_id) THEN RETURN jsonb_build_object('code',403,'message','User is not authorized to edit this occasion'); END IF;
 PERFORM public.lock_activity_editor_internal_v1(p_occasion_id);
 SELECT id,created_at INTO latest,published_at FROM public.activity_history WHERE occasion_id=p_occasion_id AND history_type='PUBLISH' ORDER BY id DESC LIMIT 1;
 IF p_history_type='AUTOSAVE' AND p_parent_history_id IS DISTINCT FROM latest THEN RETURN jsonb_build_object('code',409,'message','A new version has been published. Please reload or rebase your changes.','data',jsonb_build_object('latest_publish_id',latest,'published_at',published_at)); END IF;
 PERFORM public.write_activity_history_internal_v1(p_occasion_id,auth.uid(),p_activities_data,p_history_type,p_parent_history_id,p_note);
 PERFORM public.retain_activity_history_internal_v1(p_occasion_id);
 RETURN jsonb_build_object('code',200,'message','History saved successfully.');
EXCEPTION WHEN others THEN RETURN jsonb_build_object('code',500,'message','Error saving history: '||SQLERRM);
END $$;
CREATE OR REPLACE FUNCTION public.delete_autosave_history(p_occasion_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.get_is_editor_on_occasion(p_occasion_id) THEN RETURN jsonb_build_object('code',403,'message','User is not authorized'); END IF;
 PERFORM public.lock_activity_editor_internal_v1(p_occasion_id);
 PERFORM public.clear_activity_draft_internal_v1(p_occasion_id,auth.uid(),NULL,false);
 RETURN jsonb_build_object('code',200,'message','Autosave history has been cleared successfully.');
END $$;
