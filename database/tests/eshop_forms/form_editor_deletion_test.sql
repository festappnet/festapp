-- Real editor permissions; every fixture is rolled back by the test runner.
DO $$
DECLARE
  actor uuid; org bigint; unit_id bigint; occ bigint; form_id bigint; other_form bigint;
  answered bigint; unused bigint; late_field bigint; group_field bigint;
  pt bigint; prod bigint; order_id bigint; spot_id bigint;
  pool_id bigint; context_id bigint;
  result jsonb; payload jsonb; field_json jsonb;
  link text := 'delete-test-' || gen_random_uuid();
BEGIN
  PERFORM create_user_for_test('form-delete-editor','form-delete-editor@example.invalid');
  actor:=get_user_id('form-delete-editor');
  INSERT INTO public.organizations(title) VALUES ('Deletion test') RETURNING id INTO org;
  INSERT INTO public.units(organization,title) VALUES (org,'Deletion test') RETURNING id INTO unit_id;
  INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
    VALUES (org,unit_id,'Deletion test',link,now(),now()+interval '1 day') RETURNING id INTO occ;
  UPDATE public.user_info SET organization=org WHERE id=actor;
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor_view) VALUES(occ,actor,true,true,true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  INSERT INTO public.forms(occasion,title,link) VALUES (occ,'Original',link) RETURNING id INTO form_id;
  INSERT INTO public.form_fields(form,type,title) VALUES (form_id,'text','Answered') RETURNING id INTO answered;
  INSERT INTO public.form_fields(form,type,title) VALUES (form_id,'text','Unused') RETURNING id INTO unused;
  INSERT INTO public.form_fields(form,type,title) VALUES (form_id,'text','Late answer') RETURNING id INTO late_field;
  INSERT INTO eshop.orders(order_symbol, occasion,form,state,data) VALUES (public.generate_order_symbol(), occ,form_id,'storno',
    jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(answered::text,'yes')))) RETURNING id INTO order_id;
  payload := jsonb_build_object('id',form_id,'occasion',occ,'link',link,'title','Changed');

  result := public.get_form_for_edit(link);
  SELECT value INTO field_json FROM jsonb_array_elements(result->'data'->'form_fields') WHERE (value->>'id')::bigint = answered;
  PERFORM assert_eq(field_json->>'delete_blocked_reason','responses','Cancelled orders still protect answers');
  SELECT value INTO field_json FROM jsonb_array_elements(result->'data'->'form_fields') WHERE (value->>'id')::bigint = unused;
  PERFORM assert_eq(field_json->>'can_delete','true','Other answers do not block an unused field');
  result := public.update_form_internal_v1(payload || jsonb_build_object('deleted_field_ids',jsonb_build_array(unused)));
  PERFORM assert_eq(result->>'code','200','Unused saved field can be deleted');
  PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_fields WHERE id=unused),'Field really deleted');

  -- The editor saw this field as unused, but an answer arrived before Save.
  UPDATE eshop.orders SET data=data || jsonb_build_object('fields',jsonb_build_array(
    jsonb_build_object(answered::text,'yes'),jsonb_build_object(late_field::text,false))) WHERE id=order_id;
  result := public.update_form_internal_v1(payload || jsonb_build_object('title','Must roll back','deleted_field_ids',jsonb_build_array(late_field)));
  PERFORM assert_eq(result->>'message','FORM_DELETE_responses','Save rechecks late answers, including false');
  PERFORM assert_eq((SELECT title FROM public.forms WHERE id=form_id),'Changed','Rejected save leaves metadata unchanged');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.form_fields WHERE id=late_field),'Rejected save retains field');
  INSERT INTO eshop.orders_history("order",data) SELECT id,data FROM eshop.orders WHERE id=order_id;
  UPDATE eshop.orders SET data='{}' WHERE id=order_id;
  result := public.get_form_for_edit(link);
  SELECT value INTO field_json FROM jsonb_array_elements(result->'data'->'form_fields') WHERE (value->>'id')::bigint = answered;
  PERFORM assert_eq(field_json->>'can_delete','true','Historical-only answers do not block editor eligibility');
  result := public.update_form_internal_v1(payload || jsonb_build_object('deleted_field_ids',jsonb_build_array(answered)));
  PERFORM assert_eq(result->>'code','200','Historical-only answers do not block deletion');
  PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_fields WHERE id=answered),'Historical-only field is deleted');
  PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=order_id),'Order history remains intact');

  INSERT INTO eshop.product_types(occasion,title,type) VALUES (occ,'Group','other') RETURNING id INTO pt;
  INSERT INTO public.form_fields(form,type,product_type) VALUES (form_id,'product_type',pt) RETURNING id INTO group_field;
  INSERT INTO eshop.products(occasion,product_type,title,price) VALUES (occ,pt,'Product',10) RETURNING id INTO prod;
  INSERT INTO eshop.spots(occasion,product) VALUES (occ,prod) RETURNING id INTO spot_id;
  result := public.get_form_for_edit(link);
  PERFORM assert_eq(result->'data'->'products'->0->>'delete_blocked_reason','blueprint','Blueprint usage exposed to UI');
  result := public.update_form_internal_v1(payload || jsonb_build_object('deleted_field_ids',jsonb_build_array(group_field)));
  PERFORM assert_eq(result->>'message','FORM_DELETE_blueprint','Removing a whole group cannot bypass usage');
  DELETE FROM eshop.spots WHERE id=spot_id;

  INSERT INTO public.inventory_pools(occasion,title) VALUES (occ,'Pool') RETURNING id INTO pool_id;
  INSERT INTO public.inventory_contexts(inventory_pool) VALUES (pool_id) RETURNING id INTO context_id;
  INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES (prod,context_id,1);
  result := public.update_form_internal_v1(payload || jsonb_build_object('deleted_product_ids',jsonb_build_array(prod)));
  PERFORM assert_eq(result->>'message','FORM_DELETE_inventory','Inventory link blocks cascade deletion');
  DELETE FROM eshop.product_inventory_contexts WHERE product=prod;

  INSERT INTO public.forms(occasion,title,link) VALUES (occ,'Other',link||'-other') RETURNING id INTO other_form;
  INSERT INTO public.form_fields(form,type,product_type) VALUES (other_form,'product_type',pt);
  result := public.update_form_internal_v1(payload || jsonb_build_object('deleted_product_ids',jsonb_build_array(prod)));
  PERFORM assert_eq(result->>'message','FORM_DELETE_shared','Other forms protect shared products');
  DELETE FROM public.form_fields WHERE form=other_form;
  INSERT INTO eshop.order_product_ticket("order",product) VALUES (order_id,prod);
  result := public.update_form_internal_v1(payload || jsonb_build_object('deleted_product_ids',jsonb_build_array(prod)));
  PERFORM assert_eq(result->>'message','FORM_DELETE_orders','Cancelled orders protect products too');
  DELETE FROM eshop.order_product_ticket WHERE product=prod;
  INSERT INTO eshop.orders_history("order",data) VALUES(order_id,jsonb_build_object('tickets',jsonb_build_array(jsonb_build_object('products',jsonb_build_array(jsonb_build_object('id',prod))))));
  result := public.get_form_for_edit(link);
  PERFORM assert_eq(result->'data'->'products'->0->>'can_delete','true','Historical-only product usage does not block editor eligibility');
  result := public.update_form_internal_v1(payload || jsonb_build_object('deleted_product_ids',jsonb_build_array(prod)));
  PERFORM assert_eq(result->>'code','200','Historical-only product usage does not block deletion');
  PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.products WHERE id=prod),'Product really deleted');

  INSERT INTO public.form_fields(form,type) VALUES (other_form,'text') RETURNING id INTO unused;
  result := public.update_form_internal_v1(payload || jsonb_build_object('deleted_field_ids',jsonb_build_array(unused)));
  PERFORM assert_eq(result->>'message','FORM_DELETE_changed','Cannot delete another form field');
  result := public.update_form_internal_v1(payload);
  PERFORM assert_eq(result->>'code','200','Older/partial payload still works');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.form_fields WHERE id=late_field),'Omitted fields are never implicit deletions');
  UPDATE public.occasion_users SET is_editor_order=false WHERE occasion=occ AND "user"=actor;
  result:=public.update_form_internal_v1(payload || jsonb_build_object('title','Unauthorized'));
  PERFORM assert_eq((result->>'code')::int,403,'Revoked editor permission denies save');
  PERFORM assert_eq((SELECT title FROM public.forms WHERE id=form_id),'Changed','Denied save preserves metadata');
END $$;
