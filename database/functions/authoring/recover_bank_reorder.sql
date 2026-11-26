-- Match the original command's named parameters for transport recovery.
CREATE OR REPLACE FUNCTION public.recover_bank_reorder(
 p_unit bigint,p_organization bigint,p_action text,p_payload jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_action IS DISTINCT FROM 'reorder' THEN
  RAISE invalid_parameter_value USING MESSAGE='bank reorder required';
 END IF;
 RETURN public.manage_bank_authoring(p_unit,p_organization,'recover_reorder',p_payload,p_command_id);
END $$;
REVOKE ALL ON FUNCTION public.recover_bank_reorder(bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.recover_bank_reorder(bigint,bigint,text,jsonb,uuid) TO authenticated;
