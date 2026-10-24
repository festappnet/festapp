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

-- A dedicated random monitoring capability has no table, write or service-role
-- authority. Only its SHA-256 digest is persisted, provisioned at activation.
CREATE TABLE public.abuse_monitor_key(singleton boolean PRIMARY KEY CHECK(singleton),token_hash bytea CHECK(octet_length(token_hash)=32));
INSERT INTO public.abuse_monitor_key VALUES(true,NULL);
ALTER TABLE public.abuse_monitor_key ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.abuse_monitor_key FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_abuse_monitor_v1(p_token text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE expected bytea; state jsonb; alarm_policy jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE insufficient_privilege USING MESSAGE='monitor denied'; END IF;
 SELECT token_hash INTO expected FROM public.abuse_monitor_key WHERE singleton;
 IF expected IS NULL OR extensions.digest(p_token,'sha256') IS DISTINCT FROM expected THEN
  RAISE insufficient_privilege USING MESSAGE='monitor denied'; END IF;
 state:=public.abuse_health_internal_v1();
 alarm_policy:=public.abuse_effective_rules_v1('monitor.thresholds',NULL,NULL);
 IF alarm_policy IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 RETURN state||jsonb_build_object('thresholds',(SELECT jsonb_object_agg(r->>'rule_key',(r->>'base_limit')::bigint) FROM jsonb_array_elements(alarm_policy->'rules') r));
END $$;
REVOKE ALL ON FUNCTION public.get_abuse_monitor_v1(text) FROM PUBLIC,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_abuse_monitor_v1(text) TO anon;
