CREATE OR REPLACE FUNCTION get_exists_on_occasion(oc bigint) RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  select exists(
  select
    1
  from
    occasion_users
  where
    "user" = auth.uid() and
    occasion = oc)
$$;