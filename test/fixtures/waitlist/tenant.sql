-- Synthetic fixture for the owned disposable local UI backend only.
DO $$
DECLARE actor uuid; oc bigint; f bigint; pt bigint; bank bigint;
BEGIN
 IF (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization'
 OR EXISTS(SELECT 1 FROM public.occasions WHERE link='waitlist-ui-e2e') THEN
  RAISE EXCEPTION 'Expected fresh task-owned synthetic fixture';
 END IF;
 SELECT id INTO STRICT actor FROM public.user_info WHERE email_readonly='t@t.com';
 UPDATE public.organizations SET data=coalesce(data,'{}')||
  '{"DEFAULT_URL":"http://127.0.0.1:56980","APP_NAME":"Waitlist E2E"}' WHERE id=1;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,features)
 VALUES('Waitlist UI E2E',1,1,'waitlist-ui-e2e',now()+interval '1 day',now()+interval '2 days',
  '[{"code":"form","is_enabled":true},{"code":"ticket","is_enabled":false}]') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_manager,is_editor_order,is_editor_order_view,is_approved)
 VALUES(oc,actor,true,true,true,true,true,true);
 INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies,is_fetch_enabled)
 VALUES('Synthetic Waitlist Bank','123456/0100','FIO',ARRAY['CZK'],false) RETURNING id INTO bank;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(1,bank,1);
 INSERT INTO public.forms(title,occasion,link,is_open,bank_account,header,data)
 VALUES('Waitlist UI Form',oc,'waitlist-ui-form',true,bank,'<p>Synthetic waitlist registration</p>','{}') RETURNING id INTO f;
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion,maximum)
 VALUES('Synthetic Admission',pt,100,'CZK',oc,20);
 INSERT INTO public.form_fields(form,type,title,is_required,is_ticket_field,"order",data)
 VALUES(f,'email','Email',true,false,0,'{}'),(f,'ticket','People',true,false,1,'{"max_tickets":20}'),
  (f,'name','First name',true,true,2,'{}'),(f,'surname','Last name',true,true,3,'{}');
 INSERT INTO public.form_fields(form,type,title,product_type,is_required,is_ticket_field,"order",data)
 VALUES(f,'product_type','Admission',pt,true,true,4,'{}');
END $$;
NOTIFY pgrst, 'reload schema';
