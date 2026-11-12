-- test-setup: database/tests/helpers/admin_email_fixture.sql
BEGIN;
DO $$
DECLARE fx jsonb; u uuid; org bigint; oc bigint; dispatch uuid; result jsonb;
BEGIN
 fx:=pg_temp.admin_email_fixture();u:=(fx->>'user')::uuid;org:=(fx->>'organization')::bigint;
 UPDATE public.email_messages SET workflow_state='accepted' WHERE message_id=(fx->>'message')::uuid;
 SELECT id INTO oc FROM public.occasions WHERE organization=org LIMIT 1;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','no-address-new-event','{"count":1,"formContext":{"allowsMultiple":false}}');
 PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 UPDATE public.user_info SET email_delivery=NULL,email_readonly=NULL WHERE id=u;
 SELECT id INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=u AND state='collecting';
 UPDATE public.notification_center_email_dispatches SET opened_at=opened_at-interval '301 seconds',due_at=due_at-interval '301 seconds' WHERE id=dispatch;
 PERFORM assert_eq(public.enqueue_notification_center_emails(100),0,'missing address retains the existing collecting envelope');
 PERFORM assert_true((SELECT next_attempt_at>now()+interval '4 minutes' FROM public.notification_center_email_dispatches WHERE id=dispatch),'no-address recheck is bounded, not an idle wake loop');
 result:=public.notification_center_email_settings_internal(org);
 PERFORM assert_eq(result->>'state','no_address','self settings explain the missing address');
 UPDATE public.user_info SET email_delivery='new@example.test' WHERE id=u;
 UPDATE public.notification_center_email_dispatches SET next_attempt_at=now() WHERE id=dispatch;
 PERFORM assert_eq(public.enqueue_notification_center_emails(100),1,'first enqueue uses the newly available canonical address');
 PERFORM assert_eq((SELECT recipient FROM public.email_messages WHERE notification_dispatch_id=dispatch),'new@example.test','address is captured only in the original queue intent');
END $$;
ROLLBACK;
