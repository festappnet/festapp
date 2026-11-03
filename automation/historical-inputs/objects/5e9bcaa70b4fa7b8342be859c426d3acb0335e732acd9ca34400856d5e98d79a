-- Conservative rolling buckets include the whole leading bucket: no boundary overshoot.
-- At most window/bucket+1 indexed buckets are read for one rule/scope.
-- Locks always follow rule_key,scope_id, independent of route or policy revision.
CREATE OR REPLACE FUNCTION public.abuse_charge_v1(p_policy jsonb,p_scopes jsonb,p_costs jsonb DEFAULT '{}',p_attempt boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb; s text; n bigint; used bigint; lim bigint; bucket timestamptz;
 t timestamptz:=statement_timestamp(); allowed boolean:=true; cost bigint; failed_rule text;
 retry_seconds integer:=0; needs_change boolean:=false; release_at timestamptz;
BEGIN
 IF p_policy IS NULL OR jsonb_array_length(p_policy->'rules')=0 THEN
  RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(p_policy->'rules') ORDER BY value->>'rule_key' LOOP
  s:=p_scopes->>(r->>'scope_kind');
  IF s IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='abuse_scope_missing'; END IF;
  IF r->>'kind' IN ('bytes','duration','items') THEN CONTINUE; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||s,0));
 END LOOP;
 -- Check every rule before changing any accepted-operation counter.
 FOR r IN SELECT value FROM jsonb_array_elements(p_policy->'rules') ORDER BY value->>'rule_key' LOOP
  s:=p_scopes->>(r->>'scope_kind');
  cost:=coalesce((p_costs->>(r->>'rule_key'))::bigint,1);
  IF cost<0 THEN RAISE invalid_parameter_value USING MESSAGE='negative abuse cost'; END IF;
  lim:=least((r->>'hard_cap')::bigint,(r->>'base_limit')::bigint+
   least(coalesce((p_costs->>'growth')::bigint,0),1000000000)*(r->>'growth_increment')::bigint);
  IF r->>'kind'='rolling' THEN
   bucket:=to_timestamp(floor(extract(epoch FROM t)/(r->>'bucket_seconds')::int)*(r->>'bucket_seconds')::int);
   SELECT coalesce(sum(amount),0) INTO used FROM public.abuse_budget_usage
    WHERE rule_key=r->>'rule_key' AND scope_id=s
     AND bucket_at>=bucket-make_interval(secs=>(r->>'window_seconds')::int);
  ELSIF r->>'kind'='cumulative' THEN
   bucket:='epoch'::timestamptz;
   SELECT coalesce(sum(amount),0) INTO used FROM public.abuse_budget_usage WHERE rule_key=r->>'rule_key' AND scope_id=s;
  ELSE used:=0; END IF;
  IF used+cost>lim THEN
   allowed:=false; failed_rule:=coalesce(failed_rule,r->>'rule_key');
   IF NOT p_attempt AND r->>'kind'='rolling' AND cost<=lim THEN
    SELECT q.bucket_at INTO release_at FROM (
     SELECT bucket_at,sum(amount) OVER(ORDER BY bucket_at) AS released FROM public.abuse_budget_usage
     WHERE rule_key=r->>'rule_key' AND scope_id=s AND bucket_at>=bucket-make_interval(secs=>(r->>'window_seconds')::int)
    ) q WHERE q.released>=used+cost-lim ORDER BY q.bucket_at LIMIT 1;
    retry_seconds:=greatest(retry_seconds,ceil(extract(epoch FROM release_at+make_interval(secs=>(r->>'window_seconds')::int+(r->>'bucket_seconds')::int)-t))::integer);
   ELSIF r->>'kind'='cumulative' OR (cost>lim AND r->>'kind' IN ('bytes','items','duration')) THEN needs_change:=true;
   ELSE retry_seconds:=greatest(retry_seconds,60); END IF;
  END IF;
 END LOOP;
 IF NOT allowed AND NOT p_attempt THEN RAISE SQLSTATE 'PT429' USING MESSAGE='abuse_limit_exceeded',DETAIL=jsonb_build_object('retryAfterSeconds',CASE WHEN needs_change THEN NULL ELSE greatest(retry_seconds,1) END,'needsPolicyChange',needs_change,'policyRevision',p_policy->'revision','ruleKey',failed_rule)::text,HINT='Capacity is limited. Retry later or request a reviewed policy increase.'; END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(p_policy->'rules') ORDER BY value->>'rule_key' LOOP
  IF r->>'kind' NOT IN ('rolling','cumulative') THEN CONTINUE; END IF;
  s:=p_scopes->>(r->>'scope_kind'); cost:=coalesce((p_costs->>(r->>'rule_key'))::bigint,1);
  IF cost=0 THEN CONTINUE; END IF;
  bucket:=CASE WHEN r->>'kind'='cumulative' THEN 'epoch'::timestamptz ELSE to_timestamp(floor(extract(epoch FROM t)/(r->>'bucket_seconds')::int)*(r->>'bucket_seconds')::int) END;
  INSERT INTO public.abuse_budget_usage VALUES(r->>'rule_key',s,bucket,cost,
   CASE WHEN r->>'kind'='cumulative' THEN 'infinity'::timestamptz ELSE bucket+make_interval(secs=>(r->>'window_seconds')::int+(r->>'bucket_seconds')::int) END)
  ON CONFLICT(rule_key,scope_id,bucket_at) DO UPDATE SET amount=least(1000000000001,public.abuse_budget_usage.amount+excluded.amount);
 END LOOP;
 RETURN allowed;
END $$;
REVOKE ALL ON FUNCTION public.abuse_charge_v1(jsonb,jsonb,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_occasion_creation_v1(p_actor uuid,p_unit bigint,p_org bigint,p_system_source text,p_policy jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE policy jsonb; scopes jsonb; costs jsonb; r jsonb;
BEGIN
 IF (p_actor IS NULL AND (p_system_source IS NULL OR NOT EXISTS(SELECT 1 FROM public.external_sync_sources WHERE source_name=p_system_source))) OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_org) THEN
  RAISE insufficient_privilege USING MESSAGE='invalid occasion admission scope'; END IF;
 policy:=coalesce(p_policy,public.abuse_effective_rules_v1('occasion.creation',p_unit,p_org));
 scopes:=jsonb_build_object('actor',coalesce(p_actor::text,'system:'||p_system_source),'unit',p_unit,'organization',p_org);
 -- Acquire the same scope locks before reading occupancy; charge reuses them.
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT jsonb_build_object('occasion.stored.unit',count(*) FILTER(WHERE unit=p_unit)+1,
  'occasion.stored.organization',count(*)+1) INTO costs FROM public.occasions WHERE organization=p_org;
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
END $$;
REVOKE ALL ON FUNCTION public.admit_occasion_creation_v1(uuid,bigint,bigint,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_occasion_draft_v1(p_actor uuid,p_unit bigint,p_org bigint,p_bytes bigint,p_new boolean,p_work boolean,p_policy jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE policy jsonb; scopes jsonb; costs jsonb; r jsonb; unit_count bigint; org_count bigint;
BEGIN
 policy:=coalesce(p_policy,public.abuse_effective_rules_v1('occasion.draft',p_unit,p_org));
 scopes:=jsonb_build_object('actor',p_actor,'unit',p_unit,'organization',p_org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT count(*) FILTER(WHERE unit=p_unit),count(*) INTO unit_count,org_count FROM public.occasion_setup_drafts WHERE organization=p_org;
 costs:=jsonb_build_object('draft.stored.unit',unit_count+p_new::int,'draft.stored.organization',org_count+p_new::int,'draft.payload.bytes',p_bytes,
  'draft.create.actor.burst',p_new::int,'draft.create.actor.day',p_new::int,'draft.create.organization.day',p_new::int,'draft.work.actor.burst',p_work::int);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
END $$;
REVOKE ALL ON FUNCTION public.admit_occasion_draft_v1(uuid,bigint,bigint,bigint,boolean,boolean,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_unit_creation_v1(p_actor uuid,p_org bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_actor IS NULL OR p_org IS NULL THEN RAISE insufficient_privilege USING MESSAGE='unit admission scope required'; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('unit.creation',NULL,p_org),
  jsonb_build_object('actor',p_actor,'organization',p_org,'global','all'));
END $$;
REVOKE ALL ON FUNCTION public.admit_unit_creation_v1(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.cleanup_abuse_usage_v1() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 PERFORM public.require_service_role();
 DELETE FROM public.abuse_budget_usage WHERE (rule_key,scope_id,bucket_at) IN
  (SELECT rule_key,scope_id,bucket_at FROM public.abuse_budget_usage WHERE expires_at<statement_timestamp() ORDER BY expires_at LIMIT 5000 FOR UPDATE SKIP LOCKED);
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.cleanup_abuse_usage_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_abuse_usage_v1() TO service_role;

CREATE OR REPLACE FUNCTION public.admit_occasion_creation_v1(p_actor uuid,p_unit bigint,p_org bigint,p_system_source text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.admit_occasion_creation_v1(p_actor,p_unit,p_org,p_system_source,NULL);
$$;
REVOKE ALL ON FUNCTION public.admit_occasion_creation_v1(uuid,bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_occasion_creation_v1(p_actor uuid,p_unit bigint,p_org bigint)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.admit_occasion_creation_v1(p_actor,p_unit,p_org,NULL);
$$;
REVOKE ALL ON FUNCTION public.admit_occasion_creation_v1(uuid,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_occasion_draft_v1(p_actor uuid,p_unit bigint,p_org bigint,p_bytes bigint,p_new boolean,p_work boolean)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.admit_occasion_draft_v1(p_actor,p_unit,p_org,p_bytes,p_new,p_work,NULL);
$$;
REVOKE ALL ON FUNCTION public.admit_occasion_draft_v1(uuid,bigint,bigint,bigint,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
