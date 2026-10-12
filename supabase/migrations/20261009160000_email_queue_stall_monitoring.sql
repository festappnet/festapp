-- Age due emails from their scheduled time, so future reminders do not
-- become overdue immediately when they first become eligible.
CREATE OR REPLACE FUNCTION public.get_festapp_monitoring_health_v1(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;v_since timestamptz;v_oldest timestamptz;v_alerts text[]:='{}';
BEGIN
  IF p_token IS NULL OR length(p_token)<32 OR length(p_token)>256 THEN RAISE insufficient_privilege USING MESSAGE='monitoring capability required'; END IF;
  SELECT registered_at INTO v_since FROM public.festapp_monitoring_credentials
    WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND expires_at>now();
  IF v_since IS NULL THEN RAISE insufficient_privilege USING MESSAGE='monitoring capability required'; END IF;
  SELECT * INTO c FROM public.email_capacity;
  SELECT min(greatest(created_at,target_time)) INTO v_oldest FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait','preparing','sending') AND target_time<=now();
  IF c.paused THEN v_alerts:=array_append(v_alerts,'email_paused'); END IF;
  IF c.quota_at IS NULL OR c.quota_at<now()-interval '15 minutes' THEN v_alerts:=array_append(v_alerts,'quota_stale'); END IF;
  IF v_oldest<now()-interval '5 minutes' THEN v_alerts:=array_append(v_alerts,'email_backlog'); END IF;
  IF c.provider_outage_streak>0 OR c.wake_error IS NOT NULL OR c.circuit_until>now() THEN v_alerts:=array_append(v_alerts,'email_provider_failed'); END IF;
  IF EXISTS(SELECT 1 FROM public.email_messages WHERE created_at>=v_since AND (workflow_state IN ('dead','unknown') OR provider_failure IS NOT NULL OR last_error='post_action_failed')) THEN v_alerts:=array_append(v_alerts,'email_delivery_failed'); END IF;
  IF EXISTS(SELECT 1 FROM public.email_messages m WHERE accepted_at>=v_since AND accepted_at<now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id)) THEN v_alerts:=array_append(v_alerts,'email_feedback_overdue'); END IF;
  IF EXISTS(SELECT 1 FROM public.first_login_notification_settings WHERE enabled AND activated_at<now()-interval '3 minutes' AND (last_poll_at IS NULL OR last_poll_at<now()-interval '3 minutes')) THEN v_alerts:=array_append(v_alerts,'first_login_poll_stale'); END IF;
  RETURN jsonb_build_object('ok',cardinality(v_alerts)=0,'alerts',to_jsonb(v_alerts));
END $$;
REVOKE ALL ON FUNCTION public.get_festapp_monitoring_health_v1(text) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION public.get_festapp_monitoring_health_v1(text) TO anon;
