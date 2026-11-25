-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE fixture jsonb:=pg_temp.payment_fixture(); org bigint:=(fixture->>'organization')::bigint;
 f bigint:=(fixture->>'form')::bigint; oc bigint:=(fixture->>'occasion')::bigint;
 unit_id bigint; other_occasion bigint; other_form bigint; connection uuid; result jsonb; claim jsonb; facts jsonb;
 merchant_origin text:='https://prodej-test.vstupenky.online';
 remote_id text:='3123456789'; new_order bigint; attempt eshop.gopay_attempts;
BEGIN
 SELECT unit INTO unit_id FROM public.occasions WHERE id=oc;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,features,is_order_synchronization_enabled)
 SELECT 'Druhá akce',organization,unit,gen_random_uuid()::text,start_time,end_time,features,is_order_synchronization_enabled
 FROM public.occasions WHERE id=oc RETURNING id INTO other_occasion;
 INSERT INTO public.forms(occasion,title,link,is_open,bank_account)
 SELECT other_occasion,'Druhý prodej',gen_random_uuid()::text,true,bank_account FROM public.forms WHERE id=f
 RETURNING id INTO other_form;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 connection:=public.configure_gopay_sandbox_connection_internal(org,unit_id,'8123456789',merchant_origin,'Testovací pořadatel',ARRAY[f,other_form]);
 BEGIN
  PERFORM public.configure_gopay_sandbox_connection_internal(org,unit_id,'8123456789',
   'https://prodej-cizi.vstupenky.online','Testovací pořadatel',ARRAY[f],true);
  RAISE EXCEPTION 'sandbox changed origin';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'GOPAY_SANDBOX_SCOPE_INVALID' THEN RAISE; END IF;
 END;
 UPDATE eshop.organization_payment_method_policies SET enabled=true WHERE organization_id=org AND method='gopay';
 UPDATE public.forms SET data=coalesce(data,'{}')||jsonb_build_object('payments',jsonb_build_object(
  'bankEnabled',true,'providerConnections',jsonb_build_object('gopay',connection))) WHERE id IN (f,other_form);
 PERFORM assert_false('gopay'=ANY(ARRAY(SELECT jsonb_array_elements_text(public.form_payment_availability_internal(f)->'available'))),'configured sandbox starts disabled');
 PERFORM public.configure_gopay_sandbox_connection_internal(org,unit_id,'8123456789',merchant_origin,'Testovací pořadatel',ARRAY[f,other_form],true);
 PERFORM assert_eq(public.form_payment_availability_internal(f)#>>'{providers,gopay,recipient,storefrontOrigin}',merchant_origin,'first form uses organizer storefront');
 PERFORM assert_eq(public.form_payment_availability_internal(other_form)#>>'{providers,gopay,recipient,connectionId}',connection::text,'second form shares the merchant');
 PERFORM assert_true(public.form_payment_availability_internal(f)->'available' ? 'gopay','first sandbox form offers GoPay');
 PERFORM assert_true(public.form_payment_availability_internal(other_form)->'available' ? 'gopay','second sandbox form offers GoPay');
 result:=public.create_ticket_order_client_sync_v1(jsonb_build_object(
  'form',(SELECT key FROM public.forms WHERE id=f),'email','gopay@example.invalid',
  'payment_method','gopay','payment_type','full','payment_connection_id',connection,'payment_surface','web',
  'expected_payment_amount_minor',100000,'expected_payment_currency','CZK',
  'goPayPaymentSource',jsonb_build_object(
   'tokenHash',encode(extensions.digest(repeat('a',64),'sha256'),'hex'),
   'returnHash',encode(extensions.digest(repeat('b',64),'sha256'),'hex'),
   'contentHash',repeat('c',64),'sealed',jsonb_build_object('v','1','iv','fixture','ciphertext','fixture')),
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',fixture->'product'))))
 ),gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(result->>'status','applied','canonical GoPay checkout: '||result::text);
 new_order:=(result#>>'{data,order,id}')::bigint;
 SELECT * INTO STRICT attempt FROM eshop.gopay_attempts WHERE order_id=new_order;
 PERFORM assert_eq(attempt.return_base_url,merchant_origin||'/payments/gopay/return','checkout pins return to storefront');
 claim:=public.gopay_runtime_internal('claim_checkout',jsonb_build_object('token',repeat('a',64)));
 PERFORM assert_eq(claim->>'disposition','dispatch','original capability claims checkout');
 PERFORM public.gopay_runtime_internal('callback_schedule',jsonb_build_object('paymentId',remote_id));
 PERFORM assert_true((SELECT a.remote_id IS NULL FROM eshop.gopay_attempts a WHERE a.id=attempt.id),'untied webhook cannot associate payment');
 PERFORM public.gopay_runtime_internal('commit_checkout',jsonb_build_object(
  'attemptId',attempt.id,'lease',claim->>'lease','checkout',jsonb_build_object(
   'id',remote_id,'url','https://gw.sandbox.gopay.com/gw/v3/Fixture',
   'expiresAt',extract(epoch FROM attempt.reservation_expires_at)::bigint)));
 PERFORM public.gopay_runtime_internal('callback_schedule',jsonb_build_object('paymentId',remote_id));
 PERFORM assert_true((SELECT next_reconcile_at<=clock_timestamp() FROM eshop.gopay_attempts WHERE id=attempt.id),'known callback schedules a read');
 claim:=public.gopay_runtime_internal('claim_sync',jsonb_build_object('attemptId',attempt.id,'accountId','8123456789'));
 facts:=jsonb_build_object('checkoutId',remote_id,'paymentId',remote_id,'checkoutStatus','complete',
  'connectorState',jsonb_build_object('goPayState','PAYMENT_METHOD_CHOSEN'),'movements','[]'::jsonb,'disputes','[]'::jsonb);
 result:=public.gopay_runtime_internal('ingest',jsonb_build_object('attemptId',attempt.id,'lease',claim->>'lease','facts',facts));
 PERFORM assert_eq(result#>>'{payment,status}','pending','pending authorization removes pay action');
 UPDATE eshop.gopay_attempts SET last_synced_at=clock_timestamp()-interval '7 seconds' WHERE id=attempt.id;
 PERFORM public.gopay_runtime_internal('callback_schedule',jsonb_build_object('paymentId',remote_id));
 claim:=public.gopay_runtime_internal('claim_sync',jsonb_build_object('attemptId',attempt.id,'accountId','8123456789'));
 facts:=jsonb_build_object('checkoutId',remote_id,'paymentId',remote_id,'checkoutStatus','complete',
  'connectorState',jsonb_build_object('goPayState','PAID'),
  'movements',jsonb_build_array(jsonb_build_object('providerId',remote_id,'kind','payment','amountMinor',100000,
   'currency','CZK','occurredAt',extract(epoch FROM attempt.created_at)::bigint)),'disputes','[]'::jsonb);
 PERFORM public.gopay_runtime_internal('ingest',jsonb_build_object('attemptId',attempt.id,'lease',claim->>'lease','facts',facts));
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=new_order),'paid','verified GoPay status grants paid via shared lifecycle');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=new_order AND message_kind='order_tickets'),'shared lifecycle queues ticket delivery');
 PERFORM assert_true((SELECT next_reconcile_at='infinity' FROM eshop.gopay_attempts WHERE id=attempt.id),'completed payments are not polled cyclically');
END $$;
