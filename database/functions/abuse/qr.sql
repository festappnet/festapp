-- Separate service RPC commits attempts before credential verification/session work.
CREATE OR REPLACE FUNCTION public.consume_qr_login_attempt_v1(p_occasion bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE accepted boolean; policy jsonb; cap bigint;
BEGIN
 PERFORM public.require_service_role();
 IF p_occasion IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion) THEN
  RETURN jsonb_build_object('allowed',false); END IF;
 policy:=public.abuse_effective_rules_v1(CASE WHEN p_occasion IS NULL THEN 'qr.global' ELSE 'qr.proof' END,NULL,NULL);
 accepted:=public.abuse_charge_v1(policy,jsonb_build_object('global','all','recipient',p_occasion::text),'{}',true);
 SELECT base_limit INTO cap FROM public.abuse_policy_rules WHERE rule_key='qr.payload.bytes';
 IF cap IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 RETURN jsonb_build_object('allowed',accepted,'maxBodyBytes',cap);
END $$;
REVOKE ALL ON FUNCTION public.consume_qr_login_attempt_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.consume_qr_login_attempt_v1(bigint) TO service_role;
