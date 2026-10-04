-- Shared, distributed serialization for internal GoTrue recovery minting.
CREATE OR REPLACE FUNCTION public.format_auth_email(p_organization bigint, p_sign_in_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE v_email text := lower(btrim(p_sign_in_email)); v_result text;
BEGIN
  IF p_organization IS NULL OR p_organization <= 0 OR v_email IS NULL
     OR v_email = '' OR position('@' IN v_email) <= 1 THEN
    RAISE EXCEPTION 'INVALID_USER_EMAIL';
  END IF;
  v_result := p_organization::text || '+' || v_email;
  IF octet_length(v_result) > 254 THEN RAISE EXCEPTION 'INVALID_USER_EMAIL'; END IF;
  RETURN v_result;
END $$;

CREATE TABLE IF NOT EXISTS public.existing_user_session_leases (
  user_id uuid PRIMARY KEY REFERENCES public.user_info(id) ON DELETE CASCADE,
  owner uuid NOT NULL,
  expires_at timestamptz NOT NULL
);
ALTER TABLE public.existing_user_session_leases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.existing_user_session_leases FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.existing_user_session_leases TO service_role;

CREATE OR REPLACE FUNCTION public.resolve_existing_user_session_v1(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_profile public.user_info%rowtype; v_auth auth.users%rowtype;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_profile FROM public.user_info WHERE id=p_user;
  SELECT * INTO v_auth FROM auth.users WHERE id=p_user;
  IF v_profile.id IS NULL OR v_auth.id IS NULL OR v_auth.deleted_at IS NOT NULL
    OR v_auth.banned_until > clock_timestamp()
    OR v_auth.email IS DISTINCT FROM public.format_auth_email(v_profile.organization,v_profile.email_readonly) THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('userId',v_auth.id,'authEmail',v_auth.email,'organization',v_profile.organization,'requiresMfa',EXISTS(SELECT 1 FROM auth.mfa_factors WHERE user_id=p_user AND status='verified'));
END $$;

CREATE OR REPLACE FUNCTION public.acquire_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_target jsonb; v_acquired uuid;
BEGIN
  PERFORM public.require_service_role();
  IF p_owner IS NULL THEN RAISE EXCEPTION 'invalid_lease_owner'; END IF;
  v_target := public.resolve_existing_user_session_v1(p_user);
  IF v_target IS NULL THEN RETURN NULL; END IF;
  INSERT INTO public.existing_user_session_leases(user_id,owner,expires_at)
    VALUES(p_user,p_owner,clock_timestamp()+interval '120 seconds')
  ON CONFLICT(user_id) DO UPDATE SET owner=excluded.owner,expires_at=excluded.expires_at
    WHERE existing_user_session_leases.expires_at <= clock_timestamp()
  RETURNING owner INTO v_acquired;
  IF v_acquired IS NULL THEN RETURN NULL; END IF;
  RETURN v_target;
END $$;

CREATE OR REPLACE FUNCTION public.check_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF NOT EXISTS(SELECT 1 FROM public.existing_user_session_leases
      WHERE user_id=p_user AND owner=p_owner AND expires_at>clock_timestamp()) THEN RETURN NULL; END IF;
  RETURN public.resolve_existing_user_session_v1(p_user);
END $$;

CREATE OR REPLACE FUNCTION public.release_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM public.existing_user_session_leases WHERE user_id=p_user AND owner=p_owner;
END $$;

REVOKE ALL ON FUNCTION public.resolve_existing_user_session_v1(uuid),
  public.acquire_existing_user_session_lease_v1(uuid,uuid),
  public.check_existing_user_session_lease_v1(uuid,uuid),
  public.release_existing_user_session_lease_v1(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_existing_user_session_v1(uuid),
  public.acquire_existing_user_session_lease_v1(uuid,uuid),
  public.check_existing_user_session_lease_v1(uuid,uuid),
  public.release_existing_user_session_lease_v1(uuid,uuid) TO service_role;
