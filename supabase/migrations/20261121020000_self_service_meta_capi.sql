-- Fence any delivery captured under a since-withdrawn grant, even if the
-- connector was already off when the old platform gate was removed.
UPDATE analytics.meta_purchase_connectors c SET enabled=false,revision=gen_random_uuid()
WHERE NOT EXISTS(
 SELECT 1 FROM public.units u JOIN analytics.organization_policy p ON p.organization=u.organization
 WHERE u.id=c.unit AND p.meta_capi_enabled);

DROP TRIGGER fulfil_meta_capi_approval ON analytics.organization_policy;
DROP FUNCTION public.fulfil_meta_capi_approval_internal();
DROP FUNCTION public.unit_meta_capi_approval_internal(bigint);
DROP FUNCTION public.meta_purchase_platform_allowed_internal(bigint);
DROP INDEX public.unit_meta_capi_notification_generation;
DROP TABLE analytics.organization_meta_capi_request;
ALTER TABLE analytics.organization_policy DROP COLUMN meta_capi_enabled;
DROP FUNCTION public.form_conversion_policy_allows_internal(jsonb);
DROP FUNCTION public.form_meta_purchase_unit_internal(bigint);
DROP FUNCTION public.form_purchase_timing_internal(bigint);

-- SOURCE: user_permissions/unit_meta_purchase.sql
CREATE OR REPLACE FUNCTION public.can_manage_unit_meta_purchase(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND NOT public.is_demo_unit(p_unit) AND coalesce((SELECT
 (public.can_manage_unit_configuration(u.id) OR public.can_manage_organization_settings(u.organization)) FROM public.units u WHERE u.id=p_unit),false);
$$;
REVOKE ALL ON FUNCTION public.can_manage_unit_meta_purchase(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_unit_meta_purchase(bigint) TO authenticated;

-- SOURCE: eshop_forms/form_measurement_decision.sql
-- Evaluate each form's current configuration once per caller. The order
-- cohort, visitor consent and payment evidence are checked by their own owners.
CREATE OR REPLACE FUNCTION public.form_measurement_decision_internal(p_form bigint)
RETURNS TABLE(requested_enabled boolean,organization_allowed boolean,organization_enabled boolean,
 unit_enabled boolean,privacy_policy_valid boolean,runtime_supported boolean,destination_configured boolean,
 policy_revision bigint,conversion_eligible boolean,browser_eligible boolean,capi_unit bigint,purchase_timing text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH scope AS MATERIALIZED (
  SELECT public.normalize_form_metadata_internal(f.data)->'analytics' settings,
   coalesce(p.enabled,false) organization_allowed,coalesce(p.revision,0) policy_revision,
   coalesce(org.data->'FORM_MEASUREMENT_ENABLED'='true'::jsonb,false) organization_enabled,
   coalesce(u.data->'measurement_enabled'='true'::jsonb,false) unit_enabled,
   coalesce(length(u.data->>'measurement_privacy_url') BETWEEN 1 AND 2048
    AND (u.data->>'measurement_privacy_url') ~ (public.configuration_settings_contract_internal_v1()#>>'{unit,measurement_privacy_url,pattern}'),false)
    privacy_policy_valid,
   public.form_measurement_runtime_supported_internal(r.runtime_profile,r.runtime_origin,r.parent_origins) runtime_supported,
   coalesce(nullif(btrim(u.data->>'measurement_gtm_container'),''),nullif(u.data->>'measurement_scripts','')) IS NOT NULL destination_configured,
   public.is_demo_occasion(f.occasion) demo,
   c.unit connector_unit,c.paused_at
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
  JOIN public.organizations org ON org.id=o.organization
  LEFT JOIN analytics.organization_policy p ON p.organization=o.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
  LEFT JOIN analytics.meta_purchase_forms m ON m.form=f.id AND m.unit=u.id
  LEFT JOIN analytics.meta_purchase_connectors c ON c.unit=m.unit AND c.enabled
  WHERE f.id=p_form
 ), readiness AS (
  SELECT scope.*,coalesce(settings->'enabled'='true'::jsonb,false) requested_enabled,
   coalesce(settings->'enabled'='true'::jsonb,false) AND organization_allowed AND organization_enabled
    AND unit_enabled AND privacy_policy_valid conversion_eligible
  FROM scope
 )
 SELECT d.requested_enabled,d.organization_allowed,d.organization_enabled,d.unit_enabled,d.privacy_policy_valid,
  d.runtime_supported AND NOT d.demo,d.destination_configured,d.policy_revision,d.conversion_eligible,
  d.conversion_eligible AND d.runtime_supported AND NOT d.demo AND d.destination_configured,
  CASE WHEN NOT d.demo AND d.paused_at IS NULL THEN d.connector_unit END,
  CASE WHEN (d.connector_unit IS NOT NULL AND NOT d.demo) OR d.settings->>'purchase_timing'='paid'
   THEN 'paid' ELSE 'order' END
 FROM readiness d;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_decision_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/form_measurement_policy.sql
CREATE OR REPLACE FUNCTION public.form_measurement_status_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('requested_enabled',d.requested_enabled,'organization_allowed',d.organization_allowed,
  'organization_enabled',d.organization_enabled,'unit_enabled',d.unit_enabled,
  'runtime_supported',d.runtime_supported,'eligible',d.browser_eligible,
  'meta_purchase_enabled',d.capi_unit IS NOT NULL,'purchase_timing',d.purchase_timing,
  'policy_revision',d.policy_revision,'consent_required',true,'enhanced_conversions_unavailable',false,
  'blocked_reasons',to_jsonb(array_remove(ARRAY[
   CASE WHEN NOT d.requested_enabled THEN 'disabled' END,
   CASE WHEN NOT d.organization_allowed THEN 'organization_not_enabled' END,
   CASE WHEN NOT d.organization_enabled THEN 'organization_disabled' END,
   CASE WHEN NOT d.unit_enabled THEN 'unit_disabled' END,
   CASE WHEN NOT d.runtime_supported THEN 'runtime_unavailable' END,
   CASE WHEN NOT d.destination_configured THEN 'no_destination' END,
   CASE WHEN NOT d.privacy_policy_valid THEN 'no_privacy_policy' END],NULL)))
 FROM public.form_measurement_decision_internal(p_form) d;
$$;

-- SOURCE: eshop_forms/form_paid_conversion.sql
CREATE OR REPLACE FUNCTION public.form_paid_conversion_eligible_internal(p_order bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE
 o eshop.orders;
 payment eshop.payment_info;
 totals record;
 eligible_bank_received numeric;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.form IS NULL OR (o.state IN ('paid','sent')) IS NOT TRUE OR coalesce(o.price,0)<=0
  OR coalesce(trim(o.currency_code),'') !~ '^[A-Z]{3}$'
  OR NOT EXISTS(SELECT FROM public.form_measurement_decision_internal(o.form) d WHERE d.conversion_eligible)
 THEN RETURN false; END IF;

 SELECT * INTO payment FROM eshop.payment_info WHERE id=o.payment_info;
 IF payment.amount IS DISTINCT FROM o.price OR payment.currency_code IS DISTINCT FROM o.currency_code
  OR payment.payment_method IS NULL THEN RETURN false; END IF;

 SELECT * INTO totals FROM public.payment_financial_totals_internal(payment.id);
 IF totals.invalid_identity IS DISTINCT FROM false OR coalesce(totals.available,0)<o.price THEN RETURN false; END IF;

 IF payment.payment_method='bank' THEN
  -- Cash and administrative settlements cannot complete a qualifying purchase.
  SELECT coalesce(sum(m.amount),0) INTO eligible_bank_received
  FROM public.payment_transaction_movements_internal(payment.id) m
  JOIN eshop.transactions t ON t.id=m.transaction_id
  JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
  WHERE NOT m.is_refund AND NOT m.voided AND upper(b.type)<>'CASH'
    AND t.transaction_type IS DISTINCT FROM 'manual' AND t.ingest_source IS DISTINCT FROM 'manual';
  IF eligible_bank_received-totals.refunded<o.price THEN RETURN false; END IF;
 ELSIF NOT public.payment_method_is_online_internal(payment.payment_method) THEN
  RETURN false;
 END IF;

 RETURN true;
END $$;

-- SOURCE: eshop_forms/meta_purchase_settings.sql
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

-- SOURCE: eshop_forms/form_datalayer.sql
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
 AND EXISTS(SELECT FROM public.form_measurement_decision_internal(o.form) d WHERE d.conversion_eligible)
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
 AND EXISTS(SELECT FROM public.form_measurement_decision_internal(o.form) d WHERE d.conversion_eligible)) END;
$$;
REVOKE ALL ON FUNCTION public.form_conversion_datalayer_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

-- Called exactly at canonical finalization/registration, never on replay.
-- Products come from the finalizer's charged-price snapshot, not today's catalog.
CREATE OR REPLACE FUNCTION public.record_form_conversion_internal(p_order bigint,p_capi_supported boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE o eshop.orders; decision record; items jsonb; total numeric; payload jsonb; identity uuid:=gen_random_uuid(); brand text;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO decision FROM public.form_measurement_decision_internal(o.form);
 IF decision.conversion_eligible IS NOT TRUE THEN RETURN; END IF;
 IF o.state='waitlisted' OR o.price=0 THEN
  payload:=jsonb_build_object('event','generate_lead','event_id',identity,'currency',coalesce(nullif(trim(o.currency_code),''),'CZK'),
   'value',0,'lead_source',CASE WHEN o.state='waitlisted' THEN 'waitlist' ELSE 'free_registration' END);
 ELSIF o.price>0 AND trim(o.currency_code) ~ '^[A-Z]{3}$' THEN
  -- Freeze the checkout cohort even if there is no safe browser item projection.
  payload:=jsonb_build_object('purchase_timing',decision.purchase_timing,
   'capi_required',p_capi_supported AND decision.capi_unit IS NOT NULL);
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
 FROM public.form_measurement_decision_internal(p_form) d
 JOIN analytics.meta_purchase_connectors c ON c.unit=d.capi_unit
 WHERE d.conversion_eligible;
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
DECLARE c analytics.meta_purchase_connectors; b analytics.website_consent_bindings; service_origin text;
BEGIN
 IF jsonb_typeof(p_snapshot) IS DISTINCT FROM 'object'
  OR coalesce(p_snapshot->>'source','') NOT IN ('klaro','cookiebot','cookieconsent','wix','complianz')
  OR p_snapshot->'ad_storage' IS DISTINCT FROM 'true'::jsonb
  OR p_snapshot->'ad_user_data' IS DISTINCT FROM 'true'::jsonb
  OR p_snapshot->'ad_personalization' IS DISTINCT FROM 'true'::jsonb
  OR p_snapshot->>'consentRevision' IS DISTINCT FROM public.unit_measurement_consent_scope_internal(p_unit)->>'consentRevision' THEN RETURN false; END IF;
 SELECT * INTO c FROM analytics.meta_purchase_connectors WHERE unit=p_unit AND enabled AND paused_at IS NULL;
 IF NOT FOUND OR p_snapshot->>'websiteOrigin' IS DISTINCT FROM c.website_origin THEN RETURN false; END IF;
 IF p_snapshot->>'source'='klaro' THEN
  SELECT rtrim(org.data->>'DEFAULT_URL','/') INTO service_origin FROM public.units u JOIN public.organizations org ON org.id=u.organization WHERE u.id=p_unit;
  RETURN coalesce(NOT p_snapshot ? 'binding' AND c.website_origin=service_origin,false);
 END IF;
 SELECT * INTO b FROM analytics.website_consent_bindings WHERE unit=p_unit
  AND id::text=p_snapshot#>>'{binding,id}' AND version::text=p_snapshot#>>'{binding,version}'
  AND website_origin=c.website_origin;
 RETURN coalesce(FOUND AND public.website_consent_binding_effective_internal(b)
  AND b.provider_config->>'provider'=p_snapshot->>'source'
  AND p_snapshot->>'source' IN ('cookiebot','cookieconsent','wix','complianz'),false);
END $$;
REVOKE ALL ON FUNCTION public.meta_purchase_snapshot_valid_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Retain only a digest of the non-contact consent scope and the capture time
-- for comparisons after matching data and the full snapshot have been scrubbed.
CREATE OR REPLACE FUNCTION public.meta_purchase_consent_scope_internal(p_snapshot jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(jsonb_build_array(p_snapshot->>'source',p_snapshot->>'websiteOrigin',
  p_snapshot->>'consentRevision',p_snapshot#>>'{binding,id}',p_snapshot#>>'{binding,version}')::text,'sha256'),'hex');
$$;
REVOKE ALL ON FUNCTION public.meta_purchase_consent_scope_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- A CMP date can order decisions only when it is a plausible UTC instant
-- at the time the server received the assertion.
CREATE OR REPLACE FUNCTION public.meta_purchase_decision_at_internal(p_snapshot jsonb,p_observed_at timestamptz)
RETURNS timestamptz LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE raw text:=coalesce(p_snapshot->>'decidedAt',p_snapshot->>'timestamp'); decision timestamptz;
BEGIN
 IF raw IS NULL OR raw !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,6})?Z$'
 THEN RETURN NULL; END IF;
 decision:=raw::timestamptz;
 IF decision<=p_observed_at THEN RETURN decision; END IF;
 RETURN NULL;
EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.meta_purchase_decision_at_internal(jsonb,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.capture_meta_purchase_consent_internal(p_order bigint,p_consent jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE
 details record;
 captured timestamptz:=clock_timestamp(); audit_time timestamptz;
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
 SELECT o.form,o.price,o.data,oc.unit,f.link,c.website_origin,c.revision,c.enabled,c.paused_at
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
    OR coalesce(details.price,0)<=0
    OR public.form_measurement_visitor_role_internal(details.form)='staff'
    OR coalesce(details.link,'') !~ '^[a-zA-Z0-9_-]+$'
    OR public.meta_purchase_consent_revision_internal(details.form) IS DISTINCT FROM p_consent->>'revision'
    OR public.meta_purchase_snapshot_valid_internal(details.unit,p_consent) IS DISTINCT FROM true
 THEN RETURN; END IF;
 -- Missing or implausible metadata never prevents capture.
 audit_time:=public.meta_purchase_decision_at_internal(p_consent,captured);
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
 INSERT INTO analytics.meta_purchase_deliveries(order_id,unit,connector_revision,consent_revision,consent_scope,consent_decided_at,consent_at,consent_snapshot,email_hash,client_agent,source_url,phone_hash,fbp,fbc,client_ip)
 VALUES (p_order,details.unit,details.revision,p_consent->>'revision',
   public.meta_purchase_consent_scope_internal(p_consent),audit_time,captured,
   jsonb_build_object('source',p_consent->'source','capturedAt',to_char(captured AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
     'consentRevision',p_consent->'consentRevision','websiteOrigin',details.website_origin,
     'ad_storage',true,'ad_user_data',true,'ad_personalization',true)
     || CASE WHEN audit_time IS NOT NULL THEN jsonb_build_object('decidedAt',to_char(audit_time AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')) ELSE '{}'::jsonb END
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
-- scope. Only comparable CMP decision dates can prove that a denial is older.
CREATE OR REPLACE FUNCTION public.revoke_meta_purchase_consent(p_token text,p_order_id bigint,p_denial jsonb)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE overview jsonb; decision timestamptz; scope_hash text; affected integer;
BEGIN
 overview:=public.get_customer_order_overview_internal(p_token,p_order_id);
 IF overview->>'code' IS DISTINCT FROM '200' THEN RETURN false; END IF;
 IF p_denial IS NOT NULL THEN
  IF jsonb_typeof(p_denial) IS DISTINCT FROM 'object' OR octet_length(p_denial::text)>2048
    OR coalesce(p_denial->>'source','') NOT IN ('klaro','cookiebot','cookieconsent','wix','complianz')
    OR NOT (p_denial->'ad_storage' IN ('true'::jsonb,'false'::jsonb)
      AND p_denial->'ad_user_data' IN ('true'::jsonb,'false'::jsonb)
      AND p_denial->'ad_personalization' IN ('true'::jsonb,'false'::jsonb))
    OR NOT (p_denial ?& ARRAY['ad_storage','ad_user_data','ad_personalization'])
    OR NOT (p_denial @> '{"ad_storage":false}' OR p_denial @> '{"ad_user_data":false}' OR p_denial @> '{"ad_personalization":false}')
  THEN RETURN false; END IF;
  decision:=public.meta_purchase_decision_at_internal(p_denial,clock_timestamp());
  scope_hash:=public.meta_purchase_consent_scope_internal(p_denial);
 END IF;
 UPDATE analytics.meta_purchase_deliveries SET revoked_at=clock_timestamp(),status=CASE WHEN status='pending' THEN 'revoked' ELSE status END,
  -- Prepare commits the send authorization; keep its live receipt fence after withdrawal.
  done_at=CASE WHEN status='pending' THEN clock_timestamp() ELSE done_at END,
  lease=CASE WHEN prepared AND lease_until>clock_timestamp() THEN lease END,
  lease_until=CASE WHEN prepared AND lease_until>clock_timestamp() THEN lease_until END,
  consent_snapshot=NULL,email_hash=NULL,phone_hash=NULL,fbp=NULL,fbc=NULL,client_ip=NULL,client_agent=NULL,source_url=NULL
 WHERE order_id IN(SELECT (value->>'id')::bigint FROM jsonb_array_elements(overview->'orders'))
   AND revoked_at IS NULL
   AND (p_denial IS NULL OR (consent_scope=scope_hash AND (decision IS NULL OR consent_decided_at IS NULL OR NOT isfinite(consent_decided_at)
     OR consent_decided_at>consent_at OR decision>=consent_decided_at)));
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
 token text; connector_unit bigint; invalid_reason text;
BEGIN
 PERFORM public.require_service_role();
 -- Follow the same connector -> delivery order as disconnect and finish.
 SELECT unit INTO connector_unit FROM analytics.meta_purchase_deliveries WHERE order_id=p_order_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO connector FROM analytics.meta_purchase_connectors WHERE unit=connector_unit FOR NO KEY UPDATE;
 -- Serialize short prepares before a possible credential pause; never upgrade
 -- two concurrent shared connector locks to an update lock.
 IF NOT FOUND OR connector.enabled IS DISTINCT FROM true OR connector.paused_at IS NOT NULL THEN RETURN NULL; END IF;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND status='pending' AND lease=p_lease AND lease_until>clock_timestamp() AND NOT prepared
 FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF delivery.unit IS DISTINCT FROM connector.unit THEN RETURN NULL; END IF;
 SELECT * INTO fact FROM analytics.conversion_facts WHERE "order"=p_order_id AND kind='order_fully_paid';
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 -- Closed reason vocabulary; the first matching guard owns the outcome.
 invalid_reason:=CASE
  WHEN delivery.connector_revision IS DISTINCT FROM connector.revision THEN 'connector_changed'
  WHEN public.form_order_purchase_timing_internal(p_order_id) IS DISTINCT FROM 'paid'
    OR public.form_order_purchase_capi_required_internal(p_order_id) IS DISTINCT FROM true
    OR (SELECT d.capi_unit FROM public.form_measurement_decision_internal(o.form) d) IS DISTINCT FROM connector.unit
    OR fact.payload IS DISTINCT FROM jsonb_build_object('value',o.price,'currency',trim(o.currency_code))
    OR NOT public.form_paid_conversion_eligible_internal(p_order_id) THEN 'order_ineligible'
  WHEN delivery.consent_revision IS DISTINCT FROM public.meta_purchase_consent_revision_internal(o.form)
    OR public.meta_purchase_snapshot_valid_internal(delivery.unit,delivery.consent_snapshot) IS DISTINCT FROM true
    OR delivery.consent_at>fact.created_at
    OR delivery.consent_at<clock_timestamp()-interval '30 days' THEN 'consent_invalid'
  WHEN fact.created_at<clock_timestamp()-interval '7 days' THEN 'payment_too_old'
  WHEN delivery.attempts>=6 THEN 'attempts_exhausted'
 END;
 IF invalid_reason IS NOT NULL THEN
  UPDATE analytics.meta_purchase_deliveries SET status='invalid',error_code=invalid_reason,done_at=clock_timestamp(),
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

-- SOURCE: eshop_forms/unit_meta_capi_approval.sql
-- Wire compatibility for installed clients and published API consumers.
-- Both legacy responses describe current organizer access without queueing mail.
CREATE OR REPLACE FUNCTION public.get_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.can_read_unit_administration(p_unit) OR public.can_manage_unit_meta_purchase(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='unit Meta CAPI access denied';
 END IF;
 RETURN jsonb_build_object('approved',public.can_manage_unit_meta_purchase(p_unit),
  'requested_at',NULL,'request_state','not_requested','can_request',false);
END $$;
REVOKE ALL ON FUNCTION public.get_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_meta_capi_approval(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_unit_meta_capi_approval(p_unit);
$$;
REVOKE ALL ON FUNCTION public.request_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.request_unit_meta_capi_approval(bigint) TO authenticated;

-- SOURCE: emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb; v_template_epoch bigint; template_audit jsonb; bank_enabled boolean;
BEGIN
 IF p_message.message_kind='custom' AND p_message.code='MEASUREMENT_APPROVAL_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM analytics.unit_measurement_request q JOIN public.units u ON u.id=q.unit
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE q.unit=p_message.unit AND u.organization=p_message.organization AND NOT public.is_demo_unit(u.id)
    AND q.revision=coalesce((p_message.data->>'request_revision')::integer,1)
    AND public.unit_measurement_approval_internal(u.id)->'approved'='false'::jsonb
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 -- Messages queued by older releases expire without notifying anyone.
 IF p_message.message_kind='custom' AND p_message.code='META_CAPI_APPROVAL_REQUEST' THEN
  RETURN false;
 END IF;
 IF p_message.message_kind='admin_notification_digest' THEN
  RETURN p_message.recipient IS NOT DISTINCT FROM public.get_user_delivery_email(p_message.recipient_user)
   AND coalesce(jsonb_array_length(public.notification_center_email_context_internal(p_message.notification_dispatch_id,p_message.recipient_user)->'items'),0)>0;
 END IF;

 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.access_invitations i WHERE i.message_id=p_message.message_id
   AND i.accepted_at IS NULL AND public.access_invitation_valid_internal_v1(i)
   AND i.email=p_message.recipient AND i.occasion IS NOT DISTINCT FROM p_message.occasion AND i.unit=p_message.unit AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_ACCESS_NOTICE' THEN
  RETURN public.can_manage_member_access_as_actor_internal_v1(p_message.producer_actor,
   CASE WHEN p_message.occasion IS NULL THEN 'unit' ELSE 'occasion' END,coalesce(p_message.occasion,p_message.unit))
   AND public.get_user_delivery_email(p_message.recipient_user)=p_message.recipient
   AND CASE WHEN p_message.occasion IS NULL THEN EXISTS(SELECT 1 FROM public.unit_users WHERE unit=p_message.unit AND "user"=p_message.recipient_user)
    ELSE EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_message.occasion AND "user"=p_message.recipient_user) END;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_confirmation' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_opened' THEN
  RETURN public.sale_opening_intent_valid_internal(p_message);
 END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.data->>'repair_payment_fingerprint' IS NOT NULL AND p_message.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(v_order.id) THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  v_template_epoch:=coalesce((SELECT e.revision FROM eshop.payment_template_epochs e WHERE e.occasion_id=v_order.occasion),0);
  bank_enabled:=coalesce(public.payment_method_policy_enabled_internal(v_occ.unit,'bank'),false);
  IF p_message.data ? 'paymentTemplateEpoch' THEN
   IF (p_message.data->>'paymentTemplateEpoch')::bigint IS DISTINCT FROM v_template_epoch THEN RETURN false; END IF;
  ELSIF p_message.prepared IS NOT NULL AND (NOT bank_enabled OR public.payment_method_is_online_internal(v_pi.payment_method)) THEN
   -- An encrypted legacy snapshot has no attestation for the current template.
   -- Preserve it as audit; a new authorized preparation must replace the intent.
   RETURN false;
  END IF;
  IF NOT bank_enabled OR public.payment_method_is_online_internal(v_pi.payment_method) THEN
   template_audit:=public.payment_template_audit_internal(v_order.occasion);
   IF template_audit->'compatible' IS DISTINCT FROM 'true'::jsonb THEN RETURN false; END IF;
  END IF;
 END IF;
 IF p_message.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice') THEN
  IF p_message.data#>>'{collectionAction,policyRevision}' IS NULL THEN RETURN false; END IF;
  IF public.payment_collection_action_internal(v_order.id)->'policyRevision' IS DISTINCT FROM p_message.data#>'{collectionAction,policyRevision}' THEN RETURN false; END IF;
 END IF;
 IF p_message.data#>'{collectionAction,allowed}'='true'::jsonb THEN
 IF (
  public.payment_collection_action_internal(v_order.id)->'allowed' IS DISTINCT FROM 'true'::jsonb OR
  public.payment_collection_action_internal(v_order.id)->'policyRevision' IS DISTINCT FROM p_message.data#>'{collectionAction,policyRevision}') THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND public.payment_method_is_online_internal(payment_method))
   AND public.provider_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_confirmation' THEN
  RETURN public.order_checkout_email_kind_internal(v_order.id)='order_confirmation'
   AND v_order.state IN ('ordered','paid') AND v_order.email_payment_version=p_message.source_version
   AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  IF public.payment_collection_action_internal(v_order.id)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN RETURN false; END IF;
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method<>'bank' OR v_pi.data#>>'{payment_policy,mode}'='none' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND coalesce(v_pi.paid,0)-coalesce(v_pi.returned,0)<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

-- SOURCE: units/delete_unit.sql
CREATE OR REPLACE FUNCTION public.delete_unit(p_unit_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_manager_count integer;
BEGIN
    PERFORM public.check_is_manager_on_unit(p_unit_id);

    IF EXISTS (SELECT 1 FROM public.occasions WHERE unit = p_unit_id) THEN
        RAISE EXCEPTION 'UNIT_HAS_OCCASIONS';
    END IF;

    SELECT count(*)
      INTO v_manager_count
      FROM public.unit_users
     WHERE "user" = auth.uid()
       AND is_manager = true;

    IF v_manager_count <= 1 THEN
        RAISE EXCEPTION 'CANNOT_DELETE_LAST_UNIT';
    END IF;

    -- Preserve notification history without retaining a deleted unit or live intent.
    UPDATE public.email_messages
       SET unit = NULL,
           workflow_state = CASE WHEN workflow_state IN ('pending','retry_wait','blocked','preparing')
                                 THEN 'cancelled' ELSE workflow_state END
     WHERE unit = p_unit_id AND message_kind = 'custom' AND code IN ('UNIT_VERIFICATION_REQUEST','MEASUREMENT_APPROVAL_REQUEST');

    DELETE FROM public.unit_users WHERE unit = p_unit_id;
    DELETE FROM public.units WHERE id = p_unit_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_unit(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_unit(bigint) TO authenticated;
