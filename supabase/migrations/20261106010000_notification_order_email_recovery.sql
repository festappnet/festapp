-- Generated forward migration: notification-order-email-recovery-2026-11-06
-- Prerequisites: 20261021100000_canonical_authorization.sql, 20261024010000_organization_notification_center.sql, 20261024025000_notification_email_recipient.sql, 20261024120000_order_email_recovery.sql, 20261024220000_cancelled_order_email_alerts.sql, 20261024235000_notification_center_canonical_availability.sql, 20261026120000_notification_center_feed.sql, 20261026150000_notification_center_order_periods.sql, 20261026230000_notification_center_unread_snapshot.sql, 20261027210000_notification_center_overview.sql, 20261027220000_notification_center_daily_overview.sql, 20261027234500_notification_group_order_selection.sql, 20261028010000_notification_legacy_place_totals.sql, 20261028013000_notification_category_rollups.sql, 20261028020000_notification_center_lifecycle.sql, 20261028030000_notification_new_orders_exclude_cancelled.sql, 20261028120000_notification_center_current_rollups.sql, 20261028130000_notification_personal_read_batches.sql, 20261030093000_notification_deleted_entities.sql, 20261031110000_notification_current_participants.sql, 20261031120000_notification_center_source_alignment.sql, 20261101170000_hidden_participant_notifications.sql, 20261105070000_notification_subject_lookup_performance.sql, 20261105110000_notification_center_delivery_draining.sql, 20261105120000_notification_center_prepared_views.sql, 20261105181000_notification_prepared_retention.sql, 20261105190000_notification_prepared_scope_discovery.sql, 20261105203000_notification_idle_wake.sql, 20261105213000_notification_open_work.sql, 20261105230000_notification_read_history_compaction.sql, 20261105233000_notification_order_visibility.sql
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regprocedure('public.get_notification_center_updates(bigint,bigint,uuid[])') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;

-- SOURCE: notification_center/email.sql
-- Reuse the order reporting authority: successful repair chains and delivered
-- current tickets can resolve a different, older message's incident.
CREATE OR REPLACE FUNCTION public.notification_center_reconcile_order_email_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE issues jsonb; event_id uuid;
BEGIN
 IF p_order IS NULL THEN RETURN; END IF;
 issues:=public.order_email_current_issues(p_order);
 FOR event_id IN
  SELECT e.id FROM public.email_messages m
  JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion AND o.state<>'storno'
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=m.organization
  JOIN public.notification_center_events e ON e.organization=m.organization AND e.source_key='email:'||m.message_id
  WHERE m.order_id=p_order AND m.message_kind IN ('order_confirmation','order_tickets')
   AND e.kind='email_problem' AND e.status='active'
   AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(issues) issue
    WHERE issue->>'source_message_id'=m.message_id::text OR issue->>'message_id'=m.message_id::text)
 LOOP
  PERFORM public.notification_center_prepared_invalidate(event_id);
  UPDATE public.notification_center_events SET status='recovered' WHERE id=event_id;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_reconcile_order_email_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.notification_center_email_internal(p_message uuid,p_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; a public.notification_center_organizations; old public.notification_center_source_state;
 reason text; fact_at timestamptz; ev uuid; seen jsonb; key text:='email:'||p_message; due_at timestamptz;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF NOT FOUND THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||m.organization,0));
 p_at:=coalesce(p_at,clock_timestamp());
 SELECT * INTO a FROM public.notification_center_organizations WHERE organization=m.organization FOR SHARE;
 IF NOT FOUND THEN RETURN; END IF;
 -- Cancellation retires recovery of the original order messages. Provider
 -- callbacks can arrive later; preserve their audit facts without re-alerting.
 -- A failed cancellation notice is a separate, still relevant incident.
 IF m.order_id IS NOT NULL AND m.message_kind<>'order_storno' AND EXISTS(
  SELECT 1 FROM eshop.orders o WHERE o.id=m.order_id AND o.occasion=m.occasion AND o.state='storno') THEN
  PERFORM public.notification_center_prepared_invalidate(ev.id) FROM public.notification_center_events ev WHERE ev.organization=m.organization AND ev.source_key=key AND ev.status<>'recovered';
  UPDATE public.notification_center_events SET status='recovered'
   WHERE organization=m.organization AND source_key=key AND kind='email_problem';
  RETURN;
 END IF;
 reason:=public.email_reporting_state(m);
 -- A failed preparation/send is an incident now, even while the queue retries.
 -- Reserve the grace period for ordinary waiting and brief rate limiting.
 IF reason IN ('retry_wait','unknown') AND nullif(m.last_error,'') IS NOT NULL
    AND m.last_error<>'throttled' AND (m.expires_at IS NULL OR m.expires_at>p_at) THEN
  reason:=CASE WHEN m.last_error='preparation_failed' THEN 'rendering_failure' ELSE 'delayed' END;
 END IF;
 SELECT * INTO old FROM public.notification_center_source_state WHERE organization=m.organization AND source_key=key FOR UPDATE;
 due_at:=coalesce((old.state->>'dueAt')::timestamptz,m.target_time);
 IF reason IN ('unknown','retry_wait','pending','preparing','delay') THEN
  IF m.expires_at<=p_at OR m.workflow_state IN ('cancelled','expired') THEN reason:=NULL;
  ELSIF p_at<due_at+interval '30 minutes' AND NOT coalesce((m.message_kind='waitlist_offer' AND m.expires_at<=p_at+interval '5 minutes'),false) THEN reason:=NULL;
  ELSE reason:='delayed'; END IF;
 END IF;
 IF reason='suppressed' AND EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(m.recipient) AND created_at<m.created_at) THEN reason:=NULL; END IF;
 IF reason NOT IN ('complaint','bounce','reject','rendering_failure','dead','suppressed','delayed','post_action_failed') THEN reason:=NULL; END IF;
 fact_at:=CASE reason WHEN 'complaint' THEN m.complained_at WHEN 'bounce' THEN m.bounced_at
 WHEN 'reject' THEN (SELECT min(provider_time) FROM public.email_delivery_events WHERE message_id=m.message_id AND event_type='reject')
 WHEN 'rendering_failure' THEN (SELECT min(provider_time) FROM public.email_delivery_events WHERE message_id=m.message_id AND event_type='rendering_failure')
 WHEN 'delayed' THEN least(p_at,due_at+interval '30 minutes') ELSE p_at END;
 seen:=coalesce(old.state->'seen','[]');
 IF reason IS NOT NULL AND coalesce(fact_at,p_at)>=a.initialized_at AND NOT seen ? reason THEN
  ev:=public.notification_center_publish_internal(m.organization,m.occasion,'email_problem',key,
    jsonb_build_object('messageId',m.message_id,'messageKind',m.message_kind,'reason',reason),NULL,coalesce(fact_at,p_at));
  IF ev IS NOT NULL AND old.state->>'eventId'=ev::text THEN
   PERFORM public.notification_center_prepared_invalidate((old.state->>'eventId')::uuid);
   UPDATE public.notification_center_events SET attention_revision=attention_revision+1,status='active',
    data=data||jsonb_build_object('reason',reason) WHERE id=(old.state->>'eventId')::uuid;
   PERFORM public.notification_center_capture_recipients_internal((old.state->>'eventId')::uuid,NULL);
  END IF;
  seen:=seen||jsonb_build_array(reason);
 ELSIF reason IS NULL AND old.state->>'eventId' IS NOT NULL
  AND (m.order_id IS NULL OR m.message_kind NOT IN ('order_confirmation','order_tickets'))
  AND public.email_reporting_state(m) IN ('delivery','open','click','accepted') THEN
  PERFORM public.notification_center_prepared_invalidate((old.state->>'eventId')::uuid);
  UPDATE public.notification_center_events SET status='recovered' WHERE id=(old.state->>'eventId')::uuid;
 END IF;
 INSERT INTO public.notification_center_source_state(organization,source_key,state)
 VALUES(m.organization,key,jsonb_build_object('reason',reason,'seen',seen,'dueAt',due_at,'eventId',coalesce(ev::text,old.state->>'eventId')))
 ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=p_at;
 PERFORM public.notification_center_reconcile_order_email_internal(m.order_id);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_email_internal(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
