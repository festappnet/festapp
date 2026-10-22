DO $$
DECLARE org bigint; other_org bigint; u bigint; other_unit bigint; actor uuid; manager uuid; cfg jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Stripe preview tenant') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other preview tenant') RETURNING id INTO other_org;
 INSERT INTO public.units(title,organization) VALUES('Preview unit',org) RETURNING id INTO u;
 INSERT INTO public.units(title,organization) VALUES('Other preview unit',other_org) RETURNING id INTO other_unit;
 PERFORM public.create_user_for_test('stripe_preview_admin','stripe-preview-admin@example.test');actor:=get_user_id('stripe_preview_admin');
 PERFORM public.create_user_for_test('stripe_preview_manager','stripe-preview-manager@example.test');manager:=get_user_id('stripe_preview_manager');
 UPDATE public.user_info SET organization=org WHERE id IN(actor,manager);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,actor,true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(u,manager,true);
 PERFORM assert_false(public.stripe_unit_feature_enabled_internal(u),'unit defaults hidden');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub',manager::text,true);
 BEGIN
  PERFORM public.set_stripe_unit_feature(u,true);RAISE EXCEPTION 'manager enabled hidden feature';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.begin_stripe_connection_flow(u,false);RAISE EXCEPTION 'hidden unit began OAuth';
 EXCEPTION WHEN insufficient_privilege THEN
  IF SQLERRM<>'STRIPE_FEATURE_DISABLED' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 BEGIN
  PERFORM public.set_stripe_unit_feature(other_unit,true);RAISE EXCEPTION 'foreign admin enabled feature';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.set_stripe_unit_feature(u,true);
 PERFORM assert_true(public.stripe_unit_feature_enabled_internal(u),'tenant admin enables selected unit');
 PERFORM assert_false(public.stripe_unit_feature_enabled_internal(other_unit),'other tenant stays hidden');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.stripe_runtime_policy WHERE organization_id=org AND new_payments_enabled),'discovery never enables sales');
 cfg:=public.get_app_config_v218(jsonb_build_object('organization',org,'unit_id',u,'platform',jsonb_build_object('platform','web')));
 PERFORM assert_eq(cfg#>>'{unit,stripe_preview_enabled}','true','context projects enabled unit');
 PERFORM public.set_stripe_unit_feature(u,false);
 PERFORM assert_false(public.stripe_unit_feature_enabled_internal(u),'admin can hide feature again');
 PERFORM assert_false(has_table_privilege('authenticated','eshop.stripe_unit_features','UPDATE'),'clients cannot modify hidden settings directly');
 PERFORM assert_false(has_table_privilege('service_role','eshop.stripe_unit_features','UPDATE'),'service role has no table write grant');
END $$;
