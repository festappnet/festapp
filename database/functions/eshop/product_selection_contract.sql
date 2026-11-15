-- Shared admission/required-product validation for checkout and term moves.
CREATE OR REPLACE FUNCTION public.assert_ticket_required_products_internal(p_form bigint,p_products bigint[])
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE missing_field bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE p.id=ANY(p_products) AND pt.type='spot') AND NOT coalesce((SELECT bool_and(is_hidden IS TRUE)
   FROM public.form_fields WHERE form=p_form AND type='ticket'),false) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',1015,'message','Spot product is missing in ticket fields')::text;
 END IF;
 SELECT ff.id INTO missing_field FROM public.form_fields ff WHERE ff.form=p_form AND ff.type='product_type'
  AND ff.is_ticket_field AND ff.is_required AND NOT ff.is_hidden AND NOT EXISTS(
   SELECT 1 FROM eshop.products p WHERE p.id=ANY(p_products) AND p.product_type=ff.product_type)
 ORDER BY ff.id LIMIT 1;
 IF FOUND THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',missing_field,'message','Required product selection missing')::text;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_ticket_required_products_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;
