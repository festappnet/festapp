CREATE OR REPLACE FUNCTION public.begin_unit_client_mutation_v1(p_command_id uuid, p_command_name text, p_unit bigint, p_actor_id uuid, p_request_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  IF p_actor_id IS NULL OR p_actor_id IS DISTINCT FROM auth.uid()
     OR p_command_id IS NULL OR p_unit IS NULL
     OR p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$'
     OR NOT (CASE WHEN p_command_name IN ('occasion.create','occasion.setup.finalize')
       THEN public.can_create_occasion(p_unit)
       WHEN p_command_name='occasion.delete' THEN public.can_delete_occasion_in_unit(p_unit)
       WHEN p_command_name IN ('unit.information.save','unit.information.delete')
         THEN public.can_write_unit_information(p_unit)
       WHEN p_command_name IN ('unit.icon.save','unit.icon.delete')
         THEN public.can_write_unit_icons(p_unit)
       WHEN p_command_name IN ('unit.email_template.save','unit.email_template.reset','unit.email_banner.save')
         THEN public.can_write_unit_email_templates(p_unit)
       WHEN p_command_name IN ('profile.unit_access.delete','profile.unit_user.save') THEN public.can_manage_unit_users(p_unit)
       WHEN p_command_name='unit.config.save' THEN public.can_manage_unit_configuration(p_unit)
       WHEN p_command_name IN ('unit.cards.pause','unit.cards.disconnect') THEN public.can_manage_unit_configuration(p_unit) AND NOT public.is_demo_unit(p_unit)
       WHEN p_command_name='unit.order_history.delete' THEN public.can_manage_unit_configuration(p_unit) AND NOT public.is_demo_unit(p_unit)
       WHEN p_command_name='unit.delete' THEN public.can_manage_unit_configuration(p_unit) AND NOT public.is_demo_unit(p_unit)
       WHEN p_command_name IN ('unit.legal.save','unit.legal.submit') THEN public.can_manage_unit_legal_profile(p_unit)
       WHEN p_command_name IN ('unit.bank.save','unit.bank.link','unit.bank.user') THEN public.can_manage_unit_bank_accounts(p_unit)
       WHEN p_command_name='occasion.duplicate' THEN public.can_copy_occasion_target(p_unit)
       ELSE false END) THEN
    RAISE insufficient_privilege USING MESSAGE='invalid unit mutation receipt claim';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,unit,actor_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_unit,p_actor_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS NOT NULL OR v_receipt.unit IS DISTINCT FROM p_unit
     OR v_receipt.actor_id IS DISTINCT FROM p_actor_id OR v_receipt.actor_client_id IS NOT NULL
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
END; $function$
;
REVOKE ALL ON FUNCTION public.begin_unit_client_mutation_v1(p_command_id uuid, p_command_name text, p_unit bigint, p_actor_id uuid, p_request_sha256 text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.begin_unit_client_mutation_v1(uuid,text,bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_unit_client_mutation_v1(uuid,text,bigint,uuid,text) TO service_role;
