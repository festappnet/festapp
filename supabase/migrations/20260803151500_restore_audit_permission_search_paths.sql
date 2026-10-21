-- Hosted production drifted to NULL proconfig for these SECURITY DEFINER
-- permission helpers. Audit RPCs intentionally have an empty search_path, so
-- every nested helper must restore its own explicit trusted lookup path.
ALTER FUNCTION public.get_is_manager_on_occasion(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.get_is_admin_on_occasion(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.get_is_manager_on_unit(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.get_is_admin_on_organization(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.get_is_editor_view_on_occasion(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.get_is_editor_on_occasion(bigint)
  SET search_path = public, extensions;
