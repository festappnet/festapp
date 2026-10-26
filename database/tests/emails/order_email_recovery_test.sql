BEGIN;
SELECT set_config('festapp.email_wake','scheduled',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
CREATE FUNCTION pg_temp.repair(oid bigint, email text, source uuid, resend boolean, command uuid DEFAULT gen_random_uuid()) RETURNS jsonb
LANGUAGE sql AS $$ SELECT public.repair_order_email_client_sync_v1(o.id,o.data->>'email',o.state,o.email_payment_version,email,source,resend,command,public.order_email_payment_fingerprint(o.id)) FROM eshop.orders o WHERE id=oid $$;
CREATE TEMP TABLE recovery_fixture(oid bigint,source uuid,actor uuid,v bigint);
DO $$
DECLARE org bigint; un bigint; oc bigint; oid bigint; other_order bigint; actor uuid:=gen_random_uuid(); viewer uuid:=gen_random_uuid();
 src uuid; src2 uuid; msg uuid; cmd uuid:=gen_random_uuid(); a jsonb; b jsonb; before_order jsonb; before_tickets jsonb; before_payment jsonb;
 fid bigint; field bigint; pi bigint; v bigint; payment_token text;
BEGIN
 PERFORM assert_false(has_function_privilege('anon','public.repair_order_email_client_sync_v1(bigint,text,text,bigint,text,uuid,boolean,uuid,text)','EXECUTE'),'anonymous RPC denied');
 PERFORM assert_true(has_function_privilege('authenticated','public.repair_order_email_client_sync_v1(bigint,text,text,bigint,text,uuid,boolean,uuid,text)','EXECUTE'),'authenticated RPC available');
 PERFORM assert_false(has_function_privilege('authenticated','public.normalize_order_email_contact(text)','EXECUTE'),'internal validator private');
 INSERT INTO public.organizations(title) VALUES('Recovery synthetic') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Recovery',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Recovery',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(actor),(viewer);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org),(viewer,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(oc,actor,true,true),(oc,viewer,false,true);
 INSERT INTO public.forms(occasion,title) VALUES(oc,'Contact') RETURNING id INTO fid;
 INSERT INTO public.form_fields(form,type,title) VALUES(fid,'email','Email') RETURNING id INTO field;
 INSERT INTO eshop.payment_info(amount,paid,currency_code) VALUES(100,0,'CZK') RETURNING id INTO pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,form,payment_info,state,price,currency_code,data)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,fid,pi,'ordered',100,'CZK',jsonb_build_object('email','old@example.invalid','fields',jsonb_build_array(jsonb_build_object(field::text,'old@example.invalid')))) RETURNING id,email_payment_version INTO oid,v;
 INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered');
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,currval(pg_get_serial_sequence('eshop.tickets','id')));
 SELECT to_jsonb(o)-'data'-'updated_at' INTO before_order FROM eshop.orders o WHERE id=oid;
 SELECT jsonb_agg(to_jsonb(t)) INTO before_tickets FROM eshop.tickets t WHERE t.occasion=oc;
 SELECT to_jsonb(p) INTO before_payment FROM eshop.payment_info p WHERE id=pi;
 a:=public.enqueue_order_email('TICKET_ORDER_CONFIRMATION',jsonb_build_object('order_id',oid,'command_id',gen_random_uuid()),org,oc,un);
 src:=(a->>'message_id')::uuid;
 UPDATE public.email_messages SET workflow_state='accepted',bounced_at=now(),recipient='old@example.invalid' WHERE message_id=src;
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 BEGIN PERFORM pg_temp.repair(oid,'fixed@example.invalid',src,true); RAISE EXCEPTION 'read-only allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 BEGIN PERFORM pg_temp.repair(oid,E'bad\r\n@example.invalid',src,true); RAISE EXCEPTION 'header allowed'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM pg_temp.repair(oid,'',src,false); RAISE EXCEPTION 'empty allowed'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"other@example.invalid"}') RETURNING id INTO other_order;
 BEGIN PERFORM pg_temp.repair(other_order,'fixed@example.invalid',src,true); RAISE EXCEPTION 'foreign source allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 a:=public.repair_order_email_client_sync_v1(oid,'stale@example.invalid','ordered',v,'fixed@example.invalid',src,true,gen_random_uuid(),public.order_email_payment_fingerprint(oid));
 PERFORM assert_eq((a->>'code')::int,409,'contact conflict');
 a:=public.repair_order_email_client_sync_v1(oid,'old@example.invalid','ordered',v+1,'fixed@example.invalid',src,true,gen_random_uuid(),public.order_email_payment_fingerprint(oid));
 PERFORM assert_eq((a->>'code')::int,409,'payment version conflict');
 payment_token:=public.order_email_payment_fingerprint(oid);
 UPDATE eshop.payment_info SET deadline=now()+interval '1 day' WHERE id=pi;
 a:=public.repair_order_email_client_sync_v1(oid,'old@example.invalid','ordered',v,'fixed@example.invalid',src,true,gen_random_uuid(),payment_token);
 PERFORM assert_eq((a->>'code')::int,409,'changed deadline conflicts even without changing payment version');
 UPDATE eshop.payment_info SET deadline=NULL WHERE id=pi;

 a:=pg_temp.repair(oid,'fixed+alias@example.invalid',src,false);
 PERFORM assert_eq(a#>>'{data,sendingRequested}','false','save without send');
 PERFORM assert_eq((SELECT data#>>ARRAY['fields','0',field::text] FROM eshop.orders WHERE id=oid),'fixed+alias@example.invalid','form projection updated');
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),1,'save alone preserves issue');
 a:=pg_temp.repair(oid,'fixed+alias@example.invalid',src,true,cmd);
 msg:=(a#>>'{data,intent,message_id}')::uuid;
 PERFORM assert_true(msg IS NOT NULL,'one canonical intent returned');
 PERFORM assert_eq((SELECT data->>'command_id' FROM public.email_messages WHERE message_id=msg),cmd::text,'resend owns its command identity');
 PERFORM assert_true((SELECT data->>'command_id' FROM public.email_messages WHERE message_id=src)<>cmd::text,'checkout command evidence preserved');
 PERFORM assert_eq((SELECT data#>>'{ticket_order,order,data,email}' FROM public.email_messages WHERE message_id=msg),'fixed+alias@example.invalid','renderer snapshot has current contact');
 PERFORM assert_eq((SELECT data#>>'{ticket_order,order,order_symbol}' FROM public.email_messages WHERE message_id=msg),(SELECT order_symbol FROM eshop.orders WHERE id=oid),'renderer snapshot preserves identity');
 b:=public.repair_order_email_client_sync_v1(oid,'fixed+alias@example.invalid','ordered',v,'fixed+alias@example.invalid',src,true,cmd,public.order_email_payment_fingerprint(oid));
 PERFORM assert_eq(a,b,'lost response replays identical receipt');
 BEGIN PERFORM pg_temp.repair(oid,'different@example.invalid',src,true,cmd); RAISE EXCEPTION 'payload reuse allowed'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 UPDATE public.occasion_users SET is_editor_order=false WHERE occasion=oc AND "user"=actor;
 BEGIN PERFORM pg_temp.repair(oid,'fixed+alias@example.invalid',src,true,cmd); RAISE EXCEPTION 'revoked replay allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE public.occasion_users SET is_editor_order=true WHERE occasion=oc AND "user"=actor;
 b:=pg_temp.repair(oid,'fixed+alias@example.invalid',src,true);
 PERFORM assert_eq((b->>'code')::int,409,'distinct command joins conflict with active intent');
 PERFORM assert_eq(public.get_order_email_summary(oid)#>>'{current_issues,0,resolution}','waiting_repair','enqueue remains waiting');
 UPDATE public.email_capacity SET paused=true;
 PERFORM assert_eq(public.get_order_email_summary(oid)#>>'{current_issues,0,reason}','queue_paused','paused queue has an explicit waiting reason');
 UPDATE public.email_capacity SET paused=false;
 UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now() WHERE message_id=msg;
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),1,'acceptance is not delivery');
 UPDATE public.email_messages SET opened_at=now() WHERE message_id=msg;
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),1,'open is not delivery');
 UPDATE public.email_messages SET delivered_at=now() WHERE message_id=msg;
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),0,'linked current delivery resolves');
 PERFORM assert_true((SELECT bounced_at IS NOT NULL FROM public.email_messages WHERE message_id=src),'original bounce retained');
 UPDATE eshop.payment_info SET deadline=now()+interval '3 days' WHERE id=pi;
 PERFORM assert_eq(public.get_order_email_summary(oid)#>>'{current_issues,0,resolution}','stale_delivery','stale payment evidence never appears as current success');
 UPDATE eshop.payment_info SET deadline=NULL WHERE id=pi;
 UPDATE public.email_messages SET bounced_at=now() WHERE message_id=msg;
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),1,'late bounce reopens');
 UPDATE public.email_messages SET bounced_at=now()-interval '1 day' WHERE message_id=msg;
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),0,'older bounce cannot override newer delivery');
 PERFORM assert_true((SELECT bounced_at IS NOT NULL FROM public.email_messages WHERE message_id=msg),'older bounce remains historical evidence');
 UPDATE public.email_messages SET provider_message_id='recovery-fixture:'||msg,bounced_at=NULL WHERE message_id=msg;
 PERFORM public.record_email_events(jsonb_build_array(jsonb_build_object('key','older-bounce:'||msg,'provider_id','recovery-fixture:'||msg,'recipient','fixed+alias@example.invalid','type','bounce','time',now()-interval '1 day')));
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),0,'late older provider bounce does not override delivery');
 PERFORM public.record_email_events(jsonb_build_array(
  jsonb_build_object('key','newer-bounce:'||msg,'provider_id','recovery-fixture:'||msg,'recipient','fixed+alias@example.invalid','type','bounce','time',now()+interval '1 second'),
  jsonb_build_object('key','newer-bounce:'||msg,'provider_id','recovery-fixture:'||msg,'recipient','fixed+alias@example.invalid','type','bounce','time',now()+interval '1 second')));
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),1,'newer provider bounce reopens even when earliest bounce is old');
 PERFORM assert_eq((SELECT count(*) FROM public.email_delivery_events WHERE event_key='newer-bounce:'||msg),1::bigint,'provider duplicates are idempotent');
 DELETE FROM public.email_delivery_events WHERE message_id=msg;
 UPDATE public.email_messages SET bounced_at=now() WHERE message_id=msg;
 -- A second independent problem is never hidden by the first chain's delivery.
 a:=public.enqueue_order_email('TICKET_ORDER_UPDATE',jsonb_build_object('order_id',oid),org,oc,un,now(),'second-problem');
 src2:=(a->>'message_id')::uuid;
 UPDATE public.email_messages SET workflow_state='dead' WHERE message_id=src2;
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),2,'independent issues preserved');
 UPDATE public.email_messages SET bounced_at=NULL WHERE message_id=msg;
 PERFORM assert_eq(jsonb_array_length(public.get_order_email_summary(oid)->'current_issues'),1,'unrelated success cannot resolve second problem');
 UPDATE public.email_messages SET workflow_state='unknown',delivered_at=NULL,opened_at=NULL WHERE message_id=msg;
 BEGIN PERFORM pg_temp.repair(oid,'another@example.invalid',src,true); RAISE EXCEPTION 'unknown bypassed'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'email_outcome_unresolved' THEN RAISE; END IF; END;
 PERFORM pg_temp.repair(oid,'another@example.invalid',src,false);
 PERFORM assert_eq((SELECT recipient FROM public.email_messages WHERE message_id=msg),'fixed+alias@example.invalid','in-flight evidence immutable');
 UPDATE public.email_messages SET workflow_state='dead' WHERE message_id=msg;
 INSERT INTO public.email_suppressions(recipient,reason) VALUES('blocked@example.invalid','hard_bounce');
 BEGIN PERFORM pg_temp.repair(oid,'blocked@example.invalid',src,true); RAISE EXCEPTION 'suppression bypassed'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'email_recipient_suppressed' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT data->>'email' FROM eshop.orders WHERE id=oid),'another@example.invalid','suppression rolls contact back');
 PERFORM assert_eq((SELECT to_jsonb(o)-'data'-'updated_at' FROM eshop.orders o WHERE id=oid),before_order,'order finance and identity unchanged');
 PERFORM assert_eq((SELECT jsonb_agg(to_jsonb(t)) FROM eshop.tickets t WHERE t.occasion=oc),before_tickets,'ticket identity and inventory unchanged');
 PERFORM assert_eq((SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=pi),before_payment,'payment unchanged');
 -- A changed split-child contact cannot acquire the parent/sibling overview.
 UPDATE eshop.orders SET form=fid WHERE id=other_order;
 UPDATE eshop.orders SET source_waitlist_order_id=other_order WHERE id=oid;
 PERFORM assert_true(public.get_order_email_overview_source_v1(oid,'another@example.invalid',gen_random_uuid()) IS NULL,'repaired child omits capability for another contact');
 UPDATE eshop.orders SET source_waitlist_order_id=NULL WHERE id=oid;

 INSERT INTO recovery_fixture VALUES(oid,msg,actor,v);
 UPDATE eshop.orders SET state='storno' WHERE id=oid;
 BEGIN PERFORM pg_temp.repair(oid,'other@example.invalid',src,false); RAISE EXCEPTION 'cancelled edited'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ORDER_ACTION_NOT_ALLOWED' THEN RAISE; END IF; END;
 PERFORM assert_eq(public.get_order_email_summary(oid)#>>'{current_issues,0,resolution}','cancelled','cancellation is informational');
END $$;
DO $$
DECLARE f record; original text; before_contact text; before_count bigint; a jsonb; pending uuid; row public.email_messages;
BEGIN
 SELECT * INTO f FROM recovery_fixture;
 PERFORM set_config('request.jwt.claim.sub',f.actor::text,true);
 UPDATE eshop.orders SET state='ordered' WHERE id=f.oid;
 SELECT data->>'email' INTO before_contact FROM eshop.orders WHERE id=f.oid;
 SELECT count(*) INTO before_count FROM public.email_messages WHERE order_id=f.oid;
 SELECT pg_get_functiondef('public.enqueue_order_email(text,jsonb,bigint,bigint,bigint,timestamptz,text)'::regprocedure) INTO original;
 EXECUTE replace(original,E'BEGIN\n',E'BEGIN\n RAISE EXCEPTION ''fixture_enqueue_rejected'';\n');
 BEGIN
  PERFORM pg_temp.repair(f.oid,'rollback@example.invalid',f.source,true);
  RAISE EXCEPTION 'enqueue failure ignored';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'fixture_enqueue_rejected' THEN RAISE; END IF; END;
 EXECUTE original;
 PERFORM assert_eq((SELECT data->>'email' FROM eshop.orders WHERE id=f.oid),before_contact,'enqueue failure rolls contact back');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=f.oid),before_count,'enqueue failure leaves no intent');
 -- Removing the form field does not invent a new response key.
 DELETE FROM public.form_fields WHERE form=(SELECT form FROM eshop.orders WHERE id=f.oid) AND type='email';
 a:=pg_temp.repair(f.oid,'after-removal@example.invalid',f.source,false);
 PERFORM assert_eq((a->>'code')::int,200,'historical order without email field retains contact format');
 -- Stale pre-permit payload is retired, while the historical snapshot remains.
 a:=public.enqueue_order_email('TICKET_ORDER_CONFIRMATION',jsonb_build_object('order_id',f.oid),
  (SELECT organization FROM public.occasions WHERE id=(SELECT occasion FROM eshop.orders WHERE id=f.oid)),
  (SELECT occasion FROM eshop.orders WHERE id=f.oid),(SELECT unit FROM public.occasions WHERE id=(SELECT occasion FROM eshop.orders WHERE id=f.oid)),now(),'stale-fixture');
 pending:=(a->>'message_id')::uuid;
 SELECT * INTO row FROM public.email_messages WHERE message_id=pending;
 PERFORM pg_temp.repair(f.oid,'final@example.invalid',f.source,false);
 PERFORM assert_false(public.email_intent_valid(row),'old contact fails send fence validation');
 PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE message_id=pending),'cancelled','old prepared recipient retired');
 UPDATE eshop.orders SET state='stock',price=NULL,payment_info=NULL WHERE id=f.oid;
 BEGIN PERFORM pg_temp.repair(f.oid,'stock@example.invalid',f.source,false); RAISE EXCEPTION 'stock edited';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ORDER_ACTION_NOT_ALLOWED' THEN RAISE; END IF; END;
END $$;
DO $$
DECLARE f record; original text; a jsonb; result_id uuid; count_before bigint;
BEGIN
 SELECT * INTO f FROM recovery_fixture;
 UPDATE eshop.orders SET state='ordered' WHERE id=f.oid;
 PERFORM set_config('request.jwt.claim.sub',f.actor::text,true);
 SELECT pg_get_functiondef('public.generate_request_secret(integer)'::regprocedure) INTO original;
 EXECUTE replace(original,E'BEGIN\n',E'BEGIN\n RAISE EXCEPTION ''fixture_wake_failure'';\n');
 UPDATE public.email_capacity SET paused=false,worker_url='http://127.0.0.1:1/fake-worker',wake_error=NULL;
 PERFORM set_config('festapp.email_wake','',true);
 SELECT count(*) INTO count_before FROM public.email_messages WHERE order_id=f.oid;
 a:=pg_temp.repair(f.oid,'wake-failure@example.invalid',f.source,true);
 result_id:=(a#>>'{data,intent,message_id}')::uuid;
 PERFORM assert_true(result_id IS NOT NULL,'wake failure still commits one durable intent');
 PERFORM assert_eq((SELECT wake_error FROM public.email_capacity),'wake_failed','wake failure retained for cron recovery');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=f.oid),count_before+1,'wake failure creates exactly one intent');
 EXECUTE original;
END $$;
ROLLBACK;
