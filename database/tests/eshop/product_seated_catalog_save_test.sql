DO $$
<<product_inventory_save_test>>
DECLARE actor uuid; org bigint; un bigint; oc bigint; foreign_oc bigint; pt bigint; product bigint;
 fm bigint; result jsonb; payload jsonb; cmd uuid:=gen_random_uuid();
BEGIN
 PERFORM public.create_user_for_test('atomic-product','atomic-product@example.invalid');actor:=public.get_user_id('atomic-product');
 INSERT INTO public.organizations(title) VALUES('Atomic product') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Atomic product',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Atomic product',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Foreign product',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO foreign_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(oc,actor,true,true);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,price,currency_code,occasion,product_type) VALUES('Original',10,'CZK',oc,pt) RETURNING id INTO product;
 INSERT INTO public.forms(title,occasion,link) VALUES('Seated admission',oc,gen_random_uuid()::text) RETURNING id INTO fm;
 INSERT INTO public.form_fields(form,type,is_hidden) VALUES(fm,'ticket',false);
 -- Existing seated forms retain a hidden catalog field for seat products.
 INSERT INTO public.form_fields(form,type,product_type,is_hidden) VALUES(fm,'product_type',pt,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SELECT to_jsonb(p)||jsonb_build_object('price',500,'expected_aggregate_version',0,'inventory_contexts','[]'::jsonb)
 INTO payload FROM eshop.products p WHERE p.id=product;
 result:=public.manage_product(oc,org,un,'save',payload,cmd);
 ASSERT result->>'code'='200',result::text;
 ASSERT result#>>'{data,aggregate_version}'='1',result::text;
 ASSERT (SELECT price=500 FROM eshop.products WHERE id=product);
 ASSERT public.manage_product(oc,org,un,'save',payload,cmd)=result;
 -- Even a repeated empty context replacement must invalidate stale editors.
 ASSERT public.manage_product(oc,org,un,'save',payload,gen_random_uuid())->>'status'='conflict';
 payload:=payload||jsonb_build_object('price',0,'expected_aggregate_version',1);
 result:=public.manage_product(oc,org,un,'save',payload,gen_random_uuid());
 ASSERT result#>>'{data,aggregate_version}'='2',result::text;
 ASSERT (SELECT price=0 FROM eshop.products WHERE id=product);
 -- The detail-save exception must never permit hiding the last admission.
 BEGIN
   PERFORM public.manage_product(oc,org,un,'save',payload||jsonb_build_object(
     'is_hidden',true,'expected_aggregate_version',2),gen_random_uuid());
   RAISE EXCEPTION 'Last primary offer was hidden';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'FORM_DELETE_primary_product' THEN RAISE; END IF;
 END;
END $$;
