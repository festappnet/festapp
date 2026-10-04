-- Operator telemetry only. This is the same queue/attempt/event journal, no second state owner.
CREATE OR REPLACE FUNCTION public.get_email_delivery_health() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;v_queue jsonb;v_times jsonb;v_provider jsonb;v_oldest timestamptz;v_post bigint;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity;
 SELECT min(created_at) INTO v_oldest FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now();
 SELECT coalesce(jsonb_object_agg(workflow_state,n),'{}') INTO v_queue FROM (SELECT workflow_state,count(*) n FROM public.email_messages GROUP BY workflow_state) s;
 SELECT jsonb_build_object('commit_to_claim_seconds',avg(extract(epoch FROM a.created_at-m.created_at)),
 'preparation_seconds',avg(extract(epoch FROM m.prepared_at-a.created_at)) FILTER(WHERE m.prepared_at>=a.created_at),
 'ready_to_send_seconds',avg(extract(epoch FROM a.began_at-m.prepared_at)) FILTER(WHERE a.began_at>=m.prepared_at),
 'throttles',count(*) FILTER(WHERE error_code='throttled')) INTO v_times
 FROM public.email_attempts a JOIN public.email_messages m USING(message_id) WHERE a.created_at>now()-interval '1 day';
 SELECT jsonb_build_object('unmatched',count(*) FILTER(WHERE message_id IS NULL),'last_event_at',max(received_at),
 'feedback_lag_seconds',avg(extract(epoch FROM received_at-provider_time)) FILTER(WHERE received_at>now()-interval '1 day')) INTO v_provider FROM public.email_delivery_events;
 SELECT count(*) INTO v_post FROM public.email_messages WHERE workflow_state='accepted' AND post_action_state='pending';
 RETURN jsonb_build_object('queue',v_queue,'oldest_due_at',v_oldest,'timings_24h',v_times,'provider',v_provider,'post_action_backlog',v_post,
 'capacity',jsonb_build_object('paused',c.paused,'quota_at',c.quota_at,'quota_fresh',coalesce(c.quota_at>now()-interval '15 minutes',false),
 'heartbeat_at',c.heartbeat_at,'circuit_until',c.circuit_until,'provider_outage_streak',c.provider_outage_streak,'probe_until',c.probe_until,'incident',c.wake_error,
 'effective_rate',CASE WHEN c.shared_account THEN least(c.max_rate*0.8,c.allocated_rate) ELSE c.max_rate*0.8 END*c.rate_factor,
 'allocated_daily',c.allocated_daily,'provider_sent_24h',c.provider_sent_24h),
 'alerts',to_jsonb(array_remove(ARRAY[
 CASE WHEN NOT c.paused AND (c.quota_at IS NULL OR c.quota_at<now()-interval '15 minutes') THEN 'quota_stale' END,
 CASE WHEN v_oldest<now()-interval '5 minutes' THEN 'oldest_due' END,
 CASE WHEN v_oldest<now()-interval '5 minutes' AND (c.heartbeat_at IS NULL OR c.heartbeat_at<now()-interval '5 minutes') THEN 'worker_heartbeat_stale' END,
 CASE WHEN c.provider_outage_streak>0 THEN 'provider_outage' END,
 CASE WHEN c.wake_error IS NOT NULL THEN 'provider_or_wake_incident' END,
 CASE WHEN EXISTS(SELECT 1 FROM public.email_messages WHERE last_error='post_action_failed') THEN 'post_action_failed' END,
 CASE WHEN EXISTS(SELECT 1 FROM public.email_messages m WHERE accepted_at BETWEEN now()-interval '1 day' AND now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id)) THEN 'feedback_overdue' END
 ],NULL)));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_health() TO service_role;
