CREATE OR REPLACE FUNCTION public.reception_rate_limit_v1(p_operation text,p_limit integer DEFAULT 30)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_count integer; v_bucket timestamptz:=date_trunc('minute',now());
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  INSERT INTO public.reception_rate_limits(actor,operation,bucket,count)
  VALUES(auth.uid(),p_operation,v_bucket,1)
  ON CONFLICT(actor,operation,bucket) DO UPDATE SET count=public.reception_rate_limits.count+1
  RETURNING count INTO v_count;
  RETURN v_count<=p_limit;
END $$;

CREATE OR REPLACE FUNCTION public.get_reception_registration_options_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_services jsonb;
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN
    RETURN jsonb_build_object('code',403,'message','reception_unavailable');
  END IF;
  SELECT COALESCE(o.services,'{}'::jsonb) INTO v_services FROM public.occasions o WHERE o.id=p_occasion;
  RETURN jsonb_build_object('code',200,'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',g.id,'title',g.title) ORDER BY g.title)
    FROM public.user_group_info g WHERE g.occasion=p_occasion AND g.type IS NULL),'[]'::jsonb),
    'accommodations',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.item->>'code','title',x.item->>'title','placeTitle',p.title) ORDER BY x.ordinality)
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_services->'accommodation')='array' THEN v_services->'accommodation' ELSE '[]'::jsonb END)
      WITH ORDINALITY x(item,ordinality) LEFT JOIN public.places p ON p.occasion=p_occasion AND p.id=CASE WHEN x.item->>'reference' ~ '^[0-9]+$' THEN (x.item->>'reference')::bigint END),'[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.create_reception_user_v1(p_occasion bigint, p_command_id uuid, p_profile jsonb, p_group_id bigint DEFAULT NULL::bigint, p_accommodation_code text DEFAULT NULL::text, p_confirm_same_name boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF NOT public.get_can_use_reception(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='reception unavailable'; END IF;
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
  IF p_group_id IS NOT NULL THEN
    INSERT INTO public.user_groups("user","group",is_admin) VALUES(v_user,p_group_id,false);
    UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_group_id::text;
    PERFORM public.advance_group_profile_heads_internal_v1(p_occasion,ARRAY(SELECT "user" FROM public.user_groups WHERE "group"=p_group_id));
  END IF;
  INSERT INTO public.reception_registrations(occasion,"user",created_by,command_id,request_hash) VALUES(p_occasion,v_user,v_actor,p_command_id,v_hash);
  RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,'replayed',false);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('code',409,'message','email_or_command_conflict');
END $function$
;

-- Superseded ungranted wrapper implementations, now folded into receipt owners.
DROP FUNCTION IF EXISTS public.replace_group_assignments_companion_internal_v1(bigint,uuid,jsonb);
DROP FUNCTION IF EXISTS public.import_profiles_companion_internal_v1(bigint,uuid,jsonb,jsonb);
DROP FUNCTION IF EXISTS public.delete_occasion_user_companion_internal_v1(bigint,uuid,uuid,bigint);

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

CREATE OR REPLACE FUNCTION public.resolve_reception_login_qr_v1(p_occasion bigint,p_token_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_user uuid; v_email text;
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
  SELECT c."user",(o.organization::text||'+'||au.email_readonly) INTO v_user,v_email
  FROM public.user_login_qr_credentials c JOIN public.occasion_users ou ON (ou.occasion,ou."user")=(c.occasion,c."user")
  JOIN public.user_info au ON au.id=c."user" JOIN public.occasions o ON o.id=c.occasion
  WHERE c.occasion=p_occasion
    AND (c.token_hash=p_token_hash OR (c.manual_token_hash=p_token_hash AND c.manual_expires_at>now()))
    AND c.revoked_at IS NULL
    AND jsonb_path_exists(COALESCE(o.features,'[]'::jsonb),'$[*] ? (@.code == "reception" && @.is_enabled == true)') FOR UPDATE OF c;
  IF v_user IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('userId',v_user,'authEmail',v_email);
END $$;

CREATE OR REPLACE FUNCTION public.revoke_reception_login_qr_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_actor uuid:=auth.uid();
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN
    RETURN jsonb_build_object('code',403,'message','reception_unavailable');
  END IF;
  IF NOT public.reception_rate_limit_v1('revoke',30) THEN
    RETURN jsonb_build_object('code',429,'message','rate_limited');
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.reception_registrations r
    WHERE r.occasion=p_occasion AND r."user"=p_user AND r.status='active'
      AND ((r.created_by=v_actor AND r.created_at>now()-interval '30 minutes')
        OR public.get_is_manager_on_occasion(p_occasion)
        OR public.get_is_admin_on_occasion(p_occasion))
  ) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable');
  END IF;
  UPDATE public.user_login_qr_credentials
  SET revoked_at=now()
  WHERE occasion=p_occasion AND "user"=p_user AND revoked_at IS NULL;
  RETURN jsonb_build_object('code',200,'status','revoked');
END $$;

CREATE OR REPLACE FUNCTION public.mark_reception_login_qr_used_v1(p_occasion bigint,p_token_hash text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
  UPDATE public.user_login_qr_credentials c SET
    last_used_at=now(),
    use_count=use_count+1,
    manual_token_hash=CASE WHEN c.manual_token_hash=p_token_hash THEN NULL ELSE c.manual_token_hash END,
    manual_expires_at=CASE WHEN c.manual_token_hash=p_token_hash THEN NULL ELSE c.manual_expires_at END
  FROM public.occasion_users ou,public.occasions o
  WHERE c.occasion=p_occasion
    AND (c.token_hash=p_token_hash OR (c.manual_token_hash=p_token_hash AND c.manual_expires_at>now()))
    AND c.revoked_at IS NULL
    AND (ou.occasion,ou."user")=(c.occasion,c."user") AND o.id=c.occasion
    AND jsonb_path_exists(COALESCE(o.features,'[]'::jsonb),'$[*] ? (@.code == "reception" && @.is_enabled == true)');
END $$;

CREATE OR REPLACE FUNCTION public.cancel_reception_registration_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_r public.reception_registrations%rowtype; v_actor uuid:=auth.uid(); v_impacts jsonb;
BEGIN
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  SELECT * INTO v_r FROM public.reception_registrations WHERE occasion=p_occasion AND "user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','registration_unavailable'); END IF;
  IF NOT public.get_can_use_reception(p_occasion) OR NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR (v_r.created_by=v_actor AND (v_r.status='cancelled' OR v_r.created_at>now()-interval '30 minutes'))) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable'); END IF;
  IF v_r.status='cancelled' THEN RETURN jsonb_build_object('code',200,'status',CASE WHEN v_r.auth_revoked_at IS NULL THEN 'domain_blocked_auth_revocation_pending' ELSE 'cancelled' END,'targetUser',p_user); END IF;
  UPDATE public.reception_registrations SET status='cancelled',cancelled_by=v_actor,cancelled_at=now() WHERE occasion=p_occasion AND "user"=p_user;
  v_impacts:=public.remove_occasion_user_domain_internal_v1(p_occasion,p_user);
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT x->>'component',p_occasion,(x->>'userId')::uuid,1 FROM jsonb_array_elements(v_impacts) x ORDER BY x->>'component',x->>'userId'
  ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();
  RETURN jsonb_build_object('code',200,'status','domain_blocked_auth_revocation_pending','targetUser',p_user);
END $$;

CREATE OR REPLACE FUNCTION public.mark_reception_auth_revoked_v1(p_occasion bigint,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
UPDATE public.reception_registrations SET auth_revoked_at=now() WHERE occasion=p_occasion AND "user"=p_user AND status='cancelled'; END $$;

CREATE OR REPLACE FUNCTION public.get_my_recent_reception_registrations_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
SELECT CASE WHEN public.get_can_use_reception(p_occasion) THEN COALESCE(jsonb_agg(jsonb_build_object('userId',r."user",'name',ui.name,'surname',ui.surname,'email',ui.email_readonly,'createdAt',r.created_at,'qrUsed',c.last_used_at IS NOT NULL) ORDER BY r.created_at DESC),'[]'::jsonb) ELSE '[]'::jsonb END
FROM public.reception_registrations r JOIN public.user_info ui ON ui.id=r."user" LEFT JOIN public.user_login_qr_credentials c ON (c.occasion,c."user")=(r.occasion,r."user")
WHERE r.occasion=p_occasion AND r.created_by=auth.uid() AND r.status='active' AND r.created_at>now()-interval '30 minutes'; $$;

REVOKE ALL ON FUNCTION public.reception_rate_limit_v1(text,integer),public.get_reception_occasion_users_v1(bigint,text),public.resolve_reception_login_qr_v1(bigint,text),public.mark_reception_login_qr_used_v1(bigint,text),public.mark_reception_auth_revoked_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_reception_login_qr_v1(bigint,text),public.mark_reception_login_qr_used_v1(bigint,text),public.mark_reception_auth_revoked_v1(bigint,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_reception_registration_options_v1(bigint),public.create_reception_user_v1(bigint,uuid,jsonb,bigint,text,boolean),public.issue_reception_login_qr_v1(bigint,uuid),public.get_reception_occasion_users_v1(bigint,text),public.revoke_reception_login_qr_v1(bigint,uuid),public.cancel_reception_registration_v1(bigint,uuid),public.get_my_recent_reception_registrations_v1(bigint) TO authenticated,service_role;
