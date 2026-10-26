-- Canonical receipt entry points reject demo mutations before creating a receipt.
CREATE OR REPLACE FUNCTION public.begin_anonymous_client_mutation_v1(p_command_id uuid, p_command_name text, p_occasion bigint, p_actor_client_id uuid, p_request_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  PERFORM public.check_occasion_writable(p_occasion);
  IF auth.uid() IS NOT NULL OR p_actor_client_id IS NULL OR p_command_id IS NULL
     OR p_occasion IS NULL OR p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid anonymous mutation receipt claim';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,occasion,actor_client_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_occasion,p_actor_client_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS DISTINCT FROM p_occasion OR v_receipt.actor_id IS NOT NULL
     OR v_receipt.actor_client_id IS DISTINCT FROM p_actor_client_id
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  ELSIF v_receipt.status='expired' THEN
    RETURN jsonb_build_object('disposition','replay',
      'response',public.expired_client_mutation_response_v1(v_receipt));
  END IF;
  IF v_inserted<>1 THEN RAISE serialization_failure
    USING MESSAGE='incomplete mutation receipt cannot be resumed'; END IF;
  RETURN jsonb_build_object('disposition','claimed');
END; $function$;

CREATE OR REPLACE FUNCTION public.begin_client_mutation_v1(p_command_id uuid, p_command_name text, p_occasion bigint, p_actor_id uuid, p_request_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  PERFORM public.check_occasion_writable(p_occasion);
  IF p_command_id IS NULL OR p_actor_id IS NULL OR p_actor_id IS DISTINCT FROM auth.uid() THEN
    RAISE insufficient_privilege USING MESSAGE='authenticated command actor required';
  END IF;
  IF p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid mutation receipt metadata';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,occasion,actor_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_occasion,p_actor_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS DISTINCT FROM p_occasion
     OR v_receipt.actor_id IS DISTINCT FROM p_actor_id
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  ELSIF v_receipt.status='expired' THEN
    RETURN jsonb_build_object('disposition','replay',
      'response',public.expired_client_mutation_response_v1(v_receipt));
  END IF;
  IF v_inserted<>1 THEN RAISE serialization_failure
    USING MESSAGE='incomplete mutation receipt cannot be resumed'; END IF;
  RETURN jsonb_build_object('disposition','claimed');
END; $function$;
