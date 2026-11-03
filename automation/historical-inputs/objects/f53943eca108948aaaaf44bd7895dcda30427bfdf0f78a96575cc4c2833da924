-- Raw mutation is retired. There is no post-publication renumbering UI/contract.
CREATE OR REPLACE FUNCTION public.update_payment_info_variable_symbol(p_payment_info_id bigint,p_variable_symbol bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RAISE EXCEPTION 'PAYMENT_REFERENCE_COMMAND_REQUIRED';
END $$;
REVOKE ALL ON FUNCTION public.update_payment_info_variable_symbol(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
