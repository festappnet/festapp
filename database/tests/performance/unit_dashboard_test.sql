DO $$
DECLARE actor uuid; outsider uuid; org bigint; target_unit bigint; other_unit bigint; event_id bigint; d jsonb; r jsonb; ctx jsonb;
BEGIN
 PERFORM create_user_for_test('dashboard_manager','dashboard-manager@test.local');
 PERFORM create_user_for_test('dashboard_outsider','dashboard-outsider@test.local');
 actor:=get_user_id('dashboard_manager'); outsider:=get_user_id('dashboard_outsider');
 SELECT organization INTO org FROM public.user_info WHERE id=actor;
 INSERT INTO public.units(organization,title) VALUES(org,'Dashboard performance') RETURNING id INTO target_unit;
 INSERT INTO public.units(organization,title) VALUES(org,'Unrelated unit') RETURNING id INTO other_unit;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(target_unit,actor,true);
 INSERT INTO public.occasions(unit,organization,title,link,start_time,end_time,features,data)
 VALUES(target_unit,org,'Scoped dashboard event','dashboard-perf-event',now()+interval '1 day',now()+interval '2 days',
  '[{"code":"ticket","is_enabled":true,"ticketLayout":{"large":"not part of a card"}}]',
  '{"timezone":"Europe/Prague"}') RETURNING id INTO event_id;
 INSERT INTO public.occasions(unit,organization,title,link,start_time,end_time)
 VALUES(other_unit,org,'Other unit event','dashboard-perf-other',now(),now());
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 d:=public.get_unit_occasion_dashboard_internal(target_unit);
 PERFORM assert_eq((d->>'unit_id')::bigint,target_unit,'Snapshot stays scoped to one unit');
 PERFORM assert_eq(jsonb_array_length(d->'occasions'),1,'Only the requested unit is aggregated');
 PERFORM assert_eq((d#>>'{occasions,0,id}')::bigint,event_id,'Catalogue identity retained');
 PERFORM assert_true(d#>'{occasions,0,features,0,ticketLayout}' IS NULL,'Card payload excludes ticket layout data');
 PERFORM assert_eq(d#>>'{occasions,0,features,0,code}','ticket','Feature identity retained');
 PERFORM assert_true(d ?& ARRAY['drafts','app_landing','demo_catalog'],'One snapshot owns all screen sections');
 EXECUTE 'SET LOCAL ROLE authenticated';
 r:=public.get_unit_edit_data(target_unit);
 PERFORM assert_eq(r->'occasions',d->'occasions','Refresh uses the same projection');
 ctx:=public.get_app_config_v219(jsonb_build_object('organization',org,'unit_id',target_unit,'platform','test'));
 PERFORM assert_eq(ctx->>'code','200','Existing context still authorizes the unit');
 PERFORM assert_eq(ctx->'unit_dashboard'->'occasions',d->'occasions','Initial context contains the same catalogue without another RPC');
 BEGIN
  PERFORM public.get_unit_occasion_dashboard_internal(target_unit);
  RAISE EXCEPTION 'Private projection exposed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN
  PERFORM public.get_unit_edit_data(target_unit);
  RAISE EXCEPTION 'Unrelated actor read dashboard';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Unrelated actor read dashboard' THEN RAISE; END IF;
 END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_true(NOT has_function_privilege('anon','public.get_unit_edit_data(bigint)','EXECUTE'),'Anonymous dashboard read is denied');
END $$;
