DO $$
DECLARE actor uuid; org bigint; unit_id bigint; occ bigint; f bigint; result jsonb;
  field_type text; choices jsonb; payload jsonb; cmd uuid:=gen_random_uuid(); copied bigint;
  link text:='choices-'||gen_random_uuid();
BEGIN
  PERFORM create_user_for_test('choice-editor','choice-editor@example.invalid');
  actor:=get_user_id('choice-editor');
  INSERT INTO public.organizations(title) VALUES('Choice validation') RETURNING id INTO org;
  INSERT INTO public.units(organization,title) VALUES(org,'Choice validation') RETURNING id INTO unit_id;
  INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
    VALUES(org,unit_id,'Choice validation',link,now(),now()+interval '1 day') RETURNING id INTO occ;
  PERFORM public.reserve_public_link_internal('occasion',occ,link,true);
  UPDATE public.user_info SET organization=org WHERE id=actor;
  INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order,is_editor_view,is_editor_order_view)
    VALUES(occ,actor,true,true,true,true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  INSERT INTO public.forms(occasion,title,link) VALUES(occ,'Přihláška',link) RETURNING id INTO f;
  PERFORM public.reserve_public_link_internal('form',f,link,true);
  payload:=jsonb_build_object('id',f,'occasion',occ,'title','Changed');
  FOREACH field_type IN ARRAY ARRAY['select_one','select_many'] LOOP
    FOR choices IN SELECT value FROM jsonb_array_elements('[null,{}, {"options":[]}, {"options":[{"value":" "}]}, {"options":[{"value":null}]}]'::jsonb) LOOP
      result:=public.update_form_internal_v1(payload||jsonb_build_object('form_fields',jsonb_build_array(
        jsonb_build_object('type',field_type,'data',choices,'is_required',true))));
      PERFORM assert_eq(result->>'code','422','invalid options rejected');
      PERFORM assert_eq((SELECT title FROM public.forms WHERE id=f),'Přihláška','failed save retains persisted form');
      PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=f),'invalid field not persisted');
    END LOOP;
  END LOOP;
  -- A settings-only save does not prevent repairing a legacy field later.
  result:=public.update_form_internal_v1(payload);
  PERFORM assert_eq(result->>'code','200','partial settings save allowed');
  result:=public.update_form_internal_v1(payload||jsonb_build_object('title','Přihláška','form_fields',jsonb_build_array(
    jsonb_build_object('type','select_one','data',jsonb_build_object('options',jsonb_build_array(jsonb_build_object('value','Ranní skupina')))))));
  PERFORM assert_eq(result->>'code','200','valid choice saves');
  result:=public.duplicate_form_to_occasion_client_sync_v1(f,link,cmd,'cs');
  copied:=(result#>>'{data,formId}')::bigint;
  PERFORM assert_eq((SELECT title FROM public.forms WHERE id=copied),'Přihláška (kopie)','Czech copy title');
  PERFORM assert_eq(public.duplicate_form_to_occasion_client_sync_v1(f,link,cmd,'cs')#>>'{data,formId}',copied::text,'copy replay keeps identity');
  result:=public.duplicate_form_to_occasion_client_sync_v1(f,link,gen_random_uuid());
  PERFORM assert_eq((SELECT title FROM public.forms WHERE id=(result#>>'{data,formId}')::bigint),'Přihláška (copy)','older caller English default');
END $$;
