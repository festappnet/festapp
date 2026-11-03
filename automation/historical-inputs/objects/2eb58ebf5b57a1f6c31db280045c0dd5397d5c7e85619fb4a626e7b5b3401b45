BEGIN;

-- Occasion settings are edited from the unit workspace. Keep the explicit
-- wrapper authorization aligned with both that UI contract and the trusted
-- update_occasion_internal_v1 implementation, which authorizes the target
-- unit editor before changing the aggregate.
CREATE OR REPLACE FUNCTION public.save_occasion_client_sync_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_config jsonb;
  v_data jsonb;
  v_enabled boolean;
  v_hidden boolean;
  v_unit bigint;
BEGIN
  SELECT
    COALESCE((o.data->>'client_sync_v1')::boolean, false),
    o.is_hidden,
    o.unit
  INTO v_enabled, v_hidden, v_unit
  FROM public.occasions o
  WHERE o.id = p_occasion;

  IF auth.uid() IS NULL OR NOT (
    public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR (v_unit IS NOT NULL AND public.get_is_editor_on_unit(v_unit))
  ) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  IF v_enabled
    AND NOT v_hidden
    AND COALESCE((p_config->>'is_hidden')::boolean, false)
  THEN
    RAISE object_not_in_prerequisite_state
      USING MESSAGE = 'disable client_sync_v1 before hiding occasion';
  END IF;

  v_data := CASE
    WHEN jsonb_typeof(p_config->'data') = 'object' THEN p_config->'data'
    ELSE '{}'::jsonb
  END;
  v_config := jsonb_set(
    p_config,
    '{data}',
    jsonb_set(
      v_data,
      '{client_sync_v1}',
      to_jsonb(COALESCE(v_enabled, false)),
      true
    ),
    true
  );

  RETURN public.save_occasion_domain_command_internal_v1(
    p_occasion,
    p_command_id,
    p_expected_version,
    v_config
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_occasion_client_sync_v1(
  bigint,
  uuid,
  bigint,
  jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_occasion_client_sync_v1(
  bigint,
  uuid,
  bigint,
  jsonb
) TO authenticated;

COMMIT;
