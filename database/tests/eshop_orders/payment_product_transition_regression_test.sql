-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Target contract. Expected to fail on the pre-unification implementation.
-- Keep failures visible; do not bless inconsistent states as characterization.
DO $$
DECLARE x jsonb; oid bigint; ticket bigint; initial_state text; errors text[]:='{}';
 history_before jsonb; identity_before jsonb; version_before bigint; mid uuid;
BEGIN
 BEGIN
  x:=pg_temp.payment_attach_spot(pg_temp.payment_fixture(300)); oid:=(x->>'order')::bigint;
  PERFORM pg_temp.payment_pair(x,300);
  PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'deposit baseline is paid');
  history_before:=pg_temp.payment_history(oid); identity_before:=pg_temp.payment_identity(x);
  SELECT email_payment_version INTO version_before FROM eshop.orders WHERE id=oid;
  PERFORM pg_temp.payment_edit(x,1100);
  PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,
   'product edit must preserve paid deposit eligibility');
  PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'paid'::text,
   'deposit-paid ticket remains eligible');
  PERFORM pg_temp.payment_assert_edit_history(x,history_before,'paid',1100);
  PERFORM assert_eq(pg_temp.payment_identity(x),identity_before,'deposit edit preserves ticket/OPT/seat identity');
  PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),version_before+1,'deposit edit invalidates email content exactly once');
  PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets'
   AND source_version=version_before+1),1::bigint,'deposit edit creates one final-version ticket intent');
 EXCEPTION WHEN OTHERS THEN errors:=array_append(errors,'deposit edit: '||SQLERRM); END;
 FOREACH initial_state IN ARRAY ARRAY['paid','sent'] LOOP
  BEGIN
   x:=pg_temp.payment_attach_spot(pg_temp.payment_fixture()); oid:=(x->>'order')::bigint; ticket:=(x->>'ticket')::bigint;
   PERFORM pg_temp.payment_pair(x,1000);
   IF initial_state='sent' THEN PERFORM pg_temp.payment_accept_tickets(x); END IF;
   PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),initial_state,'price-rise baseline');
   history_before:=pg_temp.payment_history(oid); identity_before:=pg_temp.payment_identity(x);
  SELECT email_payment_version INTO version_before FROM eshop.orders WHERE id=oid;
  SELECT message_id INTO STRICT mid FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets'
   AND source_version=version_before;
  PERFORM pg_temp.payment_edit(x,1100);
   PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered'::text,'price rise creates a balance due');
   PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),'ordered'::text,
    'price rise must revoke unpaid admission consistently with bank unpairing');
   PERFORM pg_temp.payment_assert_edit_history(x,history_before,'ordered',1100);
   PERFORM assert_eq(pg_temp.payment_identity(x),identity_before,'price rise preserves ticket/OPT/seat identity');
   PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),version_before+1,'debt edit invalidates old email exactly once');
   PERFORM set_config('request.jwt.claim.role','service_role',true);
   PERFORM assert_false((SELECT public.email_intent_valid(m) FROM public.email_messages m WHERE message_id=mid),'old ticket source version is no longer valid');
   PERFORM set_config('request.jwt.claim.role','authenticated',true);
   PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets'
    AND source_version=version_before+1),0::bigint,'unpaid edit creates no new ticket delivery');
   history_before:=pg_temp.payment_history(oid);
   UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now(),post_action_state='pending',
    post_action=jsonb_build_object('ticket_ids',jsonb_build_array(ticket)) WHERE message_id=mid;
   PERFORM set_config('request.jwt.claim.role','service_role',true);
   PERFORM public.apply_email_post_actions(mid);
   PERFORM set_config('request.jwt.claim.role','authenticated',true);
   PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered'::text,'late acceptance after price edit cannot restore order');
   PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),'ordered'::text,'late acceptance after price edit cannot restore ticket');
   PERFORM assert_eq(pg_temp.payment_history(oid),history_before,'late acceptance after price edit adds no false sent snapshot');
  EXCEPTION WHEN OTHERS THEN errors:=array_append(errors,initial_state||' price rise: '||SQLERRM); END;
 END LOOP;
 IF cardinality(errors)>0 THEN RAISE EXCEPTION 'Payment transition regressions: %',array_to_string(errors,E'\n'); END IF;
END $$;
