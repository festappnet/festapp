DO $$
DECLARE org bigint; uid bigint; occ bigint; fid bigint; cid uuid; sid uuid; oid bigint; ticket bigint; payload jsonb; slug text;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 INSERT INTO public.organizations(title) VALUES('Skutečné otevření') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO uid;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Ples',gen_random_uuid()::text,org,uid,now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO public.forms(occasion,is_open,participant_capacity,data) VALUES(occ,true,1,jsonb_build_object('schedule',jsonb_build_object('start_time',now()+interval '1 day'),'sale_opening_notifications','{"enabled":true}'::jsonb)) RETURNING id INTO fid;
 slug:=public.reserve_public_link_internal('form',fid,NULL,true); UPDATE public.forms SET link=slug WHERE id=fid;
 PERFORM public.sync_sale_opening_settings_internal(fid,NULL);
 SELECT id INTO cid FROM public.sale_opening_campaigns WHERE form_id=fid;
 payload:=jsonb_build_object('formLink',slug,'email','late@example.invalid','lang','cs',
 'unsubscribe',jsonb_build_object('hash',repeat('2',64),'envelope',jsonb_build_object('v','1','ciphertext',repeat('y',48))));
 PERFORM public.sale_opening_notification_command('subscribe',payload);
 INSERT INTO eshop.orders(occasion,form,state,order_sequence,order_symbol) VALUES(occ,fid,'ordered',public.next_order_sequence(occ),public.generate_order_symbol()) RETURNING id INTO oid;
 INSERT INTO eshop.tickets(occasion,state) VALUES(occ,'ordered') RETURNING id INTO ticket;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,ticket);
 UPDATE public.forms SET data=jsonb_set(data,'{schedule,start_time}',to_jsonb(now()-interval '1 minute')) WHERE id=fid;
 PERFORM assert_eq(public.get_form_registration_mode_internal(fid),'full','Fixture is full');
 PERFORM public.maintain_sale_opening_notifications(100);
 PERFORM assert_eq((SELECT phase FROM public.sale_opening_campaigns WHERE id=cid),'armed','Full form does not claim launch');
 UPDATE public.forms SET waitlist_enabled=true,waitlist_offer_duration_seconds=3600 WHERE id=fid;
 PERFORM assert_eq(public.get_form_registration_mode_internal(fid),'waitlist','Fixture accepts waiting entries');
 PERFORM public.maintain_sale_opening_notifications(100);
 PERFORM assert_eq((SELECT phase FROM public.sale_opening_campaigns WHERE id=cid),'armed','Waitlist is not regular sales');
 UPDATE eshop.tickets SET state='storno' WHERE id=ticket;
 UPDATE eshop.orders SET state='storno' WHERE id=oid;
 PERFORM public.maintain_sale_opening_notifications(100);
 PERFORM assert_eq((SELECT phase FROM public.sale_opening_campaigns WHERE id=cid),'completed','Available form observes first real opening');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE occasion=occ AND message_kind='sale_opening_opened'),1::bigint,'Direct subscriber receives one launch after actual opening');
 UPDATE public.sale_opening_campaigns SET opened_at=now()-interval '25 hours' WHERE id=cid;
 PERFORM assert_false((SELECT public.email_intent_valid(m) FROM public.email_messages m WHERE occasion=occ AND message_kind='sale_opening_opened'),'Original launch TTL never extends');
END $$;
