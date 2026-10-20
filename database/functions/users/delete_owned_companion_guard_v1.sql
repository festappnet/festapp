CREATE OR REPLACE FUNCTION public.delete_owned_companion_guard_v1(p_occasion bigint, p_companion uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_policy jsonb;
BEGIN
  v_policy:=public.get_companion_feature_policy_v1(p_occasion);
  IF NOT COALESCE((v_policy->>'is_enabled')::boolean,false)
      OR NOT COALESCE((v_policy->>'allow_user_create')::boolean,true) THEN
    RAISE insufficient_privilege USING MESSAGE='self-created companion lifecycle disabled';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_companions uc
    WHERE uc.occasion=p_occasion AND uc."user"=auth.uid()
      AND uc.companion=p_companion AND uc.origin='self_created') THEN
    RAISE insufficient_privilege USING MESSAGE='self-created companion ownership required';
  END IF;
END $function$
;
REVOKE ALL ON FUNCTION public.delete_owned_companion_guard_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
