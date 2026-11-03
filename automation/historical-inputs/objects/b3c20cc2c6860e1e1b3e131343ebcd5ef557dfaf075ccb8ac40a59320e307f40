CREATE OR REPLACE FUNCTION get_is_approved_on_occasion(oc bigint) RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  select coalesce((
  select
    is_approved
  from
    occasion_users
  where
    "user" = auth.uid() and
    occasion = oc), false)
$$;