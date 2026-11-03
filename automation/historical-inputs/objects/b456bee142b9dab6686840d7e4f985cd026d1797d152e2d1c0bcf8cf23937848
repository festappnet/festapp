CREATE OR REPLACE FUNCTION get_is_editor_view_on_unit(unit_id bigint) RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  select coalesce((
  select
    is_editor_view
  from
    unit_users
  where
    "user" = auth.uid() and
    unit = unit_id), false)
$$;