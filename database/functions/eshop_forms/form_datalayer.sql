-- Read only after the existing command's receipt authorization. Live policy is
-- deliberately separate from immutable conversion facts and durable receipts.
CREATE OR REPLACE FUNCTION public.form_conversion_datalayer_internal(p_order bigint,p_kind text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT c.payload FROM analytics.conversion_facts c
 JOIN eshop.orders o ON o.id=c."order"
 CROSS JOIN LATERAL (SELECT public.form_measurement_status_internal(o.form) s) policy
 WHERE c."order"=p_order AND c.kind=p_kind AND s->'requested_enabled'='true'::jsonb AND s->'organization_allowed'='true'::jsonb AND s->'organization_enabled'='true'::jsonb AND s->'unit_enabled'='true'::jsonb AND NOT (s->'blocked_reasons' @> '["no_privacy_policy"]'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.form_conversion_datalayer_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

DROP FUNCTION IF EXISTS public.form_purchase_datalayer_internal(bigint);

-- Called exactly at canonical finalization/registration, never on replay.
-- Products come from the finalizer's charged-price snapshot, not today's catalog.
CREATE OR REPLACE FUNCTION public.record_form_conversion_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE o eshop.orders; s jsonb; items jsonb; total numeric; payload jsonb; identity uuid:=gen_random_uuid(); brand text;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 s:=public.form_measurement_status_internal(o.form);
 IF s->'requested_enabled' IS DISTINCT FROM 'true'::jsonb OR s->'organization_allowed' IS DISTINCT FROM 'true'::jsonb OR s->'organization_enabled' IS DISTINCT FROM 'true'::jsonb OR s->'unit_enabled' IS DISTINCT FROM 'true'::jsonb OR coalesce(s->'blocked_reasons' @> '["no_privacy_policy"]'::jsonb,true) THEN RETURN; END IF;
 IF o.state='waitlisted' OR o.price=0 THEN
  payload:=jsonb_build_object('event','generate_lead','event_id',identity,'currency',coalesce(nullif(trim(o.currency_code),''),'CZK'),
   'value',0,'lead_source',CASE WHEN o.state='waitlisted' THEN 'waitlist' ELSE 'free_registration' END);
 ELSIF o.price>0 AND trim(o.currency_code) ~ '^[A-Z]{3}$' THEN
  SELECT title INTO brand FROM public.occasions WHERE id=o.occasion;
  -- Labels stay out of the grouping: they cannot split a line or change the total.
  SELECT jsonb_agg(jsonb_build_object('item_id','product_'||x.id,'item_name',x.title,'price',x.price,'quantity',x.quantity)||
    jsonb_strip_nulls(jsonb_build_object('item_category',nullif(left(btrim(x.category),100),''),'item_brand',nullif(left(btrim(brand),100),''))) ORDER BY x.id,x.price),
   sum(x.price*x.quantity) INTO items,total
  FROM (SELECT p->>'id' id,p->>'title' title,(p->>'price')::numeric price,count(*) quantity,min(p->>'type_title') category
   FROM jsonb_array_elements(o.data->'tickets') t CROSS JOIN LATERAL jsonb_array_elements(t->'products') p
   GROUP BY p->>'id',p->>'title',(p->>'price')::numeric) x;
  IF jsonb_array_length(items) BETWEEN 1 AND 200 AND total=o.price THEN
   payload:=jsonb_build_object('event','purchase','ecommerce',jsonb_build_object('transaction_id',identity,
    'currency',trim(o.currency_code),'value',o.price,'items',items,'payment_type',
    CASE WHEN (SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info)='stripe' THEN 'card' ELSE 'bank_transfer' END));
  END IF;
 END IF;
 IF payload IS NOT NULL THEN
  INSERT INTO analytics.conversion_facts("order",kind,event_id,payload) VALUES(p_order,coalesce(payload->>'lead_source',payload->>'event'),identity,payload)
   ON CONFLICT("order",kind) DO NOTHING;
 END IF;
-- Measurement failure cannot change checkout. Invalid/incomplete snapshots are
-- intentionally not exported; no second price calculation repairs them.
EXCEPTION WHEN OTHERS THEN RETURN;
END $$;
REVOKE ALL ON FUNCTION public.record_form_conversion_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
