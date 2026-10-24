CREATE OR REPLACE FUNCTION get_is_editor_order_view_on_occasion(oc bigint) RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  select public.can_read_demo_occasion(oc) OR (NOT public.is_demo_occasion(oc) AND coalesce((
  select
    is_editor_order_view
  from
    occasion_users
  where
    "user" = auth.uid() and
    occasion = oc), false))
$$;