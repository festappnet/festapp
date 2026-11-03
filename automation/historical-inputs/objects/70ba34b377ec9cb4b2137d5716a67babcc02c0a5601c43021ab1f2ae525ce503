-- Transition-only capability bootstrap. v217/v218 remain unchanged for
-- released clients; a context selects legacy or client_sync_v1 exactly once.
CREATE OR REPLACE FUNCTION public.get_app_config_v219(data_in jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
  v_occasion bigint;
  v_enabled boolean := false;
BEGIN
  v_result := public.get_app_config_v218(data_in);
  v_occasion := (v_result#>>'{occasion,id}')::bigint;
  IF v_occasion IS NOT NULL THEN
    SELECT COALESCE((o.data->>'client_sync_v1')::boolean, false)
      AND NOT EXISTS (
        SELECT 1 FROM public.client_sync_component_sources s
        WHERE s.registry_version=(SELECT max(v.registry_version)
          FROM public.client_sync_component_sources v)
          AND NOT s.cutover_ready)
      INTO v_enabled
    FROM public.occasions o
    WHERE o.id = v_occasion;
  END IF;
  RETURN v_result || jsonb_build_object('client_sync_v1', v_enabled);
END;
$$;

REVOKE ALL ON FUNCTION public.get_app_config_v219(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_config_v219(jsonb)
  TO anon, authenticated;
