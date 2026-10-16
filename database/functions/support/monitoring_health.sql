-- A separate hashed capability exposes bounded operational facts only. It cannot
-- mint sessions, enqueue mail or access customer rows through another RPC.
CREATE TABLE IF NOT EXISTS public.festapp_monitoring_credentials (
  token_hash text PRIMARY KEY CHECK(length(token_hash)=64),
  expires_at timestamptz NOT NULL,
  registered_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.festapp_monitoring_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.festapp_monitoring_credentials FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_festapp_monitoring_health_v1(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;v_since timestamptz;v_oldest timestamptz;v_alerts text[]:='{}'; abuse jsonb; thresholds jsonb; cls text; age_seconds numeric; max_seconds bigint;
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
  abuse:=public.abuse_health_internal_v1();
  SELECT jsonb_object_agg(r->>'rule_key',(r->>'base_limit')::bigint) INTO thresholds
   FROM jsonb_array_elements(public.abuse_effective_rules_v1('monitor.thresholds',NULL,NULL)->'rules') r;
  IF thresholds IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
  FOREACH cls IN ARRAY ARRAY['auth','commitment','ordinary'] LOOP
   age_seconds:=extract(epoch FROM statement_timestamp()-(abuse#>>ARRAY['queue',cls,'oldestCreatedAt'])::timestamptz);
   max_seconds:=(thresholds->>('monitor.'||cls||'.age.seconds'))::bigint;
   IF max_seconds IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
   IF age_seconds>max_seconds THEN v_alerts:=array_append(v_alerts,'abuse_'||cls||'_backlog'); END IF;
  END LOOP;
  IF (abuse->>'oldestExpiredUsageAt')::timestamptz<statement_timestamp()-make_interval(secs=>(thresholds->>'monitor.cleanup.age.seconds')::integer) THEN v_alerts:=array_append(v_alerts,'abuse_cleanup_stale'); END IF;
  IF (abuse->>'oldestGrowthEvidenceAt')::timestamptz<statement_timestamp()-make_interval(secs=>(thresholds->>'monitor.growth.age.seconds')::integer) THEN v_alerts:=array_append(v_alerts,'abuse_growth_stale'); END IF;
  RETURN jsonb_build_object('ok',cardinality(v_alerts)=0,'alerts',to_jsonb(v_alerts),'abuse',abuse);
END $$;
REVOKE ALL ON FUNCTION public.get_festapp_monitoring_health_v1(text) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION public.get_festapp_monitoring_health_v1(text) TO anon;
