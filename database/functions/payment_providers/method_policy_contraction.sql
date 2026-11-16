-- Apply only after compatible backend, clients and renderers are installed.
-- Retain the one-time configuration evidence without retaining a second writer.
ALTER TABLE eshop.payment_method_policy_scopes ADD COLUMN IF NOT EXISTS migration_evidence jsonb;
UPDATE eshop.payment_method_policy_scopes s SET migration_evidence=jsonb_build_object(
 'legacyDefault',o.data->'DEFAULT_FORM_PAYMENT_METHOD',
 'stripeUnits',(SELECT coalesce(jsonb_agg(jsonb_build_object('unitId',u.id,'enabled',f.enabled) ORDER BY u.id),'[]')
  FROM public.units u JOIN eshop.stripe_unit_features f ON f.unit_id=u.id WHERE u.organization=o.id))
FROM public.organizations o WHERE o.id=s.organization_id AND s.migration_evidence IS NULL;
DROP TABLE eshop.stripe_unit_features RESTRICT;
UPDATE public.organizations SET data=data-'DEFAULT_FORM_PAYMENT_METHOD' WHERE data ? 'DEFAULT_FORM_PAYMENT_METHOD';
