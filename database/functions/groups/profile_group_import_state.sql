CREATE OR REPLACE FUNCTION public.profile_group_import_state_internal_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('profiles',COALESCE((SELECT jsonb_agg(jsonb_build_object('membership',to_jsonb(ou)-'created_at'-'updated_at','profile',to_jsonb(ui)-'created_at'-'updated_at') ORDER BY ou."user") FROM public.occasion_users ou JOIN public.user_info ui ON ui.id=ou."user" WHERE ou.occasion=p_occasion),'[]'),'groups',COALESCE((SELECT jsonb_object_agg(g.id,public.get_user_group_command_data_v1(g.id)-'aggregate_version') FROM public.user_group_info g WHERE g.occasion=p_occasion),'{}'));
$$;
REVOKE ALL ON FUNCTION public.profile_group_import_state_internal_v1(bigint) FROM PUBLIC,anon,authenticated;
