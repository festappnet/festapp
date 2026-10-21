-- One live scan-link proof owner for session bootstrap and retained legacy
-- readers. The actual occasion comes from the stored secret relationship;
-- NULL is never a proof. This resolver does not grant editor capabilities.
CREATE OR REPLACE FUNCTION public.get_scanner_occasion_for_scan_code_internal(p_code text)
RETURNS SETOF public.occasions LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=public,extensions AS $$
 SELECT occasion.* FROM public.occasions occasion
 JOIN public.occasions_hidden hidden ON hidden.id=occasion.occasion_hidden
 WHERE p_code IS NOT NULL AND hidden.secret=p_code;
$$;
REVOKE ALL ON FUNCTION public.get_scanner_occasion_for_scan_code_internal(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_occasion_for_scan_code_internal(text) TO postgres;
