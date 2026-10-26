-- One transaction owns state/history and the automatic queue commitment.
UPDATE public.email_capacity SET paused=true,worker_url=NULL;
DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; ord bigint; no_mail bigint;
 cmd uuid:=gen_random_uuid(); result jsonb; notice jsonb; legacy_notice jsonb; count_before bigint; admission_before numeric;
BEGIN
 PERFORM public.create_user_for_test('canonical-cancel','canonical-cancel@example.invalid');
 actor:=public.get_user_id('canonical-cancel');
 INSERT INTO public.organizations(title) VALUES('Canonical cancellation') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Canonical cancellation',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Canonical cancellation',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,actor,true);
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,price,currency_code,data)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered',10,'CZK','{"email":"owner@example.invalid"}') RETURNING id INTO ord;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 -- Force queue insertion failure after the state transition. Everything rolls back.
 ALTER TABLE public.email_messages ADD CONSTRAINT canonical_cancel_failure CHECK(message_kind<>'order_storno') NOT VALID;
 BEGIN
  PERFORM public.storno_order_client_sync_v1(ord,cmd);
  RAISE EXCEPTION 'queue failure was swallowed';
 EXCEPTION WHEN check_violation THEN NULL; END;
 ALTER TABLE public.email_messages DROP CONSTRAINT canonical_cancel_failure;
 ASSERT (SELECT state='ordered' AND price=10 FROM eshop.orders WHERE id=ord);
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=ord);
 ASSERT NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=cmd);
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.storno_order_client_sync_v1(ord,cmd);
 ASSERT result->>'code'='200';
 ASSERT public.storno_order_client_sync_v1(ord,cmd)=result;
 EXECUTE 'RESET ROLE';
 SELECT sum(amount) INTO admission_before FROM public.abuse_budget_usage WHERE rule_key='order.mutation.actor.burst' AND scope_id=actor::text;
 EXECUTE 'SET LOCAL ROLE authenticated';
 ASSERT public.storno_order_client_sync_v1(ord,gen_random_uuid())->>'status'='unchanged';
 PERFORM public.update_order_and_tickets_to_storno_ws(ord);
 EXECUTE 'RESET ROLE';
 ASSERT (SELECT count(*)=1 FROM eshop.orders_history WHERE "order"=ord AND state='storno');
 ASSERT (SELECT count(*)=1 FROM public.email_messages WHERE order_id=ord AND message_kind='order_storno');
 ASSERT (SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='order.mutation.actor.burst' AND scope_id=actor::text)=admission_before;
 -- Old Edge follow-up supplies requested_by; it is still automatic without a resend identity.
 notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',ord,'requested_by',actor),org,oc,un);
 ASSERT notice->>'replayed'='true';
 ASSERT notice->>'state'='pending';
 UPDATE public.email_messages SET workflow_state='expired' WHERE order_id=ord;
 notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',ord,'requested_by',actor),org,oc,un);
 ASSERT notice->>'replayed'='true' AND notice->>'state'='expired';
 notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',ord,'requested_by',actor),org,oc,un,now(),'manual:fixture-resend');
 ASSERT notice->>'replayed'='false';
 ASSERT (SELECT count(*)=2 FROM public.email_messages WHERE order_id=ord);
 -- Missing/invalid addresses do not prevent the domain transition.
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"invalid"}') RETURNING id INTO no_mail;
 PERFORM public.storno_order_client_sync_v1(no_mail,gen_random_uuid());
 ASSERT (SELECT state='storno' FROM eshop.orders WHERE id=no_mail);
 ASSERT NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=no_mail);
 -- Preserve the actual old Edge key/hash rather than merely deduping new keys.
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'storno','{"email":"legacy@example.invalid"}') RETURNING id INTO no_mail;
 legacy_notice:=public.enqueue_email('order_storno',jsonb_build_object('organization',org,'occasion',oc,'unit',un),
  'legacy@example.invalid',jsonb_build_object('order_id',no_mail,'requested_by',actor),
  no_mail||':0:legacy@example.invalid:false','TICKET_ORDER_STORNO',now(),NULL,no_mail,0);
 notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',no_mail,'requested_by',actor),org,oc,un);
 ASSERT notice->>'message_id'=legacy_notice->>'message_id';
 ASSERT (SELECT count(*)=1 FROM public.email_messages WHERE order_id=no_mail);
 UPDATE public.email_messages SET workflow_state='expired' WHERE order_id=no_mail;
 notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',no_mail),org,oc,un);
 ASSERT notice->>'state'='expired' AND notice->>'message_id'=legacy_notice->>'message_id';
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN
  PERFORM public.storno_order_client_sync_v1(ord,cmd);
  RAISE EXCEPTION 'receipt leaked to another actor';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 cmd:=gen_random_uuid();
 result:=public.delete_order_client_sync_v1(ord,cmd);
 ASSERT public.delete_order_client_sync_v1(ord,cmd)=result, 'direct deletion replay after row removal';
 UPDATE public.client_mutation_receipts SET status='expired',response=NULL,expired_at=clock_timestamp() WHERE command_id=cmd;
 result:=public.delete_order_client_sync_v1(ord,cmd);
 ASSERT result->>'status'='expired', 'receipt tombstone must never repeat deletion';
END $$;
