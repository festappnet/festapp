-- Transaction-local tenants and emails; the SQL runner rolls everything back.
CREATE FUNCTION pg_temp.meta_capi_request_fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; other_org bigint; un bigint; spare bigint; manager uuid:=gen_random_uuid();
 admin uuid:=gen_random_uuid(); admin2 uuid:=gen_random_uuid(); no_email uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); editor uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Kulturní platforma','{"DEFAULT_URL":"https://example.invalid/","DEFAULT_LANGUAGE":"en"}') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other platform') RETURNING id INTO other_org;
 INSERT INTO public.units(title,organization) VALUES('Kulturní spolek',org) RETURNING id INTO un;
 -- A second managed Unit lets the manager delete the first one.
 INSERT INTO public.units(title,organization) VALUES('Spare organizer',org) RETURNING id INTO spare;
 INSERT INTO auth.users(id,email) VALUES(manager,manager||'@example.invalid'),(admin,admin||'@example.invalid'),
  (admin2,admin2||'@example.invalid'),(no_email,NULL),(outsider,outsider||'@example.invalid'),(editor,editor||'@example.invalid');
 INSERT INTO public.user_info(id,organization) VALUES(manager,org),(admin,org),(admin2,org),(no_email,org),(outsider,other_org),(editor,org);
 UPDATE public.user_info SET email_readonly=id||'@example.invalid' WHERE id IN (manager,admin,admin2,outsider,editor);
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,manager,true,false),(spare,manager,true,false),(un,editor,false,true);
 UPDATE public.unit_users SET is_editor_view=true WHERE unit=un AND "user"=editor;
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,admin,true),(org,admin2,true),(org,no_email,true),(other_org,outsider,true);
 PERFORM set_config('request.jwt.claim.sub',manager::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 RETURN jsonb_build_object('organization',org,'unit',un,'spare',spare,'manager',manager,'admin',admin,'admin2',admin2,'outsider',outsider,'editor',editor);
END $$;


DO $$
DECLARE x jsonb:=pg_temp.meta_capi_request_fixture(); un bigint:=(x->>'unit')::bigint;
 org bigint:=(x->>'organization')::bigint; result jsonb; actor text;
BEGIN
 UPDATE public.units SET data=coalesce(data,'{}')||'{"measurement_websites":["https://example.invalid"]}' WHERE id=un;
 SET LOCAL ROLE authenticated;
 result:=public.get_unit_meta_purchase(un);
 PERFORM assert_true(result->'websites' ? 'https://example.invalid','Unit manager loads the settings directly');
 result:=public.save_unit_meta_purchase(un,'123456','https://example.invalid','TEST123',true,repeat('fixture-token-',3));
 PERFORM assert_true(result->'enabled'='true'::jsonb AND result->'token_saved'='true'::jsonb,'Unit manager can enable the connector');
 PERFORM assert_false(result ? 'token' OR result ? 'vault_secret','settings expose no credential');
 PERFORM assert_eq(public.request_unit_meta_capi_approval(un),
  '{"approved":true,"requested_at":null,"request_state":"not_requested","can_request":false}'::jsonb,
  'installed clients receive the current status without requesting approval');
 RESET ROLE;
 PERFORM assert_false(EXISTS(SELECT FROM analytics.organization_policy WHERE organization=org),'settings create no organization policy');
 PERFORM assert_false(EXISTS(SELECT FROM public.email_messages WHERE organization=org AND code='META_CAPI_APPROVAL_REQUEST'),'legacy adapters do not send mail');
 FOREACH actor IN ARRAY ARRAY[x->>'editor',x->>'outsider'] LOOP
  PERFORM set_config('request.jwt.claim.sub',actor,true);
  SET LOCAL ROLE authenticated;
  BEGIN
   PERFORM public.get_unit_meta_purchase(un);
   RAISE EXCEPTION 'unauthorized settings read';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
   PERFORM public.delete_unit_meta_purchase(un);
   RAISE EXCEPTION 'unauthorized disconnect';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',x->>'admin',true);
 SET LOCAL ROLE authenticated;
 PERFORM assert_true((public.get_unit_meta_purchase(un)->>'enabled')::boolean,'existing organization administrators retain access');
 RESET ROLE;
END $$;
