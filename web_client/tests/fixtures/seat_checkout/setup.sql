DO $$
DECLARE org bigint; un bigint; oc bigint; fid bigint; bank bigint; pt bigint; prod bigint;
 bp bigint; seat bigint; email_field bigint; name_field bigint; surname_field bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Browser seat regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Browser seat regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time,features)
 VALUES('Browser seat regression',un,org,gen_random_uuid()::text,now(),now()+interval '1 day','[{"code":"blueprint","is_enabled":true}]'::jsonb) RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
 VALUES('Regression bank','FIO','123/0100',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.blueprints(title,organization,occasion,objects,configuration)
 VALUES('Regression seats',org,oc,'[]','{"dimensions":{"width":5,"height":5}}') RETURNING id INTO bp;
 INSERT INTO public.forms(title,occasion,link,is_open,blueprint,bank_account)
 VALUES('Browser seat regression',oc,'seat-checkout-regression',true,bp,bank) RETURNING id INTO fid;
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion,is_hidden)
 VALUES('Admission',pt,150,'CZK',oc,false) RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'email','E-mail',true,false,false,0) RETURNING id INTO email_field;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'name','Jméno',true,false,false,1) RETURNING id INTO name_field;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'surname','Příjmení',true,false,false,2) RETURNING id INTO surname_field;
 INSERT INTO public.form_fields(form,type,title,product_type,is_required,is_hidden,"order")
 VALUES(fid,'ticket','Vstupenky',pt,true,false,3);
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'spot','Výběr místa',true,false,true,4);
 INSERT INTO eshop.spots(title,product,occasion,blueprint)
 VALUES('A1',prod,oc,bp) RETURNING id INTO seat;
 UPDATE eshop.blueprints SET objects=jsonb_build_array(jsonb_build_object('id',seat,'type','spot','title','A1','x',2,'y',2)) WHERE id=bp;
 PERFORM set_config('festapp.browser_fixture',jsonb_build_object('form',fid,'seat',seat,'email',email_field,'name',name_field,'surname',surname_field)::text,true);
END $$;
SELECT current_setting('festapp.browser_fixture')::jsonb AS fixture;
