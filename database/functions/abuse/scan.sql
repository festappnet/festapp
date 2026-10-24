-- Domain callers verify the actual scan secret. Invalid inputs never gain a new
-- arbitrary limiter key: only an existing occasion or the shared unknown scope.
-- Return rejection rather than raise so failed proof consumption can commit.
-- Only the gateway-owned header is an IP identity; the gateway must replace it.
-- Missing/malformed context shares a bounded fail-closed unknown source.
CREATE OR REPLACE FUNCTION public.abuse_request_source_v1() RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE source text;
BEGIN
 BEGIN source:=((nullif(current_setting('request.headers',true),'')::jsonb)->>'x-festapp-client-ip')::inet::text;
 EXCEPTION WHEN invalid_text_representation THEN source:=NULL; END;
 RETURN public.abuse_recipient_key_v1(coalesce(source,'unknown'));
END $$;
REVOKE ALL ON FUNCTION public.abuse_request_source_v1() FROM PUBLIC,anon,authenticated,service_role;

-- Check before comparing any proof, with the same locks used by consumption.
-- Authenticated order viewers have an available recovery path during anonymous
-- source exhaustion; a correct staff secret alone never bypasses the gate.
CREATE OR REPLACE FUNCTION public.check_scan_attempt_budget_v1(p_occasion bigint DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE policies jsonb; policy jsonb; family text; scopes jsonb;
BEGIN
 IF auth.uid() IS NOT NULL AND p_occasion IS NOT NULL AND public.get_is_editor_order_view_on_occasion(p_occasion) THEN RETURN true; END IF;
 policies:=public.abuse_policy_bundle_v1(ARRAY['scan.invalid.global','scan.invalid.source'],NULL,NULL);
 scopes:=jsonb_build_object('global','all','recipient',public.abuse_request_source_v1());
 FOREACH family IN ARRAY ARRAY['scan.invalid.global','scan.invalid.source'] LOOP
  policy:=policies->family;
  -- A zero-cost check must deny at the limit, not only after one more guess.
  policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(jsonb_set(r,'{base_limit}',to_jsonb((r->>'base_limit')::bigint-1))) FROM jsonb_array_elements(policy->'rules') r));
  IF NOT public.abuse_charge_v1(policy,scopes,(SELECT jsonb_object_agg(r->>'rule_key',0) FROM jsonb_array_elements(policy->'rules') r),true) THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.check_scan_attempt_budget_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_scan_access_v1(p_occasion bigint,p_authorized boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint;
BEGIN
 SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion;
 IF p_authorized IS DISTINCT FROM true OR un IS NULL THEN
  IF public.abuse_charge_v1(public.abuse_effective_rules_v1('scan.invalid.global',NULL,NULL),jsonb_build_object('global','all'),'{}',true) THEN
   PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('scan.invalid.source',NULL,NULL),jsonb_build_object('recipient',public.abuse_request_source_v1()),'{}',true);
  END IF;
  RETURN false;
 END IF;
 RETURN public.abuse_charge_v1(public.abuse_effective_rules_v1('scan.operation',un,org),
  jsonb_build_object('unit',un,'organization',org),'{}',true);
END $$;
REVOKE ALL ON FUNCTION public.admit_scan_access_v1(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_scan_password_reset_v1(p_occasion bigint,p_user uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint;
BEGIN
 SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion;
 IF un IS NULL OR p_user IS NULL THEN RETURN false; END IF;
 RETURN public.abuse_charge_v1(public.abuse_effective_rules_v1('scan.password',un,org),
  jsonb_build_object('unit',un,'recipient',public.abuse_recipient_key_v1(p_user::text)),'{}',true);
END $$;
REVOKE ALL ON FUNCTION public.admit_scan_password_reset_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX IF NOT EXISTS occasions_hidden_scan_secret_idx ON public.occasions_hidden(secret);
