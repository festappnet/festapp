-- Organization-approved Meta CAPI settings. No live activation.
ALTER TABLE analytics.meta_purchase_connectors ADD COLUMN IF NOT EXISTS token_changed_at timestamptz;
ALTER TABLE analytics.meta_purchase_deliveries ADD COLUMN IF NOT EXISTS prepared_at timestamptz;

-- SOURCE: user_permissions/unit_meta_purchase.sql
CREATE OR REPLACE FUNCTION public.can_manage_unit_meta_purchase(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND NOT public.is_demo_unit(p_unit) AND coalesce((SELECT
 public.can_manage_organization_settings(u.organization) FROM public.units u WHERE u.id=p_unit),false);
$$;
REVOKE ALL ON FUNCTION public.can_manage_unit_meta_purchase(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_unit_meta_purchase(bigint) TO authenticated;

-- SOURCE: eshop_forms/meta_purchase_settings.sql
-- Platform policy is intentionally independent of organizer configuration.
ALTER TABLE analytics.organization_policy ADD COLUMN IF NOT EXISTS meta_capi_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE analytics.meta_purchase_connectors ALTER COLUMN vault_secret DROP NOT NULL;
ALTER TABLE analytics.meta_purchase_connectors ADD CONSTRAINT meta_purchase_enabled_requires_token
 CHECK (NOT enabled OR vault_secret IS NOT NULL);
CREATE INDEX IF NOT EXISTS meta_purchase_unit_history ON analytics.meta_purchase_deliveries(unit,consent_at DESC);
-- Keep terminal delivery audit rows after disconnecting a connector.
ALTER TABLE analytics.meta_purchase_deliveries DROP CONSTRAINT meta_purchase_deliveries_unit_fkey;
ALTER TABLE analytics.meta_purchase_deliveries ADD CONSTRAINT meta_purchase_deliveries_unit_fkey
 FOREIGN KEY(unit) REFERENCES public.units(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.meta_purchase_platform_allowed_internal(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.meta_capi_enabled FROM public.units u
 JOIN analytics.organization_policy p ON p.organization=u.organization WHERE u.id=p_unit),false);
$$;
REVOKE ALL ON FUNCTION public.meta_purchase_platform_allowed_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

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
 IF NOT public.meta_purchase_platform_allowed_internal(p_unit) THEN
  RETURN jsonb_build_object('allowed',false,'connected',EXISTS(SELECT FROM analytics.meta_purchase_connectors WHERE unit=p_unit));
 END IF;
 SELECT jsonb_build_object('dataset',c.dataset,'website_origin',c.website_origin,'test_event_code',c.test_event_code,
  'enabled',c.enabled,'paused_at',c.paused_at,'token_saved',c.vault_secret IS NOT NULL,'revision',c.revision,
  'website_ready',coalesce(c.website_origin=ANY(public.unit_meta_purchase_origins_internal(p_unit)) AND (
   c.website_origin=(SELECT rtrim(org.data->>'DEFAULT_URL','/') FROM public.units u
    JOIN public.organizations org ON org.id=u.organization WHERE u.id=p_unit)
   OR EXISTS(SELECT FROM analytics.website_consent_bindings b WHERE b.unit=p_unit
    AND b.website_origin=c.website_origin AND b.provider_config->>'provider' IN ('cookiebot','cookieconsent','wix')
    AND public.website_consent_binding_effective_internal(b))
  ),false))
 INTO result FROM analytics.meta_purchase_connectors c WHERE c.unit=p_unit;
 RETURN coalesce(result,'{}'::jsonb)||jsonb_build_object('allowed',true,
  'websites',to_jsonb(public.unit_meta_purchase_origins_internal(p_unit)),
  'queue',(SELECT jsonb_build_object('pending',count(*) FILTER(WHERE status='pending'),
    'sent',count(*) FILTER(WHERE status='sent'),'failed',count(*) FILTER(WHERE status='failed'),
    'revoked',count(*) FILTER(WHERE status='revoked')) FROM analytics.meta_purchase_deliveries
    WHERE unit=p_unit AND consent_at>=statement_timestamp()-interval '30 days'),
  'last_error',coalesce((SELECT jsonb_build_object('code',error_code,'status',status,'at',coalesce(done_at,next_attempt_at-interval '2 minutes'*power(2,greatest(attempts-1,0))))
    FROM analytics.meta_purchase_deliveries WHERE unit=p_unit AND error_code IS NOT NULL
    ORDER BY coalesce(done_at,next_attempt_at) DESC LIMIT 1),
    (SELECT jsonb_build_object('code','credentials','status','pending','at',paused_at) FROM analytics.meta_purchase_connectors WHERE unit=p_unit AND paused_at IS NOT NULL)),
  'forms',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'enabled',m.form IS NOT NULL,
     'measurement_ready',public.form_conversion_policy_allows_internal(public.form_measurement_status_internal(f.id))) ORDER BY f.id),'[]'::jsonb)
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    LEFT JOIN analytics.meta_purchase_forms m ON m.form=f.id AND m.unit=p_unit WHERE o.unit=p_unit));
END $$;

CREATE OR REPLACE FUNCTION public.save_unit_meta_purchase(p_unit bigint,p_dataset text,p_website_origin text,p_test_event_code text,p_enabled boolean,p_token text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE secret_id uuid; previous_secret_id uuid;
BEGIN
 IF NOT public.can_manage_unit_meta_purchase(p_unit) OR NOT public.meta_purchase_platform_allowed_internal(p_unit) THEN
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
  (unit,dataset,website_origin,test_event_code,enabled,vault_secret,token_changed_at)
 VALUES(p_unit,p_dataset,p_website_origin,nullif(p_test_event_code,''),p_enabled,secret_id,
  CASE WHEN p_token IS NOT NULL THEN clock_timestamp() END)
 ON CONFLICT(unit) DO UPDATE SET dataset=EXCLUDED.dataset,website_origin=EXCLUDED.website_origin,
  test_event_code=EXCLUDED.test_event_code,enabled=EXCLUDED.enabled,
  paused_at=CASE WHEN p_token IS NULL THEN c.paused_at END,
  token_changed_at=coalesce(EXCLUDED.token_changed_at,c.token_changed_at),
  revision=CASE WHEN (c.dataset,c.website_origin,c.test_event_code)
   IS DISTINCT FROM (EXCLUDED.dataset,EXCLUDED.website_origin,EXCLUDED.test_event_code) THEN gen_random_uuid() ELSE c.revision END;
 RETURN public.get_unit_meta_purchase(p_unit);
END $$;

CREATE OR REPLACE FUNCTION public.set_form_meta_purchase(p_unit bigint,p_form bigint,p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_manage_unit_meta_purchase(p_unit) OR NOT public.meta_purchase_platform_allowed_internal(p_unit) THEN
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
 -- Withdrawing platform approval must never prevent authorized cleanup.
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

-- SOURCE: eshop_forms/form_datalayer.sql
CREATE OR REPLACE FUNCTION public.form_conversion_policy_allows_internal(p_status jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT coalesce(p_status @> '{"requested_enabled":true,"organization_allowed":true,"organization_enabled":true,"unit_enabled":true}'::jsonb
  AND NOT (p_status->'blocked_reasons' @> '["no_privacy_policy"]'::jsonb),false);
$$;
REVOKE ALL ON FUNCTION public.form_conversion_policy_allows_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Only a pilot mapped to the form's owning unit can select a destination.
CREATE OR REPLACE FUNCTION public.form_meta_purchase_unit_internal(p_form bigint)
RETURNS bigint LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT c.unit FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN analytics.meta_purchase_forms m ON m.form=f.id AND m.unit=o.unit
 JOIN analytics.meta_purchase_connectors c ON c.unit=m.unit
 WHERE f.id=p_form AND c.enabled AND c.paused_at IS NULL
  AND public.meta_purchase_platform_allowed_internal(c.unit) AND NOT public.is_demo_occasion(o.id);
$$;
REVOKE ALL ON FUNCTION public.form_meta_purchase_unit_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- A configured CAPI form keeps paid timing even while delivery is paused.
CREATE OR REPLACE FUNCTION public.form_purchase_timing_internal(p_form bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN EXISTS (
   SELECT FROM public.occasions o JOIN analytics.meta_purchase_forms m ON m.form=f.id AND m.unit=o.unit
   JOIN analytics.meta_purchase_connectors c ON c.unit=m.unit
   WHERE o.id=f.occasion AND c.enabled AND NOT public.is_demo_occasion(o.id))
   OR public.normalize_form_metadata_internal(f.data)#>>'{analytics,purchase_timing}'='paid'
 THEN 'paid' ELSE 'order' END FROM public.forms f WHERE f.id=p_form;
$$;
REVOKE ALL ON FUNCTION public.form_purchase_timing_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- The creation cohort is immutable. Legacy purchase facts are order mode;
-- settings edits and later CAPI activation cannot convert them into paid events.
CREATE OR REPLACE FUNCTION public.form_order_purchase_timing_internal(p_order bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(payload->>'purchase_timing','order') FROM analytics.conversion_facts
 WHERE "order"=p_order AND kind='purchase';
$$;
REVOKE ALL ON FUNCTION public.form_order_purchase_timing_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- CAPI activation after creation cannot adopt a pre-existing browser cohort.
CREATE OR REPLACE FUNCTION public.form_order_purchase_capi_required_internal(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT payload->'capi_required'='true'::jsonb
 FROM analytics.conversion_facts WHERE "order"=p_order AND kind='purchase'),false);
$$;
REVOKE ALL ON FUNCTION public.form_order_purchase_capi_required_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Only called after receipt/capability authorization. No fact is created on read.
CREATE OR REPLACE FUNCTION public.form_purchase_datalayer_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN public.form_order_purchase_timing_internal(o.id)='order'
 THEN snapshot.payload||jsonb_build_object('event_id',snapshot.event_id)
 ELSE jsonb_set(snapshot.payload,'{ecommerce,transaction_id}',to_jsonb(paid.event_id::text))
   ||jsonb_build_object('event_id',paid.event_id)
 END ||jsonb_build_object('meta_purchase_allowed',NOT public.form_order_purchase_capi_required_internal(o.id)
   AND meta.expires_at>statement_timestamp(),
   'meta_purchase_expires_at',floor(extract(epoch FROM meta.expires_at)*1000)::bigint) FROM eshop.orders o
 JOIN analytics.conversion_facts snapshot ON snapshot."order"=o.id AND snapshot.kind='purchase'
 LEFT JOIN analytics.conversion_facts paid ON paid."order"=o.id AND paid.kind='order_fully_paid'
 CROSS JOIN LATERAL (SELECT CASE WHEN public.form_order_purchase_timing_internal(o.id)='order'
   THEN snapshot.created_at ELSE paid.created_at END + interval '47 hours' expires_at) meta
 WHERE o.id=p_order AND jsonb_typeof(snapshot.payload->'ecommerce')='object'
 AND public.form_conversion_policy_allows_internal(public.form_measurement_status_internal(o.form))
 AND (public.form_order_purchase_timing_internal(o.id)='order' OR
   (paid.event_id IS NOT NULL
    AND public.form_paid_conversion_eligible_internal(o.id)
    AND snapshot.payload#>'{ecommerce,value}'=paid.payload->'value'
    AND snapshot.payload#>'{ecommerce,currency}'=paid.payload->'currency'));
$$;
REVOKE ALL ON FUNCTION public.form_purchase_datalayer_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Meta-only companion: general analytics must not wait for advertising consent
-- or CAPI delivery. Pixel follows confirmed CAPI within its deduplication window.
CREATE OR REPLACE FUNCTION public.form_meta_purchase_datalayer_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT public.form_purchase_datalayer_internal(p_order)||jsonb_build_object('event','meta_purchase','meta_purchase_allowed',true)
 WHERE public.form_order_purchase_timing_internal(p_order)='paid'
 AND public.form_order_purchase_capi_required_internal(p_order)
 AND EXISTS(SELECT FROM analytics.meta_purchase_deliveries d
   JOIN analytics.conversion_facts c ON c."order"=d.order_id AND c.kind='order_fully_paid'
   WHERE d.order_id=p_order AND d.status='sent' AND d.revoked_at IS NULL AND c.created_at>statement_timestamp()-interval '47 hours');
$$;
REVOKE ALL ON FUNCTION public.form_meta_purchase_datalayer_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.form_conversion_datalayer_internal(p_order bigint,p_kind text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_kind='purchase' THEN public.form_purchase_datalayer_internal(p_order)
 ELSE (SELECT c.payload FROM analytics.conversion_facts c JOIN eshop.orders o ON o.id=c."order"
 WHERE c."order"=p_order AND c.kind=p_kind AND p_kind IN ('waitlist','free_registration')
 AND public.form_conversion_policy_allows_internal(public.form_measurement_status_internal(o.form))) END;
$$;
REVOKE ALL ON FUNCTION public.form_conversion_datalayer_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

-- Called exactly at canonical finalization/registration, never on replay.
-- Products come from the finalizer's charged-price snapshot, not today's catalog.
CREATE OR REPLACE FUNCTION public.record_form_conversion_internal(p_order bigint,p_capi_supported boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE o eshop.orders; s jsonb; items jsonb; total numeric; payload jsonb; identity uuid:=gen_random_uuid(); brand text;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 s:=public.form_measurement_status_internal(o.form);
 IF NOT public.form_conversion_policy_allows_internal(s) THEN RETURN; END IF;
 IF o.state='waitlisted' OR o.price=0 THEN
  payload:=jsonb_build_object('event','generate_lead','event_id',identity,'currency',coalesce(nullif(trim(o.currency_code),''),'CZK'),
   'value',0,'lead_source',CASE WHEN o.state='waitlisted' THEN 'waitlist' ELSE 'free_registration' END);
 ELSIF o.price>0 AND trim(o.currency_code) ~ '^[A-Z]{3}$' THEN
  -- Freeze the checkout cohort even if there is no safe browser item projection.
  payload:=jsonb_build_object('purchase_timing',public.form_purchase_timing_internal(o.form),
   'capi_required',p_capi_supported AND public.form_meta_purchase_unit_internal(o.form) IS NOT NULL);
  BEGIN
  SELECT title INTO brand FROM public.occasions WHERE id=o.occasion;
  -- Labels stay out of the grouping: they cannot split a line or change the total.
  SELECT jsonb_agg(jsonb_build_object('item_id','product_'||x.id,'item_name',x.title,'price',x.price,'quantity',x.quantity)||
    jsonb_strip_nulls(jsonb_build_object('item_category',nullif(left(btrim(x.category),100),''),'item_brand',nullif(left(btrim(brand),100),''))) ORDER BY x.id,x.price),
   sum(x.price*x.quantity) INTO items,total
  FROM (SELECT p->>'id' id,p->>'title' title,(p->>'price')::numeric price,count(*) quantity,min(p->>'type_title') category
   FROM jsonb_array_elements(o.data->'tickets') t CROSS JOIN LATERAL jsonb_array_elements(t->'products') p
   GROUP BY p->>'id',p->>'title',(p->>'price')::numeric) x;
  IF jsonb_array_length(items) BETWEEN 1 AND 200 AND total=o.price THEN
   payload:=payload||jsonb_build_object('event','purchase','event_id',identity,'ecommerce',jsonb_build_object('transaction_id',identity,
    'currency',trim(o.currency_code),'value',o.price,'items',items,'payment_type',
    CASE WHEN public.payment_method_is_online_internal((SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info)) THEN 'card' ELSE 'bank_transfer' END));
  END IF;
  EXCEPTION WHEN OTHERS THEN NULL; -- Preserve the cohort without exporting invalid browser lines.
  END;
 END IF;
 IF payload IS NOT NULL THEN
  INSERT INTO analytics.conversion_facts("order",kind,event_id,payload) VALUES(p_order,coalesce(payload->>'lead_source','purchase'),identity,payload)
   ON CONFLICT("order",kind) DO NOTHING;
 END IF;
-- Measurement failure cannot change checkout. Invalid/incomplete snapshots are
-- intentionally not exported; no second price calculation repairs them.
EXCEPTION WHEN OTHERS THEN RETURN;
END $$;
REVOKE ALL ON FUNCTION public.record_form_conversion_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.record_form_conversion_internal(p_order bigint)
RETURNS void LANGUAGE sql VOLATILE SET search_path=public,extensions AS $$
 SELECT public.record_form_conversion_internal(p_order,true);
$$;
REVOKE ALL ON FUNCTION public.record_form_conversion_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

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
 IF NOT FOUND OR NOT public.meta_purchase_platform_allowed_internal(p_unit) OR p_snapshot->>'websiteOrigin' IS DISTINCT FROM c.website_origin THEN RETURN false; END IF;
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
 SELECT o.form,o.price,o.data,oc.unit,f.link,c.website_origin,c.revision,c.enabled,c.paused_at,
  public.meta_purchase_platform_allowed_internal(c.unit) platform_allowed
 INTO details
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN public.forms f ON f.id=o.form
 JOIN analytics.meta_purchase_connectors c ON c.unit=oc.unit
 WHERE o.id=p_order
 -- Capture coexists with routine non-key writes and worker activity. Only
 -- disconnect/key changes may skip optional matching. Destination revisions
 -- captured during an edit are revalidated by prepare before any send.
 FOR KEY SHARE OF c SKIP LOCKED;
 IF NOT FOUND THEN RETURN; END IF;
 IF details.enabled IS DISTINCT FROM true OR details.paused_at IS NOT NULL
    OR details.platform_allowed IS DISTINCT FROM true OR coalesce(details.price,0)<=0
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
EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
 -- Matching is optional. Roll back this capture only; never fail the checkout
 -- for lock contention (including a configured lock_timeout).
 RETURN;
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
    AND public.meta_purchase_platform_allowed_internal(c.unit)
    AND public.form_order_purchase_timing_internal(d.order_id)='paid'
    AND public.form_order_purchase_capi_required_internal(d.order_id) IS TRUE
    AND d.next_attempt_at<=clock_timestamp() AND (d.lease_until IS NULL OR d.lease_until<=clock_timestamp())
  ORDER BY d.next_attempt_at,d.order_id LIMIT least(greatest(coalesce(p_limit,1),1),20)
  FOR UPDATE OF d SKIP LOCKED
 )
 UPDATE analytics.meta_purchase_deliveries d SET lease=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes',prepared=false,prepared_at=NULL
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
 token text; connector_unit bigint;
BEGIN
 PERFORM public.require_service_role();
 -- Follow the same connector -> delivery order as disconnect and finish.
 SELECT unit INTO connector_unit FROM analytics.meta_purchase_deliveries WHERE order_id=p_order_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO connector FROM analytics.meta_purchase_connectors WHERE unit=connector_unit FOR NO KEY UPDATE;
 -- Serialize short prepares before a possible credential pause; never upgrade
 -- two concurrent shared connector locks to an update lock.
 IF NOT FOUND OR connector.enabled IS DISTINCT FROM true OR connector.paused_at IS NOT NULL
  OR NOT public.meta_purchase_platform_allowed_internal(connector.unit) THEN RETURN NULL; END IF;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND status='pending' AND lease=p_lease AND lease_until>clock_timestamp() AND NOT prepared
 FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF delivery.unit IS DISTINCT FROM connector.unit THEN RETURN NULL; END IF;
 SELECT * INTO fact FROM analytics.conversion_facts WHERE "order"=p_order_id AND kind='order_fully_paid';
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 IF public.form_order_purchase_timing_internal(p_order_id) IS DISTINCT FROM 'paid'
    OR public.form_order_purchase_capi_required_internal(p_order_id) IS DISTINCT FROM true
    OR public.form_meta_purchase_unit_internal(o.form) IS DISTINCT FROM connector.unit
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
 UPDATE analytics.meta_purchase_deliveries SET client_ip=delivery.client_ip,attempts=attempts+1,prepared=true,prepared_at=clock_timestamp() WHERE order_id=p_order_id;
 RETURN jsonb_build_object('dataset',connector.dataset,'accessToken',token,'testEventCode',connector.test_event_code,
  'eventId',fact.event_id,'eventTime',floor(extract(epoch FROM fact.created_at)),
  'value',fact.payload->'value','currency',fact.payload->>'currency',
  'phoneHash',CASE WHEN delivery.phone_hash ~ '^[0-9a-f]{64}$' THEN delivery.phone_hash END,'fbp',public.meta_purchase_browser_id_internal(delivery.fbp),
  'fbc',public.meta_purchase_browser_id_internal(delivery.fbc),'clientIp',host(delivery.client_ip),
  'emailHash',delivery.email_hash,'clientAgent',delivery.client_agent,'sourceUrl',delivery.source_url);
END $$;

CREATE OR REPLACE FUNCTION public.finish_meta_purchase_delivery(p_order_id bigint,p_lease uuid,p_result text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE delivery analytics.meta_purchase_deliveries; final_status text; connector_unit bigint;
BEGIN
 PERFORM public.require_service_role();
 IF p_result IS NULL OR p_result NOT IN ('sent','retry','credentials','rejected') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid delivery result'; END IF;
 -- A disconnected connector may be absent; its terminal receipt still exists.
 -- Lock any surviving connector before the delivery, like prepare and delete.
 SELECT unit INTO connector_unit FROM analytics.meta_purchase_deliveries WHERE order_id=p_order_id;
 IF NOT FOUND THEN RETURN false; END IF;
 PERFORM 1 FROM analytics.meta_purchase_connectors WHERE unit=connector_unit FOR NO KEY UPDATE;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND lease=p_lease AND status IN ('pending','revoked') AND prepared FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_result='credentials' THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=delivery.unit AND revision=delivery.connector_revision
   AND (token_changed_at IS NULL OR token_changed_at<delivery.prepared_at);
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
   AND public.meta_purchase_platform_allowed_internal(c.unit)
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
