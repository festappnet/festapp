-- Extends tenant.sql only in the task-owned disposable local E2E database.
DO $$
DECLARE oc bigint; f bigint; fk uuid; product bigint; response jsonb; preview uuid; actor uuid; oid bigint; schedule_at timestamptz:=clock_timestamp();
BEGIN
 IF (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization' THEN RAISE EXCEPTION 'Synthetic tenant required'; END IF;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('festapp.email_wake','scheduled',true);
 PERFORM public.create_user_in_organization_with_data_pure(1,'bujnmi@gmail.com','test','{"name":"Local","surname":"Preview"}');
 SELECT id INTO preview FROM public.user_info WHERE organization=1 AND email_readonly='bujnmi@gmail.com';
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(1,preview,true);
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) VALUES(1,preview,true,true,true);
 SELECT id,key,occasion INTO f,fk,oc FROM public.forms WHERE link='notification-center-e2e';
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor,is_editor_view,is_approved) VALUES(oc,preview,true,true,true,true,true);
 SELECT id INTO actor FROM public.user_info WHERE email_readonly='t@t.com';
 SELECT p.id INTO product FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type WHERE pt.occasion=oc AND pt.title='Notification center admission';
 PERFORM set_config('request.jwt.claim.sub','',true);
 FOR i IN 8..35 LOOP
  response:=public.create_ticket_order_internal_v1(jsonb_build_object('form',fk,'email','notification-customer-'||i||'@example.invalid','ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product))))));
  IF response->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Feed checkout failed: %',response; END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 response:=public.update_form_client_sync_v1(jsonb_build_object('id',f,'occasion',oc,'is_open',false),gen_random_uuid());
 IF response#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Close failed: %',response; END IF;
 response:=public.update_form_client_sync_v1(jsonb_build_object('id',f,'occasion',oc,'is_open',true),gen_random_uuid());
 IF response#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Open failed: %',response; END IF;
 -- Prepare real due boundaries; maintenance is invoked later, without admin page visits.
 response:=public.update_form_client_sync_v1(jsonb_build_object('id',f,'occasion',oc,'data',jsonb_build_object('schedule',jsonb_build_object('start_time',schedule_at+interval '15 seconds','end_time',schedule_at+interval '30 seconds'))),gen_random_uuid());
 IF response#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Schedule failed: %',response; END IF;
 PERFORM public.project_notification_center(500);
END $$;
NOTIFY pgrst,'reload schema';
