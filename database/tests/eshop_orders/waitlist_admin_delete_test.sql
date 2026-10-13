-- Synthetic fixtures only; the runner wraps this file in a rollback transaction.
CREATE FUNCTION pg_temp.delete_fixture(p_form bigint,p_occasion bigint,p_state text DEFAULT 'waitlisted',p_ticket_state text DEFAULT 'waitlisted')
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE o bigint;t bigint;
BEGIN
 INSERT INTO eshop.orders(form,occasion,state,order_sequence,order_symbol)
 VALUES(p_form,p_occasion,p_state,public.next_order_sequence(p_occasion),public.generate_order_symbol()) RETURNING id INTO o;
 INSERT INTO eshop.tickets(occasion,state,data,waitlist_queue_at)
 VALUES(p_occasion,p_ticket_state,'{"fields":[]}',clock_timestamp()) RETURNING id INTO t;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(o,t);
 RETURN jsonb_build_object('order',o,'ticket',t);
END $$;
DO $$
DECLARE actor uuid:=gen_random_uuid();stranger uuid:=gen_random_uuid();org bigint;un bigint;oc bigint;f bigint;
 other_org bigint;other_un bigint;other_oc bigint;other_f bigint;fixture jsonb;child jsonb;oid bigint;tid bigint;
 child_id bigint;child_ticket bigint;w uuid;s uuid;cmd uuid;attempt uuid;response jsonb;role_name text;revision bigint;
 bank bigint;pi bigint;tx bigint;msg uuid;mail_attempt uuid;mail_lease uuid:=gen_random_uuid();child_snapshot jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Waitlist admin deletion') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Delete unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES('Delete event',gen_random_uuid()::text,org,un,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.forms(occasion,link,participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds)
 VALUES(oc,gen_random_uuid()::text,10,true,3600) RETURNING id INTO f;
 INSERT INTO auth.users(id,email) VALUES(actor,actor::text||'@example.invalid'),(stranger,stranger::text||'@example.invalid');
 INSERT INTO public.user_info(id,email_readonly) VALUES(actor,actor::text||'@example.invalid'),(stranger,stranger::text||'@example.invalid');
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,actor,true);
 INSERT INTO public.organization_users(organization,"user") VALUES(org,actor);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 -- Waiting and fully withdrawn tickets, under all legitimate delete roles.
 FOREACH role_name IN ARRAY ARRAY['manager','editor','organization_admin'] LOOP
  UPDATE public.unit_users SET is_manager=role_name='manager',is_editor=role_name='editor' WHERE unit=un AND "user"=actor;
  UPDATE public.organization_users SET is_admin=role_name='organization_admin' WHERE organization=org AND "user"=actor;
  fixture:=pg_temp.delete_fixture(f,oc,'waitlisted',CASE WHEN role_name='editor' THEN 'storno' ELSE 'waitlisted' END);
  oid:=(fixture->>'order')::bigint;tid:=(fixture->>'ticket')::bigint;cmd:=gen_random_uuid();
  response:=public.delete_order_client_sync_v1(oid,cmd);
  ASSERT (response->>'code')::int=200,'Waiting/withdrawn admin deletion rejected';
  ASSERT NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid),'Waiting order remains';
  ASSERT NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=tid),'Waiting ticket remains';
  ASSERT public.delete_order_client_sync_v1(oid,cmd)=response,'Exact deletion replay differs';
  UPDATE public.unit_users SET is_manager=false,is_editor=false WHERE unit=un AND "user"=actor;
  UPDATE public.organization_users SET is_admin=false WHERE organization=org AND "user"=actor;
  BEGIN PERFORM public.delete_order_client_sync_v1(oid,cmd);RAISE EXCEPTION 'Revoked actor replay succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  UPDATE public.unit_users SET is_manager=role_name='manager',is_editor=role_name='editor' WHERE unit=un AND "user"=actor;
  UPDATE public.organization_users SET is_admin=role_name='organization_admin' WHERE organization=org AND "user"=actor;
  PERFORM set_config('request.jwt.claim.sub',stranger::text,true);
  BEGIN PERFORM public.delete_order_client_sync_v1(oid,cmd);RAISE EXCEPTION 'Foreign actor replay succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 END LOOP;
 UPDATE public.organization_users SET is_admin=false WHERE organization=org AND "user"=actor;
 UPDATE public.unit_users SET is_manager=true,is_editor=false WHERE unit=un AND "user"=actor;
 -- Active offer, a confirmed child and a completed conversion journal.
 fixture:=pg_temp.delete_fixture(f,oc);oid:=(fixture->>'order')::bigint;tid:=(fixture->>'ticket')::bigint;
 child:=pg_temp.delete_fixture(f,oc,'paid','paid');child_id:=(child->>'order')::bigint;child_ticket:=(child->>'ticket')::bigint;
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Synthetic bank','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.payment_info(amount,paid,currency_code,bank_account) VALUES(200,200,'CZK',bank) RETURNING id INTO pi;
 UPDATE eshop.orders SET source_waitlist_order_id=oid,payment_info=pi,price=200,currency_code='CZK',data='{"name":"Accepted child"}' WHERE id=child_id;
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date) VALUES(bank,pi,200,'CZK',now()) RETURNING id INTO tx;
 INSERT INTO eshop.waitlist_offers(order_id,form_id,expires_at,revision) VALUES(oid,f,now()+interval '1 hour',1) RETURNING id INTO w;
 INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id) VALUES(w,tid,f) RETURNING id INTO s;
 INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id,outcome,resulting_order_id) VALUES(w,child_ticket,f,'accepted',child_id);
 INSERT INTO eshop.waitlist_capabilities(token_hash,organization_id,form_id,order_id,offer_id,kind,expires_at)
 VALUES(repeat('a',64),org,f,oid,w,'offer',now()+interval '1 hour');
 attempt:=gen_random_uuid();
 INSERT INTO eshop.waitlist_acceptance_attempts(command_id,source_order_id,target_order_id,offer_id,conversion,ticket_ids,slot_ids,previous_order_data,previous_tickets,previous_links,previous_slots,state)
 VALUES(attempt,oid,child_id,w,'split',ARRAY[child_ticket],ARRAY[s],'{}','[]','[]','[]','completed');
 INSERT INTO public.email_messages(target_time,code,organization,occasion,order_id,message_kind,dedupe_key,input_hash,recipient)
 VALUES(now(),'waitlist_offer',org,oc,oid,'waitlist_offer',gen_random_uuid()::text,repeat('f',64),'fixture@example.invalid') RETURNING message_id INTO msg;
 UPDATE public.email_messages SET workflow_state='preparing',lease_token=mail_lease,lease_until=now()+interval '1 minute' WHERE message_id=msg;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(msg,mail_lease,'preparing') RETURNING attempt_id INTO mail_attempt;
 SELECT to_jsonb(o)-'source_waitlist_order_id'-'updated_at' INTO child_snapshot FROM eshop.orders o WHERE id=child_id;
 SELECT capacity_revision INTO revision FROM public.forms WHERE id=f;
 response:=public.delete_order_client_sync_v1(oid,gen_random_uuid());
 ASSERT (response->>'code')::int=200,'Active-offer parent deletion rejected';
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE id=w),'Offer remains';
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w),'Slots remain';
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.waitlist_capabilities WHERE order_id=oid),'Capability remains';
 ASSERT NOT EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE command_id=attempt),'Conversion journal remains';
 ASSERT NOT EXISTS(SELECT 1 FROM public.email_messages WHERE message_id=msg),'Deleted offer can still be emailed';
 ASSERT NOT EXISTS(SELECT 1 FROM public.email_attempts WHERE attempt_id=mail_attempt),'Deleted offer lease remains';
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 BEGIN PERFORM public.begin_email_send(mail_attempt,mail_lease);RAISE EXCEPTION 'Late worker obtained send permit';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'stale_email_attempt' THEN RAISE;END IF;END;
 ASSERT (SELECT capacity_revision FROM public.forms WHERE id=f)=revision+1,'Capacity revision not released';
 ASSERT (SELECT to_jsonb(o)-'source_waitlist_order_id'-'updated_at' FROM eshop.orders o WHERE id=child_id)=child_snapshot,'Confirmed child mutated';
 ASSERT (SELECT source_waitlist_order_id IS NULL FROM eshop.orders WHERE id=child_id),'Child source FK remains';
 ASSERT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=child_ticket AND state='paid'),'Child admission removed';
 ASSERT EXISTS(SELECT 1 FROM eshop.transactions WHERE id=tx AND payment_info=pi),'Child finance detached';
 -- A preparation journal is never removed while the Fakturoid recovery owns it.
 fixture:=pg_temp.delete_fixture(f,oc);oid:=(fixture->>'order')::bigint;tid:=(fixture->>'ticket')::bigint;
 child:=pg_temp.delete_fixture(f,oc,'preparing_payment','ordered');child_id:=(child->>'order')::bigint;child_ticket:=(child->>'ticket')::bigint;
 UPDATE eshop.orders SET source_waitlist_order_id=oid WHERE id=child_id;
 INSERT INTO eshop.waitlist_offers(order_id,form_id,expires_at,revision) VALUES(oid,f,now()+interval '1 hour',1) RETURNING id INTO w;
 attempt:=gen_random_uuid();
 INSERT INTO eshop.waitlist_acceptance_attempts(command_id,source_order_id,target_order_id,offer_id,conversion,ticket_ids,slot_ids,previous_order_data,previous_tickets,previous_links,previous_slots)
 VALUES(attempt,oid,child_id,w,'split',ARRAY[tid],'{}','{}','[]','[]','[]');
 BEGIN PERFORM public.delete_order_client_sync_v1(oid,gen_random_uuid());RAISE EXCEPTION 'Preparing acceptance deleted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'WAITLIST_ACCEPTANCE_IN_PROGRESS' THEN RAISE;END IF;END;
 ASSERT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid),'Preparing source deleted';
 ASSERT EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE command_id=attempt),'Preparing recovery journal deleted';
 -- After preparation completes, deleting a child must preserve the parent's
 -- active waiting ticket and pending offer, rather than cascading the group.
 UPDATE eshop.waitlist_acceptance_attempts SET state='completed' WHERE command_id=attempt;
 UPDATE eshop.orders SET state='paid' WHERE id=child_id;
 INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id) VALUES(w,tid,f);
 INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id,outcome,resulting_order_id) VALUES(w,child_ticket,f,'accepted',child_id);
 response:=public.delete_order_client_sync_v1(child_id,gen_random_uuid());
 ASSERT (response->>'code')::int=200 AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=child_id),'Completed child deletion failed';
 ASSERT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND state='waitlisted'),'Parent remainder deleted';
 ASSERT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w AND ticket_id=tid AND outcome='pending'),'Parent pending offer changed';
 ASSERT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=tid AND state='waitlisted'),'Parent waiting ticket changed';
 -- Viewer/order editor without unit edit rights cannot delete; tenant scope is exact.
 UPDATE public.unit_users SET is_manager=false,is_editor=false,is_editor_view=true WHERE unit=un AND "user"=actor;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,actor,true);
 fixture:=pg_temp.delete_fixture(f,oc);oid:=(fixture->>'order')::bigint;
 BEGIN PERFORM public.delete_order_client_sync_v1(oid,gen_random_uuid());RAISE EXCEPTION 'Viewer/order-editor deleted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO public.organizations(title) VALUES('Other tenant') RETURNING id INTO other_org;
 INSERT INTO public.units(title,organization) VALUES('Other unit',other_org) RETURNING id INTO other_un;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Other event',gen_random_uuid()::text,other_org,other_un,now(),now()+interval '1 day') RETURNING id INTO other_oc;
 INSERT INTO public.forms(occasion,link) VALUES(other_oc,gen_random_uuid()::text) RETURNING id INTO other_f;
 UPDATE public.organization_users SET is_admin=true WHERE organization=org AND "user"=actor;
 fixture:=pg_temp.delete_fixture(other_f,other_oc);oid:=(fixture->>'order')::bigint;
 BEGIN PERFORM public.delete_order_client_sync_v1(oid,gen_random_uuid());RAISE EXCEPTION 'Cross-tenant admin deleted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid),'Foreign order removed';
END $$;
