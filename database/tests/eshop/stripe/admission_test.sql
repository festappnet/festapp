-- scanner_test_fixture is installed only in the dedicated disposable harness.
DO $$
DECLARE fx jsonb; oc bigint; org bigint; u bigint; v_ticket bigint; bank_ticket bigint; oid bigint; pi bigint; conn uuid; attempt uuid;
 session jsonb; sid uuid; token text; dto jsonb; result jsonb; op jsonb; fingerprint text; expected text; cfg jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 fx:=public.scanner_test_fixture(2);oc:=(fx->>'occasion')::bigint;v_ticket:=(fx#>>'{tickets,0}')::bigint;bank_ticket:=(fx#>>'{tickets,1}')::bigint;
 SELECT organization,unit INTO org,u FROM public.occasions WHERE id=oc;
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE eshop.order_product_ticket.ticket=v_ticket;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state) VALUES(org,u,'acct_admissionFixture',false,'connected') RETURNING id INTO conn;
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method,stripe_connection_id) VALUES(100,'CZK','stripe',conn) RETURNING id INTO pi;
 UPDATE eshop.orders SET payment_info=pi,price=100,currency_code='CZK' WHERE id=oid;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,amount_minor,currency,order_revision,idempotency_key,reservation_expires_at,state)
 VALUES(oid,pi,org,u,conn,false,10000,'CZK',1,'admission:'||extensions.gen_random_uuid(),now()+interval '31 minutes','paid') RETURNING id INTO attempt;
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'pi_admissionFixture',attempt,'payment',10000,'CZK',now());
 PERFORM public.refresh_payment_info_totals_internal(pi);
 session:=public.open_scanner_session(fx->>'scan_code');sid:=(session#>>'{data,session_id}')::uuid;token:=session#>>'{data,token}';
 PERFORM assert_eq(session->>'code','200','real scanner session');
 result:=public.lookup_scanner_ticket(sid,token,(SELECT ticket_symbol FROM eshop.tickets WHERE id=v_ticket));dto:=result->'data';
 PERFORM assert_true((dto->>'online_required')::boolean AND (dto->>'admission_allowed')::boolean,'paid card ticket requires live SQL admission');
 op:=jsonb_build_object('operation_id',extensions.gen_random_uuid(),'origin_session_id',sid,'ticket_id',v_ticket,'action','admit_ticket',
  'snapshot_id',extensions.gen_random_uuid(),'settings_revision',result->'settings_revision','eligibility_fingerprint',dto->>'eligibility_fingerprint','captured_at',clock_timestamp());
 result:=public.sync_scanner_operations(sid,token,jsonb_build_array(op));
 PERFORM assert_eq(result#>>'{data,0,reason}','online_required','server rejects offline admission even with current fingerprint');
 op:=jsonb_set(op,'{operation_id}',to_jsonb(extensions.gen_random_uuid()))||jsonb_build_object('snapshot_id',NULL);
 result:=public.sync_scanner_operations(sid,token,jsonb_build_array(op));
 PERFORM assert_eq(result#>>'{data,0,outcome}','accepted','online card admission uses canonical scanner');
 UPDATE eshop.tickets SET state='sent' WHERE id=v_ticket;
 INSERT INTO eshop.stripe_disputes(connection_id,provider_id,attempt_id,amount_minor,status,observed_at)
 VALUES(conn,'du_admissionFixture',attempt,10000,'needs_response',now());
 result:=public.update_ticket_to_used(v_ticket,fx->>'scan_code');
 PERFORM assert_true(result->>'code'<>'200','retained native writer cannot bypass dispute hold');
 BEGIN
  PERFORM public.scanner_admit_ticket_internal(v_ticket);RAISE EXCEPTION 'hold bypassed central writer';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'stripe_admission_hold' THEN RAISE; END IF; END;
 result:=public.get_all_tickets_for_scan(fx->>'scan_code');
 PERFORM assert_eq(jsonb_array_length(result),1,'native offline export preserves bank and excludes card');
 PERFORM assert_eq((result#>>'{0,id}')::bigint,bank_ticket,'only bank ticket exported');
 -- The bank fingerprint remains byte-for-byte compatible with old snapshots.
 SELECT config INTO cfg FROM public.scanner_settings WHERE occasion_id=oc;
 SELECT projection.dto->>'eligibility_fingerprint' INTO fingerprint FROM public.scanner_ticket_projection_internal(oc,cfg,bank_ticket) projection;
 SELECT encode(extensions.digest(jsonb_build_object('v',1,'id',t.id,'symbol',t.ticket_symbol,'state',t.state,'updated',t.updated_at,
  'parents',(SELECT jsonb_agg(jsonb_build_array(o.id,o.state,o.updated_at,p.amount,p.paid) ORDER BY o.id) FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE x.ticket=t.id))::text,'sha256'),'hex') INTO expected FROM eshop.tickets t WHERE t.id=bank_ticket;
 PERFORM assert_eq(fingerprint,expected,'existing bank offline queues retain their fingerprint');
END $$;
