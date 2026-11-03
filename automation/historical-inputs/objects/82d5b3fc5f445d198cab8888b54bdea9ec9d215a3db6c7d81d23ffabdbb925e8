-- Discovery/setup gate only. Sales remain governed by stripe_runtime_policy.
CREATE TABLE eshop.stripe_unit_features (
 unit_id bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 enabled boolean NOT NULL DEFAULT false,
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_by uuid
);
ALTER TABLE eshop.stripe_unit_features ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.stripe_unit_features FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.stripe_unit_feature_enabled_internal(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(f.enabled,org.data->>'DEFAULT_FORM_PAYMENT_METHOD'='stripe',false)
 FROM public.units u JOIN public.organizations org ON org.id=u.organization
 LEFT JOIN eshop.stripe_unit_features f ON f.unit_id=u.id WHERE u.id=p_unit
$$;
REVOKE ALL ON FUNCTION public.stripe_unit_feature_enabled_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.set_stripe_unit_feature(p_unit bigint,p_enabled boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE org bigint;
BEGIN
 SELECT organization INTO org FROM public.units WHERE id=p_unit;
 IF org IS NULL OR auth.uid() IS NULL OR NOT public.can_manage_organization_settings(org) THEN
  RAISE insufficient_privilege USING MESSAGE='STRIPE_ORGANIZATION_ADMIN_REQUIRED';
 END IF;
 IF p_enabled IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='Stripe feature setting must be boolean'; END IF;
 IF public.is_demo_unit(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='DEMO_UNIT_READ_ONLY'; END IF;
 -- Serialize with checkout and connection setup. Never alter retained money facts.
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 INSERT INTO eshop.stripe_unit_features(unit_id,enabled,updated_by)
 VALUES(p_unit,p_enabled,auth.uid()) ON CONFLICT(unit_id) DO UPDATE
 SET enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 RETURN p_enabled;
END $$;
REVOKE ALL ON FUNCTION public.set_stripe_unit_feature(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.set_stripe_unit_feature(bigint,boolean) TO authenticated;
