-- Cash setup and duplication traverse the existing public aggregate commands.
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE actor uuid; org bigint; un bigint; draft uuid:=gen_random_uuid(); d jsonb; payload jsonb; result jsonb;
 oc bigint; f bigint; fk uuid; product bigint; pid bigint; copied bigint; link text;
BEGIN
 PERFORM public.create_user_for_test('cash-setup','cash-setup-'||gen_random_uuid()||'@example.invalid');
 actor:=public.get_user_id('cash-setup');
 INSERT INTO public.organizations(title) VALUES('Cash setup') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Cash setup',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 d:=public.create_occasion_setup_draft(draft,un);
 RESET ROLE;
 payload:=d->'data'||jsonb_build_object('title','Hotovostní rezervace','formEnabled',true,
  'start',now()+interval '10 days','end',now()+interval '11 days','reviewConfirmed',true,
  'saleMode','immediate','blueprintMode','none','payments',
  jsonb_build_object('bankEnabled',false,'cashEnabled',true,'cashInstructions','U vstupu.','providerConnections','{}'::jsonb));
 payload:=jsonb_set(payload,'{formDraft,fields,2,product_type_data,products,0,price}','100');
 SET LOCAL ROLE authenticated;
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 result:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());
 RESET ROLE;
 oc:=(result#>>'{data,occasionId}')::bigint;
 SELECT id,key INTO STRICT f,fk FROM public.forms WHERE occasion=oc ORDER BY id LIMIT 1;
 PERFORM assert_true((SELECT bank_account IS NULL AND data#>'{payments,cashEnabled}'='true'::jsonb AND data#>>'{payment_deadline,mode}'='none' FROM public.forms WHERE id=f),'wizard saves explicit cash/none without bank');
 PERFORM assert_eq(public.form_payment_availability_internal(f)->'available','["cash"]'::jsonb,'wizard cash is available');
 SELECT o.link INTO link FROM public.occasions o WHERE o.id=oc;
 SET LOCAL ROLE authenticated;
 result:=public.duplicate_form_to_occasion_client_sync_v1(f,link,gen_random_uuid(),'cs');
 RESET ROLE;
 copied:=(result#>>'{data,formId}')::bigint;
 PERFORM assert_true(copied IS NOT NULL,'copy uses canonical versioned command: '||result::text);
 PERFORM assert_eq((SELECT data->'payments' FROM public.forms WHERE id=copied),(SELECT data->'payments' FROM public.forms WHERE id=f),'copy preserves cash choice and instructions');
 PERFORM assert_eq((SELECT data->'payment_deadline' FROM public.forms WHERE id=copied),'{"mode":"none"}'::jsonb,'copy retains explicit none');
 SELECT id INTO product FROM eshop.products WHERE occasion=oc ORDER BY id LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','anon',true);
 SET LOCAL ROLE anon;
 result:=public.create_ticket_order_client_sync_v1(jsonb_build_object('form',fk,'email','cash-setup@example.invalid',
  'client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product))))),gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(result->>'status','applied','wizard cash checkout: '||result::text);
 SELECT payment_info INTO pid FROM eshop.orders WHERE id=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_true((SELECT payment_method='cash' AND bank_account IS NULL AND deadline IS NULL AND variable_symbol IS NULL FROM eshop.payment_info WHERE id=pid),'wizard checkout retains the canonical cash snapshot');
END $$;
