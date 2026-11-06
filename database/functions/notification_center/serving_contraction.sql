-- Retire obsolete admin-center serving only. Mobile news/push delivery is unchanged.
-- Explicit signatures, no CASCADE and no receipt/baseline/data deletion.
DROP FUNCTION IF EXISTS public.get_notification_center_badge(bigint);
DROP FUNCTION IF EXISTS public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamp with time zone,text,jsonb,integer,text[],boolean);
DROP FUNCTION IF EXISTS public.get_notification_center_feed(bigint,bigint,bigint,jsonb,integer);
DROP FUNCTION IF EXISTS public.get_notification_center_group(bigint,text,bigint,bigint,integer);
DROP FUNCTION IF EXISTS public.get_notification_center_overview(bigint,bigint,bigint,jsonb,integer,text[]);
DROP FUNCTION IF EXISTS public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb);
DROP FUNCTION IF EXISTS public.get_notification_center_timeline(bigint,bigint,bigint,timestamp with time zone,jsonb,jsonb,integer);
DROP FUNCTION IF EXISTS public.get_notification_center_timeline_group(bigint,bigint,bigint,timestamp with time zone,bigint,jsonb,jsonb,integer);
DROP FUNCTION IF EXISTS public.get_notification_center_timeline_group_updates(bigint,bigint,bigint,timestamp with time zone,jsonb);
DROP FUNCTION IF EXISTS public.get_notification_center_updates(bigint,bigint,uuid[]);
DROP FUNCTION IF EXISTS public.mark_notification_center_item_read(bigint,jsonb);
DROP FUNCTION IF EXISTS public.open_notification_center(bigint,bigint,integer);
DROP FUNCTION IF EXISTS public.notification_center_periods_internal(jsonb,timestamp with time zone);
DROP FUNCTION IF EXISTS public.notification_center_rollup_id_internal(text);
DROP FUNCTION IF EXISTS public.notification_center_time_cursor_internal(jsonb,text);
DROP FUNCTION IF EXISTS public.notification_center_visible_internal(bigint,bigint,bigint);
