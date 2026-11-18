-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE
 fixture jsonb:=pg_temp.fixture(NULL);
 form_id bigint:=(fixture->>'form')::bigint;
 command_id uuid:=gen_random_uuid();
 client_id uuid:=gen_random_uuid();
 checkout jsonb:=pg_temp.checkout(fixture);
 receipt jsonb;
 v_order_id bigint;
 payment_id bigint;
 bank_id bigint;
 deposit_id bigint;
 balance_id bigint;
 paid_id uuid;
 claimed uuid;
 prepared jsonb;
 first_event_time bigint;
 buyer_token text:=repeat('a',64);
 connector_unit bigint:=(fixture->>'unit')::bigint;
 unconsented_id bigint;
 second_order_id bigint;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES ((fixture->>'organization')::bigint,true,1,'fixture','confirmed purchase');
 UPDATE public.forms SET is_open=true,data=data||'{"analytics":{"enabled":true}}' WHERE id=form_id;
 PERFORM public.reserve_public_link_internal('form',form_id,fixture->>'link',true);
 INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled,test_event_code)
 VALUES(connector_unit,'123456',vault.create_secret(repeat('t',40),'meta-purchase-fixture'),
  'https://tickets.example',true,'TEST4242');
 INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES(form_id,connector_unit);
 checkout:=checkout||jsonb_build_object('metaPurchaseConsent',jsonb_build_object(
  'revision',public.get_meta_purchase_consent(fixture->>'link')->>'revision','userAgent','Test checkout'));
 PERFORM assert_true(checkout#>>'{metaPurchaseConsent,revision}' IS NOT NULL,'enabled connector exposes the bound notice');

 receipt:=public.create_ticket_order_client_sync_v1(checkout,command_id,client_id);
 PERFORM assert_eq(receipt#>>'{data,code}','200','bank checkout succeeds');
 PERFORM assert_eq(receipt#>'{data,analytics}','null'::jsonb,'unpaid checkout has no purchase');
 v_order_id:=(receipt#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO STRICT payment_id FROM eshop.orders WHERE id=v_order_id;
 PERFORM assert_true(EXISTS(SELECT FROM analytics.meta_purchase_deliveries d WHERE d.order_id=v_order_id),
  'checkout atomically binds explicit consent to the order');
 PERFORM assert_false((SELECT data ? 'metaPurchaseConsent' FROM eshop.orders WHERE id=v_order_id),
  'measurement evidence is private and absent from commerce data');
 PERFORM assert_eq((SELECT count(*) FROM public.claim_meta_purchase_deliveries(8)),0::bigint,'no work before full payment');

 UPDATE eshop.payment_info SET deposit_amount=30 WHERE id=payment_id RETURNING bank_account INTO bank_id;

 -- Simulate a receipt written before this migration. Old clients must never
 -- recover the historical order-time event, even after this order is paid.
 INSERT INTO analytics.conversion_facts("order",kind,payload)
 VALUES(v_order_id,'purchase','{"event":"purchase"}');
 PERFORM assert_eq(public.create_ticket_order_client_sync_v1(checkout,command_id,client_id)#>'{data,analytics}',
  'null'::jsonb,'checkout replay suppresses historical order-time purchase');

 UPDATE eshop.payment_info SET paid_externally=70 WHERE id=payment_id;
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source,vs)
 SELECT bank_id,30,'CZK',now(),'fio_api',variable_symbol::text FROM eshop.payment_info WHERE id=payment_id
 RETURNING id INTO deposit_id;
 PERFORM assert_eq(public.match_bank_transaction(deposit_id)->>'verdict','paired','automatic deposit match');
 PERFORM assert_true((SELECT state IN ('paid','sent') FROM eshop.orders WHERE id=v_order_id),'deposit activates admission');
 PERFORM assert_false(EXISTS(SELECT FROM analytics.conversion_facts WHERE "order"=v_order_id AND kind='order_fully_paid'),
  'deposit and external settlement cannot produce a purchase');

 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
 VALUES (bank_id,70,'CZK',now(),'fio_api') RETURNING id INTO balance_id;
 -- A failed conversion write must leave payment pairing retryable.
 ALTER TABLE analytics.conversion_facts ADD CONSTRAINT measurement_payment_write_fault
 CHECK(kind<>'order_fully_paid') NOT VALID;
 BEGIN
  PERFORM public.apply_transaction_pairing(balance_id,payment_id,'manual_attach','user');
  RAISE EXCEPTION 'conversion failure unexpectedly committed the pairing';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
 PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.transactions WHERE id=balance_id),
  'the payment is still unpaired after a failed write');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=payment_id),30::numeric,
  'payment totals roll back with pairing');
 ALTER TABLE analytics.conversion_facts DROP CONSTRAINT measurement_payment_write_fault;

 -- The same private pairing boundary used by the admin RPC after permission checks.
 PERFORM public.apply_transaction_pairing(balance_id,payment_id,'manual_attach','user');
 SELECT event_id INTO STRICT paid_id FROM analytics.conversion_facts WHERE "order"=v_order_id AND kind='order_fully_paid';
 PERFORM assert_eq((SELECT payload FROM analytics.conversion_facts WHERE event_id=paid_id),
  '{"currency":"CZK","value":100}'::jsonb,'actual bank receipts cover the full order');
 PERFORM assert_eq(public.create_ticket_order_client_sync_v1(checkout,command_id,client_id)#>'{data,analytics}',
  'null'::jsonb,'full payment stays out of browser checkout receipts');
 PERFORM public.apply_transaction_pairing(balance_id,NULL,'manual_unlink','user');
 PERFORM public.apply_transaction_pairing(balance_id,payment_id,'manual_attach','user');
 PERFORM assert_eq((SELECT event_id FROM analytics.conversion_facts WHERE "order"=v_order_id AND kind='order_fully_paid'),
  paid_id,'unlink and re-pair preserve the original event ID');

 SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(8) d WHERE d.order_id=v_order_id;
 PERFORM assert_eq((SELECT count(*) FROM public.claim_meta_purchase_deliveries(8)),0::bigint,'active lease excludes a second worker');
 prepared:=public.prepare_meta_purchase_delivery(v_order_id,claimed);
 PERFORM assert_eq(prepared->>'eventId',paid_id::text,'the stable settlement ID reaches the payload');
 PERFORM assert_eq(prepared->>'testEventCode','TEST4242','test code is bound to the dataset and consent');
 PERFORM assert_eq(prepared->>'emailHash',encode(extensions.digest('regression@example.invalid','sha256'),'hex'),
  'only the normalized hash is returned to the worker');
 PERFORM assert_true(public.prepare_meta_purchase_delivery(v_order_id,claimed) IS NULL,'one prepare per lease');
 first_event_time:=(prepared->>'eventTime')::bigint;
 PERFORM assert_true(public.finish_meta_purchase_delivery(v_order_id,claimed,'retry'),'transient result acknowledges the lease');
 PERFORM assert_eq((SELECT count(*) FROM public.claim_meta_purchase_deliveries(8)),0::bigint,'retry backs off');
 UPDATE analytics.meta_purchase_deliveries d SET next_attempt_at=now()-interval '1 second' WHERE d.order_id=v_order_id;
 SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(8) d WHERE d.order_id=v_order_id;
 prepared:=public.prepare_meta_purchase_delivery(v_order_id,claimed);
 PERFORM assert_eq(prepared->>'eventId',paid_id::text,'retry preserves event ID');
 PERFORM assert_eq((prepared->>'eventTime')::bigint,first_event_time,'retry preserves settlement time');
 PERFORM assert_true(public.finish_meta_purchase_delivery(v_order_id,claimed,'credentials'),'bad token reports to the connector');
 PERFORM assert_true((SELECT paused_at IS NOT NULL FROM analytics.meta_purchase_connectors WHERE unit=connector_unit),'bad credentials pause the connector');
 UPDATE analytics.meta_purchase_connectors SET paused_at=NULL WHERE unit=connector_unit;
 UPDATE analytics.meta_purchase_deliveries d SET next_attempt_at=now()-interval '1 second' WHERE d.order_id=v_order_id;
 SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(8) d WHERE d.order_id=v_order_id;
 PERFORM public.issue_order_overview_internal(v_order_id,pg_temp.delivery('fixture',buyer_token,v_order_id),gen_random_uuid());
 PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('b',64),v_order_id),'invalid buyer capability cannot revoke');
 PERFORM assert_true(public.revoke_meta_purchase_consent(buyer_token,v_order_id),'buyer can revoke in order overview');
 PERFORM assert_true(public.prepare_meta_purchase_delivery(v_order_id,claimed) IS NULL,'withdrawal invalidates an outstanding claim');
 PERFORM assert_true((SELECT status='revoked' AND email_hash IS NULL AND client_agent IS NULL
  FROM analytics.meta_purchase_deliveries d WHERE d.order_id=v_order_id),'withdrawal erases matching data');

 receipt:=public.create_ticket_order_client_sync_v1(checkout-'metaPurchaseConsent',gen_random_uuid(),client_id);
 unconsented_id:=(receipt#>>'{data,order,id}')::bigint;
 PERFORM assert_true(unconsented_id IS NOT NULL,'checkout without consent succeeds');
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_deliveries d WHERE d.order_id=unconsented_id),
  'checkout without consent never queues a delivery');

 receipt:=public.create_ticket_order_client_sync_v1(checkout,gen_random_uuid(),client_id);
 second_order_id:=(receipt#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO STRICT payment_id FROM eshop.orders WHERE id=second_order_id;
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
 VALUES (bank_id,110,'CZK',now(),'fio_api') RETURNING id INTO balance_id;
 PERFORM public.apply_transaction_pairing(balance_id,payment_id,'manual_attach','user');
 SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(8) d WHERE d.order_id=second_order_id;
 prepared:=public.prepare_meta_purchase_delivery(second_order_id,claimed);
 PERFORM assert_eq((prepared->>'value')::numeric,100::numeric,'overpayment does not inflate purchase value');
 PERFORM assert_true(public.finish_meta_purchase_delivery(second_order_id,claimed,'sent'),'a confirmed Meta receipt completes delivery');
 PERFORM assert_false(public.finish_meta_purchase_delivery(second_order_id,claimed,'sent'),'replaying acknowledgment does not deliver twice');
 PERFORM assert_true((SELECT status='sent' AND email_hash IS NULL AND client_agent IS NULL
  FROM analytics.meta_purchase_deliveries d WHERE d.order_id=second_order_id),'success retains only operational evidence');

END $$;
