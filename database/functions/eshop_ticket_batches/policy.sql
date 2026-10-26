INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('batch-document.actor.burst','batch-document','actor','rolling',600,60,300,1000),
 ('batch-document.unit.burst','batch-document','unit','rolling',600,60,1000,5000)
 ON CONFLICT(rule_key) DO NOTHING;
CREATE OR REPLACE FUNCTION public.admit_ticket_batch_document_internal(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o public.occasions;
BEGIN
 SELECT * INTO STRICT o FROM public.occasions WHERE id=p_occasion;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('batch-document',o.unit,o.organization),
  jsonb_build_object('actor',auth.uid(),'unit',o.unit,'organization',o.organization));
END $$;
REVOKE ALL ON FUNCTION public.admit_ticket_batch_document_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,base_limit,hard_cap)
 VALUES('batch-create.items','batch-create','unit','items',200,200) ON CONFLICT(rule_key) DO NOTHING;
CREATE OR REPLACE FUNCTION public.check_ticket_batch_cash_unit_internal(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_occasion_writable(p_occasion);
 IF EXISTS(SELECT 1 FROM eshop.external_services s JOIN public.occasions o ON o.unit=s.unit WHERE o.id=p_occasion AND s.type='FAKTUROID') THEN
  RAISE EXCEPTION 'CASH_SALE_INVOICE_WORKFLOW_REQUIRED'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_ticket_batch_cash_unit_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.check_ticket_batch_eligible_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; o public.occasions; feature jsonb; template jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=f.occasion;
 PERFORM public.check_ticket_batch_cash_unit_internal(o.id);
 -- Personal registration products and automatic participant imports are outside v1.
 IF EXISTS(SELECT 1 FROM public.form_fields WHERE form=f.id AND is_ticket_field AND is_required
   AND NOT is_hidden AND type NOT IN ('product_type','spot','ticket','html')) THEN
  RAISE EXCEPTION 'BATCH_PERSONAL_REGISTRATION_UNSUPPORTED'; END IF;
 SELECT value INTO feature FROM jsonb_array_elements(o.features) WHERE value->>'code'='ticket';
 IF feature IS NULL OR coalesce((feature->>'is_enabled')::boolean,false) IS NOT TRUE THEN
  RAISE EXCEPTION 'BATCH_TICKET_FEATURE_REQUIRED'; END IF;
 PERFORM public.validate_ticket_layout(feature->'layout');
 PERFORM public.validate_ticket_layout_references(o.id,feature->'layout');
 -- Explicit saved templates make anonymity and the frozen render contract reviewable.
 template:=feature#>ARRAY['layout','templates',CASE WHEN feature->>'ticket_type'='named' THEN 'named' ELSE 'wide' END];
 IF template IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements(template->'elements') e
 WHERE e->>'binding'='orderName' AND (e->>'visible')::boolean) THEN
  RAISE EXCEPTION 'BATCH_ANONYMOUS_TEMPLATE_REQUIRED'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.normalize_ticket_batch_selection_internal(p_form bigint,p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_selection) IS DISTINCT FROM 'array' OR jsonb_array_length(p_selection) NOT BETWEEN 1 AND 200
 OR octet_length(p_selection::text)>1048576 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_selection) t
 WHERE jsonb_typeof(t)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(t) k WHERE k NOT IN ('spot','fields'))) THEN
  RAISE invalid_parameter_value USING MESSAGE='BATCH_SELECTION_INVALID'; END IF;
 result:=public.normalize_form_ticket_answers_internal(p_form,p_selection);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result) t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'fields','[]')) f
  WHERE NOT f ? 'product_type' OR EXISTS(SELECT 1 FROM jsonb_object_keys(f) k
    WHERE k NOT IN ('product_type','_subFieldId','currency_code') AND k !~ '^[0-9]+$')) THEN
  RAISE invalid_parameter_value USING MESSAGE='BATCH_SELECTION_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result) t JOIN eshop.spots s ON s.id=(t->>'spot')::bigint
  JOIN public.forms f ON f.id=p_form WHERE s.blueprint IS DISTINCT FROM f.blueprint OR s.occasion IS DISTINCT FROM f.occasion) THEN
  RAISE EXCEPTION 'BATCH_SPOT_SCOPE_MISMATCH'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.check_ticket_batch_eligible_internal(bigint),
 public.normalize_ticket_batch_selection_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
-- Read preview and write command share the same normalized, server-priced selection.
CREATE OR REPLACE FUNCTION public.ticket_batch_selection_summary_internal(p_form bigint,p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE fid bigint; oc bigint; invalid boolean; currency text; total numeric; item record; capacity jsonb;
BEGIN
 SELECT occasion INTO STRICT oc FROM public.forms WHERE id=p_form;
 IF (SELECT count(*) FROM jsonb_array_elements(p_selection) t WHERE t->>'spot' IS NOT NULL)<>
  (SELECT count(DISTINCT t->>'spot') FROM jsonb_array_elements(p_selection) t WHERE t->>'spot' IS NOT NULL) THEN
  RAISE EXCEPTION 'BATCH_DUPLICATE_SPOT'; END IF;
 FOR item IN
  WITH choices AS (
   SELECT n,(a->>'product_type')::bigint product,false seated FROM jsonb_array_elements(p_selection) WITH ORDINALITY t(v,n)
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(v->'fields','[]')) a
   UNION ALL SELECT n,s.product,true FROM jsonb_array_elements(p_selection) WITH ORDINALITY t(v,n)
    LEFT JOIN eshop.spots s ON s.id=(v->>'spot')::bigint WHERE v->>'spot' IS NOT NULL)
  SELECT c.*,p.price,p.currency_code,p.maximum,p.is_hidden,p.occasion,pt.type,pt.occasion type_occasion,p.product_type,
   EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.form=p_form AND ff.product_type=p.product_type AND NOT ff.is_hidden) offered,
   (SELECT count(*) FROM eshop.order_product_ticket x WHERE x.product=p.id) occupied,
   count(*) OVER(PARTITION BY c.product) selected
  FROM choices c LEFT JOIN eshop.products p ON p.id=c.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
 LOOP
  IF item.occasion IS DISTINCT FROM oc OR item.type_occasion IS DISTINCT FROM oc OR item.is_hidden
   OR item.price IS NULL OR item.price<0 OR (NOT item.seated AND NOT item.offered) THEN RAISE EXCEPTION 'BATCH_PRODUCT_UNAVAILABLE'; END IF;
  IF item.maximum>0 AND item.occupied+item.selected>item.maximum THEN RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;
  IF currency IS NULL THEN currency:=item.currency_code;
  ELSIF currency IS DISTINCT FROM item.currency_code THEN RAISE EXCEPTION 'BATCH_CURRENCY_MISMATCH'; END IF;
  total:=coalesce(total,0)+item.price;
 END LOOP;
 IF total IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_selection) t WHERE t->>'spot' IS NULL AND NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(coalesce(t->'fields','[]')) a JOIN eshop.products p ON p.id=(a->>'product_type')::bigint
  JOIN eshop.product_types pt ON pt.id=p.product_type WHERE pt.type='spot')) THEN RAISE EXCEPTION 'BATCH_ADMISSION_PRODUCT_REQUIRED'; END IF;
 capacity:=public.get_form_capacity_snapshot_internal(p_form);
 IF (capacity->>'enabled')::boolean AND jsonb_array_length(p_selection)>(capacity->>'remainingPublic')::bigint THEN RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
 RETURN jsonb_build_object('count',jsonb_array_length(p_selection),'prices',jsonb_build_array(jsonb_build_object('currency_code',currency,'amount',total)),'capacity',capacity);
END $$;
REVOKE ALL ON FUNCTION public.ticket_batch_selection_summary_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
