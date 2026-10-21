-- get_app_config_v219 deliberately runs with an empty search_path. Its call to
-- v218 therefore also inherited an empty path, while v218 still references
-- public relations by their legacy unqualified names. Give the established
-- v218 implementation an explicit, fixed path so v219 remains hardened and
-- the released v218 contract keeps its existing behavior.
ALTER FUNCTION public.get_app_config_v218(jsonb)
  SET search_path = public, extensions;
