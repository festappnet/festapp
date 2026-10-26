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
DECLARE x jsonb:=pg_temp.legal_fixture(); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint; r jsonb; m public.email_messages;
BEGIN
 UPDATE public.organizations SET data=coalesce(data,'{}')||'{"DEFAULT_URL":"https://example.invalid"}' WHERE id=org;
 PERFORM public.save_unit_legal_profile(un,0,pg_temp.legal_data());
 PERFORM public.submit_unit_verification(un,1);
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND unit=un AND code='UNIT_VERIFICATION_REQUEST'),1::bigint,'submission must notify the tenant owner');
 SELECT * INTO m FROM public.email_messages WHERE organization=org AND unit=un AND code='UNIT_VERIFICATION_REQUEST';
 PERFORM assert_eq(m.recipient,public.get_user_delivery_email((x->>'admin')::uuid),'only tenant administrator receives request');
 PERFORM assert_eq(m.recipient_user,(x->>'admin')::uuid,'recipient identity retained');
 PERFORM assert_eq(m.data->>'review_url','https://example.invalid/organizationEdit/'||org,'link opens platform review queue');
 PERFORM assert_eq(m.tracking_policy,'disabled'::text,'private admin request has no tracking');
 PERFORM public.enqueue_unit_verification_request(un);
 PERFORM public.submit_unit_verification(un,2);
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND code='UNIT_VERIFICATION_REQUEST'),1::bigint,'retry does not duplicate notice');
 PERFORM assert_false(has_function_privilege('authenticated','public.enqueue_unit_verification_request(bigint)','EXECUTE'),'applicants cannot invoke internal producer');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_true(public.email_intent_valid(m),'pending request for active admin is deliverable');
 UPDATE public.organization_users SET is_admin=false WHERE organization=org AND "user"=(x->>'admin')::uuid;
 PERFORM assert_false(public.email_intent_valid(m),'removed administrator cannot receive private request');
 UPDATE public.organization_users SET is_admin=true WHERE organization=org AND "user"=(x->>'admin')::uuid;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM public.save_unit_legal_profile(un,2,pg_temp.legal_data()||'{"legalName":"Changed after submission"}');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_false(public.email_intent_valid(m),'superseded request is not delivered');
END $$;
