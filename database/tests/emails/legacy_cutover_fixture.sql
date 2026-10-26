-- Disposable local fixture only, applied BEFORE the cutover migration.
INSERT INTO public.organizations(id,title) VALUES(1,'Email local rehearsal foundation');
INSERT INTO public.units(id,title,organization) VALUES(1,'Email local unit',1);
SELECT setval('public.organizations_id_seq',100);
SELECT setval('public.units_id_seq',100);
INSERT INTO public.occasions(id,title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled)
VALUES(98001,'Email migration fixture',1,1,'email-migration-fixture',now(),now()+interval '1 day',true);
INSERT INTO eshop.orders(order_sequence, order_symbol, id,occasion,state,price,currency_code,data) VALUES
(public.next_order_sequence(98001), public.generate_order_symbol(), 98001,98001,'ordered',100,'CZK','{"email":"fixture@example.invalid"}'),
(public.next_order_sequence(98001), public.generate_order_symbol(), 98002,98001,'paid',100,'CZK','{"email":"paid@example.invalid"}'),
(public.next_order_sequence(98001), public.generate_order_symbol(), 98003,98001,'paid',100,'CZK','{"email":""}'),
(public.next_order_sequence(98001), public.generate_order_symbol(), 98004,98001,'paid',100,'CZK','{"email":"legacy-invalid-address"}'),
(public.next_order_sequence(98001), public.generate_order_symbol(), 98005,98001,'paid',100,'CZK','{"email":null}');
INSERT INTO public.queue_emails(id,organization,unit,occasion,code,data,target_time,processing_at,attempt_count) VALUES
(98001,1,1,98001,'TICKET_ORDER_REMINDER','{"order_id":98001}',now()+interval '1 day',NULL,0),
(98002,1,1,98001,'TICKET_ORDER_CONFIRMATION','{"order_id":98001}','infinity',NULL,0),
(98003,1,1,98001,'TICKET_ORDER_UPDATE','{"order_id":98001}',now(),now(),1),
(98004,1,1,98001,'TICKET_ORDER_UPDATE','{"order_id":98001}',now(),now()-interval '1 hour',1),
(98005,1,1,98001,'TICKET_ORDER_STORNO','{"order_id":98001}',now(),NULL,1);
INSERT INTO public.log_emails("to",template,"from",organization,occasion,unit) VALUES('paid@example.invalid','legacy accepted snapshot','sender@example.invalid',1,98001,1);
