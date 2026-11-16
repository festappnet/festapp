CREATE OR REPLACE FUNCTION public.collect_notification_center_emails(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE profile record; scope record; entry record; scopes text[]; key text; dispatch uuid; at timestamptz;
 bound bigint; scanned bigint; n integer:=0; rows integer; enabled timestamptz; expired integer:=0; total_scanned integer:=0; required_recipient uuid;
BEGIN
 PERFORM public.notification_center_require_service();
 -- Captured required deliveries enroll a serialization profile, never optional
 -- subscriptions. Recovered/revoked events are then consumed and skipped by the
 -- ordinary live checks, so a missing profile cannot leave endless wake work.
 FOR required_recipient IN
  SELECT DISTINCT u.recipient FROM public.notification_center_user_state u
  JOIN public.notification_center_organizations a USING(organization)
  JOIN public.user_info ui ON ui.id=u.recipient
  JOIN public.notification_center_deliveries d ON d.organization=u.organization AND d.recipient=u.recipient AND d.sequence>u.email_scanned_sequence
  JOIN public.notification_center_events e ON e.id=d.event_id
  WHERE u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL
   AND e.occurred_at>=a.email_collection_started_at AND public.notification_center_email_required_kind_internal(e.kind)
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_profiles p WHERE p.recipient=u.recipient)
  ORDER BY u.recipient LIMIT greatest(1,least(p_limit,100))
 LOOP
  PERFORM public.notification_center_email_ensure_profile_internal(required_recipient,true);
 END LOOP;

 FOR profile IN SELECT p.* FROM public.notification_center_email_profiles p
  WHERE EXISTS(SELECT 1 FROM public.notification_center_user_state u
   JOIN public.notification_center_organizations a USING(organization)
   WHERE u.recipient=p.recipient AND u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL)
   OR (p.collected_at<clock_timestamp()-interval '1 day' AND EXISTS(SELECT 1 FROM public.notification_center_email_items i WHERE i.recipient=p.recipient AND i.admitted_at<clock_timestamp()-interval '90 days'))
  ORDER BY p.collected_at,p.recipient LIMIT greatest(1,least(p_limit,100)) FOR UPDATE OF p SKIP LOCKED LOOP
  FOR scope IN SELECT u.* FROM public.notification_center_user_state u
   JOIN public.notification_center_organizations a USING(organization)
   WHERE u.recipient=profile.recipient AND u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL
   ORDER BY u.organization LIMIT 20 FOR UPDATE OF u SKIP LOCKED LOOP
   bound:=scope.last_delivery_sequence; scanned:=scope.email_scanned_sequence; rows:=0;
   SELECT array_agg(a.scope) INTO scopes FROM public.notification_center_prepared_allowed_scopes(scope.organization,NULL,profile.recipient) a;
   FOR entry IN SELECT d.sequence,e FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
    WHERE d.organization=scope.organization AND d.recipient=profile.recipient AND d.sequence>scope.email_scanned_sequence AND d.sequence<=bound
    ORDER BY d.sequence LIMIT 500 LOOP
    scanned:=entry.sequence; rows:=rows+1; total_scanned:=total_scanned+1;
    enabled:=public.notification_center_email_enabled_internal(entry.e,profile.recipient,coalesce(scopes,'{}'));
    IF enabled IS NULL OR NOT public.notification_center_prepared_event_access(entry.e,scope.organization,coalesce(scopes,'{}'))
     OR NOT public.notification_center_in_center_internal(entry.e,statement_timestamp()) THEN CONTINUE; END IF;
    IF (entry.e).kind NOT IN ('bank_problem','email_problem','payment_problem','provider_problem') AND (entry.e).occurred_at<statement_timestamp()-interval '24 hours' THEN
     expired:=expired+1; CONTINUE;
    END IF;
    key:=CASE WHEN (entry.e).kind='bank_problem' THEN
     'bank:'||((entry.e).data->>'bankConnectionId')||':incident:'||((entry.e).data->>'incidentId')
     WHEN (entry.e).kind='provider_problem' THEN 'provider:'||((entry.e).data->>'provider')||':'||((entry.e).data->>'connectionId')||':incident:'||((entry.e).data->>'incidentId') ELSE 'event:'||(entry.e).id END;
    -- Unmapped historical bank episodes cannot start a new external campaign.
    IF key IS NULL THEN CONTINUE; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.notification_center_email_items i WHERE i.recipient=profile.recipient AND i.delivery_key=key) THEN
     SELECT id INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=profile.recipient AND state='collecting' FOR UPDATE;
     IF dispatch IS NULL THEN
      at:=clock_timestamp();
      INSERT INTO public.notification_center_email_dispatches(recipient,opened_at,due_at) VALUES(profile.recipient,at,at+public.notification_center_email_window_internal()) RETURNING id INTO dispatch;
     END IF;
     INSERT INTO public.notification_center_email_items(recipient,delivery_key,dispatch_id) VALUES(profile.recipient,key,dispatch) ON CONFLICT DO NOTHING;
    END IF;
    INSERT INTO public.notification_center_email_item_sources(event_id,recipient,organization,delivery_key,first_sequence,enabled_from)
    VALUES((entry.e).id,profile.recipient,scope.organization,key,entry.sequence,enabled) ON CONFLICT DO NOTHING;
   END LOOP;
   IF rows<500 THEN scanned:=bound; END IF;
   UPDATE public.notification_center_user_state SET email_scanned_sequence=scanned WHERE organization=scope.organization AND recipient=profile.recipient;
  END LOOP;
  DELETE FROM public.notification_center_email_items i WHERE i.recipient=profile.recipient
   AND i.admitted_at<clock_timestamp()-interval '90 days'
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d JOIN public.email_messages m ON m.message_id=d.message_id
    WHERE d.id=i.dispatch_id AND m.workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown'))
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d WHERE d.id=i.dispatch_id AND d.state='collecting')
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_item_sources s JOIN public.notification_center_events e ON e.id=s.event_id
    WHERE s.recipient=i.recipient AND s.delivery_key=i.delivery_key AND e.kind IN ('bank_problem','email_problem','payment_problem','provider_problem') AND e.status NOT IN ('resolved','recovered'))
   AND NOT EXISTS(SELECT 1 FROM eshop.provider_connection_notification_incidents i2 WHERE i2.active
    AND i.delivery_key='provider:'||i2.provider||':'||i2.connection_id||':incident:'||i2.incident_id)
   AND NOT EXISTS(SELECT 1 FROM eshop.bank_sync_health h WHERE i.delivery_key='bank:'||h.connection_id||':incident:'||h.incident_id AND h.warning_code IS NOT NULL);
  DELETE FROM public.notification_center_email_dispatches d WHERE d.recipient=profile.recipient AND d.state IN ('collecting','omitted')
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_items i WHERE i.dispatch_id=d.id);
  UPDATE public.notification_center_email_profiles SET collected_at=clock_timestamp() WHERE recipient=profile.recipient;
  n:=n+1;
 END LOOP;
 UPDATE public.notification_center_maintenance SET last_scanned=total_scanned,last_processed=n,
  last_deferred=expired,last_run_at=clock_timestamp() WHERE name='email-collection' AND n>0
  AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='email-collection' FOR UPDATE SKIP LOCKED);
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_notification_center_emails(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE profile record; dispatch record; context jsonb; result jsonb; n integer:=0; detail text; retry integer;
BEGIN
 PERFORM public.notification_center_require_service();
 FOR profile IN SELECT p.* FROM public.notification_center_email_profiles p
  WHERE EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d WHERE d.recipient=p.recipient AND d.state='collecting' AND d.due_at<=clock_timestamp() AND d.next_attempt_at<=clock_timestamp())
  ORDER BY p.collected_at,p.recipient LIMIT greatest(1,least(p_limit,100)) FOR UPDATE OF p SKIP LOCKED LOOP
  IF EXISTS(SELECT 1 FROM public.email_messages m WHERE m.recipient_user=profile.recipient AND m.message_kind='admin_notification_digest'
   AND m.workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown')) THEN CONTINUE; END IF;
  SELECT * INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=profile.recipient AND state='collecting' AND due_at<=clock_timestamp() AND next_attempt_at<=clock_timestamp() FOR UPDATE;
  IF NOT FOUND THEN CONTINUE; END IF;
  context:=public.notification_center_email_context_internal(dispatch.id,profile.recipient);
  IF context IS NULL OR jsonb_array_length(context->'items')=0 THEN
   UPDATE public.notification_center_email_dispatches SET state='omitted' WHERE id=dispatch.id;
   CONTINUE;
  END IF;
  IF nullif(context->>'address','') IS NULL THEN
   UPDATE public.notification_center_email_dispatches SET next_attempt_at=clock_timestamp()+interval '5 minutes' WHERE id=dispatch.id;
   CONTINUE;
  END IF;
  BEGIN
  result:=public.enqueue_email('admin_notification_digest',jsonb_build_object('recipient_user',profile.recipient),context->>'address',
   jsonb_build_object('dispatchId',dispatch.id,'templateVersion',1),'notification:'||dispatch.id,'ADMIN_NOTIFICATION_DIGEST');
  UPDATE public.notification_center_email_dispatches SET state='queued',message_id=(result->>'message_id')::uuid WHERE id=dispatch.id;
  n:=n+1;
  EXCEPTION WHEN SQLSTATE 'PT429' THEN
   -- Producer admission rolls back independently; the durable collecting
   -- envelope waits for the original abuse backend's release time.
   GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_DETAIL;
   retry:=greatest(1,least(coalesce((detail::jsonb->>'retryAfterSeconds')::integer,60),86400));
   UPDATE public.notification_center_email_dispatches SET next_attempt_at=clock_timestamp()+make_interval(secs=>retry) WHERE id=dispatch.id;
  END;
 END LOOP;
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.collect_notification_center_emails(integer),public.enqueue_notification_center_emails(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.collect_notification_center_emails(integer),public.enqueue_notification_center_emails(integer) TO service_role;
CREATE OR REPLACE FUNCTION public.get_notification_center_email_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 RETURN jsonb_build_object(
 'lastCollection',(SELECT jsonb_build_object('scanned',last_scanned,'recipients',last_processed,'expiredCatchup',last_deferred,'at',last_run_at) FROM public.notification_center_maintenance WHERE name='email-collection'),
 'cursorLag',(SELECT coalesce(sum(u.last_delivery_sequence-u.email_scanned_sequence),0) FROM public.notification_center_user_state u JOIN public.notification_center_email_profiles p USING(recipient) JOIN public.notification_center_organizations a USING(organization) WHERE a.email_collection_started_at IS NOT NULL),
 'oldestUnscanned',(SELECT min(d.delivered_at) FROM public.notification_center_user_state u JOIN public.notification_center_email_profiles p USING(recipient) JOIN public.notification_center_organizations a USING(organization) JOIN public.notification_center_deliveries d ON d.organization=u.organization AND d.recipient=u.recipient AND d.sequence>u.email_scanned_sequence WHERE a.email_collection_started_at IS NOT NULL),
 'oldestDue',(SELECT min(due_at) FROM public.notification_center_email_dispatches WHERE state='collecting' AND due_at<=clock_timestamp()),
 'deferredEnqueue',(SELECT count(*) FROM public.notification_center_email_dispatches WHERE state='collecting' AND next_attempt_at>clock_timestamp()),
 'activeQueue',(SELECT count(*) FROM public.email_messages WHERE message_kind='admin_notification_digest' AND workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown')),
 'unknown',(SELECT count(*) FROM public.email_messages WHERE message_kind='admin_notification_digest' AND workflow_state='unknown'),
 'noAddress',(SELECT count(*) FROM public.notification_center_email_dispatches d JOIN public.notification_center_email_profiles p USING(recipient) WHERE d.state='collecting' AND public.get_user_delivery_email(p.recipient) IS NULL));
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_email_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_center_email_health() TO service_role;
