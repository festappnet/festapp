DO $$
DECLARE actor uuid; org bigint; un bigint; draft uuid; d jsonb; payload jsonb; result jsonb; event_id bigint; visible boolean; expected_wrapper text;
BEGIN
 PERFORM create_user_for_test('setup_feedback_manager','setup-feedback@test.local');
 actor:=get_user_id('setup_feedback_manager');
 INSERT INTO public.organizations(title,data) VALUES('Feedback test','{"IS_APP_SUPPORTED":false}') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization,data) VALUES('Feedback test',org,'{"email_banner":"https://img.festapp.net/inherited.webp"}') RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 expected_wrapper:=public.email_banner_wrapper_internal('','Myslivecký ples');
 FOREACH visible IN ARRAY ARRAY[true,false] LOOP
  draft:=gen_random_uuid();
  EXECUTE 'SET LOCAL ROLE authenticated';
  d:=public.create_occasion_setup_draft(draft,un);
  payload:=d->'data'||jsonb_build_object('title','Myslivecký ples','start',now()+interval '10 days',
   'end',now()+interval '11 days','saleEnd',now()+interval '12 days','reviewConfirmed',true,
   'formEnabled',true,'saleMode','immediate','listPubliclyOnPublish',visible,'emailBanner','');
  payload:=jsonb_set(payload,'{formDraft,fields,2,product_type_data,products,0,price}','0');
  d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
  result:=public.get_occasion_setup_email_preview(draft,(d->>'revision')::bigint);
  PERFORM assert_eq(result->>'emailBanner','','Removed banner suppresses the inherited image in preview');
  PERFORM assert_eq(result#>>'{resolved,wrapper,html}',expected_wrapper,'Preview uses the saved-email wrapper owner');
  PERFORM assert_eq(result->>'inheritedEmailBanner','https://img.festapp.net/inherited.webp','Inheritance remains available for Restore');
  result:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());
  event_id:=(result#>>'{data,occasionId}')::bigint;
  PERFORM assert_eq((result#>>'{data,isOpen}')::boolean,visible,'Receipt returns actual open flag');
  PERFORM assert_eq((result#>>'{data,isHidden}')::boolean,NOT visible,'Receipt returns actual hidden flag');
  EXECUTE 'RESET ROLE';
  PERFORM assert_eq((SELECT is_hidden FROM public.occasions WHERE id=event_id),NOT visible,'Catalogue follows explicit visibility');
  PERFORM assert_eq((SELECT is_open FROM public.occasions WHERE id=event_id),visible,'Published entry is open');
  PERFORM assert_eq((SELECT (data#>>'{schedule,end_time}')::timestamptz FROM public.forms WHERE occasion=event_id),(payload->>'saleEnd')::timestamptz,'Sale can end after the event');
  PERFORM assert_eq((SELECT data->>'email_banner' FROM public.occasions WHERE id=event_id),'','Removed banner persists');
  PERFORM assert_true((SELECT html NOT LIKE '%<img%' AND html LIKE '%{{content}}%' FROM public.email_wrappers WHERE occasion=event_id),'Removed banner creates a valid wrapper without an image');
 END LOOP;
 PERFORM assert_true(public.email_banner_wrapper_internal('https://img.festapp.net/banner.webp','Ples "A&B"') LIKE '%alt="Ples &quot;A&amp;B&quot;"%','Banner title is escaped at its owner');
 PERFORM assert_true(public.email_banner_wrapper_internal(NULL,'Ples') IS NULL,'Inherited banner does not replace its wrapper');
 PERFORM assert_false(has_function_privilege('authenticated','public.email_banner_wrapper_internal(text,text)','EXECUTE'),'Wrapper owner is internal');
 PERFORM assert_true(public.occasion_setup_font_id_internal('Manrope') IS NOT NULL,'Custom picker font has a canonical PDF identity');
END $$;
