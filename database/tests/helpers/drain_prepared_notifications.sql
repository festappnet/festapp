-- Bounded readiness over the real workers; no source/recipient/view mutation.
CREATE OR REPLACE FUNCTION pg_temp.drain_prepared_notifications(p_org bigint,p_views boolean DEFAULT true,p_view uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE started timestamptz:=clock_timestamp(); rounds integer:=0; response jsonb;
 view_occasion bigint; view_timezone text;
BEGIN
 IF p_view IS NOT NULL THEN
  SELECT current_occasion,timezone INTO STRICT view_occasion,view_timezone
  FROM public.notification_center_views WHERE token=p_view AND organization=p_org AND recipient=auth.uid();
 END IF;
 LOOP
  rounds:=rounds+1;
  -- Refreshing an already owned view wakes live privacy debt through the actual
  -- API. It neither allocates a lease nor acknowledges a new snapshot.
  IF p_view IS NOT NULL THEN
   PERFORM public.get_notification_center_view(p_org,view_occasion,p_timezone=>view_timezone,p_mode=>'refresh',p_view=>p_view);
  END IF;
  PERFORM public.prepare_notification_center(100);
  IF p_views THEN PERFORM public.prepare_notification_center_views(100); END IF;
  IF p_view IS NOT NULL THEN
   response:=public.get_notification_center_view(p_org,view_occasion,p_timezone=>view_timezone,p_mode=>'refresh',p_view=>p_view);
   EXIT WHEN response->>'state'='ready';
  ELSE
  EXIT WHEN NOT EXISTS(
   SELECT 1 FROM public.notification_center_projection_scopes s
   JOIN public.notification_center_user_state u ON u.organization=s.organization AND u.recipient=s.recipient
   WHERE s.organization=p_org AND (s.phase<>'ready' OR s.pending_events>0 OR s.pending_groups>0 OR s.pending_delivery>0
    OR s.privacy_pending OR s.prepared_sequence<u.last_delivery_sequence
    OR s.privacy<>public.notification_center_prepared_privacy(p_org)))
   AND (NOT p_views OR NOT EXISTS(
    SELECT 1 FROM public.notification_center_view_rows r JOIN public.notification_center_views v ON v.token=r.token
    JOIN public.notification_center_projection_scopes s ON s.organization=v.organization AND s.recipient=v.recipient
    JOIN public.notification_center_user_state u ON u.organization=v.organization AND u.recipient=v.recipient
    WHERE v.organization=p_org AND v.expires_at>clock_timestamp() AND
      (r.state='preparing' OR r.revision<>s.revision OR r.read_revision<>u.view_read_revision
       OR r.privacy_key<>md5(public.notification_center_prepared_privacy(p_org)::text))));
  END IF;
  IF rounds>=100 OR clock_timestamp()>started+interval '10 seconds' THEN
   RAISE EXCEPTION 'Prepared notification fixture did not become ready after % rounds (state %)',rounds,response->>'state';
  END IF;
 END LOOP;
 RAISE NOTICE 'TEST_TIMING %',jsonb_build_object('phase','prepared-worker','serverSeconds',extract(epoch FROM clock_timestamp()-started),'iterations',rounds);
END $$;
