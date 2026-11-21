-- Saved websites remain available even before a separate runtime is provisioned.
CREATE OR REPLACE FUNCTION public.unit_meta_purchase_origins_internal(p_unit bigint)
RETURNS text[] LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT ARRAY(SELECT DISTINCT origin FROM public.units u CROSS JOIN LATERAL (
  SELECT unnest(public.unit_measurement_parent_origins_internal(p_unit)) origin
  UNION ALL SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(u.data->'measurement_websites')='array'
   THEN u.data->'measurement_websites' ELSE '[]'::jsonb END)
 ) sites WHERE u.id=p_unit AND origin ~ '^https://[a-z0-9.-]+$' ORDER BY origin);
$$;
REVOKE ALL ON FUNCTION public.unit_meta_purchase_origins_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_meta_purchase(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF NOT public.can_manage_unit_meta_purchase(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Meta CAPI access denied'; END IF;
 SELECT jsonb_build_object('dataset',c.dataset,'website_origin',c.website_origin,'test_event_code',c.test_event_code,
  'enabled',c.enabled,'paused_at',c.paused_at,'token_saved',c.vault_secret IS NOT NULL,'revision',c.revision,
  -- Only the stored masked suffix is projected; reads never decrypt the Vault secret.
  'token_hint',c.token_hint,'token_changed_at',c.token_changed_at,
  'website_ready',coalesce(c.website_origin=ANY(public.unit_meta_purchase_origins_internal(p_unit)) AND (
   c.website_origin=(SELECT rtrim(org.data->>'DEFAULT_URL','/') FROM public.units u
    JOIN public.organizations org ON org.id=u.organization WHERE u.id=p_unit)
   OR EXISTS(SELECT FROM analytics.website_consent_bindings b WHERE b.unit=p_unit
    AND b.website_origin=c.website_origin AND b.provider_config->>'provider' IN ('cookiebot','cookieconsent','wix','complianz')
    AND public.website_consent_binding_effective_internal(b))
  ),false))
 INTO result FROM analytics.meta_purchase_connectors c WHERE c.unit=p_unit;
 RETURN coalesce(result,'{}'::jsonb)||jsonb_build_object('allowed',true,
  'websites',to_jsonb(public.unit_meta_purchase_origins_internal(p_unit)),
  'queue',(SELECT jsonb_build_object('pending',count(*) FILTER(WHERE status='pending'),
    'sent',count(*) FILTER(WHERE status='sent'),'failed',count(*) FILTER(WHERE status='failed'),
    'revoked',count(*) FILTER(WHERE status='revoked'),
    'invalid',count(*) FILTER(WHERE status='invalid'),'expired',count(*) FILTER(WHERE status='expired')) FROM analytics.meta_purchase_deliveries
    WHERE unit=p_unit AND coalesce(done_at,consent_at)>=statement_timestamp()-interval '30 days'),
  'last_error',coalesce(
    (SELECT jsonb_build_object('code',error_code,'status',status,'at',outcome_at) FROM (
      SELECT error_code,status,coalesce(done_at,next_attempt_at-interval '2 minutes'*power(2,greatest(attempts-1,0))) AS outcome_at
      FROM analytics.meta_purchase_deliveries WHERE unit=p_unit AND error_code IS NOT NULL
     ) outcomes ORDER BY outcome_at DESC LIMIT 1),
    (SELECT jsonb_build_object('code','credentials','status','pending','at',paused_at)
      FROM analytics.meta_purchase_connectors WHERE unit=p_unit AND paused_at IS NOT NULL)),
  'forms',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'enabled',m.form IS NOT NULL,
     'measurement_ready',EXISTS(SELECT FROM public.form_measurement_decision_internal(f.id) d WHERE d.conversion_eligible)) ORDER BY f.id),'[]'::jsonb)
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    LEFT JOIN analytics.meta_purchase_forms m ON m.form=f.id AND m.unit=p_unit WHERE o.unit=p_unit));
END $$;

CREATE OR REPLACE FUNCTION public.save_unit_meta_purchase(p_unit bigint,p_dataset text,p_website_origin text,p_test_event_code text,p_enabled boolean,p_token text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE secret_id uuid; previous_secret_id uuid;
BEGIN
 IF NOT public.can_manage_unit_meta_purchase(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Meta CAPI not allowed'; END IF;
 -- Serialize settings writers without blocking the delivery FK's key-share lock.
 PERFORM 1 FROM public.units WHERE id=p_unit FOR NO KEY UPDATE;
 SELECT vault_secret INTO previous_secret_id FROM analytics.meta_purchase_connectors WHERE unit=p_unit FOR NO KEY UPDATE;
 secret_id:=previous_secret_id;
 IF p_dataset IS NULL OR p_dataset !~ '^[0-9]{5,30}$' OR p_website_origin IS NULL
  OR NOT coalesce(p_website_origin=ANY(public.unit_meta_purchase_origins_internal(p_unit)),false)
  OR p_website_origin !~ '^https://[a-z0-9.-]+$'
  OR (nullif(p_test_event_code,'') IS NOT NULL AND p_test_event_code !~ '^[A-Za-z0-9_-]{1,60}$') OR p_enabled IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid Meta CAPI settings'; END IF;
 IF p_token IS NOT NULL THEN
  IF length(p_token) NOT BETWEEN 16 AND 4096 OR p_token ~ '[[:cntrl:]]' THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid Meta CAPI token';
  END IF;
  -- Vault and connector changes commit together. Do not propagate Vault
  -- errors, which can include sensitive arguments.
  BEGIN
   IF secret_id IS NULL THEN
    secret_id:=vault.create_secret(p_token);
   ELSE
    PERFORM vault.update_secret(secret_id,p_token);
   END IF;
  EXCEPTION WHEN OTHERS THEN
   RAISE EXCEPTION USING MESSAGE='Could not save Meta CAPI token';
  END;
 END IF;
 IF p_enabled AND secret_id IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='An access token is required to enable Meta CAPI';
 END IF;
 -- Only first provisioning changes the unique secret reference. Existing
 -- token replacement updates Vault in place without upgrading the row lock.
 IF p_token IS NOT NULL AND previous_secret_id IS NULL THEN
  UPDATE analytics.meta_purchase_connectors SET vault_secret=secret_id WHERE unit=p_unit AND vault_secret IS NULL;
 END IF;
 INSERT INTO analytics.meta_purchase_connectors AS c
  (unit,dataset,website_origin,test_event_code,enabled,vault_secret,token_changed_at,token_hint)
 VALUES(p_unit,p_dataset,p_website_origin,nullif(p_test_event_code,''),p_enabled,secret_id,
  CASE WHEN p_token IS NOT NULL THEN clock_timestamp() END,
  -- Meta tokens share their prefix and often their last characters; ten
  -- trailing characters let organizers tell saved tokens apart.
  CASE WHEN p_token IS NOT NULL THEN right(p_token,10) END)
 ON CONFLICT(unit) DO UPDATE SET dataset=EXCLUDED.dataset,website_origin=EXCLUDED.website_origin,
  test_event_code=EXCLUDED.test_event_code,enabled=EXCLUDED.enabled,
  paused_at=CASE WHEN p_token IS NULL THEN c.paused_at END,
  token_changed_at=coalesce(EXCLUDED.token_changed_at,c.token_changed_at),
  token_hint=CASE WHEN p_token IS NOT NULL THEN EXCLUDED.token_hint ELSE c.token_hint END,
  revision=CASE WHEN (c.dataset,c.website_origin,c.test_event_code)
   IS DISTINCT FROM (EXCLUDED.dataset,EXCLUDED.website_origin,EXCLUDED.test_event_code) THEN gen_random_uuid() ELSE c.revision END;
 RETURN public.get_unit_meta_purchase(p_unit);
END $$;

CREATE OR REPLACE FUNCTION public.set_form_meta_purchase(p_unit bigint,p_form bigint,p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_manage_unit_meta_purchase(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Meta CAPI not allowed'; END IF;
 -- Serialize settings writers without blocking the delivery FK's key-share lock.
 PERFORM 1 FROM public.units WHERE id=p_unit FOR NO KEY UPDATE;
 PERFORM 1 FROM analytics.meta_purchase_connectors WHERE unit=p_unit FOR NO KEY UPDATE;
 IF NOT EXISTS(SELECT FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form AND o.unit=p_unit)
  OR p_enabled IS NULL THEN RAISE insufficient_privilege USING MESSAGE='Meta CAPI form denied'; END IF;
 IF p_enabled THEN INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES(p_form,p_unit) ON CONFLICT(form) DO NOTHING;
 ELSE DELETE FROM analytics.meta_purchase_forms WHERE form=p_form AND unit=p_unit; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.delete_unit_meta_purchase(p_unit bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE secret_id uuid;
BEGIN
 IF NOT public.can_manage_unit_meta_purchase(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Meta CAPI access denied'; END IF;
 -- Serialize settings writers without blocking the delivery FK's key-share lock.
 PERFORM 1 FROM public.units WHERE id=p_unit FOR NO KEY UPDATE;
 -- All delivery boundaries take the connector before any delivery row locks.
 SELECT vault_secret INTO secret_id FROM analytics.meta_purchase_connectors WHERE unit=p_unit FOR UPDATE;
 UPDATE analytics.meta_purchase_deliveries SET status=CASE WHEN status='pending' THEN 'revoked' ELSE status END,
  revoked_at=coalesce(revoked_at,clock_timestamp()),done_at=coalesce(done_at,clock_timestamp()),
  -- Like consent withdrawal, disconnect erases data but retains the live sender's receipt fence.
  lease=CASE WHEN prepared AND lease_until>clock_timestamp() THEN lease END,
  lease_until=CASE WHEN prepared AND lease_until>clock_timestamp() THEN lease_until END,
  consent_snapshot=NULL,consent_scope=NULL,consent_decided_at=NULL,email_hash=NULL,phone_hash=NULL,fbp=NULL,fbc=NULL,
  client_ip=NULL,client_agent=NULL,source_url=NULL WHERE unit=p_unit;
 DELETE FROM analytics.meta_purchase_connectors WHERE unit=p_unit;
 DELETE FROM vault.secrets WHERE id=secret_id;
END $$;

REVOKE ALL ON FUNCTION public.get_unit_meta_purchase(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_meta_purchase(bigint) TO authenticated;

REVOKE ALL ON FUNCTION public.save_unit_meta_purchase(bigint,text,text,text,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_unit_meta_purchase(bigint,text,text,text,boolean,text) TO authenticated;

REVOKE ALL ON FUNCTION public.set_form_meta_purchase(bigint,bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_form_meta_purchase(bigint,bigint,boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.delete_unit_meta_purchase(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_unit_meta_purchase(bigint) TO authenticated;
