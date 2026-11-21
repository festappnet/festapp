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
