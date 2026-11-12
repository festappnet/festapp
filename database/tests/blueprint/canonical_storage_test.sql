-- test-setup: database/tests/blueprint/fixtures.sql
DO $$
DECLARE org bigint; un bigint; oc bigint; bp bigint; invalid jsonb; col text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Canonical blueprint storage') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Canonical storage unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,un,'Canonical storage',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO eshop.blueprints(occasion,organization,title) VALUES(oc,org,'New plan') RETURNING id INTO bp;
 PERFORM assert_eq((SELECT layout->'schemaVersion' FROM eshop.blueprints WHERE id=bp),'2'::jsonb,'Implicit creation is canonical');
 PERFORM assert_true((SELECT layout->'nodes'='[]'::jsonb AND objects IS NULL AND groups IS NULL AND configuration IS NULL AND background_svg IS NULL FROM eshop.blueprints WHERE id=bp),'No second stored geometry');
 FOR invalid IN SELECT v FROM jsonb_array_elements('[null,{}, {"schemaVersion":1,"nodes":[]},{"schemaVersion":"2","nodes":[]}]') v LOOP
  BEGIN
   UPDATE eshop.blueprints SET layout=nullif(invalid,'null'::jsonb) WHERE id=bp;
   RAISE EXCEPTION 'Retired or malformed layout accepted';
  EXCEPTION WHEN check_violation OR not_null_violation THEN NULL; END;
 END LOOP;
 FOREACH col IN ARRAY ARRAY['objects','groups','configuration'] LOOP
  BEGIN
   EXECUTE format('UPDATE eshop.blueprints SET %I=$1 WHERE id=$2',col) USING '[]'::jsonb,bp;
   RAISE EXCEPTION 'Retired geometry column accepted: %',col;
  EXCEPTION WHEN check_violation THEN NULL; END;
 END LOOP;
 BEGIN
  UPDATE eshop.blueprints SET background_svg='<svg/>' WHERE id=bp;
  RAISE EXCEPTION 'Retired background accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM assert_true(to_regprocedure('public.get_blueprint_editor(text)') IS NULL,'Retired editor RPC absent');
 PERFORM assert_true(to_regprocedure('public.migrate_blueprint_layout_reviewed_internal(text,text,jsonb,uuid)') IS NULL,'Runtime legacy migration API absent');
END $$;

DO $$
DECLARE f jsonb; req jsonb; r jsonb; bad jsonb; group_id uuid:=gen_random_uuid();
BEGIN
 f:=public.blueprint_test_fixture_internal(); req:=f->'request';
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 req:=jsonb_set(req,'{layout,nodes}',req#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object('id',group_id,'kind','group','width',40,'height',40,'transform',jsonb_build_object('x',500,'y',500,'rotation',0))));
 req:=jsonb_set(req,'{groupProductChanges}',jsonb_build_array(jsonb_build_object('groupNodeId',group_id,'productId',f->'product')));
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','group default setup saves');
 req:=jsonb_set(req,'{expected_layout_revision}','1');
 req:=jsonb_set(req,'{seatChanges}',(SELECT jsonb_agg(c||jsonb_build_object('spotId',b.spot)) FROM jsonb_array_elements(req->'seatChanges') c JOIN eshop.blueprint_seat_bindings b ON b.blueprint=(f->>'blueprint')::bigint AND b.node_id=(c->>'nodeId')::uuid));
 req:=jsonb_set(req,'{layout,nodes}',(SELECT jsonb_agg(n) FROM jsonb_array_elements(req#>'{layout,nodes}') n WHERE n->>'id'<>group_id::text));
 -- The existing client sends a null product tombstone for baseline groups
 -- removed from the draft, alongside the final layout without that group.
 req:=jsonb_set(req,'{groupProductChanges,0,productId}','null');
 bad:=jsonb_set(req,'{groupProductChanges,0,productId}',f->'product');
 r:=public.update_blueprint_client_sync_v1(bad,gen_random_uuid());
 PERFORM public.assert_eq(r#>>'{data,reason}','BLUEPRINT_INVALID_GROUP_PRODUCT','assigning a product to a missing group stays rejected');
 bad:=jsonb_set(req,'{groupProductChanges,0,groupNodeId}',to_jsonb(gen_random_uuid()));
 r:=public.update_blueprint_client_sync_v1(bad,gen_random_uuid());
 PERFORM public.assert_eq(r#>>'{data,reason}','BLUEPRINT_INVALID_GROUP_PRODUCT','unknown group tombstone stays rejected');
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','removed group default tombstone saves: '||r::text);
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_group_products WHERE blueprint=(f->>'blueprint')::bigint),0,'removed group default is cleaned up');
END $$;
