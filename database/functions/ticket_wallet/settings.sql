CREATE OR REPLACE FUNCTION public.ticket_wallet_enabled(p_feature jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
 IF NOT coalesce(p_feature ? 'wallet_enabled',false) THEN RETURN true; END IF;
 IF jsonb_typeof(p_feature->'wallet_enabled') IS DISTINCT FROM 'boolean' THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid ticket wallet preference'; END IF;
 RETURN (p_feature->>'wallet_enabled')::boolean;
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_enabled(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_enabled(jsonb) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_ready(p_organization bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.is_service_role() AND NOT EXISTS(SELECT 1 FROM public.units u WHERE u.organization=p_organization AND public.can_create_occasion(u.id)) THEN RETURN false; END IF;
 RETURN EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=p_organization AND (publishing_ready OR apple_publishing_ready));
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_ready(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_ready(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_fingerprint(p_occasion bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT coalesce((f->>'is_enabled')::boolean,false)::text||'/'||public.ticket_wallet_enabled(f)::text||'/'||public.ticket_wallet_ready(o.organization)::text||'/'||coalesce((SELECT publishing_ready::text||'/'||apple_publishing_ready::text||'/'||collection_enabled::text FROM eshop.ticket_wallet_integrations WHERE organization=o.organization),'false/false/false')
 FROM public.occasions o LEFT JOIN LATERAL (SELECT x f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket') x ON true WHERE o.id=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_fingerprint(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_fingerprint(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.validate_ticket_wallet_appearance(p_feature jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE appearance jsonb:=p_feature->'wallet_appearance'; k text; value text;
BEGIN
 IF appearance IS NULL THEN RETURN; END IF;
 IF jsonb_typeof(appearance) IS DISTINCT FROM 'object' OR octet_length(appearance::text)>8192
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(appearance) key WHERE key NOT IN ('background_color','logo','hero_image')) THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid Google Wallet appearance'; END IF;
 FOR k,value IN SELECT key,appearance->>key FROM jsonb_object_keys(appearance) key LOOP
  IF value IS NULL THEN CONTINUE; END IF;
  IF jsonb_typeof(appearance->k) IS DISTINCT FROM 'string' OR
   (k='background_color' AND value !~ '^#?[a-fA-F0-9]{6}$') OR
   (k IN ('logo','hero_image') AND (length(value)>2048 OR value !~ '^https://(img\.festapp\.net/(images|assets)/|a\.img\.festapp\.net/images/)[^?#[:space:]]+$')) THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid Google Wallet appearance'; END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.validate_ticket_wallet_appearance(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_ticket_wallet_appearance(jsonb) TO authenticated,service_role;
