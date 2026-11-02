DO $$
DECLARE org bigint; un bigint; oc bigint; fm bigint; form_key uuid; bank bigint;
 parent bigint; pt bigint; product bigint; dinner_type bigint; dinner bigint; oid bigint;
 payload jsonb; result jsonb; replay jsonb; before_orders bigint;
 command uuid:=gen_random_uuid(); client uuid:=gen_random_uuid();
 invalid_payload jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Application-only checkout') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Application-only checkout',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Application without admission ticket',org,un,gen_random_uuid()::text,now(),now()+interval '2 days') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies)
 VALUES('Fixture bank','123/0100','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(un,bank,1);
 INSERT INTO public.forms(occasion,is_open,bank_account) VALUES(oc,true,bank) RETURNING id,key INTO fm,form_key;
 INSERT INTO public.form_fields(form,type,is_hidden,is_required,data)
 VALUES(fm,'ticket',true,true,'{"max_tickets":1}') RETURNING id INTO parent;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Participation fee',NULL) RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(oc,pt,'Participation',2650,'CZK',false) RETURNING id INTO product;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field,is_required,is_hidden)
 VALUES(fm,'product_type',pt,true,true,false);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Dinner',NULL) RETURNING id INTO dinner_type;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(oc,dinner_type,'Dinner',150,'CZK',false) RETURNING id INTO dinner;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field,is_required,is_hidden)
 VALUES(fm,'product_type',dinner_type,true,false,false);
 payload:=jsonb_build_object('form',form_key,'email','application-checkout@example.invalid','payment_method','bank',
   'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product)))));
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','anon',true);
 EXECUTE 'SET LOCAL ROLE anon';
 result:=public.create_ticket_order_client_sync_v1(payload,command,client);
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(result#>>'{data,code}','200','Application-only paid checkout must accept ordinary fee products: '||result::text);
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),2650::numeric,'Canonical stored base price');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','Unpaid transfer order remains ordered');
 PERFORM assert_eq((SELECT pi.amount FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id WHERE o.id=oid),2650::numeric,'Bank payment amount matches');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=oid AND message_kind='order_confirmation'),'Confirmation intent created');
 EXECUTE 'SET LOCAL ROLE anon';
 replay:=public.create_ticket_order_client_sync_v1(payload,command,client);
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(replay#>>'{data,order,id}',result#>>'{data,order,id}','Same command does not duplicate order');
 payload:=jsonb_set(payload,'{ticket,0,fields}',jsonb_build_array(jsonb_build_object('product_type',product),jsonb_build_object('product_type',dinner)));
 EXECUTE 'SET LOCAL ROLE anon';
 result:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),client);
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(result#>>'{data,code}','200','Optional dinner checkout succeeds');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=(result#>>'{data,order,id}')::bigint),2800::numeric,'Base plus dinner stored at 2800');
 SELECT count(*) INTO before_orders FROM eshop.orders;
 FOREACH invalid_payload IN ARRAY ARRAY[
   jsonb_set(payload,'{ticket,0,fields}','[]'),
   jsonb_set(payload,'{ticket,0,fields}',jsonb_build_array(jsonb_build_object('product_type',dinner)))
 ] LOOP
  EXECUTE 'SET LOCAL ROLE anon';
  result:=public.create_ticket_order_client_sync_v1(invalid_payload,gen_random_uuid(),client);
  EXECUTE 'RESET ROLE';
  PERFORM assert_eq(result#>>'{data,errorCode}','REQUIRED_FIELD_MISSING','Required fee cannot be bypassed with empty or dinner-only selection');
  PERFORM assert_eq((SELECT count(*) FROM eshop.orders),before_orders,'Missing required fee leaves no partial order');
 END LOOP;
 UPDATE public.form_fields SET is_hidden=false WHERE id=parent;
 SELECT count(*) INTO before_orders FROM eshop.orders;
 EXECUTE 'SET LOCAL ROLE anon';
 result:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),client);
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(result#>>'{data,code}','1015','Ticket-enabled checkout still requires an admission product');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders),before_orders,'Rejected ticket-enabled checkout leaves no partial order');
 DELETE FROM public.form_fields WHERE id=parent;
 EXECUTE 'SET LOCAL ROLE anon';
 result:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),client);
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(result#>>'{data,code}','1015','Missing container does not silently disable admission validation');
END $$;
