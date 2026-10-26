-- Run while the headless local panel holds its earlier snapshot.
DO $$
DECLARE f bigint; oc bigint; fk uuid; actor uuid; product bigint; response jsonb; token text; oid bigint; opened_before bigint;
BEGIN
 IF (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization' THEN RAISE EXCEPTION 'Synthetic tenant required'; END IF;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('festapp.email_wake','scheduled',true);
 SELECT id,key,occasion INTO f,fk,oc FROM public.forms WHERE link='notification-center-e2e';
 SELECT id INTO actor FROM public.user_info WHERE email_readonly='t@t.com';
 SELECT p.id INTO product FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type WHERE pt.occasion=oc AND pt.title='Notification center admission';
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 response:=public.update_form_client_sync_v1(jsonb_build_object('id',f,'occasion',oc,'data','{}'::jsonb),gen_random_uuid());
 IF response#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Open failed: %',response; END IF;
 UPDATE public.form_fields SET data='{"max_tickets":2}' WHERE form=f AND type='ticket';
 PERFORM set_config('request.jwt.claim.sub','',true);
 response:=public.create_ticket_order_internal_v1(jsonb_build_object('form',fk,'email','two-tickets@example.invalid','ticket',jsonb_build_array(
  jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product))),
  jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product))))));
 IF response->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Two tickets failed: %',response; END IF;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 response:=public.update_form_client_sync_v1(jsonb_build_object('id',f,'occasion',oc,'participant_capacity',37,'waitlist_enabled',true,'waitlist_offer_duration_seconds',3600),gen_random_uuid());
 IF response#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Waitlist setup failed: %',response; END IF;
 PERFORM set_config('request.jwt.claim.sub','',true);
 token:=encode(extensions.gen_random_bytes(32),'hex');
 response:=public.execute_waitlist_command_client_sync_v1('register',jsonb_build_object('form',fk,'email','waiting@example.invalid','tickets','[{"fields":[]}]'::jsonb),gen_random_uuid(),gen_random_uuid(),NULL,
  jsonb_build_array(jsonb_build_object('recipient','waiting@example.invalid','templateCode','waitlist_confirmation','tokenHash',encode(extensions.digest(token,'sha256'),'hex'),'contentHash',repeat('f',64),'sealed',jsonb_build_object('ciphertext','sealed-local-test-double'))));
 IF response#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Waitlist registration failed: %',response; END IF;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 SELECT min(id) INTO oid FROM eshop.orders WHERE form=f AND state='ordered';
 SELECT count(*) INTO opened_before FROM public.notification_center_events WHERE organization=1 AND kind='form_opened';
 PERFORM public.cancel_order_domain_internal_v1(oid,false);
 IF (SELECT count(*) FROM public.notification_center_events WHERE organization=1 AND kind='form_opened')<>opened_before THEN RAISE EXCEPTION 'Capacity recovery emitted false opening'; END IF;
 PERFORM public.maintain_notification_center(500);
END $$;
