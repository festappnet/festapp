-- Separate invitation proofs never become account passwords.
CREATE TABLE IF NOT EXISTS public.sign_in_codes (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 code_hash text NOT NULL,
 version uuid NOT NULL DEFAULT gen_random_uuid(),
 expires_at timestamptz NOT NULL,
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
 consumed_at timestamptz
);
ALTER TABLE public.sign_in_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sign_in_codes FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.sign_in_codes TO service_role;

-- Called only within authorized account-domain transactions.
CREATE OR REPLACE FUNCTION public.store_sign_in_code_v1(p_user uuid,p_code text,p_expires timestamptz)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' OR p_expires IS NULL OR p_expires<=now() THEN RAISE EXCEPTION 'invalid_sign_in_code'; END IF;
 INSERT INTO public.sign_in_codes(user_id,code_hash,expires_at)
 VALUES(p_user,extensions.crypt(p_code,extensions.gen_salt('bf')),least(p_expires,now()+interval '10 minutes'))
 ON CONFLICT(user_id) DO UPDATE SET code_hash=excluded.code_hash,version=gen_random_uuid(),expires_at=excluded.expires_at,attempts=0,consumed_at=NULL;
END $$;
REVOKE ALL ON FUNCTION public.store_sign_in_code_v1(uuid,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.store_sign_in_code_v1(uuid,text,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.consume_sign_in_code_v1(p_email text,p_organization bigint,p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_code public.sign_in_codes; v_user uuid; v_email text;
BEGIN
 PERFORM public.require_service_role();
 IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' THEN RETURN NULL; END IF;
 SELECT ui.id,au.email INTO v_user,v_email FROM public.user_info ui JOIN auth.users au ON au.id=ui.id
 WHERE ui.organization=p_organization AND lower(ui.email_readonly)=lower(trim(p_email));
 IF v_user IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO v_code FROM public.sign_in_codes WHERE user_id=v_user FOR UPDATE;
 IF NOT FOUND OR v_code.expires_at<=now() OR v_code.consumed_at IS NOT NULL OR v_code.attempts>=5 THEN RETURN NULL; END IF;
 -- Return rather than raise: failed attempts must commit.
 UPDATE public.sign_in_codes SET attempts=attempts+1 WHERE user_id=v_user;
 IF extensions.crypt(p_code,v_code.code_hash) IS DISTINCT FROM v_code.code_hash THEN RETURN NULL; END IF;
 UPDATE public.sign_in_codes SET consumed_at=now() WHERE user_id=v_user;
 RETURN jsonb_build_object('userId',v_user,'authEmail',v_email);
END $$;
REVOKE ALL ON FUNCTION public.consume_sign_in_code_v1(text,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.consume_sign_in_code_v1(text,bigint,text) TO service_role;
