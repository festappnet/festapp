-- Separate bank-QR case. Never rewrite the immutable payment of an earlier order.
DO $$
DECLARE un bigint; oc bigint; fid bigint; bank bigint; pt bigint;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM festapp_test_support.disposable_environment
                WHERE singleton AND project='festapp-wix-qa-20261025') OR
    (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization' THEN
   RAISE EXCEPTION 'Dedicated canonical Wix fixture required';
 END IF;
 IF EXISTS (SELECT 1 FROM public.forms WHERE link='wix-qa-bank-20261025') THEN RETURN; END IF;
 SELECT id INTO STRICT un FROM public.units WHERE organization=1 ORDER BY id LIMIT 1;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time,features)
 VALUES('Wix - bankovní test',un,1,'wix-qa-bank-20261025',now(),now()+interval '30 days',
 '[{"code":"form","is_enabled":true},{"code":"ticket","is_enabled":true}]') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type,account_number,account_number_human_readable,creditor_name,supported_currencies,is_fetch_enabled)
 VALUES('Wix QR synthetic bank','FIO','CZ7001000000000000123457','123457/0100','Synthetic Organizer',ARRAY['CZK'],false) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO public.forms(title,header,occasion,link,is_open,bank_account,participant_capacity,data)
 VALUES('Wix - bankovní test','<h1>Wix - bankovní test</h1><p>Izolovaný test QR instrukcí. Žádná skutečná platba.</p>',
 oc,'wix-qa-bank-20261025',true,bank,10,'{"is_card_design":true}') RETURNING id INTO fid;
 PERFORM public.reserve_public_link_internal('occasion',oc,'wix-qa-bank-20261025',true);
 PERFORM public.reserve_public_link_internal('form',fid,'wix-qa-bank-20261025',true);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Vstupenka','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion,is_hidden)
 VALUES('Základní vstupenka',pt,150,'CZK',oc,false);
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order",product_type) VALUES
 (fid,'email','E-mail',true,false,false,1,null),
 (fid,'ticket','Vstupenky',true,false,false,2,null),
 (fid,'product_type','Vstupenka',true,false,true,3,pt),
 (fid,'name','Jméno',true,false,false,4,null),
 (fid,'surname','Příjmení',true,false,false,5,null);
END $$;
NOTIFY pgrst, 'reload schema';
