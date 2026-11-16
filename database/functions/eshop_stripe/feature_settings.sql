-- Released Stripe discovery boundary delegates to canonical scoped policy.
-- Consumer: published mobile versions reading stripe_preview_enabled and the old
-- feature endpoint. Remove after those supported clients retire. No second store.
CREATE OR REPLACE FUNCTION public.stripe_unit_feature_enabled_internal(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.payment_method_policy_enabled_internal(p_unit,'stripe'),false);
$$;
REVOKE ALL ON FUNCTION public.stripe_unit_feature_enabled_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.set_stripe_unit_feature(p_unit bigint,p_enabled boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE org bigint; input jsonb; preview jsonb;
BEGIN
 SELECT organization INTO org FROM public.units WHERE id=p_unit;
 IF NOT public.can_manage_organization_settings(org) OR NOT public.can_manage_payment_method_policy(org,p_unit) THEN RAISE insufficient_privilege; END IF;
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'PAYMENT_POLICY_MODE_INVALID'; END IF;
 input:=jsonb_build_object('organizationId',org,'unitId',p_unit,'method','stripe','mode',CASE WHEN p_enabled THEN 'enabled' ELSE 'disabled' END);
 preview:=public.preview_payment_method_policy(input);
 -- Legacy setter cannot acknowledge obligations: require the new preview UI.
 IF p_enabled=false AND ((preview#>>'{impact,openCollections}')::bigint>0 OR (preview#>>'{impact,pendingRequests}')::bigint>0) THEN RAISE EXCEPTION 'PAYMENT_POLICY_IMPACT_CONFIRMATION_REQUIRED'; END IF;
 PERFORM public.command_payment_method_policy(input,extensions.gen_random_uuid(),preview->>'confirmation');
 RETURN public.payment_method_policy_enabled_internal(p_unit,'stripe');
END $$;
REVOKE ALL ON FUNCTION public.set_stripe_unit_feature(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.set_stripe_unit_feature(bigint,boolean) TO authenticated;
