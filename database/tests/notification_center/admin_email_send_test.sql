-- test-setup: database/tests/helpers/admin_email_fixture.sql
BEGIN;
DO $$
DECLARE fixture jsonb; u uuid; dispatch uuid; message uuid; claim jsonb; snapshot jsonb; outcome jsonb; used bigint; rules jsonb; recipient_scopes jsonb;
BEGIN
 fixture:=pg_temp.admin_email_fixture();u:=(fixture->>'user')::uuid;dispatch:=(fixture->>'dispatch')::uuid;message:=(fixture->>'message')::uuid;
 UPDATE public.email_messages SET target_time='infinity' WHERE message_id<>message;
 UPDATE public.email_capacity SET paused=false,quota_at=now(),shared_account=false,max_rate=100,daily_quota=100000,provider_sent_24h=0,next_send_at='-infinity',circuit_until=NULL,probe_until=NULL;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 claim:=public.claim_email();
 PERFORM assert_eq(claim->>'message_id',message::text,'the real queue claims the digest');
 snapshot:=public.notification_center_email_context_internal(dispatch,u);
 PERFORM public.prepare_email(message,(claim->>'lease_token')::uuid,'{"sealed":"fake-transport-boundary"}',jsonb_build_object('notification_fingerprint',snapshot->>'fingerprint'));
 -- Revocation after preparation must invalidate all of A, including its headings.
 DELETE FROM public.occasion_users WHERE "user"=u AND occasion IN(SELECT id FROM public.occasions WHERE organization=(fixture->>'organization')::bigint);
 SELECT coalesce(sum(amount),0) INTO used FROM public.abuse_budget_usage WHERE rule_key LIKE 'email.send.notification%';
 outcome:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(outcome->>'disposition','deferred','old authorized snapshot cannot get a permit');
 PERFORM assert_eq((SELECT coalesce(sum(amount),0)::bigint FROM public.abuse_budget_usage WHERE rule_key LIKE 'email.send.notification%'),used,'stale snapshot rolls back send metering');
 PERFORM assert_true((SELECT prepared IS NULL AND workflow_state='pending' FROM public.email_messages WHERE message_id=message),'same intent returns to preparation');
 snapshot:=public.notification_center_email_context_internal(dispatch,u);
 PERFORM assert_eq(jsonb_array_length(snapshot->'items'),1,'only remaining authorized source survives');
 claim:=public.claim_email();
 PERFORM public.prepare_email(message,(claim->>'lease_token')::uuid,'{"sealed":"updated-authorized-content"}',jsonb_build_object('notification_fingerprint',snapshot->>'fingerprint'));
 outcome:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(outcome->>'disposition','send','fresh authorized snapshot receives the sole send permit');
 outcome:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(outcome->>'disposition','replay','same provider attempt never gets another permit');
 PERFORM public.finish_email_attempt((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid,'accepted','fake-provider-id');
 PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE message_id=message),'accepted','existing queue owns transport result');
 -- A changed destination cancels the immutable intent and cannot create a replacement.
 fixture:=pg_temp.admin_email_fixture();u:=(fixture->>'user')::uuid;message:=(fixture->>'message')::uuid;
 UPDATE public.email_messages SET target_time='infinity' WHERE message_id<>message;
 UPDATE public.user_info SET email_delivery='changed@example.test' WHERE id=u;
 claim:=public.claim_email();
 PERFORM assert_true((claim->>'skipped')::boolean,'destination change is terminal before rendering');
 PERFORM assert_eq((SELECT last_error FROM public.email_messages WHERE message_id=message),'destination_changed','explicit destination disposition');
 PERFORM assert_eq(public.enqueue_notification_center_emails(100),0,'destination change never creates replacement');
 -- An address change after preparation has the same terminal outcome.
 fixture:=pg_temp.admin_email_fixture();u:=(fixture->>'user')::uuid;message:=(fixture->>'message')::uuid;dispatch:=(fixture->>'dispatch')::uuid;
 UPDATE public.email_messages SET target_time='infinity' WHERE message_id<>message;
 claim:=public.claim_email();snapshot:=public.notification_center_email_context_internal(dispatch,u);
 PERFORM public.prepare_email(message,(claim->>'lease_token')::uuid,'{"sealed":"prepared-before-address-change"}',jsonb_build_object('notification_fingerprint',snapshot->>'fingerprint'));
 UPDATE public.user_info SET email_delivery='after-preparation@example.test' WHERE id=u;
 outcome:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(outcome->>'disposition','cancelled','destination change after preparation cannot receive a permit');
 PERFORM assert_eq((SELECT last_error FROM public.email_messages WHERE message_id=message),'destination_changed','destination change retains its explicit reason at permit time');
 fixture:=pg_temp.admin_email_fixture();u:=(fixture->>'user')::uuid;message:=(fixture->>'message')::uuid;dispatch:=(fixture->>'dispatch')::uuid;
 UPDATE public.email_messages SET target_time='infinity' WHERE message_id<>message;
 claim:=public.claim_email();snapshot:=public.notification_center_email_context_internal(dispatch,u);
 PERFORM public.prepare_email(message,(claim->>'lease_token')::uuid,'{"sealed":"prepared-before-opt-out"}',jsonb_build_object('notification_fingerprint',snapshot->>'fingerprint'));
 UPDATE public.notification_center_email_profiles SET stopped=true,revision=revision+1 WHERE recipient=u;
 outcome:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(outcome->>'disposition','cancelled','global opt-out after preparation cannot receive a permit');
 -- Notification sends do not inherit the ordinary 20/day ceiling. Same backend.
 rules:=public.abuse_effective_rules_v1('email.send.notification',NULL,NULL);
 recipient_scopes:=jsonb_build_object('recipient',u,'global','all');

 PERFORM assert_eq((SELECT base_limit FROM public.abuse_policy_rules WHERE rule_key='email.send.ordinary.recipient.day'),20::bigint,'ordinary send ceiling unchanged');
 PERFORM assert_eq((SELECT base_limit FROM public.abuse_policy_rules WHERE rule_key='email.send.notification.recipient.day'),288::bigint,'notification rolling day supports fixed five-minute delivery');
 DELETE FROM public.abuse_policy_rules WHERE rule_key='email.send.notification.global.day';
 BEGIN PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.notification',NULL,NULL),recipient_scopes);RAISE EXCEPTION 'expected missing policy rejection';
 EXCEPTION WHEN configuration_limit_exceeded THEN NULL; END;
END $$;
ROLLBACK;
