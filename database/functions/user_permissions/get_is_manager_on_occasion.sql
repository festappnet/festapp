CREATE OR REPLACE FUNCTION get_is_manager_on_occasion(oc bigint) RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  select NOT public.is_demo_occasion(oc) AND coalesce((
  select
    is_manager
  from
    occasion_users
  where
    "user" = auth.uid() and
    occasion = oc), false)
$$;
