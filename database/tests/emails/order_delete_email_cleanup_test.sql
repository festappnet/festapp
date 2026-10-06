BEGIN;
DO $$
DECLARE org bigint; u bigint; occ bigint; ord bigint; other_ord bigint; actor uuid; ctx jsonb; msg jsonb; n int; message_ids uuid[]; attempt_ids uuid[]; log_id bigint; states text[]:=ARRAY['pending','retry_wait','blocked','preparing','sending','accepted','unknown','dead','cancelled','suppressed','expired'];
BEGIN
 PERFORM create_user_for_test('delete-email-owner','delete-email-owner@example.invalid');
 actor:=get_user_id('delete-email-owner');
 INSERT INTO public.organizations(title) VALUES('Delete email fixture') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Delete email unit',org) RETURNING id INTO u;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(u,actor,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Delete email occasion',org,u,'delete-email-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO eshop.orders(order_symbol, occasion,state,data,price,currency_code) VALUES(public.generate_order_symbol(), occ,'ordered','{}',100,'CZK') RETURNING id INTO ord;
 INSERT INTO eshop.orders(order_symbol, occasion,state,data,price,currency_code) VALUES(public.generate_order_symbol(), occ,'ordered','{}',100,'CZK') RETURNING id INTO other_ord;
 ctx:=jsonb_build_object('organization',org,'unit',u,'occasion',occ);
 FOR n IN 1..array_length(states,1) LOOP
  msg:=public.enqueue_email('order_reminder',ctx,'cleanup@example.invalid','{}','delete-'||n,p_not_before:=now()+interval '1 day',p_order:=ord);
  UPDATE public.email_messages SET workflow_state=states[n],lease_token=CASE WHEN n=4 THEN gen_random_uuid() ELSE NULL END,lease_until=CASE WHEN n=4 THEN now()+interval '1 minute' ELSE NULL END WHERE message_id=(msg->>'message_id')::uuid;
 END LOOP;
 SELECT array_agg(message_id) INTO message_ids FROM public.email_messages WHERE order_id=ord;
 INSERT INTO public.email_attempts(message_id,lease_token,state,provider_message_id)
 SELECT message_id,coalesce(lease_token,gen_random_uuid()),'preparing','provider-'||message_id FROM public.email_messages WHERE order_id=ord;
 SELECT array_agg(attempt_id) INTO attempt_ids FROM public.email_attempts WHERE message_id=ANY(message_ids);
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,message_id)
 SELECT 'linked-'||a.attempt_id,a.provider_message_id,a.attempt_id,'cleanup@example.invalid','delivery',now(),a.message_id
 FROM public.email_attempts a WHERE a.attempt_id=ANY(attempt_ids);
 -- Feedback may already be persisted but not yet reconciled to a message.
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,recipient,event_type,provider_time)
 SELECT 'unmatched-'||a.attempt_id,a.provider_message_id,'cleanup@example.invalid','open',now()
 FROM public.email_attempts a WHERE a.attempt_id=ANY(attempt_ids);
 INSERT INTO public.email_confirmation_receipts(token_hash,message_id,expires_at)
 SELECT encode(extensions.digest(message_id::text,'sha256'),'hex'),message_id,now()+interval '1 day'
 FROM public.email_messages WHERE order_id=ord;
 INSERT INTO public.log_emails("to",template,organization,occasion,unit) VALUES('cleanup@example.invalid','TICKET_ORDER_REMINDER',org,occ,u) RETURNING id INTO log_id;
 INSERT INTO public.email_suppressions(recipient,reason) VALUES('cleanup@example.invalid','hard_bounce');
 INSERT INTO eshop.orders_history("order",state) VALUES(ord,'ordered');
 INSERT INTO eshop.bank_account_requests("order",occasion,created_by,state) VALUES(ord,occ,actor,'pending');
 PERFORM public.enqueue_email('order_reminder',ctx,'other@example.invalid','{}','other',p_not_before:=now()+interval '1 day',p_order:=other_ord);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 UPDATE public.unit_users SET is_manager=false WHERE unit=u AND "user"=actor;
 BEGIN
  PERFORM public.delete_order_221(ord);
  RAISE EXCEPTION 'Deletion without permission succeeded';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='Deletion without permission succeeded' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=ord AND workflow_state='pending'),1::bigint,'denied deletion leaves reminder intact');
 UPDATE public.unit_users SET is_manager=true WHERE unit=u AND "user"=actor;
 BEGIN
  PERFORM public.delete_order_221(ord);
  RAISE EXCEPTION 'rollback-fixture';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'rollback-fixture' THEN RAISE; END IF; END;
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders WHERE id=ord),'order deletion rolls back');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=ord AND workflow_state='pending'),1::bigint,'email deletion rolls back with order');
 PERFORM public.delete_order_221(ord);
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=ord),'order deleted');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=ord),0::bigint,'all order email states deleted');
 PERFORM assert_eq((SELECT count(*) FROM public.email_attempts WHERE attempt_id=ANY(attempt_ids)),0::bigint,'provider attempts deleted');
 PERFORM assert_eq((SELECT count(*) FROM public.email_delivery_events WHERE message_id=ANY(message_ids) OR attempt_id=ANY(attempt_ids) OR recipient='cleanup@example.invalid'),0::bigint,'linked and unmatched feedback deleted');
 PERFORM assert_eq((SELECT count(*) FROM public.email_confirmation_receipts WHERE message_id=ANY(message_ids)),0::bigint,'confirmation receipts deleted');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.log_emails WHERE id=log_id),'log_emails retained');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient='cleanup@example.invalid'),'address suppression retained');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=ord),'order history deleted');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.bank_account_requests WHERE "order"=ord),'order bank requests deleted');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 BEGIN
  PERFORM public.begin_email_send(attempt_ids[1],gen_random_uuid());
  RAISE EXCEPTION 'Deleted attempt was allowed to send';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'stale_email_attempt' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE order_id=other_ord),'pending','other order unchanged');
END $$;
ROLLBACK;
