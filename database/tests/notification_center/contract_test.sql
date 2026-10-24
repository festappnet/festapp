BEGIN;
DO $$
DECLARE org bigint; other_org bigint; oc bigint; oc2 bigint; outsider uuid:=gen_random_uuid(); editor uuid:=gen_random_uuid(); author uuid:=gen_random_uuid();
 e uuid; result jsonb; n bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Notification contract') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Foreign notification tenant') RETURNING id INTO other_org;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'First',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Second',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc2;
 INSERT INTO auth.users(id) VALUES(editor),(author),(outsider);
 INSERT INTO public.user_info(id,organization) VALUES(editor,org),(author,org),(outsider,other_org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor_order) VALUES(oc,editor,true,true),(oc,author,true,true);
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','disabled');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),0::bigint,'disabled activation emits nothing');
 INSERT INTO public.notification_center_activation(organization,enabled) VALUES(org,true);
 e:=public.notification_center_publish_internal(org,oc,'order_created','order:1','{"orderId":1}',author);
 PERFORM assert_eq(public.notification_center_publish_internal(org,oc,'order_created','order:1','{"orderId":1}',author),e,'dedupe identity');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_recipients WHERE event_id=e),1::bigint,'verified author excluded');
 PERFORM public.project_notification_center(); PERFORM public.project_notification_center();
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE event_id=e),1::bigint,'fanout retry dedupes');
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 PERFORM assert_true((public.get_notification_center_badge(org)->>'unread')::boolean,'new event is unread');
 result:=public.open_notification_center(org,oc,1);
 PERFORM assert_eq((result->>'snapshot')::bigint,1::bigint,'snapshot captures delivery');
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'open ack persists');
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','order:2'); PERFORM public.project_notification_center();
 PERFORM assert_true((public.get_notification_center_badge(org)->>'unread')::boolean,'same group new event relights dot');
 PERFORM assert_eq(jsonb_array_length(public.get_notification_center_group(org,result#>>'{groups,0,key}',1)->'items'),1,'snapshot excludes arrivals');
 PERFORM public.set_notification_center_muted(org,oc,true);
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','order:3'); PERFORM public.project_notification_center();
 PERFORM public.set_notification_center_muted(org,oc,false); PERFORM public.project_notification_center();
 PERFORM assert_eq((SELECT last_delivery_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=editor),2::bigint,'unmute does not replay');
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=oc AND "user"=editor;
 -- Remain authorized on oc2, but no access to old oc history or counts.
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc2,editor,true);
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'revoked ACL hides badge');
 PERFORM assert_eq(jsonb_array_length(public.get_notification_center_page(org)->'groups'),0,'revoked ACL hides history');
 BEGIN PERFORM public.open_notification_center(org,oc); RAISE EXCEPTION 'bad context accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.open_notification_center(other_org); RAISE EXCEPTION 'foreign tenant accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.notification_center_publish_internal(org,oc2,'order_created','rolled-back');
  RAISE EXCEPTION 'rollback';
 EXCEPTION WHEN raise_exception THEN NULL; END;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key='rolled-back'),0::bigint,'domain rollback removes event');
 PERFORM assert_false(has_function_privilege('authenticated','public.project_notification_center(integer)','execute'),'no user projection grant');
 PERFORM assert_false(has_function_privilege('anon','public.open_notification_center(bigint,bigint,integer)','execute'),'no anonymous inbox');
 PERFORM assert_false(has_table_privilege('authenticated','public.notification_center_deliveries','select'),'no direct inbox reads');
END $$;
ROLLBACK;
