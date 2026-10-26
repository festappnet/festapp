CREATE OR REPLACE FUNCTION get_is_admin_on_organization(org bigint) RETURNS bool
    LANGUAGE "sql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
  select coalesce((
  select
    is_admin
  from
    organization_users
  where
    "user" = auth.uid() and
    organization = org), false)
$$;