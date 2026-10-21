-- Scope arguments can only narrow the authenticated actor's live rights.
-- Resource bindings are locked and checked in the SAME request that returns
-- the data or executes/replays the command. A previous HTTP lookup is no proof.
CREATE OR REPLACE FUNCTION public.get_delegated_ticket_layout_for_authoring_v1(
  p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_unit bigint;
BEGIN
  SELECT o.unit INTO v_unit FROM public.occasions o
    WHERE o.id=p_occasion AND o.organization=p_organization
      AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info ui
      WHERE ui.id=auth.uid() AND ui.organization=p_organization) THEN
    RAISE insufficient_privilege USING MESSAGE='delegated occasion context unavailable';
  END IF;
  RETURN public.get_ticket_layout_for_authoring_v1(p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_delegated_ticket_layout_for_authoring_v1(bigint,bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_delegated_ticket_layout_for_authoring_v1(bigint,bigint,bigint) TO authenticated;

-- Creation uses the same live operation predicate as the application.
-- The delegated adapter additionally verifies the tenant binding before replay.
CREATE OR REPLACE FUNCTION public.create_delegated_occasion_client_sync_v1(
  p_command_id uuid,p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_unit bigint:=(p_config->>'unit')::bigint;
  v_organization bigint:=(p_config->>'organization')::bigint;
BEGIN
  PERFORM 1 FROM public.units u WHERE u.id=v_unit AND u.organization=v_organization FOR SHARE;
  IF NOT FOUND OR auth.uid() IS NULL
    OR NOT public.can_create_occasion(v_unit)
    OR NOT EXISTS(SELECT 1 FROM public.user_info ui WHERE ui.id=auth.uid() AND ui.organization=v_organization) THEN
    RAISE insufficient_privilege USING MESSAGE='delegated unit manager required';
  END IF;
  RETURN public.create_occasion_client_sync_v1(p_command_id,p_config);
END $$;
REVOKE ALL ON FUNCTION public.create_delegated_occasion_client_sync_v1(uuid,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_delegated_occasion_client_sync_v1(uuid,jsonb) TO authenticated;
