CREATE OR REPLACE FUNCTION public.get_is_manager_on_unit(unit_id bigint) RETURNS bool
    LANGUAGE plpgsql STABLE
    SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
 RETURN (
 SELECT NOT public.is_demo_unit(unit_id) AND EXISTS (
    SELECT 1
    FROM public.unit_users membership
    WHERE membership."user" = auth.uid()
      AND membership.unit = unit_id
      AND membership.is_manager
  )
 );
END;
$$;
REVOKE ALL ON FUNCTION public.get_is_manager_on_unit(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_manager_on_unit(bigint) TO anon,authenticated,service_role;
