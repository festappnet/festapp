-- Cleaning-crew permission on an occasion. True when the caller has the
-- per-occasion is_cleaning_crew flag on occasion_users, OR is an editor/admin
-- (editors implicitly get crew rights). Mirrors get_is_editor_order_on_occasion.
CREATE OR REPLACE FUNCTION public.get_is_cleaning_crew_on_occasion(oc bigint) RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  select coalesce((
  select
    is_cleaning_crew
  from
    occasion_users
  where
    "user" = auth.uid() and
    occasion = oc), false)
  or get_is_editor_on_occasion(oc)
$$;
