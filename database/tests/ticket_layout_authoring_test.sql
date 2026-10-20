UPDATE public.email_capacity SET paused=true,worker_url=NULL;
DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; config jsonb; result jsonb;
 layout jsonb:=$layout${"schemaVersion":3,"templates":{"named":{"page":{"width":212.5,"height":387.5},"ticketArea":{"x":6.25,"y":6.25,"width":200,"height":375},"elements":[{"id":"logo","binding":"logo","box":{"x":71.875,"y":12.5,"width":56.25,"height":56.25},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"occasionTitle","binding":"occasionTitle","box":{"x":6.25,"y":77,"width":187.5,"height":32},"visible":true,"locked":false,"style":{"fontSize":12.5,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"occasionDatePlace","binding":"occasionDatePlace","box":{"x":6.25,"y":111,"width":187.5,"height":24},"visible":true,"locked":false,"style":{"fontSize":8.75,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"orderName","binding":"orderName","box":{"x":6.25,"y":151,"width":187.5,"height":32},"visible":true,"locked":false,"style":{"fontSize":12.5,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"qr","binding":"qr","box":{"x":50,"y":206.25,"width":100,"height":100},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"ticketSymbol","binding":"ticketSymbol","box":{"x":10,"y":313,"width":180,"height":20},"visible":true,"locked":false,"style":{"fontSize":8.75,"minFontSize":6,"maxLines":1,"color":"2A2A2A","align":"center"}},{"id":"footer","binding":"footer","box":{"x":6.25,"y":348,"width":187.5,"height":20},"visible":true,"locked":false,"style":{"fontSize":6.25,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}}]}}}$layout$::jsonb; changed jsonb; baseline jsonb; cmd uuid:=gen_random_uuid();
BEGIN
 PERFORM public.create_user_for_test('narrow-layout','narrow-layout@example.invalid'); actor:=public.get_user_id('narrow-layout');
 INSERT INTO public.organizations(title,data) VALUES('Layout authoring','{"IS_APP_SUPPORTED":true}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Layout authoring',org) RETURNING id INTO un;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.unit_users(unit,"user",is_editor) VALUES(un,actor,true);
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time,features,data)
 VALUES('Preserved title',gen_random_uuid()::text,org,un,now(),now()+interval '1 day',
 jsonb_build_array(jsonb_build_object('code','ticket','is_enabled',true,'show_hidden_note',true,'layout',layout),
 '{"code":"form","is_enabled":true,"reminder_is_enabled":false}'::jsonb),'{"preserve":"settings"}') RETURNING id INTO oc;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 baseline:=public.get_ticket_layout_for_authoring_v1(oc);
 ASSERT baseline->>'aggregate_version'='0';
 ASSERT NOT baseline::text LIKE '%order_product_ticket%';
 changed:=jsonb_set(layout,'{templates,named,elements,0,box,x}','70');
 config:=jsonb_build_object('id',oc,'ticket_layout_change',jsonb_build_object('expected',layout,'next',changed,'appearance',jsonb_build_object('ticket_type','named')));
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.save_occasion_client_sync_v1(oc,cmd,0,config);
 ASSERT result->>'code'='200';
 ASSERT public.save_occasion_client_sync_v1(oc,cmd,0,config)=result;
 ASSERT public.save_occasion_client_sync_v1(oc,gen_random_uuid(),0,config)->>'status'='conflict';
 EXECUTE 'RESET ROLE';
 ASSERT (SELECT title='Preserved title' AND data='{"preserve":"settings"}'::jsonb FROM public.occasions WHERE id=oc);
 ASSERT (SELECT features#>'{1}'='{"code":"form","is_enabled":true,"reminder_is_enabled":false}'::jsonb AND features#>>'{0,show_hidden_note}'='true' AND features#>>'{0,ticket_type}'='named' FROM public.occasions WHERE id=oc);
 ASSERT NOT EXISTS(SELECT 1 FROM public.forms WHERE occasion=oc), 'layout-only save must not create forms';
 ASSERT NOT EXISTS(SELECT 1 FROM public.email_messages WHERE occasion=oc);
 BEGIN
  PERFORM public.save_occasion_client_sync_v1(oc,gen_random_uuid(),1,jsonb_build_object('id',oc,'ticket_layout_change',jsonb_build_object('expected',changed,'next',changed,'appearance','{"background":"https://untrusted.invalid/image"}'::jsonb)));
  RAISE EXCEPTION 'foreign background accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE public.unit_users SET is_editor=false WHERE unit=un AND "user"=actor;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,actor,true);
 BEGIN
  PERFORM public.save_occasion_client_sync_v1(oc,gen_random_uuid(),1,config);
  RAISE EXCEPTION 'order editor gained layout permission';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
