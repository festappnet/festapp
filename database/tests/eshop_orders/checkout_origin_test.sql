DO $$
<<checkout_origin_test>>
DECLARE org bigint; unit_id bigint; occ bigint; f bigint; f2 bigint; form_key uuid; product_type bigint; product bigint;
 bank bigint; link text:='wix-origin-'||extensions.gen_random_uuid(); proof jsonb; payload jsonb; result jsonb;
 command uuid:=extensions.gen_random_uuid(); client uuid:=extensions.gen_random_uuid(); order_id bigint; before_count bigint;
 instance uuid:=extensions.gen_random_uuid(); site uuid:=extensions.gen_random_uuid(); key_before bytea;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 INSERT INTO public.organizations(title,data) VALUES('Wix origin fixture','{"DEFAULT_URL":"https://example.invalid"}') RETURNING id INTO org;
 UPDATE eshop.checkout_origin_signing_key SET organization_id=org WHERE singleton;
 INSERT INTO public.units(title,organization) VALUES('Wix organizer',org) RETURNING id INTO unit_id;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Wix origin',org,unit_id,link,now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies)
 VALUES('Fixture bank','123/0100','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(unit_id,bank,1);
 INSERT INTO public.forms(occasion,link,is_open,data) VALUES(occ,link,true,'{}') RETURNING id,key INTO f,form_key;
 INSERT INTO public.forms(occasion,link,is_open,data) VALUES(occ,link||'-other',true,'{}') RETURNING id INTO f2;
 PERFORM public.reserve_public_link_internal('form',f,link,true);
 PERFORM public.reserve_public_link_internal('form',f2,link||'-other',true);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'General admission','spot') RETURNING id INTO product_type;
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code,is_hidden)
 VALUES(product_type,occ,'Free fixture',0,'CZK',false) RETURNING id INTO product;
 INSERT INTO public.form_fields(form,product_type,type) VALUES(f,product_type,'product_type');
 proof:=public.issue_wix_checkout_origin_internal(link,instance,site,org,'9c099206-ce3d-43de-bd9d-deb96bb4f51e');
 PERFORM assert_eq(public.read_checkout_origin_internal(proof->>'context',f)->>'instanceId',instance::text,'signed issuer identity retained');
 PERFORM assert_true(public.read_checkout_origin_internal(proof->>'context',f2) IS NULL,'context cannot cross forms');
 PERFORM assert_true(public.read_checkout_origin_internal((proof->>'context')||'0',f) IS NULL,'modified context rejected');
 PERFORM assert_false(has_table_privilege('anon','eshop.checkout_origin_signing_key','SELECT'),'anonymous cannot read signing key');
 PERFORM assert_false(has_table_privilege('authenticated','eshop.order_checkout_origins','INSERT'),'user cannot assert an origin');
 PERFORM assert_false(has_function_privilege('anon','public.issue_wix_checkout_origin_internal(text,uuid,uuid,bigint,uuid)','EXECUTE'),'anonymous cannot mint proofs');
 BEGIN
  PERFORM public.issue_wix_checkout_origin_internal(link,instance,site,org+1000000,'9c099206-ce3d-43de-bd9d-deb96bb4f51e');
  RAISE EXCEPTION 'cross-tenant issuer accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 payload:=jsonb_build_object('form',form_key,'email','origin@example.invalid','checkoutOrigin',proof->>'context',
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product)))));
 PERFORM set_config('request.jwt.claim.role','anon',true);
 result:=public.create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','origin order commits: '||result::text);
 order_id:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT instance_id FROM eshop.order_checkout_origins WHERE order_checkout_origins.order_id=checkout_origin_test.order_id),instance,'origin and order commit together');
 PERFORM assert_false((SELECT data ? 'checkoutOrigin' FROM eshop.orders WHERE id=order_id),'raw proof excluded from order data');
 SELECT secret INTO key_before FROM eshop.checkout_origin_signing_key WHERE singleton;
 UPDATE eshop.checkout_origin_signing_key SET secret=extensions.gen_random_bytes(32) WHERE singleton;
 result:=public.create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,order,id}',order_id::text,'committed replay survives later proof invalidation');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_checkout_origins WHERE form_id=f),1::bigint,'replay cannot duplicate origin');
 SELECT count(*) INTO before_count FROM eshop.orders WHERE occasion=occ;
 result:=public.create_ticket_order_client_sync_v1(payload,extensions.gen_random_uuid(),client);
 PERFORM assert_eq(result#>>'{data,errorCode}','CHECKOUT_CONTEXT_EXPIRED','new intent rejects invalidated proof');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE occasion=occ),before_count,'rejected proof cannot create order');
 UPDATE eshop.checkout_origin_signing_key SET secret=key_before WHERE singleton;
 payload:=payload-'checkoutOrigin';
 result:=public.create_ticket_order_client_sync_v1(payload,extensions.gen_random_uuid(),client);
 PERFORM assert_eq(result#>>'{data,code}','200','ordinary checkout unchanged');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_checkout_origins WHERE form_id=f),1::bigint,'ordinary checkout never invents Wix origin');
END $$;
