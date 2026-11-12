-- test-setup: database/tests/helpers/admin_email_fixture.sql
BEGIN;
DO $$
DECLARE fx jsonb; u uuid; org bigint; oc bigint; dispatch uuid; message uuid; claim jsonb; context jsonb; outcome jsonb;
BEGIN
 fx:=pg_temp.admin_email_fixture();u:=(fx->>'user')::uuid;org:=(fx->>'organization')::bigint;
 dispatch:=(fx->>'dispatch')::uuid;message:=(fx->>'message')::uuid;
 SELECT id INTO oc FROM public.occasions WHERE organization=org LIMIT 1;
 UPDATE public.email_messages SET target_time='infinity' WHERE message_id<>message;
 UPDATE public.email_capacity SET paused=false,shared_account=false,quota_at=now(),max_rate=100,daily_quota=100000,
  provider_sent_24h=0,next_send_at=now(),circuit_until=NULL,probe_until=NULL,provider_outage_streak=0;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 FOR j IN 1..21 LOOP
  -- Simulate passage of the five-minute burst windows in stored fixture time;
  -- every rolling 24-hour intent/send charge stays intact for the same UUID.
  UPDATE public.abuse_budget_usage SET bucket_at=now()-make_interval(secs=>j*300),expires_at=now()-interval '1 second'
   WHERE scope_id=u::text AND rule_key IN ('email.notification.recipient.burst','email.send.notification.recipient.burst','email.notification.prepare.recipient.burst')
    AND bucket_at>now()-interval '2 minutes';
  UPDATE public.email_capacity SET next_send_at=now();
  claim:=public.claim_email();
  PERFORM assert_eq(claim->>'message_id',message::text,'each iteration claims the real recipient intent');
  context:=public.notification_center_email_context_internal(dispatch,u);
  PERFORM public.prepare_email(message,(claim->>'lease_token')::uuid,'{"sealed":"fake-provider-boundary"}',jsonb_build_object('notification_fingerprint',context->>'fingerprint'));
  outcome:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
  PERFORM assert_eq(outcome->>'disposition','send','notification permits remain available beyond ordinary 20/day');
  PERFORM public.finish_email_attempt((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid,'accepted','budget-fixture-'||j||'-'||u);
  IF j=21 THEN EXIT; END IF;
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','budget:'||j,'{"count":1,"formContext":{"allowsMultiple":false}}');
  PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
  SELECT id INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=u AND state='collecting';
  UPDATE public.notification_center_email_dispatches SET opened_at=opened_at-interval '301 seconds',due_at=due_at-interval '301 seconds' WHERE id=dispatch;
  PERFORM public.enqueue_notification_center_emails(100);
  SELECT message_id INTO message FROM public.notification_center_email_dispatches WHERE id=dispatch;
 END LOOP;
 PERFORM assert_eq((SELECT count(*) FROM public.email_attempts a JOIN public.email_messages m USING(message_id)
  WHERE m.recipient_user=u AND a.state='accepted'),21::bigint,'21 actual queue send permits for one canonical recipient');
 PERFORM assert_eq((SELECT base_limit FROM public.abuse_policy_rules WHERE rule_key='email.send.ordinary.recipient.day'),20::bigint,'ordinary class limit unchanged');
 PERFORM assert_eq((SELECT coalesce(sum(amount),0) FROM public.abuse_budget_usage WHERE rule_key='email.send.notification.recipient.day' AND scope_id=u::text),21::numeric,'rolling daily send accounting is preserved across the simulated burst windows');
END $$;
ROLLBACK;
