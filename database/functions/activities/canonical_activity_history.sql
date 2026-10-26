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

-- A publication consumes the selected immutable draft row. Legacy publications
-- without a row token may clear only a draft containing the published graph.
CREATE OR REPLACE FUNCTION public.consume_selected_activity_draft_internal_v1(
 p_occasion bigint,p_actor uuid,p_parent bigint,p_selection jsonb,p_graph jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 DELETE FROM public.activity_history h WHERE h.occasion_id=p_occasion
  AND h.user_id=p_actor AND h.history_type='AUTOSAVE'
  AND CASE WHEN p_selection IS NULL THEN
   h.parent_history_id IS NOT DISTINCT FROM p_parent AND
   public.activity_history_graph_internal_v1(p_occasion,h.activities_data)=p_graph
  ELSE h.id=(p_selection->>'id')::bigint
   AND (p_selection->>'created_at' IS NULL OR h.created_at=(p_selection->>'created_at')::timestamptz)
  END;
 GET DIAGNOSTICS n=ROW_COUNT;
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.consume_selected_activity_draft_internal_v1(bigint,uuid,bigint,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
