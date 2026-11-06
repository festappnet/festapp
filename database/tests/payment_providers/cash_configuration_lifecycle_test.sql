-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(200); f bigint:=(x->>'form')::bigint; oc bigint:=(x->>'occasion')::bigint;
 oid bigint:=(x->>'order')::bigint; pid bigint:=(x->>'payment')::bigint; un bigint; org bigint;
 payload jsonb; response jsonb; replay jsonb; saved jsonb; cash_order bigint; cash_payment bigint;
 command uuid:=gen_random_uuid(); session uuid:=gen_random_uuid(); edit_command uuid:=gen_random_uuid();
 original_response jsonb; stale_reminder public.email_messages; form_revision bigint; revision text; movement jsonb; movement_command uuid:=gen_random_uuid(); tid bigint; policy jsonb;
BEGIN
 SELECT unit,organization INTO un,org FROM public.occasions WHERE id=oc;
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',f,'cash-policy-'||f,false) WHERE id=f;
 -- Existing receipted order editor changes policy and fences pending reminders.
 SELECT * INTO STRICT stale_reminder FROM public.email_messages WHERE order_id=oid AND message_kind='order_reminder' ORDER BY message_id LIMIT 1;
 revision:=public.operator_order_revision_internal_v1(oid);
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=oc AND aggregate_id=f::text),0) INTO form_revision;
 SET LOCAL ROLE authenticated;
 response:=public.manage_operator_order_v1(oc,org,un,oid,edit_command,
  revision,'update','{"paymentDeadline":null}');
 RESET ROLE;
 PERFORM assert_eq(response->>'code','200','existing order deadline command: '||response::text);
 PERFORM assert_true((SELECT deadline IS NULL AND deposit_deadline IS NULL AND data#>>'{payment_policy,mode}'='none' FROM eshop.payment_info WHERE id=pid),'none clears both bank deadlines');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=oid AND message_kind='order_reminder' AND workflow_state IN ('pending','retry_wait','blocked','preparing')),'none cancels reminders');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 PERFORM assert_true(NOT public.email_intent_valid(stale_reminder),'already queued reminder fails final send eligibility after none');
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM pg_temp.payment_edit(x,1100);
 PERFORM assert_true((SELECT deadline IS NULL FROM eshop.payment_info WHERE id=pid),'none survives product edit');
 -- Store explicit cash through the real versioned settings owner, not direct flags.
 payload:=jsonb_build_object('id',f,'occasion',oc,'expected_aggregate_version',form_revision,
  'payment_selection_intent','replace','bank_account',NULL,'settings',jsonb_build_object('payments',
   jsonb_build_object('bankEnabled',false,'cashEnabled',true,'cashInstructions','Uhraďte u vstupu.','providerConnections','{}'::jsonb),'payment_deadline',jsonb_build_object('mode','none')));
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=oc AND aggregate_id=f::text),0) INTO form_revision;
 SET LOCAL ROLE authenticated;
 response:=public.update_form_client_sync_v1(payload,gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(response->>'code','200','cash settings save: '||response::text);
 SELECT data INTO saved FROM public.forms WHERE id=f;
 PERFORM assert_true(saved#>'{payments,cashEnabled}'='true'::jsonb,'cash stored explicitly');
 -- An unrelated legacy metadata save retains omitted policy. Conflicting old full saves fail atomically.
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=oc AND aggregate_id=f::text),0) INTO form_revision;
 SET LOCAL ROLE authenticated;
 response:=public.update_form_client_sync_v1(jsonb_build_object('id',f,'occasion',oc,'expected_aggregate_version',
  form_revision,'title','Nový název','data','{"communication_tone":"formal"}'::jsonb),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(response->>'code','200','unrelated old save preserves omitted payments: '||response::text);
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=oc AND aggregate_id=f::text),0) INTO form_revision;
 SET LOCAL ROLE authenticated;
 response:=public.update_form_client_sync_v1(jsonb_build_object('id',f,'occasion',oc,'expected_aggregate_version',
  form_revision,'data','{"payments":{"bankEnabled":true,"providerConnections":{}}}'::jsonb),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(response#>>'{data,errorCode}','PAYMENT_CLIENT_UPDATE_REQUIRED','old bank full save cannot overwrite cash: '||response::text);
 PERFORM assert_true((SELECT data#>'{payments,cashEnabled}'='true'::jsonb FROM public.forms WHERE id=f),'rejected full save is atomic');
 PERFORM assert_eq((public.get_form_by_link((SELECT link FROM public.forms WHERE id=f))::jsonb)->>'errorCode','PAYMENT_CLIENT_UPDATE_REQUIRED','old public reader refuses cash');
 payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=f),'email','cash@example.invalid','payment_method','cash',
  'client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))));
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=oc AND aggregate_id=f::text),0) INTO form_revision;
 SET LOCAL ROLE authenticated;
 response:=public.create_ticket_order_client_sync_v1(payload,command,session);
 RESET ROLE;
 PERFORM assert_eq(response->>'status','applied','cash checkout: '||response::text);
 original_response:=response;
 cash_order:=(response#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO cash_payment FROM eshop.orders WHERE id=cash_order;
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE order_id=cash_order) AND NOT EXISTS(SELECT 1 FROM eshop.barion_attempts WHERE order_id=cash_order),'cash creates no online attempt');
 -- Adding mandatory invoicing later must invalidate cash checkout before commit.
 INSERT INTO eshop.external_services(unit,type,data) VALUES(un,'FAKTUROID','{}');
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=oc AND aggregate_id=f::text),0) INTO form_revision;
 SET LOCAL ROLE authenticated;
 response:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(response->>'status','rejected','late invoice configuration cannot bypass mandatory invoicing');
 PERFORM assert_true(response::text LIKE '%CASH_FAKTUROID_UNSUPPORTED%','specific invoice incompatibility');
 DELETE FROM eshop.external_services WHERE unit=un AND type='FAKTUROID';
 -- Receipted exact movement replay records one ledger row and preserves decimal facts.
 movement:=jsonb_build_object('amount','250.50','currency','CZK','unitId',un,'paymentInfoId',cash_payment,'receivedAt',now(),'note','U vstupu');
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=oc AND aggregate_id=f::text),0) INTO form_revision;
 SET LOCAL ROLE authenticated;
 response:=public.insert_manual_transaction(movement,movement_command);
 replay:=public.insert_manual_transaction(movement,movement_command);
 RESET ROLE;
 PERFORM assert_eq(response->>'code','200','cash command accepted: '||response::text);
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE payment_info=cash_payment),1::bigint,'cash replay makes one movement');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=cash_payment),250.50::numeric,'exact decimal ledger');
 -- A later form change never rewrites committed checkout instructions or its receipt.
 UPDATE public.forms SET data='{"payments":{"bankEnabled":true,"cashEnabled":false,"providerConnections":{}}}',bank_account=(x->>'bank')::bigint WHERE id=f;
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=oc AND aggregate_id=f::text),0) INTO form_revision;
 SET LOCAL ROLE authenticated;
 replay:=public.create_ticket_order_client_sync_v1(payload,command,session);
 RESET ROLE;
 PERFORM assert_eq(replay#>'{data,order,payment_info}',original_response#>'{data,order,payment_info}','checkout replay retains cash snapshot after config change');
 -- Storno remains immutable for cash recording and correction.
 UPDATE eshop.orders SET state='storno' WHERE id=cash_order;
 BEGIN
  PERFORM public.insert_manual_transaction_internal_v1(1,'CZK',un,NULL,now(),NULL,cash_payment);
  RAISE EXCEPTION 'cash after cancellation accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 SELECT id INTO tid FROM eshop.transactions WHERE payment_info=cash_payment;
 BEGIN
  PERFORM public.delete_manual_transaction_ws(tid,cash_payment);
  RAISE EXCEPTION 'cash correction after cancellation accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
END $$;
