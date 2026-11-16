-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); org bigint:=(x->>'organization')::bigint; un bigint; sibling bigint; input jsonb; preview jsonb; response jsonb; actor uuid:=(x->>'actor')::uuid;
 bank bigint:=(x->>'bank')::bigint; new_form jsonb; email_accounts jsonb;
BEGIN
 SELECT unit INTO un FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,actor,true);
 INSERT INTO public.units(title,organization) VALUES('Sousední pořadatel',org) RETURNING id INTO sibling;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(sibling,actor,true);
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(sibling,bank);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date) VALUES(bank,10,'CZK',now());
 input:=jsonb_build_object('organizationId',org,'unitId',un,'method','bank','mode','disabled');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input); PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 BEGIN PERFORM public.get_bank_transaction_history(bank,un); RAISE EXCEPTION 'disabled statement accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 response:=public.get_bank_transaction_history(bank,sibling);
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(response),1,'explicit enabled sibling can read the physical statement with both roles');
 DELETE FROM public.unit_users WHERE unit=sibling AND "user"=actor;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.get_bank_transaction_history(bank,sibling); RAISE EXCEPTION 'spoofed sibling accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 -- Tenant restriction dominates an explicit enabled unit, and the preference is canonical.
 input:=jsonb_build_object('organizationId',org,'method','bank','mode','disabled','preferredMethod','stripe');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input); PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 input:=jsonb_build_object('organizationId',org,'unitId',un,'method','bank','mode','enabled');
 preview:=public.preview_payment_method_policy(input); response:=public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 BEGIN PERFORM public.get_bank_accounts_for_unit_management(un); RAISE EXCEPTION 'disabled bank management exposed accounts'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_linkable_bank_accounts(un); RAISE EXCEPTION 'disabled link picker exposed accounts'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 email_accounts:=public.get_email_authoring_payment_accounts(un,(x->>'occasion')::bigint);
 RESET ROLE;
 PERFORM assert_eq(email_accounts->'linkedAccounts','[]'::jsonb,'disabled email authoring has no ordinary receiving accounts');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_false(public.payment_method_policy_enabled_internal(un,'bank'),'unit enabled cannot override tenant disabled');
 PERFORM assert_false(public.payment_method_policy_enabled_internal(sibling,'bank'),'tenant restriction also reaches sibling');
 PERFORM assert_eq(response#>>'{methods,bank,reason}','organization_disabled','reason retains tenant authority');
 PERFORM assert_eq(public.get_form_bank_accounts_internal(un),'[]'::jsonb,'authoring reader has no account choices');
 PERFORM assert_false(public.form_payment_availability_internal((x->>'form')::bigint)->'available' ? 'bank','stale form bank=true cannot advertise a disabled method');
 new_form:=public.insert_form_for_occasion_internal_v1((x->>'occasion')::bigint,'global-default-'||gen_random_uuid(),'Nový formulář');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.forms f WHERE f.occasion=(x->>'occasion')::bigint AND f.title='Nový formulář' AND f.data#>'{payments,bankEnabled}'='true'::jsonb),'new form uses Stripe preference with no bank fallback');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.forms f WHERE f.occasion=(x->>'occasion')::bigint AND f.title='Nový formulář' AND f.is_open),'default awaits a ready recipient in a closed draft');
END $$;
