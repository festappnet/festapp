-- The unit manager who creates a copy must be able to administer its event
-- and orders, including an event with no orders yet.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint, p_command_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_response jsonb;
  v_new bigint;
  v_unit bigint;
BEGIN
  SELECT o.unit INTO v_unit FROM public.occasions o WHERE o.id = p_occasion;
  IF v_actor IS NULL OR v_unit IS NULL
     OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE = 'unit manager required';
  END IF;

  v_response := public.duplicate_occasion_domain_command_internal_v1(
    p_occasion, p_command_id);
  v_new := NULLIF(v_response #>> '{data,occasionId}', '')::bigint;
  IF v_response->>'status' = 'applied' AND v_new IS NOT NULL THEN
    INSERT INTO public.occasion_users
      (occasion, "user", is_manager, is_editor, is_editor_view,
       is_editor_order, is_editor_order_view)
    VALUES (v_new, v_actor, true, true, true, true, true)
    ON CONFLICT (occasion, "user") DO UPDATE
      SET is_manager = true, is_editor = true, is_editor_view = true,
          is_editor_order = true, is_editor_order_view = true;

    UPDATE public.occasions o
    SET data = jsonb_set(COALESCE(o.data, '{}'::jsonb),
      '{client_sync_v1}', 'false'::jsonb, true)
    WHERE o.id = v_new;
  END IF;
  RETURN v_response;
END; $$;

REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid)
  TO authenticated;
