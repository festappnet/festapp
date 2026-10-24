BEGIN;
DO $$
DECLARE actor uuid; org bigint; unit_id bigint; occ bigint; pt bigint; seat_product bigint; ordinary_product bigint;
  wave jsonb; bundle jsonb; target_wave bigint; visibility_id bigint;
  link text := 'seat-wave-'||gen_random_uuid()::text;
BEGIN
  PERFORM public.create_user_for_test('seat_wave_guard','seat-wave-guard@test.local');
  actor:=public.get_user_id('seat_wave_guard');
  INSERT INTO public.organizations(title) VALUES('Seat wave guard') RETURNING id INTO org;
  UPDATE public.user_info SET organization=org WHERE id=actor;
  INSERT INTO public.units(title,organization) VALUES('Seat wave guard',org) RETURNING id INTO unit_id;
  INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
    VALUES(org,unit_id,'Seat wave guard',link,now(),now()+interval '40 days') RETURNING id INTO occ;
  PERFORM public.reserve_public_link_internal('occasion',occ,link,true);
  INSERT INTO public.occasion_users("user",occasion,is_editor_order,is_editor_order_view) VALUES(actor,occ,true,true);
  INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Seats','spot') RETURNING id INTO pt;
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
    VALUES(occ,pt,'Seat product',450,'CZK',false) RETURNING id INTO seat_product;
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
    VALUES(occ,pt,'Unused seat tariff',100,'CZK',false) RETURNING id INTO ordinary_product;
  INSERT INTO eshop.spots(occasion,title,product,secret) VALUES(occ,'A1',seat_product,gen_random_uuid());
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  SET LOCAL ROLE authenticated;
  wave:=public.create_product_price_wave(link,now()+interval '10 days'); target_wave:=(wave->>'id')::bigint;
  bundle:=public.get_products_and_types_for_edit(link)::jsonb;
  PERFORM public.assert_true(bundle->'products' @> jsonb_build_array(jsonb_build_object('id',seat_product,'is_used_in_blueprint',true)), 'actual seat assignment reported');
  PERFORM public.assert_true(bundle->'products' @> jsonb_build_array(jsonb_build_object('id',ordinary_product,'is_used_in_blueprint',false)), 'type alone does not block a tariff');
  BEGIN
    PERFORM public.save_product_wave_target(target_wave,seat_product,1,550,true);
    RAISE EXCEPTION 'seat hide accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'BLUEPRINT_PRODUCT_VISIBILITY_NOT_SUPPORTED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.save_product_wave_target(target_wave,seat_product,1,550,false);
    RAISE EXCEPTION 'seat visibility target accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'BLUEPRINT_PRODUCT_VISIBILITY_NOT_SUPPORTED' THEN RAISE; END IF;
  END;
  -- A price wave without visibility remains supported, as does an unrelated tariff.
  PERFORM public.save_product_wave_target(target_wave,seat_product,1,550,NULL);
  PERFORM public.save_product_wave_target(target_wave,ordinary_product,1,150,true);
  RESET ROLE;
  PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.planned_changes WHERE wave_id=target_wave AND subject_id=seat_product),1,'rejected visibility did not persist');
  PERFORM public.assert_eq((SELECT price FROM eshop.products WHERE id=seat_product),450::numeric,'editing never changes current price');
  -- An older visibility plan must survive price editing until explicitly cancelled.
  INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion,wave_id)
    VALUES('products.is_hidden',seat_product,'true',(wave->>'change_time')::timestamptz,occ,target_wave) RETURNING id INTO visibility_id;
  SET LOCAL ROLE authenticated;
  PERFORM public.save_product_wave_target(target_wave,seat_product,1,575,true,1,1);
  BEGIN
    PERFORM public.save_product_wave_target(target_wave,seat_product,1,600,false,2,2);
    RAISE EXCEPTION 'existing seat visibility replaced';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'BLUEPRINT_PRODUCT_VISIBILITY_NOT_SUPPORTED' THEN RAISE; END IF;
  END;
  RESET ROLE;
  PERFORM public.assert_eq((SELECT new_value FROM eshop.planned_changes WHERE id=visibility_id),'true','price save preserves existing visibility');
  SET LOCAL ROLE authenticated;
  PERFORM public.save_product_wave_target(target_wave,seat_product,1,600,NULL,2,2);
  RESET ROLE;
  PERFORM public.assert_false(EXISTS(SELECT 1 FROM eshop.planned_changes WHERE id=visibility_id),'explicit cancellation removes visibility only');
  PERFORM public.assert_eq((SELECT new_value FROM eshop.planned_changes WHERE subject_id=seat_product AND change_type='products.price'),'600','price remains editable after cancellation');
END $$;
ROLLBACK;
