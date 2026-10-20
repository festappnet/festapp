BEGIN;
DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; stale jsonb;
BEGIN
 PERFORM public.create_user_for_test('layout-fence-editor','layout-fence-editor@example.invalid');
 actor:=public.get_user_id('layout-fence-editor');
 INSERT INTO public.organizations(title,data) VALUES('Layout fence','{"IS_APP_SUPPORTED":true}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Layout fence',org) RETURNING id INTO un;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.unit_users(unit,"user",is_editor,is_manager) VALUES(un,actor,true,true);
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time,features,data)
 VALUES('Original',gen_random_uuid()::text,org,un,now(),now()+interval '1 day',
 '[{"code":"ticket","is_enabled":true,"background":"https://img.festapp.net/old.jpg","ticket_type":"wide"},{"code":"form","is_enabled":true}]','{"keep":true}') RETURNING id INTO oc;
 SELECT jsonb_build_object('id',id,'title','Stale title','features',features,'data',data) INTO stale FROM public.occasions WHERE id=oc;
 PERFORM set_config('festapp.test.occasion',oc::text,true);
 PERFORM set_config('festapp.test.unit',un::text,true);
 PERFORM set_config('festapp.test.organization',org::text,true);
 PERFORM set_config('festapp.test.stale',stale::text,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
END $$;
SET LOCAL ROLE authenticated;
DO $$
DECLARE oc bigint:=current_setting('festapp.test.occasion')::bigint;
 stale jsonb:=current_setting('festapp.test.stale')::jsonb;
 current_doc jsonb; before_json jsonb; after_json jsonb; result jsonb; name text;
BEGIN
 ASSERT (public.get_ticket_layout_write_contract_v1()->>'ready')::boolean;
 result:=public.save_occasion_client_sync_v1(oc,gen_random_uuid(),0,
  jsonb_build_object('id',oc,'title','New title','data','{"keep":true}'::jsonb,'features',
   '[{"code":"ticket","is_enabled":true,"background":"https://img.festapp.net/current.jpg","ticket_type":"named"},{"code":"form","is_enabled":true}]'::jsonb));
 ASSERT result->>'status'='applied';
 before_json:=public.get_ticket_layout_for_authoring_v1(oc);
 FOREACH name IN ARRAY ARRAY['update_occasion','update_occasion_203','update_occasion_182'] LOOP
  BEGIN
   EXECUTE format('SELECT public.%I($1)',name) USING stale;
   RAISE EXCEPTION 'stale artwork was accepted by %',name;
  EXCEPTION WHEN serialization_failure THEN
   ASSERT SQLERRM='ticket_layout_editor_upgrade_required';
  END;
  after_json:=public.get_ticket_layout_for_authoring_v1(oc);
  ASSERT before_json=after_json,'rejected facade advanced or changed the aggregate';
 END LOOP;
 BEGIN
  PERFORM public.update_occasion(stale||'{"features":[]}'::jsonb);
  RAISE EXCEPTION 'omission cleared current appearance';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 BEGIN
  PERFORM public.update_occasion(stale||'{"ticket_layout_change":{"expected":null,"next":{}}}'::jsonb);
  RAISE EXCEPTION 'explicit envelope bypassed original-version requirement';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 -- Legacy settings still work when the appearance snapshot is current.
 current_doc:=jsonb_build_object('id',oc,'data','{"keep":true}'::jsonb,'features',
  result#>'{data,occasion,features}');
 FOREACH name IN ARRAY ARRAY['update_occasion','update_occasion_203','update_occasion_182'] LOOP
  EXECUTE format('SELECT public.%I($1)',name) USING current_doc||jsonb_build_object('title','Settings via '||name);
 END LOOP;
 after_json:=public.get_ticket_layout_for_authoring_v1(oc);
 ASSERT after_json->'appearance'=before_json->'appearance';
 ASSERT (after_json->>'aggregate_version')::bigint=4;
 -- Creating a new occasion through each released signature still works.
 FOREACH name IN ARRAY ARRAY['update_occasion','update_occasion_203','update_occasion_182'] LOOP
  EXECUTE format('SELECT public.%I($1)',name) USING jsonb_build_object('title','Created via '||name,
   'link',gen_random_uuid()::text,'unit',current_setting('festapp.test.unit')::bigint,
   'organization',current_setting('festapp.test.organization')::bigint,
   'start_time',now(),'end_time',now()+interval '1 day','features','[]'::jsonb,'data','{}'::jsonb);
 END LOOP;
 ASSERT (public.get_ticket_layout_write_contract_v1()->>'ready')::boolean;
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.get_ticket_layout_write_contract_v1();
  RAISE EXCEPTION 'anonymous identity read the authenticated capability';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$
DECLARE actor uuid:=public.get_user_id('layout-fence-editor'); original text;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 GRANT UPDATE(features) ON public.occasions TO authenticated;
 ASSERT NOT (public.get_ticket_layout_write_contract_v1()->>'ready')::boolean,'column grant bypass was not detected';
 REVOKE UPDATE(features) ON public.occasions FROM authenticated;
 GRANT EXECUTE ON FUNCTION public.update_occasion_internal_v1(jsonb) TO authenticated;
 ASSERT NOT (public.get_ticket_layout_write_contract_v1()->>'ready')::boolean,'private writer grant bypass was not detected';
 REVOKE EXECUTE ON FUNCTION public.update_occasion_internal_v1(jsonb) FROM authenticated;
 SELECT pg_get_functiondef('public.update_occasion_182(jsonb)'::regprocedure) INTO original;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.update_occasion_182(input_data jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $drift$ BEGIN NULL; END $drift$';
 ASSERT NOT (public.get_ticket_layout_write_contract_v1()->>'ready')::boolean,'effective body drift was not detected';
 EXECUTE original;
 ASSERT (public.get_ticket_layout_write_contract_v1()->>'ready')::boolean,'restored release contract did not recover';
END $$;
ROLLBACK;
