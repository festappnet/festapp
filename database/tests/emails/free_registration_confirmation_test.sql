SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; fm bigint; form_key uuid; pt bigint; prod bigint;
 oid bigint; msg public.email_messages; result jsonb; claimed jsonb; permit jsonb;
 token uuid; attempt uuid; actor uuid:=gen_random_uuid(); repaired jsonb; command uuid:=gen_random_uuid();
BEGIN
 UPDATE public.email_messages SET workflow_state='cancelled';
 UPDATE public.email_capacity SET paused=false,shared_account=false,quota_at=now(),
   max_rate=1,rate_factor=1,max_sending=2,max_preparing=2,
   daily_quota=100,provider_sent_24h=0,worker_url=NULL,next_send_at=now(),circuit_until=NULL,
   provider_outage_streak=0,probe_until=NULL;
 INSERT INTO public.organizations(title) VALUES('Free registration confirmation') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Helpni-like confirmation',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled,features)
 VALUES('Free weekend',org,un,gen_random_uuid()::text,now(),now()+interval '1 day',true,
   '[{"code":"ticket","is_enabled":false}]') RETURNING id INTO oc;
 INSERT INTO public.forms(occasion,is_open) VALUES(oc,true) RETURNING id,key INTO fm,form_key;
 INSERT INTO public.form_fields(form,type,is_hidden,is_required) VALUES(fm,'ticket',false,true);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Attendance','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(oc,pt,'Full weekend',0,'CZK',false) RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field,is_required,is_hidden)
 VALUES(fm,'product_type',pt,true,true,false);
 INSERT INTO public.email_templates(unit,code,subject,html)
 VALUES(un,'TICKET_ORDER_CONFIRMATION','Potvrzení rezervace','<p>Potvrzujeme Vaši rezervaci.</p>');
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','anon',true);
 EXECUTE 'SET LOCAL ROLE anon';
 result:=public.create_ticket_order_client_sync_v1(jsonb_build_object('form',form_key,
   'email','free-registration@example.invalid','ticket',jsonb_build_array(jsonb_build_object(
     'fields',jsonb_build_array(jsonb_build_object('product_type',prod))))),command,gen_random_uuid());
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(result#>>'{data,code}','200','Real free checkout commits');
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','Zero total remains paid');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),0::numeric,'Zero total remains zero');
 PERFORM assert_true((SELECT pi.bank_account IS NULL FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id WHERE o.id=oid),'No bank account needed');
 SELECT * INTO STRICT msg FROM public.email_messages WHERE order_id=oid AND message_kind='order_confirmation';
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_true(public.email_intent_valid(msg),'Paid zero-price registration must retain its configured confirmation');
 PERFORM assert_eq(public.get_resolved_email_template(msg.code,jsonb_build_object('organization',org,'unit',un,'occasion',oc))->>'subject',
   'Potvrzení rezervace','Configured organizer confirmation is selected unchanged');
 claimed:=public.claim_email();
 PERFORM assert_eq(claimed->>'message_id',msg.message_id::text,'Worker claims zero-price confirmation instead of cancelling it');
 token:=(claimed->>'lease_token')::uuid; attempt:=(claimed->>'attempt_id')::uuid;
 -- SQL worker lifecycle is real; provider acceptance is simulated, no email leaves localhost.
 PERFORM public.prepare_email(msg.message_id,token,'{"sealed":"fixture"}');
 permit:=public.begin_email_send(attempt,token);
 PERFORM assert_eq(permit->>'disposition','send','Final send fence permits free confirmation');
 PERFORM public.finish_email_attempt(attempt,token,'accepted','free-confirmation-fixture');
 PERFORM public.apply_email_post_actions(msg.message_id);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','Sending confirmation never reverts or changes paid state');
 PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE message_id=msg.message_id),'accepted','Provider acceptance retained');
 UPDATE public.occasions SET features='[{"code":"ticket","is_enabled":true}]' WHERE id=oc;
 PERFORM assert_false(public.email_intent_valid(msg),'Automatic free tickets still replace checkout confirmation');
 PERFORM public.enqueue_paid_order_tickets(oid);
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets'),'Automatic ticket delivery unchanged');
 UPDATE public.occasions SET is_order_synchronization_enabled=false WHERE id=oc;
 PERFORM assert_true(public.email_intent_valid(msg),'Manual ticket delivery does not suppress the initial free registration confirmation');
 UPDATE public.occasions SET features='[]',is_order_synchronization_enabled=true WHERE id=oc;
 UPDATE eshop.orders SET price=100 WHERE id=oid;
 PERFORM assert_false(public.email_intent_valid(msg),'Paid positive orders retain their existing lifecycle');
 UPDATE eshop.orders SET state='ordered' WHERE id=oid;
 PERFORM assert_true(public.email_intent_valid(msg),'Unpaid positive confirmations unchanged');
 UPDATE eshop.orders SET state='paid',price=0,email_payment_version=email_payment_version+1 WHERE id=oid;
 PERFORM assert_false(public.email_intent_valid(msg),'Stale source version still rejected');
 SELECT email_payment_version INTO msg.source_version FROM eshop.orders WHERE id=oid;
 msg.recipient:='another@example.invalid';
 PERFORM assert_false(public.email_intent_valid(msg),'Wrong recipient still rejected');
 msg.recipient:='free-registration@example.invalid';
 UPDATE eshop.orders SET state='storno' WHERE id=oid;
 PERFORM assert_false(public.email_intent_valid(msg),'Cancelled free registration cannot send confirmation');
 UPDATE eshop.orders SET state='paid' WHERE id=oid;
 UPDATE public.email_messages SET bounced_at=now() WHERE message_id=msg.message_id;
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(public.order_email_current_issues(oid)) issue
   WHERE issue->>'kind'='order_confirmation' AND NOT (issue->>'obsolete')::boolean),
   'Free registration confirmation remains the current message in delivery reporting');
 -- An explicit organizer repair must select the same configured confirmation.
 INSERT INTO auth.users(id) VALUES(actor);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(oc,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 repaired:=public.repair_order_email_client_sync_v1(oid,'free-registration@example.invalid','paid',
   (SELECT email_payment_version FROM eshop.orders WHERE id=oid),'free-registration@example.invalid',NULL,true,gen_random_uuid(),public.order_email_payment_fingerprint(oid));
 PERFORM assert_eq((repaired->>'code')::int,200,'Explicit free registration confirmation resend accepted');
 PERFORM assert_eq((SELECT message_kind FROM public.email_messages WHERE message_id=(repaired#>>'{data,intent,message_id}')::uuid),'order_confirmation','Repair never switches free registration to ticket mail');
END $$;
