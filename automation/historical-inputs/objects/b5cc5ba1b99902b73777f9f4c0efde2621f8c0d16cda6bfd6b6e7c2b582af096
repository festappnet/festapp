BEGIN;

CREATE OR REPLACE FUNCTION public.create_reception_user_v1(p_occasion bigint,p_command_id uuid,p_profile jsonb,p_group_id bigint DEFAULT NULL,p_accommodation_code text DEFAULT NULL,p_confirm_same_name boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_org bigint; v_user uuid; v_hash text; v_existing public.reception_registrations%rowtype;
  v_name text:=btrim(p_profile->>'name'); v_surname text:=btrim(p_profile->>'surname'); v_email text:=lower(btrim(p_profile->>'email'));
  v_sex text:=p_profile->>'sex'; v_matches jsonb; v_services jsonb:='{}'::jsonb; v_catalog jsonb;
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('create',20) THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_profile) k WHERE k NOT IN('name','surname','email','sex','phone','birthDate'))
  THEN RETURN jsonb_build_object('code',400,'message','invalid_profile_fields'); END IF;
  IF COALESCE(v_name,'')='' OR COALESCE(v_surname,'')='' OR COALESCE(v_email,'')='' OR position('@' IN v_email)<=1 OR v_sex NOT IN('male','female','unspecified')
  THEN RETURN jsonb_build_object('code',400,'message','required_profile_fields'); END IF;
  v_hash:=encode(digest(jsonb_build_object('profile',p_profile,'group',p_group_id,'accommodation',p_accommodation_code)::text,'sha256'),'hex');
  SELECT * INTO v_existing FROM public.reception_registrations WHERE occasion=p_occasion AND created_by=v_actor AND command_id=p_command_id;
  IF FOUND THEN
    IF v_existing.request_hash<>v_hash THEN RETURN jsonb_build_object('code',409,'message','command_conflict'); END IF;
    SELECT ui.email_readonly INTO v_email FROM public.user_info ui WHERE ui.id=v_existing."user";
    RETURN jsonb_build_object('code',200,'userId',v_existing."user",'email',v_email,'replayed',true);
  END IF;
  SELECT o.organization,COALESCE(o.services,'{}'::jsonb) INTO v_org,v_catalog FROM public.occasions o WHERE o.id=p_occasion FOR SHARE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('reception-email:'||v_org::text||':'||v_email,0));
  SELECT ui.id INTO v_user
  FROM public.user_info ui
  WHERE ui.organization=v_org AND lower(btrim(ui.email_readonly))=v_email;
  IF v_user IS NOT NULL THEN
    IF (public.get_is_admin_on_occasion(p_occasion)
        OR public.get_is_manager_on_occasion(p_occasion))
      AND EXISTS(SELECT 1 FROM public.occasion_users ou
        WHERE ou.occasion=p_occasion AND ou."user"=v_user) THEN
      RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,
        'existing',true,'replayed',false);
    END IF;
    RETURN jsonb_build_object('code',409,'message','email_already_exists');
  END IF;
  SELECT COALESCE(jsonb_agg(candidate),'[]'::jsonb) INTO v_matches FROM (
    SELECT jsonb_build_object('name',ui.name,'surname',ui.surname,'sex',ui.sex,
      'birthYear',CASE WHEN ui.birth_date IS NULL THEN NULL ELSE extract(year FROM ui.birth_date)::int END,
      'email',CASE WHEN position('@' IN ui.email_readonly)>2 THEN left(ui.email_readonly,1)||'***@'||split_part(ui.email_readonly,'@',2) ELSE '***' END,
      'onOccasion',EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=ui.id)) candidate
    FROM public.user_info ui WHERE ui.organization=v_org AND public.f_unaccent(btrim(ui.name))=public.f_unaccent(v_name)
      AND public.f_unaccent(btrim(ui.surname))=public.f_unaccent(v_surname) ORDER BY ui.created_at NULLS LAST LIMIT 10) q;
  IF jsonb_array_length(v_matches)>0 AND NOT p_confirm_same_name THEN RETURN jsonb_build_object('code',409,'message','same_name_confirmation_required','candidates',v_matches); END IF;
  IF p_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.user_group_info g WHERE g.id=p_group_id AND g.occasion=p_occasion AND g.type IS NULL FOR SHARE)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_group'); END IF;
  IF p_accommodation_code IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_catalog->'accommodation')='array' THEN v_catalog->'accommodation' ELSE '[]'::jsonb END) x WHERE x->>'code'=p_accommodation_code)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_accommodation'); END IF;
  v_user:=public.create_user_in_organization_with_data_pure(v_org,v_email,v_email,encode(gen_random_bytes(32),'hex'),p_profile-'email');
  IF p_accommodation_code IS NOT NULL THEN v_services:=jsonb_build_object('accommodation',jsonb_build_object(p_accommodation_code,'paid')); END IF;
  INSERT INTO public.occasion_users(occasion,"user",data,services) VALUES(p_occasion,v_user,p_profile,v_services);
  IF p_group_id IS NOT NULL THEN INSERT INTO public.user_groups("user","group",is_admin) VALUES(v_user,p_group_id,false); END IF;
  INSERT INTO public.reception_registrations(occasion,"user",created_by,command_id,request_hash) VALUES(p_occasion,v_user,v_actor,p_command_id,v_hash);
  RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,'replayed',false);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('code',409,'message','email_or_command_conflict');
END $$;

CREATE OR REPLACE FUNCTION public.issue_reception_login_qr_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_token text; v_hash text; v_actor uuid:=auth.uid();
  v_manual text; v_manual_hash text; v_manual_bytes bytea; v_alphabet constant text:='23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('issue',30) THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=p_user)
    OR NOT (public.get_is_admin_on_occasion(p_occasion)
      OR public.get_is_manager_on_occasion(p_occasion) OR EXISTS(
      SELECT 1 FROM public.reception_registrations r
      WHERE r.occasion=p_occasion AND r."user"=p_user AND r.status='active'
        AND r.created_by=v_actor AND r.created_at>now()-interval '30 minutes')) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable'); END IF;
  v_token:=translate(encode(gen_random_bytes(32),'base64'),E'+/=\n','-_'); v_hash:=encode(digest(v_token,'sha256'),'hex');
  v_manual_bytes:=gen_random_bytes(8);
  SELECT string_agg(substr(v_alphabet,(get_byte(v_manual_bytes,i)%32)+1,1),'') INTO v_manual FROM generate_series(0,7) i;
  v_manual_hash:=encode(digest(v_manual,'sha256'),'hex');
  INSERT INTO public.user_login_qr_credentials(occasion,"user",token_hash,manual_token_hash,manual_expires_at,created_by)
  VALUES(p_occasion,p_user,v_hash,v_manual_hash,now()+interval '30 minutes',v_actor)
  ON CONFLICT(occasion,"user") DO UPDATE SET token_hash=excluded.token_hash,manual_token_hash=excluded.manual_token_hash,
    manual_expires_at=excluded.manual_expires_at,created_by=excluded.created_by,rotated_at=now(),revoked_at=NULL,last_used_at=NULL,use_count=0;
  RETURN jsonb_build_object('code',200,'payload','festapp-login:v1:'||p_occasion::text||':'||v_token,
    'manualCode',left(v_manual,4)||'-'||right(v_manual,4));
END $$;

CREATE OR REPLACE FUNCTION public.get_reception_occasion_users_v1(p_occasion bigint,p_query text DEFAULT '')
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
SELECT CASE
  WHEN public.get_can_use_reception(p_occasion)
    AND (public.get_is_admin_on_occasion(p_occasion)
      OR public.get_is_manager_on_occasion(p_occasion))
  THEN COALESCE(jsonb_agg(jsonb_build_object(
    'userId',q.id,'name',q.name,'surname',q.surname,'email',q.email_readonly
  ) ORDER BY q.surname,q.name,q.email_readonly),'[]'::jsonb)
  ELSE '[]'::jsonb
END
FROM (
  SELECT ui.id,ui.name,ui.surname,ui.email_readonly
  FROM public.occasion_users ou
  JOIN public.user_info ui ON ui.id=ou."user"
  WHERE ou.occasion=p_occasion
    AND (COALESCE(btrim(p_query),'')=''
      OR public.f_unaccent(COALESCE(ui.name,'')||' '||COALESCE(ui.surname,'')||' '||COALESCE(ui.email_readonly,''))
        ILIKE '%'||public.f_unaccent(btrim(left(p_query,100)))||'%')
  ORDER BY ui.surname,ui.name,ui.email_readonly
  LIMIT 50
) q; $$;

REVOKE ALL ON FUNCTION public.get_reception_occasion_users_v1(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_reception_user_v1(bigint,uuid,jsonb,bigint,text,boolean),public.get_reception_occasion_users_v1(bigint,text),public.issue_reception_login_qr_v1(bigint,uuid) TO authenticated,service_role;

COMMIT;
