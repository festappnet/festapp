BEGIN;
-- Intercept dispatch only inside this disposable, rolled-back transaction.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_wake()
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM set_config('festapp_test.wake_calls',
  (coalesce(nullif(current_setting('festapp_test.wake_calls',true),''),'0')::integer+1)::text,true);
END $$;
DO $$
DECLARE org bigint; actor uuid:=gen_random_uuid(); ev uuid;
BEGIN
 DELETE FROM public.notification_center_views;
 DELETE FROM public.notification_center_projection_scopes;
 DELETE FROM public.notification_center_events;
 PERFORM set_config('festapp_test.wake_calls','0',true);
 PERFORM public.wake_notification_center();
 PERFORM assert_eq(current_setting('festapp_test.wake_calls'),'0','idle safety tick must not dispatch HTTP');
 INSERT INTO public.organizations(title) VALUES('Pořadatel plesu') RETURNING id INTO org;
 INSERT INTO public.notification_center_events(organization,kind,source_key,occurred_at)
 VALUES(org,'order_created','idle-wake-test',clock_timestamp()) RETURNING id INTO ev;
 PERFORM set_config('festapp_test.wake_calls','0',true);
 PERFORM public.wake_notification_center();
 PERFORM assert_eq(current_setting('festapp_test.wake_calls'),'1','pending delivery retains one-second safety wake');
 UPDATE public.notification_center_events SET projected_revision=attention_revision WHERE id=ev;
 INSERT INTO public.notification_center_projection_scopes(organization,recipient,next_check_at)
 VALUES(org,actor,clock_timestamp()+interval '1 hour');
 PERFORM set_config('festapp_test.wake_calls','0',true);
 PERFORM public.wake_notification_center();
 PERFORM assert_eq(current_setting('festapp_test.wake_calls'),'0','future retry does not dispatch early');
 UPDATE public.notification_center_projection_scopes SET next_check_at='-infinity' WHERE organization=org;
 PERFORM public.wake_notification_center();
 PERFORM assert_eq(current_setting('festapp_test.wake_calls'),'1','due prepared work dispatches');
 UPDATE public.notification_center_projection_scopes SET quarantined=true WHERE organization=org;
 PERFORM set_config('festapp_test.wake_calls','0',true);
 PERFORM public.wake_notification_center();
 PERFORM assert_eq(current_setting('festapp_test.wake_calls'),'0','quarantined scope does not create idle traffic');
 INSERT INTO public.notification_center_views(organization,recipient,timezone,snapshot,anchor,previous_seen,source_revision,read_revision,privacy_key)
 VALUES(org,actor,'Europe/Prague',0,now(),0,0,0,'test');
 PERFORM public.wake_notification_center();
 PERFORM assert_eq(current_setting('festapp_test.wake_calls'),'1','existing view retains repair and expiry scheduling');
 DELETE FROM public.notification_center_views;
 PERFORM set_config('festapp_test.wake_calls','0',true);
 PERFORM public.notification_center_prepared_wake();
 PERFORM assert_eq(current_setting('festapp_test.wake_calls'),'1','domain fast wake remains unconditional');
END $$;
ROLLBACK;
