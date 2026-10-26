-- Disposable local data for the supported original-baseline upgrade.
INSERT INTO public.organizations(id,title) VALUES(991001,'Baseline upgrade fixture');
INSERT INTO public.units(id,title,organization) VALUES(991001,'Baseline upgrade fixture',991001);
INSERT INTO public.occasions(id,title,organization,unit,link,start_time,end_time)
VALUES(991001,'Baseline upgrade fixture',991001,991001,'baseline-upgrade-fixture',now(),now()+interval '1 day');
INSERT INTO eshop.payment_info(id,variable_symbol,amount,paid,currency_code)
VALUES(991001,987654321,100,0,'CZK');
INSERT INTO eshop.orders(id,occasion,payment_info,state,price,currency_code,data)
VALUES(991001,991001,991001,'ordered',100,'CZK','{"email":"fixture@example.invalid"}');
INSERT INTO public.queue_emails(id,organization,unit,occasion,code,data,target_time,attempt_count)
VALUES(991001,991001,991001,991001,'TICKET_ORDER_REMINDER','{"order_id":991001}',now()+interval '1 day',0);
INSERT INTO public.log_emails("to",template,"from",organization,occasion,unit)
VALUES('fixture@example.invalid','baseline upgrade audit','sender@example.invalid',991001,991001,991001);
