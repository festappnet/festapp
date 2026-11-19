BEGIN;
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; oid bigint; first_message uuid; result jsonb;
 actor uuid:=gen_random_uuid(); rejection text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Paid ticket delivery regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Delivery regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled,features)
 VALUES('Delivery regression',org,un,gen_random_uuid()::text,now(),now()+interval '1 day',true,'[{"code":"ticket","is_enabled":true}]') RETURNING id INTO oc;
 INSERT INTO eshop.orders(occasion,order_symbol,order_sequence,state,data,price,currency_code)
 VALUES(oc,public.generate_order_symbol(),public.next_order_sequence(oc),'paid','{"email":"regression@example.invalid"}',100,'CZK') RETURNING id INTO oid;
 PERFORM public.enqueue_paid_order_tickets(oid);
 SELECT message_id INTO STRICT first_message FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets';
 -- The worker may accept the automatic message before the UI confirms sending.
 UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now() WHERE message_id=first_message;
 result:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',oid,'requested_by',actor),org,oc,un);
 IF result->>'message_id' IS DISTINCT FROM first_message::text OR (SELECT count(*) FROM public.email_messages WHERE order_id=oid)<>1 THEN
  RAISE EXCEPTION 'First delivery must reuse the already accepted automatic intent'; END IF;
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.ordinary.recipient.day';
 SET LOCAL ROLE service_role;
 -- An explicit later resend remains a distinct authorized user operation.
 result:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',oid,'requested_by',actor),org,oc,un,now(),'resend:explicit-test');
 IF result->>'message_id'=first_message::text OR (SELECT count(*) FROM public.email_messages WHERE order_id=oid)<>2 THEN
  RAISE EXCEPTION 'Explicit resend must create a new intent'; END IF;
 UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now() WHERE message_id=(result->>'message_id')::uuid;
 BEGIN
  PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',oid,'requested_by',actor),org,oc,un,now(),'resend:after-recipient-limit');
  RAISE EXCEPTION 'A new resend must obey the existing recipient budget';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS rejection = PG_EXCEPTION_DETAIL;
  IF rejection::jsonb->>'ruleKey' IS DISTINCT FROM 'email.ordinary.recipient.day'
     OR coalesce((rejection::jsonb->>'retryAfterSeconds')::int,0)<=0 THEN
   RAISE EXCEPTION 'The rejected resend must report the recipient rule and retry time';
  END IF;
 END;
 IF (SELECT count(*) FROM public.email_messages WHERE order_id=oid)<>2 THEN
  RAISE EXCEPTION 'A rejected resend must leave the delivered messages intact'; END IF;
 RESET ROLE;
 RAISE NOTICE 'PASS: first delivery reuses accepted automatic tickets; explicit resend remains available';
END $$;
ROLLBACK;

BEGIN;
SELECT set_config('festapp.email_wake','scheduled',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$
DECLARE
 org bigint; organizer bigint; event_id bigint; fixture_order bigint; ticket_id bigint;
 organizers bigint[]; events bigint[]; fixture_orders bigint[];
 actor uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 contact text:='shared-resend-recipient@example.invalid';
 contact_key text; first_send jsonb; second_send jsonb; claim jsonb;
 rejection text; i integer;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Ticket resend budget') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(actor),(outsider);
 FOR i IN 1..4 LOOP
  IF i<>2 THEN
   INSERT INTO public.units(title,organization) VALUES('Resend organizer',org) RETURNING id INTO organizer;
  END IF;
  INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled,features)
  VALUES('Ticket resend',org,organizer,gen_random_uuid()::text,now(),now()+interval '1 day',true,'[{"code":"ticket","is_enabled":true}]')
  RETURNING id INTO event_id;
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(event_id,actor,true);
  INSERT INTO eshop.orders(occasion,order_symbol,order_sequence,state,data,price,currency_code)
  VALUES(event_id,public.generate_order_symbol(),public.next_order_sequence(event_id),'paid',jsonb_build_object('email',contact),100,'CZK')
  RETURNING id INTO fixture_order;
  INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(event_id,'paid',public.generate_ticket_symbol(org,event_id)) RETURNING id INTO ticket_id;
  INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(fixture_order,ticket_id);
  IF i<>3 THEN
   PERFORM public.enqueue_paid_order_tickets(fixture_order);
   UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now() WHERE order_id=fixture_order;
  END IF;
  organizers:=array_append(organizers,organizer);
  events:=array_append(events,event_id);
  fixture_orders:=array_append(fixture_orders,fixture_order);
 END LOOP;
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.ticket_resend.recipient.unit.day';
 UPDATE public.abuse_policy_rules SET base_limit=2 WHERE rule_key='email.ticket_resend.recipient.global.day';
 contact_key:=public.abuse_recipient_key_v1(contact);
 INSERT INTO public.abuse_budget_usage(rule_key,scope_id,bucket_at,amount,expires_at)
 SELECT key,identity,date_trunc('hour',now()),20,date_trunc('hour',now())+interval '25 hours'
 FROM (VALUES
  ('email.ordinary.recipient.day',contact_key),
  ('email.send.ordinary.recipient.day',contact_key),
  ('email.ordinary.recipient.day',public.abuse_recipient_key_v1('other-recipient@example.invalid'))
 ) v(key,identity);

 SET LOCAL ROLE service_role;
 first_send:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',fixture_orders[1],'requested_by',actor),
   org,events[1],organizers[1],now(),'resend:organizer-one');
 IF first_send->>'state' IS DISTINCT FROM 'pending' THEN RAISE EXCEPTION 'Ordinary traffic must leave the authorized resend available'; END IF;
 IF public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',fixture_orders[1],'requested_by',actor),
   org,events[1],organizers[1],now(),'resend:organizer-one')->>'message_id' IS DISTINCT FROM first_send->>'message_id'
 THEN RAISE EXCEPTION 'Retry must join the same message'; END IF;
 BEGIN
  PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',fixture_orders[2],'requested_by',actor),
   org,events[2],organizers[2],now(),'resend:same-organizer-other-event');
  RAISE EXCEPTION 'New event bypassed the organizer recipient limit';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS rejection=PG_EXCEPTION_DETAIL;
  IF rejection::jsonb->>'ruleKey' IS DISTINCT FROM 'email.ticket_resend.recipient.unit.day' THEN RAISE; END IF;
 END;
 FOR i IN 1..2 LOOP
  BEGIN
   PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',fixture_orders[3],'requested_by',CASE WHEN i=1 THEN outsider ELSE actor END)
    ||CASE WHEN i=2 THEN '{"recipient":"other-recipient@example.invalid","manual":true}'::jsonb ELSE '{}'::jsonb END,
    org,events[3],organizers[3],now(),'resend:unqualified-'||i);
   RAISE EXCEPTION 'Unqualified resend used the special budget';
  EXCEPTION WHEN SQLSTATE 'PT429' THEN
   GET STACKED DIAGNOSTICS rejection=PG_EXCEPTION_DETAIL;
   IF rejection::jsonb->>'ruleKey' IS DISTINCT FROM 'email.ordinary.recipient.day' THEN RAISE; END IF;
  END;
 END LOOP;
 second_send:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',fixture_orders[3],'requested_by',actor),
   org,events[3],organizers[3],now(),'resend:organizer-two');
 IF second_send->>'state' IS DISTINCT FROM 'pending' THEN RAISE EXCEPTION 'The first manual send for another organizer should retain capacity'; END IF;
 BEGIN
  PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',fixture_orders[4],'requested_by',actor),
   org,events[4],organizers[4],now(),'resend:organizer-three');
  RAISE EXCEPTION 'Separate organizers bypassed the platform recipient limit';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS rejection=PG_EXCEPTION_DETAIL;
  IF rejection::jsonb->>'ruleKey' IS DISTINCT FROM 'email.ticket_resend.recipient.global.day' THEN RAISE; END IF;
 END;
 RESET ROLE;

 IF (SELECT sum(amount) FROM public.abuse_budget_usage WHERE scope_id=actor::text AND rule_key='email.actor.day') IS DISTINCT FROM 2::numeric
 THEN RAISE EXCEPTION 'An admitted resend charges the actual editor exactly once'; END IF;
 IF (SELECT sum(amount) FROM public.abuse_budget_usage WHERE scope_id=org::text AND rule_key='email.ordinary.organization.day') IS DISTINCT FROM 2::numeric
 THEN RAISE EXCEPTION 'Reserve admissions still charge the ordinary organization budget'; END IF;
 UPDATE public.email_capacity SET paused=false,shared_account=false,daily_quota=100,provider_sent_24h=0,max_rate=100,
  rate_factor=1,max_sending=2,max_preparing=2,quota_at=now(),next_send_at=now(),circuit_until=NULL,provider_outage_streak=0,probe_until=NULL;
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.send.ticket_resend.recipient.global.day';
 UPDATE public.email_messages SET target_time=now()+interval '1 hour' WHERE message_id=(second_send->>'message_id')::uuid;
 FOR i IN 1..3 LOOP
  IF i=3 THEN DELETE FROM public.occasion_users WHERE occasion=events[3] AND "user"=actor; END IF;
  claim:=public.claim_email();
  IF claim->>'message_id' IS DISTINCT FROM (CASE WHEN i=1 THEN first_send->>'message_id' ELSE second_send->>'message_id' END)
  THEN RAISE EXCEPTION 'Unexpected claim'; END IF;
  PERFORM public.prepare_email((claim->>'message_id')::uuid,(claim->>'lease_token')::uuid,'{"ciphertext":"fixture"}',
   jsonb_build_object('wallet_fingerprint',public.ticket_wallet_fingerprint((claim->>'occasion')::bigint)));
  IF i=1 THEN
   IF public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid)->>'disposition' IS DISTINCT FROM 'send'
   THEN RAISE EXCEPTION 'Authorized resend should reach the sender even when ordinary sending is full'; END IF;
   IF public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid)->>'disposition' IS DISTINCT FROM 'replay'
   THEN RAISE EXCEPTION 'Worker replay should reuse the send attempt'; END IF;
   PERFORM public.finish_email_attempt((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid,'accepted','resend-fixture-provider');
   UPDATE public.email_capacity SET next_send_at=now();
  ELSE
   IF public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid)->>'disposition' IS DISTINCT FROM 'deferred'
   THEN RAISE EXCEPTION 'The actual sender must honor the global resend cap and fall back to ordinary limits after revocation'; END IF;
   UPDATE public.abuse_policy_rules SET base_limit=12 WHERE rule_key='email.send.ticket_resend.recipient.global.day';
  END IF;
  IF i<3 THEN UPDATE public.email_messages SET target_time=now() WHERE message_id=(second_send->>'message_id')::uuid; END IF;
 END LOOP;
 IF (SELECT sum(amount) FROM public.abuse_budget_usage WHERE scope_id=contact_key AND rule_key='email.send.ticket_resend.recipient.global.day') IS DISTINCT FROM 1::numeric
 THEN RAISE EXCEPTION 'Only the actual authorized send should consume the dedicated send budget'; END IF;

 UPDATE eshop.orders SET data=jsonb_set(data,'{email}','"normal-resend-capacity@example.invalid"') WHERE id=fixture_orders[4];
 PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',fixture_orders[4],'requested_by',actor),
   org,events[4],organizers[4],now(),'resend:ordinary-capacity-available');
 IF NOT EXISTS (
   SELECT 1 FROM public.abuse_budget_usage
   WHERE scope_id=public.abuse_recipient_key_v1('normal-resend-capacity@example.invalid')
    AND rule_key='email.ordinary.recipient.day' AND amount=1
 ) OR EXISTS (
   SELECT 1 FROM public.abuse_budget_usage
   WHERE scope_id=public.abuse_recipient_key_v1('normal-resend-capacity@example.invalid')
    AND rule_key='email.ticket_resend.recipient.global.day'
 ) THEN RAISE EXCEPTION 'Resends with ordinary capacity must preserve their reserve'; END IF;
 RAISE NOTICE 'PASS organizer and recipient admission, worker gate, editor revocation and exact replay';
END $$;
ROLLBACK;
