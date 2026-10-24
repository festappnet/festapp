CREATE OR REPLACE FUNCTION public.report_cleaning_issue_client_sync_v1(p_place bigint, p_problem_type text, p_note text, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_existing bigint; v_has_note boolean;
BEGIN
  SELECT p.occasion INTO v_occasion FROM public.places p WHERE p.id=p_place;
  IF v_actor IS NULL OR v_occasion IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='signed-in occasion participant required';
  END IF;
  v_has_note:=NULLIF(btrim(COALESCE(p_note,'')),'') IS NOT NULL;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'place',p_place,'problemType',p_problem_type,'note',p_note)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'cleaning.report',
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.places p WHERE p.id=p_place FOR UPDATE;
  SELECT cr.id INTO v_existing FROM public.cleaning_reports cr
    WHERE cr.place=p_place AND cr.problem_type=p_problem_type
      AND cr.resolved_at IS NULL ORDER BY cr.created_at LIMIT 1 FOR UPDATE;
  v_result:=public.report_cleaning_issue_internal_v1(p_place,p_problem_type,p_note);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')||
      jsonb_build_object('message',v_result->>'message')); END IF;
  IF v_existing IS NOT NULL AND NOT v_has_note THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      v_result->'data'); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'cleaning.report','cleaning',jsonb_build_array(jsonb_build_object(
      'entityType','cleaning_report','entityId',v_result#>>'{data,id}',
      'operation',CASE WHEN v_existing IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel','Cleaning report','changedFields',CASE WHEN v_existing IS NULL
        THEN jsonb_build_array('place','problemType') ELSE jsonb_build_array('note') END)),
    CASE WHEN v_existing IS NULL THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    '[]',CASE WHEN v_existing IS NULL THEN jsonb_build_array(jsonb_build_object(
      'component','live_public','entityId',p_place)) ELSE '[]'::jsonb END,
    v_result->'data');
END; $function$;
REVOKE ALL ON FUNCTION public.report_cleaning_issue_client_sync_v1(bigint,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.report_cleaning_issue_client_sync_v1(bigint,text,text,uuid) TO authenticated;
