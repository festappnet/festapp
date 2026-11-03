CREATE OR REPLACE FUNCTION get_available_platforms(organization_id bigint)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    SELECT data -> 'PLATFORMS'
    FROM public.organizations
    WHERE id = organization_id;
$$;