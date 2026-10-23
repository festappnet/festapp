-- test-setup: database/tests/blueprint/fixtures.sql
-- The authoring command consumes the canonical layout and typed seat changes.
DO $$
DECLARE f jsonb:=public.blueprint_test_fixture_internal(); foreign_fixture jsonb;
 actor uuid:=(f->>'actor')::uuid; oc bigint:=(f->>'occasion')::bigint; bp bigint:=(f->>'blueprint')::bigint;
 payload jsonb; original jsonb; result jsonb; command uuid:=gen_random_uuid(); sid bigint;
 form jsonb; form_id bigint;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 original:=f->'request';
 payload:=jsonb_set(original,'{seatChanges,1,productId}','-1');
 result:=public.update_blueprint_client_sync_v1(payload,command);
 ASSERT result->>'status'='rejected',result::text;
 ASSERT public.update_blueprint_client_sync_v1(payload,command)=result;
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=bp),'rejected aggregate leaves no partial seats';
 ASSERT (SELECT layout IS NULL FROM eshop.blueprints WHERE id=bp);
 foreign_fixture:=public.blueprint_test_fixture_internal();
 INSERT INTO eshop.spots(occasion,blueprint,title) VALUES((foreign_fixture->>'occasion')::bigint,(foreign_fixture->>'blueprint')::bigint,'Foreign seat') RETURNING id INTO sid;
 payload:=jsonb_set(original,'{seatChanges,0,spotId}',to_jsonb(sid));
 ASSERT public.update_blueprint_client_sync_v1(payload,gen_random_uuid())->>'status'='rejected';
 ASSERT (SELECT title='Foreign seat' FROM eshop.spots WHERE id=sid);
 result:=public.update_blueprint_client_sync_v1(original,gen_random_uuid());
 ASSERT result->>'status'='applied',result::text;
 ASSERT result#>>'{data,layout_revision}'='1';
 ASSERT public.update_blueprint_client_sync_v1(original,gen_random_uuid())->>'status'='rejected','stale revision must reject';
 SELECT spot INTO sid FROM eshop.blueprint_seat_bindings WHERE blueprint=bp ORDER BY spot LIMIT 1;
 UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=clock_timestamp()+interval '1 hour' WHERE id=sid;
 payload:=original||jsonb_build_object('expected_layout_revision',1);
 payload:=jsonb_set(payload,'{seatChanges}',jsonb_build_array(jsonb_build_object('nodeId',(SELECT node_id FROM eshop.blueprint_seat_bindings WHERE spot=sid),'spotId',sid,'operation','delete')));
 payload:=jsonb_set(payload,'{layout,nodes}',(SELECT jsonb_agg(n) FROM jsonb_array_elements(original#>'{layout,nodes}') n WHERE n->>'id'<>(SELECT node_id::text FROM eshop.blueprint_seat_bindings WHERE spot=sid)));
 result:=public.update_blueprint_client_sync_v1(payload,gen_random_uuid());
 ASSERT result->>'status'='rejected',result::text;
 ASSERT NOT result::text LIKE '%secret%';
 ASSERT EXISTS(SELECT 1 FROM eshop.spots WHERE id=sid);
 ASSERT NOT public.get_blueprint_for_authoring_v1(bp)::text LIKE '%secret%';
 form:=public.create_form_client_sync_v1((SELECT link FROM public.occasions WHERE id=oc),'','Closed authoring',gen_random_uuid());
 ASSERT form#>>'{data,form,is_open}'='false',form::text;
 form_id:=(form#>>'{data,form,id}')::bigint;
 result:=public.update_form_client_sync_v1(jsonb_build_object('id',form_id,'occasion',oc,'title','Changed form','blueprint',bp,'expected_aggregate_version',0),gen_random_uuid());
 ASSERT result->>'code'='200',result::text;
 ASSERT (SELECT NOT is_open AND blueprint=bp AND deadline_duration_seconds=604800 AND data='{"is_reminder_enabled":true}'::jsonb FROM public.forms WHERE id=form_id),'omitted settings survive canonical form association';
 ASSERT public.update_form_client_sync_v1(jsonb_build_object('id',form_id,'occasion',oc,'expected_aggregate_version',0),gen_random_uuid())->>'status'='conflict';
 ASSERT NOT public.get_form_for_authoring_v1(form_id)::text LIKE '%"key"%';
END $$;
