CREATE OR REPLACE FUNCTION public.create_companion_in_organization_internal_v1(org bigint, oc bigint, usr uuid, c_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE new_companion uuid:=gen_random_uuid(); user_email text;
  companion_email text; v_policy jsonb;
BEGIN
  v_policy:=public.get_companion_feature_policy_v1(oc);
  IF auth.uid() IS NULL OR auth.uid()<>usr
    OR NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=oc AND ou."user"=usr)
    OR NOT COALESCE((v_policy->>'is_enabled')::boolean,false)
    OR NOT COALESCE((v_policy->>'allow_user_create')::boolean,true) THEN
    RETURN jsonb_build_object('code',403);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-member:'||oc::text||':'||usr::text,0));
  IF (SELECT count(*) FROM public.user_companions uc
      WHERE uc.occasion=oc AND uc."user"=usr)
      >= (v_policy->>'max_companions')::integer THEN
    RETURN jsonb_build_object('code',403);
  END IF;
  SELECT ui.email_readonly INTO user_email FROM public.user_info ui WHERE ui.id=usr;
  companion_email:=user_email||'+'||btrim(c_name);
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,
    email_confirmed_at,raw_app_meta_data,created_at,updated_at,
    confirmation_token,email_change,email_change_token_new,recovery_token)
  VALUES('00000000-0000-0000-0000-000000000000',new_companion,
    'authenticated','authenticated',format('%s+%s',org,companion_email),'',now(),
    '{"provider":"email","providers":["email"]}',now(),now(),'','','','');
  INSERT INTO auth.identities(id,provider_id,user_id,identity_data,provider,
    created_at,updated_at)
  VALUES(gen_random_uuid(),new_companion,new_companion,
    jsonb_build_object('sub',new_companion,'email',format('%s+%s',org,companion_email)),
    'email',now(),now());
  INSERT INTO public.user_info(id,email_readonly,name,organization)
    VALUES(new_companion,companion_email,btrim(c_name),org);
  PERFORM public.add_user_to_occasion_internal_v1(oc,new_companion);
  -- The target membership now exists; serialize and recheck the complete graph.
  PERFORM public.check_companion_relation_invariants_v1(oc,usr,new_companion);
  INSERT INTO public.user_companions(occasion,"user",companion,origin,created_by)
    VALUES(oc,usr,new_companion,'self_created',usr);
  RETURN jsonb_build_object('code',200);
END $function$
;
REVOKE ALL ON FUNCTION public.create_companion_in_organization_internal_v1(org bigint, oc bigint, usr uuid, c_name text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_companion_in_organization_internal_v1(bigint,bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_companion_in_organization_internal_v1(bigint,bigint,uuid,text) TO service_role;
