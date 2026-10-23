CREATE OR REPLACE FUNCTION public.create_counseling_slots_domain_command_internal_v1(p_speaker bigint, p_start timestamp with time zone, p_end timestamp with time zone, p_slot_minutes integer, p_place bigint, p_capacity integer, p_title text, p_break_minutes integer, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_ids bigint[];
BEGIN
  SELECT s.occasion INTO v_occasion FROM public.speakers s WHERE s.id=p_speaker;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.can_write_speakers(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('speaker',p_speaker,
    'start',p_start,'end',p_end,'slotMinutes',p_slot_minutes,'place',p_place,
    'capacity',p_capacity,'title',p_title,'breakMinutes',p_break_minutes)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'program.counseling.create',
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.speakers s WHERE s.id=p_speaker FOR UPDATE;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_speaker);
  v_result:=public.create_counseling_slots_internal_v1(p_speaker,p_start,p_end,
    p_slot_minutes,p_place,p_capacity,p_title,p_break_minutes);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')); END IF;
  SELECT COALESCE(array_agg(value::bigint),'{}'::bigint[]) INTO v_ids
    FROM jsonb_array_elements_text(v_result#>'{data,event_ids}');
  IF cardinality(v_ids)=0 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,v_result->'data'); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'event','occasion',v_occasion,id::text,1 FROM unnest(v_ids) id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'program.counseling.create','program',jsonb_build_array(jsonb_build_object(
      'entityType','counseling_slot','entityId',NULL,'operation','insert',
      'safeLabel','Counseling slots','changedFields',jsonb_build_array('events','speakers'))),
    ARRAY['program_catalog','content_catalog'],'[]','[]',v_result->'data');
END; $function$
;
REVOKE ALL ON FUNCTION public.create_counseling_slots_domain_command_internal_v1(p_speaker bigint, p_start timestamp with time zone, p_end timestamp with time zone, p_slot_minutes integer, p_place bigint, p_capacity integer, p_title text, p_break_minutes integer, p_command_id uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_counseling_slots_domain_command_internal_v1(bigint,timestamp with time zone,timestamp with time zone,integer,bigint,integer,text,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_counseling_slots_domain_command_internal_v1(bigint,timestamp with time zone,timestamp with time zone,integer,bigint,integer,text,integer,uuid) TO service_role;
