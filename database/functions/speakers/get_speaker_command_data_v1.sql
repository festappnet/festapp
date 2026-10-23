CREATE OR REPLACE FUNCTION public.get_speaker_command_data_v1(p_speaker_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
  SELECT to_jsonb(s)||jsonb_build_object('topics',COALESCE((
    SELECT jsonb_agg(l.topic ORDER BY l.topic) FROM public.speaker_topic_links l
    WHERE l.speaker=s.id),'[]'::jsonb)) FROM public.speakers s
  WHERE s.id=p_speaker_id;
$function$
;
REVOKE ALL ON FUNCTION public.get_speaker_command_data_v1(p_speaker_id bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_speaker_command_data_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_speaker_command_data_v1(bigint) TO service_role;
