CREATE OR REPLACE FUNCTION get_is_editor_on_any_occasion() RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  SELECT coalesce((
    SELECT
      true
    FROM
      occasion_users
    WHERE
      "user" = auth.uid() AND
      is_editor = true
    LIMIT 1
  ), false)
$$;