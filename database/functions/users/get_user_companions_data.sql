CREATE OR REPLACE FUNCTION public.get_user_companions_data(p_occasion bigint)
RETURNS jsonb
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT jsonb_build_object('code',200,'data',payload->'companions')
  FROM (SELECT public.get_private_profile_payload_v1(
    p_occasion,auth.uid()) payload) projected
  WHERE EXISTS (SELECT 1 FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=auth.uid());
$$;

REVOKE ALL ON FUNCTION public.get_user_companions_data(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_companions_data(bigint)
  TO authenticated;
