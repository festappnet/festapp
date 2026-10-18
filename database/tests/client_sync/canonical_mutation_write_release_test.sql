DO $$
DECLARE o bigint; other_o bigint; other_org bigint; other_unit bigint; actor uuid; organization_id bigint; denied boolean; result jsonb;
 command_id uuid:=gen_random_uuid(); dto jsonb; signature text; invocation text;
BEGIN
 PERFORM create_user_for_test('canonical_release_actor','canonical_release_actor@test.local');
 actor:=get_user_id('canonical_release_actor');
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open)
 SELECT organization,id,'Release gate',gen_random_uuid()::text,now(),now()+interval '1 day',true
 FROM public.units LIMIT 1 RETURNING id,organization INTO o,organization_id;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_approved)
 VALUES(o,actor,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.method','POST',true);
 INSERT INTO public.organizations(title) VALUES('Other global release organization') RETURNING id INTO other_org;
 INSERT INTO public.units(organization,title) VALUES(other_org,'Other global release unit') RETURNING id INTO other_unit;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open)
 VALUES(other_org,other_unit,'Other global release',gen_random_uuid()::text,now(),now()+interval '1 day',true) RETURNING id INTO other_o;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_approved)
 VALUES(other_o,actor,true,true,true);
 INSERT INTO public.canonical_mutation_write_release_gate(singleton,paused,minimum_build) VALUES(true,false,620);
 -- The same typed owner fence covers ordinary REST and GraphQL execution.
 FOREACH invocation IN ARRAY ARRAY[
  format('public.save_user_group_client_sync_v1(%s,NULL,NULL,NULL)',o),
  format('public.delete_user_group_client_sync_v1(%s,NULL,NULL,NULL)',o),
  format('public.replace_group_assignments_client_sync_v1(%s,NULL,NULL)',o),
  format('public.save_activity_draft_client_sync_v1(%s,NULL,NULL,NULL,NULL)',o),
  format('public.discard_activity_draft_client_sync_v1(%s,NULL,NULL)',o),
  format('public.publish_activities_client_sync_v1(%s,NULL,NULL,NULL,NULL,NULL)',o),
  format('public.move_place_client_sync_v1(%s,NULL,NULL,NULL,NULL,NULL)',o),
  format('public.save_place_client_sync_v1(%s,NULL,NULL,NULL)',o),
  format('public.delete_place_client_sync_v1(%s,NULL,NULL,NULL)',o)
 ] LOOP
  denied:=false;
  BEGIN EXECUTE 'SELECT '||invocation; EXCEPTION WHEN insufficient_privilege THEN
   denied:=SQLERRM='canonical editor requires an enabled current release'; END;
  PERFORM assert_true(denied,'all nine owners deny an old unidentified request before mutation');
 END LOOP;
 -- Client GUCs are not server policy authority.
 PERFORM set_config('festapp.canonical_mutation_write_gate','{"paused":false,"minimumBuild":1}',true);
 FOREACH signature IN ARRAY ARRAY['{}','{"x-client-info":"festapp/0.20.134+618/web"}',
  '{"x-client-info":"festapp/0.20.136+620/web forged"}',
  '{"x-client-info":"festapp/0.20.136+620/unrecognized"}'] LOOP
  PERFORM set_config('request.headers',signature,true);denied:=false;
  BEGIN PERFORM public.assert_canonical_mutation_write_release_internal_v1(o);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  PERFORM assert_true(denied,'missing old malformed and unknown build metadata denied');
 END LOOP;
 PERFORM set_config('request.headers','{"x-client-info":"festapp/0.20.136+620/web"}',true);
 UPDATE public.canonical_mutation_write_release_gate SET paused=true;
 denied:=false;BEGIN PERFORM public.assert_canonical_mutation_write_release_internal_v1(o);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'maintenance pause denies even current builds');
 UPDATE public.canonical_mutation_write_release_gate SET paused=false;
 denied:=false;BEGIN PERFORM public.assert_canonical_mutation_write_release_internal_v1(-1);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'unknown occasion cannot write');
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(other_o);
 dto:=jsonb_build_object('title','Current client','participants','[]'::jsonb);
 SET LOCAL ROLE authenticated;
 denied:=false;BEGIN UPDATE public.canonical_mutation_write_release_gate SET minimum_build=1;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM assert_true(denied,'client cannot alter protected operational policy');
 result:=public.save_user_group_client_sync_v1(o,command_id,NULL,dto);
 PERFORM assert_eq(result->>'status','applied','current authorized editor uses canonical owner');
 PERFORM assert_eq(public.save_user_group_client_sync_v1(o,command_id,NULL,dto),result,'current editor replay retains one receipt');
 result:=public.save_user_group_client_sync_v1(other_o,gen_random_uuid(),NULL,dto);
 PERFORM assert_eq(result->>'status','applied','same current client writes in another organization without activation');
 RESET ROLE;
 UPDATE public.occasion_users SET is_editor=false,is_editor_view=false WHERE occasion=other_o AND "user"=actor;
 SET LOCAL ROLE authenticated;
 denied:=false;BEGIN PERFORM public.save_user_group_client_sync_v1(other_o,gen_random_uuid(),NULL,dto);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'global release eligibility preserves object-derived permissions');
 RESET ROLE;
 PERFORM set_config('request.headers','{}',true);
 denied:=false;BEGIN PERFORM public.save_user_group_client_sync_v1(o,command_id,NULL,dto);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'release fence also applies to receipt replay');
 PERFORM set_config('request.headers','{"x-client-info":"festapp/0.20.136+620/web"}',true);
 UPDATE public.occasion_users SET is_editor=false,is_editor_view=false WHERE occasion=o AND "user"=actor;
 denied:=false;BEGIN PERFORM public.save_user_group_client_sync_v1(o,command_id,NULL,dto);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'declared build does not restore revoked domain authority');
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.assert_canonical_mutation_write_release_internal_v1(bigint)','EXECUTE'),'private release policy helper is not a public RPC');
 denied:=false;BEGIN UPDATE public.canonical_mutation_write_release_gate SET minimum_build=0;
 EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM assert_true(denied,'invalid minimum build cannot activate');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.canonical_mutation_write_release_gate'::regclass AND attname='organization_ids' AND NOT attisdropped),'no tenant-specific release allowlist remains');
 PERFORM set_config('request.method','',true);
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(o);
END $$;
