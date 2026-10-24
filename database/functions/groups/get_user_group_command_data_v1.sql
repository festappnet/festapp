CREATE OR REPLACE FUNCTION public.get_user_group_command_data_v1(p_group bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
  SELECT jsonb_build_object('id',g.id,'title',g.title,
    'description',g.description,'type',g.type,'data',g.data,'place',g.place,
    'placeData',(SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',coalesce(v.version,0)) FROM public.places p LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place' AND v.scope_type='occasion' AND v.scope_id=p.occasion AND v.aggregate_id=p.id::text WHERE p.id=g.place),
    'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'userId',ug."user",'isAdmin',ug.is_admin,'is_admin',ug.is_admin,
      'user_info',jsonb_build_object('id',ui.id,'name',ui.name,'surname',ui.surname))
      ORDER BY ug."user") FROM public.user_groups ug JOIN public.user_info ui
      ON ui.id=ug."user" WHERE ug."group"=g.id),'[]'::jsonb))
  FROM public.user_group_info g WHERE g.id=p_group;
$function$
;
REVOKE ALL ON FUNCTION public.get_user_group_command_data_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
