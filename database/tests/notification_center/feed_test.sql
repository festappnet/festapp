BEGIN;
DO $$
DECLARE org bigint; oc bigint; oc2 bigint; viewer uuid:=gen_random_uuid(); result jsonb; page jsonb; cursor jsonb;
 ids uuid[]:='{}'; event_id uuid; n integer:=0; before_read bigint; timestamp_at timestamptz:=clock_timestamp();
BEGIN
 INSERT INTO public.organizations(title) VALUES('Flat feed test') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer);
 INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Same title',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Same title',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc2;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true),(oc2,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,timestamp_at-interval '1 day');
 FOR i IN 1..13 LOOP
  event_id:=public.notification_center_publish_internal(org,oc,'order_created','feed:'||i,'{}',NULL,timestamp_at);
  ids:=array_append(ids,event_id);
 END LOOP;
 PERFORM public.notification_center_publish_internal(org,oc2,'form_closed','second','{}',NULL,timestamp_at-interval '1 hour');
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 PERFORM assert_true((public.get_notification_center_badge(org)->>'feedSupported')::boolean,'read-only capability');
 result:=public.open_notification_center(org,oc,5);
 PERFORM assert_eq(jsonb_array_length(result->'feedItems'),5,'item page limit');
 PERFORM assert_eq(jsonb_array_length(result->'groups'),2,'legacy groups remain over same snapshot');
 before_read:=(SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer);
 cursor:=NULL;
 LOOP
  page:=public.get_notification_center_feed(org,oc,(result->>'snapshot')::bigint,cursor,5);
  n:=n+jsonb_array_length(page->'items');cursor:=page->'nextCursor';EXIT WHEN cursor='null'::jsonb;
 END LOOP;
 PERFORM assert_eq(n,14,'no sixth-item hole, same names keep distinct IDs');
 PERFORM assert_eq((SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer),before_read,'pagination does not ack');
 BEGIN
  PERFORM public.get_notification_center_feed(org,oc2,(result->>'snapshot')::bigint,result->'feedNextCursor',5);
  RAISE EXCEPTION 'cross context cursor accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.get_notification_center_feed(org,oc,(result->>'snapshot')::bigint,'"garbage"',5);
  RAISE EXCEPTION 'malformed cursor accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 -- A new revision is one row in the next snapshot, never duplicated in history.
 UPDATE public.notification_center_events SET attention_revision=attention_revision+1 WHERE id=ids[1];
 PERFORM public.notification_center_capture_recipients_internal(ids[1],NULL); PERFORM public.project_notification_center(500);
 PERFORM assert_eq(jsonb_array_length(public.get_notification_center_feed(org,oc,NULL,NULL,100)->'items'),14,'latest revision only');
 PERFORM public.notification_center_publish_internal(org,oc,'form_opened','late-old','{}',NULL,timestamp_at-interval '2 hours');
 PERFORM public.project_notification_center(500);
 PERFORM assert_eq(jsonb_array_length(public.get_notification_center_feed(org,oc,(result->>'snapshot')::bigint,NULL,100)->'items'),14,'snapshot excludes later delivery of older event');
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=oc AND "user"=viewer;
 PERFORM assert_eq(jsonb_array_length(public.get_notification_center_feed(org,NULL,(result->>'snapshot')::bigint,NULL,100)->'items'),1,'revocation rechecked before DTO');
 PERFORM assert_false(has_function_privilege('authenticated','public.notification_center_visible_internal(bigint,bigint,bigint)','execute'),'selector stays internal');
END $$;
ROLLBACK;
