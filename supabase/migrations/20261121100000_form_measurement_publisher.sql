-- Keep existing conversion facts and deliveries in place as writer ownership changes.
DROP FUNCTION public.record_form_conversion_internal(bigint);
DROP FUNCTION public.record_form_conversion_internal(bigint,boolean);
DROP FUNCTION public.record_form_paid_conversion_internal(bigint);

-- SOURCE: eshop_forms/form_measurement_subscriptions.sql
-- Browser projections and the Meta delivery worker subscribe to stored facts
-- by role. Each adapter still owns its own authorization and delivery rules.
CREATE OR REPLACE FUNCTION public.form_measurement_subscription_kind_internal(p_subscription text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE p_subscription
  WHEN 'web_purchase_snapshot' THEN 'purchase'
  WHEN 'web_paid_purchase' THEN 'order_fully_paid'
  WHEN 'web_free_registration' THEN 'free_registration'
  WHEN 'web_waitlist' THEN 'waitlist'
  WHEN 'meta_purchase' THEN 'order_fully_paid'
 END;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_subscription_kind_internal(text) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/form_measurement_publisher.sql
-- Business callers own authorization, replay and their transaction. Only
-- these four business moments may mint a conversion identity.
CREATE OR REPLACE FUNCTION public.publish_form_measurement_event_internal(p_event text,p_order bigint)
RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE
 o eshop.orders;
 decision record;
 fact_kind text;
 items jsonb;
 total numeric;
 payload jsonb;
 identity uuid:=gen_random_uuid();
 published uuid;
 brand text;
BEGIN
 IF (p_event IN ('checkout_finalized','waitlist_registered','waitlist_offer_accepted','order_fully_paid')) IS NOT TRUE THEN
  RAISE invalid_parameter_value USING MESSAGE='Unknown form measurement event';
 END IF;
 BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF NOT FOUND THEN RETURN NULL; END IF;

 fact_kind:=CASE
  WHEN p_event='order_fully_paid' THEN 'order_fully_paid'
  WHEN p_event='waitlist_registered' AND o.state='waitlisted' THEN 'waitlist'
  WHEN p_event IN ('checkout_finalized','waitlist_offer_accepted') AND o.state IS DISTINCT FROM 'waitlisted' THEN
   CASE WHEN o.price=0 THEN 'free_registration'
        WHEN o.price>0 AND trim(o.currency_code) ~ '^[A-Z]{3}$' THEN 'purchase' END
 END;
 IF fact_kind IS NULL THEN RETURN NULL; END IF;

 SELECT c.event_id INTO published FROM analytics.conversion_facts c WHERE c."order"=p_order AND c.kind=fact_kind;
 IF FOUND THEN RETURN published; END IF;

 IF p_event='order_fully_paid' THEN
  -- Payment owners hold the order and payment locks. A write failure must
  -- abort settlement so its retry can publish in the same transaction.
  IF NOT public.form_paid_conversion_eligible_internal(p_order) THEN RETURN NULL; END IF;
 ELSE
  SELECT * INTO decision FROM public.form_measurement_decision_internal(o.form);
  IF decision.conversion_eligible IS NOT TRUE THEN RETURN NULL; END IF;
 END IF;

 IF p_event='order_fully_paid' THEN
  payload:=jsonb_build_object('value',o.price,'currency',trim(o.currency_code));
 ELSIF fact_kind IN ('waitlist','free_registration') THEN
  payload:=jsonb_build_object('event','generate_lead','event_id',identity,'currency',coalesce(nullif(trim(o.currency_code),''),'CZK'),
   'value',0,'lead_source',fact_kind);
 ELSE
  -- Freeze the checkout cohort even if there is no safe browser item projection.
  payload:=jsonb_build_object('purchase_timing',decision.purchase_timing,
   'capi_required',p_event='checkout_finalized' AND decision.capi_unit IS NOT NULL);
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

 INSERT INTO analytics.conversion_facts("order",kind,event_id,payload)
 VALUES(p_order,fact_kind,identity,payload)
 ON CONFLICT("order",kind) DO NOTHING
 RETURNING event_id INTO published;
 IF NOT FOUND THEN
  SELECT c.event_id INTO published FROM analytics.conversion_facts c WHERE c."order"=p_order AND c.kind=fact_kind;
 END IF;
 RETURN published;
 EXCEPTION WHEN OTHERS THEN
  IF p_event='order_fully_paid' THEN RAISE; END IF;
  -- Optional measurement cannot stop checkout or waitlist registration.
  RETURN NULL;
 END;
END $$;
REVOKE ALL ON FUNCTION public.publish_form_measurement_event_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/form_datalayer.sql
-- The creation cohort is immutable. Legacy purchase facts are order mode;
-- settings edits and later CAPI activation cannot convert them into paid events.
CREATE OR REPLACE FUNCTION public.form_order_purchase_timing_internal(p_order bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(payload->>'purchase_timing','order') FROM analytics.conversion_facts
 WHERE "order"=p_order AND kind=public.form_measurement_subscription_kind_internal('web_purchase_snapshot');
$$;
REVOKE ALL ON FUNCTION public.form_order_purchase_timing_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- CAPI activation after creation cannot adopt a pre-existing browser cohort.
CREATE OR REPLACE FUNCTION public.form_order_purchase_capi_required_internal(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT payload->'capi_required'='true'::jsonb
 FROM analytics.conversion_facts WHERE "order"=p_order AND kind=public.form_measurement_subscription_kind_internal('web_purchase_snapshot')),false);
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
 JOIN analytics.conversion_facts snapshot ON snapshot."order"=o.id AND snapshot.kind=public.form_measurement_subscription_kind_internal('web_purchase_snapshot')
 LEFT JOIN analytics.conversion_facts paid ON paid."order"=o.id AND paid.kind=public.form_measurement_subscription_kind_internal('web_paid_purchase')
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
   JOIN analytics.conversion_facts c ON c."order"=d.order_id AND c.kind=public.form_measurement_subscription_kind_internal('meta_purchase')
   WHERE d.order_id=p_order AND d.status='sent' AND d.revoked_at IS NULL AND c.created_at>statement_timestamp()-interval '47 hours');
$$;
REVOKE ALL ON FUNCTION public.form_meta_purchase_datalayer_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.form_conversion_datalayer_internal(p_order bigint,p_kind text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_kind=public.form_measurement_subscription_kind_internal('web_purchase_snapshot') THEN public.form_purchase_datalayer_internal(p_order)
 ELSE (SELECT c.payload FROM analytics.conversion_facts c JOIN eshop.orders o ON o.id=c."order"
 WHERE c."order"=p_order AND c.kind=p_kind AND p_kind IN (public.form_measurement_subscription_kind_internal('web_waitlist'),public.form_measurement_subscription_kind_internal('web_free_registration'))
 AND EXISTS(SELECT FROM public.form_measurement_decision_internal(o.form) d WHERE d.conversion_eligible)) END;
$$;
REVOKE ALL ON FUNCTION public.form_conversion_datalayer_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/meta_purchase_worker.sql
CREATE OR REPLACE FUNCTION public.claim_meta_purchase_deliveries(p_limit integer)
RETURNS TABLE(order_id bigint, lease uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN QUERY
 WITH due AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  JOIN analytics.meta_purchase_connectors c ON c.unit=d.unit
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind=public.form_measurement_subscription_kind_internal('meta_purchase')
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
 SELECT * INTO fact FROM analytics.conversion_facts WHERE "order"=p_order_id AND kind=public.form_measurement_subscription_kind_internal('meta_purchase');
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
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind=public.form_measurement_subscription_kind_internal('meta_purchase')
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

-- SOURCE: eshop_orders/create_ticket_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_command_internal(
  p_order jsonb,p_command_id uuid,p_client_id uuid,p_context jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text; v_legacy_hash text; v_request jsonb;
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
  v_request:=jsonb_build_object('occasion',v_occasion,'order',public.strip_payment_sources_internal(p_order))
    ||CASE WHEN p_context IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('administration',p_context) END;
  v_hash:=encode(extensions.digest(convert_to((v_request#-'{order,metaPurchaseConsent}')::text,'UTF8'),'sha256'),'hex');
  IF p_order ? 'metaPurchaseConsent' THEN
    -- Historical receipts may bind the original consent. Match their exact
    -- request and buyer; new claims always use the consent-independent hash.
    v_legacy_hash:=encode(extensions.digest(convert_to((v_request#-'{order,metaPurchaseConsent,matching}')::text,'UTF8'),'sha256'),'hex');
    IF EXISTS(SELECT FROM public.client_mutation_receipts r WHERE r.command_id=p_command_id
      AND r.command_name='inventory.order.create' AND r.occasion=v_occasion
      AND r.actor_id IS NOT DISTINCT FROM v_actor
      AND (v_actor IS NOT NULL OR r.actor_client_id=p_client_id)
      AND r.request_sha256=v_legacy_hash) THEN
      v_hash:=v_legacy_hash;
    END IF;
  END IF;
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
    IF p_context IS NULL AND public.form_measurement_visitor_role_internal(
      (SELECT form FROM eshop.orders WHERE id=(v_result#>>'{data,order,id}')::bigint)) IN ('visitor','anonymous') THEN
      v_result:=jsonb_set(v_result,'{data,analytics}',coalesce(public.form_purchase_datalayer_internal((v_result#>>'{data,order,id}')::bigint),public.form_conversion_datalayer_internal((v_result#>>'{data,order,id}')::bigint,'free_registration'),'null'::jsonb));
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
  v_result:=public.create_ticket_order_internal_v1((public.strip_payment_sources_internal(p_order)-ARRAY['checkoutOrigin','discount_command_id','metaPurchaseConsent'])||CASE WHEN p_order ? 'discount' THEN jsonb_build_object('discount_command_id',p_command_id) ELSE '{}'::jsonb END);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  IF p_context IS NULL AND p_order ? 'metaPurchaseConsent' THEN
    PERFORM public.capture_meta_purchase_consent_internal((v_result#>>'{order,id}')::bigint,p_order->'metaPurchaseConsent');
  END IF;
  PERFORM public.attach_checkout_origin_internal((v_result#>>'{order,id}')::bigint,v_origin);
  PERFORM public.attach_provider_order_source_internal((v_result#>>'{order,id}')::bigint,p_command_id,p_order);
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,p_order->>'lang');
  IF p_context IS NOT NULL THEN v_result:=v_result||jsonb_build_object('adminQuote',p_context->'quote','paymentPreparationPolicy','leased_keep_pending'); END IF;
  v_result:=public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.create',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Ticket order','changedFields',jsonb_build_array(
        'tickets','products','allocations','membership'))),v_before_users,v_result,
    v_actor_kind);
  -- The receipt remains frozen; first response and authorized replay project the
  -- same immutable facts, filtered through current stored form policy.
  IF p_context IS NULL AND public.form_measurement_visitor_role_internal(
      (SELECT form FROM eshop.orders WHERE id=(v_result#>>'{data,order,id}')::bigint)) IN ('visitor','anonymous') THEN
    PERFORM public.publish_form_measurement_event_internal('checkout_finalized',(v_result#>>'{data,order,id}')::bigint);
  END IF;
  IF p_context IS NULL AND public.form_measurement_visitor_role_internal(
      (SELECT form FROM eshop.orders WHERE id=(v_result#>>'{data,order,id}')::bigint)) IN ('visitor','anonymous') THEN
    v_result:=jsonb_set(v_result,'{data,analytics}',coalesce(public.form_purchase_datalayer_internal((v_result#>>'{data,order,id}')::bigint),
      public.form_conversion_datalayer_internal((v_result#>>'{data,order,id}')::bigint,'free_registration'),'null'::jsonb));
  END IF;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_command_internal(jsonb,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Released RPC signature and ordinary checkout hashes remain unchanged.
CREATE OR REPLACE FUNCTION public.create_ticket_order_client_sync_v1(p_order jsonb,p_command_id uuid,p_client_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.create_ticket_order_command_internal(p_order,p_command_id,p_client_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) TO anon,authenticated;

-- SOURCE: eshop_waitlist/commands.sql
-- Edge is the trusted preparation boundary for random capabilities and sealed email.
-- It verifies the bearer user; SQL still checks the explicit actor's occasion rights.
CREATE OR REPLACE FUNCTION public.sanitize_waitlist_history_internal(p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(key,public.sanitize_waitlist_history_internal(value)),'{}') INTO result
  FROM jsonb_each(p_value) WHERE lower(key) NOT IN
   ('token','secret','password','offertoken','managetoken','capability','waitlistenvelope','sealed','tokenhash') AND lower(key) NOT IN(SELECT lower(source_field) FROM eshop.payment_providers WHERE source_field IS NOT NULL);
  RETURN result;
 ELSIF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(value) ORDER BY ordinal),'[]') INTO result
  FROM jsonb_array_elements(p_value) WITH ORDINALITY item(value,ordinal);
  RETURN result;
 END IF;
 RETURN p_value;
END $$;
CREATE OR REPLACE FUNCTION public.snapshot_waitlist_tickets_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(to_jsonb(p)||jsonb_build_object('answers',p.data,'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(p.id))) ORDER BY created_at,id),'[]')
 FROM public.get_order_tickets_internal(p_order) p;
$$;
REVOKE ALL ON FUNCTION public.sanitize_waitlist_history_internal(jsonb),public.snapshot_waitlist_tickets_internal(bigint)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.execute_waitlist_command_client_sync_v1(
 p_operation text,p_payload jsonb,p_command_id uuid,p_client_id uuid,p_actor uuid DEFAULT NULL,p_deliveries jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; occ bigint; oid bigint; offer uuid; mode text; c jsonb; result jsonb; claim jsonb;
 hash text; selected bigint[]; expected integer; changed integer; recipients jsonb; r jsonb; delivery jsonb;
 person jsonb; created_ticket bigint; slot_ids uuid[]; expiry timestamptz; f public.forms; people jsonb; n integer; before_users uuid[];
 previous_sub text; actor_kind text; o eshop.orders; entity_changes jsonb:='[]';
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_operation NOT IN ('register','send','accept','decline','cancel','withdraw') OR p_command_id IS NULL OR p_client_id IS NULL
 OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4194304 THEN RAISE EXCEPTION 'Invalid waitlist command'; END IF;
 IF p_operation='register' THEN SELECT id INTO fid FROM public.forms WHERE key=(p_payload->>'form')::uuid;
 ELSIF p_operation='send' THEN fid:=(p_payload->>'formId')::bigint;
 ELSIF p_operation='withdraw' THEN oid:=(p_payload->>'orderId')::bigint; SELECT form INTO fid FROM eshop.orders WHERE id=oid;
 ELSE offer:=(p_payload->>'offerId')::uuid; SELECT order_id,form_id INTO oid,fid FROM eshop.waitlist_offers WHERE id=offer; END IF;
 SELECT * INTO f FROM public.forms WHERE id=fid; occ:=f.occasion;
 PERFORM public.check_occasion_writable(occ);
 IF occ IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Match checkout and cancellation: scope precedes the form/order parents.
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 IF p_operation IN ('send','cancel') AND NOT public.can_write_orders_as_actor_internal(p_actor,occ) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 previous_sub:=current_setting('request.jwt.claim.sub',true);
 PERFORM set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
 hash:=encode(extensions.digest(jsonb_build_object('operation',p_operation,'payload',CASE WHEN p_payload ? 'orderDetails' THEN jsonb_set(p_payload,'{orderDetails}',public.strip_payment_sources_internal(p_payload->'orderDetails')) ELSE p_payload END,'actor',p_actor)::text,'sha256'),'hex');
 BEGIN
  IF p_actor IS NULL THEN claim:=public.begin_anonymous_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_client_id,hash); actor_kind:='unknown';
  ELSE claim:=public.begin_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_actor,hash); actor_kind:='user'; END IF;
 EXCEPTION WHEN invalid_parameter_value THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  RETURN jsonb_build_object('code',409,'errorCode','COMMAND_PAYLOAD_CONFLICT');
 END;
 IF claim->>'disposition'='replay' THEN
  result:=claim->'response';
  IF p_actor IS NULL AND p_operation IN ('register','accept') THEN
   result:=jsonb_set(result,'{data,analytics}',coalesce(public.form_purchase_datalayer_internal((result#>>'{data,order,id}')::bigint),public.form_conversion_datalayer_internal((result#>>'{data,order,id}')::bigint,CASE WHEN p_operation='register' THEN 'waitlist' ELSE 'free_registration' END),'null'::jsonb));
  END IF;
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN public.project_local_payment_reference_order_internal(result); END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO before_users FROM public.occasion_users WHERE occasion=occ;
 BEGIN
  PERFORM 1 FROM public.forms WHERE id=fid FOR UPDATE;
 IF p_operation IN ('accept','decline','cancel','withdraw') THEN
  PERFORM public.check_waitlist_scope_internal(oid,offer,p_payload->>'token',p_actor,p_operation); END IF;

  PERFORM public.expire_waitlist_form_internal(fid);
  c:=public.get_form_capacity_snapshot_internal(fid);
  IF p_operation='register' THEN
   mode:=public.get_form_registration_mode_internal(fid);
   IF mode<>'waitlist' THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   people:=public.normalize_form_ticket_answers_internal(fid,p_payload->'tickets');
   PERFORM public.validate_waitlist_answers_internal(fid,p_payload,people,true);
   IF nullif(p_payload->>'email','') IS NULL THEN RAISE EXCEPTION 'Email required'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(people) p CROSS JOIN LATERAL jsonb_array_elements(coalesce(p->'fields','[]')) a WHERE a ? 'product_type') THEN
    RAISE EXCEPTION 'Waitlist does not accept products'; END IF;
   oid:=public.allocate_ticket_order_identity_internal(fid);
   UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=p_payload-'tickets'-'token' WHERE id=oid;
   FOR person IN SELECT * FROM jsonb_array_elements(people) LOOP
    INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data,waitlist_queue_at)
     VALUES(occ,'waitlisted',NULL,public.extract_ticket_answers_internal(fid,person),clock_timestamp()) RETURNING id INTO created_ticket;
    INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,created_ticket,NULL); END LOOP;
   result:=jsonb_build_object('code',200,'order',jsonb_build_object('id',oid,'order_symbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),'state','waitlisted','payment_info',NULL,'price',NULL),
    'waitlistSummary',public.get_waitlist_summary_internal(oid),'email',public.enqueue_waitlist_email_internal(oid,NULL,p_command_id,p_deliveries->0));
  ELSIF p_operation='send' THEN
   SELECT * INTO f FROM public.forms WHERE id=fid;
   IF NOT f.waitlist_enabled THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   IF f.capacity_revision<>(p_payload->>'revision')::bigint THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','OFFER_CHANGED','capacity',c)::text; END IF;
   expiry:=(p_payload->>'expiresAt')::timestamptz;
   IF expiry IS NULL OR expiry<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
   recipients:=p_payload->'recipients';
   IF jsonb_typeof(recipients)<>'array' OR jsonb_array_length(recipients)<1 OR
    jsonb_array_length(recipients)<>(SELECT count(DISTINCT x->>'orderId') FROM jsonb_array_elements(recipients) x) THEN RAISE EXCEPTION 'Invalid recipients'; END IF;
   SELECT sum((x->>'count')::integer) INTO n FROM jsonb_array_elements(recipients) x;
   IF n>(c->>'offerablePlaces')::integer THEN RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
   PERFORM 1 FROM eshop.orders WHERE id IN(SELECT (x->>'orderId')::bigint FROM jsonb_array_elements(recipients) x) ORDER BY id FOR UPDATE;
   result:=jsonb_build_object('code',200,'offers','[]'::jsonb);
   FOR r IN SELECT * FROM jsonb_array_elements(recipients) ORDER BY (value->>'orderId')::bigint LOOP
    oid:=(r->>'orderId')::bigint; n:=(r->>'count')::integer;
    IF n<1 OR NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND form=fid AND state='waitlisted') THEN RAISE EXCEPTION 'Invalid recipient scope'; END IF;
    SELECT array_agg(id) INTO selected FROM (SELECT p.id FROM eshop.tickets p WHERE p.state='waitlisted'
     AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=p.id AND x."order"=oid)
     AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE ticket_id=p.id AND outcome='pending')
     ORDER BY waitlist_queue_at,created_at,id LIMIT n FOR UPDATE) tickets;
    IF coalesce(cardinality(selected),0)<>n THEN RAISE EXCEPTION 'OFFER_CHANGED'; END IF;
    INSERT INTO eshop.waitlist_offers(order_id,form_id,created_by,expires_at,revision) VALUES(oid,fid,p_actor,expiry,f.capacity_revision) RETURNING id INTO offer;
    INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id) SELECT offer,id,fid FROM unnest(selected) id;
    SELECT x INTO delivery FROM jsonb_array_elements(p_deliveries) x WHERE (x->>'orderId')::bigint=oid;
    result:=jsonb_set(result,'{offers}',result->'offers'||jsonb_build_array(jsonb_build_object('orderId',oid,'offerId',offer,'count',n,'expiresAt',expiry,
     'email',public.enqueue_waitlist_email_internal(oid,offer,p_command_id,delivery))));
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,'waitlisted',jsonb_build_object('action','offer_sent','offerId',offer,'count',n,'expiresAt',expiry));
    entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist offer','changedFields',jsonb_build_array('waitlistSummary')));
   END LOOP;
  ELSIF p_operation='accept' THEN
   result:=public.accept_waitlist_offer_internal(p_payload,p_command_id,p_actor);
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',result#>>'{order,id}','operation','update','safeLabel','Accepted order','changedFields',jsonb_build_array('state','tickets','products','allocations')));
  ELSE
   PERFORM public.lock_order_capacity_scope_internal(ARRAY[oid]);
   IF (SELECT state FROM eshop.orders WHERE id=oid)<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   SELECT array_agg(x::bigint) INTO selected FROM jsonb_array_elements_text(p_payload->'ticketIds') x; n:=coalesce(cardinality(selected),0);
   IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(selected) x) THEN RAISE EXCEPTION 'Invalid persons'; END IF;
   IF n<>(SELECT count(*) FROM public.get_order_tickets_internal(oid) WHERE id=ANY(selected) AND state='waitlisted') THEN
    RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   IF p_operation IN ('decline','cancel') AND n<>(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=offer AND outcome='pending' AND ticket_id=ANY(selected)) THEN
    RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   UPDATE eshop.waitlist_offer_slots SET outcome=CASE WHEN p_operation='decline' THEN 'declined' ELSE 'cancelled' END,updated_at=clock_timestamp()
    WHERE ticket_id=ANY(selected) AND outcome='pending' AND (p_operation='withdraw' OR offer_id=offer);
   UPDATE eshop.tickets SET state=CASE WHEN p_operation='withdraw' THEN 'storno' ELSE state END,
    waitlist_queue_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=ANY(selected);
   UPDATE eshop.waitlist_capabilities cap SET revoked_at=clock_timestamp() WHERE cap.order_id=oid AND kind='offer' AND NOT EXISTS
    (SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=cap.offer_id AND outcome='pending');
   result:=jsonb_build_object('code',200,'orderId',oid,'waitlistSummary',public.get_waitlist_summary_internal(oid));
  END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=fid;
  IF p_operation<>'send' THEN
   -- Acceptance owns its richer before/after snapshot at the same transaction
   -- boundary; avoid a second action-only row hiding that record in the detail.
   IF p_operation<>'accept' THEN
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,(SELECT state FROM eshop.orders WHERE id=oid),
     jsonb_build_object('action','waitlist_'||p_operation,'commandId',p_command_id,
     'ticketIds',CASE WHEN p_operation='register' THEN
       (SELECT jsonb_agg(id ORDER BY created_at,id) FROM public.get_order_tickets_internal(oid))
       ELSE to_jsonb(selected) END,
     'tickets',public.snapshot_waitlist_tickets_internal(oid)));
   END IF;
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist order','changedFields',jsonb_build_array('waitlistSummary','tickets')));
  END IF;
  IF p_operation='register' THEN
   PERFORM public.notification_center_order_internal(oid,'waitlist_registered','created',p_actor);
  ELSIF p_operation='accept' THEN
   PERFORM public.notification_center_order_internal((result#>>'{order,id}')::bigint,'offer_accepted',offer::text||':'||p_command_id,p_actor,
    jsonb_build_object('offerId',offer,'count',jsonb_array_length(p_payload->'ticketIds')));
  ELSIF p_operation='withdraw' THEN
   PERFORM public.notification_center_order_internal(oid,'order_cancelled','withdraw:'||p_command_id,p_actor,jsonb_build_object('count',n));
  ELSIF p_operation='decline' THEN
   PERFORM public.notification_center_order_internal(oid,'offer_declined',offer::text||':'||p_command_id,p_actor,jsonb_build_object('offerId',offer,'count',n));
  END IF;
  PERFORM public.notification_center_form_capacity_internal(fid,p_actor);
  result:=result||jsonb_build_object('capacity',public.get_form_capacity_snapshot_internal(fid));
 EXCEPTION WHEN OTHERS THEN
  result:=CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',409,'errorCode',SQLERRM,'message',SQLERRM) END;
  result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
   CASE WHEN (result->>'code')::integer BETWEEN 200 AND 599 THEN (result->>'code')::integer ELSE 409 END,result);
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN result;
 END;
 entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','form','entityId',fid,'operation','update','safeLabel','Form capacity','changedFields',jsonb_build_array('capacity','registrationMode')));
 IF p_operation='accept' AND p_payload ? 'administrativeApproval' THEN
  result:=result||jsonb_build_object('adminQuote',p_payload#>'{administrativeApproval,quote}',
   'adminScope',p_payload#>'{administrativeApproval,scope}','paymentPreparationPolicy','leased_keep_pending'); END IF;
 result:=public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.waitlist.'||p_operation,entity_changes,before_users,result,actor_kind);
 IF p_actor IS NULL AND p_operation IN ('register','accept') THEN
  -- Offer checkout has no Meta consent capture. Keep it in the browser-only cohort.
  PERFORM public.publish_form_measurement_event_internal(
   CASE WHEN p_operation='register' THEN 'waitlist_registered' ELSE 'waitlist_offer_accepted' END,
   (result#>>'{data,order,id}')::bigint);
  result:=jsonb_set(result,'{data,analytics}',coalesce(public.form_purchase_datalayer_internal((result#>>'{data,order,id}')::bigint),public.form_conversion_datalayer_internal((result#>>'{data,order,id}')::bigint,CASE WHEN p_operation='register' THEN 'waitlist' ELSE 'free_registration' END),'null'::jsonb));
 END IF;
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) TO service_role;

-- SOURCE: eshop_transactions/apply_transaction_pairing.sql
CREATE OR REPLACE FUNCTION public.apply_transaction_pairing(
  p_transaction_id bigint,
  p_payment_info_id bigint,
  p_method text,
  p_actor_kind text DEFAULT 'system',
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_target eshop.payment_info%ROWTYPE;
  v_old_payment_info_id bigint;
  v_order_id bigint;
  v_order_ids bigint[];
  v_order_bindings jsonb;
  v_locked_order_bindings jsonb;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id));
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
  IF p_method IS NULL OR p_method !~ '^[a-z0-9_]{1,64}$' THEN
    RAISE EXCEPTION 'PAIRING_INVALID_METHOD';
  END IF;
  IF p_actor_kind NOT IN ('service', 'user', 'system') THEN
    RAISE EXCEPTION 'PAIRING_INVALID_ACTOR_KIND';
  END IF;

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_TRANSACTION_NOT_FOUND'; END IF;
  v_old_payment_info_id := v_transaction.payment_info;

  -- The transaction row stabilizes the old target (also held by ingest/matcher).
  -- Acquire every stored old/new form and order before either payment row,
  -- matching product edit and cancellation. Never trust a caller's scope list.
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]),
    coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_order_ids,v_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  PERFORM public.lock_order_capacity_scope_internal(v_order_ids);
  SELECT coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_locked_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  IF v_order_bindings IS DISTINCT FROM v_locked_order_bindings THEN
    RAISE EXCEPTION 'PAIRING_ORDER_SCOPE_CHANGED' USING ERRCODE='40001';
  END IF;
  PERFORM 1 FROM eshop.payment_info WHERE id IN (v_old_payment_info_id,p_payment_info_id)
  ORDER BY id FOR UPDATE;

  -- A settled movement is immutable through the generic attach/unlink API.
  -- Cash voids and evidenced bank reclassification have their explicit owner.
  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id)
     AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION';
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0
     AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b WHERE b.id=v_transaction.bank_account_id
       AND upper(b.type)='CASH' AND v_transaction.transaction_type='manual'
       AND v_transaction.ingest_source='manual') THEN
    RAISE EXCEPTION 'OUTGOING_REQUIRES_REFUND_CLASSIFICATION';
  END IF;
  IF v_old_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.assert_payment_refund_reservations_internal(v_old_payment_info_id,greatest(v_transaction.amount,0));
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0 THEN
    PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-v_transaction.amount);
  END IF;

  IF p_actor_kind='user' THEN
    FOR v_order_id IN SELECT id FROM eshop.orders
      WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id) ORDER BY id LOOP
      PERFORM public.check_order_is_mutable(v_order_id);
    END LOOP;
  END IF;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF public.payment_method_is_online_internal(v_target.payment_method) THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_target.payment_method='cash' AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b
      WHERE b.id=v_transaction.bank_account_id AND b.type='CASH' AND v_transaction.transaction_type='manual') THEN
      RAISE EXCEPTION 'CASH_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_transaction.transaction_type='manual' THEN
      IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
        JOIN eshop.orders o ON o.occasion=oc.id JOIN eshop.bank_accounts b ON b.id=link.bank_account
        WHERE o.payment_info=v_target.id AND b.id=v_transaction.bank_account_id ) THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
    END IF;
    IF upper(trim(v_transaction.currency::text)) <> upper(trim(v_target.currency_code::text)) THEN
      RAISE EXCEPTION 'PAIRING_CURRENCY_MISMATCH';
    END IF;
    IF v_transaction.transaction_type IS DISTINCT FROM 'manual'
       AND v_transaction.bank_account_id <> v_target.bank_account
       AND NOT public.bank_sync_accounts_match(p_transaction_id,v_target.bank_account) THEN
      RAISE EXCEPTION 'PAIRING_BANK_ACCOUNT_MISMATCH';
    END IF;
  END IF;

  UPDATE eshop.transactions SET payment_info = p_payment_info_id WHERE id = p_transaction_id;

  IF v_old_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(v_old_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(p_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN
      PERFORM public.recalculate_order_payment_status(v_order_id);
      IF v_transaction.amount>0 AND v_transaction.transaction_type IS DISTINCT FROM 'manual'
        AND v_transaction.ingest_source IS DISTINCT FROM 'manual' THEN
        PERFORM public.publish_form_measurement_event_internal('order_fully_paid',v_order_id);
      END IF;
    END IF;
  END IF;


  IF v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.notification_center_prepared_invalidate(e.id) FROM public.notification_center_events e
     JOIN eshop.orders o ON o.occasion=e.occasion AND o.id=(e.data->>'orderId')::bigint
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id AND o.payment_info=v_old_payment_info_id;
    UPDATE public.notification_center_events e SET status='resolved' FROM eshop.orders o
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id
      AND o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion AND o.payment_info=v_old_payment_info_id;
    IF p_payment_info_id IS NOT NULL AND v_transaction.amount>0 THEN
      FOR v_order_id IN SELECT id FROM eshop.orders WHERE payment_info=p_payment_info_id LOOP
       PERFORM public.notification_center_payment_fact_internal(v_order_id,'transaction',p_transaction_id::text,
        v_transaction.amount,v_transaction.currency::text,coalesce(v_transaction.date,now()),
        EXISTS(SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_id=p_transaction_id AND new_payment_info_id IS NOT NULL));
      END LOOP;
    END IF;
  END IF;
  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind, details
  ) VALUES (
    p_transaction_id, p_transaction_id, v_old_payment_info_id,
    p_payment_info_id, CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    p_method, auth.uid(), p_actor_kind, COALESCE(p_details, '{}'::jsonb)
  );

  RETURN jsonb_build_object('status', CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    'transaction_id', p_transaction_id, 'payment_info_id', p_payment_info_id);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_transaction_pairing(bigint,bigint,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE: payment_providers/effects.sql
-- Shared admission effect. Callers own authorization and financial interpretation.
-- This owner never manufactures a provider observation or changes original prices.
-- Lock hierarchy: payment policy fence -> capacity/forms -> order -> payment ->
-- provider attempt -> tickets. Callers that hold later locks must own the parents.
CREATE OR REPLACE FUNCTION public.cancel_online_order_admission_internal(p_order bigint,p_state text)
RETURNS bigint[] LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; cancelled bigint[];
BEGIN
 IF p_state IS NULL OR p_state NOT IN ('storno','expired') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid admission cancellation state'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info
  AND public.payment_method_is_online_internal(pi.payment_method)) THEN
  RAISE EXCEPTION 'ONLINE_ADMISSION_SOURCE_REQUIRED'; END IF;
 IF o.state=p_state THEN RETURN '{}'::bigint[]; END IF;
 SELECT array_agg(t.id ORDER BY t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t
 WHERE coalesce(t.state,'') NOT IN ('used','storno');
 PERFORM public.internal_storno_tickets_221(cancelled);
 UPDATE eshop.orders SET state=p_state,email_payment_version=email_payment_version+1,
  updated_at=clock_timestamp() WHERE id=o.id;
 PERFORM public.cancel_order_email_intents(o.id);
 RETURN coalesce(cancelled,'{}');
END $$;
REVOKE ALL ON FUNCTION public.cancel_online_order_admission_internal(bigint,text)
 FROM PUBLIC,anon,authenticated,service_role;

-- Lock order: capacity/form scope -> order -> payment -> provider attempt -> tickets.
-- All facts are read back from connector storage. No caller-supplied markPaid/amount.
CREATE OR REPLACE FUNCTION public.apply_provider_payment_effects_internal(
 p_provider text,p_attempt uuid,p_revision text,p_before jsonb,p_expired boolean DEFAULT false,
 p_unresolved boolean DEFAULT false,p_action text DEFAULT 'observe',p_tickets bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE context jsonb; prior jsonb; o eshop.orders; pi eshop.payment_info; totals record; projection jsonb; transition jsonb;
 received numeric; refunded numeric; payment_time timestamptz; deadline timestamptz; cancelled bigint[];
 conflict boolean; action_required boolean; changed boolean:=false; args jsonb:=jsonb_build_object('attemptId',p_attempt); decision jsonb; fact jsonb;
BEGIN
 IF p_provider IS NULL OR p_provider='bank' OR p_attempt IS NULL OR nullif(p_revision,'') IS NULL
  OR p_action IS NULL OR p_action NOT IN ('observe','keep','cancel_selected') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_INPUT_INVALID'; END IF;
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS NULL OR jsonb_typeof(context)<>'object' OR NOT context ?& ARRAY['attemptId','orderId','paymentId','connectionId','organizationId','unitId','accountId','livemode','amountMinor','currency','reservationExpiresAt','state','incomplete','receivedMinor','refundedMinor','paymentTime','decisions']
  OR context->>'attemptId' IS DISTINCT FROM p_attempt::text OR nullif(context->>'accountId','') IS NULL
  OR nullif(context->>'connectionId','') IS NULL OR (context->>'connectionId')::uuid IS NULL
  OR context->>'state' IS NULL OR context->>'state' NOT IN ('preparing','open','uncertain','paid','expired','action_required')
  OR jsonb_typeof(context->'livemode') IS DISTINCT FROM 'boolean' OR jsonb_typeof(context->'incomplete') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(context->'decisions') IS DISTINCT FROM 'array'
  OR jsonb_typeof(context->'amountMinor') IS DISTINCT FROM 'number' OR jsonb_typeof(context->'receivedMinor') IS DISTINCT FROM 'number'
  OR jsonb_typeof(context->'refundedMinor') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'PAYMENT_EFFECT_CONTEXT_INVALID'; END IF;
 prior:=context;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[(context->>'orderId')::bigint]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(context->>'orderId')::bigint FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 PERFORM public.payment_provider_call_internal(p_provider,'effect_lock',args);
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS DISTINCT FROM prior OR pi.id IS DISTINCT FROM (context->>'paymentId')::bigint
  OR pi.payment_method IS DISTINCT FROM p_provider OR pi.amount*100 IS DISTINCT FROM (context->>'amountMinor')::numeric
  OR pi.currency_code::text IS DISTINCT FROM context->>'currency'
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=(context->>'organizationId')::bigint AND unit=(context->>'unitId')::bigint)
  OR (p_before IS NOT NULL AND p_before->>'method' IS DISTINCT FROM p_provider) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_SCOPE_INVALID'; END IF;
 IF (context->>'amountMinor')::numeric<=0 OR (context->>'amountMinor')::numeric<>trunc((context->>'amountMinor')::numeric) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 received:=(context->>'receivedMinor')::numeric/100;refunded:=(context->>'refundedMinor')::numeric/100;
 deadline:=(context->>'reservationExpiresAt')::timestamptz;payment_time:=(context->>'paymentTime')::timestamptz;
 IF received<0 OR refunded<0 OR received>pi.amount OR refunded>received OR deadline IS NULL
  OR received*100<>trunc(received*100) OR refunded*100<>trunc(refunded*100)
  OR (received>0 AND payment_time IS NULL) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 conflict:=totals.gross_received>pi.amount OR totals.external_received<>0;
 action_required:=context->>'state'='action_required';
 IF p_action<>'observe' THEN
  IF auth.uid() IS NULL OR NOT public.can_write_orders(o.occasion) OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=(context->>'organizationId')::bigint)
   THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF refunded<=0 OR refunded>=pi.amount OR context->>'state'<>'paid' OR o.state NOT IN ('paid','sent') OR totals.invalid_identity
   OR context->'incomplete'='true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_PARTIAL_REFUND_REQUIRED'; END IF;
  IF (p_action='keep' AND cardinality(p_tickets)<>0) OR (p_action='cancel_selected' AND cardinality(p_tickets) NOT BETWEEN 1 AND 1000)
   OR EXISTS(SELECT 1 FROM unnest(p_tickets) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) t WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'PAYMENT_REFUND_TICKET_UNAVAILABLE'; END IF;
  PERFORM 1 FROM eshop.tickets WHERE id=ANY(p_tickets) ORDER BY id FOR UPDATE;
  IF p_action='cancel_selected' THEN
   PERFORM public.internal_storno_tickets_221(p_tickets);
   UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state<>'storno') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  END IF;
  decision:=public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason',CASE WHEN p_action='keep' THEN 'partial_refund_keep' ELSE 'partial_refund_cancel' END,'revision',p_revision,'tickets',to_jsonb(p_tickets)));
  PERFORM public.enqueue_order_wallet_internal(o.id);
  RETURN jsonb_build_object('changed',true,'decisionId',decision,'payment',public.provider_order_payment_projection_internal(o.id));
 END IF;
 IF conflict AND NOT context->'decisions' ? 'financial_conflict' THEN
  action_required:=true;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','financial_conflict','revision',p_revision));
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 IF received>=pi.amount AND refunded<pi.amount AND NOT conflict AND context->'incomplete'='false'::jsonb THEN
  IF o.state IN ('ordered','created') AND payment_time<=deadline THEN
   transition:=public.update_order_and_tickets_to_paid(o.id);
   IF transition->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'PAYMENT_PAID_TRANSITION_FAILED'; END IF;
   changed:=true;
  ELSIF o.state NOT IN ('paid','sent') THEN
   action_required:=true;
   PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
   IF NOT context->'decisions' ? 'late_payment' THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','late_payment','revision',p_revision)); END IF;
  END IF;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||jsonb_build_object('state',CASE WHEN action_required THEN 'action_required' ELSE 'paid' END));
  IF NOT action_required THEN
   PERFORM public.publish_form_measurement_event_internal('order_fully_paid',o.id);
  END IF;
 END IF;
 IF refunded>=pi.amount AND received>0 THEN
  IF NOT context->'decisions' ? 'full_refund' THEN
   cancelled:=public.cancel_online_order_admission_internal(o.id,'storno');
   PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','full_refund','revision',p_revision,'tickets',to_jsonb(coalesce(cancelled,'{}'))));
   changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND (p_expired OR (p_unresolved AND deadline<=clock_timestamp())) AND o.state='ordered' THEN
  cancelled:=public.cancel_online_order_admission_internal(o.id,'expired');
  -- Releasing inventory does not prove financial absence. Keep uncertain recovery alive.
  IF NOT p_unresolved THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"expired"}'); END IF;
  changed:=true;
 END IF;
 projection:=public.provider_order_payment_projection_internal(o.id);
 IF projection->>'admissionState' IS DISTINCT FROM p_before->>'admissionState' AND
  (projection->>'status'='disputed' OR p_before->>'status'='disputed' OR projection->'reconciliationPending'='true'::jsonb OR p_before->'reconciliationPending'='true'::jsonb) THEN
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('revision',p_revision,'reason',
   CASE WHEN projection->>'status'='disputed' THEN 'dispute_hold' WHEN p_before->>'status'='disputed' THEN 'dispute_release'
   WHEN projection->'reconciliationPending'='true'::jsonb THEN 'reconciliation_hold' ELSE 'reconciliation_release' END));
  IF projection->>'admissionState'='valid' THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  changed:=true;
 END IF;

 FOR fact IN SELECT value FROM jsonb_array_elements(public.payment_provider_call_internal(p_provider,'notification_facts',args)) LOOP
  PERFORM public.notification_center_payment_fact_internal(o.id,p_provider,fact->>'identity',(fact->>'amount')::numeric,fact->>'currency',(fact->>'occurredAt')::timestamptz);
 END LOOP;
 PERFORM public.notification_center_payment_problem_internal(o.id,action_required OR conflict,
  CASE WHEN conflict THEN 'financial_conflict' ELSE 'action_required' END);
 PERFORM public.enqueue_order_wallet_internal(o.id);
 RETURN jsonb_build_object('changed',changed,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.apply_provider_payment_effects_internal(text,uuid,text,jsonb,boolean,boolean,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;
