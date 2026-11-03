CREATE OR REPLACE FUNCTION public.get_exclusive_group_command_data_v1(p_group bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
  SELECT jsonb_build_object(
    'id',g.id,
    'title',g.title,
    'exclusive_events',COALESCE((SELECT jsonb_agg(
      jsonb_build_object('event',ee.event) ORDER BY ee.event)
      FROM public.exclusive_events ee WHERE ee."group"=g.id),'[]'::jsonb),
    'aggregate_version',COALESCE(v.version,0))
  FROM public.exclusive_groups g
  LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='exclusive_group' AND v.scope_type='occasion'
    AND v.scope_id=g.occasion AND v.aggregate_id=g.id::text
  WHERE g.id=p_group;
$function$
;
REVOKE ALL ON FUNCTION public.get_exclusive_group_command_data_v1(p_group bigint) FROM PUBLIC,anon,authenticated;
