BEGIN;
DO $$
DECLARE org bigint; u bigint; occ bigint; ord bigint; other_ord bigint; actor uuid; ctx jsonb; msg jsonb; n int; states text[]:=ARRAY['pending','retry_wait','blocked','preparing','sending','accepted','unknown']; kinds text[]:=ARRAY['order_reminder','order_tickets','order_update','order_confirmation','order_reminder','order_reminder','order_reminder'];
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
 FOR n IN 1..7 LOOP
  msg:=public.enqueue_email(kinds[n],ctx,'cleanup@example.invalid','{}','delete-'||n,p_not_before:=now()+interval '1 day',p_order:=ord);
  UPDATE public.email_messages SET workflow_state=states[n],lease_token=CASE WHEN n=4 THEN gen_random_uuid() ELSE NULL END,lease_until=CASE WHEN n=4 THEN now()+interval '1 minute' ELSE NULL END WHERE message_id=(msg->>'message_id')::uuid;
 END LOOP;
 INSERT INTO public.email_attempts(message_id,lease_token,state) SELECT message_id,lease_token,'preparing' FROM public.email_messages WHERE order_id=ord AND workflow_state='preparing';
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
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=ord AND workflow_state='pending'),1::bigint,'email cancellation rolls back with deletion');
 PERFORM public.delete_order_221(ord);
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=ord),'order deleted');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=ord AND workflow_state='cancelled' AND last_error='order_deleted' AND lease_token IS NULL AND lease_until IS NULL),4::bigint,'all unsent order mail cancelled immediately');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=ord),7::bigint,'history retained');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=ord AND workflow_state IN ('sending','accepted','unknown')),3::bigint,'in-flight and provider evidence preserved');
 PERFORM assert_eq((SELECT count(*) FROM public.email_attempts a JOIN public.email_messages m USING(message_id) WHERE m.order_id=ord AND a.state='cancelled' AND a.error_code='order_deleted' AND a.finished_at IS NOT NULL),1::bigint,'preparation attempt fenced and closed');
 PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE order_id=other_ord),'pending','other order unchanged');
END $$;
ROLLBACK;
