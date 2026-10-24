-- Apply only after test/fixtures/navigation/tenant.sql in the fresh disposable
-- project festapp-order-email-e2e-20261024 (runbook: festapp-local-e2e).
-- No real provider or worker is configured. The local renderer needs an origin.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.organizations)<>1 OR
  (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization' OR
  NOT EXISTS(SELECT 1 FROM public.occasions WHERE link='e2e-tabs-a' AND organization=1) THEN
  RAISE EXCEPTION 'Expected the fresh synthetic recovery tenant';
 END IF;
END $$;
UPDATE public.organizations SET data=coalesce(data,'{}')||'{"DEFAULT_URL":"http://127.0.0.1:56531"}' WHERE id=1;
SELECT public.reserve_public_link_internal('occasion',id,link,true) FROM public.occasions WHERE organization=1;
SELECT set_config('festapp.email_wake','scheduled',false);
SELECT set_config('request.jwt.claim.role','service_role',false);
UPDATE public.email_capacity SET worker_url=NULL,paused=false,shared_account=false,quota_at=now(),max_rate=10,daily_quota=1000,provider_sent_24h=0,next_send_at=now(),circuit_until=NULL,provider_outage_streak=0,probe_until=NULL;
DO $$
DECLARE oc bigint; fid bigint; pi bigint; oid bigint; src uuid; editor uuid;
BEGIN
 SELECT id INTO oc FROM public.occasions WHERE link='e2e-tabs-a';
 SELECT id INTO fid FROM public.forms WHERE occasion=oc ORDER BY id LIMIT 1;
 SELECT id INTO editor FROM public.user_info WHERE email_readonly='t@t.com';
 INSERT INTO eshop.payment_info(amount,paid,currency_code,bank_account,variable_symbol,deadline) VALUES(0,0,'CZK',(SELECT bank_account FROM eshop.unit_bank_accounts WHERE unit=1 LIMIT 1),12345,now()+interval '7 days') RETURNING id INTO pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,form,payment_info,state,price,currency_code,data)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,fid,pi,'ordered',0,'CZK',jsonb_build_object('email','old-recovery@example.invalid','name','Recovery','surname','Synthetic','form',(SELECT key FROM public.forms WHERE id=fid),'tickets','[]'::jsonb)) RETURNING id INTO oid;
 INSERT INTO eshop.orders_history("order",state,price,currency_code,data) SELECT id,state,price,currency_code,data FROM eshop.orders WHERE id=oid;
 src:=(public.enqueue_order_email('TICKET_ORDER_CONFIRMATION',jsonb_build_object('order_id',oid),1,oc,1)->>'message_id')::uuid;
 UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now(),bounced_at=now() WHERE message_id=src;
 CREATE TEMP TABLE recovery_e2e_fixture(order_id bigint,source_message uuid);
 INSERT INTO recovery_e2e_fixture VALUES(oid,src);
END $$;
NOTIFY pgrst,'reload schema';

SELECT * FROM recovery_e2e_fixture;
