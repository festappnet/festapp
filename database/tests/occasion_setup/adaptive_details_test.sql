UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('occasion.creation','occasion.draft');
DO $$
DECLARE actor uuid; org bigint; unit_id bigint; other_unit bigint; draft uuid:=gen_random_uuid(); d jsonb; payload jsonb;
 suggestion jsonb; count_before bigint; response jsonb; occasion_id bigint; product_id bigint; old_product bigint; new_form bigint; bank_id bigint; bank_info jsonb;
 image_url text:='https://img.festapp.net/images/adaptive-fixture.webp';
BEGIN
 PERFORM create_user_for_test('adaptive_setup_manager','adaptive_setup@test.local');
 actor:=get_user_id('adaptive_setup_manager');
 INSERT INTO public.organizations(title,data) VALUES('Adaptive setup','{"IS_APP_SUPPORTED":false}') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Adaptive',org) RETURNING id INTO unit_id;
 INSERT INTO public.units(title,organization) VALUES('Other',org) RETURNING id INTO other_unit;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(unit_id,actor,true,true);
 INSERT INTO public.images(link,unit) VALUES(image_url,unit_id);
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies) VALUES('Fixture bank','OTHER','CZ6508000000192000145399',ARRAY['CZK']) RETURNING id INTO bank_id;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(unit_id,bank_id,0);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft,unit_id);
 bank_info:=public.get_occasion_setup_bank_accounts(draft);
 PERFORM assert_eq((bank_info->'accounts'->0->>'id')::bigint,bank_id,'Draft editor sees linked receiving account');
 PERFORM assert_false((bank_info->'accounts'->0) ?| ARRAY['token_masked','pairing_code','token_expiry_date'],'Draft read excludes connection credentials');
 PERFORM assert_true(coalesce(bank_info#>'{accounts,0,bank_sync}','null'::jsonb)='null'::jsonb OR ((bank_info#>'{accounts,0,bank_sync}')-'state'-'mode')='{}'::jsonb,'Draft connection exposes only state and mode');
 payload:=d->'data'||jsonb_build_object('title','Žluťoučký ples','start','2090-05-01T18:00:00Z','end','2090-05-02T02:00:00Z',
   'link','','reviewConfirmed',true,'formEnabled',true);
 payload:=jsonb_set(payload,'{title}',to_jsonb('Žluťoučký ples'::text));
 payload:=jsonb_set(payload,'{formDraft,title}',to_jsonb('Registration'::text));
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,1);
 suggestion:=public.suggest_occasion_setup_form_link(draft,'Žluťoučký ples',NULL);
 PERFORM assert_eq(suggestion->>'suggestion','zlutoucky_ples_2090','Title normalization and event year');
 PERFORM assert_eq(public.suggest_occasion_setup_form_link(draft,'QA Wizard - běžný průchod 2026-10-22',NULL)->>'suggestion','qa_wizard_bezny_pruchod_2026_10_22','Mixed separators become valid slug boundaries');
 PERFORM assert_eq(public.suggest_occasion_setup_form_link(draft,'---',NULL)->>'suggestion','akce_2090','Punctuation-only title gets a valid fallback');
 PERFORM assert_true((public.suggest_occasion_setup_form_link(draft,repeat('a',63)||' - konec',NULL)->>'suggestion') ~ '^[a-z0-9]+([-_][a-z0-9]+)*$','Truncation preserves valid boundaries');
 EXECUTE 'RESET ROLE';
 SELECT count(*) INTO count_before FROM public.form_link_reservations;
 -- Deleted historical URLs remain unavailable.
 INSERT INTO public.form_link_reservations(slug,form) VALUES('zlutoucky_ples_2090',NULL);
 EXECUTE 'SET LOCAL ROLE authenticated';
 suggestion:=public.suggest_occasion_setup_form_link(draft,'Žluťoučký ples','zlutoucky_ples_2090');
 PERFORM assert_eq(suggestion->>'suggestion','zlutoucky_ples_2090_2','Taken title gets a readable suffix');
 PERFORM assert_false((suggestion->>'available')::boolean,'Tombstones are unavailable');
 PERFORM assert_true((public.suggest_occasion_setup_form_link(draft,'Žluťoučký ples','volna-adresa')->>'available')::boolean,'Free manual URL check');
 PERFORM assert_false((public.suggest_occasion_setup_form_link(draft,'Žluťoučký ples','Not valid')->>'available')::boolean,'Invalid manual URL');
 BEGIN PERFORM public.suggest_occasion_setup_form_link(gen_random_uuid(),'Title',NULL); RAISE EXCEPTION 'Missing draft accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.form_link_reservations),count_before+1,'Suggestions do not reserve URLs');
 PERFORM assert_false(has_function_privilege('anon','public.suggest_occasion_setup_form_link(uuid,text,text)','EXECUTE'),'Suggestions are authenticated');
 -- Simulate another writer taking the preview before finalization.
 INSERT INTO public.form_link_reservations(slug,form) VALUES('zlutoucky_ples_2090_2',NULL);
 old_product:=(payload#>>'{formDraft,fields,2,product_type_data,products,0,id}')::bigint;
 payload:=jsonb_set(payload,'{formDraft,link}',to_jsonb('zlutoucky_ples_2090_2'::text))||jsonb_build_object(
   'formLinkAutomatic',true,'introImage',image_url,'isPromoted',true,'placeName','Kulturní dům',
   'listPubliclyOnPublish',false,'description','Slavnostní večer','bankAccountId',bank_id,
   'bankAccountFingerprint',bank_info->'accounts'->0->>'fingerprint','priceWavesEnabled',true,'priceWaves',jsonb_build_array(jsonb_build_object(
     'change_time',now()+interval '60 days','targets',jsonb_build_array(jsonb_build_object('product',old_product,'price',120)))));
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 response:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());
 occasion_id:=(response#>>'{data,occasionId}')::bigint;
 EXECUTE 'RESET ROLE';
 SELECT id INTO new_form FROM public.forms WHERE occasion=occasion_id ORDER BY id LIMIT 1;
 PERFORM assert_eq((SELECT bank_account FROM public.forms WHERE id=new_form),bank_id,'Confirmed account is pinned to form');
 PERFORM assert_eq((SELECT link FROM public.forms WHERE id=new_form),'zlutoucky_ples_2090_3','Commit rechecks automatic suggestion');
 PERFORM assert_eq((SELECT data->>'image' FROM public.occasions WHERE id=occasion_id),image_url,'Intro image survives finalization');
 PERFORM assert_eq((SELECT data->>'place_name' FROM public.occasions WHERE id=occasion_id),'Kulturní dům','Venue survives finalization');
 PERFORM assert_true((SELECT is_promoted AND is_hidden AND NOT is_open FROM public.occasions WHERE id=occasion_id),'Promotion preference does not publish the event');
 SELECT subject_id INTO product_id FROM eshop.planned_changes WHERE occasion=occasion_id AND change_type='products.price';
 PERFORM assert_true(product_id IS NOT NULL AND product_id<>old_product,'Wave uses newly owned product ID');
 PERFORM assert_eq((SELECT new_value FROM eshop.planned_changes WHERE occasion=occasion_id AND change_type='products.price'),'120','Existing price queue owns the wave');
 PERFORM assert_eq((SELECT data->>'setup_listing_intent' FROM public.occasions WHERE id=occasion_id),'false','Listing intent retained without publishing');
 -- A missing selection or stale verified account cannot create a paid event.
 draft:=gen_random_uuid();
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft,unit_id);
 payload:=d->'data'||jsonb_build_object('title','Unconfirmed bank','start',now(),'end',now()+interval '1 day','reviewConfirmed',true,'bankAccountConfirmed',false);
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid()); RAISE EXCEPTION 'Missing bank confirmation accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 payload:=payload||jsonb_build_object('bankAccountId',bank_id,'bankAccountFingerprint','stale');
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid()); RAISE EXCEPTION 'Changed bank details accepted'; EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 EXECUTE 'RESET ROLE';
 -- Image and promotion validation happen before creating any event.
 draft:=gen_random_uuid();
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft,unit_id);
 payload:=d->'data'||jsonb_build_object('title','Invalid intro','start',now(),'end',now()+interval '1 day','reviewConfirmed',true,'isPromoted',true);
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid()); RAISE EXCEPTION 'Promoted without image'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 EXECUTE 'RESET ROLE';
 INSERT INTO public.images(link,unit) VALUES('https://img.festapp.net/images/foreign-fixture.webp',other_unit);
 payload:=payload||'{"introImage":"https://img.festapp.net/images/foreign-fixture.webp"}';
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid()); RAISE EXCEPTION 'Other unit image adopted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 DELETE FROM public.unit_users WHERE unit=unit_id AND "user"=actor;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.get_occasion_setup_bank_accounts(draft); RAISE EXCEPTION 'Revoked bank read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.suggest_occasion_setup_form_link(draft,'Revoked',NULL); RAISE EXCEPTION 'Revoked permission accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
END $$;
