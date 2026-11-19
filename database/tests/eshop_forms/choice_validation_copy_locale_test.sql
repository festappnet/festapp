DO $$
DECLARE actor uuid; org bigint; unit_id bigint; occ bigint; f bigint; result jsonb;
  field_type text; choices jsonb; payload jsonb; cmd uuid:=gen_random_uuid(); copied bigint;
  primary_type bigint; empty_type bigint; source_plan bigint; target_occasion bigint;
  target_link text:='choices-target-'||gen_random_uuid();
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
  -- Copying must not let an editor publish another administrator's code.
  UPDATE public.forms SET data=coalesce(data,'{}')||'{"analytics":{"gtm_container":"GTM-AB12","scripts":"<script>window.test=1</script>"}}'::jsonb WHERE id=f;
  -- Legacy price fields must be canonicalized at the standalone form-copy
  -- boundary too, without hiding sale products or carrying empty selectors.
  INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Admission','spot') RETURNING id INTO primary_type;
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) VALUES(occ,primary_type,'Standard',100,'CZK',false);
  INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Unused','spot') RETURNING id INTO empty_type;
  INSERT INTO public.form_fields(form,type,product_type,is_ticket_field,is_hidden) VALUES(f,'product_type',primary_type,true,true),(f,'product_type',empty_type,true,true);
  INSERT INTO eshop.blueprints(occasion,organization,title)
    VALUES(occ,org,'Source plan') RETURNING id INTO source_plan;
  UPDATE public.forms SET blueprint=source_plan WHERE id=f;
  result:=public.duplicate_form_to_occasion_client_sync_v1(f,link,cmd,'cs');
  copied:=(result#>>'{data,formId}')::bigint;
  PERFORM assert_eq((SELECT count(*)::integer FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type WHERE ff.form=copied AND pt.type='spot'),1,'Standalone copy drops obsolete empty selector');
  PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type WHERE ff.form=copied AND pt.type='spot' AND ff.is_hidden),'Standalone copy has canonical primary visibility');
  PERFORM public.assert_form_primary_products_internal(copied);
  PERFORM assert_eq((SELECT blueprint FROM public.forms WHERE id=copied),source_plan,'Same-occasion copy keeps its scoped plan');

  PERFORM assert_false((SELECT data ? 'analytics' FROM public.forms WHERE id=copied),'form copy omits measurement code');
  PERFORM assert_eq((SELECT title FROM public.forms WHERE id=copied),'Přihláška (kopie)','Czech copy title');
  PERFORM assert_eq(public.duplicate_form_to_occasion_client_sync_v1(f,link,cmd,'cs')#>>'{data,formId}',copied::text,'copy replay keeps identity');
  result:=public.duplicate_form_to_occasion_client_sync_v1(f,link,gen_random_uuid());
  PERFORM assert_eq((SELECT title FROM public.forms WHERE id=(result#>>'{data,formId}')::bigint),'Přihláška (copy)','older caller English default');
  -- A standalone copy across occasions has no binding to the source plan.
  INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
    VALUES(org,unit_id,'Copy destination',target_link,now(),now()+interval '1 day') RETURNING id INTO target_occasion;
  PERFORM public.reserve_public_link_internal('occasion',target_occasion,target_link,true);
  INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order,is_editor_view,is_editor_order_view)
    VALUES(target_occasion,actor,true,true,true,true);
  result:=public.duplicate_form_to_occasion_client_sync_v1(f,target_link,gen_random_uuid(),'cs');
  copied:=(result#>>'{data,formId}')::bigint;
  PERFORM assert_eq((SELECT occasion FROM public.forms WHERE id=copied),target_occasion,'Copy belongs to the destination occasion');
  SELECT jsonb_build_object('id',id,'occasion',occasion,'blueprint',blueprint,'title','Updated copy')
    INTO payload FROM public.forms WHERE id=copied;
  result:=public.update_form_client_sync_v1(payload,gen_random_uuid());
  PERFORM assert_eq(result->>'code','200','The destination form saves without Foreign blueprint');
  PERFORM assert_true((SELECT blueprint IS NULL FROM public.forms WHERE id=copied),'Copy has no source plan');
END $$;
