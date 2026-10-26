BEGIN;
DO $$
DECLARE org bigint; oc bigint; f bigint; oid bigint; tid bigint; viewer uuid:=gen_random_uuid(); result jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Presentation test') RETURNING id INTO org;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Presentation',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(viewer); INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.forms(occasion,title) VALUES(oc,'Entries') RETURNING id INTO f;
 INSERT INTO public.form_fields(form,type,data) VALUES(f,'ticket','{"max_tickets":"2"}');
 INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data) VALUES(oc,f,'ordered','1A2C3E4F5G',1,'{"name":" ","surname":"","email":" customer@example.invalid "}') RETURNING id INTO oid;
 FOR i IN 1..2 LOOP
  INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered') RETURNING id INTO tid;
  INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,tid);
 END LOOP;
 INSERT INTO public.notification_center_organizations(organization) VALUES(org);
 PERFORM public.notification_center_order_internal(oid,'order_created','created',NULL);
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 result:=public.get_notification_center_feed(org,oc);
 PERFORM assert_eq(result#>>'{items,0,data,contact,email}',' customer@example.invalid ','authorized live email is available to formatter');
 PERFORM assert_eq((result#>>'{items,0,data,count}')::int,2,'exact creation identity count');
 PERFORM assert_true((result#>>'{items,0,data,formContext,allowsMultiple}')::boolean,'configured multiple context');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND data::text LIKE '%customer@example.invalid%'),'contact absent from event log');
 UPDATE public.form_fields SET data='{"max_tickets":1}' WHERE form=f;
 UPDATE eshop.tickets SET state='storno' WHERE id=tid;
 result:=public.get_notification_center_feed(org,oc);
 PERFORM assert_eq((result#>>'{items,0,data,count}')::int,2,'later partial storno does not rewrite historical count');
 UPDATE eshop.orders SET data='{}' WHERE id=oid;
 result:=public.get_notification_center_feed(org,oc);
 PERFORM assert_true((result#>'{items,0,data,contact,email}')='null'::jsonb,'missing contact has no identifier fallback');
 -- Legacy rows lack a captured form context; hydrate only the missing fact.
 UPDATE public.form_fields SET data='{"max_tickets":2}' WHERE form=f;
 PERFORM public.notification_center_publish_internal(org,oc,'order_cancelled','legacy-single-place',
  jsonb_build_object('orderId',oid,'count',1),NULL);
 PERFORM public.project_notification_center(500);
 SELECT x INTO result FROM jsonb_array_elements(public.get_notification_center_feed(org,oc)->'items') x
  WHERE x->>'kind'='order_cancelled';
 PERFORM assert_eq((result#>>'{data,count}')::int,1,'one cancelled place stays an exact count');
 PERFORM assert_true((result#>>'{data,formContext,allowsMultiple}')::boolean,'legacy multi-place form displays even one place');
 UPDATE public.form_fields SET data='{"max_tickets":"invalid legacy metadata"}' WHERE form=f;
 PERFORM public.notification_center_order_internal(oid,'order_created','legacy-metadata',NULL);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),3::bigint,'legacy invalid metadata never breaks order publication');
END $$;
ROLLBACK;
