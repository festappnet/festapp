-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/helpers/refund_operation_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); org bigint:=(x->>'organization')::bigint; un bigint:=(x->>'unit')::bigint;
 sibling bigint; foreign_org bigint; policy jsonb; input jsonb; preview jsonb; response jsonb; cmd uuid:=gen_random_uuid();
 refund_cmd uuid:=gen_random_uuid(); payload jsonb; before_count bigint;
BEGIN
 INSERT INTO public.units(title,organization) VALUES('Sousední pořadatel',org) RETURNING id INTO sibling;
 INSERT INTO public.organizations(title) VALUES('Jiný tenant') RETURNING id INTO foreign_org;
 PERFORM assert_true(public.payment_method_policy_enabled_internal(un,'bank'),'explicit fixture bank permission');
 PERFORM assert_false(coalesce(public.payment_method_policy_enabled_internal(un,'missing'),false),'unknown method fails closed');
 PERFORM assert_false((public.resolve_payment_method_policy_internal(foreign_org,NULL)#>>'{methods,bank,policyEnabled}')::boolean,'new tenant has no implicit bank');
 BEGIN PERFORM public.resolve_payment_method_policy_internal(foreign_org,un); RAISE EXCEPTION 'scope mismatch accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_POLICY_SCOPE_MISMATCH' THEN RAISE; END IF; END;
 payload:=jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','100',
  'recipientIban',public.canonical_payment_reference_account_internal('1234/2010'),'recipientName','Jana Nováková');
 SET LOCAL ROLE authenticated;
 response:=public.command_payment_operation(payload,refund_cmd);
 RESET ROLE;
 PERFORM assert_true((response#>>'{data,request,instructionAllowed}')::boolean,'pending bank instructions explicitly authorized');
 input:=jsonb_build_object('organizationId',org,'unitId',un,'method','bank','mode','disabled');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input);
 response:=public.command_payment_method_policy(input,cmd,preview->>'confirmation');
 RESET ROLE;
 PERFORM assert_false(public.payment_method_policy_enabled_internal(un,'bank'),'unit disable effective');
 PERFORM assert_true(public.payment_method_policy_enabled_internal(sibling,'bank'),'neighbor inherits permission');
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=refund_cmd),'pending','disable retains request');
 SET LOCAL ROLE authenticated;
 response:=public.command_payment_operation(payload,refund_cmd);
 RESET ROLE;
 PERFORM assert_true(response#>'{data,request,instructions}' IS NULL OR response#>'{data,request,instructions}'='null'::jsonb,'replay removes disabled instructions');
 PERFORM assert_false(coalesce((response#>>'{data,request,canReopen}')::boolean,false),'disabled request cannot reopen');
 PERFORM assert_eq(response#>>'{data,context,pending}','100.00','disable preserves reservation');
 PERFORM assert_false(public.form_payment_availability_internal((x->>'form')::bigint)->'available' ? 'bank','disabled bank absent from public options');
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.command_payment_operation(payload,gen_random_uuid()); RAISE EXCEPTION 'disabled refund accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_REFUND_UNAVAILABLE' THEN RAISE; END IF; END;
 BEGIN PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation'); RAISE EXCEPTION 'stale preview accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_POLICY_PREVIEW_STALE' THEN RAISE; END IF; END;
 response:=public.get_transactions_for_order((x->>'order')::bigint);
 RESET ROLE;
 PERFORM assert_false(response->'actions' ? 'historyAccounts','order DTO has no unrelated account discovery');
 PERFORM assert_false((response#>>'{actions,canConfigureBank}')::boolean,'disabled order has no bank setup');
 -- Incoming verified facts still settle a request after product disable.
 response:=pg_temp.refund_bank_event(x,81,-12000);
 PERFORM assert_true((response#>>'{refund,matched}')::boolean,'late bank debit still observed');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),120::numeric,'excessive debit remains a real fact');
 DELETE FROM public.unit_users WHERE unit=un AND "user"=(x->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.command_payment_method_policy(input,cmd,preview->>'confirmation'); RAISE EXCEPTION 'revoked policy replay accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 PERFORM assert_false(has_table_privilege('authenticated','eshop.organization_payment_method_policies','INSERT'),'private policy storage');
END $$;
