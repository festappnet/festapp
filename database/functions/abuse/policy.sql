-- One statement snapshot per domain admission. Scoped overrides cannot alter an actor rule.
CREATE OR REPLACE FUNCTION public.abuse_effective_rules_v1(p_budget text,p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('revision',v.revision,'rules',coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object(
 'base_limit',coalesce(u.base_limit,o.base_limit,r.base_limit)) ORDER BY r.rule_key),'[]'::jsonb))
 FROM public.abuse_policy_revision v CROSS JOIN public.abuse_policy_rules r
 LEFT JOIN public.abuse_policy_overrides o ON o.rule_key=r.rule_key AND o.target_kind='organization'
  AND o.target_id=p_org AND r.scope_kind IN ('unit','organization') AND o.expires_at>statement_timestamp()
 LEFT JOIN public.abuse_policy_overrides u ON u.rule_key=r.rule_key AND u.target_kind='unit'
  AND u.target_id=p_unit AND r.scope_kind='unit' AND u.expires_at>statement_timestamp()
 WHERE r.budget_key=p_budget GROUP BY v.revision
 HAVING count(*)=CASE p_budget WHEN 'occasion.creation' THEN 8 WHEN 'occasion.copy' THEN 2 WHEN 'occasion.draft' THEN 7
  WHEN 'unit.creation' THEN 3 WHEN 'email.ordinary' THEN 4 WHEN 'email.auth' THEN 4
  WHEN 'email.backlog' THEN 4 WHEN 'email.auth.backlog' THEN 1 WHEN 'email.payload' THEN 1
  WHEN 'email.prepare' THEN 2 WHEN 'email.actor' THEN 1 WHEN 'email.dispatch' THEN 1 WHEN 'ticket.document' THEN 4 WHEN 'ticket.preview' THEN 4 WHEN 'bank.operation' THEN 3 WHEN 'order.creation' THEN 4 WHEN 'qr.global' THEN 1 WHEN 'qr.proof' THEN 1 WHEN 'qr.payload' THEN 1 WHEN 'spot.hold' THEN 3 WHEN 'image.upload' THEN 5 WHEN 'image.fetch' THEN 5 WHEN 'sync.snapshot' THEN 2 WHEN 'sync.work' THEN 1 WHEN 'hold.duration' THEN 1 WHEN 'auth.reset.source' THEN 2 WHEN 'organization.creation' THEN 1 WHEN 'auth.reset.account' THEN 1
  WHEN 'auth.google.source' THEN 1 WHEN 'auth.google.client' THEN 1 WHEN 'auth.google.global' THEN 1 WHEN 'auth.google.attempt' THEN 1 WHEN 'auth.google.proof' THEN 1
  WHEN 'scan.operation' THEN 2 WHEN 'scan.invalid.global' THEN 1 WHEN 'scan.invalid.source' THEN 1 WHEN 'scan.password' THEN 2 WHEN 'scan.export' THEN 2
  WHEN 'reception.create' THEN 1 WHEN 'reception.issue' THEN 1 WHEN 'reception.revoke' THEN 1 WHEN 'reception.cancel' THEN 1
  WHEN 'order.mutation' THEN 4
  WHEN 'push.delivery' THEN 10
  WHEN 'cleaning.report' THEN 3
  WHEN 'push.dispatch' THEN 2
  WHEN 'image.records' THEN 9 WHEN 'auth.password' THEN 2 WHEN 'document.output' THEN 4 WHEN 'image.storage' THEN 3 WHEN 'monitor.thresholds' THEN 6 WHEN 'auth.password.change' THEN 3
  WHEN 'email.send.ordinary' THEN 2 WHEN 'email.send.auth' THEN 2 WHEN 'email.send.commitment' THEN 2
  ELSE -1 END;
$$;

-- All families in one admission phase share a PostgreSQL STABLE statement
-- snapshot, including overrides and revision; no config lock or HTTP hop.
CREATE OR REPLACE FUNCTION public.abuse_policy_bundle_v1(p_budgets text[],p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_object_agg(b,public.abuse_effective_rules_v1(b,p_unit,p_org)) FROM unnest(p_budgets) b;
$$;
REVOKE ALL ON FUNCTION public.abuse_policy_bundle_v1(text[],bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Only numeric limits may be changed here. Algorithm/window/identity changes need a migration.
-- A batch is one audited optimistic revision; no writes to usage.
CREATE OR REPLACE FUNCTION public.set_abuse_policy_v1(p_expected_revision bigint,p_reason text,p_changes jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_revision bigint; c jsonb; r public.abuse_policy_rules; v_old jsonb; v_author text;
BEGIN
 PERFORM public.require_service_role();
 IF length(btrim(p_reason)) NOT BETWEEN 8 AND 1000 OR p_reason IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_changes) NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy batch'; END IF;
 SELECT revision INTO v_revision FROM public.abuse_policy_revision FOR UPDATE;
 IF p_expected_revision IS DISTINCT FROM v_revision THEN RAISE serialization_failure USING MESSAGE='abuse policy revision conflict'; END IF;
 v_author:=coalesce(auth.uid()::text,session_user::text);
 SELECT jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
 'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x)) INTO v_old;
 FOR c IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN ('rule_key','base_limit','target_kind','target_id','expires_at')) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported abuse policy parameter'; END IF;
  SELECT * INTO r FROM public.abuse_policy_rules WHERE rule_key=c->>'rule_key';
  IF NOT FOUND OR (c->>'base_limit')::bigint IS NULL OR (c->>'base_limit')::bigint NOT BETWEEN 1 AND r.hard_cap THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy limit'; END IF;
  IF c ? 'target_kind' THEN
   IF (c->>'target_kind'='unit' AND r.scope_kind<>'unit') OR
    (c->>'target_kind'='organization' AND r.scope_kind NOT IN ('unit','organization')) OR
    c->>'target_kind' NOT IN ('unit','organization') OR (c->>'target_id')::bigint IS NULL OR
    (c->>'expires_at')::timestamptz IS NULL OR (c->>'expires_at')::timestamptz<=statement_timestamp() OR
    (c->>'expires_at')::timestamptz>statement_timestamp()+interval '90 days' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid abuse override scope or expiry'; END IF;
   IF NOT (CASE WHEN c->>'target_kind'='unit' THEN EXISTS(SELECT 1 FROM public.units WHERE id=(c->>'target_id')::bigint)
    ELSE EXISTS(SELECT 1 FROM public.organizations WHERE id=(c->>'target_id')::bigint) END) THEN
    RAISE invalid_parameter_value USING MESSAGE='unknown abuse override target'; END IF;
   INSERT INTO public.abuse_policy_overrides VALUES(r.rule_key,c->>'target_kind',(c->>'target_id')::bigint,
    (c->>'base_limit')::bigint,(c->>'expires_at')::timestamptz,p_reason,v_author)
   ON CONFLICT(rule_key,target_kind,target_id) DO UPDATE SET base_limit=excluded.base_limit,expires_at=excluded.expires_at,reason=excluded.reason,author=excluded.author;
  ELSE
   IF c ? 'target_id' OR c ? 'expires_at' THEN RAISE invalid_parameter_value USING MESSAGE='override target required'; END IF;
   UPDATE public.abuse_policy_rules SET base_limit=(c->>'base_limit')::bigint WHERE rule_key=r.rule_key;
  END IF;
 END LOOP;
 UPDATE public.abuse_policy_revision SET revision=revision+1 RETURNING revision INTO v_revision;
 INSERT INTO public.abuse_policy_audit SELECT v_revision,clock_timestamp(),v_author,p_reason,v_old,
  jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
   'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x));
 RETURN v_revision;
END $$;
REVOKE ALL ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.abuse_effective_rules_v1(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_abuse_policy_v1(p_unit bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_read_unit_abuse_policy(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 SELECT organization INTO v_org FROM public.units WHERE id=p_unit;
 RETURN jsonb_build_object('creation',public.abuse_effective_rules_v1('occasion.creation',p_unit,v_org),
 'draft',public.abuse_effective_rules_v1('occasion.draft',p_unit,v_org),
 'usage',coalesce((SELECT jsonb_agg(jsonb_build_object('rule',u.rule_key,'amount',u.amount,'bucketAt',u.bucket_at,'expiresAt',u.expires_at))
 FROM public.abuse_budget_usage u JOIN public.abuse_policy_rules r USING(rule_key)
 WHERE u.expires_at>statement_timestamp() AND ((r.scope_kind='unit' AND u.scope_id=p_unit::text)
 OR (r.scope_kind='actor' AND u.scope_id=auth.uid()::text))),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_unit_abuse_policy_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_abuse_policy_v1(bigint) TO authenticated;
