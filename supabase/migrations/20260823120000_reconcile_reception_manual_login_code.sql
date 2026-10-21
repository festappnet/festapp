ALTER TABLE public.user_login_qr_credentials
  ADD COLUMN IF NOT EXISTS manual_token_hash text,
  ADD COLUMN IF NOT EXISTS manual_expires_at timestamptz;

ALTER TABLE public.user_login_qr_credentials
  DROP CONSTRAINT IF EXISTS user_login_qr_credentials_manual_hash_key,
  ADD CONSTRAINT user_login_qr_credentials_manual_hash_key UNIQUE (manual_token_hash),
  DROP CONSTRAINT IF EXISTS user_login_qr_credentials_manual_hash_check,
  ADD CONSTRAINT user_login_qr_credentials_manual_hash_check
    CHECK (manual_token_hash IS NULL OR manual_token_hash ~ '^[0-9a-f]{64}$'),
  DROP CONSTRAINT IF EXISTS user_login_qr_credentials_manual_expiry_check,
  ADD CONSTRAINT user_login_qr_credentials_manual_expiry_check
    CHECK ((manual_token_hash IS NULL) = (manual_expires_at IS NULL));

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

REVOKE ALL ON FUNCTION public.resolve_reception_login_qr_v1(bigint,text),public.mark_reception_login_qr_used_v1(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_reception_login_qr_v1(bigint,text),public.mark_reception_login_qr_used_v1(bigint,text) TO service_role;
