-- test-setup: database/tests/helpers/admin_email_fixture.sql
BEGIN;
DO $$
DECLARE fx jsonb; u uuid; org bigint; oc bigint; dispatch uuid;
BEGIN
 fx:=pg_temp.admin_email_fixture();u:=(fx->>'user')::uuid;org:=(fx->>'organization')::bigint;
 SELECT id INTO oc FROM public.occasions WHERE organization=org LIMIT 1;
 -- Transaction-local mutation proves all three consumers use the policy owner,
 -- rather than merely agreeing on duplicated literals. Never a runtime setting.
 EXECUTE $ddl$CREATE OR REPLACE FUNCTION public.notification_center_email_window_internal()
 RETURNS interval LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $policy$
 SELECT interval '600 seconds';
 $policy$;$ddl$;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','policy-probe','{"count":1,"formContext":{"allowsMultiple":false}}');
 PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 SELECT id INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=u AND state='collecting';
 PERFORM assert_eq((SELECT extract(epoch FROM due_at-opened_at)::integer FROM public.notification_center_email_dispatches WHERE id=dispatch),600,'collector uses the sole interval policy');
 PERFORM assert_eq((public.notification_center_email_settings_internal(org)->>'windowSeconds')::integer,600,'settings project the same policy into the UI');
 BEGIN
  UPDATE public.notification_center_email_dispatches SET due_at=opened_at+interval '300 seconds' WHERE id=dispatch;
  RAISE EXCEPTION 'duplicated deadline literal accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM assert_false(has_function_privilege('authenticated','public.notification_center_email_window_internal()','EXECUTE'),'policy owner remains private');
END $$;
ROLLBACK;
