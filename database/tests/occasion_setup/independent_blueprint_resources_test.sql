-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/functions/occasion_setup/finalize.sql
DO $$
DECLARE f jsonb; req jsonb; source jsonb; plan jsonb; payload jsonb; draft jsonb; result jsonb;
 actor uuid; unit_id bigint; source_occ bigint; source_bp bigint; new_occ bigint; new_bp bigint;
 area_id uuid:=gen_random_uuid(); draft_id uuid; command_id uuid; origin jsonb; resources_before bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal();
 actor:=(f->>'actor')::uuid; source_occ:=(f->>'occasion')::bigint; source_bp:=(f->>'blueprint')::bigint;
 SELECT unit INTO unit_id FROM public.occasions WHERE id=source_occ;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(unit_id,actor,true,true);
 UPDATE public.user_info SET organization=(SELECT organization FROM public.occasions WHERE id=source_occ) WHERE id=actor;
 UPDATE eshop.products SET price=0 WHERE id=(f->>'product')::bigint;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 req:=f->'request';
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object(
   'id',area_id,'kind','capacityArea','width',100,'height',100,
   'transform',jsonb_build_object('x',400,'y',400,'rotation',0))));
 req:=jsonb_set(req,'{textResourceIds}',(SELECT jsonb_agg(resource_id) FROM public.blueprint_text_resources WHERE occasion=source_occ));
 result:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 IF result->>'status'<>'applied' THEN RAISE EXCEPTION 'Source fixture failed: %',result; END IF;
 source:=public.get_occasion_setup_source(unit_id,source_occ);
 plan:=source#>'{blueprints,0,blueprintLayoutDraft}';
 plan:=jsonb_set(plan,'{areaBindings}',jsonb_build_array(jsonb_build_object('nodeId',area_id,'productId',f->'product','capacity',3)));
 SELECT count(*) INTO resources_before FROM public.blueprint_text_resources WHERE occasion=source_occ;
 PERFORM public.assert_true(resources_before>0,'source has real prepared number paths');
 -- Each independent selector can supply the resource origin without sourceId.
 FOR origin IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
   jsonb_build_object('blueprintSourceId',source_bp,'blueprintSourceOccasionId',source_occ),
   jsonb_build_object('blueprintSourceOccasionId',source_occ),
   jsonb_build_object('formSourceOccasionId',source_occ))) LOOP
  draft_id:=gen_random_uuid(); command_id:=gen_random_uuid();
  draft:=public.create_occasion_setup_draft(draft_id,unit_id);
  payload:=origin||jsonb_build_object('title','Independent plan resources','start',now()+interval '30 days','end',now()+interval '31 days',
    'formEnabled',true,'formDraft',(source#>'{forms,0}')-'link','blueprintMode','copy','blueprintLayoutDraft',plan,'reviewConfirmed',true);
  draft:=public.save_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,payload,5);
  PERFORM public.assert_eq((SELECT count(*)::int FROM public.blueprint_text_resources WHERE setup_draft=draft_id),0,'copy needs no editor visit to prepare draft paths');
  result:=public.finalize_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,command_id);
  new_occ:=(result#>>'{data,occasionId}')::bigint;
  SELECT blueprint INTO new_bp FROM public.forms WHERE occasion=new_occ LIMIT 1;
  PERFORM public.assert_true(new_bp IS NOT NULL AND new_bp<>source_bp,'independent plan materialized');
  PERFORM public.check_blueprint_text_resources_internal((SELECT layout FROM eshop.blueprints WHERE id=new_bp),new_occ);
  PERFORM public.assert_true(EXISTS(SELECT 1 FROM public.blueprint_text_resources WHERE occasion=new_occ),'source paths copied to destination scope');
  PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_seat_bindings WHERE blueprint=new_bp),4,'seats retained');
  PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_seat_bindings a JOIN eshop.blueprint_seat_bindings b ON a.node_id=b.node_id OR a.spot=b.spot WHERE a.blueprint=source_bp AND b.blueprint=new_bp),0,'node and spot identities remapped');
  PERFORM public.assert_eq(public.finalize_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,command_id),result,'same request replay');
 END LOOP;
 PERFORM public.assert_eq((SELECT count(*) FROM public.blueprint_text_resources WHERE occasion=source_occ),resources_before,'source resources untouched');
END $$;
