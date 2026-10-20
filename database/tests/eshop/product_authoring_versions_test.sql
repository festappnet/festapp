BEGIN;
DO $$
<<authoring_versions>>
DECLARE actor uuid; org bigint; un bigint; oc bigint; pt bigint; prod bigint; form_id bigint; field_id bigint;
 pool bigint; ctx bigint; spot bigint; result jsonb; payload jsonb; form_payload jsonb; product_json jsonb; snapshot jsonb;
 cmd uuid; link text:=gen_random_uuid()::text; ver bigint;
BEGIN
 PERFORM public.create_user_for_test('product-versions','product-versions@example.invalid');actor:=public.get_user_id('product-versions');
 INSERT INTO public.organizations(title) VALUES('Product versions') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Product versions',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Product versions',org,un,link,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor_view,is_editor) VALUES(oc,actor,true,true,true,true);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,price,currency_code,occasion,product_type) VALUES('Original',10,'CZK',oc,pt) RETURNING id INTO prod;
 INSERT INTO public.forms(title,occasion,link) VALUES('Original form',oc,link) RETURNING id INTO form_id;
 PERFORM public.reserve_public_link_internal('occasion',oc,link,true);PERFORM public.reserve_public_link_internal('form',form_id,link,true);
 INSERT INTO public.form_fields(form,type,title,product_type) VALUES(form_id,'product_type','Admission',pt) RETURNING id INTO field_id;
 INSERT INTO public.inventory_pools(title,occasion) VALUES('Pool',oc) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(title,inventory_pool) VALUES('Context',pool) RETURNING id INTO ctx;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 snapshot:=public.get_products_and_types_for_edit(link)::jsonb;
 ASSERT snapshot#>>'{products,0,aggregate_version}'='0';
 snapshot:=public.get_product_for_authoring_v1(prod);
 ASSERT snapshot->>'aggregate_version'='0';ASSERT NOT snapshot ?| ARRAY['forms','orders','tickets','secret'];
 payload:=jsonb_build_object('id',prod,'title','Saved','expected_aggregate_version',0,'inventory_contexts',jsonb_build_array(jsonb_build_object('inventory_context_id',ctx,'quantity',1)));
 cmd:=gen_random_uuid();EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.update_product_client_sync_v1(payload,cmd);ASSERT result->>'status'='applied';ASSERT result#>>'{data,aggregate_version}'='1';
 ASSERT public.update_product_client_sync_v1(payload,cmd)=result;
 ASSERT public.update_product_client_sync_v1(payload||jsonb_build_object('title','Stale','inventory_contexts','[]'::jsonb),gen_random_uuid())->>'status'='conflict';
 ASSERT public.update_product_inventory_contexts_client_sync_v1(prod,jsonb_build_object('expected_aggregate_version',1,'contexts','[]'::jsonb),gen_random_uuid())->>'status'='applied';
 ASSERT public.update_product_inventory_contexts_client_sync_v1(prod,jsonb_build_object('expected_aggregate_version',1,'contexts','[]'::jsonb),gen_random_uuid())->>'status'='conflict';
 EXECUTE 'RESET ROLE';
 ASSERT (SELECT title='Saved' FROM eshop.products WHERE id=prod);
 product_json:=jsonb_build_object('id',prod,'title','Form edit','price',10,'currency_code','CZK','is_hidden',false);
 form_payload:=jsonb_build_object('id',form_id,'occasion',oc,'link',link,'title','Form edit','expected_aggregate_version',0,
  'expected_product_versions',jsonb_build_object(prod::text,2),'expected_product_type_versions',jsonb_build_object(pt::text,0),
  'form_fields',jsonb_build_array(jsonb_build_object('id',field_id,'type','product_type','title','Admission',
   'product_type',jsonb_build_object('id',pt,'title','Admission','type','spot','products',jsonb_build_array(product_json)))));
 -- Another editor saves the product after the form editor loaded it.
 PERFORM public.update_product_client_sync_v1(jsonb_build_object('id',prod,'title','Other editor','expected_aggregate_version',2),gen_random_uuid());
 result:=public.update_form_client_sync_v1(form_payload,gen_random_uuid());ASSERT result->>'status'='conflict';ASSERT result#>>'{data,entity_type}'='product';
 ASSERT (SELECT title='Original form' FROM public.forms WHERE id=form_id);
 ASSERT (SELECT title='Other editor' FROM eshop.products WHERE id=prod);
 -- Reopened form starts from an explicit new snapshot, never a silent client rebase.
 form_payload:=jsonb_set(form_payload,ARRAY['expected_product_versions',prod::text],'3');
 result:=public.update_form_client_sync_v1(form_payload,gen_random_uuid());ASSERT result->>'status'='applied',result::text;
 ASSERT result#>>ARRAY['data','product_versions',prod::text]='4';ASSERT result#>>ARRAY['data','product_type_versions',pt::text]='1';
 ASSERT public.update_product_client_sync_v1(jsonb_build_object('id',prod,'title','Stale product','expected_aggregate_version',3),gen_random_uuid())->>'status'='conflict';
 -- A second form sharing the type cannot overwrite an intervening type edit.
 form_payload:=jsonb_set(form_payload,'{expected_aggregate_version}','1');
 form_payload:=jsonb_set(form_payload,ARRAY['expected_product_versions',prod::text],'4');
 result:=public.update_form_client_sync_v1(form_payload,gen_random_uuid());ASSERT result->>'status'='conflict';ASSERT result#>>'{data,entity_type}'='product_type';
 -- Pool context reconciliation also invalidates the original product snapshot.
 PERFORM public.update_product_inventory_contexts_client_sync_v1(prod,jsonb_build_object('expected_aggregate_version',4,'contexts',jsonb_build_array(jsonb_build_object('inventory_context_id',ctx,'quantity',1))),gen_random_uuid());
 result:=public.save_inventory_pool_client_sync_v1(oc,gen_random_uuid(),0,jsonb_build_object('pool',jsonb_build_object('id',pool,'occasion',oc,'title','Pool changed'),'contexts','[]'::jsonb));
 ASSERT result->>'status'='applied';
 ASSERT public.update_product_client_sync_v1(jsonb_build_object('id',prod,'expected_aggregate_version',5),gen_random_uuid())->>'status'='conflict';
 -- Scheduling actual application advances the same product aggregate.
 SELECT version INTO ver FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=oc AND aggregate_id=prod::text;
 INSERT INTO eshop.planned_changes(occasion,subject_id,change_type,new_value,change_time) VALUES(oc,prod,'products.price','15',now()-interval '1 day');
 PERFORM set_config('request.jwt.claim.role','service_role',true);PERFORM public.apply_planned_changes();
 ASSERT (SELECT price=15 FROM eshop.products WHERE id=prod);
 ASSERT (SELECT version=ver+1 FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=oc AND aggregate_id=prod::text);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 ASSERT NOT has_table_privilege('authenticated','eshop.products','UPDATE');
 ASSERT NOT has_function_privilege('service_role','public.apply_planned_changes_obsolete_v1()','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.advance_ticketing_authoring_version_internal_v1(text,bigint,bigint)','EXECUTE');
END $$;
ROLLBACK;
