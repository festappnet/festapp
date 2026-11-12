-- One-time repair for the activated vstupenky.online organization only.
-- Other organizations retain their stored policies. Runtime cash defaults below
-- remain generic; explicit organization decisions and unit overrides still win.
DO $$
DECLARE target_org bigint;
BEGIN
 FOR target_org IN
  SELECT p.organization_id FROM eshop.organization_payment_method_policies p
  JOIN public.organizations o ON o.id=p.organization_id
  WHERE o.data->>'DEFAULT_URL'='https://vstupenky.online'
   AND p.method='cash' AND NOT p.enabled AND p.revision=1
   AND NOT EXISTS (
    SELECT 1 FROM eshop.payment_method_policy_commands c
    WHERE c.organization_id=p.organization_id AND c.input->>'method'='cash'
     AND nullif(c.input->>'unitId','') IS NULL)
  ORDER BY p.organization_id
 LOOP
  -- Same exclusive fence as an organization policy command. Recheck its
  -- decision after the fence so a concurrent explicit disable is preserved.
  PERFORM pg_advisory_xact_lock(hashtextextended('payment-policy:'||target_org,0));
  UPDATE eshop.organization_payment_method_policies p
  SET enabled=true, revision=p.revision+1
  WHERE p.organization_id=target_org AND p.method='cash'
   AND NOT p.enabled AND p.revision=1
   AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=p.organization_id
    AND o.data->>'DEFAULT_URL'='https://vstupenky.online')
   AND NOT EXISTS (
    SELECT 1 FROM eshop.payment_method_policy_commands c
    WHERE c.organization_id=p.organization_id AND c.input->>'method'='cash'
     AND nullif(c.input->>'unitId','') IS NULL);
 END LOOP;
END $$;
