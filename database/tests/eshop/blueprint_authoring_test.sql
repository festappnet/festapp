DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; oc2 bigint; bp bigint; bp2 bigint;
 pt bigint; product bigint; sid bigint; foreign_sid bigint; result jsonb; payload jsonb;
 command uuid:=gen_random_uuid(); form jsonb; form_id bigint;
BEGIN
 PERFORM public.create_user_for_test('blueprint-author','blueprint-author@example.invalid'); actor:=public.get_user_id('blueprint-author');
 INSERT INTO public.organizations(title) VALUES('Blueprint authoring') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Blueprint authoring',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Blueprint authoring',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Foreign blueprint',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc2;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(oc,actor,true,true);
 INSERT INTO eshop.blueprints(title,occasion,organization,objects) VALUES('Original',oc,org,'[]') RETURNING id INTO bp;
 INSERT INTO eshop.blueprints(occasion,organization) VALUES(oc2,org) RETURNING id INTO bp2;
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,price,currency_code,occasion,product_type) VALUES('Seat',10,'CZK',oc,pt) RETURNING id INTO product;
 INSERT INTO eshop.spots(title,occasion,blueprint,product) VALUES('Original seat',oc,bp,product) RETURNING id INTO sid;
 INSERT INTO eshop.spots(title,occasion,blueprint) VALUES('Foreign seat',oc2,bp2) RETURNING id INTO foreign_sid;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true); PERFORM set_config('request.jwt.claim.role','authenticated',true);
 payload:=jsonb_build_object('id',bp,'occasion',oc,'organization',org,'title','Must roll back','expected_aggregate_version',0,
  'objects',jsonb_build_array(jsonb_build_object('id',sid,'type','spot','title','Changed seat','product',product),jsonb_build_object('type','spot','title','Invalid','product',-1)));
 result:=public.update_blueprint_client_sync_v1(payload,command);
 ASSERT result->>'status'='rejected'; ASSERT public.update_blueprint_client_sync_v1(payload,command)=result;
 ASSERT (SELECT title='Original seat' FROM eshop.spots WHERE id=sid);
 ASSERT (SELECT title='Original' FROM eshop.blueprints WHERE id=bp);
 payload:=jsonb_set(payload,'{objects}',jsonb_build_array(jsonb_build_object('id',foreign_sid,'type','spot','product',product)));
 ASSERT public.update_blueprint_client_sync_v1(payload,gen_random_uuid())->>'status'='rejected';
 ASSERT (SELECT title='Foreign seat' FROM eshop.spots WHERE id=foreign_sid);
 UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=clock_timestamp()+interval '1 hour' WHERE id=sid;
 payload:=jsonb_set(payload,'{objects}','[]');
 result:=public.update_blueprint_client_sync_v1(payload,gen_random_uuid());
 ASSERT result->>'status'='rejected'; ASSERT NOT result::text LIKE '%secret%';
 ASSERT EXISTS(SELECT 1 FROM eshop.spots WHERE id=sid);
 ASSERT NOT public.get_blueprint_for_authoring_v1(bp)::text LIKE '%secret%';
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=sid;
 payload:=jsonb_set(payload,'{objects}',jsonb_build_array(jsonb_build_object('id',sid,'type','spot','product',product,'title','Saved')));
 result:=public.update_blueprint_client_sync_v1(payload,gen_random_uuid());
 ASSERT result->>'code'='200'; ASSERT result#>>'{data,aggregate_version}'='1';
 ASSERT public.update_blueprint_client_sync_v1(payload,gen_random_uuid())->>'status'='conflict';
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',oc,NULL,true) WHERE id=oc;
 -- New forms are closed in the creation transaction and returned as such.
 form:=public.create_form_client_sync_v1((SELECT link FROM public.occasions WHERE id=oc),'','Closed authoring',gen_random_uuid());
 ASSERT form#>>'{data,form,is_open}'='false'; form_id:=(form#>>'{data,form,id}')::bigint;
 result:=public.update_form_client_sync_v1(jsonb_build_object('id',form_id,'occasion',oc,'title','Changed form','expected_aggregate_version',0),gen_random_uuid());
 ASSERT result->>'code'='200';
 ASSERT (SELECT NOT is_open AND deadline_duration_seconds=604800 AND data='{"is_reminder_enabled":true}'::jsonb FROM public.forms WHERE id=form_id),'omitted settings must survive';
 ASSERT public.update_form_client_sync_v1(jsonb_build_object('id',form_id,'occasion',oc,'expected_aggregate_version',0),gen_random_uuid())->>'status'='conflict';
 ASSERT NOT public.get_form_for_authoring_v1(form_id)::text LIKE '%"key"%';
 payload:=jsonb_build_object('id',bp,'occasion',oc,'organization',org,'form',form_id,
  'expected_aggregate_version',1,'expected_form_version',0);
 ASSERT public.update_blueprint_client_sync_v1(payload,gen_random_uuid())->>'status'='conflict';
 ASSERT (SELECT blueprint IS NULL FROM public.forms WHERE id=form_id);
 payload:=jsonb_set(payload,'{expected_form_version}','1');
 ASSERT public.update_blueprint_client_sync_v1(payload,gen_random_uuid())->>'code'='200';
 ASSERT (SELECT blueprint=bp FROM public.forms WHERE id=form_id);

END $$;
