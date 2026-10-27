-- Lock the stored resource scope and live authorization facts before delegating.
-- Row locks also fence revocation while a bounded read is in flight.
CREATE OR REPLACE FUNCTION public.lock_people_scope_internal_v1(p_occasion bigint,p_organization bigint DEFAULT NULL,p_unit bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE resource public.occasions%ROWTYPE; organizer public.units%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE insufficient_privilege USING MESSAGE='authenticated identity required'; END IF;
 IF p_occasion IS NOT NULL THEN
  SELECT * INTO resource FROM public.occasions WHERE id=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='occasion unavailable'; END IF;
  IF (p_organization IS NOT NULL AND resource.organization IS DISTINCT FROM p_organization)
    OR (p_unit IS NOT NULL AND resource.unit IS DISTINCT FROM p_unit) THEN
   RAISE insufficient_privilege USING MESSAGE='occasion scope changed'; END IF;
  SELECT * INTO organizer FROM public.units WHERE id=resource.unit FOR SHARE;
 ELSE
  SELECT * INTO organizer FROM public.units WHERE id=p_unit FOR SHARE;
 END IF;
 IF organizer.id IS NULL OR (p_organization IS NOT NULL AND organizer.organization IS DISTINCT FROM p_organization) THEN
  RAISE insufficient_privilege USING MESSAGE='organizer scope changed'; END IF;
 PERFORM 1 FROM public.organization_users WHERE organization=organizer.organization AND "user"=auth.uid() FOR SHARE;
 PERFORM 1 FROM public.unit_users WHERE unit=organizer.id AND "user"=auth.uid() FOR SHARE;
 IF p_occasion IS NOT NULL THEN
  PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=auth.uid() FOR SHARE;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_people_scope_internal_v1(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
