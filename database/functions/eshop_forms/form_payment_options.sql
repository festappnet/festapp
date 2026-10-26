-- One bank selection projection for the editor and MCP. Linked accounts only;
-- bank management, connection onboarding and provider effects are separate.
CREATE OR REPLACE FUNCTION public.get_form_bank_accounts_internal(p_unit bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',ba.id,'account_number',ba.account_number,
  'account_number_human_readable',ba.account_number_human_readable,'title',ba.title,
  'supported_currencies',ba.supported_currencies,'type',ba.type,
  'bank_sync_warning',public.bank_sync_warning(ba.id)) ORDER BY uba.priority,ba.id),'[]')
 FROM eshop.unit_bank_accounts uba JOIN eshop.bank_accounts ba ON ba.id=uba.bank_account
 WHERE uba.unit=p_unit AND ba.type IS DISTINCT FROM 'CASH';
$$;
REVOKE ALL ON FUNCTION public.get_form_bank_accounts_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_form_payment_options(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,'save');
 IF p_livemode IS NULL OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='foreign form or missing Stripe environment'; END IF;
 result:=jsonb_build_object('occasionId',p_occasion,'formId',p_form,'livemode',p_livemode,
  'bankAccounts',public.get_form_bank_accounts_internal(p_unit),
  'stripeRecipient',public.get_form_stripe_recipient(p_unit,p_occasion,p_livemode),
  'availability',public.form_payment_availability_internal(p_form));
 IF octet_length(result::text)>1048576 OR jsonb_array_length(result->'bankAccounts')>100 THEN
  RAISE program_limit_exceeded USING MESSAGE='form payment options too large'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_payment_options(bigint,bigint,bigint,bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_payment_options(bigint,bigint,bigint,bigint,boolean) TO authenticated;
