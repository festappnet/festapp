BEGIN;
DO $$
DECLARE org bigint; oc bigint; f bigint; at_time timestamptz:=clock_timestamp(); c jsonb; n bigint; event_times timestamptz[]; oid bigint; tid bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Availability test') RETURNING id INTO org;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Availability',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.forms(occasion,title,is_open,data,participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds) VALUES(oc,'Entry',true,jsonb_build_object('schedule',jsonb_build_object('start_time',at_time+interval '1 hour','end_time',at_time+interval '2 hours')),1,true,3600) RETURNING id INTO f;
 INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence) VALUES(oc,f,'ordered','1A2C3E4F5G',1) RETURNING id INTO oid;
 INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,tid);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,at_time-interval '1 hour');
 PERFORM public.notification_center_form_availability_internal(f,at_time,NULL,true);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),0::bigint,'silent create baseline');
 PERFORM assert_eq(public.get_form_registration_mode_internal(f,at_time),'closed','before start');
 PERFORM assert_eq(public.get_form_registration_mode_internal(f,at_time+interval '1 hour'),'waitlist','start inclusive and capacity separate');
 PERFORM assert_eq(public.get_form_registration_mode_internal(f,at_time+interval '2 hours'),'waitlist','end inclusive');
 PERFORM assert_eq(public.get_form_registration_mode_internal(f,at_time+interval '2 hours 1 microsecond'),'closed','after end');
 PERFORM public.notification_center_form_availability_internal(f,at_time+interval '3 hours',NULL);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),2::bigint,'outage replays start and end');
 SELECT array_agg(occurred_at ORDER BY occurred_at) INTO event_times FROM public.notification_center_events WHERE organization=org;
 PERFORM assert_eq(event_times,ARRAY[at_time+interval '1 hour',at_time+interval '2 hours'],'original configured times');
 PERFORM public.notification_center_form_availability_internal(f,at_time+interval '3 hours',NULL);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),2::bigint,'retry emits nothing');
 UPDATE public.forms SET is_open=false WHERE id=f;
 PERFORM public.notification_center_form_availability_internal(f,at_time+interval '3 hours',NULL);
 UPDATE public.forms SET is_open=true WHERE id=f;
 PERFORM public.notification_center_form_availability_internal(f,at_time+interval '3 hours',NULL);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),2::bigint,'manual reopen after end emits no false opening');
 UPDATE public.forms SET data='{}' WHERE id=f;
 PERFORM public.notification_center_form_availability_internal(f,at_time+interval '3 hours',NULL);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='form_opened'),2::bigint,'schedule removal actually opens');
 BEGIN
  UPDATE public.forms SET is_open=false WHERE id=f;
  PERFORM public.notification_center_form_availability_internal(f,at_time+interval '3 hours',NULL);
  RAISE EXCEPTION 'rollback';
 EXCEPTION WHEN raise_exception THEN NULL; END;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),3::bigint,'rollback removes transition and serial');
 UPDATE public.forms SET is_open=false WHERE id=f;
 PERFORM public.notification_center_form_availability_internal(f,at_time+interval '3 hours',NULL);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),4::bigint,'retry after rollback publishes once');
 -- Same normalized precedence and null behavior as the original SQL expression.
 FOR c IN SELECT value FROM jsonb_array_elements(jsonb_build_array('{}'::jsonb,
  jsonb_build_object('start_time',at_time+interval '1 hour'),
  jsonb_build_object('schedule',jsonb_build_object('start_time',''),'start_time',at_time+interval '1 hour'),
  jsonb_build_object('schedule',jsonb_build_object('start_time',at_time+interval '2 hours','end_time',at_time+interval '1 hour')))) LOOP
  UPDATE public.forms SET data=c,is_open=true,participant_capacity=NULL,waitlist_enabled=false WHERE id=f;
  c:=public.get_effective_form_data(f);
  PERFORM assert_eq(public.get_form_registration_mode_internal(f,at_time),
   CASE WHEN at_time<nullif(coalesce(c#>>'{schedule,start_time}',c->>'start_time'),'')::timestamptz OR at_time>nullif(coalesce(c#>>'{schedule,end_time}',c->>'end_time'),'')::timestamptz THEN 'closed' ELSE 'regular' END,'legacy temporal parity');
 END LOOP;
 SELECT count(*) INTO n FROM public.notification_center_events WHERE organization=org;
 PERFORM public.initialize_notification_center_internal(org);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),n,'repeat initialization stays silent');
 PERFORM assert_eq(to_regprocedure('public.set_notification_center_activation(bigint,boolean,text)'),NULL::regprocedure,'retired activation setter is not resurrected');
END $$;
ROLLBACK;
