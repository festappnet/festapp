-- Wix checkout provenance only; no fees, financial reporting or authorization grants.

-- Canonical source: database/tables/checkout_origins.sql
-- Provenance only. These records never authorize a purchase or establish a fee.
CREATE TABLE IF NOT EXISTS eshop.checkout_origin_signing_key (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 secret bytea NOT NULL CHECK(octet_length(secret)=32),
 app_id uuid NOT NULL,
 organization_id bigint NOT NULL CHECK(organization_id>0)
);
-- Deployment configuration for the assigned vstupenky.online application.
INSERT INTO eshop.checkout_origin_signing_key(singleton,secret,app_id,organization_id)
 VALUES(true,extensions.gen_random_bytes(32),'9c099206-ce3d-43de-bd9d-deb96bb4f51e',3)
 ON CONFLICT(singleton) DO NOTHING;
CREATE TABLE IF NOT EXISTS eshop.order_checkout_origins (
 order_id bigint PRIMARY KEY REFERENCES eshop.orders(id) ON DELETE CASCADE,
 form_id bigint NOT NULL REFERENCES public.forms(id),
 channel text NOT NULL CHECK(channel='wix'),
 instance_id uuid NOT NULL,
 site_id uuid NOT NULL,
 verified_at timestamptz NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE eshop.checkout_origin_signing_key ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.order_checkout_origins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.checkout_origin_signing_key,eshop.order_checkout_origins FROM PUBLIC,anon,authenticated,service_role;


-- Canonical source: database/functions/eshop_orders/checkout_origin.sql
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

-- Canonical source: database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_command_internal(
  p_order jsonb,p_command_id uuid,p_client_id uuid,p_context jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_symbol text; v_before_users uuid[]; v_actor_kind text; v_origin jsonb; v_form bigint;
BEGIN
  IF p_order IS NULL OR jsonb_typeof(p_order)<>'object'
    OR octet_length(p_order::text)>4194304 OR p_command_id IS NULL
    OR (v_actor IS NULL AND p_client_id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order command'; END IF;
  SELECT f.occasion INTO v_occasion FROM public.forms f
    WHERE f.key=NULLIF(p_order->>'form','')::uuid;
  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket order form not found'; END IF;
  v_hash:=encode(extensions.digest(convert_to((jsonb_build_object(
    'occasion',v_occasion,'order',p_order-'stripePaymentSource')
      ||CASE WHEN p_context IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('administration',p_context) END)::text,'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,p_client_id,v_hash);
    v_actor_kind:='unknown';
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,v_actor,v_hash);
    v_actor_kind:='user';
  END IF;
  IF v_begin->>'disposition'='replay' THEN
    v_result := v_begin->'response';
    IF v_result#>'{data,order}' IS NOT NULL AND v_result#>>'{data,order,order_symbol}' IS NULL THEN
      v_symbol := public.read_order_identity((v_result#>>'{data,order,id}')::bigint,
        v_occasion, (SELECT organization FROM public.occasions WHERE id=v_occasion));
      IF v_symbol IS NOT NULL THEN
        v_result := jsonb_set(v_result, '{data,order,order_symbol}', to_jsonb(v_symbol));
      END IF;
    END IF;
    RETURN public.project_local_payment_reference_order_internal(v_result);
  END IF;
  IF p_order ? 'checkoutOrigin' THEN
    SELECT id INTO v_form FROM public.forms WHERE key=(p_order->>'form')::uuid;
    v_origin:=public.read_checkout_origin_internal(p_order->>'checkoutOrigin',v_form);
    IF v_origin IS NULL THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',400,
        jsonb_build_object('code',400,'errorCode','CHECKOUT_CONTEXT_EXPIRED'));
    END IF;
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.create_ticket_order_internal_v1(p_order-ARRAY['stripePaymentSource','checkoutOrigin']);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  PERFORM public.attach_checkout_origin_internal((v_result#>>'{order,id}')::bigint,v_origin);
  IF v_result#>>'{order,payment_info,payment_method}'='stripe' THEN
    PERFORM public.attach_stripe_order_pay_source_internal((v_result#>>'{order,id}')::bigint,p_command_id,p_order->'stripePaymentSource');
  END IF;
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,p_order->>'lang');
  IF p_context IS NOT NULL THEN v_result:=v_result||jsonb_build_object('adminQuote',p_context->'quote','paymentPreparationPolicy','leased_keep_pending'); END IF;
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.create',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Ticket order','changedFields',jsonb_build_array(
        'tickets','products','allocations','membership'))),v_before_users,v_result,
    v_actor_kind);
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_command_internal(jsonb,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Released RPC signature and ordinary checkout hashes remain unchanged.
CREATE OR REPLACE FUNCTION public.create_ticket_order_client_sync_v1(p_order jsonb,p_command_id uuid,p_client_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.create_ticket_order_command_internal(p_order,p_command_id,p_client_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) TO anon,authenticated;
