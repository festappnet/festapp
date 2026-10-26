CREATE OR REPLACE FUNCTION public.get_form_stripe_recipient(p_unit bigint,p_occasion bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.can_author_forms(p_occasion),false)
  OR NOT EXISTS(SELECT 1 FROM public.occasions o JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
    JOIN public.user_info actor ON actor.organization=o.organization AND actor.id=auth.uid()
    WHERE o.id=p_occasion AND u.id=p_unit) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 SELECT jsonb_build_object('connectionId',id,'name',business_name,'state',state,'paused',paused,
  'modelVerified',model_verified,'chargesEnabled',charges_enabled,'payoutsEnabled',payouts_enabled,
  'cardPaymentsActive',card_payments_active,'checkedAt',checked_at,
  'unsupportedReason',CASE WHEN EXISTS(SELECT 1 FROM eshop.external_services WHERE unit=p_unit AND type='FAKTUROID') THEN 'fakturoid_unsupported' END) INTO result
 FROM eshop.stripe_connections WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted');
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_stripe_recipient(bigint,bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_stripe_recipient(bigint,bigint,boolean) TO authenticated;
