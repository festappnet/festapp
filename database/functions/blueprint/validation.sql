-- One canonical document contract; resource readiness is authorized by Save.
CREATE OR REPLACE FUNCTION public.validate_blueprint_layout_internal(p_doc jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.validate_blueprint_canonical_declarations_internal(p_doc);
 PERFORM public.validate_blueprint_geometry_internal(p_doc);
END $$;
REVOKE ALL ON FUNCTION public.validate_blueprint_layout_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
