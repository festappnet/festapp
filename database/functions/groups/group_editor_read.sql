CREATE OR REPLACE FUNCTION public.get_user_group_command_data_v1(p_group bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
  SELECT jsonb_build_object('id',g.id,'title',g.title,
    'description',g.description,'type',g.type,'data',g.data,'place',g.place,
    'is_admin',COALESCE((SELECT is_admin FROM public.user_groups WHERE "group"=g.id AND "user"=auth.uid()),false),
    'aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=g.occasion AND aggregate_id=g.id::text),0),
    'placeData',(SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=g.occasion AND aggregate_id=p.id::text),0)) FROM public.places p WHERE p.id=g.place),
    'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'userId',ug."user",'isAdmin',ug.is_admin,'is_admin',ug.is_admin,
      'user_info',jsonb_build_object('id',ui.id,'name',ui.name,'surname',ui.surname))
      ORDER BY ug."user") FROM public.user_groups ug JOIN public.user_info ui
      ON ui.id=ug."user" WHERE ug."group"=g.id),'[]'::jsonb))
  FROM public.user_group_info g WHERE g.id=p_group;
$function$
;
REVOKE ALL ON FUNCTION public.get_user_group_command_data_v1(bigint) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.get_user_group_editor_bundle_v1(p_occasion bigint,p_group_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_view_on_occasion(p_occasion) OR EXISTS(SELECT 1 FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group" WHERE g.id=p_group_id AND g.occasion=p_occasion AND ug."user"=auth.uid() AND ug.is_admin)) THEN
 RAISE insufficient_privilege USING MESSAGE='group editor required'; END IF;
 RETURN (SELECT public.get_user_group_command_data_v1(id) FROM public.user_group_info WHERE id=p_group_id AND occasion=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_user_group_editor_bundle_v1(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_group_editor_bundle_v1(bigint,bigint) TO authenticated;
