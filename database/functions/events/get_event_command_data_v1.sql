CREATE OR REPLACE FUNCTION public.get_event_command_data_v1(p_event_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
  SELECT jsonb_build_object(
    'id',e.id,'title',e.title,'startTime',e.start_time,'endTime',e.end_time,
    'maxParticipants',e.max_participants,'description',e.description,
    'placeId',e.place,'splitForMenWomen',e.split_for_men_women,
    'isGroupEvent',e.is_group_event,'isHidden',e.is_hidden,'type',e.type,
    'data',e.data,'order',e."order",
    'parentEventIds',COALESCE((SELECT jsonb_agg(g.event_parent ORDER BY g.event_parent)
      FROM public.event_groups g WHERE g.event_child=e.id),'[]'::jsonb),
    'eventRoleIds',COALESCE((SELECT jsonb_agg(r.role ORDER BY r.role)
      FROM public.event_roles r WHERE r.event=e.id),'[]'::jsonb))
  FROM public.events e WHERE e.id=p_event_id;
$function$
;
REVOKE ALL ON FUNCTION public.get_event_command_data_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
