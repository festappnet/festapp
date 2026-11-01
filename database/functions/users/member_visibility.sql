-- Visibility is independent of roles. Callers still own operation authorization.
CREATE OR REPLACE FUNCTION public.organization_member_visible_internal(p_organization bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_organization IS NOT NULL AND p_user IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM public.organization_users m
  WHERE m.organization=p_organization AND m."user"=p_user AND m.is_hidden);
$$;
CREATE OR REPLACE FUNCTION public.occasion_member_visible_internal(p_occasion bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.organization_member_visible_internal(o.organization,p_user)
  FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.organization_member_visible_internal(bigint,uuid),public.occasion_member_visible_internal(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
