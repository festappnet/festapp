-- Synthetic history only, on this task's marked disposable database.
DO $$ DECLARE oc bigint; oid bigint; singleton_order bigint; singleton_form bigint; tid bigint; at timestamptz:=clock_timestamp(); context jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE project='festapp-notification-feed-e2e-20261026')
  OR (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization' THEN RAISE EXCEPTION 'Wrong synthetic environment'; END IF;
 SELECT id INTO STRICT oc FROM public.occasions WHERE link='e2e-tabs-a';
 SELECT o.id INTO STRICT oid FROM eshop.orders o JOIN public.forms f ON f.id=o.form WHERE f.link='notification-center-e2e' AND o.state='ordered' ORDER BY o.id LIMIT 1;
 UPDATE public.notification_center_organizations SET initialized_at=at-interval '100 days',collection_started_at=at-interval '100 days' WHERE organization=1;
 UPDATE public.occasions SET title='Country bál 2026' WHERE id=oc;
 UPDATE public.form_fields SET data='{"max_tickets":2}' WHERE form=(SELECT form FROM eshop.orders WHERE id=oid) AND type='ticket';
 context:=public.notification_center_order_form_context_internal((SELECT form FROM eshop.orders WHERE id=oid));
 DELETE FROM public.notification_center_events WHERE organization=1;
 DELETE FROM public.notification_center_preferences WHERE organization=1;
 FOR i IN 1..35 LOOP
  PERFORM public.notification_center_publish_internal(1,oc,CASE i%3 WHEN 0 THEN 'order_cancelled' WHEN 1 THEN 'order_created' ELSE 'waitlist_registered' END,
   'period-e2e-day:'||i,jsonb_build_object('orderId',oid,'count',1,'formContext',context),NULL,at-interval '2 days'-make_interval(mins=>i));
 END LOOP;
 FOR i IN 1..5 LOOP
  PERFORM public.notification_center_publish_internal(1,oc,'order_cancelled','period-e2e-week:'||i,
   jsonb_build_object('orderId',oid,'count',1,'formContext',context),NULL,at-interval '14 days'-make_interval(mins=>i));
 END LOOP;
 PERFORM public.notification_center_publish_internal(1,oc,'form_closed','period-e2e-form',
  '{"title":"Vstupenky","reason":"schedule_end"}',NULL,at-interval '2 days'-interval '20 minutes');
 PERFORM public.notification_center_order_internal(oid,'order_created','period-e2e-recent-multi',NULL);
 SELECT id INTO STRICT singleton_form FROM public.forms WHERE link='e2e-first-form';
 INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data)
 VALUES(oc,singleton_form,'ordered',public.generate_order_symbol(),public.next_order_sequence(oc),'{"name":"Jednotlivá","surname":"Přihláška"}') RETURNING id INTO singleton_order;
 INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(singleton_order,tid);
 PERFORM public.notification_center_order_internal(singleton_order,'order_created','period-e2e-recent-single',NULL);
 PERFORM public.project_notification_center(500);
END $$;
NOTIFY pgrst,'reload schema';
