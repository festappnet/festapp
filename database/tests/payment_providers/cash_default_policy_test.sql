-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/helpers/cash_default_policy_fixture.sql
-- test-setup: database/functions/payment_providers/cash_policy_defaults.sql
DO $$
DECLARE org bigint; un bigint; x jsonb; c jsonb; result jsonb; input jsonb; preview jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Nový pořadatel') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Taneční spolek',org) RETURNING id INTO un;
 c:=public.resolve_payment_method_policy_internal(org,un);
 PERFORM assert_true((c#>>'{methods,cash,policyEnabled}')::boolean,'cash enabled by default for new organizations');
 PERFORM assert_true((c#>>'{methods,cash,organizationEnabled}')::boolean,'organization settings show the effective cash default');
 PERFORM assert_false((c#>>'{methods,bank,policyEnabled}')::boolean,'other unconfigured methods still fail closed');
 PERFORM assert_true((SELECT enabled FROM eshop.organization_payment_method_policies WHERE organization_id=(SELECT organization_id FROM cash_default_policy_cases WHERE kind='legacy') AND method='cash'),'legacy inferred disable repaired');
 PERFORM assert_false((SELECT enabled FROM eshop.organization_payment_method_policies WHERE organization_id=(SELECT organization_id FROM cash_default_policy_cases WHERE kind='explicit') AND method='cash'),'explicit organization disable retained');
 PERFORM assert_false((SELECT enabled FROM eshop.organization_payment_method_policies WHERE organization_id=(SELECT organization_id FROM cash_default_policy_cases WHERE kind='other') AND method='cash'),'other organizations are outside the backfill scope');
 x:=pg_temp.payment_fixture();
 DELETE FROM eshop.organization_payment_method_policies WHERE organization_id=(x->>'organization')::bigint AND method='cash';
 SET LOCAL ROLE authenticated;
 c:=public.get_payment_operation_context((x->>'order')::bigint);
 result:=public.command_payment_operation(jsonb_build_object('operation','record_payment','orderId',x->'order','method','cash','amount','50','receivedAt',now()),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(c#>'{context,methods}') m WHERE m->>'id'='cash' AND m->'record'='true'::jsonb),'manager can add cash without a saved cash policy');
 PERFORM assert_eq(result->>'code','200','cash command actually commits');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),50::numeric,'cash receipt reaches the ledger');
 input:=jsonb_build_object('organizationId',x->'organization','unitId',(SELECT unit FROM public.occasions WHERE id=(x->>'occasion')::bigint),'method','cash','mode','disabled');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input);
 PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 c:=public.get_payment_operation_context((x->>'order')::bigint);
 BEGIN
  PERFORM public.command_payment_operation(jsonb_build_object('operation','record_payment','orderId',x->'order','method','cash','amount','10','receivedAt',now()),gen_random_uuid());
  RAISE EXCEPTION 'explicit disabled cash accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_RECORD_UNAVAILABLE' THEN RAISE; END IF; END;
 RESET ROLE;
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(c#>'{context,methods}') m WHERE m->>'id'='cash' AND m->'record'='true'::jsonb),'explicit unit disable still wins');
 DELETE FROM public.unit_users WHERE unit=(input->>'unitId')::bigint AND "user"=(x->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.command_payment_operation(jsonb_build_object('operation','record_payment','orderId',x->'order','method','cash','amount','10','receivedAt',now()),gen_random_uuid());
  RAISE EXCEPTION 'cash without manager accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END $$;
