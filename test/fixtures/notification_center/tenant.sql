-- Only the task-owned disposable notification-center E2E project.
DO $$
DECLARE oc bigint; f bigint; fk uuid; pt bigint; product bigint; organizer uuid; response jsonb;
BEGIN
 IF (SELECT title FROM public.organizations WHERE id=1) <> 'Test Organization'
    OR EXISTS (SELECT 1 FROM public.forms WHERE link='notification-center-e2e') THEN
  RAISE EXCEPTION 'Expected fresh synthetic notification fixture';
 END IF;
 SELECT id INTO oc FROM public.occasions WHERE link='e2e-tabs-a';
 IF oc IS NULL THEN RAISE EXCEPTION 'Navigation fixture required'; END IF;
 UPDATE public.occasions SET title='Notification center - a long event title for responsive administration checks' WHERE id=oc;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('festapp.email_wake','scheduled',true);
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',id,link,true) WHERE link IN ('e2e-tabs-a','e2e-tabs-b');
 PERFORM public.create_user_in_organization_with_data_pure(1,'notification-organizer@festapp.invalid','test','{"name":"Notification","surname":"Organizer"}');
 SELECT id INTO organizer FROM public.user_info WHERE email_readonly='notification-organizer@festapp.invalid';
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_approved) VALUES(oc,organizer,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',(SELECT id::text FROM public.user_info WHERE email_readonly='t@t.com'),true);
 PERFORM public.create_form(oc,'notification-center-e2e','Notification center E2E checkout');
 SELECT id,key INTO f,fk FROM public.forms WHERE link='notification-center-e2e';
 UPDATE public.forms SET participant_capacity=100,is_open=true,data='{"is_reminder_enabled":false}'::jsonb WHERE id=f;
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Notification center admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion) VALUES('Admission',pt,100,'CZK',oc) RETURNING id INTO product;
 INSERT INTO public.form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 PERFORM public.set_notification_center_activation(1,true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 FOR i IN 1..7 LOOP
  response:=public.create_ticket_order_internal_v1(jsonb_build_object('form',fk,'email','notification-customer-'||i||'@example.invalid','ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product))))));
  IF response->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'E2E checkout % failed: %',i,response; END IF;
 END LOOP;
 PERFORM public.project_notification_center(100);
END $$;
NOTIFY pgrst, 'reload schema';
