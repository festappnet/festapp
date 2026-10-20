DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; pt bigint; product bigint; link text;
 target jsonb; cmd uuid:=gen_random_uuid(); result jsonb; at_time timestamptz:=now()+interval '10 days'; plan bigint;
BEGIN
 PERFORM public.create_user_for_test('atomic-wave','atomic-wave@example.invalid');actor:=public.get_user_id('atomic-wave');
 INSERT INTO public.organizations(title) VALUES('Atomic wave') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Atomic wave',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Atomic wave',org,un,gen_random_uuid()::text,now(),now()+interval '20 days') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,actor,true);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,price,currency_code,occasion,product_type) VALUES('Original',10,'CZK',oc,pt) RETURNING id INTO product;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',oc,NULL,true) WHERE id=oc RETURNING occasions.link INTO link;
 INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion) VALUES('products.price',product,'20',at_time,oc) RETURNING id INTO plan;
 target:=jsonb_build_object('occasion_link',link,'product_id',product,'change_time',at_time,'price',30,'is_hidden',NULL,
  'expected_price_revision',NULL,'expected_visibility_revision',NULL);
 BEGIN PERFORM public.save_product_wave_target_client_sync_v1(target,cmd);RAISE EXCEPTION 'stale adopted plan accepted';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.product_price_waves WHERE occasion=oc);
 ASSERT (SELECT wave_id IS NULL AND new_value='20' FROM eshop.planned_changes WHERE id=plan),'failed target must roll back wave/adoption';
 target:=jsonb_set(target,'{expected_price_revision}','1');
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.save_product_wave_target_client_sync_v1(target,cmd);
 ASSERT result->>'code'='200';ASSERT public.save_product_wave_target_client_sync_v1(target,cmd)=result;
 EXECUTE 'RESET ROLE';
 ASSERT (SELECT count(*)=1 FROM eshop.product_price_waves WHERE occasion=oc);
 ASSERT (SELECT new_value='30' AND wave_id IS NOT NULL FROM eshop.planned_changes WHERE id=plan);
 ASSERT (SELECT price=10 FROM eshop.products WHERE id=product),'scheduling must not reprice now';
END $$;
