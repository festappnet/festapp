-- New paid wizard form -> real checkout -> existing canonical reference registry.
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE actor uuid; org bigint; unit_id bigint; bank bigint; draft uuid:=gen_random_uuid();
 d jsonb; payload jsonb; response jsonb; form_id bigint; form_key uuid; product bigint;
 payment bigint; namespace text; symbol bigint; event_id bigint;
BEGIN
 PERFORM public.create_user_for_test('wizard-policy','wizard-policy-'||gen_random_uuid()||'@example.invalid');
 actor:=public.get_user_id('wizard-policy');
 INSERT INTO public.organizations(title) VALUES('Wizard policy fixture') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Wizard policy unit',org) RETURNING id INTO unit_id;
 INSERT INTO public.unit_users("user",unit,is_manager,is_editor) VALUES(actor,unit_id,true,true);
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
  VALUES('Wizard policy account','FIO','9876543210/2010',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(unit_id,bank,0);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft,unit_id);
 EXECUTE 'RESET ROLE';
 payload:=d->'data'||jsonb_build_object('title','Automatic reference wizard','formEnabled',true,
  'start',now()+interval '10 days','end',now()+interval '11 days','reviewConfirmed',true,
  'saleMode','immediate','blueprintMode','none','paymentMethod','bank','bankAccountId',bank,
  'bankAccountFingerprint',public.occasion_setup_bank_fingerprint_internal(bank));
 payload:=payload #- '{formDraft,data,variable_symbol}';
 payload:=jsonb_set(payload,'{formDraft,fields,2,product_type_data,products,0,price}','100');
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 response:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());
 EXECUTE 'RESET ROLE';
 event_id:=(response#>>'{data,occasionId}')::bigint;
 SELECT id,key INTO form_id,form_key FROM public.forms WHERE occasion=event_id ORDER BY id LIMIT 1;
 PERFORM assert_true(form_id IS NOT NULL,'Paid wizard completes without any explicit reference policy');
 PERFORM assert_true(coalesce((SELECT data#>>'{variable_symbol,type}' FROM public.forms WHERE id=form_id),'random')='random','Server default remains random');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 namespace:=public.enroll_payment_reference_account(bank);
 INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES(org,'active',repeat('a',64));
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true WHERE id=namespace;
 SELECT id INTO product FROM eshop.products WHERE occasion=event_id ORDER BY id LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','anon',true);
 EXECUTE 'SET LOCAL ROLE anon';
 response:=public.create_ticket_order_client_sync_v1(jsonb_build_object('form',form_key,'email','wizard-checkout@example.invalid',
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product))))),gen_random_uuid(),gen_random_uuid());
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(response->>'status','applied','Synthetic checkout uses the real form and transaction owner');
 SELECT payment_info INTO payment FROM eshop.orders WHERE id=(response#>>'{data,order,id}')::bigint;
 SELECT variable_symbol INTO symbol FROM eshop.payment_info WHERE id=payment;
 PERFORM assert_true(symbol BETWEEN 1 AND 9999999999,'Canonical allocator assigns the VS during checkout');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.payment_reference_reservations WHERE payment_info_id=payment AND namespace_id=namespace AND variable_symbol=symbol),'Assigned symbol is reserved in the existing registry');
END $$;

-- The existing settings normalizer remains authoritative for advanced edits.
DO $$
DECLARE policy jsonb; result jsonb;
BEGIN
 FOREACH policy IN ARRAY ARRAY[
  '{"type":"sequence"}'::jsonb,'{"type":"sequence","starting_number":null}',
  '{"type":"sequence","starting_number":0}','{"type":"sequence","starting_number":10000000000}',
  '{"type":"sequence","starting_number":1.5}'
 ] LOOP
  BEGIN
   PERFORM public.apply_form_settings_internal('{}',jsonb_build_object('variable_symbol',policy));
   RAISE EXCEPTION 'Invalid explicit sequence accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH policy IN ARRAY ARRAY['{"type":"sequence","starting_number":1}'::jsonb,'{"type":"sequence","starting_number":9999999999}'] LOOP
  result:=public.apply_form_settings_internal('{}',jsonb_build_object('variable_symbol',policy));
  PERFORM assert_eq(result->'variable_symbol',policy,'Advanced explicit sequence bounds are preserved');
 END LOOP;
END $$;
