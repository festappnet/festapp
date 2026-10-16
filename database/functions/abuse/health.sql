-- Read-only operator evidence. Labels are the three fixed mail classes, never
-- recipient/source/UUID. The endpoint does no cleanup, dispatch or provider IO.
CREATE INDEX email_pending_class_age ON public.email_messages(admission_class,created_at)
 WHERE workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
CREATE INDEX abuse_evidence_age ON public.abuse_unit_evidence(measured_at);

CREATE OR REPLACE FUNCTION public.abuse_health_internal_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE queues jsonb; expired_at timestamptz; evidence_at timestamptz; capacity jsonb;
BEGIN
 SELECT jsonb_object_agg(class,stats) INTO queues FROM (
  SELECT class,jsonb_build_object(
   'pendingCount',least(5000,(SELECT count(*) FROM (
     SELECT 1 FROM public.email_messages WHERE admission_class=class
      AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown') LIMIT 5001
    ) q)),
   'countCappedAt',5000,
   'oldestCreatedAt',(SELECT created_at FROM public.email_messages WHERE admission_class=class
     AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown') ORDER BY created_at LIMIT 1)
  ) stats FROM unnest(ARRAY['ordinary','auth','commitment']) class
 ) q;
 SELECT expires_at INTO expired_at FROM public.abuse_budget_usage WHERE expires_at<statement_timestamp() ORDER BY expires_at LIMIT 1;
 SELECT measured_at INTO evidence_at FROM public.abuse_unit_evidence ORDER BY measured_at LIMIT 1;
 SELECT jsonb_build_object('paused',paused,'quotaMeasuredAt',quota_at,'circuitUntil',circuit_until,
   'nextSendAt',next_send_at,'providerOutageStreak',provider_outage_streak) INTO capacity FROM public.email_capacity LIMIT 1;
 RETURN jsonb_build_object('measuredAt',statement_timestamp(),
  'policyRevision',(SELECT revision FROM public.abuse_policy_revision WHERE singleton),
  'queue',queues,'oldestExpiredUsageAt',expired_at,'oldestGrowthEvidenceAt',evidence_at,'provider',capacity);
END $$;
REVOKE ALL ON FUNCTION public.abuse_health_internal_v1() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_abuse_health_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN public.abuse_health_internal_v1();
END $$;
REVOKE ALL ON FUNCTION public.get_abuse_health_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_abuse_health_v1() TO service_role;
