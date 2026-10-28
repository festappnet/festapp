-- Only a server-verified Wix token may enter this issuer. It grants no Festapp rights.
CREATE OR REPLACE FUNCTION public.get_wix_checkout_configuration_internal()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('appId',app_id,'organizationId',organization_id)
  FROM eshop.checkout_origin_signing_key WHERE singleton);
END $$;
REVOKE ALL ON FUNCTION public.get_wix_checkout_configuration_internal() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_wix_checkout_configuration_internal() TO service_role;

CREATE OR REPLACE FUNCTION public.issue_wix_checkout_origin_internal(
 p_form_link text,p_instance uuid,p_site uuid,p_organization bigint,p_app uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE f public.forms; token_payload text; token_signature text; stamp bigint:=extract(epoch FROM clock_timestamp())::bigint;
BEGIN
 PERFORM public.require_service_role();
 IF p_instance IS NULL OR p_site IS NULL OR p_organization IS NULL OR p_app IS NULL
  OR p_form_link IS NULL OR length(p_form_link)>200 THEN RAISE invalid_parameter_value USING MESSAGE='INVALID_CHECKOUT_ORIGIN'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.checkout_origin_signing_key
  WHERE singleton AND organization_id=p_organization AND app_id=p_app) THEN
  RAISE invalid_parameter_value USING MESSAGE='INVALID_CHECKOUT_ORIGIN'; END IF;
 SELECT * INTO f FROM public.forms WHERE id=public.resolve_form_link_internal(p_form_link);
 IF f.id IS NULL OR f.is_open IS DISTINCT FROM true OR NOT EXISTS(
  SELECT 1 FROM public.occasions o WHERE o.id=f.occasion AND o.organization=p_organization
 ) OR public.is_demo_occasion(f.occasion) THEN
  RAISE invalid_parameter_value USING MESSAGE='FORM_UNAVAILABLE'; END IF;
 token_payload:=rtrim(translate(encode(convert_to(jsonb_build_object(
  'v',1,'channel','wix','formId',f.id,'instanceId',p_instance,'siteId',p_site,
  'verifiedAt',stamp,'expiresAt',stamp+86400)::text,'UTF8'),'base64'),E'+/\n','-_'),'=');
 SELECT encode(extensions.hmac(convert_to(token_payload,'UTF8'),secret,'sha256'),'hex')
 INTO STRICT token_signature FROM eshop.checkout_origin_signing_key WHERE singleton;
 RETURN jsonb_build_object('context',token_payload||'.'||token_signature,'expiresAt',stamp+86400);
END $$;
REVOKE ALL ON FUNCTION public.issue_wix_checkout_origin_internal(text,uuid,uuid,bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.issue_wix_checkout_origin_internal(text,uuid,uuid,bigint,uuid) TO service_role;

-- A signed context establishes origin at issuance, not an authenticated actor,
-- an active installation entitlement or App Market revenue eligibility.
CREATE OR REPLACE FUNCTION public.read_checkout_origin_internal(p_context text,p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE parts text[]; expected bytea; supplied bytea; payload jsonb; stamp bigint:=extract(epoch FROM statement_timestamp())::bigint;
BEGIN
 IF p_context IS NULL THEN RETURN NULL; END IF;
 IF length(p_context)>2048 OR p_context !~ '^[A-Za-z0-9_-]+\.[0-9a-f]{64}$' THEN RETURN NULL; END IF;
 parts:=string_to_array(p_context,'.');
 SELECT extensions.hmac(convert_to(parts[1],'UTF8'),secret,'sha256') INTO STRICT expected
  FROM eshop.checkout_origin_signing_key WHERE singleton;
 supplied:=decode(parts[2],'hex');
 -- Hash before comparing so equality timing reveals no HMAC prefix.
 IF extensions.digest(supplied,'sha256')<>extensions.digest(expected,'sha256') THEN RETURN NULL; END IF;
 payload:=convert_from(decode(translate(parts[1],'-_','+/')||repeat('=',(4-length(parts[1])%4)%4),'base64'),'UTF8')::jsonb;
 IF payload->>'v'<>'1' OR payload->>'channel'<>'wix'
  OR (payload->>'formId')::bigint IS DISTINCT FROM p_form
  OR (payload->>'expiresAt')::bigint<=stamp OR (payload->>'verifiedAt')::bigint>stamp+60
  OR (payload->>'expiresAt')::bigint-(payload->>'verifiedAt')::bigint<>86400
  OR (payload->>'instanceId')::uuid IS NULL OR (payload->>'siteId')::uuid IS NULL THEN RETURN NULL; END IF;
 RETURN payload;
EXCEPTION WHEN invalid_text_representation OR character_not_in_repertoire OR numeric_value_out_of_range THEN RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.read_checkout_origin_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.attach_checkout_origin_internal(p_order bigint,p_origin jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_origin IS NULL THEN RETURN; END IF;
 INSERT INTO eshop.order_checkout_origins(order_id,form_id,channel,instance_id,site_id,verified_at)
 VALUES(p_order,(p_origin->>'formId')::bigint,'wix',(p_origin->>'instanceId')::uuid,
  (p_origin->>'siteId')::uuid,to_timestamp((p_origin->>'verifiedAt')::bigint));
END $$;
REVOKE ALL ON FUNCTION public.attach_checkout_origin_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
