CREATE OR REPLACE FUNCTION public.get_activity_editor_session_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT CASE WHEN auth.uid() IS NULL OR NOT (public.get_is_editor_view_on_occasion(p_occasion) OR public.get_is_editor_on_occasion(p_occasion)) THEN jsonb_build_object('code',403) ELSE
 jsonb_build_object('code',200,'liveVersion',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text),0),
 'latestPublishId',(SELECT id FROM public.activity_history WHERE occasion_id=p_occasion AND history_type='PUBLISH' ORDER BY id DESC LIMIT 1),
 'draftId',d.id,'draftParentHistoryId',d.parent_history_id,'draftData',CASE WHEN d.id IS NOT NULL THEN public.activity_graph_history_internal_v1(public.activity_history_graph_internal_v1(p_occasion,d.activities_data,false)) ELSE NULL END,
 'editBundle',jsonb_build_object(
 'events',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) FROM public.events e WHERE e.occasion=p_occasion),'[]'),
 'places',COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p."order",p.id) FROM public.places p WHERE p.occasion=p_occasion),'[]'),
 'activities',COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.activities a WHERE a.occasion=p_occasion),'[]'),
 'activity_assignments',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.activity_assignments x JOIN public.activities a ON a.id=x.activity_id WHERE a.occasion=p_occasion),'[]'),
 'assignment_place_links',COALESCE((SELECT jsonb_agg(to_jsonb(l)) FROM public.activity_assignment_places l JOIN public.activity_assignments x ON x.id=l.assignment_id JOIN public.activities a ON a.id=x.activity_id WHERE a.occasion=p_occasion),'[]'),
 'assignment_event_links',COALESCE((SELECT jsonb_agg(to_jsonb(l)) FROM public.activity_assignment_events l JOIN public.activity_assignments x ON x.id=l.assignment_id JOIN public.activities a ON a.id=x.activity_id WHERE a.occasion=p_occasion),'[]'),
 'user_info',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'surname',u.surname,'sex',u.sex,'email',u.email_readonly)) FROM public.user_info u JOIN public.occasion_users ou ON ou."user"=u.id WHERE ou.occasion=p_occasion AND (ou.data->>'is_volunteer')::boolean),'[]'))) END
 FROM (SELECT 1) root LEFT JOIN LATERAL (SELECT id,parent_history_id,activities_data FROM public.activity_history WHERE occasion_id=p_occasion AND user_id=auth.uid() AND history_type='AUTOSAVE' ORDER BY id DESC LIMIT 1) d ON true;
$$;
REVOKE ALL ON FUNCTION public.get_activity_editor_session_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_activity_editor_session_v1(bigint) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_latest_autosave(p_occasion_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
    autosave_record JSONB;
    v_latest_publish_id BIGINT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.get_is_editor_view_on_occasion(p_occasion_id) THEN RETURN jsonb_build_object('code',403); END IF;
    -- Select the single latest autosave record for the current user
    SELECT jsonb_build_object(
        'id', id,
        'created_at', created_at,
        'activities_data', activities_data,
        'parent_history_id', parent_history_id
    )
    INTO autosave_record
    FROM public.activity_history
    WHERE occasion_id = p_occasion_id
      AND user_id = auth.uid()
      AND history_type = 'AUTOSAVE'
    ORDER BY created_at DESC
    LIMIT 1;

    -- Separately, find the ID of the absolute latest published version for the occasion
    SELECT id
    INTO v_latest_publish_id
    FROM public.activity_history
    WHERE occasion_id = p_occasion_id
      AND history_type = 'PUBLISH'
    ORDER BY created_at DESC
    LIMIT 1;

    -- Return an object containing both the autosave data (if found) and the latest publish ID (if found)
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Autosave and publish info retrieved.',
        'data', jsonb_build_object(
            'autosave', autosave_record,
            'latest_publish_id', v_latest_publish_id
        )
    );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.get_activity_history_version(p_history_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
    v_occasion_id BIGINT;
    history_data JSONB;
BEGIN
    SELECT occasion_id INTO v_occasion_id FROM public.activity_history WHERE id = p_history_id AND (history_type<>'AUTOSAVE' OR user_id=auth.uid());

    IF v_occasion_id IS NULL OR (SELECT get_is_editor_on_occasion(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this history version');
    END IF;

    -- Select the single history record into a JSON object
    SELECT jsonb_build_object(
        'id', id,
        'created_at', created_at,
        'activities_data', public.activity_graph_history_internal_v1(public.activity_history_graph_internal_v1(v_occasion_id,activities_data,false)),
        'parent_history_id', parent_history_id
    )
    INTO history_data
    FROM public.activity_history
    WHERE id = p_history_id AND (history_type<>'AUTOSAVE' OR user_id=auth.uid());

    -- Return the object wrapped in a standard response
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'History version retrieved.',
        'data', history_data
    );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.list_activity_history(p_occasion_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
    history_data JSONB;
BEGIN
    IF (SELECT get_is_editor_on_occasion(p_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view history');
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', h.id,
        'created_at', h.created_at,
        'history_type', h.history_type,
        'note', h.note,
        'user_name', u.name,
        'user_surname', u.surname
    ) ORDER BY h.created_at DESC), '[]'::jsonb)
    INTO history_data
    FROM public.activity_history h
    LEFT JOIN public.user_info u ON h.user_id = u.id
    WHERE h.occasion_id = p_occasion_id AND (h.history_type <> 'AUTOSAVE' OR (h.history_type = 'AUTOSAVE' AND h.user_id = auth.uid()));

    RETURN jsonb_build_object(
        'code', 200,
        'message', 'History retrieved successfully',
        'data', history_data
    );
END;
$function$
;
