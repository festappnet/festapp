DO $$
DECLARE v_org bigint; v_unit bigint; v_occ bigint; v_bank bigint; v_conn bigint; v_payment bigint; v_order bigint;
  v_ticket bigint; v_failed_payment bigint; v_failed_order bigint; v_event jsonb; v_receipt jsonb; v_requests bigint; v_claim jsonb; v_start jsonb;
BEGIN
  INSERT INTO public.organizations(title) VALUES('BankSync event-driven tickets') RETURNING id INTO v_org;
  INSERT INTO public.units(title,organization) VALUES('BankSync ticket unit',v_org) RETURNING id INTO v_unit;
  INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled)
    VALUES('BankSync ticket occasion',v_org,v_unit,gen_random_uuid()::text,now(),now()+interval '1 day',true) RETURNING id INTO v_occ;
  INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
    VALUES('BankSync ticket bank','FIO','331234/2010',ARRAY['CZK']) RETURNING id INTO v_bank;
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256) VALUES('ticket-test','festapp','44',v_bank,'331234/2010','FIO','api','shadow','0123456789',repeat('a',64)) RETURNING id INTO v_conn;
  PERFORM public.activate_bank_sync_connection(v_conn,repeat('a',64));
  INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code) VALUES(v_bank,123456,10.07,'CZK') RETURNING id INTO v_payment;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,state,data,price,currency_code,payment_info)
    VALUES(public.next_order_sequence(v_occ), public.generate_order_symbol(), v_occ,'ordered','{"email":"tickets@example.invalid"}',10.07,'CZK',v_payment) RETURNING id INTO v_order;
  INSERT INTO eshop.tickets(occasion,state) VALUES(v_occ,'ordered') RETURNING id INTO v_ticket;
  INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(v_order,v_ticket);
  -- All network intentions remain inside this rolled-back test transaction.
  UPDATE public.email_capacity SET paused=false,worker_url='http://127.0.0.1:9/banksync-ticket-fixture',quota_at=now();
  PERFORM set_config('festapp.email_wake','',true);
  SELECT count(*) INTO v_requests FROM net.http_request_queue;
  v_event:=jsonb_build_object('event','transaction.received','event_version','2','delivery_id','01K00000000000000000000051',
    'pairing_code','0123456789','data',jsonb_build_object('id',51,'bank_account_id',44,'amount_cents',499,'currency','CZK',
      'date','2026-10-04T12:00:00Z','source','fio_api','transaction_id','331001','raw_vs','123456','payer_reference',NULL,
      'direction','incoming','identity_kind','movement','identity_provenance','fio_api_column22'));
  PERFORM public.ingest_bank_sync_transaction('ticket-test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=v_order),'ordered','partial payment does not release tickets');
  PERFORM assert_eq((SELECT count(*)::int FROM public.email_messages WHERE order_id=v_order AND message_kind='order_tickets'),0,'no ticket intent before paid threshold');
  v_event:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000052"'),'{data,id}','52'),'{data,transaction_id}','"331002"'),'{data,amount_cents}','508');
  v_receipt:=public.ingest_bank_sync_transaction('ticket-test','festapp',repeat('b',64),v_event);
  PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=v_order),'paid','final webhook immediately marks order paid');
  PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=v_ticket),'paid','same commit makes tickets eligible');
  PERFORM assert_eq((SELECT count(*)::int FROM public.email_messages WHERE order_id=v_order AND message_kind='order_tickets' AND workflow_state='pending' AND target_time<=now()),1,'same commit creates one immediately due ticket intent');
  PERFORM assert_eq((SELECT count(*) FROM net.http_request_queue),v_requests+1,'producer immediately wakes worker without a cron tick');
  PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.bank_sync_inbox WHERE instance_id='ticket-test' AND delivery_id=v_event->>'delivery_id' AND receipt=v_receipt),'receipt commits with ticket intent');
  PERFORM public.ingest_bank_sync_transaction('ticket-test','festapp',repeat('b',64),v_event);
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000053"');
  PERFORM public.ingest_bank_sync_transaction('ticket-test','festapp',repeat('c',64),v_event);
  PERFORM assert_eq((SELECT count(*)::int FROM public.email_messages WHERE order_id=v_order AND message_kind='order_tickets'),1,'delivery retries never create a second ticket email');
  PERFORM assert_eq((SELECT count(*) FROM net.http_request_queue),v_requests+1,'wake is coalesced within the transaction');

  -- Immediate wake does not grant a bypass around the global email gate.
  UPDATE public.email_messages SET workflow_state='cancelled' WHERE order_id IS DISTINCT FROM v_order;
  UPDATE public.email_capacity SET paused=true;
  PERFORM assert_true(public.claim_email() IS NULL,'global pause gates webhook-triggered tickets');
  UPDATE public.email_capacity SET paused=false,max_rate=10,daily_quota=1,provider_sent_24h=1,
    shared_account=false,next_send_at=now(),circuit_until=NULL,provider_outage_streak=0,quota_at=now();
  v_claim:=public.claim_email();
  PERFORM assert_eq((v_claim->>'order_id')::bigint,v_order,'ticket preparation uses canonical queue');
  PERFORM public.prepare_email((v_claim->>'message_id')::uuid,(v_claim->>'lease_token')::uuid,
    '{"sealed":"synthetic-ticket-snapshot"}',jsonb_build_object('ticket_ids',jsonb_build_array(v_ticket)));
  v_start:=public.begin_email_send((v_claim->>'attempt_id')::uuid,(v_claim->>'lease_token')::uuid);
  PERFORM assert_eq(v_start->>'disposition','deferred','global daily quota still gates tickets');
  PERFORM assert_eq((SELECT attempt_count FROM public.email_messages WHERE order_id=v_order AND message_kind='order_tickets'),0,'capacity wait does not consume a send attempt');
  UPDATE public.email_capacity SET daily_quota=100,provider_sent_24h=0,next_send_at=now();
  UPDATE public.email_messages SET target_time=now() WHERE order_id=v_order;
  v_claim:=public.claim_email();
  v_start:=public.begin_email_send((v_claim->>'attempt_id')::uuid,(v_claim->>'lease_token')::uuid);
  PERFORM assert_eq(v_start->>'disposition','send','available global capacity releases prepared ticket intent');
  PERFORM public.finish_email_attempt((v_claim->>'attempt_id')::uuid,(v_claim->>'lease_token')::uuid,'accepted','synthetic-provider-receipt');
  PERFORM public.apply_email_post_actions((v_claim->>'message_id')::uuid);
  PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=v_ticket),'sent','only canonical provider acceptance projects sent tickets');

  INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code) VALUES(v_bank,223456,10.07,'CZK') RETURNING id INTO v_failed_payment;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,state,data,price,currency_code,payment_info)
    VALUES(public.next_order_sequence(v_occ), public.generate_order_symbol(), v_occ,'ordered','{"email":"failure@example.invalid"}',10.07,'CZK',v_failed_payment) RETURNING id INTO v_failed_order;
  EXECUTE format('ALTER TABLE public.email_messages ADD CONSTRAINT banksync_intent_failure_fixture CHECK (order_id IS DISTINCT FROM %s) NOT VALID',v_failed_order);
  v_event:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000054"'),'{data,transaction_id}','"331003"'),'{data,raw_vs}','"223456"'),'{data,amount_cents}','1007');
  BEGIN
    PERFORM public.ingest_bank_sync_transaction('ticket-test','festapp',repeat('d',64),v_event);
    RAISE EXCEPTION 'failed ticket intent was acknowledged';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'ORDER_PAID_TRANSITION_FAILED:%' THEN RAISE; END IF;
  END;
  PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=v_failed_order),'ordered','intent failure rolls order back');
  PERFORM assert_true((SELECT COALESCE(paid,0)=0 FROM eshop.payment_info WHERE id=v_failed_payment),'intent failure rolls payment credit back');
  PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.transactions WHERE bank_account_id=v_bank AND transaction_id=331003),'intent failure rolls bank ledger back');
  PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.bank_sync_inbox WHERE instance_id='ticket-test' AND delivery_id=v_event->>'delivery_id'),'intent failure commits no success receipt');
  ALTER TABLE public.email_messages DROP CONSTRAINT banksync_intent_failure_fixture;
END;
$$;
