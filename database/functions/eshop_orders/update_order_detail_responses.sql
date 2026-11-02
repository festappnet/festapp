-- Scoped order-form answers retain their existing domain owner.
-- Ticket products and notes use their own existing owners.
DROP FUNCTION IF EXISTS public.update_order_detail_responses(bigint,bigint,bigint,jsonb,jsonb);
CREATE OR REPLACE FUNCTION public.update_order_detail_responses(
 p_order bigint,p_form bigint,p_expected_fields jsonb,p_responses jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; current_fields jsonb; entry record; ff public.form_fields;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL OR o.form IS DISTINCT FROM p_form OR public.can_write_orders(o.occasion) IS NOT TRUE
   OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=o.occasion) THEN
   RETURN jsonb_build_object('code',404,'message','Responses unavailable'); END IF;
 IF p_responses IS NULL OR jsonb_typeof(p_responses)<>'object' OR octet_length(p_responses::text)>65536 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid responses'; END IF;
 -- Use the same form -> order -> ticket lock order as response/grid owners.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR SHARE;
 PERFORM public.check_order_is_mutable(p_order);
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=p_order));
 SELECT * INTO o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF o.id IS NULL OR public.can_write_orders(o.occasion) IS NOT TRUE THEN RETURN jsonb_build_object('code',404); END IF;
 IF o.form IS DISTINCT FROM p_form OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=o.occasion) THEN RETURN jsonb_build_object('code',409); END IF;
 current_fields:=coalesce(o.data->'fields','[]');
 IF current_fields IS DISTINCT FROM coalesce(p_expected_fields,'[]') THEN RETURN jsonb_build_object('code',409); END IF;
 FOR entry IN SELECT * FROM jsonb_each(p_responses) LOOP
   SELECT * INTO ff FROM public.form_fields WHERE form=p_form AND id::text=entry.key
     AND coalesce(is_ticket_field,false)=false;
   IF ff.id IS NULL OR ff.type IS NULL OR ff.type IN('sex','birth_year','birth_date','id_document','select_many','note','spot','product_type','ticket','email')
     OR (entry.value<>'null'::jsonb AND jsonb_typeof(entry.value)<>'string') THEN
     RAISE invalid_parameter_value USING MESSAGE='response field not editable'; END IF;
   IF ff.type='select_one' AND entry.value NOT IN('null'::jsonb,'""'::jsonb)
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(ff.data->'options','[]')) opt WHERE opt->'value'=entry.value) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid response option'; END IF;
 END LOOP;
 IF p_responses='{}' THEN RETURN jsonb_build_object('code',200); END IF;
 PERFORM public.update_order_responses(p_order,p_responses);
 RETURN jsonb_build_object('code',200);
END $$;
REVOKE ALL ON FUNCTION public.update_order_detail_responses(bigint,bigint,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_order_detail_responses(bigint,bigint,jsonb,jsonb) TO authenticated;
