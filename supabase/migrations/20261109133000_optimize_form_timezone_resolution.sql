-- Resolve inherited form timezones with one catalog scan, preserving strict name validation.
BEGIN;
-- Shared presentation metadata; no lifecycle or capability decisions.
CREATE OR REPLACE FUNCTION public.get_waitlist_form_timezone_internal(p_form bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH config AS MATERIALIZED (
  SELECT array_remove(ARRAY[nullif(occ.data->>'timezone',''),nullif(u.data->>'timezone',''),
   nullif(org.data->>'timezone','')],NULL) zones
  FROM public.forms f JOIN public.occasions occ ON occ.id=f.occasion
  LEFT JOIN public.units u ON u.id=occ.unit
  LEFT JOIN public.organizations org ON org.id=occ.organization
  WHERE f.id=p_form
 )
 -- Enumerating pg_timezone_names reads the whole catalog. Validate all three
 -- preferences in one pass, and avoid that work when no preference is set.
 SELECT CASE WHEN cardinality(zones)=0 THEN 'Europe/Prague' ELSE coalesce((
  SELECT name FROM pg_timezone_names WHERE name=ANY(config.zones)
  ORDER BY array_position(config.zones,name) LIMIT 1
 ),'Europe/Prague') END FROM config;
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_form_timezone_internal(bigint) FROM PUBLIC,anon,authenticated;
COMMIT;
