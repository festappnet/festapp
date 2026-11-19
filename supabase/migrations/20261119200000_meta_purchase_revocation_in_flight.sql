-- Preserve the prepared receipt fence after consent withdrawal without rescheduling delivery.

-- SOURCE: eshop_forms/meta_purchase_consent.sql
-- Policy gates and destination/notice binding are shared by checkout and delivery.
CREATE OR REPLACE FUNCTION public.meta_purchase_consent_revision_internal(p_form bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT md5(jsonb_build_array(c.revision,c.dataset,c.website_origin,c.test_event_code,
         public.unit_measurement_consent_scope_internal(c.unit)->>'consentRevision')::text)
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN analytics.meta_purchase_connectors c ON c.unit=public.form_meta_purchase_unit_internal(f.id)
 WHERE f.id=p_form
  AND public.form_conversion_policy_allows_internal(public.form_measurement_status_internal(f.id));
$$;
REVOKE ALL ON FUNCTION public.meta_purchase_consent_revision_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_meta_purchase_consent(p_form_link text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('revision',v.revision,'origin',c.website_origin,
     'privacyUrl',u.data->>'measurement_privacy_url')
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN public.units u ON u.id=o.unit JOIN analytics.meta_purchase_connectors c ON c.unit=u.id
 CROSS JOIN LATERAL (SELECT public.meta_purchase_consent_revision_internal(f.id) revision) v
 WHERE f.id=public.resolve_form_link_internal(p_form_link) AND public.can_read_public_form_measurement(f.id) AND v.revision IS NOT NULL
  AND c.paused_at IS NULL AND public.form_measurement_visitor_role_internal(f.id)<>'staff'
  AND public.meta_purchase_retention_ready_internal();
$$;
REVOKE ALL ON FUNCTION public.get_meta_purchase_consent(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_meta_purchase_consent(text) TO anon,authenticated;

-- Browser assertions are not credentials. Bind every accepted assertion to the
-- current server-owned notice, destination and (for remote sources) saved website.
-- This checks durable consent, not the 60-second transport lease used at capture.
CREATE OR REPLACE FUNCTION public.meta_purchase_snapshot_valid_internal(p_unit bigint,p_snapshot jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE c analytics.meta_purchase_connectors; b analytics.website_consent_bindings; decision timestamptz; service_origin text;
BEGIN
 IF jsonb_typeof(p_snapshot) IS DISTINCT FROM 'object'
  OR coalesce(p_snapshot->>'source','') NOT IN ('klaro','cookiebot','cookieconsent','wix')
  OR p_snapshot->'ad_storage' IS DISTINCT FROM 'true'::jsonb
  OR p_snapshot->'ad_user_data' IS DISTINCT FROM 'true'::jsonb
  OR p_snapshot->'ad_personalization' IS DISTINCT FROM 'true'::jsonb
  OR p_snapshot->>'consentRevision' IS DISTINCT FROM public.unit_measurement_consent_scope_internal(p_unit)->>'consentRevision'
  OR coalesce(p_snapshot->>'timestamp','') !~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$' THEN RETURN false; END IF;
 BEGIN decision:=(p_snapshot->>'timestamp')::timestamptz; EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN RETURN false; END;
 IF decision>statement_timestamp() OR decision<=statement_timestamp()-interval '365 days' THEN RETURN false; END IF;
 SELECT * INTO c FROM analytics.meta_purchase_connectors WHERE unit=p_unit AND enabled AND paused_at IS NULL;
 IF NOT FOUND OR p_snapshot->>'websiteOrigin' IS DISTINCT FROM c.website_origin THEN RETURN false; END IF;
 IF p_snapshot->>'source'='klaro' THEN
  SELECT rtrim(org.data->>'DEFAULT_URL','/') INTO service_origin FROM public.units u JOIN public.organizations org ON org.id=u.organization WHERE u.id=p_unit;
  RETURN coalesce(NOT p_snapshot ? 'binding' AND c.website_origin=service_origin
   AND decision>statement_timestamp()-interval '180 days',false);
 END IF;
 SELECT * INTO b FROM analytics.website_consent_bindings WHERE unit=p_unit
  AND id::text=p_snapshot#>>'{binding,id}' AND version::text=p_snapshot#>>'{binding,version}'
  AND website_origin=c.website_origin;
 RETURN coalesce(FOUND AND decision>=b.confirmed_at AND public.website_consent_binding_effective_internal(b)
  AND b.provider_config->>'provider'=p_snapshot->>'source'
  AND p_snapshot->>'source' IN ('cookiebot','cookieconsent','wix'),false);
END $$;
REVOKE ALL ON FUNCTION public.meta_purchase_snapshot_valid_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Retain only a digest of the non-contact consent scope and the decision time
-- for comparisons after matching data and the full snapshot have been scrubbed.
CREATE OR REPLACE FUNCTION public.meta_purchase_consent_scope_internal(p_snapshot jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(jsonb_build_array(p_snapshot->>'source',p_snapshot->>'websiteOrigin',
  p_snapshot->>'consentRevision',p_snapshot#>>'{binding,id}',p_snapshot#>>'{binding,version}')::text,'sha256'),'hex');
$$;
REVOKE ALL ON FUNCTION public.meta_purchase_consent_scope_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.capture_meta_purchase_consent_internal(p_order bigint,p_consent jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE
 details record;
 agent text:=p_consent->>'userAgent';
 email text; phone text; prefixes jsonb; address inet; fbp text; fbc text;
BEGIN
 IF NOT public.meta_purchase_retention_ready_internal()
    OR jsonb_typeof(p_consent) IS DISTINCT FROM 'object'
    OR coalesce(length(agent),0) NOT BETWEEN 1 AND 512 OR agent ~ '[[:cntrl:]]'
    OR coalesce(p_consent->>'revision','') !~ '^[a-f0-9]{32}$'
 THEN RETURN; END IF;
 IF p_consent->>'source' IS DISTINCT FROM 'klaro' THEN
  IF coalesce(p_consent->>'transportExpiresAt','') !~ '^[0-9]{13}$' THEN RETURN; END IF;
  IF (p_consent->>'transportExpiresAt')::bigint<=extract(epoch FROM clock_timestamp())*1000
    OR (p_consent->>'transportExpiresAt')::bigint>extract(epoch FROM clock_timestamp())*1000+60000 THEN RETURN; END IF;
 END IF;
 SELECT o.form,o.price,o.data,oc.unit,f.link,c.website_origin,c.revision
 INTO details
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN public.forms f ON f.id=o.form
 JOIN analytics.meta_purchase_connectors c ON c.unit=oc.unit
 WHERE o.id=p_order;
 IF NOT FOUND OR coalesce(details.price,0)<=0
    OR public.form_measurement_visitor_role_internal(details.form)='staff'
    OR coalesce(details.link,'') !~ '^[a-zA-Z0-9_-]+$'
    OR public.meta_purchase_consent_revision_internal(details.form) IS DISTINCT FROM p_consent->>'revision'
    OR public.meta_purchase_snapshot_valid_internal(details.unit,p_consent) IS DISTINCT FROM true
 THEN RETURN; END IF;
 email:=lower(btrim(details.data->>'email'));
 IF coalesce(length(email),0) NOT BETWEEN 3 AND 254 OR email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RETURN; END IF;
 -- Optional matching data can only degrade to NULL; it never fails checkout.
 BEGIN
  prefixes:=public.get_effective_form_data(details.form)->'phone_prefixes';
  phone:=public.meta_purchase_phone_internal(details.data->>'phone',
   CASE WHEN jsonb_typeof(prefixes)='array' THEN CASE WHEN jsonb_array_length(prefixes)=1 THEN prefixes->>0 END END);
 EXCEPTION WHEN OTHERS THEN phone:=NULL;
 END;
 BEGIN
  -- This header is replaced at the public Caddy boundary, including REST RPCs.
  address:=public.meta_purchase_ip_internal(nullif(current_setting('request.headers',true),'')::jsonb->>'x-festapp-client-ip');
 EXCEPTION WHEN OTHERS THEN address:=NULL;
 END;
 BEGIN
  fbp:=public.meta_purchase_browser_id_internal(p_consent#>>'{matching,fbp}');
  fbc:=public.meta_purchase_browser_id_internal(p_consent#>>'{matching,fbc}');
 EXCEPTION WHEN OTHERS THEN fbp:=NULL; fbc:=NULL;
 END;
 INSERT INTO analytics.meta_purchase_deliveries(order_id,unit,connector_revision,consent_revision,consent_scope,consent_decided_at,consent_snapshot,email_hash,client_agent,source_url,phone_hash,fbp,fbc,client_ip)
 VALUES (p_order,details.unit,details.revision,p_consent->>'revision',
   public.meta_purchase_consent_scope_internal(p_consent),(p_consent->>'timestamp')::timestamptz,
   jsonb_build_object('source',p_consent->'source','timestamp',p_consent->'timestamp',
     'consentRevision',p_consent->'consentRevision','websiteOrigin',details.website_origin,
     'ad_storage',true,'ad_user_data',true,'ad_personalization',true)
     || CASE WHEN p_consent ? 'binding' THEN jsonb_build_object('binding',jsonb_build_object('id',p_consent#>'{binding,id}','version',p_consent#>'{binding,version}')) ELSE '{}'::jsonb END,
   encode(extensions.digest(email,'sha256'),'hex'),agent,CASE WHEN p_consent->>'source'='klaro' THEN details.website_origin||'/form/'||details.link ELSE details.website_origin||'/' END,
   CASE WHEN phone IS NOT NULL THEN encode(extensions.digest(phone,'sha256'),'hex') END,
   fbp,fbc,address)
 ON CONFLICT(order_id) DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.capture_meta_purchase_consent_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Automated denial can affect only orders captured under that same consent
-- scope, and only if the saved denial is newer than the captured grant.
CREATE OR REPLACE FUNCTION public.revoke_meta_purchase_consent(p_token text,p_order_id bigint,p_denial jsonb)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE overview jsonb; decision timestamptz; scope_hash text; affected integer;
BEGIN
 overview:=public.get_customer_order_overview_internal(p_token,p_order_id);
 IF overview->>'code' IS DISTINCT FROM '200' THEN RETURN false; END IF;
 IF p_denial IS NOT NULL THEN
  IF jsonb_typeof(p_denial) IS DISTINCT FROM 'object' OR octet_length(p_denial::text)>2048
    OR coalesce(p_denial->>'timestamp','') !~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$'
    OR NOT (p_denial @> '{"ad_storage":false}' OR p_denial @> '{"ad_user_data":false}' OR p_denial @> '{"ad_personalization":false}')
  THEN RETURN false; END IF;
  BEGIN decision:=(p_denial->>'timestamp')::timestamptz;
  EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN RETURN false; END;
  IF decision>statement_timestamp() OR decision<=statement_timestamp()-interval '365 days' THEN RETURN false; END IF;
  scope_hash:=public.meta_purchase_consent_scope_internal(p_denial);
 END IF;
 UPDATE analytics.meta_purchase_deliveries SET revoked_at=clock_timestamp(),status=CASE WHEN status='pending' THEN 'revoked' ELSE status END,
  -- Prepare commits the send authorization; keep its live receipt fence after withdrawal.
  done_at=clock_timestamp(),
  lease=CASE WHEN prepared AND lease_until>clock_timestamp() THEN lease END,
  lease_until=CASE WHEN prepared AND lease_until>clock_timestamp() THEN lease_until END,
  consent_snapshot=NULL,email_hash=NULL,phone_hash=NULL,fbp=NULL,fbc=NULL,client_ip=NULL,client_agent=NULL,source_url=NULL
 WHERE order_id IN(SELECT (value->>'id')::bigint FROM jsonb_array_elements(overview->'orders'))
   AND revoked_at IS NULL
   AND (p_denial IS NULL OR (consent_scope=scope_hash AND consent_decided_at<decision));
 GET DIAGNOSTICS affected=ROW_COUNT;
 RETURN p_denial IS NULL OR affected>0;
END $$;
REVOKE ALL ON FUNCTION public.revoke_meta_purchase_consent(text,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_meta_purchase_consent(text,bigint,jsonb) TO anon,authenticated;

-- The released manual action never depends on a working CMP.
CREATE OR REPLACE FUNCTION public.revoke_meta_purchase_consent(p_token text,p_order_id bigint)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN public.revoke_meta_purchase_consent(p_token,p_order_id,NULL);
END $$;
REVOKE ALL ON FUNCTION public.revoke_meta_purchase_consent(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_meta_purchase_consent(text,bigint) TO anon,authenticated;

-- SOURCE: eshop_forms/meta_purchase_worker.sql
CREATE OR REPLACE FUNCTION public.claim_meta_purchase_deliveries(p_limit integer)
RETURNS TABLE(order_id bigint, lease uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN QUERY
 WITH due AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  JOIN analytics.meta_purchase_connectors c ON c.unit=d.unit
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind='order_fully_paid'
  WHERE d.status='pending' AND c.enabled AND c.paused_at IS NULL
    AND public.form_order_purchase_timing_internal(d.order_id)='paid'
    AND public.form_order_purchase_capi_required_internal(d.order_id) IS TRUE
    AND d.next_attempt_at<=clock_timestamp() AND (d.lease_until IS NULL OR d.lease_until<=clock_timestamp())
  ORDER BY d.next_attempt_at,d.order_id LIMIT least(greatest(coalesce(p_limit,1),1),20)
  FOR UPDATE OF d SKIP LOCKED
 )
 UPDATE analytics.meta_purchase_deliveries d SET lease=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes',prepared=false
 FROM due WHERE d.order_id=due.order_id RETURNING d.order_id,d.lease;
END $$;

-- Revalidate as close to sending as possible. Claiming does not disclose any
-- matching data or confer permission after withdrawal or destination changes.
CREATE OR REPLACE FUNCTION public.prepare_meta_purchase_delivery(p_order_id bigint,p_lease uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
 delivery analytics.meta_purchase_deliveries;
 connector analytics.meta_purchase_connectors;
 fact analytics.conversion_facts;
 o eshop.orders;
 token text;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND status='pending' AND lease=p_lease AND lease_until>clock_timestamp() AND NOT prepared
 FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO connector FROM analytics.meta_purchase_connectors WHERE unit=delivery.unit;
 IF connector.enabled IS DISTINCT FROM true OR connector.paused_at IS NOT NULL THEN RETURN NULL; END IF;
 SELECT * INTO fact FROM analytics.conversion_facts WHERE "order"=p_order_id AND kind='order_fully_paid';
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 IF public.form_order_purchase_timing_internal(p_order_id) IS DISTINCT FROM 'paid'
    OR public.form_order_purchase_capi_required_internal(p_order_id) IS DISTINCT FROM true
    OR delivery.connector_revision IS DISTINCT FROM connector.revision
    OR delivery.consent_revision IS DISTINCT FROM public.meta_purchase_consent_revision_internal(o.form)
    OR public.meta_purchase_snapshot_valid_internal(delivery.unit,delivery.consent_snapshot) IS DISTINCT FROM true
    OR delivery.consent_at>fact.created_at
    OR delivery.consent_at<clock_timestamp()-interval '30 days'
    OR fact.created_at<clock_timestamp()-interval '7 days'
    OR delivery.attempts>=6
    OR fact.payload IS DISTINCT FROM jsonb_build_object('value',o.price,'currency',trim(o.currency_code))
    OR NOT public.form_paid_conversion_eligible_internal(p_order_id) THEN
  UPDATE analytics.meta_purchase_deliveries SET status='invalid',done_at=clock_timestamp(),
   lease=NULL,lease_until=NULL,consent_snapshot=NULL,email_hash=NULL,phone_hash=NULL,fbp=NULL,fbc=NULL,client_ip=NULL,client_agent=NULL,source_url=NULL
  WHERE order_id=p_order_id;
  RETURN NULL;
 END IF;
 SELECT decrypted_secret INTO token FROM vault.decrypted_secrets WHERE id=connector.vault_secret;
 IF coalesce(length(token),0) NOT BETWEEN 16 AND 4096 THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=connector.unit AND revision=connector.revision;
  RETURN NULL;
 END IF;
 -- Recheck retention even if claim used an older worker or cleanup was bounded.
 IF delivery.consent_at<=clock_timestamp()-interval '7 days' THEN delivery.client_ip:=NULL; END IF;
 UPDATE analytics.meta_purchase_deliveries SET client_ip=delivery.client_ip,attempts=attempts+1,prepared=true WHERE order_id=p_order_id;
 RETURN jsonb_build_object('dataset',connector.dataset,'accessToken',token,'testEventCode',connector.test_event_code,
  'eventId',fact.event_id,'eventTime',floor(extract(epoch FROM fact.created_at)),
  'value',fact.payload->'value','currency',fact.payload->>'currency',
  'phoneHash',CASE WHEN delivery.phone_hash ~ '^[0-9a-f]{64}$' THEN delivery.phone_hash END,'fbp',public.meta_purchase_browser_id_internal(delivery.fbp),
  'fbc',public.meta_purchase_browser_id_internal(delivery.fbc),'clientIp',host(delivery.client_ip),
  'emailHash',delivery.email_hash,'clientAgent',delivery.client_agent,'sourceUrl',delivery.source_url);
END $$;

CREATE OR REPLACE FUNCTION public.finish_meta_purchase_delivery(p_order_id bigint,p_lease uuid,p_result text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE delivery analytics.meta_purchase_deliveries; final_status text;
BEGIN
 PERFORM public.require_service_role();
 IF p_result IS NULL OR p_result NOT IN ('sent','retry','credentials','rejected') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid delivery result'; END IF;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND lease=p_lease AND status IN ('pending','revoked') AND prepared FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_result='credentials' THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=delivery.unit AND revision=delivery.connector_revision;
 END IF;
 -- Withdrawal scrubs the payload but must still record the authorized in-flight result.
 IF delivery.status='revoked' THEN
  UPDATE analytics.meta_purchase_deliveries
  SET error_code=CASE WHEN p_result='sent' THEN 'sent_in_flight' ELSE p_result END,
   lease=NULL,lease_until=NULL
  WHERE order_id=p_order_id;
  RETURN true;
 END IF;
 final_status:=CASE WHEN p_result='sent' THEN 'sent'
  WHEN p_result='rejected' OR delivery.attempts>=6 THEN 'failed' ELSE 'pending' END;
 UPDATE analytics.meta_purchase_deliveries SET status=final_status,error_code=nullif(p_result,'sent'),
  next_attempt_at=clock_timestamp()+interval '2 minutes'*power(2,greatest(delivery.attempts-1,0)),
  lease=NULL,lease_until=NULL,done_at=CASE WHEN final_status<>'pending' THEN clock_timestamp() END,
  consent_snapshot=CASE WHEN final_status='pending' THEN consent_snapshot END,
  email_hash=CASE WHEN final_status='pending' THEN email_hash END,
  phone_hash=CASE WHEN final_status='pending' THEN phone_hash END,
  fbp=CASE WHEN final_status='pending' THEN fbp END,
  fbc=CASE WHEN final_status='pending' THEN fbc END,
  client_ip=CASE WHEN final_status='pending' AND consent_at>clock_timestamp()-interval '7 days' THEN client_ip END,
  client_agent=CASE WHEN final_status='pending' THEN client_agent END,
  source_url=CASE WHEN final_status='pending' THEN source_url END
 WHERE order_id=p_order_id;
 RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.claim_meta_purchase_deliveries(integer),
 public.prepare_meta_purchase_delivery(bigint,uuid),public.finish_meta_purchase_delivery(bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_meta_purchase_deliveries(integer),
 public.prepare_meta_purchase_delivery(bigint,uuid),public.finish_meta_purchase_delivery(bigint,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.wake_meta_purchase_worker()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE endpoint text;
BEGIN
 IF NOT EXISTS(
  SELECT FROM analytics.meta_purchase_deliveries d
  JOIN analytics.meta_purchase_connectors c ON c.unit=d.unit AND c.enabled AND c.paused_at IS NULL
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind='order_fully_paid'
  WHERE d.status='pending' AND d.next_attempt_at<=clock_timestamp()
   AND (d.lease_until IS NULL OR d.lease_until<=clock_timestamp())
   -- Same cohort filter as claiming, so unclaimable rows do not wake the worker.
   AND public.form_order_purchase_timing_internal(d.order_id)='paid'
   AND public.form_order_purchase_capi_required_internal(d.order_id) IS TRUE
) THEN RETURN; END IF;
 SELECT regexp_replace(worker_url,'/process-email-queue$','/process-meta-purchases') INTO endpoint
 FROM public.email_capacity
 WHERE worker_url LIKE '%/process-email-queue';
 IF endpoint IS NULL THEN RETURN; END IF;
 PERFORM net.http_post(url:=endpoint,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),
   timeout_milliseconds:=90000);
END $$;
REVOKE ALL ON FUNCTION public.wake_meta_purchase_worker() FROM PUBLIC,anon,authenticated,service_role;
