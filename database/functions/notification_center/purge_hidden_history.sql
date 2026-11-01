-- Explicit maintenance boundary. Personal notification projections are disposable;
-- business records and shared read watermarks are not part of this deletion.
CREATE OR REPLACE FUNCTION public.purge_hidden_notification_history_internal(p_organization bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids uuid[]; removed bigint;
BEGIN
 PERFORM public.notification_center_require_service();
 PERFORM pg_advisory_xact_lock(hashtextextended('notification-center-organization:'||p_organization,0));
 SELECT coalesce(array_agg(e.id),'{}'::uuid[]) INTO ids
 FROM public.notification_center_events e WHERE e.organization=p_organization
 AND NOT public.notification_center_subject_visible_internal(e.organization,e.kind,e.data);
 -- Remove references to the deleted projections while retaining source facts.
 UPDATE public.notification_center_source_state s SET state=s.state-'eventId'
 WHERE s.organization=p_organization AND s.state->>'eventId'=ANY(ids::text[]);
 UPDATE public.notification_center_source_state s SET state=s.state-'notificationId'
 WHERE s.organization=p_organization AND s.state->>'notificationId'=ANY(ids::text[]);
 DELETE FROM public.notification_center_read_batches b WHERE b.organization=p_organization
 AND b.group_key IN (SELECT 'event:'||id FROM unnest(ids) id);
 -- Recipient eligibility and delivery rows have ON DELETE CASCADE event FKs.
 DELETE FROM public.notification_center_events e WHERE e.organization=p_organization AND e.id=ANY(ids);
 GET DIAGNOSTICS removed=ROW_COUNT;
 RETURN removed;
END $$;
REVOKE ALL ON FUNCTION public.purge_hidden_notification_history_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
