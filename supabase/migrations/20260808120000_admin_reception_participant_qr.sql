CREATE OR REPLACE FUNCTION public.issue_reception_login_qr_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_token text; v_hash text; v_actor uuid:=auth.uid();
  v_manual text; v_manual_hash text; v_manual_bytes bytea; v_alphabet constant text:='23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('issue',30) THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=p_user)
    OR NOT (public.get_is_admin_on_occasion(p_occasion) OR EXISTS(
      SELECT 1 FROM public.reception_registrations r
      WHERE r.occasion=p_occasion AND r."user"=p_user AND r.status='active'
        AND (r.created_by=v_actor AND r.created_at>now()-interval '30 minutes'
          OR public.get_is_manager_on_occasion(p_occasion)))) THEN
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
  WHEN public.get_can_use_reception(p_occasion) AND public.get_is_admin_on_occasion(p_occasion)
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
GRANT EXECUTE ON FUNCTION public.get_reception_occasion_users_v1(bigint,text) TO authenticated,service_role;
