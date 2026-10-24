CREATE OR REPLACE FUNCTION public.create_ticket_order(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF public.payment_reference_scope_enabled_internal((SELECT id FROM public.forms WHERE key=(input_data->>'form')::uuid)) THEN
    RETURN jsonb_build_object('code',409,'errorCode','COMMAND_IDENTITY_REQUIRED'); END IF;
  RETURN public.create_ticket_order_client_sync_v1(input_data,
    extensions.gen_random_uuid(),COALESCE(auth.uid(),extensions.gen_random_uuid()))->'data';
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order(jsonb) TO anon,authenticated;


CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change(
  p_spot_ids bigint[],p_input_data jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  RETURN public.confirm_blueprint_order_change_client_sync_v1(
    p_spot_ids,p_input_data,extensions.gen_random_uuid())->'data';
END; $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change(bigint[],jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_blueprint_order_change(bigint[],jsonb)
  TO authenticated;

