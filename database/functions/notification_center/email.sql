CREATE OR REPLACE FUNCTION public.notification_center_email_internal(p_message uuid,p_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; a public.notification_center_activation; old public.notification_center_source_state;
 reason text; fact_at timestamptz; ev uuid; seen jsonb; key text:='email:'||p_message; due_at timestamptz;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF NOT FOUND THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-activation:'||m.organization,0));
 p_at:=coalesce(p_at,clock_timestamp());
 SELECT * INTO a FROM public.notification_center_activation WHERE organization=m.organization FOR SHARE;
 IF NOT FOUND OR NOT a.enabled THEN RETURN; END IF;
 -- Cancellation retires recovery of the original order messages. Provider
 -- callbacks can arrive later; preserve their audit facts without re-alerting.
 -- A failed cancellation notice is a separate, still relevant incident.
 IF m.order_id IS NOT NULL AND m.message_kind<>'order_storno' AND EXISTS(
  SELECT 1 FROM eshop.orders o WHERE o.id=m.order_id AND o.occasion=m.occasion AND o.state='storno') THEN
  UPDATE public.notification_center_events SET status='recovered'
   WHERE organization=m.organization AND source_key=key AND kind='email_problem';
  RETURN;
 END IF;
 reason:=public.email_reporting_state(m);
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
 IF reason IS NOT NULL AND coalesce(fact_at,p_at)>=a.activated_at AND NOT seen ? reason THEN
  ev:=public.notification_center_publish_internal(m.organization,m.occasion,'email_problem',key,
    jsonb_build_object('messageId',m.message_id,'messageKind',m.message_kind,'reason',reason),NULL,coalesce(fact_at,p_at));
  IF ev IS NOT NULL AND old.state->>'eventId'=ev::text THEN
   UPDATE public.notification_center_events SET attention_revision=attention_revision+1,status='active',
    data=data||jsonb_build_object('reason',reason) WHERE id=(old.state->>'eventId')::uuid;
   PERFORM public.notification_center_capture_recipients_internal((old.state->>'eventId')::uuid,NULL);
  END IF;
  seen:=seen||jsonb_build_array(reason);
 ELSIF reason IS NULL AND old.state->>'eventId' IS NOT NULL AND public.email_reporting_state(m) IN ('delivery','open','click','accepted') THEN
  UPDATE public.notification_center_events SET status='recovered' WHERE id=(old.state->>'eventId')::uuid;
 END IF;
 INSERT INTO public.notification_center_source_state(organization,source_key,state)
 VALUES(m.organization,key,jsonb_build_object('reason',reason,'seen',seen,'dueAt',due_at,'eventId',coalesce(ev::text,old.state->>'eventId')))
 ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=p_at;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_email_internal(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
