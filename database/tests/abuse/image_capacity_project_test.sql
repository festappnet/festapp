DO $$
DECLARE actor uuid; org bigint; un bigint; org2 bigint; un2 bigint; occ bigint; policy jsonb; scopes jsonb;
BEGIN
 PERFORM create_user_for_test('image-capacity','image-capacity@test.invalid');actor:=get_user_id('image-capacity');
 INSERT INTO public.organizations(title) VALUES('Default capacity') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Default Unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Project fixture',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.unit_users(unit,"user",is_editor) VALUES(un,actor,true);
 INSERT INTO public.occasion_users(occasion,"user",is_editor) VALUES(occ,actor,true);
 INSERT INTO public.organizations(title) VALUES('Imported capacity') RETURNING id INTO org2;
 INSERT INTO public.units(title,organization) VALUES('Imported Unit',org2) RETURNING id INTO un2;
 INSERT INTO public.image_project_imports VALUES(org2,'a');
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM assert_true(public.get_image_project_access_v1('default',NULL,un),'authorized default upload');
 PERFORM assert_false(public.get_image_project_access_v1('a',NULL,un),'project switch cannot move the same owner to another bucket');
 PERFORM assert_true(public.get_image_project_access_v1('default'),'legacy project shared read retained');
 PERFORM assert_false(public.get_image_project_access_v1('a'),'other project private objects remain inaccessible');
 EXECUTE 'RESET ROLE';
 UPDATE public.abuse_policy_rules SET base_limit=10 WHERE rule_key='image.storage.global.bytes';
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM public.admit_image_storage_v1(6,NULL,un);
 EXECUTE 'RESET ROLE';
 -- Another Unit/UUID and expired rolling buckets cannot reset global allocation.
 policy:=public.abuse_effective_rules_v1('image.storage',un2,org2);
 scopes:=jsonb_build_object('unit',un2,'organization',org2,'global','all');
 BEGIN
  PERFORM public.abuse_charge_v1(policy,scopes,'{"image.storage.unit.bytes":5,"image.storage.organization.bytes":5,"image.storage.global.bytes":5}');
  RAISE EXCEPTION 'global storage allocation reset'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='image.storage.global.bytes'),6::numeric,'failed reservation does not partially charge');
 PERFORM assert_true((SELECT bool_and(expires_at='infinity'::timestamptz AND bucket_at='epoch'::timestamptz) FROM public.abuse_budget_usage WHERE rule_key LIKE 'image.storage.%'),'capacity never expires');
 PERFORM assert_false(has_table_privilege('authenticated','public.image_project_imports','UPDATE'),'client cannot reassign project');
END $$;
