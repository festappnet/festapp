BEGIN;
-- All checks run under the real API database roles; setup remains privileged.
CREATE FUNCTION public._rpc_security_expect_denied(p_sql text) RETURNS void
LANGUAGE plpgsql SET search_path = public, extensions AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN insufficient_privilege THEN
    RETURN;
  END;
  RAISE EXCEPTION 'Expected insufficient_privilege: %', p_sql;
END $$;
GRANT EXECUTE ON FUNCTION public._rpc_security_expect_denied(text) TO anon, authenticated, service_role;

DO $$
DECLARE
  own_org bigint; foreign_org bigint; own_unit bigint; foreign_unit bigint;
  own_occ bigint; foreign_occ bigint; account bigint; foreign_account bigint;
  manager uuid := gen_random_uuid(); target uuid := gen_random_uuid(); outsider uuid := gen_random_uuid();
  bank_admin uuid := gen_random_uuid(); support_user uuid := gen_random_uuid(); editor uuid := gen_random_uuid();
  ids jsonb;
BEGIN
  INSERT INTO public.organizations(title) VALUES ('RPC security own') RETURNING id INTO own_org;
  INSERT INTO public.organizations(title) VALUES ('RPC security foreign') RETURNING id INTO foreign_org;
  INSERT INTO public.units(title,organization) VALUES ('RPC own',own_org) RETURNING id INTO own_unit;
  INSERT INTO public.units(title,organization) VALUES ('RPC foreign',foreign_org) RETURNING id INTO foreign_unit;
  INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
    VALUES ('RPC own',gen_random_uuid()::text,own_org,own_unit,now(),now()+interval '1 day') RETURNING id INTO own_occ;
  INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
    VALUES ('RPC foreign',gen_random_uuid()::text,foreign_org,foreign_unit,now(),now()+interval '1 day') RETURNING id INTO foreign_occ;
  INSERT INTO auth.users(id,email,last_sign_in_at) VALUES
    (manager,'rpc-manager@test.invalid',now()), (target,'rpc-target@test.invalid',now()),
    (outsider,'rpc-outsider@test.invalid',now()), (bank_admin,'rpc-bank-admin@test.invalid',now()),
    (support_user,'rpc-support@test.invalid',now()), (editor,'rpc-editor@test.invalid',now());
  INSERT INTO public.user_info(id,organization,email_readonly) VALUES
    (manager,own_org,'rpc-manager@test.invalid'),(target,own_org,'rpc-target@test.invalid'),
    (outsider,foreign_org,'rpc-outsider@test.invalid'),(bank_admin,own_org,'rpc-bank-admin@test.invalid'),
    (support_user,own_org,'rpc-support@test.invalid'),(editor,own_org,'rpc-editor@test.invalid');
  INSERT INTO public.unit_users(unit,"user",is_manager) VALUES (own_unit,manager,true),(own_unit,target,false);
  INSERT INTO public.unit_users(unit,"user",is_editor) VALUES (own_unit,bank_admin,true);
  INSERT INTO public.occasion_users(occasion,"user",is_editor) VALUES (own_occ,bank_admin,true);
  INSERT INTO public.organization_users(organization,"user",is_admin,is_hidden) VALUES (own_org,bank_admin,true,true);
  INSERT INTO public.occasion_users(occasion,"user",is_editor_view) VALUES (own_occ,editor,true),(own_occ,target,false);
  INSERT INTO eshop.bank_accounts(title) VALUES ('RPC own') RETURNING id INTO account;
  INSERT INTO eshop.bank_accounts(title) VALUES ('RPC foreign') RETURNING id INTO foreign_account;
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES (own_unit,account),(foreign_unit,foreign_account);
  INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin,is_support)
    VALUES (account,bank_admin,true,false),(account,support_user,false,true),(foreign_account,outsider,true,false);
  INSERT INTO public.email_templates(code,html,subject,organization,unit)
    VALUES ('RPC_SECURITY','own','own',own_org,own_unit),('RPC_SECURITY','foreign','foreign',foreign_org,foreign_unit);
  ids := jsonb_build_object('unit',own_unit,'foreign_unit',foreign_unit,'org',own_org,'foreign_org',foreign_org,
    'occasion',own_occ,'foreign_occasion',foreign_occ,'account',account,'foreign_account',foreign_account,
    'manager',manager,'target',target,'outsider',outsider,'bank_admin',bank_admin,'support',support_user,'editor',editor);
  PERFORM set_config('test.rpc_security',ids::text,true);
END $$;

SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.role','anon',true),set_config('request.jwt.claim.sub','',true);
DO $$
DECLARE x jsonb := current_setting('test.rpc_security')::jsonb; sig text;
BEGIN
  FOREACH sig IN ARRAY ARRAY['add_user_to_unit(bigint,uuid)','get_bank_account_users(bigint)',
    'get_bank_account_users(bigint,bigint)','get_user_id_by_email(text)','get_last_sign_in_at(uuid)',
    'get_entity_email_templates(text,bigint)','get_all_email_templates(jsonb)'] LOOP
    IF has_function_privilege('anon','public.'||sig,'EXECUTE') THEN
      RAISE EXCEPTION 'Anonymous EXECUTE retained on %',sig;
    END IF;
  END LOOP;
  PERFORM public._rpc_security_expect_denied(format('SELECT public.add_user_to_unit(%s,%L)',x->>'unit',x->>'target'));
  PERFORM public._rpc_security_expect_denied(format('SELECT * FROM public.get_bank_account_users(%s,%s)',x->>'account',x->>'unit'));
  PERFORM public._rpc_security_expect_denied('SELECT * FROM public.get_user_id_by_email(''rpc-target@test.invalid'')');
  PERFORM public._rpc_security_expect_denied('SELECT public.process_token_register(''{"email":"rpc-legacy@test.invalid"}''::jsonb)');
  PERFORM public._rpc_security_expect_denied(format('SELECT public.get_last_sign_in_at(%L)',x->>'target'));
  PERFORM public._rpc_security_expect_denied(format('SELECT public.get_entity_email_templates(''unit'',%s)',x->>'unit'));
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
DO $$
DECLARE x jsonb := current_setting('test.rpc_security')::jsonb; n int; templates jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',x->>'manager',true);
  PERFORM public._rpc_security_expect_denied('SELECT public.process_token_register(''{"email":"rpc-legacy@test.invalid"}''::jsonb)');
  PERFORM public.add_user_to_unit((x->>'unit')::bigint,(x->>'target')::uuid);
  SELECT count(*) INTO n FROM public.get_bank_account_users((x->>'account')::bigint,(x->>'unit')::bigint);
  IF n <> 1 THEN RAISE EXCEPTION 'Linked unit manager roster or hidden-admin filtering failed'; END IF;
  PERFORM public._rpc_security_expect_denied(format('SELECT * FROM public.get_bank_account_users(%s)',x->>'account'));
  PERFORM public._rpc_security_expect_denied(format('SELECT * FROM public.get_bank_account_users(%s,%s)',x->>'foreign_account',x->>'unit'));
  PERFORM public._rpc_security_expect_denied(format('SELECT public.add_user_to_unit(%s,%L)',x->>'foreign_unit',x->>'outsider'));
  SELECT count(*) INTO n FROM public.get_user_id_by_email('rpc-target@test.invalid');
  IF n <> 1 THEN RAISE EXCEPTION 'Unit manager auth lookup failed'; END IF;
  PERFORM public.get_last_sign_in_at((x->>'target')::uuid);
  templates := public.get_entity_email_templates('unit',(x->>'unit')::bigint);
  IF NOT templates->'templates' @> '[{"code":"RPC_SECURITY","html":"own"}]'::jsonb THEN RAISE EXCEPTION 'Own unit templates absent'; END IF;
  PERFORM public._rpc_security_expect_denied(format('SELECT public.get_all_email_templates(%L::jsonb)',jsonb_build_object('unit',x->'unit','organization',x->'foreign_org')::text));

  PERFORM set_config('request.jwt.claim.sub',x->>'outsider',true);
  PERFORM public._rpc_security_expect_denied(format('SELECT public.add_user_to_unit(%s,%L)',x->>'unit',x->>'target'));
  PERFORM public._rpc_security_expect_denied(format('SELECT * FROM public.get_bank_account_users(%s,%s)',x->>'account',x->>'unit'));
  SELECT count(*) INTO n FROM public.get_user_id_by_email('rpc-target@test.invalid');
  IF n <> 0 THEN RAISE EXCEPTION 'Foreign auth UUID leaked'; END IF;
  PERFORM public._rpc_security_expect_denied(format('SELECT public.get_last_sign_in_at(%L)',x->>'target'));
  PERFORM public._rpc_security_expect_denied(format('SELECT public.get_entity_email_templates(''unit'',%s)',x->>'unit'));
  PERFORM public._rpc_security_expect_denied(format('SELECT public.get_entity_email_templates(''occasion'',%s)',x->>'occasion'));

  PERFORM set_config('request.jwt.claim.sub',x->>'bank_admin',true);
  SELECT count(*) INTO n FROM public.get_bank_account_users((x->>'account')::bigint);
  IF n <> 2 THEN RAISE EXCEPTION 'One-argument bank admin roster failed'; END IF;
  PERFORM public._rpc_security_expect_denied(format('SELECT * FROM public.get_bank_account_users(%s,%s)',x->>'account',x->>'foreign_unit'));
  SELECT count(*) INTO n FROM public.get_user_id_by_email('rpc-target@test.invalid');
  IF n <> 1 THEN RAISE EXCEPTION 'Organization admin auth lookup failed'; END IF;
  PERFORM public.get_all_email_templates(jsonb_build_object('organization',x->'org'));
  PERFORM set_config('request.jwt.claim.sub',x->>'support',true);
  SELECT count(*) INTO n FROM public.get_bank_account_users((x->>'account')::bigint,NULL::bigint);
  IF n <> 2 THEN RAISE EXCEPTION 'Bank support roster failed'; END IF;

  PERFORM set_config('request.jwt.claim.sub',x->>'editor',true);
  PERFORM public.get_last_sign_in_at((x->>'target')::uuid);
  PERFORM public.get_entity_email_templates('occasion',(x->>'occasion')::bigint);
  PERFORM public._rpc_security_expect_denied(format('SELECT public.add_user_to_unit(%s,%L)',x->>'unit',x->>'target'));
  PERFORM public._rpc_security_expect_denied(format('SELECT * FROM public.get_bank_account_users(%s,%s)',x->>'account',x->>'unit'));
  PERFORM public._rpc_security_expect_denied(format('SELECT public.get_all_email_templates(%L::jsonb)',jsonb_build_object('occasion',x->'occasion','unit',x->'foreign_unit')::text));
  PERFORM set_config('request.jwt.claim.sub',x->>'target',true);
  PERFORM public.get_last_sign_in_at((x->>'target')::uuid);
  SELECT count(*) INTO n FROM public.get_user_id_by_email('rpc-target@test.invalid');
  IF n <> 1 THEN RAISE EXCEPTION 'Self auth lookup failed'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true),set_config('request.jwt.claim.sub','',true);
DO $$
DECLARE x jsonb := current_setting('test.rpc_security')::jsonb; n int;
BEGIN
  SELECT count(*) INTO n FROM public.get_user_id_by_email('rpc-target@test.invalid');
  IF n <> 1 THEN RAISE EXCEPTION 'Service auth lookup failed'; END IF;
  IF public.process_token_register('{}'::jsonb)->>'code' <> '400' THEN
    RAISE EXCEPTION 'Legacy service registration helper contract failed';
  END IF;
  PERFORM public.get_last_sign_in_at((x->>'target')::uuid);
  PERFORM public.add_user_to_unit((x->>'unit')::bigint,(x->>'target')::uuid);
  PERFORM public.get_entity_email_templates('unit',(x->>'unit')::bigint);
  SELECT count(*) INTO n FROM public.get_bank_account_users((x->>'account')::bigint);
  IF n <> 2 THEN RAISE EXCEPTION 'Service bank roster failed'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.role','anon',true),set_config('request.jwt.claim.sub','',true);
SELECT public._rpc_security_expect_denied('SELECT public.update_email_template(''{"organization":1,"code":"SECURITY_WRITE","html":"attack"}''::jsonb)');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
DO $$
DECLARE x jsonb := current_setting('test.rpc_security')::jsonb; data jsonb;
BEGIN
  data := jsonb_build_object('organization',x->'org','code','SECURITY_WRITE','html','safe','subject','safe');
  PERFORM set_config('request.jwt.claim.sub',x->>'outsider',true);
  PERFORM public._rpc_security_expect_denied(format('SELECT public.update_email_template(%L::jsonb)',data));
  PERFORM set_config('request.jwt.claim.sub',x->>'editor',true);
  PERFORM public._rpc_security_expect_denied(format('SELECT public.update_email_template(%L::jsonb)',data));
  PERFORM set_config('request.jwt.claim.sub',x->>'bank_admin',true);
  PERFORM public.update_email_template(data);
  PERFORM public.update_email_template(data || jsonb_build_object('unit',x->'unit'));
  PERFORM public.update_email_template(data || jsonb_build_object('occasion',x->'occasion'));
  PERFORM public._rpc_security_expect_denied(format('SELECT public.update_email_template(%L::jsonb)',data || jsonb_build_object('occasion',x->'foreign_occasion')));
END $$;
RESET ROLE;
DO $$
DECLARE x jsonb := current_setting('test.rpc_security')::jsonb; n integer;
BEGIN
  SELECT count(*) INTO n FROM public.email_templates WHERE code='SECURITY_WRITE' AND organization=(x->>'org')::bigint;
  IF n <> 3 THEN RAISE EXCEPTION 'Authorized email template write failed'; END IF;
END $$;
ROLLBACK;
