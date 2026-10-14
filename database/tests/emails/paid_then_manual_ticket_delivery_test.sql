BEGIN;
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; oid bigint; first_message uuid; result jsonb;
 actor uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title) VALUES('Paid ticket delivery regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Delivery regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled,features)
 VALUES('Delivery regression',org,un,gen_random_uuid()::text,now(),now()+interval '1 day',true,'[{"code":"ticket","is_enabled":true}]') RETURNING id INTO oc;
 INSERT INTO eshop.orders(occasion,order_symbol,order_sequence,state,data,price,currency_code)
 VALUES(oc,public.generate_order_symbol(),public.next_order_sequence(oc),'paid','{"email":"regression@example.invalid"}',100,'CZK') RETURNING id INTO oid;
 PERFORM public.enqueue_paid_order_tickets(oid);
 SELECT message_id INTO STRICT first_message FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets';
 -- The worker may accept the automatic message before the UI confirms sending.
 UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now() WHERE message_id=first_message;
 result:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',oid,'requested_by',actor),org,oc,un);
 IF result->>'message_id' IS DISTINCT FROM first_message::text OR (SELECT count(*) FROM public.email_messages WHERE order_id=oid)<>1 THEN
  RAISE EXCEPTION 'First delivery must reuse the already accepted automatic intent'; END IF;
 -- An explicit later resend remains a distinct authorized user operation.
 result:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',oid,'requested_by',actor),org,oc,un,now(),'resend:explicit-test');
 IF result->>'message_id'=first_message::text OR (SELECT count(*) FROM public.email_messages WHERE order_id=oid)<>2 THEN
  RAISE EXCEPTION 'Explicit resend must create a new intent'; END IF;
 RAISE NOTICE 'PASS: first delivery reuses accepted automatic tickets; explicit resend remains available';
END $$;
ROLLBACK;
