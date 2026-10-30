-- Structural primary product protection shared by authoring and catalog writes.
CREATE OR REPLACE FUNCTION public.primary_product_delete_blocked_internal(p_product bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE p.id=p_product AND pt.type='spot'
   AND EXISTS(SELECT 1 FROM public.form_fields f WHERE f.product_type=pt.id)
   AND NOT EXISTS(SELECT 1 FROM eshop.products sibling
     WHERE sibling.product_type=pt.id AND sibling.id<>p.id AND NOT sibling.is_hidden));
$$;
REVOKE ALL ON FUNCTION public.primary_product_delete_blocked_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.lock_primary_product_forms_internal(p_product bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM 1 FROM public.forms f WHERE f.id IN(
   SELECT ff.form FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
   JOIN eshop.products p ON p.product_type=pt.id WHERE p.id=p_product AND pt.type='spot')
 ORDER BY f.id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_primary_product_forms_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assert_form_primary_products_internal(p_form bigint,p_preserve bigint[] DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM unnest(p_preserve) required(id) WHERE NOT EXISTS(
   SELECT 1 FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
   WHERE ff.form=p_form AND pt.id=required.id AND pt.type='spot' AND ff.type='product_type' AND NOT ff.is_hidden))
 OR EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
   WHERE ff.form=p_form AND pt.type='spot' AND (ff.is_hidden OR NOT EXISTS(
     SELECT 1 FROM eshop.products p WHERE p.product_type=pt.id AND NOT p.is_hidden)))
 OR (EXISTS(SELECT 1 FROM public.form_fields WHERE form=p_form AND type='ticket')
   AND EXISTS(SELECT 1 FROM public.form_fields WHERE form=p_form AND type='product_type' AND NOT is_hidden)
   AND NOT EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
     WHERE ff.form=p_form AND pt.type='spot' AND NOT ff.is_hidden)) THEN
   RAISE EXCEPTION 'FORM_DELETE_primary_product';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_form_primary_products_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;
