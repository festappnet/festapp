-- Shared by aggregate replacement and additive membership. Authorization belongs
-- to the surrounding command; this private invoker never grants extra rights.
CREATE OR REPLACE FUNCTION public.write_user_group_members_internal_v1(p_occasion bigint,p_group bigint,p_members jsonb,p_replace boolean)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE affected integer;
BEGIN
 PERFORM 1 FROM public.user_group_info WHERE id=p_group AND occasion=p_occasion FOR UPDATE;
 IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='foreign group'; END IF;
 IF p_members IS NULL OR jsonb_typeof(p_members) IS DISTINCT FROM 'array' OR jsonb_array_length(p_members)>5000
  OR EXISTS(SELECT 1 FROM jsonb_to_recordset(p_members) x(user_id uuid,is_admin boolean)
   LEFT JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=x.user_id WHERE ou."user" IS NULL)
  OR jsonb_array_length(p_members)<>(SELECT count(DISTINCT x.user_id) FROM jsonb_to_recordset(p_members) x(user_id uuid)) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid group members'; END IF;
 IF p_replace THEN DELETE FROM public.user_groups WHERE "group"=p_group; END IF;
 INSERT INTO public.user_groups("group","user",is_admin)
 SELECT p_group,x.user_id,coalesce(x.is_admin,false) FROM jsonb_to_recordset(p_members) x(user_id uuid,is_admin boolean)
 ON CONFLICT("group","user") DO NOTHING;
 GET DIAGNOSTICS affected=ROW_COUNT;
 RETURN affected;
END $$;
REVOKE ALL ON FUNCTION public.write_user_group_members_internal_v1(bigint,bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
