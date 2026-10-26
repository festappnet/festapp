-- Synthetic, transaction-local tenant; runner rolls back every fixture and RPC write.
CREATE FUNCTION pg_temp.legal_fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; other_org bigint; un bigint; spare bigint; manager uuid:=gen_random_uuid(); admin uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); editor uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Legal fixture','{"DEFAULT_URL":"https://example.invalid"}') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other legal fixture') RETURNING id INTO other_org;
 INSERT INTO public.units(title,organization) VALUES('Legal fixture',org) RETURNING id INTO un;
 INSERT INTO public.units(title,organization) VALUES('Spare legal fixture',org) RETURNING id INTO spare;
 INSERT INTO auth.users(id,email) VALUES(manager,manager||'@example.invalid'),(admin,admin||'@example.invalid'),(outsider,outsider||'@example.invalid'),(editor,editor||'@example.invalid');
 INSERT INTO public.user_info(id,organization) VALUES(manager,org),(admin,org),(outsider,other_org),(editor,org);
 UPDATE public.user_info SET email_readonly=id||'@example.invalid' WHERE id IN (manager,admin,outsider,editor);
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,manager,true,true),(spare,manager,true,true),(un,editor,false,true);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,admin,true),(other_org,outsider,true);
 PERFORM set_config('request.jwt.claim.sub',manager::text,true);
 RETURN jsonb_build_object('organization',org,'otherOrganization',other_org,'unit',un,'spare',spare,'manager',manager,'admin',admin,'outsider',outsider,'editor',editor);
END $$;
CREATE FUNCTION pg_temp.legal_data() RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"legalName":"  Kulturní spolek  ","countryCode":"cz","registrationNumber":"27074358","address":{"street":"Dlouhá 1","city":"Praha","postalCode":"11000"},"contactEmail":"PUBLIC@example.invalid","website":"https://example.invalid"}'::jsonb;
$$;
DO $$
DECLARE x jsonb:=pg_temp.legal_fixture(); un bigint:=(x->>'unit')::bigint; r jsonb; oc bigint; bank bigint; actor text; op text;
BEGIN
 PERFORM public.save_unit_legal_profile(un,0,pg_temp.legal_data());
 PERFORM public.submit_unit_verification(un,1);
 FOR actor IN SELECT unnest(ARRAY[x->>'outsider',x->>'editor','']) LOOP
  PERFORM set_config('request.jwt.claim.sub',actor,true);
  BEGIN PERFORM public.get_unit_legal_profile(un); RAISE EXCEPTION 'unauthorized profile read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.save_unit_legal_profile(un,2,pg_temp.legal_data()); RAISE EXCEPTION 'unauthorized save'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.submit_unit_verification(un,2); RAISE EXCEPTION 'unauthorized submit'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.review_unit_verification(un,2,'approve',NULL,NULL,'source'); RAISE EXCEPTION 'unauthorized approve'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_unit_verification_queue((x->>'organization')::bigint); RAISE EXCEPTION 'unauthorized queue'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',x->>'admin',true);
 r:=public.get_unit_verification_queue((x->>'organization')::bigint);
 PERFORM assert_eq(jsonb_array_length(r->'items'),1,'pending queue');
 PERFORM public.review_unit_verification(un,2,'approve',NULL,'SECRET','SOURCE');
 UPDATE public.units SET organization=(x->>'otherOrganization')::bigint WHERE id=un;
 PERFORM assert_true(public.get_verified_unit_identity_internal(un) IS NULL,'tenant move hides identity');
 PERFORM set_config('request.jwt.claim.sub',x->>'outsider',true);
 r:=public.get_unit_legal_profile(un);
 PERFORM assert_false((r->'profile')?'reviewNote','new tenant admin cannot read old note');
 PERFORM assert_eq(public.review_unit_verification(un,3,'revoke','reason')->>'code','422'::text,'old tenant approval cannot be reviewed as current');
 PERFORM set_config('request.jwt.claim.sub',x->>'manager',true);
 r:=public.save_unit_legal_profile(un,3,pg_temp.legal_data());
 PERFORM assert_eq(r#>>'{profile,status}','unverified'::text,'save after move clears prior approval even same data');
 PERFORM assert_true((SELECT reviewed_organization_id IS NULL AND review_note IS NULL FROM public.unit_legal_profiles WHERE unit_id=un),'old review metadata reset');
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time) VALUES('Demo legal',un,(x->>'otherOrganization')::bigint,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Legal demo','CASH') RETURNING id INTO bank;
 INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,sort_order,description,reference_at) VALUES(oc,(x->>'otherOrganization')::bigint,'ball','legal-test',bank,0,'Synthetic',now());
 BEGIN PERFORM public.save_unit_legal_profile(un,4,pg_temp.legal_data()); RAISE EXCEPTION 'demo save'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.submit_unit_verification(un,4); RAISE EXCEPTION 'demo submit'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',x->>'outsider',true);
 BEGIN PERFORM public.review_unit_verification(un,4,'approve',NULL,NULL,'source'); RAISE EXCEPTION 'demo approve'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH actor IN ARRAY ARRAY['anon','authenticated'] LOOP
  PERFORM assert_false(has_table_privilege(actor,'public.unit_legal_profiles','SELECT'),'profile SELECT denied');
  FOREACH op IN ARRAY ARRAY['INSERT','UPDATE','DELETE'] LOOP
   PERFORM assert_false(has_table_privilege(actor,'public.unit_legal_profiles',op),'profile direct DML denied');
   PERFORM assert_false(has_table_privilege(actor,'public.unit_legal_profile_audit',op),'audit direct DML denied');
  END LOOP;
  PERFORM assert_false(has_table_privilege(actor,'public.unit_legal_profile_audit','SELECT'),'audit SELECT denied');
  PERFORM assert_false(has_function_privilege(actor,'public.get_verified_unit_identity_internal(bigint)','EXECUTE'),'public helper execute denied');
 END LOOP;
END $$;
