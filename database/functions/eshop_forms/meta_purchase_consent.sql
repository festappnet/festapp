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
  AND public.form_measurement_visitor_role_internal(f.id)<>'staff';
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
 email text;
BEGIN
 IF jsonb_typeof(p_consent) IS DISTINCT FROM 'object'
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
 INSERT INTO analytics.meta_purchase_deliveries(order_id,unit,connector_revision,consent_revision,consent_scope,consent_decided_at,consent_snapshot,email_hash,client_agent,source_url)
 VALUES (p_order,details.unit,details.revision,p_consent->>'revision',
   public.meta_purchase_consent_scope_internal(p_consent),(p_consent->>'timestamp')::timestamptz,
   jsonb_build_object('source',p_consent->'source','timestamp',p_consent->'timestamp',
     'consentRevision',p_consent->'consentRevision','websiteOrigin',details.website_origin,
     'ad_storage',true,'ad_user_data',true,'ad_personalization',true)
     || CASE WHEN p_consent ? 'binding' THEN jsonb_build_object('binding',jsonb_build_object('id',p_consent#>'{binding,id}','version',p_consent#>'{binding,version}')) ELSE '{}'::jsonb END,
   encode(extensions.digest(email,'sha256'),'hex'),agent,CASE WHEN p_consent->>'source'='klaro' THEN details.website_origin||'/form/'||details.link ELSE details.website_origin||'/' END)
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
  done_at=clock_timestamp(),lease=NULL,lease_until=NULL,consent_snapshot=NULL,email_hash=NULL,client_agent=NULL,source_url=NULL
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
