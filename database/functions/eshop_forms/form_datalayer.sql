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
