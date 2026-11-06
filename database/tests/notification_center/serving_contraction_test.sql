BEGIN;
DO $$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'public.get_notification_center_badge(bigint)',
  'public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamp with time zone,text,jsonb,integer,text[],boolean)',
  'public.get_notification_center_feed(bigint,bigint,bigint,jsonb,integer)',
  'public.get_notification_center_group(bigint,text,bigint,bigint,integer)',
  'public.get_notification_center_overview(bigint,bigint,bigint,jsonb,integer,text[])',
  'public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb)',
  'public.get_notification_center_timeline(bigint,bigint,bigint,timestamp with time zone,jsonb,jsonb,integer)',
  'public.get_notification_center_timeline_group(bigint,bigint,bigint,timestamp with time zone,bigint,jsonb,jsonb,integer)',
  'public.get_notification_center_timeline_group_updates(bigint,bigint,bigint,timestamp with time zone,jsonb)',
  'public.get_notification_center_updates(bigint,bigint,uuid[])',
  'public.mark_notification_center_item_read(bigint,jsonb)',
  'public.open_notification_center(bigint,bigint,integer)',
  'public.notification_center_periods_internal(jsonb,timestamp with time zone)',
  'public.notification_center_rollup_id_internal(text)',
  'public.notification_center_time_cursor_internal(jsonb,text)',
  'public.notification_center_visible_internal(bigint,bigint,bigint)'] LOOP
  PERFORM assert_true(to_regprocedure(signature) IS NULL,'retired signature remains absent: '||signature);
 END LOOP;
END $$;
ROLLBACK;
