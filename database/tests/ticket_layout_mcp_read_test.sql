-- Ordinary-role reader boundary used by E0, entirely disposable and rolled back.
BEGIN;
DO $$
DECLARE actor uuid; outsider uuid; org bigint; other_org bigint; un bigint; oc bigint;
BEGIN
 PERFORM public.create_user_for_test('mcp-layout-editor','mcp-layout-editor@example.invalid');
 PERFORM public.create_user_for_test('mcp-layout-foreign','mcp-layout-foreign@example.invalid');
 actor:=public.get_user_id('mcp-layout-editor'); outsider:=public.get_user_id('mcp-layout-foreign');
 INSERT INTO public.organizations(title,data) VALUES('MCP fixture','{}') RETURNING id INTO org;
 INSERT INTO public.organizations(title,data) VALUES('Foreign MCP fixture','{}') RETURNING id INTO other_org;
 INSERT INTO public.units(title,organization) VALUES('MCP fixture',org) RETURNING id INTO un;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 UPDATE public.user_info SET organization=other_org WHERE id=outsider;
 INSERT INTO public.unit_users(unit,"user",is_editor) VALUES(un,actor,true);
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time,features,data)
 VALUES('Synthetic MCP fixture',gen_random_uuid()::text,org,un,now(),now()+interval '1 day',
 '[{"code":"ticket","is_enabled":true,"background":null}]','{"private_fixture":"must not escape"}') RETURNING id INTO oc;
 PERFORM set_config('festapp.test.occasion',oc::text,true);
 PERFORM set_config('festapp.test.actor',actor::text,true);
 PERFORM set_config('festapp.test.outsider',outsider::text,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
END $$;
SET LOCAL ROLE authenticated;
DO $$
DECLARE result jsonb; oc bigint:=current_setting('festapp.test.occasion')::bigint;
BEGIN
 result:=public.get_ticket_layout_for_authoring_v1(oc);
 ASSERT result->>'occasion'=oc::text;
 ASSERT result->>'schemaVersion'='3';
 ASSERT (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(result) key)=
  ARRAY['aggregate_version','appearance','images','occasion','schemaVersion'];
 ASSERT result->'images'='[]'::jsonb;
 ASSERT result->'appearance'='{"layout":null,"background":null,"ticket_type":null}'::jsonb;
 ASSERT result::text NOT LIKE '%private_fixture%';
 PERFORM set_config('request.jwt.claim.sub',current_setting('festapp.test.outsider'),true);
 BEGIN
  PERFORM public.get_ticket_layout_for_authoring_v1(oc);
  RAISE EXCEPTION 'foreign identity gained layout read';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.get_ticket_layout_for_authoring_v1(oc);
  RAISE EXCEPTION 'anonymous identity gained layout read';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
