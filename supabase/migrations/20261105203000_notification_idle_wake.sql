-- Generated forward migration: notification-idle-wake-2026-11-05
-- Prerequisites: 20261021100000_canonical_authorization.sql, 20261024010000_organization_notification_center.sql, 20261024025000_notification_email_recipient.sql, 20261024120000_order_email_recovery.sql, 20261024220000_cancelled_order_email_alerts.sql, 20261024235000_notification_center_canonical_availability.sql, 20261026120000_notification_center_feed.sql, 20261026150000_notification_center_order_periods.sql, 20261026230000_notification_center_unread_snapshot.sql, 20261027210000_notification_center_overview.sql, 20261027220000_notification_center_daily_overview.sql, 20261027234500_notification_group_order_selection.sql, 20261028010000_notification_legacy_place_totals.sql, 20261028013000_notification_category_rollups.sql, 20261028020000_notification_center_lifecycle.sql, 20261028030000_notification_new_orders_exclude_cancelled.sql, 20261028120000_notification_center_current_rollups.sql, 20261028130000_notification_personal_read_batches.sql, 20261030093000_notification_deleted_entities.sql, 20261031110000_notification_current_participants.sql, 20261031120000_notification_center_source_alignment.sql, 20261101170000_hidden_participant_notifications.sql, 20261105070000_notification_subject_lookup_performance.sql, 20261105110000_notification_center_delivery_draining.sql, 20261105120000_notification_center_prepared_views.sql, 20261105181000_notification_prepared_retention.sql, 20261105190000_notification_prepared_scope_discovery.sql
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regprocedure('public.get_notification_center_updates(bigint,bigint,uuid[])') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;

-- SOURCE: notification_center/prepared_wake.sql
-- pg_net publishes only after the surrounding domain transaction commits.
-- This is a coalesced synchronization hint, never a second business queue.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_wake()
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE url text;
BEGIN
 IF current_setting('festapp.notification_wake',true)='scheduled' THEN RETURN; END IF;
 UPDATE public.notification_center_maintenance SET next_at=clock_timestamp()+interval '1 second',wake_error=NULL
 WHERE name='delivery-wake' AND worker_url IS NOT NULL AND next_at<=clock_timestamp()
  AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='delivery-wake' FOR UPDATE SKIP LOCKED)
 RETURNING worker_url INTO url;
 IF url IS NULL THEN RETURN; END IF;
 PERFORM set_config('festapp.notification_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  UPDATE public.notification_center_maintenance SET wake_error='wake_failed' WHERE name='delivery-wake'
   AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='delivery-wake' FOR UPDATE SKIP LOCKED);
 END;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_prepared_wake() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.wake_notification_center()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 -- The one-second safety tick discovers durable work; it must not create an
 -- HTTP request when idle. Domain commits retain their unconditional fast wake.
 -- Keep existing views eligible so live privacy/read repair and expiry cleanup
 -- are never delayed by this scheduler optimization.
 IF EXISTS(SELECT 1 FROM public.notification_center_events WHERE projected_revision<attention_revision)
  OR EXISTS(SELECT 1 FROM public.notification_center_projection_scopes WHERE next_check_at<=clock_timestamp() AND NOT quarantined)
  OR EXISTS(SELECT 1 FROM public.notification_center_views) THEN
  PERFORM public.notification_center_prepared_wake();
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.wake_notification_center() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_notification_center() TO service_role;
CREATE OR REPLACE FUNCTION public.configure_notification_center_worker(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 IF p_project_url IS NULL OR p_project_url !~ '^https?://[^/?#[:space:]]+/?$' THEN RAISE invalid_parameter_value USING MESSAGE='notification_worker_origin_required'; END IF;
 INSERT INTO public.notification_center_maintenance(name,worker_url) VALUES('delivery-wake',rtrim(p_project_url,'/')||'/functions/v1/process-notification-center')
 ON CONFLICT(name) DO UPDATE SET worker_url=excluded.worker_url,next_at='-infinity',wake_error=NULL;
END $$;
REVOKE ALL ON FUNCTION public.configure_notification_center_worker(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_notification_center_worker(text) TO service_role;

COMMIT;
