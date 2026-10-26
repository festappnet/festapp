BEGIN;
DO $$
DECLARE org bigint; un bigint; oc bigint; f bigint; editor uuid:=gen_random_uuid(); viewer uuid:=gen_random_uuid();
 cmd uuid:=gen_random_uuid(); result jsonb; input jsonb; n bigint; at_time timestamptz:=clock_timestamp(); copy_id bigint; new_form_id bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Availability save') RETURNING id INTO org;
 INSERT INTO public.units(organization,title) VALUES(org,'Unit') RETURNING id INTO un;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) VALUES(org,un,'Save',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',oc,link,true) WHERE id=oc;
 INSERT INTO auth.users(id) VALUES(editor),(viewer);
 INSERT INTO public.user_info(id,organization) VALUES(editor,org),(viewer,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor,is_editor_view)
 VALUES(oc,editor,true,true,true,true),(oc,viewer,false,true,false,true);
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 result:=public.create_form_internal_v1(oc,NULL,'Real save'); f:=(result->>'id')::bigint;
 PERFORM public.initialize_notification_center_internal(org);
 UPDATE public.notification_center_organizations SET initialized_at=at_time-interval '4 hours',collection_started_at=at_time-interval '4 hours' WHERE organization=org;
 input:=jsonb_build_object('id',f,'occasion',oc,'is_open',true);
 result:=public.update_form_client_sync_v1(input,cmd);
 PERFORM assert_eq((result#>>'{data,code}')::int,200,'actual save command success: '||result::text);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='form_opened'),1::bigint,'successful save publishes');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_recipients r JOIN public.notification_center_events e ON e.id=r.event_id WHERE e.organization=org AND recipient=editor),0::bigint,'verified author suppressed');
 PERFORM public.update_form_client_sync_v1(input,cmd);
 PERFORM public.update_form_client_sync_v1(input,gen_random_uuid());
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='form_opened'),1::bigint,'command replay and no-op quiet');
 result:=public.update_form_internal_v1(jsonb_build_object('id',f,'occasion',oc,'is_open',false,'deadline_duration_seconds',-1));
 PERFORM assert_true((result->>'code')::int<>200,'save failure is real');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='form_closed'),0::bigint,'failed save does not publish');
 PERFORM assert_true((SELECT is_open FROM public.forms WHERE id=f),'failed save rolls back domain');
 -- A late save drains OLD boundaries before the new schedule can erase them.
 UPDATE public.forms SET data=jsonb_build_object('schedule',jsonb_build_object('start_time',at_time-interval '2 hours','end_time',at_time-interval '1 hour')) WHERE id=f;
 PERFORM public.notification_center_form_availability_internal(f,at_time-interval '3 hours',NULL,true);
 -- Rebaseline clamps a caller's older timestamp, so set up an actual historical baseline explicitly.
 UPDATE public.notification_center_source_state SET observed_at=at_time-interval '3 hours',state=public.get_form_availability_snapshot_internal(f,at_time-interval '3 hours')||jsonb_build_object('formId',f,'title','Real save'),next_evaluation_at=at_time-interval '2 hours' WHERE organization=org AND source_key='form-availability:'||f;
 result:=public.update_form_client_sync_v1(jsonb_build_object('id',f,'occasion',oc,'data','{}'::jsonb),gen_random_uuid());
 PERFORM assert_eq((result#>>'{data,code}')::int,200,'schedule change succeeds');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),4::bigint,'old start/end plus new open preserved');
 SELECT count(*) INTO n FROM public.notification_center_events WHERE organization=org;
 copy_id:=public.duplicate_form_to_occasion_internal_v1(f,(SELECT link FROM public.occasions WHERE id=oc),'en');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),n,'copy silent baseline');
 PERFORM public.delete_form_internal_v1(copy_id);
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_source_state WHERE organization=org AND source_key='form-availability:'||copy_id),'delete retires due state');
 SELECT count(*) INTO n FROM public.notification_center_events WHERE organization=org;
 result:=public.create_form_internal_v1(oc,NULL,'Wizard creation');new_form_id:=(result->>'id')::bigint;
 result:=public.update_form_internal_v1(jsonb_build_object('id',new_form_id,'occasion',oc,'is_open',true));
 PERFORM assert_eq((result->>'code')::int,200,'wizard saves newly created form');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),n,'same-transaction wizard authoring stays a silent creation baseline');
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 result:=public.open_notification_center(org,oc);
 PERFORM assert_true(jsonb_array_length(result->'feedItems')>=4,'save to personal projection to feed');
END $$;
ROLLBACK;
