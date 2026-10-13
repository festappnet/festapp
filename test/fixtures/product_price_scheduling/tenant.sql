DO $$ DECLARE actor uuid; org bigint; u bigint; occ bigint; pt bigint;
BEGIN
 SELECT id,organization INTO actor,org FROM public.user_info LIMIT 1;
 SELECT id INTO u FROM public.units WHERE organization=org LIMIT 1;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open,is_hidden,data,features)
 VALUES(org,u,'Price scheduling E2E','price-e2e',now(),now()+interval '30 days',true,false,'{"timezone":"Europe/Prague"}',
 '[{"code":"form","is_enabled":true},{"code":"ticket","is_enabled":true}]') RETURNING id INTO occ;
 INSERT INTO public.occasion_users("user",occasion,is_editor_order,is_editor_order_view,is_editor,is_editor_view)
 VALUES(actor,occ,true,true,true,true);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Tickets','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden,"order")
 VALUES(occ,pt,'Vstupenka E2E',450,'CZK',false,1);
END $$;
NOTIFY pgrst,'reload schema';
