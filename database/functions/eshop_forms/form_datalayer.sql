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
