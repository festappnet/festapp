CREATE OR REPLACE FUNCTION get_is_editor_on_unit(unit_id bigint) RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  select NOT public.is_demo_unit(unit_id) AND coalesce((
  select
    is_editor
  from
    unit_users
  where
    "user" = auth.uid() and
    unit = unit_id), false)
$$;
