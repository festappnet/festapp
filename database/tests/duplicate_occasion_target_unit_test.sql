BEGIN;
DO $$
DECLARE actor uuid; org bigint; other_org bigint; source_unit bigint; target_unit bigint;
  denied_unit bigint; foreign_unit bigint; source bigint; copied bigint;
  same_copy bigint; bank bigint; shared_bank bigint; command uuid := gen_random_uuid();
  response jsonb; replay jsonb; destinations jsonb;
BEGIN
  PERFORM create_user_for_test('copy_target_manager', 'copy_target_manager@test.local');
  actor := get_user_id('copy_target_manager');
  INSERT INTO public.organizations(title) VALUES ('Copy tenant') RETURNING id INTO org;
  INSERT INTO public.organizations(title) VALUES ('Other copy tenant') RETURNING id INTO other_org;
  UPDATE public.user_info SET organization=org WHERE id=actor;
  INSERT INTO public.units(title,organization) VALUES ('Source',org) RETURNING id INTO source_unit;
  INSERT INTO public.units(title,organization) VALUES ('Target',org) RETURNING id INTO target_unit;
  INSERT INTO public.units(title,organization) VALUES ('Denied',org) RETURNING id INTO denied_unit;
  INSERT INTO public.units(title,organization) VALUES ('Foreign',other_org) RETURNING id INTO foreign_unit;
  INSERT INTO public.unit_users(unit,"user",is_manager,is_editor)
    VALUES (source_unit,actor,true,true),(target_unit,actor,true,true),(foreign_unit,actor,true,true);
  INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,data)
    VALUES (org,source_unit,'Source','copy-target-'||command,now(),now()+interval '1 day','{}')
    RETURNING id INTO source;
  INSERT INTO public.inventory_pools(title,occasion,sellable_capacity) VALUES('Ordered pool',source,17);
  INSERT INTO public.email_templates(occasion,unit,organization,code,title,subject,html)
    VALUES (source,source_unit,org,'TICKET_ORDER_CONFIRMATION','Custom title','Custom subject','Custom body');
  INSERT INTO public.email_templates(unit,organization,code,subject,html)
    VALUES (source_unit,org,'UNIT_COPY_INHERITED','Source inherited','Source inherited'),
           (target_unit,org,'UNIT_COPY_INHERITED','Target inherited','Target inherited');
  INSERT INTO public.information(occasion,unit,title) VALUES (source,source_unit,'Info');
  INSERT INTO public.places(occasion,unit,title) VALUES (source,source_unit,'Place');
  INSERT INTO eshop.blueprints(occasion,organization,title) VALUES (source,org,'Plan');
  INSERT INTO eshop.bank_accounts(title) VALUES ('Source only') RETURNING id INTO bank;
  INSERT INTO eshop.bank_accounts(title) VALUES ('Shared') RETURNING id INTO shared_bank;
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account)
    VALUES (source_unit,bank),(source_unit,shared_bank),(target_unit,shared_bank);
  INSERT INTO public.forms(occasion,title,link,bank_account,is_open)
    VALUES (source,'Source account','source-bank-'||command,bank,true),
           (source,'Shared account','shared-bank-'||command,shared_bank,true);

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  destinations := public.get_occasion_copy_units(source);
  PERFORM assert_eq(jsonb_array_length(destinations),2,'only same-tenant manager destinations');
  PERFORM assert_true(destinations @> jsonb_build_array(jsonb_build_object('id',target_unit)), 'target is offered');
  BEGIN
    PERFORM public.duplicate_occasion_client_sync_v1(source,gen_random_uuid(),denied_unit);
    RAISE EXCEPTION 'unauthorized target accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.duplicate_occasion_client_sync_v1(source,gen_random_uuid(),foreign_unit);
    RAISE EXCEPTION 'foreign tenant target accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  response := public.duplicate_occasion_client_sync_v1(source,command,target_unit);
  copied := (response #>> '{data,occasionId}')::bigint;
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.inventory_pools WHERE occasion=copied AND title='Ordered pool' AND sellable_capacity=17),'copied pool keeps configured capacity');
  PERFORM assert_eq((SELECT unit FROM public.occasions WHERE id=copied),target_unit,'copy belongs to target');
  PERFORM assert_eq((SELECT organization FROM public.occasions WHERE id=copied),org,'tenant unchanged');
  PERFORM assert_true(public.get_is_manager_on_occasion(copied),'creator can manage copy');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_templates WHERE occasion=copied
    AND unit=target_unit AND organization=org AND title='Custom title'
    AND subject='Custom subject' AND html='Custom body'),'template content and target ancestry');
  PERFORM assert_eq(public.get_email_template_and_wrapper('UNIT_COPY_INHERITED',
    jsonb_build_object('occasion',copied,'unit',target_unit,'organization',org))
    #>> '{template,html}', 'Target inherited', 'email inheritance uses target unit');
  PERFORM assert_eq((SELECT unit FROM public.information WHERE occasion=copied),target_unit,'information target');
  PERFORM assert_eq((SELECT unit FROM public.places WHERE occasion=copied),target_unit,'place target');
  PERFORM assert_eq((SELECT organization FROM eshop.blueprints WHERE occasion=copied),org,'blueprint tenant');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.forms WHERE occasion=copied AND title='Source account'
    AND bank_account IS NULL AND NOT is_open),'unavailable account removed and form closed');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.forms WHERE occasion=copied AND title='Shared account'
    AND bank_account=shared_bank AND is_open),'shared account retained');
  PERFORM assert_eq((SELECT unit FROM public.client_commits WHERE commit_id=
    (response #>> '{mutation,commitId}')::uuid),target_unit,'audit targets destination');
  replay := public.duplicate_occasion_client_sync_v1(source,command,target_unit);
  PERFORM assert_eq(replay #>> '{data,occasionId}',copied::text,'retry does not duplicate');
  BEGIN
    PERFORM public.duplicate_occasion_client_sync_v1(source,command,source_unit);
    RAISE EXCEPTION 'receipt target changed';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  same_copy := public.duplicate_occasion(source);
  PERFORM assert_eq((SELECT unit FROM public.occasions WHERE id=same_copy),source_unit,'legacy default is same unit');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.forms WHERE occasion=same_copy
    AND title='Source account' AND bank_account=bank AND is_open),'same-unit bank unchanged');
  UPDATE public.unit_users SET is_manager=false WHERE unit=source_unit AND "user"=actor;
  BEGIN
    PERFORM public.get_occasion_copy_units(source);
    RAISE EXCEPTION 'source list access accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.duplicate_occasion_client_sync_v1(source,gen_random_uuid(),target_unit);
    RAISE EXCEPTION 'source copy access accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
